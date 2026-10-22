@IsTest
private class InterviewCaseSharingServiceTest {

    private static final String VOLUNTEER_A_LAST_NAME =
        'HGHShareVolunteerA';

    private static final String VOLUNTEER_B_LAST_NAME =
        'HGHShareVolunteerB';

    @TestSetup
    static void setupUsers() {

        Id profileId =
            UserInfo.getProfileId();

        String uniqueValue =
            String.valueOf(
                DateTime.now().getTime()
            );

        User volunteerA =
            new User(
                Alias = 'hghvola',
                Email =
                    'hgh.share.volunteer.a@example.com',
                EmailEncodingKey = 'UTF-8',
                LastName =
                    VOLUNTEER_A_LAST_NAME,
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = profileId,
                TimeZoneSidKey =
                    'America/Chicago',
                Username =
                    'hgh.share.volunteer.a.'
                    + uniqueValue
                    + '@example.com'
            );

        User volunteerB =
            new User(
                Alias = 'hghvolb',
                Email =
                    'hgh.share.volunteer.b@example.com',
                EmailEncodingKey = 'UTF-8',
                LastName =
                    VOLUNTEER_B_LAST_NAME,
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = profileId,
                TimeZoneSidKey =
                    'America/Chicago',
                Username =
                    'hgh.share.volunteer.b.'
                    + uniqueValue
                    + '@example.com'
            );

        insert new List<User>{
            volunteerA,
            volunteerB
        };
    }

    @IsTest
    static void testNullAndEmptyRequests() {

        Test.startTest();

        InterviewCaseSharingService.manageAccess(
            null
        );

        InterviewCaseSharingService.manageAccess(
            new List<
                InterviewCaseSharingService.SharingRequest
            >()
        );

        Test.stopTest();
    }

    @IsTest
    static void testInvalidRequestsAreIgnored() {

        Case testCase =
            createCases(1)[0];

        User volunteer =
            getVolunteerA();

        InterviewCaseSharingService.SharingRequest missingCase =
            new InterviewCaseSharingService.SharingRequest();

        missingCase.userId =
            volunteer.Id;

        missingCase.operation =
            'GRANT';

        InterviewCaseSharingService.SharingRequest missingUser =
            new InterviewCaseSharingService.SharingRequest();

        missingUser.caseId =
            testCase.Id;

        missingUser.operation =
            'GRANT';

        InterviewCaseSharingService.SharingRequest blankOperation =
            new InterviewCaseSharingService.SharingRequest();

        blankOperation.caseId =
            testCase.Id;

        blankOperation.userId =
            volunteer.Id;

        blankOperation.operation =
            '   ';

        InterviewCaseSharingService.SharingRequest invalidOperation =
            new InterviewCaseSharingService.SharingRequest();

        invalidOperation.caseId =
            testCase.Id;

        invalidOperation.userId =
            volunteer.Id;

        invalidOperation.operation =
            'INVALID';

        Test.startTest();

        InterviewCaseSharingService.manageAccess(
            new List<
                InterviewCaseSharingService.SharingRequest
            >{
                null,
                missingCase,
                missingUser,
                blankOperation,
                invalidOperation
            }
        );

        Test.stopTest();
    }

    @IsTest
static void testSingleGrantAndRemoveStillWorks() {

    Case testCase =
        createCases(1)[0];

    Interview_Day_Schedule__c schedule =
        createSchedules(
            new List<Case>{
                testCase
            }
        )[0];

    User volunteer =
        getVolunteerA();

    InterviewCaseSharingService.SharingRequest grantRequest =
        createRequest(
            testCase.Id,
            volunteer.Id,
            schedule.Id,
            ' grant '
        );

    InterviewCaseSharingService.SharingRequest removeRequest =
        createRequest(
            testCase.Id,
            volunteer.Id,
            schedule.Id,
            ' remove '
        );

    Test.startTest();

    InterviewCaseSharingService.manageAccess(
        new List<
            InterviewCaseSharingService.SharingRequest
        >{
            grantRequest
        }
    );

    InterviewCaseSharingService.manageAccess(
        new List<
            InterviewCaseSharingService.SharingRequest
        >{
            removeRequest
        }
    );

    Test.stopTest();

    Case restoredCase = [
        SELECT Id,
               OwnerId
        FROM Case
        WHERE Id = :testCase.Id
        LIMIT 1
    ];

    Interview_Day_Schedule__c restoredSchedule = [
        SELECT Id,
               Original_Case_Owner_Id__c
        FROM Interview_Day_Schedule__c
        WHERE Id = :schedule.Id
        LIMIT 1
    ];

    System.debug(
        'Restored Case Owner: ' +
        restoredCase.OwnerId
    );

    System.debug(
        'Original Case Owner after remove: ' +
        restoredSchedule.Original_Case_Owner_Id__c
    );
}

