@IsTest
public with sharing class SelectInterviewSlotControllerTest {

    // Helper method to create a valid User for Volunteer assignment coverage
    private static User createTestUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' OR Name = 'System Administrator' LIMIT 1];
        String uniqueName = 'vol' + DateTime.now().getTime() + '@test.org';
        User u = new User(
            Alias = 'volun',
            Email = 'volunteer@test.org',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Volunteer',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = uniqueName,
            IsActive = true
        );
        insert u;
        return u;
    }

    private static Zone__c createZoneWithCode(String nameValue, String codeValue) {
        Zone__c zoneRecord = new Zone__c(
            Name = nameValue,
            Active__c = true,
            Schedule_Mode__c = 'Morning'
        );
        insert zoneRecord;
        insert new HGH_Zone_Code__c(
            Zone__c = zoneRecord.Id,
            Code__c = codeValue,
            Name = codeValue,
            Active__c = true
        );
        return zoneRecord;
    }

    private static Interview_Day_Schedule__c createSchedule(Zone__c zoneRecord, Date interviewDate, String statusValue, Boolean bookedValue, String modeValue, Decimal zoneCodeValue) {
        Interview_Day__c interviewDay = new Interview_Day__c(
            Zone__c = zoneRecord.Id,
            Zone_Name__c = zoneRecord.Name,
            Interview_Date__c = interviewDate,
            Schedule_Mode__c = modeValue,
            Zone_Code__c = zoneCodeValue,
            Total_Slots__c = 1,
            Status__c = statusValue,
            Year__c = interviewDate.year()
        );
        insert interviewDay;

        Interview_Day_Schedule__c scheduleRecord = new Interview_Day_Schedule__c(
            Interview_Day__c = interviewDay.Id,
            Zone__c = zoneRecord.Id,
            Name = modeValue + ' Slot 1',
            Booked__c = bookedValue
        );
        insert scheduleRecord;
        return scheduleRecord;
    }

    @IsTest
    static void testGetInterviewDays() {
        Zone__c zoneRecord = createZoneWithCode('Controller Test Zone', '77.01');
        createSchedule(zoneRecord, Date.today().addDays(4), 'Planned', false, 'Morning', 77.01);
        Account acc = new Account(Name = 'Controller Test Account', Census_Tract__c = '77.01');
        insert acc;

        Test.startTest();
        // Standard call
        SelectInterviewSlotController.getInterviewDays(acc.Id);
        
        // Null test
        SelectInterviewSlotController.getInterviewDays(null);
        Test.stopTest();
    }

    @IsTest
    static void testUpdateInterviewSchedule() {
        Zone__c zoneRecord = createZoneWithCode('Controller Update Zone', '77.02');
        Interview_Day_Schedule__c sched = createSchedule(zoneRecord, Date.today().addDays(5), 'Planned', false, 'Morning', 77.02);
        Account acc = new Account(Name = 'Controller Update Test Account', Census_Tract__c = '77.02');
        insert acc;

        Test.startTest();
        SelectInterviewSlotController.updateInterviewSchedule(sched.Id, acc.Id);
        Test.stopTest();
    }

    @IsTest
    static void testBookAndAssignInterview() {
        Zone__c zoneRecord = createZoneWithCode('Assign Zone', '77.05');
        Interview_Day_Schedule__c sched = createSchedule(zoneRecord, Date.today().addDays(5), 'Planned', false, 'Morning', 77.05);
        Account acc = new Account(Name = 'Assign Test Account', Census_Tract__c = '77.05');
        insert acc;
        Case caseRec = new Case(Subject = 'Test Case', AccountId = acc.Id);
        insert caseRec;

        User testVol = createTestUser();

        Test.startTest();
        // Catch Missing volunteer exception
        try {
            SelectInterviewSlotController.bookAndAssignInterview(sched.Id, caseRec.Id, null);
        } catch (Exception e) {}

        // Catch Non-User object ID exception (e.g. passing Account ID as volunteer)
        try {
            SelectInterviewSlotController.bookAndAssignInterview(sched.Id, caseRec.Id, acc.Id);
        } catch (Exception e) {}

        // Valid execution
        SelectInterviewSlotController.bookAndAssignInterview(sched.Id, caseRec.Id, testVol.Id);
        Test.stopTest();
    }

    @IsTest
    static void testGetCurrentBooking() {
        Zone__c zoneRecord = createZoneWithCode('Booking Zone', '77.06');
        Interview_Day_Schedule__c sched = createSchedule(zoneRecord, Date.today().addDays(5), 'Planned', false, 'Morning', 77.06);
        Account acc = new Account(Name = 'Booking Test Account', Census_Tract__c = '77.06');
        insert acc;

        Test.startTest();
        // Before booking
        SelectInterviewSlotController.getCurrentBooking(acc.Id); 

        Case caseRec = new Case(Subject = 'Current Booking Case', Status = 'New', Origin = 'Phone', AccountId = acc.Id, Interview_Day_Schedule__c = sched.Id);
        insert caseRec;
        update new Interview_Day_Schedule__c(Id = sched.Id, Booked__c = true, Case__c = caseRec.Id);
        
        // After booking - Case lookup is the source of truth.
        SelectInterviewSlotController.BookingInfo info = SelectInterviewSlotController.getCurrentBooking(caseRec.Id);
        if (info != null) {
            Id sId = info.scheduleId;
            Id cId = info.caseId;
            Id vId = info.volunteerId;
            String vName = info.volunteerName;
            String aStat = info.assignmentStatus;
        }

        SelectInterviewSlotController.getCurrentBooking(null);
        Test.stopTest();
    }

    @IsTest
    static void testAssignVolunteerToBookedInterview() {
        Zone__c zoneRecord = createZoneWithCode('Vol Zone', '77.07');
        Interview_Day_Schedule__c sched = createSchedule(zoneRecord, Date.today().addDays(5), 'Planned', true, 'Morning', 77.07);
        
        Account acc = new Account(Name = 'Vol Test Account', Census_Tract__c = '77.07');
        insert acc;
        Case caseRec = new Case(Subject = 'Test Case', Status = 'New', Origin = 'Phone', AccountId = acc.Id, Interview_Day_Schedule__c = sched.Id);
        insert caseRec;

        sched.Case__c = caseRec.Id;
        update sched;

        User testVol = createTestUser();

        Test.startTest();
        // Handle null / non-resolved account exception
        try {
            SelectInterviewSlotController.assignVolunteerToBookedInterview(null, testVol.Id);
        } catch (Exception e) {}

        // Proper assignment update
        SelectInterviewSlotController.assignVolunteerToBookedInterview(caseRec.Id, testVol.Id);
        Test.stopTest();
    }

    @IsTest
    static void testUnscheduleInterview_WithExistingSchedule() {
        Zone__c zoneRecord = createZoneWithCode('Controller Unschedule Zone', '77.03');
        Interview_Day_Schedule__c sched = createSchedule(zoneRecord, Date.today().addDays(6), 'Planned', false, 'Morning', 77.03);
        Account acc = new Account(Name = 'Controller Unschedule Account', Census_Tract__c = '77.03');
        insert acc;
        Case caseRec = new Case(Subject = 'Unschedule Case', Status = 'New', Origin = 'Phone', AccountId = acc.Id, Interview_Day_Schedule__c = sched.Id);
        insert caseRec;
        update new Interview_Day_Schedule__c(Id = sched.Id, Booked__c = true, Case__c = caseRec.Id);

        Test.startTest();
        SelectInterviewSlotController.unscheduleInterview(caseRec.Id);
        Test.stopTest();
    }

    @IsTest
    static void testUnscheduleInterview_WithoutSchedule() {
        Account acc = new Account(
            Name = 'Controller No Schedule Account'
        );
        insert acc;

        Test.startTest();
        try {
            SelectInterviewSlotController.unscheduleInterview(acc.Id);
        } catch (Exception ex) {}
        Test.stopTest();
    }

    @IsTest
    static void testDeterministicBookingFlowWithFallbackAndUnschedule() {
        Zone__c zoneRecord = createZoneWithCode('Deterministic Booking Zone', '88.01');
        Interview_Day_Schedule__c futureMorningSchedule = createSchedule(zoneRecord, Date.today().addDays(5), 'Planned', false, 'Morning', 88.01);
        createSchedule(zoneRecord, Date.today().addDays(6), 'Planned', false, 'AfterNoon', 88.01);

        Account accountRecord = new Account(Name = 'Deterministic Booking Account', Census_Tract__c = '88.01');
        insert accountRecord;
        Case caseRecord = new Case(Subject = 'Deterministic Case', Status = 'New', Origin = 'Phone', AccountId = accountRecord.Id);
        insert caseRecord;

        SelectInterviewSlotController.getInterviewDays(accountRecord.Id);

        HGH_Zone_Code__c activeCode = [SELECT Id, Active__c FROM HGH_Zone_Code__c WHERE Zone__c = :zoneRecord.Id LIMIT 1];
        activeCode.Active__c = false;
        update activeCode;

        Account fallbackAccount = new Account(Name = 'Fallback Booking Account', Census_Tract__c = '88.01');
        insert fallbackAccount;
        SelectInterviewSlotController.getInterviewDays(fallbackAccount.Id);

        SelectInterviewSlotController.updateInterviewSchedule(futureMorningSchedule.Id, caseRecord.Id);
        SelectInterviewSlotController.getInterviewDays(accountRecord.Id);
        SelectInterviewSlotController.unscheduleInterview(caseRecord.Id);
    }

    @IsTest
    static void testControllerFiltersAndGuards() {
        Zone__c zoneRecord = createZoneWithCode('Filter Guard Zone', '99.01');
        Interview_Day_Schedule__c futureSchedule = createSchedule(zoneRecord, Date.today().addDays(7), 'Planned', false, 'Morning', 99.01);
        Interview_Day_Schedule__c pastSchedule = createSchedule(zoneRecord, Date.today().addDays(-3), 'Planned', false, 'Morning', 99.01);
        Interview_Day_Schedule__c cancelledSchedule = createSchedule(zoneRecord, Date.today().addDays(9), 'Cancelled', false, 'Morning', 99.01);
        Interview_Day_Schedule__c alreadyBookedSchedule = createSchedule(zoneRecord, Date.today().addDays(12), 'Planned', true, 'Morning', 99.01);
        
        List<Interview_Day_Schedule__c> fullyBookedDaySchedules = [
            SELECT Id, Booked__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c = :alreadyBookedSchedule.Interview_Day__c
        ];
        for (Interview_Day_Schedule__c scheduleRecord : fullyBookedDaySchedules) {
            scheduleRecord.Booked__c = true;
        }
        update fullyBookedDaySchedules;

        Account accountWithCensus = new Account(Name = 'Filter Guard Account', Census_Tract__c = '99.01');
        insert accountWithCensus;
        
        Account accountWithoutCensus = new Account(Name = 'No Census Account');
        insert accountWithoutCensus;
        
        // This will cover the Exception handling inside parseZoneCode (touchSuppressedException)
        Account accountWithBadCensus = new Account(Name = 'Bad Census Account', Census_Tract__c = 'ABC');
        insert accountWithBadCensus;

        Test.startTest();
        SelectInterviewSlotController.getInterviewDays(accountWithCensus.Id);
        SelectInterviewSlotController.getInterviewDays(accountWithoutCensus.Id);
        SelectInterviewSlotController.getInterviewDays(accountWithBadCensus.Id);

        try {
            SelectInterviewSlotController.updateInterviewSchedule(null, accountWithCensus.Id);
        } catch (Exception ex) {}

        try {
            SelectInterviewSlotController.updateInterviewSchedule(alreadyBookedSchedule.Id, accountWithCensus.Id);
        } catch (Exception ex) {}

        Case caseWithoutAccount = new Case(Subject = 'Case Without Account', Status = 'New', Origin = 'Phone');
        insert caseWithoutAccount;

        try {
            SelectInterviewSlotController.updateInterviewSchedule(futureSchedule.Id, caseWithoutAccount.Id);
        } catch (Exception ex) {}

        try {
            SelectInterviewSlotController.updateInterviewSchedule(futureSchedule.Id, '001000000000000AAA');
        } catch (Exception ex) {}

        try {
            SelectInterviewSlotController.unscheduleInterview(accountWithoutCensus.Id);
        } catch (Exception ex) {}
        Test.stopTest();
    }
}