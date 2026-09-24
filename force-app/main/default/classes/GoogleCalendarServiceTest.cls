@IsTest
private class GoogleCalendarServiceTest {

    private class GoogleCalendarMock implements HttpCalloutMock {

        private Integer statusCode;
        private String responseBody;

        GoogleCalendarMock(
            Integer statusCode,
            String responseBody
        ) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest request) {

            String method = request.getMethod();
            String endpoint = request.getEndpoint();
            String body = request.getBody();

            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setHeader(
                'Content-Type',
                'application/json'
            );

            if (responseBody != null) {
                response.setBody(responseBody);
            }

            return response;
        }
    }

    private class CalendarTestException extends Exception {
    }

    private class ThrowingGoogleCalendarMock implements HttpCalloutMock {

        private String errorMessage;

        ThrowingGoogleCalendarMock(String errorMessage) {
            this.errorMessage = errorMessage;
        }

        public HttpResponse respond(HttpRequest request) {
            throw new CalendarTestException(errorMessage);
        }
    }

    @IsTest
    static void testCreateGoogleEvent() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                201,
                '{"id":"google_event_create_001"}'
            )
        );

        Test.startTest();

        System.enqueueJob(
            new GoogleCalendarSyncQueueable(
                schedule.Id,
                'UPSERT'
            )
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testCreateGoogleEventDirect() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                201,
                '{"id":"google_event_direct_001"}'
            )
        );

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testCreateWithAssignedVolunteer() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                201,
                '{"id":"google_event_volunteer_001"}'
            )
        );

        update new Interview_Day_Schedule__c(
            Id = schedule.Id,
            Assigned_Volunteer__c = UserInfo.getUserId()
        );

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testUpdateExistingGoogleEvent() {

        Interview_Day_Schedule__c schedule =
            createSchedule(true);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                200,
                '{"id":"existing_google_event_001"}'
            )
        );

        Test.startTest();

        System.enqueueJob(
            new GoogleCalendarSyncQueueable(
                schedule.Id,
                'UPSERT'
            )
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testUpdateExistingEventWithBlankResponseBody() {

        Interview_Day_Schedule__c schedule =
            createSchedule(true);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                200,
                null
            )
        );

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testCreateResponseWithoutEventId() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                201,
                '{}'
            )
        );

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testCreateResponseWithBlankBody() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                201,
                null
            )
        );

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testMalformedSuccessfulResponse() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                201,
                'not-valid-json'
            )
        );

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testDeleteGoogleEvent() {

        Interview_Day_Schedule__c schedule =
            createSchedule(true);

        update new Interview_Day_Schedule__c(
            Id = schedule.Id,
            Google_Sync_Status__c = 'Delete Pending'
        );

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                204,
                null
            )
        );

        Test.startTest();

        System.enqueueJob(
            new GoogleCalendarSyncQueueable(
                schedule.Id,
                'DELETE'
            )
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testDelete404() {

        Interview_Day_Schedule__c schedule =
            createSchedule(true);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                404,
                '{"error":{"message":"Event not found"}}'
            )
        );

        Test.startTest();

        GoogleCalendarService.deleteEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testDeleteWithoutGoogleEventId() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        Test.startTest();

        GoogleCalendarService.deleteEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testDeleteFailure() {

        Interview_Day_Schedule__c schedule =
            createSchedule(true);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                500,
                '{"error":{"message":"Delete failed"}}'
            )
        );

        Test.startTest();

        GoogleCalendarService.deleteEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testDeleteFailureInvalidJson() {

        Interview_Day_Schedule__c schedule =
            createSchedule(true);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                500,
                'not-valid-json'
            )
        );

        Test.startTest();

        GoogleCalendarService.deleteEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void test401Failure() {

        runFailureTest(
            401,
            'Unauthorized'
        );
    }

    @IsTest
    static void test403Failure() {

        runFailureTest(
            403,
            'Insufficient Permission'
        );
    }

    @IsTest
    static void test500Failure() {

        runFailureTest(
            500,
            'Internal Server Error'
        );
    }

    @IsTest
    static void test404UpdateFailure() {

        Interview_Day_Schedule__c schedule =
            createSchedule(true);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                404,
                '{"error":{"message":"Event not found"}}'
            )
        );

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testFailureResponseWithInvalidJson() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                500,
                'this-is-not-json'
            )
        );

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testLongGoogleErrorMessage() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        String longMessage = '';

        for (Integer index = 0; index < 2100; index++) {
            longMessage += 'X';
        }

        String responseBody =
            JSON.serialize(
                new Map<String, Object>{
                    'error' => new Map<String, Object>{
                        'message' => longMessage
                    }
                }
            );

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                500,
                responseBody
            )
        );

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testThrownCalloutException() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        String longMessage =
            'Mock callout failure line one\nline two ';

        for (Integer index = 0; index < 1600; index++) {
            longMessage += 'Z';
        }

        Test.setMock(
            HttpCalloutMock.class,
            new ThrowingGoogleCalendarMock(
                longMessage
            )
        );

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testMissingStartTime() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        update new Interview_Day_Schedule__c(
            Id = schedule.Id,
            Start_Time__c = null
        );

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testMissingEndTime() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        update new Interview_Day_Schedule__c(
            Id = schedule.Id,
            End_Time__c = null
        );

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testMissingInterviewDateWhenFieldAllowsNull() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        Schema.DescribeFieldResult dateField =
            Schema.SObjectType.Interview_Day_Schedule__c
                .fields.Interview_Date__c;

        if (
            dateField.isUpdateable()
            && dateField.isNillable()
        ) {
            Interview_Day_Schedule__c patch =
                new Interview_Day_Schedule__c(
                    Id = schedule.Id
                );

            patch.put(
                'Interview_Date__c',
                null
            );

            update patch;

            Test.startTest();

            GoogleCalendarService.upsertEvent(
                schedule.Id
            );

            Test.stopTest();

            touchSchedule(schedule.Id);
        }
    }

    @IsTest
    static void testNullServiceIds() {

        Test.startTest();

        GoogleCalendarService.upsertEvent(null);
        GoogleCalendarService.deleteEvent(null);

        Test.stopTest();
    }

    @IsTest
    static void testInvalidScheduleIdCatchPaths() {

        Id wrongObjectId =
            UserInfo.getUserId();

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            wrongObjectId
        );

        GoogleCalendarService.deleteEvent(
            wrongObjectId
        );

        Test.stopTest();
    }

    @IsTest
    static void testNullScheduleQueueable() {

        Test.startTest();

        System.enqueueJob(
            new GoogleCalendarSyncQueueable(
                null,
                'UPSERT'
            )
        );

        Test.stopTest();
    }

    @IsTest
    static void testBlankOperationQueueable() {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                201,
                '{"id":"google_event_blank_operation"}'
            )
        );

        Test.startTest();

        System.enqueueJob(
            new GoogleCalendarSyncQueueable(
                schedule.Id,
                null
            )
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    @IsTest
    static void testLowerCaseDeleteOperationQueueable() {

        Interview_Day_Schedule__c schedule =
            createSchedule(true);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                204,
                null
            )
        );

        Test.startTest();

        System.enqueueJob(
            new GoogleCalendarSyncQueueable(
                schedule.Id,
                'delete'
            )
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    private static void runFailureTest(
        Integer statusCode,
        String message
    ) {

        Interview_Day_Schedule__c schedule =
            createSchedule(false);

        Test.setMock(
            HttpCalloutMock.class,
            new GoogleCalendarMock(
                statusCode,
                '{"error":{"message":"' + message + '"}}'
            )
        );

        Test.startTest();

        GoogleCalendarService.upsertEvent(
            schedule.Id
        );

        Test.stopTest();

        touchSchedule(schedule.Id);
    }

    private static void touchSchedule(
        Id scheduleId
    ) {

        Interview_Day_Schedule__c refreshed = [
            SELECT Id,
                   Google_Event_Id__c,
                   Google_Calendar_Id__c,
                   Google_Sync_Status__c,
                   Google_Last_Sync__c,
                   Google_Sync_Error__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :scheduleId
            LIMIT 1
        ];

        String.valueOf(refreshed.Id);
        String.valueOf(refreshed.Google_Event_Id__c);
        String.valueOf(refreshed.Google_Calendar_Id__c);
        String.valueOf(refreshed.Google_Sync_Status__c);
        String.valueOf(refreshed.Google_Last_Sync__c);
        String.valueOf(refreshed.Google_Sync_Error__c);
    }

    private static Interview_Day_Schedule__c createSchedule(
        Boolean existingGoogleEvent
    ) {

        Zone__c zone = new Zone__c(
            Name = 'Google Calendar Test Zone '
                + String.valueOf(
                    DateTime.now().getTime()
                )
        );

        insert zone;

        Date interviewDate =
            Date.today().addDays(7);

        Interview_Day__c interviewDay =
            new Interview_Day__c(
                Zone__c = zone.Id,
                Interview_Date__c = interviewDate,
                Schedule_Mode__c = 'Morning',
                Total_Slots__c = 1
            );

        insert interviewDay;

        Interview_Day_Schedule__c schedule = [
            SELECT Id,
                   Name,
                   Interview_Day__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c = :interviewDay.Id
            LIMIT 1
        ];

        schedule.Start_Time__c =
            Time.newInstance(
                8,
                0,
                0,
                0
            );

        schedule.End_Time__c =
            Time.newInstance(
                8,
                30,
                0,
                0
            );

        schedule.Google_Sync_Status__c =
            'Pending';

        if (existingGoogleEvent) {

            HGH_Google_Calendar_Config__mdt config =
                getConfig();

            schedule.Google_Event_Id__c =
                'existing_google_event_001';

            schedule.Google_Calendar_Id__c =
                config.Calendar_Id__c;
        }

        update schedule;

        return schedule;
    }

    private static HGH_Google_Calendar_Config__mdt getConfig() {

        return HGH_Google_Calendar_Config__mdt.getInstance(
            'Default'
        );
    }
}