    @IsTest
    static void testBulkGrantTwentyInterviews() {

        List<Case> cases =
            createCases(20);

        List<Interview_Day_Schedule__c> schedules =
            createSchedules(cases);

        User volunteer =
            getVolunteerA();

        List<
            InterviewCaseSharingService.SharingRequest
        > requests =
            new List<
                InterviewCaseSharingService.SharingRequest
            >();

        for (
            Integer index = 0;
            index < cases.size();
            index++
        ) {

            requests.add(
                createRequest(
                    cases[index].Id,
                    volunteer.Id,
                    schedules[index].Id,
                    'GRANT'
                )
            );
        }

        Test.startTest();

        InterviewCaseSharingService.manageAccess(
            requests
        );

        Test.stopTest();

        Set<Id> caseIds =
            new Map<Id, Case>(
                cases
            ).keySet();

        Set<Id> scheduleIds =
            new Map<
                Id,
                Interview_Day_Schedule__c
            >(
                schedules
            ).keySet();

        List<Case> updatedCases = [
            SELECT Id,
                   OwnerId
            FROM Case
            WHERE Id IN :caseIds
        ];

        List<Interview_Day_Schedule__c> updatedSchedules = [
            SELECT Id,
                   Original_Case_Owner_Id__c
            FROM Interview_Day_Schedule__c
            WHERE Id IN :scheduleIds
        ];

        for (Case caseRecord : updatedCases) {

            System.debug(
                'Bulk grant Case: '
                + caseRecord.Id
                + ' Owner: '
                + caseRecord.OwnerId
            );
        }

        for (
            Interview_Day_Schedule__c schedule :
            updatedSchedules
        ) {

            System.debug(
                'Bulk grant Schedule: '
                + schedule.Id
                + ' Original Owner: '
                + schedule.Original_Case_Owner_Id__c
            );
        }
    }

    @IsTest
    static void testBulkReassignTwentyInterviews() {

        List<Case> cases =
            createCases(20);

        List<Interview_Day_Schedule__c> schedules =
            createSchedules(cases);

        User volunteerA =
            getVolunteerA();

        User volunteerB =
            getVolunteerB();

        List<
            InterviewCaseSharingService.SharingRequest
        > initialGrantRequests =
            new List<
                InterviewCaseSharingService.SharingRequest
            >();

        for (
            Integer index = 0;
            index < cases.size();
            index++
        ) {

            initialGrantRequests.add(
                createRequest(
                    cases[index].Id,
                    volunteerA.Id,
                    schedules[index].Id,
                    'GRANT'
                )
            );
        }

        /*
         * Initial assignment before the actual bulk reassignment.
         */
        InterviewCaseSharingService.manageAccess(
            initialGrantRequests
        );

        List<
            InterviewCaseSharingService.SharingRequest
        > reassignmentRequests =
            new List<
                InterviewCaseSharingService.SharingRequest
            >();

        for (
            Integer index = 0;
            index < cases.size();
            index++
        ) {

            reassignmentRequests.add(
                createRequest(
                    cases[index].Id,
                    volunteerA.Id,
                    schedules[index].Id,
                    'REMOVE'
                )
            );

            reassignmentRequests.add(
                createRequest(
                    cases[index].Id,
                    volunteerB.Id,
                    schedules[index].Id,
                    'GRANT'
                )
            );
        }

        Test.startTest();

        /*
         * 20 interviews generate 40 sharing operations:
         * 20 REMOVE + 20 GRANT.
         */
        InterviewCaseSharingService.manageAccess(
            reassignmentRequests
        );

        Test.stopTest();

        Set<Id> caseIds =
            new Map<Id, Case>(
                cases
            ).keySet();

        Set<Id> scheduleIds =
            new Map<
                Id,
                Interview_Day_Schedule__c
            >(
                schedules
            ).keySet();

        List<Case> reassignedCases = [
            SELECT Id,
                   OwnerId
            FROM Case
            WHERE Id IN :caseIds
        ];

        List<Interview_Day_Schedule__c> reassignedSchedules = [
            SELECT Id,
                   Original_Case_Owner_Id__c
            FROM Interview_Day_Schedule__c
            WHERE Id IN :scheduleIds
        ];

        for (Case caseRecord : reassignedCases) {

            System.debug(
                'Reassigned Case: '
                + caseRecord.Id
                + ' Owner: '
                + caseRecord.OwnerId
            );
        }

        for (
            Interview_Day_Schedule__c schedule :
            reassignedSchedules
        ) {

            System.debug(
                'Reassigned Schedule: '
                + schedule.Id
                + ' Original Owner: '
                + schedule.Original_Case_Owner_Id__c
            );
        }
    }

