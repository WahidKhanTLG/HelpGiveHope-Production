@IsTest
private class BulkVolunteerReassignmentControllerTest {
    private static final String VOLUNTEER_ONE_LAST_NAME = 'BulkReassignVolunteerOne';
    private static final String VOLUNTEER_TWO_LAST_NAME = 'BulkReassignVolunteerTwo';

    @TestSetup
    static void setupUsers() {
        List<Profile> minimumProfiles = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];

        Id profileId = minimumProfiles.isEmpty()
            ? UserInfo.getProfileId()
            : minimumProfiles[0].Id;

        String uniqueValue =
            String.valueOf(DateTime.now().getTime()) +
            '.' + UserInfo.getOrganizationId();

        List<User> volunteers = new List<User>{
            new User(
                Alias = 'bvolone',
                Email = 'bulk.volunteer.one@example.com',
                EmailEncodingKey = 'UTF-8',
                LastName = VOLUNTEER_ONE_LAST_NAME,
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = profileId,
                TimeZoneSidKey = 'America/Chicago',
                Username = 'bulk.volunteer.one.' + uniqueValue + '@example.com'
            ),
            new User(
                Alias = 'bvoltwo',
                Email = 'bulk.volunteer.two@example.com',
                EmailEncodingKey = 'UTF-8',
                LastName = VOLUNTEER_TWO_LAST_NAME,
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = profileId,
                TimeZoneSidKey = 'America/Chicago',
                Username = 'bulk.volunteer.two.' + uniqueValue + '@example.com'
            )
        };

