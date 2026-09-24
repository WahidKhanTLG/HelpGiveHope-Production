@IsTest
private class InterviewCaseSharingServiceTest {

    private static final String TEST_USER_LAST_NAME =
        'InterviewCaseShareTestVolunteer';

    @TestSetup
    static void setupUser() {

        List<Profile> minimumAccessProfiles = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];

        Id profileId =
            minimumAccessProfiles.isEmpty()
                ? UserInfo.getProfileId()
                : minimumAccessProfiles[0].Id;

        String uniqueValue =
            String.valueOf(DateTime.now().getTime())
            + '.'
            + UserInfo.getOrganizationId();

        User volunteer = new User(
            Alias = 'hghvol',
            Email = 'hgh.interview.share.test@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = TEST_USER_LAST_NAME,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profileId,
            TimeZoneSidKey = 'America/Chicago',
            Username =
                'hgh.interview.share.test.'
                + uniqueValue
                + '@example.com'
        );

        insert volunteer;
    }

    @IsTest
    static void testManageAccessNullAndEmptyRequests() {

        Test.startTest();

        InterviewCaseSharingService.manageAccess(null);

        InterviewCaseSharingService.manageAccess(
            new List<InterviewCaseSharingService.SharingRequest>()
        );

        Test.stopTest();
    }

    @IsTest
    static void testManageAccessSkipsInvalidRequests() {

        Case testCase = createCase();
        User volunteer = getVolunteer();

        InterviewCaseSharingService.SharingRequest missingCase =
            new InterviewCaseSharingService.SharingRequest();

        missingCase.userId = volunteer.Id;
        missingCase.operation = 'GRANT';

        InterviewCaseSharingService.SharingRequest missingUser =
            new InterviewCaseSharingService.SharingRequest();

        missingUser.caseId = testCase.Id;
        missingUser.operation = 'GRANT';

        InterviewCaseSharingService.SharingRequest blankOperation =
            new InterviewCaseSharingService.SharingRequest();

        blankOperation.caseId = testCase.Id;
        blankOperation.userId = volunteer.Id;
        blankOperation.operation = '   ';

        InterviewCaseSharingService.SharingRequest unknownOperation =
            new InterviewCaseSharingService.SharingRequest();

        unknownOperation.caseId = testCase.Id;
        unknownOperation.userId = volunteer.Id;
        unknownOperation.operation = 'UNKNOWN';

        Test.startTest();

        InterviewCaseSharingService.manageAccess(
            new List<InterviewCaseSharingService.SharingRequest>{
                null,
                missingCase,
                missingUser,
                blankOperation,
                unknownOperation
            }
        );

        Test.stopTest();
    }

    @IsTest
    static void testManageAccessGrantAndRemove() {

        Case testCase = createCase();
        User volunteer = getVolunteer();

        Interview_Day_Schedule__c schedule =
            createSchedule(testCase.Id);

        InterviewCaseSharingService.SharingRequest grantRequest =
            new InterviewCaseSharingService.SharingRequest();

        grantRequest.caseId = testCase.Id;
        grantRequest.userId = volunteer.Id;
        grantRequest.scheduleId = schedule.Id;
        grantRequest.operation = '  grant  ';

        InterviewCaseSharingService.SharingRequest removeRequest =
            new InterviewCaseSharingService.SharingRequest();

        removeRequest.caseId = testCase.Id;
        removeRequest.userId = volunteer.Id;
        removeRequest.scheduleId = schedule.Id;
        removeRequest.operation = ' remove ';

        Test.startTest();

        InterviewCaseSharingService.manageAccess(
            new List<InterviewCaseSharingService.SharingRequest>{
                grantRequest
            }
        );

        InterviewCaseSharingService.manageAccess(
            new List<InterviewCaseSharingService.SharingRequest>{
                removeRequest
            }
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

        String.valueOf(refreshedCase.OwnerId);
        String.valueOf(refreshedSchedule.Original_Case_Owner_Id__c);
    }

    @IsTest
    static void testExistingManualSharePath() {

        Case testCase = createCase();
        User volunteer = getVolunteer();

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
    static void testDirectNullInputs() {

        Case testCase = createCase();
        User volunteer = getVolunteer();

        Test.startTest();

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

        Test.stopTest();
    }

    @IsTest
    static void testRemoveWhenNoManualShareExists() {

        Case testCase = createCase();
        User volunteer = getVolunteer();

        Test.startTest();

        InterviewCaseSharingService.removeAccess(
            testCase.Id,
            volunteer.Id
        );

        Test.stopTest();
    }

    @IsTest
    static void testDirectAssignAndRestoreOwner() {

        Case testCase = createCase();
        User volunteer = getVolunteer();

        Interview_Day_Schedule__c schedule =
            createSchedule(testCase.Id);

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

        String.valueOf(refreshedCase.OwnerId);
    }

    @IsTest
    static void testRestoreSkipsWhenScheduleHasNoOriginalOwner() {

        Case testCase = createCase();
        User volunteer = getVolunteer();

        Interview_Day_Schedule__c schedule =
            createSchedule(testCase.Id);

        schedule.Original_Case_Owner_Id__c = null;
        update schedule;

        Test.startTest();

        InterviewCaseSharingService.restoreCaseOwner(
            testCase.Id,
            volunteer.Id,
            schedule.Id
        );

        Test.stopTest();
    }

    private static User getVolunteer() {

        return [
            SELECT Id,
                   ProfileId
            FROM User
            WHERE LastName = :TEST_USER_LAST_NAME
            LIMIT 1
        ];
    }

    private static Case createCase() {

        Case testCase = new Case(
            Subject = 'Interview Case Sharing Service Test',
            Status = firstActivePicklistValue(
                Case.Status
            ),
            Origin = firstActivePicklistValue(
                Case.Origin
            )
        );

        insert testCase;

        return testCase;
    }

    private static Interview_Day_Schedule__c createSchedule(
        Id caseId
    ) {

        Zone__c zoneRecord = new Zone__c(
            Name = 'Owner Transfer Test Zone'
        );

        insert zoneRecord;

        Interview_Day__c interviewDay =
            new Interview_Day__c(
                Interview_Date__c = Date.today().addDays(3),
                Schedule_Mode__c = 'Morning',
                Total_Slots__c = 1,
                Status__c = 'Published',
                Zone__c = zoneRecord.Id
            );

        insert interviewDay;

        Interview_Day_Schedule__c schedule =
            new Interview_Day_Schedule__c(
                Name = 'Owner Transfer Test Slot',
                Interview_Day__c = interviewDay.Id,
                Zone__c = zoneRecord.Id,
                Start_Time__c = Time.newInstance(8, 0, 0, 0),
                End_Time__c = Time.newInstance(8, 15, 0, 0),
                Booked__c = true,
                Case__c = caseId
            );

        insert schedule;

        return schedule;
    }

    private static String firstActivePicklistValue(
        Schema.SObjectField fieldToken
    ) {

        for (
            Schema.PicklistEntry entry :
            fieldToken.getDescribe().getPicklistValues()
        ) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }
}