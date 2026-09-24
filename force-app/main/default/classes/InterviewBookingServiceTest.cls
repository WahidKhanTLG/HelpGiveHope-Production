@IsTest
private class InterviewBookingServiceTest {

    private static final String TRACT = '81.01';

    @TestSetup
    static void setup() {
        Zone__c zone = InterviewSchedulingTestData.createZone('Booking Zone', TRACT, 'Morning');
        Zone__c otherZone = InterviewSchedulingTestData.createZone('Other Zone', '82.01', 'Morning');
        InterviewSchedulingTestData.createInterviewDay(zone, Date.today().addDays(7), 'Morning', 4, 'Published');
        InterviewSchedulingTestData.createInterviewDay(zone, Date.today().addDays(8), 'Morning', 2, 'Planned');
        InterviewSchedulingTestData.createInterviewDay(zone, Date.today(), 'Morning', 2, 'Published');
        InterviewSchedulingTestData.createInterviewDay(otherZone, Date.today().addDays(7), 'Morning', 2, 'Published');

        Account household = InterviewSchedulingTestData.createHousehold('Booking Household', TRACT);
        Contact contact = InterviewSchedulingTestData.createContact(household, 'Ada', 'ada@example.org');
        InterviewSchedulingTestData.createApplication(household, contact);
    }

    private static void config() {
        InterviewSchedulingTestData.googleSettings(true);
        InterviewSchedulingTestData.selfServiceConfig(24, 3);
    }

    private static Interview_Day__c day(String status, Integer daysAhead, String zoneName) {
        return [
            SELECT Id, Interview_Date__c
            FROM Interview_Day__c
            WHERE Status__c = :status AND Interview_Date__c = :Date.today().addDays(daysAhead) AND Zone__r.Name = :zoneName
            LIMIT 1
        ];
    }

    private static Case application() {
        return [SELECT Id, AccountId, OwnerId FROM Case LIMIT 1];
    }

    @IsTest
    static void triggerCreatesRequestedSlotCountWithFifteenMinuteTimes() {
        List<Interview_Day_Schedule__c> slots = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Booking Zone').Id);

        System.assertEquals(4, slots.size(), 'Total_Slots__c = 4 must create exactly four slots');
        System.assertEquals(Time.newInstance(8, 0, 0, 0), slots[0].Start_Time__c, 'Morning slots start at 08:00');
        System.assertEquals(Time.newInstance(8, 15, 0, 0), slots[0].End_Time__c);
        System.assertEquals(Time.newInstance(8, 45, 0, 0), slots[3].Start_Time__c, 'Fourth slot starts at 08:45');
        System.assertEquals(Time.newInstance(9, 0, 0, 0), slots[3].End_Time__c);
    }

    @IsTest
    static void staffBookingSetsSlotAccountAndVolunteer() {
        config();
        User volunteer = InterviewSchedulingTestData.createVolunteer();
        Case app = application();
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Booking Zone').Id)[0];

        Test.startTest();
        InterviewBookingService.BookingResult result = InterviewBookingService.book(
            slot.Id, app.Id, volunteer.Id, InterviewBookingService.Actor.STAFF
        );
        Test.stopTest();

        Interview_Day_Schedule__c booked = InterviewSchedulingTestData.slot(slot.Id);
        System.assertEquals(slot.Id, result.scheduleId);
        System.assertEquals(true, booked.Booked__c);
        System.assertEquals('Booked', booked.Status__c);
        System.assertEquals(app.Id, booked.Case__c);
        System.assertEquals(volunteer.Id, booked.Assigned_Volunteer__c);
        System.assertEquals('Pending', booked.Google_Sync_Status__c, 'Booking must queue Google sync');
        System.assertEquals('Assigned', booked.Assignment_Status__c, 'Assignment flow must run');

        Account household = [SELECT Interview_Day_Schedule__c, Zones__c FROM Account WHERE Id = :app.AccountId];
        System.assertEquals(slot.Id, household.Interview_Day_Schedule__c);
        System.assertNotEquals(null, household.Zones__c, 'Zone lookup must be populated from the slot');

        Case owned = [SELECT OwnerId FROM Case WHERE Id = :app.Id];
        System.assertEquals(volunteer.Id, owned.OwnerId, 'Assignment flow transfers the Case to the volunteer');
    }