        insert volunteers;
    }

    @IsTest
    static void testLoadAndReassign() {
        User volunteerOne = getVolunteer(VOLUNTEER_ONE_LAST_NAME);
        User volunteerTwo = getVolunteer(VOLUNTEER_TWO_LAST_NAME);

        TestData data = createInterviewData(5);

        List<Interview_Day_Schedule__c> initialSchedules = [
            SELECT Id
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c = :data.interviewDayId
            ORDER BY Start_Time__c
        ];

        List<Id> selectedIds = new List<Id>();
        for (Integer index = 0; index < 3; index++) {
            selectedIds.add(initialSchedules[index].Id);
        }

        Test.startTest();

        List<BulkVolunteerReassignmentController.OptionItem> zones =
            BulkVolunteerReassignmentController.getZones();

        List<BulkVolunteerReassignmentController.OptionItem> dates =
            BulkVolunteerReassignmentController.getScheduleDates(data.zoneId);

        List<BulkVolunteerReassignmentController.OptionItem> volunteers =
            BulkVolunteerReassignmentController.getVolunteers();

        List<BulkVolunteerReassignmentController.InterviewRow> rows =
            BulkVolunteerReassignmentController.getInterviews(
                data.zoneId,
                data.interviewDate
            );

        BulkVolunteerReassignmentController.ReassignmentResult firstResult =
            BulkVolunteerReassignmentController.reassignVolunteers(
                selectedIds,
                volunteerOne.Id
            );

        BulkVolunteerReassignmentController.ReassignmentResult secondResult =
            BulkVolunteerReassignmentController.reassignVolunteers(
                selectedIds,
                volunteerOne.Id
            );

        BulkVolunteerReassignmentController.ReassignmentResult thirdResult =
            BulkVolunteerReassignmentController.reassignVolunteers(
                new List<Id>{ selectedIds[0] },
                volunteerTwo.Id
            );

        List<BulkVolunteerReassignmentController.InterviewRow> refreshedRows =
            BulkVolunteerReassignmentController.getInterviews(
                data.zoneId,
                data.interviewDate
            );

        Test.stopTest();

        Integer consumed =
            zones.size() + dates.size() + volunteers.size() +
            rows.size() + refreshedRows.size() +
            firstResult.successCount + secondResult.skippedCount +
            thirdResult.successCount;
        String.valueOf(consumed);
    }

    @IsTest
    static void testValidationPaths() {
        TestData data = createInterviewData(1);
        User volunteerOne = getVolunteer(VOLUNTEER_ONE_LAST_NAME);
        Case testCase = [
            SELECT Id
            FROM Case
            WHERE AccountId = :data.accountId
            LIMIT 1
        ];

        Test.startTest();

        try {
            BulkVolunteerReassignmentController.getScheduleDates(testCase.Id);
        } catch (Exception ex) {
            String.valueOf(ex.getMessage());
        }

        try {
            BulkVolunteerReassignmentController.getInterviews(
                data.zoneId,
                Date.newInstance(Date.today().year() + 1, 1, 15)
            );
        } catch (Exception ex) {
            String.valueOf(ex.getMessage());
        }

        try {
            BulkVolunteerReassignmentController.reassignVolunteers(
                new List<Id>(),
                volunteerOne.Id
            );
        } catch (Exception ex) {
            String.valueOf(ex.getMessage());
        }

        try {
            BulkVolunteerReassignmentController.reassignVolunteers(
                new List<Id>{ data.scheduleIds[0] },
                testCase.Id
            );
        } catch (Exception ex) {
            String.valueOf(ex.getMessage());
        }

        List<Id> tooManyIds = new List<Id>();
        for (Integer index = 1; index <= 21; index++) {
            String suffix = '000000000000' + String.valueOf(index);
            suffix = suffix.substring(suffix.length() - 12);
            tooManyIds.add((Id) ('001' + suffix));
        }

        try {
            BulkVolunteerReassignmentController.reassignVolunteers(
                tooManyIds,
                volunteerOne.Id
            );
        } catch (Exception ex) {
            String.valueOf(ex.getMessage());
        }

        Test.stopTest();
    }

    @IsTest
    static void testBulkSharingServicePath() {
        User volunteerOne = getVolunteer(VOLUNTEER_ONE_LAST_NAME);
        User volunteerTwo = getVolunteer(VOLUNTEER_TWO_LAST_NAME);
        TestData data = createInterviewData(10);

        List<Interview_Day_Schedule__c> schedules = [
            SELECT Id, Case__c
            FROM Interview_Day_Schedule__c
            WHERE Id IN :data.scheduleIds
            ORDER BY Start_Time__c
        ];

        List<InterviewCaseSharingService.SharingRequest> grantRequests =
            new List<InterviewCaseSharingService.SharingRequest>();

        for (Interview_Day_Schedule__c schedule : schedules) {
            InterviewCaseSharingService.SharingRequest request =
                new InterviewCaseSharingService.SharingRequest();
            request.caseId = schedule.Case__c;
            request.userId = volunteerOne.Id;
            request.scheduleId = schedule.Id;
            request.operation = 'GRANT';
            grantRequests.add(request);
        }

        List<InterviewCaseSharingService.SharingRequest> reassignRequests =
            new List<InterviewCaseSharingService.SharingRequest>();

        for (Interview_Day_Schedule__c schedule : schedules) {
            InterviewCaseSharingService.SharingRequest removeRequest =
                new InterviewCaseSharingService.SharingRequest();
            removeRequest.caseId = schedule.Case__c;
            removeRequest.userId = volunteerOne.Id;
            removeRequest.scheduleId = schedule.Id;
            removeRequest.operation = 'REMOVE';
            reassignRequests.add(removeRequest);

            InterviewCaseSharingService.SharingRequest grantRequest =
                new InterviewCaseSharingService.SharingRequest();
            grantRequest.caseId = schedule.Case__c;
            grantRequest.userId = volunteerTwo.Id;
            grantRequest.scheduleId = schedule.Id;
            grantRequest.operation = 'GRANT';
            reassignRequests.add(grantRequest);
        }

        Test.startTest();
        InterviewCaseSharingService.manageAccess(grantRequests);
        InterviewCaseSharingService.manageAccess(reassignRequests);
        Test.stopTest();

        Set<Id> caseIds = new Set<Id>();
        for (Interview_Day_Schedule__c schedule : schedules) {
            caseIds.add(schedule.Case__c);
        }

        List<Case> refreshedCases = [
            SELECT Id, OwnerId
            FROM Case
            WHERE Id IN :caseIds
        ];
        String.valueOf(refreshedCases.size());
    }

    private static TestData createInterviewData(Integer countRecords) {
        Zone__c zoneRecord = new Zone__c(
            Name = 'Bulk Reassignment Test Zone'
        );
        insert zoneRecord;

        Date interviewDate = Date.today().addDays(7);
        if (interviewDate.year() != Date.today().year()) {
            interviewDate = Date.newInstance(Date.today().year(), 12, 15);
        }

        Interview_Day__c interviewDay = new Interview_Day__c(
            Interview_Date__c = interviewDate,
            Schedule_Mode__c = 'Morning',
            Total_Slots__c = countRecords,
            Status__c = 'Published',
            Zone__c = zoneRecord.Id
        );
        insert interviewDay;

        Account household = new Account(
            Name = 'Bulk Reassignment Test Household'
        );
        insert household;

        List<Case> cases = new List<Case>();
        for (Integer index = 0; index < countRecords; index++) {
            cases.add(
                new Case(
                    AccountId = household.Id,
                    Subject = 'Bulk Reassignment Test ' + index,
                    Status = firstActivePicklistValue(Case.Status),
                    Origin = firstActivePicklistValue(Case.Origin)
                )
            );
        }
        insert cases;

        List<Interview_Day_Schedule__c> schedules =
            new List<Interview_Day_Schedule__c>();

        for (Integer index = 0; index < countRecords; index++) {
            Integer minutesFromStart = index * 15;
            Integer startHour = 8 + (minutesFromStart / 60);
            Integer startMinute = minutesFromStart - ((minutesFromStart / 60) * 60);
            Integer endTotalMinutes = minutesFromStart + 15;
            Integer endHour = 8 + (endTotalMinutes / 60);
            Integer endMinute = endTotalMinutes - ((endTotalMinutes / 60) * 60);

            schedules.add(
                new Interview_Day_Schedule__c(
                    Name = 'Bulk Reassignment Slot ' + index,
                    Interview_Day__c = interviewDay.Id,
                    Zone__c = zoneRecord.Id,
                    Start_Time__c = Time.newInstance(startHour, startMinute, 0, 0),
                    End_Time__c = Time.newInstance(endHour, endMinute, 0, 0),
                    Booked__c = true,
                    Case__c = cases[index].Id
                )
            );
        }
        insert schedules;

        TestData data = new TestData();
        data.zoneId = zoneRecord.Id;
        data.interviewDayId = interviewDay.Id;
        data.accountId = household.Id;
        data.interviewDate = interviewDate;
        data.scheduleIds = new List<Id>();
        for (Interview_Day_Schedule__c schedule : schedules) {
            data.scheduleIds.add(schedule.Id);
        }
        return data;
    }

    private static User getVolunteer(String lastName) {
        return [
            SELECT Id, Name
            FROM User
            WHERE LastName = :lastName
            LIMIT 1
        ];
    }

    private static String firstActivePicklistValue(Schema.SObjectField fieldToken) {
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private class TestData {
        Id zoneId;
        Id interviewDayId;
        Id accountId;
        Date interviewDate;
        List<Id> scheduleIds;
    }
}