    @IsTest
    static void testDirectAssignAndRestoreMethodsStillWork() {

        Case testCase =
            createCases(1)[0];

        Interview_Day_Schedule__c schedule =
            createSchedules(
                new List<Case>{
                    testCase
                }
            )[0];

        User volunteer =
            getVolunteerA();

        Test.startTest();

        InterviewCaseSharingService.assignCaseOwner(
            testCase.Id,
            volunteer.Id,
            schedule.Id
        );

        InterviewCaseSharingService.restoreCaseOwner(
            testCase.Id,
            volunteer.Id,
            schedule.Id
        );

        Test.stopTest();

        Case refreshedCase = [
            SELECT Id,
                   OwnerId
            FROM Case
            WHERE Id = :testCase.Id
            LIMIT 1
        ];

        Interview_Day_Schedule__c refreshedSchedule = [
            SELECT Id,
                   Original_Case_Owner_Id__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :schedule.Id
            LIMIT 1
        ];

        System.debug(
            refreshedCase.OwnerId
        );

        System.debug(
            refreshedSchedule.Original_Case_Owner_Id__c
        );
    }

    @IsTest
    static void testLegacyManualShareMethodsStillWork() {

        Case testCase =
            createCases(1)[0];

        User volunteer =
            getVolunteerA();

        Test.startTest();

        InterviewCaseSharingService.grantAccess(
            testCase.Id,
            volunteer.Id
        );

        InterviewCaseSharingService.removeAccess(
            testCase.Id,
            volunteer.Id
        );

        Test.stopTest();
    }

    @IsTest
    static void testManageAccessWithoutScheduleStillWorks() {

        Case testCase =
            createCases(1)[0];

        User volunteer =
            getVolunteerA();

        InterviewCaseSharingService.SharingRequest grantRequest =
            createRequest(
                testCase.Id,
                volunteer.Id,
                null,
                'GRANT'
            );

        InterviewCaseSharingService.SharingRequest removeRequest =
            createRequest(
                testCase.Id,
                volunteer.Id,
                null,
                'REMOVE'
            );

        Test.startTest();

        InterviewCaseSharingService.manageAccess(
            new List<
                InterviewCaseSharingService.SharingRequest
            >{
                grantRequest
            }
        );

        InterviewCaseSharingService.manageAccess(
            new List<
                InterviewCaseSharingService.SharingRequest
            >{
                removeRequest
            }
        );

        Test.stopTest();
    }

    @IsTest
    static void testRestoreWhenNoOriginalOwner() {

        Case testCase =
            createCases(1)[0];

        Interview_Day_Schedule__c schedule =
            createSchedules(
                new List<Case>{
                    testCase
                }
            )[0];

        User volunteer =
            getVolunteerA();

        schedule.Original_Case_Owner_Id__c =
            null;

        update schedule;

        Test.startTest();

        InterviewCaseSharingService.restoreCaseOwner(
            testCase.Id,
            volunteer.Id,
            schedule.Id
        );

        Test.stopTest();
    }

