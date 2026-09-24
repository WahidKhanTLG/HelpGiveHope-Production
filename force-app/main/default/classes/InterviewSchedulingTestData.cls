/**
 * Test data and configuration helpers shared by the interview scheduling tests.
 * Custom metadata cannot be inserted in tests, so both settings classes are injected here.
 */
@IsTest
public class InterviewSchedulingTestData {

    public static GoogleCalendarSettings googleSettings(Boolean placeholders) {
        GoogleCalendarSettings settings = new GoogleCalendarSettings();
        settings.recordFound = true;
        settings.enabled = true;
        settings.calendarId = 'test-calendar@group.calendar.google.com';
        settings.timeZone = 'America/Chicago';
        settings.eventTitlePattern = 'HGH Home Interview - {CaseNumber}';
        settings.sendUpdates = 'all';
        settings.placeholderSyncEnabled = placeholders;
        settings.availableTitlePattern = 'Available - {ZoneName} {Mode} - Slot {Slot}';
        settings.availableColorId = '2';
        settings.bookedColorId = '11';
        settings.inviteApplicant = true;
        settings.inviteVolunteer = true;
        settings.includeHouseholdAddress = false;
        settings.syncBatchSize = 40;
        settings.sweepIntervalMinutes = 5;
        GoogleCalendarSettings.instanceOverride = settings;
        return settings;
    }

    public static InterviewSelfServiceConfig selfServiceConfig(Integer cutoffHours, Integer maxReschedules) {
        InterviewSelfServiceConfig cfg = new InterviewSelfServiceConfig();
        cfg.recordFound = true;
        cfg.enabled = true;
        cfg.autoSendLinkOnBooking = true;
        cfg.sendConfirmationOnChange = true;
        cfg.enforceSingleInterviewPerTime = false;
        cfg.rescheduleCutoffHours = cutoffHours;
        cfg.maxReschedules = maxReschedules;
        cfg.tokenValidityDays = 45;
        cfg.daysAheadVisible = 90;
        cfg.siteBaseUrl = 'https://example.my.site.com/Christmas/s/interview';
        cfg.orgWideEmailDisplayName = 'Help Give Hope Support';
        cfg.supportPhone = '555-0100';
        InterviewSelfServiceConfig.instanceOverride = cfg;
        return cfg;
    }

    public static Zone__c createZone(String name, String code, String mode) {
        Zone__c zone = new Zone__c(Name = name, Active__c = true, Schedule_Mode__c = mode);
        insert zone;
        insert new HGH_Zone_Code__c(Zone__c = zone.Id, Code__c = code, Name = code, Active__c = true);
        return zone;
    }

    public static User createVolunteer() {
        Profile profile = [SELECT Id FROM Profile WHERE Name = 'Standard User' OR Name = 'System Administrator' ORDER BY Name DESC LIMIT 1];
        String unique = 'vol' + Datetime.now().getTime() + Math.round(Math.random() * 1000) + '@hgh-test.org';
        User volunteer = new User(
            Alias = 'hghvol',
            Email = unique,
            EmailEncodingKey = 'UTF-8',
            FirstName = 'Val',
            LastName = 'Volunteer',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'America/Chicago',
            UserName = unique,
            IsActive = true
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert volunteer;
        }
        return volunteer;
    }

    public static Account createHousehold(String name, String censusTract) {
        Account household = new Account(
            Name = name,
            Census_Tract__c = censusTract,
            BillingStreet = '1 Test St',
            BillingCity = 'Springfield',
            BillingState = 'MO',
            BillingPostalCode = '65801'
        );
        insert household;
        return household;
    }

    public static Contact createContact(Account household, String firstName, String email) {
        Contact contact = new Contact(
            AccountId = household.Id,
            FirstName = firstName,
            LastName = 'Applicant',
            Email = email
        );
        insert contact;
        return contact;
    }

    public static Case createApplication(Account household, Contact contact) {
        Case application = new Case(
            Subject = 'Test application',
            AccountId = household.Id,
            ContactId = contact == null ? null : contact.Id,
            Status = 'New'
        );
        insert application;
        return application;
    }