    @IsTest
    static void secondBookingOfSameSlotIsRejected() {
        config();
        Case app = application();
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Booking Zone').Id)[0];
        InterviewBookingService.book(slot.Id, app.Id, null, InterviewBookingService.Actor.STAFF);

        Account other = InterviewSchedulingTestData.createHousehold('Other Household', TRACT);

        Test.startTest();
        String message;
        try {
            InterviewBookingService.book(slot.Id, other.Id, null, InterviewBookingService.Actor.STAFF);
        } catch (InterviewBookingService.BookingException ex) {
            message = ex.getMessage();
        }
        Test.stopTest();

        System.assertNotEquals(null, message, 'Double booking must throw');
        System.assert(message.contains('already been booked'), '' + message);
        System.assertEquals(null, [SELECT Interview_Day_Schedule__c FROM Account WHERE Id = :other.Id].Interview_Day_Schedule__c);
    }

    @IsTest
    static void householdWithBookingCannotBookAnotherSlot() {
        config();
        Case app = application();
        List<Interview_Day_Schedule__c> slots = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Booking Zone').Id);
        InterviewBookingService.book(slots[0].Id, app.Id, null, InterviewBookingService.Actor.STAFF);

        String message;
        try {
            InterviewBookingService.book(slots[1].Id, app.Id, null, InterviewBookingService.Actor.STAFF);
        } catch (InterviewBookingService.BookingException ex) {
            message = ex.getMessage();
        }
        System.assert(message != null && message.contains('already has a booked interview'), '' + message);
    }

    @IsTest
    static void applicantMayOnlyBookPublishedDaysInOwnZone() {
        config();
        Case app = application();
        Interview_Day_Schedule__c plannedSlot = InterviewSchedulingTestData.slotsFor(day('Planned', 8, 'Booking Zone').Id)[0];
        Interview_Day_Schedule__c otherZoneSlot = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Other Zone').Id)[0];

        String plannedMessage;
        try {
            InterviewBookingService.book(plannedSlot.Id, app.Id, null, InterviewBookingService.Actor.APPLICANT);
        } catch (InterviewBookingService.BookingException ex) {
            plannedMessage = ex.getMessage();
        }
        String zoneMessage;
        try {
            InterviewBookingService.book(otherZoneSlot.Id, app.Id, null, InterviewBookingService.Actor.APPLICANT);
        } catch (InterviewBookingService.BookingException ex) {
            zoneMessage = ex.getMessage();
        }

        System.assert(plannedMessage != null && plannedMessage.contains('not open'), '' + plannedMessage);
        System.assert(zoneMessage != null && zoneMessage.contains('not available for your area'), '' + zoneMessage);
        // Staff may still book the Planned day.
        InterviewBookingService.book(plannedSlot.Id, app.Id, null, InterviewBookingService.Actor.STAFF);
        System.assertEquals(true, InterviewSchedulingTestData.slot(plannedSlot.Id).Booked__c);
    }

    @IsTest
    static void applicantCutoffBlocksSlotsWithinTwentyFourHours() {
        config();
        Case app = application();
        Interview_Day_Schedule__c todaySlot = InterviewSchedulingTestData.slotsFor(day('Published', 0, 'Booking Zone').Id)[0];

        System.assertEquals(true, InterviewBookingService.isWithinCutoff(Date.today(), Time.newInstance(8, 0, 0, 0), 24));
        System.assertEquals(false, InterviewBookingService.isWithinCutoff(Date.today().addDays(7), Time.newInstance(8, 0, 0, 0), 24));
        System.assertEquals(false, InterviewBookingService.isWithinCutoff(Date.today(), Time.newInstance(8, 0, 0, 0), 0), '0 hours disables the cutoff');
        System.assertEquals(true, InterviewBookingService.isWithinCutoff(Date.today().addDays(7), null, 24), 'Un-timed slots are never bookable online');

        String message;
        try {
            InterviewBookingService.book(todaySlot.Id, app.Id, null, InterviewBookingService.Actor.APPLICANT);
        } catch (InterviewBookingService.BookingException ex) {
            message = ex.getMessage();
        }
        System.assert(message != null && message.contains('within 24 hours'), '' + message);
    }