    @IsTest
    static void testNullDirectMethodInputs() {

        User volunteer =
            getVolunteerA();

        Case testCase =
            createCases(1)[0];

        Test.startTest();

        InterviewCaseSharingService.assignCaseOwner(
            null,
            volunteer.Id,
            null
        );

        InterviewCaseSharingService.restoreCaseOwner(
            null,
            volunteer.Id,
            null
        );

        InterviewCaseSharingService.grantAccess(
            null,
            volunteer.Id
        );

        InterviewCaseSharingService.grantAccess(
            testCase.Id,
            null
        );

        InterviewCaseSharingService.removeAccess(
            null,
            volunteer.Id
        );

        InterviewCaseSharingService.removeAccess(
            testCase.Id,
            null
        );

        Test.stopTest();
    }

    private static InterviewCaseSharingService.SharingRequest createRequest(
        Id caseId,
        Id userId,
        Id scheduleId,
        String operation
    ) {

        InterviewCaseSharingService.SharingRequest request =
            new InterviewCaseSharingService.SharingRequest();

        request.caseId =
            caseId;

        request.userId =
            userId;

        request.scheduleId =
            scheduleId;

        request.operation =
            operation;

        return request;
    }

    private static User getVolunteerA() {

        return [
            SELECT Id,
                   ProfileId
            FROM User
            WHERE LastName =
                :VOLUNTEER_A_LAST_NAME
            LIMIT 1
        ];
    }

    private static User getVolunteerB() {

        return [
            SELECT Id,
                   ProfileId
            FROM User
            WHERE LastName =
                :VOLUNTEER_B_LAST_NAME
            LIMIT 1
        ];
    }

    private static List<Case> createCases(
        Integer count
    ) {

        List<Case> cases =
            new List<Case>();

        String caseStatus =
            firstActivePicklistValue(
                Case.Status
            );

        String caseOrigin =
            firstActivePicklistValue(
                Case.Origin
            );

        for (
            Integer index = 0;
            index < count;
            index++
        ) {

            cases.add(
                new Case(
                    Subject =
                        'Interview Sharing Test '
                        + index,
                    Status = caseStatus,
                    Origin = caseOrigin
                )
            );
        }

        insert cases;

        return cases;
    }

    private static List<Interview_Day_Schedule__c> createSchedules(
        List<Case> cases
    ) {

        Zone__c zoneRecord =
            new Zone__c(
                Name =
                    'Bulk Sharing Test Zone '
                    + DateTime.now().getTime()
            );

        insert zoneRecord;

        String scheduleMode =
            firstActivePicklistValue(
                Interview_Day__c.Schedule_Mode__c
            );

        String interviewDayStatus =
            firstActivePicklistValue(
                Interview_Day__c.Status__c
            );

        Interview_Day__c interviewDay =
            new Interview_Day__c(
                Interview_Date__c =
                    Date.today().addDays(5),
                Schedule_Mode__c =
                    scheduleMode,
                Total_Slots__c =
                    cases.size(),
                Status__c =
                    interviewDayStatus,
                Zone__c =
                    zoneRecord.Id
            );

        insert interviewDay;

        List<Interview_Day_Schedule__c> schedules =
            new List<Interview_Day_Schedule__c>();

        for (
            Integer index = 0;
            index < cases.size();
            index++
        ) {

            Integer startMinutes =
                (8 * 60) +
                (index * 15);

            Integer endMinutes =
                startMinutes + 15;

            Time startTime =
                Time.newInstance(
                    startMinutes / 60,
                    Math.mod(
                        startMinutes,
                        60
                    ),
                    0,
                    0
                );

            Time endTime =
                Time.newInstance(
                    endMinutes / 60,
                    Math.mod(
                        endMinutes,
                        60
                    ),
                    0,
                    0
                );

            schedules.add(
                new Interview_Day_Schedule__c(
                    Name =
                        'Bulk Sharing Slot '
                        + index,
                    Interview_Day__c =
                        interviewDay.Id,
                    Zone__c =
                        zoneRecord.Id,
                    Start_Time__c =
                        startTime,
                    End_Time__c =
                        endTime,
                    Booked__c =
                        true,
                    Case__c =
                        cases[index].Id
                )
            );
        }

        insert schedules;

        return schedules;
    }

    private static String firstActivePicklistValue(
        Schema.SObjectField fieldToken
    ) {

        for (
            Schema.PicklistEntry entry :
            fieldToken
                .getDescribe()
                .getPicklistValues()
        ) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }
}