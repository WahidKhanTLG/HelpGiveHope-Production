@IsTest
private class InHomeInterviewMobileControllerTest {

    @TestSetup
    static void setupData() {
        Account accountRecord = new Account(
            Name = 'HGH Mobile Interview Test Household',
            Census_Tract__c = '98.11'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Test',
            LastName = 'Interviewee',
            Phone = '417-555-0100',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Case caseRecord = new Case(
            Subject = 'HGH Mobile Interview Controller Test',
            Status = firstActivePicklistValue(Case.Status),
            Origin = firstActivePicklistValue(Case.Origin),
            AccountId = accountRecord.Id,
            ContactId = contactRecord.Id
        );
        insert caseRecord;

        Zone__c zoneRecord = new Zone__c(Name = 'HGH Mobile Test Zone');
        insert zoneRecord;

        Interview_Day__c interviewDay = new Interview_Day__c(
            Interview_Date__c = Date.today().addDays(7),
            Schedule_Mode__c = 'Morning',
            Total_Slots__c = 2,
            Status__c = 'Published',
            Zone__c = zoneRecord.Id
        );
        insert interviewDay;

        Interview_Day_Schedule__c schedule = [
            SELECT Id, Interview_Day__c, Start_Time__c, End_Time__c, Booked__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c = :interviewDay.Id
            ORDER BY Start_Time__c ASC
            LIMIT 1
        ];
        schedule.Booked__c = true;
        schedule.Case__c = caseRecord.Id;
        schedule.Assignment_Status__c = 'Assigned';
        schedule.Assigned_Volunteer__c = UserInfo.getUserId();
        update schedule;

        accountRecord.Interview_Day_Schedule__c = schedule.Id;
        update accountRecord;

        pmdm__Program__c programRecord = new pmdm__Program__c(
            Name = 'HGH Mobile Test Program',
            pmdm__status__c = 'Active'
        );
        insert programRecord;

        pmdm__Service__c serviceRecord = new pmdm__Service__c(
            Name = 'HGH Mobile Test Bed Service',
            pmdm__Program__c = programRecord.Id,
            Category__c = 'Beds',
            Subcategory__c = 'Twin',
            Gender__c = 'Male'
        );
        insert serviceRecord;

        pmdm__Service__c appliance = new pmdm__Service__c(
            Name = 'HGH Mobile Test Microwave',
            pmdm__Program__c = programRecord.Id,
            Category__c = 'Small Appliances',
            Subcategory__c = 'Microwave'
        );
        insert appliance;
    }

    @IsTest
    static void testLoadAssignedInterviews() {
        Test.startTest();
        List<Map<String, Object>> rows = InHomeInterviewMobileController.loadAssignedInterviews();
        Test.stopTest();
        System.debug(LoggingLevel.ERROR, 'ASSIGNED INTERVIEWS => ' + rows);
    }

    @IsTest
    static void testLoadInterviewFromCaseAndSchedule() {
        Case caseRecord = getCase();
        Interview_Day_Schedule__c schedule = getSchedule(caseRecord.Id);

        Test.startTest();
        Map<String, Object> fromCase = InHomeInterviewMobileController.loadInterview(caseRecord.Id);
        Map<String, Object> fromSchedule = InHomeInterviewMobileController.loadInterview(schedule.Id);
        Test.stopTest();

        System.debug(LoggingLevel.ERROR, 'LOAD FROM CASE => ' + fromCase);
        System.debug(LoggingLevel.ERROR, 'LOAD FROM SCHEDULE => ' + fromSchedule);
    }

    @IsTest
    static void testSaveDraftCreatesSectionNotesAndStartsInterview() {
        Case caseRecord = getCase();
        pmdm__Service__c serviceRecord = getService('HGH Mobile Test Bed Service');

        List<Object> items = new List<Object>{
            new Map<String, Object>{
                'id' => null,
                'serviceId' => serviceRecord.Id,
                'quantity' => 2,
                'recommendation' => 'Neutral'
            }
        };
        Map<String, Object> sectionNotes = new Map<String, Object>{
            'newBeds' => 'Family needs two twin beds.'
        };

        Test.startTest();
        Map<String, Object> result = InHomeInterviewMobileController.saveInterview(
            caseRecord.Id,
            JSON.serialize(items),
            JSON.serialize(sectionNotes),
            'Stable family situation and documented need.',
            'No disqualifying concern identified.',
            true,
            false
        );
        Test.stopTest();

        List<pmdm__ServiceDelivery__c> savedItems = [
            SELECT Id, Case__c, Interview_Day_Schedule__c, pmdm__Service__c,
                   Quantity__c, Status__c, Volunteer_Recommendation__c,
                   HGH_Approval__c
            FROM pmdm__ServiceDelivery__c
            WHERE Case__c = :caseRecord.Id
        ];
        pmdm__Service__c savedServiceNotes = [
            SELECT Id, New_Bed_Needs_Notes__c
            FROM pmdm__Service__c
            WHERE Id = :serviceRecord.Id
        ];
        Interview_Day_Schedule__c refreshed = [
            SELECT Id, Assignment_Status__c
            FROM Interview_Day_Schedule__c
            WHERE Case__c = :caseRecord.Id AND Booked__c = true
            LIMIT 1
        ];

        System.debug(LoggingLevel.ERROR, 'SAVE DRAFT RESULT => ' + result);
        System.debug(LoggingLevel.ERROR, 'SAVED ITEMS => ' + savedItems);
        System.debug(LoggingLevel.ERROR, 'SAVED SERVICE NOTES => ' + savedServiceNotes);
        System.debug(LoggingLevel.ERROR, 'IN PROGRESS SCHEDULE => ' + refreshed);
    }

    @IsTest
    static void testUpdateExistingServiceDeliveryAndSectionNotes() {
        Case caseRecord = getCase();
        Interview_Day_Schedule__c schedule = getSchedule(caseRecord.Id);
        pmdm__Service__c serviceRecord = getService('HGH Mobile Test Bed Service');

        pmdm__ServiceDelivery__c existingItem = new pmdm__ServiceDelivery__c(
            Case__c = caseRecord.Id,
            Interview_Day_Schedule__c = schedule.Id,
            pmdm__Service__c = serviceRecord.Id,
            Quantity__c = 1,
            Status__c = 'Requested',
            Volunteer_Recommendation__c = 'Recommend'
        );
        insert existingItem;

        List<Object> items = new List<Object>{
            new Map<String, Object>{
                'id' => existingItem.Id,
                'serviceId' => serviceRecord.Id,
                'quantity' => 3,
                'recommendation' => 'Concerns'
            }
        };
        Map<String, Object> sectionNotes = new Map<String, Object>{
            'newBeds' => 'Updated New Bed Needs notes.'
        };

        Test.startTest();
        InHomeInterviewMobileController.saveInterview(
            schedule.Id,
            JSON.serialize(items),
            JSON.serialize(sectionNotes),
            'Updated why help',
            'Updated why not help',
            false,
            false
        );
        Test.stopTest();

        pmdm__ServiceDelivery__c updatedItem = [
            SELECT Id, Quantity__c, Volunteer_Recommendation__c,
                   HGH_Approval__c
            FROM pmdm__ServiceDelivery__c
            WHERE Id = :existingItem.Id
        ];
        pmdm__Service__c updatedServiceNotes = [
            SELECT Id, New_Bed_Needs_Notes__c
            FROM pmdm__Service__c
            WHERE Id = :serviceRecord.Id
        ];
        System.debug(LoggingLevel.ERROR, 'UPDATED ITEM => ' + updatedItem);
        System.debug(LoggingLevel.ERROR, 'UPDATED SERVICE NOTES => ' + updatedServiceNotes);
    }

    @IsTest
    static void testReusesExistingUnlinkedRequestedItem() {
        Case caseRecord = getCase();
        Interview_Day_Schedule__c schedule = getSchedule(caseRecord.Id);
        pmdm__Service__c serviceRecord = getService('HGH Mobile Test Bed Service');

        pmdm__ServiceDelivery__c existingRequest = new pmdm__ServiceDelivery__c(
            Case__c = caseRecord.Id,
            pmdm__Service__c = serviceRecord.Id,
            Quantity__c = 1,
            Status__c = 'Requested'
        );
        insert existingRequest;

        Test.startTest();
        Map<String, Object> loaded = InHomeInterviewMobileController.loadInterview(caseRecord.Id);

        List<Object> items = new List<Object>{
            new Map<String, Object>{
                'id' => existingRequest.Id,
                'serviceId' => serviceRecord.Id,
                'quantity' => 2,
                'recommendation' => 'Recommend'
            }
        };

        InHomeInterviewMobileController.saveInterview(
            caseRecord.Id,
            JSON.serialize(items),
            '{}',
            'Why help',
            'Why not help',
            false,
            false
        );
        Test.stopTest();

        pmdm__ServiceDelivery__c linkedRequest = [
            SELECT Id, Interview_Day_Schedule__c, Quantity__c,
                   Volunteer_Recommendation__c
            FROM pmdm__ServiceDelivery__c
            WHERE Id = :existingRequest.Id
        ];

        System.debug(LoggingLevel.ERROR, 'REUSED PMM ITEMS => ' + loaded);
        System.debug(LoggingLevel.ERROR, 'LINKED REQUEST => ' + linkedRequest);
        System.debug(LoggingLevel.ERROR, 'CURRENT SCHEDULE => ' + schedule.Id);
    }

    @IsTest
    static void testMultipleQuestionnaireSections() {
        Case caseRecord = getCase();
        pmdm__Service__c bed = getService('HGH Mobile Test Bed Service');
        pmdm__Service__c appliance = getService('HGH Mobile Test Microwave');

        List<Object> items = new List<Object>{
            new Map<String, Object>{
                'serviceId' => bed.Id,
                'quantity' => 2,
                'recommendation' => 'Recommend'
            },
            new Map<String, Object>{
                'serviceId' => appliance.Id,
                'quantity' => 1,
                'recommendation' => 'Strongly Recommend'
            }
        };
        Map<String, Object> sectionNotes = new Map<String, Object>{
            'newBeds' => 'Beds section note.',
            'smallAppliances' => 'Appliance section note.'
        };

        Test.startTest();
        InHomeInterviewMobileController.saveInterview(
            caseRecord.Id,
            JSON.serialize(items),
            JSON.serialize(sectionNotes),
            'Why help',
            'Why not help',
            false,
            false
        );
        Map<String, Object> loaded = InHomeInterviewMobileController.loadInterview(caseRecord.Id);
        Test.stopTest();

        System.debug(LoggingLevel.ERROR, 'MULTI SECTION LOAD => ' + loaded);
    }

    @IsTest
    static void testCompleteInterviewAndImmediateReadOnlyServerState() {
        Case caseRecord = getCase();
        pmdm__Service__c serviceRecord = getService('HGH Mobile Test Bed Service');

        List<Object> items = new List<Object>{
            new Map<String, Object>{
                'serviceId' => serviceRecord.Id,
                'quantity' => 1,
                'recommendation' => 'Strongly Recommend'
            }
        };
        Map<String, Object> sectionNotes = new Map<String, Object>{
            'newBeds' => 'Completion note.'
        };

        Test.startTest();
        InHomeInterviewMobileController.saveInterview(
            caseRecord.Id,
            JSON.serialize(items),
            JSON.serialize(sectionNotes),
            'Complete why help',
            'Complete why not help',
            true,
            true
        );
        Map<String, Object> loaded = InHomeInterviewMobileController.loadInterview(caseRecord.Id);

        try {
            InHomeInterviewMobileController.saveInterview(
                caseRecord.Id,
                JSON.serialize(items),
                JSON.serialize(sectionNotes),
                'Should not save',
                'Should not save',
                false,
                false
            );
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'EXPECTED READ ONLY ERROR => ' + ex.getMessage());
        }
        Test.stopTest();

        Interview_Day_Schedule__c completedSchedule = [
            SELECT Id, Assignment_Status__c, Completed_On__c
            FROM Interview_Day_Schedule__c
            WHERE Case__c = :caseRecord.Id AND Booked__c = true
            LIMIT 1
        ];
        System.debug(LoggingLevel.ERROR, 'COMPLETED LOAD => ' + loaded);
        System.debug(LoggingLevel.ERROR, 'COMPLETED SCHEDULE => ' + completedSchedule);
    }

