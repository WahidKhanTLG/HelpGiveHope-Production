@isTest
private class SelectInterviewSlotControllerExtraTest {
    @isTest
    static void test_getInterviewDays_byHghZoneCodeAndFallback() {
        // Set up zone and zone code
        Zone__c zone = new Zone__c(Name='Zone Fallback', Active__c=true);
        insert zone;
        // Active HGH Zone Code mapping
        HGH_Zone_Code__c zcActive = new HGH_Zone_Code__c(Zone__c=zone.Id, Code__c='99.01', Active__c=true);
        insert zcActive;

        // Create Interview Day records for the zone (both Morning and AfterNoon with unbooked schedules)
        Interview_Day__c day1 = new Interview_Day__c(Zone__c=zone.Id, Zone_Name__c='Zone Fallback', Interview_Date__c=Date.today().addDays(3), Schedule_Mode__c='Morning', Zone_Code__c=99.01, Total_Slots__c=1);
        Interview_Day__c day2 = new Interview_Day__c(Zone__c=zone.Id, Zone_Name__c='Zone Fallback', Interview_Date__c=Date.today().addDays(4), Schedule_Mode__c='AfterNoon', Zone_Code__c=99.01, Total_Slots__c=1);
        insert new List<Interview_Day__c>{ day1, day2 };
        insert new Interview_Day_Schedule__c(Interview_Day__c=day1.Id, Name='Slot1', Booked__c=false);
        insert new Interview_Day_Schedule__c(Interview_Day__c=day2.Id, Name='Slot2', Booked__c=false);

        // Account with Census_Tract__c matching active HGH Zone Code so first branch is used
        Account a1 = new Account(Name='Acc1', Census_Tract__c='99.01');
        insert a1;

    Test.startTest();
    List<Interview_Day__c> daysViaActive = SelectInterviewSlotController.getInterviewDays(a1.Id);
        System.assert(daysViaActive.size() >= 2, 'Should find interview days via Zone__c when HGH_Zone_Code__c is active');

        // Now test fallback path by deactivating HGH_Zone_Code__c and creating another account using the numeric fallback
        zcActive.Active__c = false;
        update zcActive;
        Account a2 = new Account(Name='Acc2', Census_Tract__c='99.01');
        insert a2;

        List<Interview_Day__c> daysViaFallback = SelectInterviewSlotController.getInterviewDays(a2.Id);
        Test.stopTest();
        System.assert(daysViaFallback.size() >= 2, 'Should fallback to Zone_Code__c numeric match when no active HGH Zone Code found');

        // Book a slot via controller and verify subsequent query excludes it
        Interview_Day_Schedule__c sched = [SELECT Id FROM Interview_Day_Schedule__c WHERE Interview_Day__c IN :new List<Id>{ day1.Id, day2.Id } AND Booked__c = false LIMIT 1];
        SelectInterviewSlotController.updateInterviewSchedule(sched.Id, a2.Id);
        List<Interview_Day__c> afterBooking = SelectInterviewSlotController.getInterviewDays(a2.Id);
        // Ensure the selected schedule is no longer visible as unbooked
        Boolean foundBooked = false;
        for (Interview_Day__c d : afterBooking) {
            for (Interview_Day_Schedule__c s : d.Interview_Day_Schedules__r) {
                if (s.Id == sched.Id) { foundBooked = true; break; }
            }
        }
        System.assertEquals(false, foundBooked, 'Booked schedule should not appear in unbooked query');
    }

    @isTest
    static void test_nullCensusTract_and_updateError() {
        Account a = new Account(Name='No Census');
        insert a;
        List<Interview_Day__c> empty = SelectInterviewSlotController.getInterviewDays(a.Id);
        System.assertEquals(0, empty.size(), 'No census tract should return empty list');

        Boolean threw = false;
        try {
            SelectInterviewSlotController.updateInterviewSchedule(null, a.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Updating with null schedule should throw and cover catch block');
    }
}