    @IsTest
    static void rescheduleCarriesVolunteerAndReleasesOldSlot() {
        config();
        User volunteer = InterviewSchedulingTestData.createVolunteer();
        Case app = application();
        Id originalOwner = app.OwnerId;
        List<Interview_Day_Schedule__c> slots = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Booking Zone').Id);
        InterviewBookingService.book(slots[0].Id, app.Id, volunteer.Id, InterviewBookingService.Actor.STAFF);
        System.assertEquals(String.valueOf(originalOwner), InterviewSchedulingTestData.slot(slots[0].Id).Original_Case_Owner_Id__c,
            'Assignment flow stores the original owner on the booked slot');

        Test.startTest();
        InterviewBookingService.BookingResult result = InterviewBookingService.reschedule(
            app.Id, slots[2].Id, InterviewBookingService.Actor.APPLICANT, true
        );
        Test.stopTest();

        Interview_Day_Schedule__c oldSlot = InterviewSchedulingTestData.slot(slots[0].Id);
        Interview_Day_Schedule__c newSlot = InterviewSchedulingTestData.slot(slots[2].Id);

        System.assertEquals(slots[0].Id, result.previousScheduleId);
        System.assertEquals(slots[2].Id, result.scheduleId);
        System.assertEquals(volunteer.Id, result.volunteerId);

        System.assertEquals(false, oldSlot.Booked__c, 'Old slot is released');
        System.assertEquals('Available', oldSlot.Status__c);
        System.assertEquals(null, oldSlot.Case__c);
        System.assertEquals(null, oldSlot.Assigned_Volunteer__c);
        System.assertEquals('Pending', oldSlot.Google_Sync_Status__c, 'Old slot must become Available in Google again');
        System.assertEquals(null, oldSlot.Original_Case_Owner_Id__c, 'Released slot must not remember a previous owner');

        System.assertEquals(true, newSlot.Booked__c);
        System.assertEquals(app.Id, newSlot.Case__c);
        System.assertEquals(volunteer.Id, newSlot.Assigned_Volunteer__c, 'Volunteer is carried to the new slot');
        System.assertEquals('Assigned', newSlot.Assignment_Status__c);
        System.assertEquals('Pending', newSlot.Google_Sync_Status__c);
        System.assertEquals(String.valueOf(originalOwner), newSlot.Original_Case_Owner_Id__c, 'New slot captures the true original owner');

        System.assertEquals(slots[2].Id, [SELECT Interview_Day_Schedule__c FROM Account WHERE Id = :app.AccountId].Interview_Day_Schedule__c);
        System.assertEquals(volunteer.Id, [SELECT OwnerId FROM Case WHERE Id = :app.Id].OwnerId, 'Volunteer keeps Case ownership after the move');
    }

    @IsTest
    static void rescheduleWithoutBookingBooks() {
        config();
        Case app = application();
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Booking Zone').Id)[1];

        InterviewBookingService.BookingResult result = InterviewBookingService.reschedule(
            app.Id, slot.Id, InterviewBookingService.Actor.APPLICANT, true
        );

        System.assertEquals(null, result.previousScheduleId);
        System.assertEquals(true, InterviewSchedulingTestData.slot(slot.Id).Booked__c);
    }

    @IsTest
    static void rescheduleToSameSlotIsRejected() {
        config();
        Case app = application();
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Booking Zone').Id)[0];
        InterviewBookingService.book(slot.Id, app.Id, null, InterviewBookingService.Actor.STAFF);

        String message;
        try {
            InterviewBookingService.reschedule(app.Id, slot.Id, InterviewBookingService.Actor.APPLICANT, true);
        } catch (InterviewBookingService.BookingException ex) {
            message = ex.getMessage();
        }
        System.assert(message != null && message.contains('already the booked'), '' + message);
    }