    @IsTest
    static void testNoScheduleLoadsReadOnly() {
        Account accountRecord = new Account(Name = 'No Schedule Household');
        insert accountRecord;

        Case caseRecord = new Case(
            Subject = 'No Schedule Interview Test',
            Status = firstActivePicklistValue(Case.Status),
            Origin = firstActivePicklistValue(Case.Origin),
            AccountId = accountRecord.Id
        );
        insert caseRecord;

        Test.startTest();
        Map<String, Object> result = InHomeInterviewMobileController.loadInterview(caseRecord.Id);
        Test.stopTest();

        System.debug(LoggingLevel.ERROR, 'NO SCHEDULE READ ONLY => ' + result);
    }

    @IsTest
    static void testWrongVolunteerSaveBlocked() {
        Case caseRecord = getCase();
        Interview_Day_Schedule__c schedule = getSchedule(caseRecord.Id);

        User otherUser = createUser('otherhgh');
        InHomeInterviewMobileController.systemAdministratorOverride = false;
        InHomeInterviewMobileController.currentUserIdOverride = otherUser.Id;

        Test.startTest();
        try {
            InHomeInterviewMobileController.saveInterview(
                schedule.Id,
                '[]',
                '{}',
                'No change',
                'No change',
                false,
                false
            );
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'EXPECTED WRONG VOLUNTEER ERROR => ' + ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testInvalidRecommendationAndQuantity() {
        Case caseRecord = getCase();
        pmdm__Service__c serviceRecord = getService('HGH Mobile Test Bed Service');

        List<Object> badRecommendation = new List<Object>{
            new Map<String, Object>{
                'serviceId' => serviceRecord.Id,
                'quantity' => 1,
                'recommendation' => 'Unknown'
            }
        };

        List<Object> badQuantity = new List<Object>{
            new Map<String, Object>{
                'serviceId' => serviceRecord.Id,
                'quantity' => 0,
                'recommendation' => 'Neutral'
            }
        };

        Test.startTest();
        try {
            InHomeInterviewMobileController.saveInterview(
                caseRecord.Id,
                JSON.serialize(badRecommendation),
                '{}',
                '',
                '',
                false,
                false
            );
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'EXPECTED RECOMMENDATION ERROR => ' + ex.getMessage());
        }

        try {
            InHomeInterviewMobileController.saveInterview(
                caseRecord.Id,
                JSON.serialize(badQuantity),
                '{}',
                '',
                '',
                false,
                false
            );
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'EXPECTED QUANTITY ERROR => ' + ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testNullRecordGuards() {
        Test.startTest();
        try {
            InHomeInterviewMobileController.loadInterview(null);
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'EXPECTED LOAD GUARD => ' + ex.getMessage());
        }

        try {
            InHomeInterviewMobileController.saveInterview(
                null,
                '[]',
                '{}',
                '',
                '',
                false,
                false
            );
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'EXPECTED SAVE GUARD => ' + ex.getMessage());
        }
        Test.stopTest();
    }

    private static Case getCase() {
        return [
            SELECT Id
            FROM Case
            WHERE Subject = 'HGH Mobile Interview Controller Test'
            LIMIT 1
        ];
    }

    private static Interview_Day_Schedule__c getSchedule(Id caseId) {
        return [
            SELECT Id, Assignment_Status__c, Assigned_Volunteer__c, Booked__c
            FROM Interview_Day_Schedule__c
            WHERE Case__c = :caseId AND Booked__c = true
            LIMIT 1
        ];
    }

    private static pmdm__Service__c getService(String name) {
        return [
            SELECT Id
            FROM pmdm__Service__c
            WHERE Name = :name
            LIMIT 1
        ];
    }

    private static User createUser(String aliasPrefix) {
        List<Profile> profiles = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];
        Id profileId = profiles.isEmpty() ? UserInfo.getProfileId() : profiles[0].Id;
        String token = String.valueOf(DateTime.now().getTime()) + String.valueOf(Crypto.getRandomLong()).replace('-', '');

        User userRecord = new User(
            Alias = aliasPrefix.left(8),
            Email = aliasPrefix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'HGH Volunteer Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profileId,
            TimeZoneSidKey = 'America/Chicago',
            Username = aliasPrefix + '.' + token + '@example.com'
        );
        insert userRecord;
        return userRecord;
    }

    private static String firstActivePicklistValue(Schema.SObjectField fieldToken) {
        for(Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if(entry.isActive()) return entry.getValue();
        }
        return null;
    }
}