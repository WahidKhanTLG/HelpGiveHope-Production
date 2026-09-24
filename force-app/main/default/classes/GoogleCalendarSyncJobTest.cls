@IsTest
private class GoogleCalendarSyncJobTest {

    private static final String TRACT = '85.01';

    @TestSetup
    static void setup() {
        Zone__c zone = InterviewSchedulingTestData.createZone('Sync Zone', TRACT, 'Morning');
        InterviewSchedulingTestData.createInterviewDay(zone, Date.today().addDays(12), 'Morning', 4, 'Published');
        Account household = InterviewSchedulingTestData.createHousehold('Sync Household', TRACT);
        Contact contact = InterviewSchedulingTestData.createContact(household, 'Sam', 'sam@example.org');
        InterviewSchedulingTestData.createApplication(household, contact);
    }

    private static Interview_Day__c day() {
        return [SELECT Id FROM Interview_Day__c LIMIT 1];
    }

    private static void runJob(InterviewSchedulingTestData.GoogleMock mock) {
        GoogleCalendarSyncJob.allowInTests = true;
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        System.enqueueJob(new GoogleCalendarSyncJob());
        Test.stopTest();
    }

    @IsTest
    static void newSlotsAreMarkedPendingWhenPlaceholdersAreEnabled() {
        InterviewSchedulingTestData.googleSettings(true);
        Zone__c zone = [SELECT Id FROM Zone__c LIMIT 1];

        Interview_Day__c day = InterviewSchedulingTestData.createInterviewDay(zone, Date.today().addDays(20), 'Morning', 3, 'Published');

        for (Interview_Day_Schedule__c slot : InterviewSchedulingTestData.slotsFor(day.Id)) {
            System.assertEquals('Pending', slot.Google_Sync_Status__c, 'Every new slot is queued as a placeholder');
        }
    }

    @IsTest
    static void newUnbookedSlotsAreNotQueuedWhenPlaceholdersAreDisabled() {
        InterviewSchedulingTestData.googleSettings(false);
        Zone__c zone = [SELECT Id FROM Zone__c LIMIT 1];

        Interview_Day__c day = InterviewSchedulingTestData.createInterviewDay(zone, Date.today().addDays(21), 'Morning', 2, 'Published');

        for (Interview_Day_Schedule__c slot : InterviewSchedulingTestData.slotsFor(day.Id)) {
            System.assertNotEquals('Pending', slot.Google_Sync_Status__c, 'Unbooked slots are not mirrored in booked-only mode');
        }
    }

    @IsTest
    static void jobCreatesAvailableEventsForPlaceholders() {
        InterviewSchedulingTestData.googleSettings(true);
        // Slots from setup were created before the override existed; queue them explicitly.
        List<Interview_Day_Schedule__c> pending = new List<Interview_Day_Schedule__c>();
        for (Interview_Day_Schedule__c slot : InterviewSchedulingTestData.slotsFor(day().Id)) {
            pending.add(new Interview_Day_Schedule__c(Id = slot.Id, Google_Sync_Status__c = 'Pending'));
        }
        update pending;
        InterviewSchedulingTestData.GoogleMock mock = new InterviewSchedulingTestData.GoogleMock();

        runJob(mock);

        List<Interview_Day_Schedule__c> slots = InterviewSchedulingTestData.slotsFor(day().Id);
        System.assertEquals(4, slots.size());
        Set<String> eventIds = new Set<String>();
        for (Interview_Day_Schedule__c slot : slots) {
            System.assertEquals('Synced', slot.Google_Sync_Status__c, '' + slot.Google_Sync_Error__c);
            System.assertEquals('test-calendar@group.calendar.google.com', slot.Google_Calendar_Id__c);
            System.assert(String.isNotBlank(slot.Google_Event_Id__c));
            eventIds.add(slot.Google_Event_Id__c);
        }
        System.assertEquals(4, eventIds.size(), 'One distinct event per slot');
        System.assertEquals(4, mock.created, 'Four POSTs');

        // Each create was preceded by an idempotency lookup.
        Integer lookups = 0;
        for (HttpRequest request : mock.requests) {
            if (request.getMethod() == 'GET') {
                lookups++;
                System.assert(request.getEndpoint().contains('privateExtendedProperty=salesforceScheduleId%3D'), request.getEndpoint());
            }
        }
        System.assertEquals(4, lookups);
        System.assertEquals(0, GoogleCalendarService.countPendingWork());
    }