    @IsTest
    static void releaseClearsBooking() {
        config();
        Case app = application();
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Booking Zone').Id)[0];
        InterviewBookingService.book(slot.Id, app.Id, null, InterviewBookingService.Actor.STAFF);

        InterviewBookingService.release(app.Id);

        Interview_Day_Schedule__c released = InterviewSchedulingTestData.slot(slot.Id);
        System.assertEquals(false, released.Booked__c);
        System.assertEquals('Available', released.Status__c);
        System.assertEquals('Pending', released.Google_Sync_Status__c);
        System.assertEquals(null, [SELECT Interview_Day_Schedule__c FROM Account WHERE Id = :app.AccountId].Interview_Day_Schedule__c);

        String message;
        try {
            InterviewBookingService.release(app.Id);
        } catch (InterviewBookingService.BookingException ex) {
            message = ex.getMessage();
        }
        System.assert(message != null && message.contains('No existing booking'), '' + message);
    }

    @IsTest
    static void zoneResolvesByTextThenNumericCode() {
        Zone__c zone = [SELECT Id FROM Zone__c WHERE Name = 'Booking Zone'];
        Account exact = InterviewSchedulingTestData.createHousehold('Exact', TRACT);
        Account numeric = InterviewSchedulingTestData.createHousehold('Numeric', '81.010');
        Account unknown = InterviewSchedulingTestData.createHousehold('Unknown', '99.99');
        Account blank = InterviewSchedulingTestData.createHousehold('Blank', null);

        System.assertEquals(zone.Id, InterviewBookingService.resolveZoneForAccount(exact.Id).zoneId);
        System.assertEquals(zone.Id, InterviewBookingService.resolveZoneForAccount(numeric.Id).zoneId, '81.010 equals 81.01 numerically');
        InterviewBookingService.ZoneResolution unresolved = InterviewBookingService.resolveZoneForAccount(unknown.Id);
        System.assertEquals(null, unresolved.zoneId);
        System.assertEquals(99.99, unresolved.numericCode, 'Numeric fallback for Interview_Day__c.Zone_Code__c matching');
        System.assertEquals(false, InterviewBookingService.resolveZoneForAccount(blank.Id).isResolved());
    }

    @IsTest
    static void bookableDaysDependOnActor() {
        config();
        Case app = application();
        InterviewBookingService.ZoneResolution zone = InterviewBookingService.resolveZoneForAccount(app.AccountId);

        List<Interview_Day__c> staffDays = InterviewBookingService.queryBookableDays(zone, InterviewBookingService.Actor.STAFF, 0);
        List<Interview_Day__c> applicantDays = InterviewBookingService.queryBookableDays(zone, InterviewBookingService.Actor.APPLICANT, 90);

        System.assertEquals(3, staffDays.size(), 'Staff see Planned and Published days in the zone');
        System.assertEquals(2, applicantDays.size(), 'Applicants see Published days only');
        for (Interview_Day__c day : applicantDays) {
            System.assertEquals('Published', day.Status__c);
        }
        System.assertEquals(0, InterviewBookingService.queryBookableDays(new InterviewBookingService.ZoneResolution(),
            InterviewBookingService.Actor.STAFF, 0).size(), 'Unresolved zone yields no days');
    }

