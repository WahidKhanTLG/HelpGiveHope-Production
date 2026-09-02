@IsTest
public with sharing class SelectInterviewSlotControllerTest {

    @IsTest
    static void testGetInterviewDays() {
        Zone__c zoneRecord = createZoneWithCode('Controller Test Zone', '77.01');
        createSchedule(zoneRecord, Date.today().addDays(4), 'Planned', false, 'Morning', 77.01);
        Account acc = new Account(Name = 'Controller Test Account', Census_Tract__c = '77.01');
        insert acc;

        Test.startTest();
        List<Interview_Day__c> interviewDays = SelectInterviewSlotController.getInterviewDays(acc.Id);
        Test.stopTest();
        System.assert(!interviewDays.isEmpty(), 'Expected at least one bookable interview day for the account census tract.');
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

        Interview_Day_Schedule__c refreshedSchedule = [
            SELECT Booked__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :sched.Id
        ];
        Account refreshedAccount = [
            SELECT Interview_Day_Schedule__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals(true, refreshedSchedule.Booked__c, 'Updating the interview schedule should book the chosen slot.');
        System.assertEquals(sched.Id, refreshedAccount.Interview_Day_Schedule__c, 'The chosen schedule should be stamped back onto the Account.');
    }

    @IsTest
    static void testUnscheduleInterview_WithExistingSchedule() {
        Zone__c zoneRecord = createZoneWithCode('Controller Unschedule Zone', '77.03');
        Interview_Day_Schedule__c sched = createSchedule(zoneRecord, Date.today().addDays(6), 'Planned', false, 'Morning', 77.03);
        Account acc = new Account(Name = 'Controller Unschedule Account', Census_Tract__c = '77.03', Interview_Day_Schedule__c = sched.Id);
        insert acc;
        update new Interview_Day_Schedule__c(Id = sched.Id, Booked__c = true);

        Test.startTest();
        SelectInterviewSlotController.unscheduleInterview(acc.Id);
        Test.stopTest();

        Interview_Day_Schedule__c refreshedSchedule = [
            SELECT Booked__c, Case__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :sched.Id
        ];
        Account refreshedAccount = [
            SELECT Interview_Day_Schedule__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals(false, refreshedSchedule.Booked__c, 'Unscheduling should reopen the slot.');
        System.assertEquals(null, refreshedSchedule.Case__c, 'Unscheduling should clear the Case lookup.');
        System.assertEquals(null, refreshedAccount.Interview_Day_Schedule__c, 'Unscheduling should clear the Account booking reference.');
    }

    @IsTest
    static void testUnscheduleInterview_WithoutSchedule() {
        Account acc = new Account(
            Name = 'Controller No Schedule Account'
        );
        insert acc;

        Boolean threw = false;
        Test.startTest();
        try {
            SelectInterviewSlotController.unscheduleInterview(acc.Id);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Unscheduling without a booking should raise a handled error.');
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
    static void testDeterministicBookingFlowWithFallbackAndUnschedule() {
        Zone__c zoneRecord = createZoneWithCode('Deterministic Booking Zone', '88.01');
        Interview_Day_Schedule__c futureMorningSchedule = createSchedule(zoneRecord, Date.today().addDays(5), 'Planned', false, 'Morning', 88.01);
        createSchedule(zoneRecord, Date.today().addDays(6), 'Planned', false, 'AfterNoon', 88.01);

        Account accountRecord = new Account(Name = 'Deterministic Booking Account', Census_Tract__c = '88.01');
        insert accountRecord;
        Case caseRecord = new Case(Subject = 'Deterministic Case', Status = 'New', Origin = 'Phone', AccountId = accountRecord.Id);
        insert caseRecord;

        List<Interview_Day__c> daysViaActiveCode = SelectInterviewSlotController.getInterviewDays(accountRecord.Id);
        System.assert(daysViaActiveCode.size() >= 2, 'Active zone-code mapping should return bookable interview days.');

        HGH_Zone_Code__c activeCode = [SELECT Id, Active__c FROM HGH_Zone_Code__c WHERE Zone__c = :zoneRecord.Id LIMIT 1];
        activeCode.Active__c = false;
        update activeCode;

        Account fallbackAccount = new Account(Name = 'Fallback Booking Account', Census_Tract__c = '88.01');
        insert fallbackAccount;
        List<Interview_Day__c> daysViaFallback = SelectInterviewSlotController.getInterviewDays(fallbackAccount.Id);
        System.assert(daysViaFallback.size() >= 2, 'Numeric fallback should still find interview days when the active zone-code mapping is disabled.');

        SelectInterviewSlotController.updateInterviewSchedule(futureMorningSchedule.Id, caseRecord.Id);

        Interview_Day_Schedule__c bookedSchedule = [
            SELECT Id, Booked__c, Case__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :futureMorningSchedule.Id
        ];
        Account bookedAccount = [
            SELECT Id, Interview_Day_Schedule__c
            FROM Account
            WHERE Id = :accountRecord.Id
        ];
        System.assertEquals(true, bookedSchedule.Booked__c, 'Booking through the controller should mark the slot as booked.');
        System.assertEquals(caseRecord.Id, bookedSchedule.Case__c, 'Booking through a Case should stamp the Case lookup on the slot.');
        System.assertEquals(futureMorningSchedule.Id, bookedAccount.Interview_Day_Schedule__c, 'The selected slot should be stamped back onto the Account.');

        List<Interview_Day__c> availableAfterBooking = SelectInterviewSlotController.getInterviewDays(accountRecord.Id);
        Boolean foundBookedSchedule = false;
        for (Interview_Day__c interviewDay : availableAfterBooking) {
            for (Interview_Day_Schedule__c scheduleRecord : interviewDay.Interview_Day_Schedules__r) {
                if (scheduleRecord.Id == futureMorningSchedule.Id) {
                    foundBookedSchedule = true;
                }
            }
        }
        System.assertEquals(false, foundBookedSchedule, 'Booked schedules should no longer be returned to the booking UI.');

        SelectInterviewSlotController.unscheduleInterview(accountRecord.Id);

        Interview_Day_Schedule__c unbookedSchedule = [
            SELECT Booked__c, Case__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :futureMorningSchedule.Id
        ];
        Account unbookedAccount = [
            SELECT Interview_Day_Schedule__c
            FROM Account
            WHERE Id = :accountRecord.Id
        ];
        System.assertEquals(false, unbookedSchedule.Booked__c, 'Unscheduling should reopen the slot.');
        System.assertEquals(null, unbookedSchedule.Case__c, 'Unscheduling should clear the Case lookup from the slot.');
        System.assertEquals(null, unbookedAccount.Interview_Day_Schedule__c, 'Unscheduling should clear the Account booking reference.');
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

        Test.startTest();
        List<Interview_Day__c> availableDays = SelectInterviewSlotController.getInterviewDays(accountWithCensus.Id);
        Test.stopTest();
        Set<Id> availableDayIds = new Set<Id>();
        for (Interview_Day__c availableDay : availableDays) {
            availableDayIds.add(availableDay.Id);
        }
        System.assert(availableDayIds.contains(futureSchedule.Interview_Day__c), 'The future planned interview day should be returned.');
        System.assertEquals(false, availableDayIds.contains(pastSchedule.Interview_Day__c), 'Past interview days should be excluded.');
        System.assertEquals(false, availableDayIds.contains(cancelledSchedule.Interview_Day__c), 'Cancelled interview days should be excluded.');
        System.assertEquals(false, availableDayIds.contains(alreadyBookedSchedule.Interview_Day__c), 'Interview days without open slots should be excluded.');

        List<Interview_Day__c> noCensusDays = SelectInterviewSlotController.getInterviewDays(accountWithoutCensus.Id);
        System.assertEquals(0, noCensusDays.size(), 'Accounts without census tract data should not return interview days.');

        Boolean threw = false;
        try {
            SelectInterviewSlotController.updateInterviewSchedule(null, accountWithCensus.Id);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Null schedule ids should be rejected.');

        threw = false;
        try {
            SelectInterviewSlotController.updateInterviewSchedule(alreadyBookedSchedule.Id, accountWithCensus.Id);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Already-booked schedules should not be bookable a second time.');

        Case caseWithoutAccount = new Case(Subject = 'Case Without Account', Status = 'New', Origin = 'Phone');
        insert caseWithoutAccount;

        threw = false;
        try {
            SelectInterviewSlotController.updateInterviewSchedule(futureSchedule.Id, caseWithoutAccount.Id);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Cases without Accounts should not be bookable.');

        Interview_Day_Schedule__c refreshedSchedule = [
            SELECT Booked__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :futureSchedule.Id
        ];
        System.assertEquals(false, refreshedSchedule.Booked__c, 'Failed booking attempts should leave the schedule unbooked.');

        threw = false;
        try {
            SelectInterviewSlotController.updateInterviewSchedule(futureSchedule.Id, '001000000000000AAA');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Invalid Account ids should roll the booking back.');

        refreshedSchedule = [
            SELECT Booked__c, Case__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :futureSchedule.Id
        ];
        System.assertEquals(false, refreshedSchedule.Booked__c, 'The schedule should remain unbooked after a failed Account update.');
        System.assertEquals(null, refreshedSchedule.Case__c, 'The schedule should not keep a stamped Case when the booking rolls back.');

        threw = false;
        try {
            SelectInterviewSlotController.unscheduleInterview(accountWithoutCensus.Id);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Unscheduling should fail when no booking exists on the Account.');
    }
}