    @IsTest
    static void lookupHitPreventsDuplicateEvents() {
        InterviewSchedulingTestData.googleSettings(true);
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day().Id)[0];
        update new Interview_Day_Schedule__c(Id = slot.Id, Google_Sync_Status__c = 'Pending');
        InterviewSchedulingTestData.GoogleMock mock = new InterviewSchedulingTestData.GoogleMock();
        mock.existingEventId = 'already-there';

        runJob(mock);

        Interview_Day_Schedule__c synced = InterviewSchedulingTestData.slot(slot.Id);
        System.assertEquals('Synced', synced.Google_Sync_Status__c);
        System.assertEquals('already-there', synced.Google_Event_Id__c, 'Existing event is patched, not duplicated');
        System.assertEquals(0, mock.created);
    }

    @IsTest
    static void bookedPayloadInvitesApplicantAndVolunteer() {
        GoogleCalendarSettings settings = InterviewSchedulingTestData.googleSettings(true);
        User volunteer = InterviewSchedulingTestData.createVolunteer();
        Case app = [SELECT Id, CaseNumber FROM Case LIMIT 1];
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day().Id)[0];
        InterviewBookingService.book(slot.Id, app.Id, volunteer.Id, InterviewBookingService.Actor.STAFF);
        Interview_Day_Schedule__c loaded = GoogleCalendarService.queryForSync(new Set<Id>{ slot.Id }, 1)[0];

        List<String> warnings = new List<String>();
        Map<String, Object> payload = GoogleCalendarService.buildBookedPayload(loaded, settings, warnings);

        System.assertEquals('HGH Home Interview - ' + app.CaseNumber, payload.get('summary'));
        System.assertEquals('opaque', payload.get('transparency'));
        System.assertEquals('11', payload.get('colorId'));
        System.assertEquals(false, payload.get('guestsCanModify'));
        System.assertEquals(false, payload.get('guestsCanInviteOthers'));
        System.assertEquals(false, payload.get('guestsCanSeeOtherGuests'));
        System.assertEquals('', payload.get('location'), 'Address is excluded unless configured');

        List<Object> attendees = (List<Object>) payload.get('attendees');
        System.assertEquals(2, attendees.size(), warnings.toString());
        Set<String> emails = new Set<String>();
        for (Object attendee : attendees) {
            emails.add((String) ((Map<String, Object>) attendee).get('email'));
        }
        System.assert(emails.contains('sam@example.org'), 'Applicant invited');
        System.assert(emails.contains(volunteer.Email), 'Volunteer invited');
        System.assertEquals(0, warnings.size());

        Map<String, Object> start = (Map<String, Object>) payload.get('start');
        System.assertEquals(Date.today().addDays(12).year() + '-' + String.valueOf(Date.today().addDays(12)).substring(5) + 'T08:00:00', start.get('dateTime'));
        System.assertEquals('America/Chicago', start.get('timeZone'));
        Map<String, Object> ext = (Map<String, Object>) ((Map<String, Object>) payload.get('extendedProperties')).get('private');
        System.assertEquals(String.valueOf(slot.Id), ext.get('salesforceScheduleId'));
    }

    @IsTest
    static void availablePayloadHasNoAttendeesAndIsTransparent() {
        GoogleCalendarSettings settings = InterviewSchedulingTestData.googleSettings(true);
        Interview_Day_Schedule__c loaded = GoogleCalendarService.queryForSync(new Set<Id>{ InterviewSchedulingTestData.slotsFor(day().Id)[1].Id }, 1)[0];

        Map<String, Object> payload = GoogleCalendarService.buildAvailablePayload(loaded, settings);

        System.assertEquals('Available - Sync Zone Morning - Slot 2', payload.get('summary'));
        System.assertEquals('transparent', payload.get('transparency'));
        System.assertEquals('2', payload.get('colorId'));
        System.assertEquals(0, ((List<Object>) payload.get('attendees')).size());
    }

    @IsTest
    static void missingApplicantEmailProducesWarningNotFailure() {
        GoogleCalendarSettings settings = InterviewSchedulingTestData.googleSettings(true);
        Case app = [SELECT Id, ContactId FROM Case LIMIT 1];
        update new Contact(Id = app.ContactId, Email = null);
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day().Id)[0];
        InterviewBookingService.book(slot.Id, app.Id, null, InterviewBookingService.Actor.STAFF);
        InterviewSchedulingTestData.GoogleMock mock = new InterviewSchedulingTestData.GoogleMock();

        runJob(mock);

        Interview_Day_Schedule__c synced = InterviewSchedulingTestData.slot(slot.Id);
        System.assertEquals('Synced', synced.Google_Sync_Status__c);
        System.assert(synced.Google_Sync_Error__c != null && synced.Google_Sync_Error__c.startsWith('Warning:'), '' + synced.Google_Sync_Error__c);
    }

    @IsTest
    static void deletePendingRemovesEventAndClearsId() {
        InterviewSchedulingTestData.googleSettings(true);
        List<Interview_Day_Schedule__c> slots = InterviewSchedulingTestData.slotsFor(day().Id);
        List<Interview_Day_Schedule__c> quiet = new List<Interview_Day_Schedule__c>();
        for (Integer i = 1; i < slots.size(); i++) {
            quiet.add(new Interview_Day_Schedule__c(Id = slots[i].Id, Google_Sync_Status__c = 'Not Required'));
        }
        update quiet;   // only the slot under test is pending
        Interview_Day_Schedule__c slot = slots[0];
        update new Interview_Day_Schedule__c(Id = slot.Id, Google_Event_Id__c = 'evt-old', Google_Sync_Status__c = 'Delete Pending');
        InterviewSchedulingTestData.GoogleMock mock = new InterviewSchedulingTestData.GoogleMock();

        runJob(mock);

        Interview_Day_Schedule__c deleted = InterviewSchedulingTestData.slot(slot.Id);
        System.assertEquals('Deleted', deleted.Google_Sync_Status__c);
        System.assertEquals(null, deleted.Google_Event_Id__c);
        Boolean deleteSeen = false;
        for (HttpRequest request : mock.requests) {
            if (request.getMethod() == 'DELETE' && request.getEndpoint().contains('/events/evt-old')) {
                deleteSeen = true;
            }
        }
        System.assert(deleteSeen, 'The pending deletion reached Google');
    }

    @IsTest
    static void unbookedSlotIsDeletedWhenPlaceholdersAreDisabled() {
        InterviewSchedulingTestData.googleSettings(false);
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day().Id)[0];
        update new Interview_Day_Schedule__c(Id = slot.Id, Google_Event_Id__c = 'evt-placeholder', Google_Sync_Status__c = 'Pending');
        InterviewSchedulingTestData.GoogleMock mock = new InterviewSchedulingTestData.GoogleMock();

        runJob(mock);

        System.assertEquals('Deleted', InterviewSchedulingTestData.slot(slot.Id).Google_Sync_Status__c);
        Interview_Day_Schedule__c other = InterviewSchedulingTestData.slotsFor(day().Id)[1];
        update new Interview_Day_Schedule__c(Id = other.Id, Google_Sync_Status__c = 'Pending');
        GoogleCalendarService.SyncOutcome outcome = GoogleCalendarService.syncSchedule(
            GoogleCalendarService.queryForSync(new Set<Id>{ other.Id }, 1)[0], GoogleCalendarSettings.load());
        System.assertEquals('Not Required', outcome.updateRecord.Google_Sync_Status__c, 'No event and none wanted');
        System.assertEquals(0, outcome.calloutsUsed);
    }

    @IsTest
    static void deletingAMirroredSlotRemovesItsGoogleEvent() {
        InterviewSchedulingTestData.googleSettings(true);
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day().Id)[3];
        update new Interview_Day_Schedule__c(Id = slot.Id, Google_Event_Id__c = 'evt-gone', Google_Calendar_Id__c = 'cal-x', Google_Sync_Status__c = 'Synced');
        InterviewSchedulingTestData.GoogleMock mock = new InterviewSchedulingTestData.GoogleMock();
        GoogleCalendarEventDeleteJob.allowInTests = true;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        delete new Interview_Day_Schedule__c(Id = slot.Id);
        Test.stopTest();

        Boolean deleteSeen = false;
        for (HttpRequest request : mock.requests) {
            if (request.getMethod() == 'DELETE' && request.getEndpoint().contains('/calendars/cal-x/events/evt-gone')) {
                deleteSeen = true;
            }
        }
        System.assert(deleteSeen, 'Deleting a mirrored slot deletes the exact event on the recorded calendar');
        System.assertEquals(3, InterviewSchedulingTestData.slotsFor(day().Id).size());
    }

    @IsTest
    static void deleteJobRequeuesRemainingTargetsOnRateLimit() {
        InterviewSchedulingTestData.googleSettings(true);
        InterviewSchedulingTestData.GoogleMock mock = new InterviewSchedulingTestData.GoogleMock();
        mock.mode = 'rateLimit';
        Test.setMock(HttpCalloutMock.class, mock);
        List<GoogleCalendarEventDeleteJob.Target> targets = new List<GoogleCalendarEventDeleteJob.Target>{
            new GoogleCalendarEventDeleteJob.Target(null, 'evt-a', 'Slot 1'),
            new GoogleCalendarEventDeleteJob.Target(null, 'evt-b', 'Slot 2')
        };

        Test.startTest();
        new GoogleCalendarEventDeleteJob(targets).execute(null);
        Test.stopTest();

        System.assertEquals(1, mock.requests.size(), 'Stops at the first rate-limit response; the rest is re-queued outside tests');
        System.assertEquals(null, GoogleCalendarEventDeleteJob.enqueue(new List<GoogleCalendarEventDeleteJob.Target>()), 'Nothing to do -> not enqueued');
    }

    @IsTest
    static void rateLimitLeavesRecordsPendingForTheSweep() {
        InterviewSchedulingTestData.googleSettings(true);
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day().Id)[0];
        update new Interview_Day_Schedule__c(Id = slot.Id, Google_Sync_Status__c = 'Pending');
        InterviewSchedulingTestData.GoogleMock mock = new InterviewSchedulingTestData.GoogleMock();
        mock.mode = 'rateLimit';

        runJob(mock);

        System.assertEquals('Pending', InterviewSchedulingTestData.slot(slot.Id).Google_Sync_Status__c, 'Transient failures do not mark rows as Error');
        System.assertEquals(1, mock.requests.size(), 'Job stops at the first rate-limit response');
    }

    @IsTest
    static void calloutTimeoutLeavesRecordPendingForRetry() {
        InterviewSchedulingTestData.googleSettings(true);
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day().Id)[0];
        update new Interview_Day_Schedule__c(Id = slot.Id, Google_Sync_Status__c = 'Pending');
        InterviewSchedulingTestData.GoogleMock mock = new InterviewSchedulingTestData.GoogleMock();
        mock.mode = 'timeout';

        runJob(mock);

        System.assertEquals('Pending', InterviewSchedulingTestData.slot(slot.Id).Google_Sync_Status__c, 'Timeouts are retried by the sweep, not flagged Error');
        System.assertEquals(true, GoogleCalendarService.isTimeoutException(new CalloutException('Exceeded maximum time allotted for callout (120000 ms)')));
        System.assertEquals(false, GoogleCalendarService.isTimeoutException(new CalloutException('Unauthorized endpoint')));
    }

    @IsTest
    static void googleErrorIsStoredOnTheRecord() {
        InterviewSchedulingTestData.googleSettings(true);
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day().Id)[0];
        update new Interview_Day_Schedule__c(Id = slot.Id, Google_Sync_Status__c = 'Pending');
        InterviewSchedulingTestData.GoogleMock mock = new InterviewSchedulingTestData.GoogleMock();
        mock.mode = 'badRequest';

        runJob(mock);

        Interview_Day_Schedule__c failed = InterviewSchedulingTestData.slot(slot.Id);
        System.assertEquals('Error', failed.Google_Sync_Status__c);
        System.assert(failed.Google_Sync_Error__c.contains('HTTP 400') && failed.Google_Sync_Error__c.contains('Invalid attendee email'), '' + failed.Google_Sync_Error__c);
    }

    @IsTest
    static void patchOnRemovedEventRecreatesIt() {
        InterviewSchedulingTestData.googleSettings(true);
        List<Interview_Day_Schedule__c> slots = InterviewSchedulingTestData.slotsFor(day().Id);
        List<Interview_Day_Schedule__c> quiet = new List<Interview_Day_Schedule__c>();
        for (Integer i = 1; i < slots.size(); i++) {
            quiet.add(new Interview_Day_Schedule__c(Id = slots[i].Id, Google_Sync_Status__c = 'Not Required'));
        }
        update quiet;   // only the slot under test is pending
        Interview_Day_Schedule__c slot = slots[0];
        update new Interview_Day_Schedule__c(Id = slot.Id, Google_Event_Id__c = 'evt-removed', Google_Sync_Status__c = 'Pending');
        InterviewSchedulingTestData.GoogleMock mock = new InterviewSchedulingTestData.GoogleMock();
        mock.mode = 'patchGone';

        runJob(mock);

        Interview_Day_Schedule__c synced = InterviewSchedulingTestData.slot(slot.Id);
        System.assertEquals('Synced', synced.Google_Sync_Status__c, '' + synced.Google_Sync_Error__c);
        System.assertNotEquals('evt-removed', synced.Google_Event_Id__c, 'A 404 on PATCH falls back to POST and stores the new id');
        System.assert(String.isNotBlank(synced.Google_Event_Id__c) && synced.Google_Event_Id__c.startsWith('evt-'), '' + synced.Google_Event_Id__c);
        System.assertEquals(1, mock.created, 'Exactly one new event was created');
    }

    @IsTest
    static void legacyUpsertAndFlowInvocableStillWork() {
        InterviewSchedulingTestData.googleSettings(true);
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day().Id)[0];
        Test.setMock(HttpCalloutMock.class, new InterviewSchedulingTestData.GoogleMock());

        Test.startTest();
        GoogleCalendarService.upsertEvent(slot.Id);
        Test.stopTest();

        Interview_Day_Schedule__c synced = InterviewSchedulingTestData.slot(slot.Id);
        System.assertEquals('Synced', synced.Google_Sync_Status__c, '' + synced.Google_Sync_Error__c);
        System.assertEquals('evt-1', synced.Google_Event_Id__c);

        GoogleCalendarSyncQueueable.SyncRequest request = new GoogleCalendarSyncQueueable.SyncRequest();
        request.scheduleId = slot.Id;
        request.operation = 'DELETE';
        GoogleCalendarSyncQueueable.enqueueFromFlow(new List<GoogleCalendarSyncQueueable.SyncRequest>{ request });
        System.assertEquals('Delete Pending', InterviewSchedulingTestData.slot(slot.Id).Google_Sync_Status__c, 'Flow invocable only marks the row');
    }

    @IsTest
    static void legacyDeleteEventRemovesTheEvent() {
        InterviewSchedulingTestData.googleSettings(true);
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day().Id)[0];
        update new Interview_Day_Schedule__c(Id = slot.Id, Google_Event_Id__c = 'evt-legacy', Google_Sync_Status__c = 'Synced');
        InterviewSchedulingTestData.GoogleMock mock = new InterviewSchedulingTestData.GoogleMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GoogleCalendarService.deleteEvent(slot.Id);
        Test.stopTest();

        Interview_Day_Schedule__c deleted = InterviewSchedulingTestData.slot(slot.Id);
        System.assertEquals('Deleted', deleted.Google_Sync_Status__c, '' + deleted.Google_Sync_Error__c);
        System.assertEquals(null, deleted.Google_Event_Id__c);
        System.assertEquals('DELETE', mock.requests[0].getMethod());
    }

    @IsTest
    static void enqueueIsDeduplicatedPerTransactionAndSkippedWhenDisabled() {
        InterviewSchedulingTestData.googleSettings(true);
        GoogleCalendarSyncJob.allowInTests = true;
        Test.setMock(HttpCalloutMock.class, new InterviewSchedulingTestData.GoogleMock());

        Test.startTest();
        Id first = GoogleCalendarSyncJob.enqueue();
        Id second = GoogleCalendarSyncJob.enqueue();
        Test.stopTest();

        System.assertNotEquals(null, first);
        System.assertEquals(null, second, 'Second call in the same transaction is a no-op');

        GoogleCalendarSyncJob.enqueuedInThisTransaction = false;
        GoogleCalendarSettings.instanceOverride.enabled = false;
        System.assertEquals(null, GoogleCalendarSyncJob.enqueue(), 'Disabled integration never enqueues');
    }

    @IsTest
    static void sweepCanBeStartedAndStopped() {
        InterviewSchedulingTestData.googleSettings(true);

        Test.startTest();
        Id cronId = GoogleCalendarSyncScheduler.start();
        System.assertNotEquals(null, cronId);
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE Id = :cronId]);
        new GoogleCalendarSyncScheduler().execute(null);
        GoogleCalendarSyncScheduler.sweep();
        GoogleCalendarSyncScheduler.abortQuietly(null);
        GoogleCalendarSyncScheduler.abortQuietly(cronId);
        Id nextId = GoogleCalendarSyncScheduler.scheduleNextSafely();
        System.assertNotEquals(null, nextId, 'Self-rescheduling creates the next one-off run');
        GoogleCalendarSyncScheduler.stop();
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM CronTrigger WHERE Id IN (:cronId, :nextId) AND State != 'DELETED']);
    }

    @IsTest
    static void transientDetectionAndErrorExtraction() {
        HttpResponse rate = new HttpResponse();
        rate.setStatusCode(403);
        rate.setBody('{"error":{"message":"User Rate Limit Exceeded","errors":[{"reason":"userRateLimitExceeded"}]}}');
        HttpResponse forbidden = new HttpResponse();
        forbidden.setStatusCode(403);
        forbidden.setBody('{"error":{"message":"Insufficient Permission"}}');
        HttpResponse unavailable = new HttpResponse();
        unavailable.setStatusCode(503);

        HttpResponse unauthenticated = new HttpResponse();
        unauthenticated.setStatusCode(401);
        unauthenticated.setBody('{"error":{"code":401,"message":"Request had invalid authentication credentials."}}');
        System.assertEquals(true, GoogleCalendarService.isTransient(unauthenticated), 'Expired principal token: retry after re-authentication');
        System.assertEquals(true, GoogleCalendarService.isTransient(rate));
        System.assertEquals(false, GoogleCalendarService.isTransient(forbidden));
        System.assertEquals(true, GoogleCalendarService.isTransient(unavailable));
        System.assertEquals('HTTP 403: Insufficient Permission', GoogleCalendarService.extractGoogleError(forbidden));
        System.assertEquals(true, GoogleCalendarService.isValidEmail('a.b@example.org'));
        System.assertEquals(false, GoogleCalendarService.isValidEmail('not an email'));
        System.assertEquals('8:00 AM', GoogleCalendarService.timeLabel(Time.newInstance(8, 0, 0, 0)));
        System.assertEquals('12:30 PM', GoogleCalendarService.timeLabel(Time.newInstance(12, 30, 0, 0)));
        System.assertEquals('4:15 PM', GoogleCalendarService.timeLabel(Time.newInstance(16, 15, 0, 0)));
        System.assertEquals('Afternoon', GoogleCalendarService.modeLabel('AfterNoon'));
    }
}