    @IsTest
    static void controllerWrapsServiceErrorsForTheUi() {
        config();
        Case app = application();
        Interview_Day_Schedule__c slot = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Booking Zone').Id)[0];
        System.assertEquals(3, SelectInterviewSlotController.getInterviewDays(app.Id).size());

        SelectInterviewSlotController.updateInterviewSchedule(slot.Id, app.AccountId);
        System.assertEquals(true, InterviewSchedulingTestData.slot(slot.Id).Booked__c);

        Boolean threw = false;
        try {
            SelectInterviewSlotController.updateInterviewSchedule(slot.Id, app.AccountId);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Booking an already booked slot must surface as AuraHandledException');

        SelectInterviewSlotController.unscheduleInterview(app.AccountId);
        System.assertEquals(false, InterviewSchedulingTestData.slot(slot.Id).Booked__c);
    }

    @IsTest
    static void staffBookingFromCaseEmailsTheSchedulingLinkAutomatically() {
        config();
        Case app = application();
        List<Interview_Day_Schedule__c> slots = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Booking Zone').Id);

        Test.startTest();
        SelectInterviewSlotController.updateInterviewSchedule(slots[0].Id, app.Id);
        Test.stopTest();

        Case sent = [SELECT Self_Service_Token_Hash__c, Self_Service_Link_Sent_On__c FROM Case WHERE Id = :app.Id];
        System.assertNotEquals(null, sent.Self_Service_Token_Hash__c, 'A token is generated with the booking');
        System.assertNotEquals(null, sent.Self_Service_Link_Sent_On__c, 'The link email is sent with the booking');

        // Account context has no Case: nothing is sent. Disabled flag: nothing is sent either.
        SelectInterviewSlotController.unscheduleInterview(app.AccountId);
        update new Case(Id = app.Id, Self_Service_Link_Sent_On__c = null);
        InterviewSelfServiceConfig.instanceOverride.autoSendLinkOnBooking = false;
        SelectInterviewSlotController.updateInterviewSchedule(slots[1].Id, app.Id);
        System.assertEquals(null, [SELECT Self_Service_Link_Sent_On__c FROM Case WHERE Id = :app.Id].Self_Service_Link_Sent_On__c);
    }

    @IsTest
    static void interviewDayCarriesItsWindowAndSlotsFollowTheDayStart() {
        Zone__c zone = [SELECT Id FROM Zone__c WHERE Name = 'Booking Zone'];
        Interview_Day__c published = day('Published', 7, 'Booking Zone');
        Interview_Day__c reloaded = [SELECT Start_Time__c, End_Time__c, Total_Slots__c FROM Interview_Day__c WHERE Id = :published.Id];
        System.assertEquals(Time.newInstance(8, 0, 0, 0), reloaded.Start_Time__c, 'Morning day starts at 08:00 by default');
        System.assertEquals(Time.newInstance(9, 0, 0, 0), reloaded.End_Time__c, '4 slots x 15 min end at 09:00');

        Interview_Day_Schedule__c first = InterviewSchedulingTestData.slotsFor(published.Id)[0];
        System.assertEquals('8:00 AM', first.Start_Time_Text__c, 'Text label stamped on the slot');
        System.assertEquals('8:15 AM', first.End_Time_Text__c);

        // A custom start time is respected and drives the slots; afternoon defaults to 12:30.
        Interview_Day__c custom = new Interview_Day__c(Zone__c = zone.Id, Zone_Name__c = 'Booking Zone',
            Interview_Date__c = Date.today().addDays(9), Schedule_Mode__c = 'Morning', Total_Slots__c = 3,
            Status__c = 'Published', Start_Time__c = Time.newInstance(9, 30, 0, 0), Year__c = Date.today().year());
        insert custom;
        System.assertEquals(Time.newInstance(10, 15, 0, 0), [SELECT End_Time__c FROM Interview_Day__c WHERE Id = :custom.Id].End_Time__c);
        List<Interview_Day_Schedule__c> customSlots = InterviewSchedulingTestData.slotsFor(custom.Id);
        System.assertEquals(3, customSlots.size());
        System.assertEquals(Time.newInstance(9, 30, 0, 0), customSlots[0].Start_Time__c);
        System.assertEquals(Time.newInstance(10, 0, 0, 0), customSlots[2].Start_Time__c);

        Interview_Day__c afternoon = InterviewSchedulingTestData.createInterviewDay(zone, Date.today().addDays(10), 'AfterNoon', 16, 'Published');
        Interview_Day__c pm = [SELECT Start_Time__c, End_Time__c FROM Interview_Day__c WHERE Id = :afternoon.Id];
        System.assertEquals(Time.newInstance(12, 30, 0, 0), pm.Start_Time__c);
        System.assertEquals(Time.newInstance(16, 30, 0, 0), pm.End_Time__c, '16 afternoon slots run 12:30 - 4:30');
    }

    @IsTest
    static void changingTheWindowOfABookedDayIsBlocked() {
        config();
        Case app = application();
        Interview_Day__c published = day('Published', 7, 'Booking Zone');
        InterviewBookingService.book(InterviewSchedulingTestData.slotsFor(published.Id)[0].Id, app.Id, null, InterviewBookingService.Actor.STAFF);

        String message;
        try {
            update new Interview_Day__c(Id = published.Id, Start_Time__c = Time.newInstance(9, 0, 0, 0));
        } catch (DmlException ex) {
            message = ex.getDmlMessage(0);
        }
        System.assert(message != null && message.contains('cannot be changed'), '' + message);
    }

    @IsTest
    static void singleInterviewPerTimeRuleSpansZones() {
        config();
        InterviewSelfServiceConfig.instanceOverride.enforceSingleInterviewPerTime = true;
        Case app = application();
        Interview_Day_Schedule__c bookingZone8am = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Booking Zone').Id)[0];
        Interview_Day_Schedule__c otherZone8am = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Other Zone').Id)[0];
        Account other = InterviewSchedulingTestData.createHousehold('Other Zone Household', '82.01');
        InterviewBookingService.book(otherZone8am.Id, other.Id, null, InterviewBookingService.Actor.STAFF);

        String message;
        try {
            InterviewBookingService.book(bookingZone8am.Id, app.Id, null, InterviewBookingService.Actor.STAFF);
        } catch (InterviewBookingService.BookingException ex) {
            message = ex.getMessage();
        }
        System.assert(message != null && message.contains('already booked at this time'), '' + message);

        // Applicants are not even offered the taken time.
        InterviewBookingService.ZoneResolution zone = InterviewBookingService.resolveZoneForAccount(app.AccountId);
        for (Interview_Day__c d : InterviewBookingService.queryBookableDays(zone, InterviewBookingService.Actor.APPLICANT, 90)) {
            for (Interview_Day_Schedule__c slot : d.Interview_Day_Schedules__r) {
                System.assertNotEquals(bookingZone8am.Id, slot.Id, '08:00 is hidden because Other Zone has it booked');
            }
        }
        InterviewSelfServiceConfig.instanceOverride.enforceSingleInterviewPerTime = false;
        InterviewBookingService.book(bookingZone8am.Id, app.Id, null, InterviewBookingService.Actor.STAFF);
        System.assertEquals(true, InterviewSchedulingTestData.slot(bookingZone8am.Id).Booked__c, 'Rule off: parallel booking allowed');
    }

    @IsTest
    static void rescheduleWorksForAUserWhoCannotSeeTheCase() {
        // Simulates the Experience Cloud guest: the volunteer-assignment flow's Apex must not depend on
        // the running user's sharing when the applicant moves a slot.
        config();
        User volunteer = InterviewSchedulingTestData.createVolunteer();
        Case app = application();
        List<Interview_Day_Schedule__c> slots = InterviewSchedulingTestData.slotsFor(day('Published', 7, 'Booking Zone').Id);
        InterviewBookingService.book(slots[0].Id, app.Id, volunteer.Id, InterviewBookingService.Actor.STAFF);

        Profile minimal = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' OR Name = 'Standard User' ORDER BY Name ASC LIMIT 1];
        String unique = 'noaccess' + Datetime.now().getTime() + '@hgh-test.org';
        User restricted = new User(Alias = 'noacc', Email = unique, EmailEncodingKey = 'UTF-8', FirstName = 'No', LastName = 'Access',
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', ProfileId = minimal.Id, TimeZoneSidKey = 'America/Chicago', UserName = unique);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert restricted;
        }

        // The applicant path: site guest -> InterviewSelfServiceController (without sharing) -> service -> flow.
        String token = InterviewSelfServiceService.generateAndStore(app.Id).token;

        Test.startTest();
        System.runAs(restricted) {
            InterviewSelfServiceController.BookingDTO result = InterviewSelfServiceController.selectSlot(token, slots[1].Id);
            System.assertEquals('OK', result.status, '' + result.message);
        }
        Test.stopTest();

        Interview_Day_Schedule__c moved = InterviewSchedulingTestData.slot(slots[1].Id);
        System.assertEquals(true, moved.Booked__c);
        System.assertEquals(volunteer.Id, moved.Assigned_Volunteer__c);
        System.assertEquals(false, InterviewSchedulingTestData.slot(slots[0].Id).Booked__c);
        System.assertEquals(volunteer.Id, [SELECT OwnerId FROM Case WHERE Id = :app.Id].OwnerId);
    }
}