    /** Inserts an Interview Day; InterviewDaysTrigger creates the slots. */
    public static Interview_Day__c createInterviewDay(Zone__c zone, Date interviewDate, String mode, Integer totalSlots, String status) {
        String zoneName = zone.isSet('Name') ? zone.Name : [SELECT Name FROM Zone__c WHERE Id = :zone.Id].Name;
        Interview_Day__c day = new Interview_Day__c(
            Zone__c = zone.Id,
            Zone_Name__c = zoneName,
            Interview_Date__c = interviewDate,
            Schedule_Mode__c = mode,
            Total_Slots__c = totalSlots,
            Status__c = status,
            Year__c = interviewDate.year()
        );
        insert day;
        return day;
    }

    public static List<Interview_Day_Schedule__c> slotsFor(Id interviewDayId) {
        return [
            SELECT Id, Name, Booked__c, Case__c, Assigned_Volunteer__c, Status__c, Assignment_Status__c,
                   Start_Time__c, End_Time__c, Start_Time_Text__c, End_Time_Text__c,
                   Google_Sync_Status__c, Google_Event_Id__c, Google_Calendar_Id__c,
                   Google_Sync_Error__c, Original_Case_Owner_Id__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c = :interviewDayId
            ORDER BY Start_Time__c ASC
        ];
    }

    public static Interview_Day_Schedule__c slot(Id scheduleId) {
        return [
            SELECT Id, Name, Booked__c, Case__c, Assigned_Volunteer__c, Status__c, Assignment_Status__c,
                   Start_Time__c, End_Time__c, Start_Time_Text__c, End_Time_Text__c,
                   Google_Sync_Status__c, Google_Event_Id__c, Google_Calendar_Id__c,
                   Google_Sync_Error__c, Original_Case_Owner_Id__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :scheduleId
        ];
    }

    /**
     * HTTP mock for the Google Calendar API. Default behaviour: lookup finds nothing, POST returns a new
     * id, PATCH echoes the id from the URL, DELETE succeeds. mode switches to failure behaviours.
     */
    public class GoogleMock implements HttpCalloutMock {
        public String mode = 'ok';          // ok | rateLimit | badRequest | patchGone | timeout
        public String existingEventId;      // returned by the lookup when set
        public Integer created = 0;
        public List<HttpRequest> requests = new List<HttpRequest>();

        public HttpResponse respond(HttpRequest request) {
            requests.add(request);
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            String endpoint = request.getEndpoint();
            String method = request.getMethod();

            if (mode == 'timeout') {
                throw new CalloutException('Read timed out');
            }
            if (mode == 'rateLimit') {
                response.setStatusCode(429);
                response.setBody('{"error":{"code":429,"message":"Rate Limit Exceeded","errors":[{"reason":"rateLimitExceeded"}]}}');
                return response;
            }
            if (mode == 'badRequest' && (method == 'POST' || method == 'PATCH')) {
                response.setStatusCode(400);
                response.setBody('{"error":{"code":400,"message":"Invalid attendee email"}}');
                return response;
            }

            if (method == 'GET' && endpoint.contains('privateExtendedProperty')) {
                response.setStatusCode(200);
                response.setBody(String.isBlank(existingEventId)
                    ? '{"items":[]}'
                    : '{"items":[{"id":"' + existingEventId + '","status":"confirmed"}]}');
                return response;
            }
            if (method == 'POST') {
                created++;
                response.setStatusCode(200);
                response.setBody('{"id":"evt-' + created + '"}');
                return response;
            }
            if (method == 'PATCH') {
                if (mode == 'patchGone') {
                    response.setStatusCode(404);
                    response.setBody('{"error":{"code":404,"message":"Not Found"}}');
                    return response;
                }
                String path = endpoint.substringBefore('?');
                String patchedId = path.substringAfterLast('/');
                response.setStatusCode(200);
                response.setBody('{"id":"' + patchedId + '"}');
                return response;
            }
            if (method == 'DELETE') {
                response.setStatusCode(204);
                response.setBody('');
                return response;
            }
            response.setStatusCode(500);
            response.setBody('{"error":{"message":"unexpected"}}');
            return response;
        }
    }
}