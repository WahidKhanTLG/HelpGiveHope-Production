/**
 * Mirrors Interview_Day_Schedule__c records to Google Calendar.
 *
 *  - Unbooked slot  -> "Available" event (transparent, no attendees) when placeholder sync is enabled
 *  - Booked slot    -> interview event with the applicant and assigned volunteer as attendees
 *  - Delete Pending -> event removed
 *
 * One Google event per schedule record, identified by extendedProperties.private.salesforceScheduleId.
 * Creates are idempotent: when the record has no Google_Event_Id__c the service first looks the event up
 * by that private property so an interrupted or overlapping run never produces a second event.
 *
 * This class never enqueues anything and does no DML for bulk callers: syncSchedule() returns the record
 * update to apply so GoogleCalendarSyncJob can write results in one DML statement after all callouts.
 * upsertEvent()/deleteEvent() keep the original single-record API used by GoogleCalendarSyncQueueable.
 */
public without sharing class GoogleCalendarService {

    private static final String NAMED_CREDENTIAL = 'callout:HGH_Google_Calendar';
    private static final Integer TIMEOUT_MS = 20000;
    private static final String PROPERTY_KEY = 'salesforceScheduleId';

    public static final String STATUS_PENDING = 'Pending';
    public static final String STATUS_DELETE_PENDING = 'Delete Pending';
    public static final String STATUS_SYNCED = 'Synced';
    public static final String STATUS_DELETED = 'Deleted';
    public static final String STATUS_ERROR = 'Error';
    public static final String STATUS_NOT_REQUIRED = 'Not Required';

    public class SyncOutcome {
        /** Record update to apply; null when nothing should be written (transient failure, retry later). */
        public Interview_Day_Schedule__c updateRecord;
        public Boolean transientFailure = false;
        public Integer calloutsUsed = 0;
        public String message;
    }

    public class DeleteOutcome {
        public Boolean success = false;
        public Boolean transientFailure = false;
        public Integer calloutsUsed = 0;
        public String message;
    }

    // ------------------------------------------------------------------
    // Single-record API (kept for GoogleCalendarSyncQueueable / existing callers)
    // ------------------------------------------------------------------

    public static void upsertEvent(Id scheduleId) {
        if (scheduleId == null) {
            return;
        }
        GoogleCalendarSettings settings = GoogleCalendarSettings.load();
        List<Interview_Day_Schedule__c> schedules = queryForSync(new Set<Id>{ scheduleId }, 1);
        if (schedules.isEmpty()) {
            return;
        }
        SyncOutcome outcome = syncSchedule(schedules[0], settings);
        applyOutcome(outcome);
    }

    public static void deleteEvent(Id scheduleId) {
        if (scheduleId == null) {
            return;
        }
        GoogleCalendarSettings settings = GoogleCalendarSettings.load();
        List<Interview_Day_Schedule__c> schedules = queryForSync(new Set<Id>{ scheduleId }, 1);
        if (schedules.isEmpty()) {
            return;
        }
        schedules[0].Google_Sync_Status__c = STATUS_DELETE_PENDING;
        SyncOutcome outcome = syncSchedule(schedules[0], settings);
        applyOutcome(outcome);
    }

    private static void applyOutcome(SyncOutcome outcome) {
        if (outcome == null || outcome.updateRecord == null) {
            return;
        }
        try {
            Database.update(outcome.updateRecord, AccessLevel.SYSTEM_MODE);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Unable to save Google Calendar sync result: ' + ex.getMessage());
        }
    }

    // ------------------------------------------------------------------
    // Queries
    // ------------------------------------------------------------------

    /**
     * Schedules with everything the payload builder needs. Pass ids = null to fetch rows that are
     * waiting for synchronisation (Pending / Delete Pending), oldest change first.
     */
    public static List<Interview_Day_Schedule__c> queryForSync(Set<Id> ids, Integer limitSize) {
        Integer safeLimit = limitSize == null || limitSize <= 0 ? 50 : limitSize;
        Set<String> pendingStatuses = new Set<String>{ STATUS_PENDING, STATUS_DELETE_PENDING };

        if (ids == null) {
            return [
                SELECT Id, Name, Booked__c, Case__c, Case__r.CaseNumber,
                       Case__r.Contact.Email, Case__r.Contact.Name,
                       Case__r.Account.Name, Case__r.Account.BillingStreet, Case__r.Account.BillingCity,
                       Case__r.Account.BillingState, Case__r.Account.BillingPostalCode,
                       Case__r.Account.npe01__One2OneContact__r.Email,
                       Case__r.Account.npe01__One2OneContact__r.Name,
                       Assigned_Volunteer__c, Assigned_Volunteer__r.Name, Assigned_Volunteer__r.Email,
                       Interview_Date__c, Schedule_Mode__c, Start_Time__c, End_Time__c,
                       Interview_Day__c, Interview_Day__r.Zone__r.Name, Interview_Day__r.Zone_Name__c,
                       Google_Event_Id__c, Google_Calendar_Id__c, Google_Sync_Status__c
                FROM Interview_Day_Schedule__c
                WHERE Google_Sync_Status__c IN :pendingStatuses
                ORDER BY LastModifiedDate ASC
                LIMIT :safeLimit
            ];
        }

        return [
            SELECT Id, Name, Booked__c, Case__c, Case__r.CaseNumber,
                   Case__r.Contact.Email, Case__r.Contact.Name,
                   Case__r.Account.Name, Case__r.Account.BillingStreet, Case__r.Account.BillingCity,
                   Case__r.Account.BillingState, Case__r.Account.BillingPostalCode,
                   Case__r.Account.npe01__One2OneContact__r.Email,
                   Case__r.Account.npe01__One2OneContact__r.Name,
                   Assigned_Volunteer__c, Assigned_Volunteer__r.Name, Assigned_Volunteer__r.Email,
                   Interview_Date__c, Schedule_Mode__c, Start_Time__c, End_Time__c,
                   Interview_Day__c, Interview_Day__r.Zone__r.Name, Interview_Day__r.Zone_Name__c,
                   Google_Event_Id__c, Google_Calendar_Id__c, Google_Sync_Status__c
            FROM Interview_Day_Schedule__c
            WHERE Id IN :ids
            LIMIT :safeLimit
        ];
    }

    public static Integer countPendingWork() {
        Set<String> pendingStatuses = new Set<String>{ STATUS_PENDING, STATUS_DELETE_PENDING };
        return [
            SELECT COUNT() FROM Interview_Day_Schedule__c WHERE Google_Sync_Status__c IN :pendingStatuses
        ];
    }

    // ------------------------------------------------------------------
    // Core synchronisation
    // ------------------------------------------------------------------

    /**
     * Decides and performs the Google operation for one schedule. Never throws; never does DML.
     */
    public static SyncOutcome syncSchedule(Interview_Day_Schedule__c schedule, GoogleCalendarSettings settings) {
        SyncOutcome outcome = new SyncOutcome();
        Interview_Day_Schedule__c upd = new Interview_Day_Schedule__c(Id = schedule.Id);
        outcome.updateRecord = upd;

        try {
            if (settings == null || !settings.recordFound) {
                setError(upd, 'Google Calendar configuration was not found.');
                return outcome;
            }
            if (!settings.enabled) {
                setNotRequired(upd);
                return outcome;
            }

            String calendarId = String.isNotBlank(schedule.Google_Calendar_Id__c)
                ? schedule.Google_Calendar_Id__c
                : settings.calendarId;

            Boolean isBooked = schedule.Booked__c == true;
            Boolean wantsDelete = schedule.Google_Sync_Status__c == STATUS_DELETE_PENDING
                || (!isBooked && !settings.placeholderSyncEnabled);

            if (wantsDelete) {
                if (String.isBlank(schedule.Google_Event_Id__c)) {
                    if (schedule.Google_Sync_Status__c == STATUS_DELETE_PENDING) {
                        setDeleted(upd, calendarId);
                    } else {
                        setNotRequired(upd);
                    }
                    return outcome;
                }
                if (String.isBlank(calendarId)) {
                    setError(upd, 'Google Calendar Id is not configured.');
                    return outcome;
                }
                DeleteOutcome del = deleteEventById(calendarId, schedule.Google_Event_Id__c, settings);
                outcome.calloutsUsed += del.calloutsUsed;
                if (del.transientFailure) {
                    outcome.transientFailure = true;
                    outcome.updateRecord = null;
                    outcome.message = del.message;
                    return outcome;
                }
                if (!del.success) {
                    setError(upd, del.message);
                    return outcome;
                }
                setDeleted(upd, calendarId);
                return outcome;
            }

            // ---- create / update ----
            if (String.isBlank(calendarId)) {
                setError(upd, 'Google Calendar Id is not configured.');
                return outcome;
            }
            if (String.isBlank(settings.timeZone)) {
                setError(upd, 'Google Calendar time zone is not configured.');
                return outcome;
            }
            if (schedule.Interview_Date__c == null) {
                setError(upd, 'Interview Date is missing.');
                return outcome;
            }
            if (schedule.Start_Time__c == null || schedule.End_Time__c == null) {
                setError(upd, 'Interview Start/End Time is missing.');
                return outcome;
            }

            List<String> warnings = new List<String>();
            Map<String, Object> payload = isBooked
                ? buildBookedPayload(schedule, settings, warnings)
                : buildAvailablePayload(schedule, settings);

            String eventId = schedule.Google_Event_Id__c;

            if (String.isBlank(eventId)) {
                // Idempotency guard: an event may already exist for this record.
                HttpResponse lookup = send(buildLookupRequest(calendarId, schedule.Id));
                outcome.calloutsUsed++;
                if (isTransient(lookup)) {
                    outcome.transientFailure = true;
                    outcome.updateRecord = null;
                    outcome.message = extractGoogleError(lookup);
                    return outcome;
                }
                eventId = parseFirstEventId(lookup);
            }

            HttpResponse response;
            if (String.isNotBlank(eventId)) {
                response = send(buildEventRequest('PATCH', calendarId, eventId, payload, settings.sendUpdates));
                outcome.calloutsUsed++;
                if (response.getStatusCode() == 404 || response.getStatusCode() == 410) {
                    // Event was removed in Google; recreate it.
                    eventId = null;
                }
            }
            if (String.isBlank(eventId)) {
                response = send(buildEventRequest('POST', calendarId, null, payload, settings.sendUpdates));
                outcome.calloutsUsed++;
            }

            if (isTransient(response)) {
                outcome.transientFailure = true;
                outcome.updateRecord = null;
                outcome.message = extractGoogleError(response);
                return outcome;
            }
            if (!isSuccess(response)) {
                setError(upd, extractGoogleError(response));
                return outcome;
            }

            String returnedId = parseEventId(response);
            if (String.isBlank(returnedId)) {
                returnedId = eventId;
            }
            if (String.isBlank(returnedId)) {
                setError(upd, 'Google Calendar did not return an event Id.');
                return outcome;
            }

            setSynced(upd, calendarId, returnedId, warnings);
            return outcome;

        } catch (Exception ex) {
            if (isTimeoutException(ex)) {
                outcome.transientFailure = true;
                outcome.updateRecord = null;
                outcome.message = sanitizeException(ex);
                return outcome;
            }
            setError(upd, sanitizeException(ex));
            outcome.updateRecord = upd;
            return outcome;
        }
    }

    /** Read timeouts and the per-transaction callout-time limit: retry later instead of flagging Error. */
    @TestVisible
    private static Boolean isTimeoutException(Exception ex) {
        if (ex == null || !(ex instanceof CalloutException)) {
            return false;
        }
        String message = ex.getMessage() == null ? '' : ex.getMessage().toLowerCase();
        return message.contains('timed out') || message.contains('time allotted') || message.contains('timeout');
    }

    /**
     * Deletes a Google event. 404/410 count as success (already gone).
     */
    public static DeleteOutcome deleteEventById(String calendarId, String eventId, GoogleCalendarSettings settings) {
        DeleteOutcome outcome = new DeleteOutcome();
        try {
            if (String.isBlank(calendarId) || String.isBlank(eventId)) {
                outcome.success = true;
                return outcome;
            }
            HttpRequest request = new HttpRequest();
            request.setEndpoint(
                NAMED_CREDENTIAL + '/calendars/' + EncodingUtil.urlEncode(calendarId, 'UTF-8')
                + '/events/' + EncodingUtil.urlEncode(eventId, 'UTF-8')
                + '?sendUpdates=' + EncodingUtil.urlEncode(settings == null ? 'none' : settings.sendUpdates, 'UTF-8')
            );
            request.setMethod('DELETE');
            request.setTimeout(TIMEOUT_MS);

            HttpResponse response = send(request);
            outcome.calloutsUsed = 1;

            if (isTransient(response)) {
                outcome.transientFailure = true;
                outcome.message = extractGoogleError(response);
                return outcome;
            }
            if (isSuccess(response) || response.getStatusCode() == 404 || response.getStatusCode() == 410) {
                outcome.success = true;
                return outcome;
            }
            outcome.message = extractGoogleError(response);
            return outcome;
        } catch (Exception ex) {
            outcome.transientFailure = isTimeoutException(ex);
            outcome.message = sanitizeException(ex);
            return outcome;
        }
    }

    // ------------------------------------------------------------------
    // Payloads
    // ------------------------------------------------------------------

    @TestVisible
    private static Map<String, Object> buildAvailablePayload(Interview_Day_Schedule__c schedule, GoogleCalendarSettings settings) {
        Map<String, Object> payload = baseEventPayload(schedule, settings);
        payload.put('summary', applyTokens(settings.availableTitlePattern, schedule));
        payload.put('description',
            'Open Help Give Hope interview slot.'
            + '\nZone: ' + zoneName(schedule)
            + '\n' + modeLabel(schedule.Schedule_Mode__c) + ' slot ' + slotNumber(schedule)
            + '\nBook this slot from Salesforce or send the applicant a scheduling link.');
        payload.put('transparency', 'transparent');
        payload.put('attendees', new List<Object>());
        payload.put('location', '');
        if (String.isNotBlank(settings.availableColorId)) {
            payload.put('colorId', settings.availableColorId);
        }
        return payload;
    }

    @TestVisible
    private static Map<String, Object> buildBookedPayload(
        Interview_Day_Schedule__c schedule, GoogleCalendarSettings settings, List<String> warnings
    ) {
        Map<String, Object> payload = baseEventPayload(schedule, settings);
        payload.put('summary', applyTokens(settings.eventTitlePattern, schedule));

        String description = 'Help Give Hope home interview.'
            + '\nDate: ' + dateLabel(schedule.Interview_Date__c)
            + '\nTime: ' + timeLabel(schedule.Start_Time__c) + ' - ' + timeLabel(schedule.End_Time__c)
            + '\nZone: ' + zoneName(schedule);
        if (schedule.Assigned_Volunteer__c != null && schedule.Assigned_Volunteer__r != null) {
            description += '\nInterviewer: ' + schedule.Assigned_Volunteer__r.Name;
        }
        description += '\n\nNeed to change the time? Use the scheduling link in your email or call Help Give Hope.';
        payload.put('description', description);
        payload.put('transparency', 'opaque');
        payload.put('location', settings.includeHouseholdAddress ? householdAddress(schedule) : '');

        List<Object> attendees = new List<Object>();
        if (settings.inviteApplicant) {
            String applicantEmail = applicantEmail(schedule);
            if (isValidEmail(applicantEmail)) {
                attendees.add(new Map<String, Object>{
                    'email' => applicantEmail.trim(),
                    'displayName' => applicantName(schedule),
                    'responseStatus' => 'needsAction'
                });
            } else {
                warnings.add('Applicant has no valid email; no calendar invitation was sent to the household.');
            }
        }
        if (settings.inviteVolunteer && schedule.Assigned_Volunteer__c != null && schedule.Assigned_Volunteer__r != null) {
            String volunteerEmail = schedule.Assigned_Volunteer__r.Email;
            if (isValidEmail(volunteerEmail)) {
                attendees.add(new Map<String, Object>{
                    'email' => volunteerEmail.trim(),
                    'displayName' => schedule.Assigned_Volunteer__r.Name,
                    'responseStatus' => 'needsAction'
                });
            } else {
                warnings.add('Assigned volunteer has no valid email; no calendar invitation was sent to the volunteer.');
            }
        }
        payload.put('attendees', attendees);
        if (String.isNotBlank(settings.bookedColorId)) {
            payload.put('colorId', settings.bookedColorId);
        }
        return payload;
    }

    private static Map<String, Object> baseEventPayload(Interview_Day_Schedule__c schedule, GoogleCalendarSettings settings) {
        return new Map<String, Object>{
            'start' => new Map<String, Object>{
                'dateTime' => formatLocalDateTime(schedule.Interview_Date__c, schedule.Start_Time__c),
                'timeZone' => settings.timeZone
            },
            'end' => new Map<String, Object>{
                'dateTime' => formatLocalDateTime(schedule.Interview_Date__c, schedule.End_Time__c),
                'timeZone' => settings.timeZone
            },
            'guestsCanModify' => false,
            'guestsCanInviteOthers' => false,
            'guestsCanSeeOtherGuests' => false,
            'reminders' => new Map<String, Object>{ 'useDefault' => true },
            'extendedProperties' => new Map<String, Object>{
                'private' => new Map<String, Object>{ PROPERTY_KEY => String.valueOf(schedule.Id) }
            }
        };
    }

    @TestVisible
    private static String applyTokens(String pattern, Interview_Day_Schedule__c schedule) {
        String caseNumber = schedule.Case__c != null && schedule.Case__r != null ? schedule.Case__r.CaseNumber : null;
        String household = schedule.Case__c != null && schedule.Case__r != null && schedule.Case__r.Account != null
            ? schedule.Case__r.Account.Name : null;
        String result = pattern == null ? '' : pattern;
        result = result.replace('{CaseNumber}', String.isNotBlank(caseNumber) ? caseNumber : schedule.Name);
        result = result.replace('{HouseholdName}', String.isNotBlank(household) ? household : '');
        result = result.replace('{ZoneName}', zoneName(schedule));
        result = result.replace('{Mode}', modeLabel(schedule.Schedule_Mode__c));
        result = result.replace('{Slot}', String.valueOf(slotNumber(schedule)));
        result = result.replace('{Date}', dateLabel(schedule.Interview_Date__c));
        return result.trim();
    }

    private static String zoneName(Interview_Day_Schedule__c schedule) {
        if (schedule.Interview_Day__c != null && schedule.Interview_Day__r != null) {
            if (schedule.Interview_Day__r.Zone__r != null && String.isNotBlank(schedule.Interview_Day__r.Zone__r.Name)) {
                return schedule.Interview_Day__r.Zone__r.Name;
            }
            if (String.isNotBlank(schedule.Interview_Day__r.Zone_Name__c)) {
                return schedule.Interview_Day__r.Zone_Name__c;
            }
        }
        return 'Zone';
    }

    public static String modeLabel(String mode) {
        if (String.isBlank(mode)) {
            return '';
        }
        return mode.equalsIgnoreCase('AfterNoon') ? 'Afternoon' : mode;
    }

    /** Slot number is the trailing integer of the record name (naming convention set by the triggers). */
    public static Integer slotNumber(Interview_Day_Schedule__c schedule) {
        if (schedule == null || String.isBlank(schedule.Name)) {
            return 0;
        }
        List<String> parts = schedule.Name.trim().split(' ');
        try {
            return Integer.valueOf(parts[parts.size() - 1]);
        } catch (Exception ignored) {
            return 0;
        }
    }

    private static String applicantEmail(Interview_Day_Schedule__c schedule) {
        if (schedule.Case__c == null || schedule.Case__r == null) {
            return null;
        }
        if (schedule.Case__r.Contact != null && String.isNotBlank(schedule.Case__r.Contact.Email)) {
            return schedule.Case__r.Contact.Email;
        }
        if (schedule.Case__r.Account != null && schedule.Case__r.Account.npe01__One2OneContact__r != null) {
            return schedule.Case__r.Account.npe01__One2OneContact__r.Email;
        }
        return null;
    }

    private static String applicantName(Interview_Day_Schedule__c schedule) {
        if (schedule.Case__r != null && schedule.Case__r.Contact != null && String.isNotBlank(schedule.Case__r.Contact.Name)) {
            return schedule.Case__r.Contact.Name;
        }
        if (schedule.Case__r != null && schedule.Case__r.Account != null
            && schedule.Case__r.Account.npe01__One2OneContact__r != null) {
            return schedule.Case__r.Account.npe01__One2OneContact__r.Name;
        }
        return 'Applicant';
    }

    private static String householdAddress(Interview_Day_Schedule__c schedule) {
        if (schedule.Case__r == null || schedule.Case__r.Account == null) {
            return '';
        }
        List<String> parts = new List<String>();
        Account acc = schedule.Case__r.Account;
        if (String.isNotBlank(acc.BillingStreet)) parts.add(acc.BillingStreet.replace('\n', ' '));
        if (String.isNotBlank(acc.BillingCity)) parts.add(acc.BillingCity);
        if (String.isNotBlank(acc.BillingState)) parts.add(acc.BillingState);
        if (String.isNotBlank(acc.BillingPostalCode)) parts.add(acc.BillingPostalCode);
        return String.join(parts, ', ');
    }

    @TestVisible
    private static Boolean isValidEmail(String email) {
        return String.isNotBlank(email)
            && Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', email.trim());
    }

    // ------------------------------------------------------------------
    // Date / time formatting
    // ------------------------------------------------------------------

    public static String formatLocalDateTime(Date interviewDate, Time interviewTime) {
        return String.valueOf(interviewDate.year()) + '-' + pad2(interviewDate.month()) + '-' + pad2(interviewDate.day())
            + 'T' + pad2(interviewTime.hour()) + ':' + pad2(interviewTime.minute()) + ':' + pad2(interviewTime.second());
    }

    public static String dateLabel(Date value) {
        if (value == null) {
            return '';
        }
        return Datetime.newInstanceGmt(value, Time.newInstance(12, 0, 0, 0)).formatGmt('EEEE, MMMM d, yyyy');
    }

    public static String timeLabel(Time value) {
        String label = InterviewDayWindow.label(value);
        return label == null ? '' : label;
    }

    private static String pad2(Integer value) {
        return value < 10 ? '0' + String.valueOf(value) : String.valueOf(value);
    }

    // ------------------------------------------------------------------
    // HTTP
    // ------------------------------------------------------------------

    private static HttpRequest buildLookupRequest(String calendarId, Id scheduleId) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(
            NAMED_CREDENTIAL + '/calendars/' + EncodingUtil.urlEncode(calendarId, 'UTF-8')
            + '/events?maxResults=1&showDeleted=false&privateExtendedProperty='
            + EncodingUtil.urlEncode(PROPERTY_KEY + '=' + String.valueOf(scheduleId), 'UTF-8')
        );
        request.setMethod('GET');
        request.setHeader('Accept', 'application/json');
        request.setTimeout(TIMEOUT_MS);
        return request;
    }

    private static HttpRequest buildEventRequest(
        String method, String calendarId, String eventId, Map<String, Object> payload, String sendUpdates
    ) {
        String endpoint = NAMED_CREDENTIAL + '/calendars/' + EncodingUtil.urlEncode(calendarId, 'UTF-8') + '/events';
        if (String.isNotBlank(eventId)) {
            endpoint += '/' + EncodingUtil.urlEncode(eventId, 'UTF-8');
        }
        endpoint += '?sendUpdates=' + EncodingUtil.urlEncode(String.isBlank(sendUpdates) ? 'none' : sendUpdates, 'UTF-8');

        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod(method);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
        request.setTimeout(TIMEOUT_MS);
        request.setBody(JSON.serialize(payload));
        return request;
    }

    private static HttpResponse send(HttpRequest request) {
        return new Http().send(request);
    }

    private static Boolean isSuccess(HttpResponse response) {
        return response != null && response.getStatusCode() >= 200 && response.getStatusCode() < 300;
    }

    /**
     * Rate limiting, backend unavailability and an expired principal token (401): keep the record
     * Pending and retry on the next sweep. A 401 clears itself once the principal is re-authenticated.
     */
    @TestVisible
    private static Boolean isTransient(HttpResponse response) {
        if (response == null) {
            return false;
        }
        Integer code = response.getStatusCode();
        if (code == 429 || code == 503 || code == 401) {
            return true;
        }
        if (code == 403) {
            String body = response.getBody();
            return body != null && (body.contains('rateLimitExceeded') || body.contains('userRateLimitExceeded')
                || body.contains('quotaExceeded') || body.contains('usageLimits'));
        }
        return false;
    }

    private static String parseEventId(HttpResponse response) {
        if (response == null || String.isBlank(response.getBody())) {
            return null;
        }
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            return body.get('id') == null ? null : String.valueOf(body.get('id'));
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String parseFirstEventId(HttpResponse response) {
        if (response == null || !isSuccess(response) || String.isBlank(response.getBody())) {
            return null;
        }
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            Object items = body.get('items');
            if (items instanceof List<Object>) {
                List<Object> eventItems = (List<Object>) items;
                if (!eventItems.isEmpty() && eventItems[0] instanceof Map<String, Object>) {
                    Map<String, Object> firstItem = (Map<String, Object>) eventItems[0];
                    if (firstItem.get('status') != null && String.valueOf(firstItem.get('status')) == 'cancelled') {
                        return null;
                    }
                    return firstItem.get('id') == null ? null : String.valueOf(firstItem.get('id'));
                }
            }
        } catch (Exception ignored) {
            // fall through
        }
        return null;
    }

    @TestVisible
    private static String extractGoogleError(HttpResponse response) {
        String message;
        try {
            if (response != null && String.isNotBlank(response.getBody())) {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                if (body.get('error') instanceof Map<String, Object>) {
                    Map<String, Object> errorData = (Map<String, Object>) body.get('error');
                    if (errorData.get('message') != null) {
                        message = String.valueOf(errorData.get('message'));
                    }
                }
            }
        } catch (Exception ignored) {
            message = null;
        }
        if (String.isBlank(message)) {
            message = 'Google Calendar request failed.';
        }
        return 'HTTP ' + (response == null ? '0' : String.valueOf(response.getStatusCode())) + ': ' + message;
    }

    private static String sanitizeException(Exception ex) {
        String message = ex == null ? null : ex.getMessage();
        if (String.isBlank(message)) {
            return 'Google Calendar synchronization failed.';
        }
        message = message.replace('\r', ' ').replace('\n', ' ');
        return message.length() > 1500 ? message.substring(0, 1500) : message;
    }

    // ------------------------------------------------------------------
    // Record state helpers (in-memory; DML is the caller's job)
    // ------------------------------------------------------------------

    private static void setSynced(Interview_Day_Schedule__c upd, String calendarId, String eventId, List<String> warnings) {
        upd.Google_Calendar_Id__c = calendarId;
        upd.Google_Event_Id__c = eventId;
        upd.Google_Sync_Status__c = STATUS_SYNCED;
        upd.Google_Last_Sync__c = System.now();
        upd.Google_Sync_Error__c = warnings == null || warnings.isEmpty() ? null : 'Warning: ' + String.join(warnings, ' ');
    }

    private static void setDeleted(Interview_Day_Schedule__c upd, String calendarId) {
        upd.Google_Calendar_Id__c = calendarId;
        upd.Google_Event_Id__c = null;
        upd.Google_Sync_Status__c = STATUS_DELETED;
        upd.Google_Last_Sync__c = System.now();
        upd.Google_Sync_Error__c = null;
    }

    private static void setNotRequired(Interview_Day_Schedule__c upd) {
        upd.Google_Sync_Status__c = STATUS_NOT_REQUIRED;
        upd.Google_Sync_Error__c = null;
    }

    private static void setError(Interview_Day_Schedule__c upd, String message) {
        String safeMessage = String.isBlank(message) ? 'Unknown Google Calendar synchronization error.' : message;
        if (safeMessage.length() > 2000) {
            safeMessage = safeMessage.substring(0, 2000);
        }
        upd.Google_Sync_Status__c = STATUS_ERROR;
        upd.Google_Sync_Error__c = safeMessage;
    }
}