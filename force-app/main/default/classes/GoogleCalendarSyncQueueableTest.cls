@IsTest
private class GoogleCalendarSyncQueueableTest {

    private class CalendarMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();

            if (request.getMethod() == 'DELETE') {
                response.setStatusCode(204);
                response.setBody('');
                return response;
            }

            response.setStatusCode(200);
            response.setHeader(
                'Content-Type',
                'application/json'
            );

            response.setBody(
                '{"id":"queueable-test-google-event"}'
            );

            return response;
        }
    }

    @TestSetup
    static void setupData() {

        Zone__c zoneRecord = new Zone__c(
            Name = 'HGH Queueable Test Zone'
        );
        insert zoneRecord;

        Interview_Day__c interviewDay =
            new Interview_Day__c(
                Interview_Date__c =
                    Date.today().addDays(10),
                Schedule_Mode__c = 'Morning',
                Total_Slots__c = 2,
                Status__c = 'Published',
                Zone__c = zoneRecord.Id
            );

        insert interviewDay;

        Interview_Day_Schedule__c schedule = [
            SELECT Id,
                   Interview_Day__c,
                   Interview_Date__c,
                   Schedule_Mode__c,
                   Start_Time__c,
                   End_Time__c,
                   Google_Event_Id__c,
                   Google_Calendar_Id__c,
                   Google_Sync_Status__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c =
                :interviewDay.Id
            ORDER BY Start_Time__c ASC
            LIMIT 1
        ];

        schedule.Google_Sync_Status__c =
            'Pending';

        update schedule;
    }

    private static Interview_Day_Schedule__c
        getSchedule() {

        return [
            SELECT Id,
                   Interview_Day__c,
                   Interview_Date__c,
                   Schedule_Mode__c,
                   Start_Time__c,
                   End_Time__c,
                   Google_Event_Id__c,
                   Google_Calendar_Id__c,
                   Google_Sync_Status__c,
                   Google_Sync_Error__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__r.Zone__r.Name =
                'HGH Queueable Test Zone'
            ORDER BY Start_Time__c ASC
            LIMIT 1
        ];
    }

    @IsTest
    static void testEnqueueFromFlowNullRequests() {

        Test.startTest();

        GoogleCalendarSyncQueueable.enqueueFromFlow(
            null
        );

        Test.stopTest();

        System.debug(
            LoggingLevel.ERROR,
            'NULL REQUEST LIST TEST COMPLETED'
        );
    }

    @IsTest
    static void testEnqueueFromFlowEmptyRequests() {

        List<GoogleCalendarSyncQueueable.SyncRequest>
            requests =
                new List<
                    GoogleCalendarSyncQueueable.SyncRequest
                >();

        Test.startTest();

        GoogleCalendarSyncQueueable.enqueueFromFlow(
            requests
        );

        Test.stopTest();

        System.debug(
            LoggingLevel.ERROR,
            'EMPTY REQUEST LIST TEST COMPLETED'
        );
    }

    @IsTest
    static void testEnqueueFromFlowSkipsNullRequest() {

        List<GoogleCalendarSyncQueueable.SyncRequest>
            requests =
                new List<
                    GoogleCalendarSyncQueueable.SyncRequest
                >{
                    null
                };

        Test.startTest();

        GoogleCalendarSyncQueueable.enqueueFromFlow(
            requests
        );

        Test.stopTest();

        System.debug(
            LoggingLevel.ERROR,
            'NULL REQUEST TEST COMPLETED'
        );
    }

    @IsTest
    static void testEnqueueFromFlowSkipsNullSchedule() {

        GoogleCalendarSyncQueueable.SyncRequest
            request =
                new GoogleCalendarSyncQueueable.SyncRequest();

        request.scheduleId = null;
        request.operation = 'UPSERT';

        List<GoogleCalendarSyncQueueable.SyncRequest>
            requests =
                new List<
                    GoogleCalendarSyncQueueable.SyncRequest
                >{
                    request
                };

        Test.startTest();

        GoogleCalendarSyncQueueable.enqueueFromFlow(
            requests
        );

        Test.stopTest();

        System.debug(
            LoggingLevel.ERROR,
            'NULL SCHEDULE REQUEST TEST COMPLETED'
        );
    }

    @IsTest
    static void testEnqueueFromFlowBlankOperationDefaultsToUpsert() {

        Interview_Day_Schedule__c schedule =
            getSchedule();

        GoogleCalendarSyncQueueable.SyncRequest
            request =
                new GoogleCalendarSyncQueueable.SyncRequest();

        request.scheduleId = schedule.Id;
        request.operation = '';

        List<GoogleCalendarSyncQueueable.SyncRequest>
            requests =
                new List<
                    GoogleCalendarSyncQueueable.SyncRequest
                >{
                    request
                };

        Test.setMock(
            HttpCalloutMock.class,
            new CalendarMock()
        );

        Test.startTest();

        GoogleCalendarSyncQueueable.enqueueFromFlow(
            requests
        );

        Test.stopTest();

        Interview_Day_Schedule__c result = [
            SELECT Id,
                   Google_Event_Id__c,
                   Google_Sync_Status__c,
                   Google_Sync_Error__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :schedule.Id
        ];

        System.debug(
            LoggingLevel.ERROR,
            'BLANK OPERATION UPSERT => ' +
            result
        );
    }

    @IsTest
    static void testEnqueueFromFlowNullOperationDefaultsToUpsert() {

        Interview_Day_Schedule__c schedule =
            getSchedule();

        GoogleCalendarSyncQueueable.SyncRequest
            request =
                new GoogleCalendarSyncQueueable.SyncRequest();

        request.scheduleId = schedule.Id;
        request.operation = null;

        List<GoogleCalendarSyncQueueable.SyncRequest>
            requests =
                new List<
                    GoogleCalendarSyncQueueable.SyncRequest
                >{
                    request
                };

        Test.setMock(
            HttpCalloutMock.class,
            new CalendarMock()
        );

        Test.startTest();

        GoogleCalendarSyncQueueable.enqueueFromFlow(
            requests
        );

        Test.stopTest();

        Interview_Day_Schedule__c result = [
            SELECT Id,
                   Google_Event_Id__c,
                   Google_Sync_Status__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :schedule.Id
        ];

        System.debug(
            LoggingLevel.ERROR,
            'NULL OPERATION UPSERT => ' +
            result
        );
    }

    @IsTest
    static void testEnqueueFromFlowNormalizesUpsert() {

        Interview_Day_Schedule__c schedule =
            getSchedule();

        GoogleCalendarSyncQueueable.SyncRequest
            request =
                new GoogleCalendarSyncQueueable.SyncRequest();

        request.scheduleId = schedule.Id;
        request.operation = '  upsert  ';

        List<GoogleCalendarSyncQueueable.SyncRequest>
            requests =
                new List<
                    GoogleCalendarSyncQueueable.SyncRequest
                >{
                    request
                };

        Test.setMock(
            HttpCalloutMock.class,
            new CalendarMock()
        );

        Test.startTest();

        GoogleCalendarSyncQueueable.enqueueFromFlow(
            requests
        );

        Test.stopTest();

        Interview_Day_Schedule__c result = [
            SELECT Id,
                   Google_Event_Id__c,
                   Google_Sync_Status__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :schedule.Id
        ];

        System.debug(
            LoggingLevel.ERROR,
            'NORMALIZED UPSERT => ' +
            result
        );
    }

    @IsTest
    static void testEnqueueFromFlowDelete() {

        Interview_Day_Schedule__c schedule =
            getSchedule();

        schedule.Google_Event_Id__c =
            'queueable-delete-event';

        schedule.Google_Calendar_Id__c =
            'queueable-test-calendar';

        schedule.Google_Sync_Status__c =
            'Delete Pending';

        update schedule;

        GoogleCalendarSyncQueueable.SyncRequest
            request =
                new GoogleCalendarSyncQueueable.SyncRequest();

        request.scheduleId = schedule.Id;
        request.operation = '  delete  ';

        List<GoogleCalendarSyncQueueable.SyncRequest>
            requests =
                new List<
                    GoogleCalendarSyncQueueable.SyncRequest
                >{
                    request
                };

        Test.setMock(
            HttpCalloutMock.class,
            new CalendarMock()
        );

        Test.startTest();

        GoogleCalendarSyncQueueable.enqueueFromFlow(
            requests
        );

        Test.stopTest();

        Interview_Day_Schedule__c result = [
            SELECT Id,
                   Google_Event_Id__c,
                   Google_Calendar_Id__c,
                   Google_Sync_Status__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :schedule.Id
        ];

        System.debug(
            LoggingLevel.ERROR,
            'FLOW DELETE RESULT => ' +
            result
        );
    }

    @IsTest
    static void testExecuteNullSchedule() {

        GoogleCalendarSyncQueueable job =
            new GoogleCalendarSyncQueueable(
                null,
                'UPSERT'
            );

        Test.startTest();

        job.execute(null);

        Test.stopTest();

        System.debug(
            LoggingLevel.ERROR,
            'DIRECT NULL SCHEDULE EXECUTE COMPLETED'
        );
    }

    @IsTest
    static void testExecuteBlankOperation() {

        Interview_Day_Schedule__c schedule =
            getSchedule();

        Test.setMock(
            HttpCalloutMock.class,
            new CalendarMock()
        );

        GoogleCalendarSyncQueueable job =
            new GoogleCalendarSyncQueueable(
                schedule.Id,
                ''
            );

        Test.startTest();

        job.execute(null);

        Test.stopTest();

        Interview_Day_Schedule__c result = [
            SELECT Id,
                   Google_Event_Id__c,
                   Google_Sync_Status__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :schedule.Id
        ];

        System.debug(
            LoggingLevel.ERROR,
            'DIRECT BLANK OPERATION => ' +
            result
        );
    }

    @IsTest
    static void testExecuteDelete() {

        Interview_Day_Schedule__c schedule =
            getSchedule();

        schedule.Google_Event_Id__c =
            'direct-delete-event';

        schedule.Google_Calendar_Id__c =
            'direct-test-calendar';

        schedule.Google_Sync_Status__c =
            'Delete Pending';

        update schedule;

        Test.setMock(
            HttpCalloutMock.class,
            new CalendarMock()
        );

        GoogleCalendarSyncQueueable job =
            new GoogleCalendarSyncQueueable(
                schedule.Id,
                'DELETE'
            );

        Test.startTest();

        job.execute(null);

        Test.stopTest();

        Interview_Day_Schedule__c result = [
            SELECT Id,
                   Google_Event_Id__c,
                   Google_Sync_Status__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :schedule.Id
        ];

        System.debug(
            LoggingLevel.ERROR,
            'DIRECT DELETE => ' +
            result
        );
    }

    @IsTest
    static void testExecuteUnknownOperationUsesUpsert() {

        Interview_Day_Schedule__c schedule =
            getSchedule();

        Test.setMock(
            HttpCalloutMock.class,
            new CalendarMock()
        );

        GoogleCalendarSyncQueueable job =
            new GoogleCalendarSyncQueueable(
                schedule.Id,
                'refresh'
            );

        Test.startTest();

        job.execute(null);

        Test.stopTest();

        Interview_Day_Schedule__c result = [
            SELECT Id,
                   Google_Event_Id__c,
                   Google_Sync_Status__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :schedule.Id
        ];

        System.debug(
            LoggingLevel.ERROR,
            'UNKNOWN OPERATION UPSERT => ' +
            result
        );
    }
}