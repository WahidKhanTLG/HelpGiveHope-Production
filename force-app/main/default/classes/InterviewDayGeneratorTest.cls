@isTest
private class InterviewDayGeneratorTest {

    @testSetup
    static void setup() {
        Zone__c z = new Zone__c(Name = 'Gen Zone', Active__c = true);
        insert z;

        // Two zone codes for selected-processing paths
        insert new List<HGH_Zone_Code__c>{
            new HGH_Zone_Code__c(Zone__c = z.Id, Code__c = '51.02', Name = 'Code 51.02', Active__c = true),
            new HGH_Zone_Code__c(Zone__c = z.Id, Code__c = '51.03', Name = 'Code 51.03', Active__c = true)
        };

        // Schedule Year and two schedule dates with same Calculated_Date__c to trigger duplicate-key skip branch
        Integer thisYear = Date.today().year();
        Schedule_Year__c sy = new Schedule_Year__c(Name = String.valueOf(thisYear), Year__c = thisYear, Status__c = 'Planned');
        insert sy;
        Date d = Date.today().toStartOfMonth().addDays(10);
        insert new List<Schedule_Date__c>{
            new Schedule_Date__c(Name = 'SD-A', Schedule_Year__c = sy.Id, Zone__c = z.Id, Status__c = 'Planned', Calculated_Date__c = d),
            new Schedule_Date__c(Name = 'SD-B', Schedule_Year__c = sy.Id, Zone__c = z.Id, Status__c = 'Planned', Calculated_Date__c = d)
        };
    }

    private static Zone__c getZone() {
        return [SELECT Id FROM Zone__c WHERE Active__c = true ORDER BY CreatedDate DESC LIMIT 1];
    }

    @isTest
    static void testProcessPlaceholdersByDates_combined_and_duplicateSkip() {
        Zone__c z = getZone();
        List<Id> sdIds = new List<Id>();
        for (Schedule_Date__c sd : [SELECT Id FROM Schedule_Date__c WHERE Zone__c = :z.Id ORDER BY CreatedDate ASC LIMIT 2]) {
            sdIds.add(sd.Id);
        }
        System.assertEquals(2, sdIds.size(), 'Expected two schedule dates');

        // Single mode should skip duplicate unique key for same date
        String msgSingle = InterviewDayGenerator.processPlaceholdersByDates(z.Id, sdIds, 'Morning', 3);
        System.assert(msgSingle.contains('Processed'));

        // Combined mode creates both Morning and AfterNoon for same date
        String msgCombined = InterviewDayGenerator.processPlaceholdersByDates(z.Id, sdIds, 'Morning & Afternoon', 4);
        System.assert(msgCombined.contains('mode "Morning & Afternoon"'));
    }

    @isTest
    static void testProcessSelectedInterviewPlaceholders_and_skipAll() {
        Zone__c z = getZone();
        List<HGH_Zone_Code__c> codes = [SELECT Id, Code__c FROM HGH_Zone_Code__c WHERE Zone__c = :z.Id ORDER BY CreatedDate ASC LIMIT 2];
        System.assertEquals(2, codes.size());
        List<Id> ids = new List<Id>{ codes[0].Id, codes[1].Id };

        // First pass should create records for both modes (combined)
        String msg = InterviewDayGenerator.processSelectedInterviewPlaceholders(ids, 'Morning & Afternoon', 4);
        System.assert(msg.contains('Successfully processed'));

        // Second pass should detect all already exist and throw
        Boolean threw = false;
        try {
            InterviewDayGenerator.processSelectedInterviewPlaceholders(ids, 'Morning & Afternoon', 4);
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'Expected skip-all exception on second pass');
    }

    @isTest
    static void testProcessInterviewPlaceholders_aliases_and_generateInterviewDays() {
        Zone__c z = getZone();

        // PM should map to AfterNoon internally
        String msgZone = InterviewDayGenerator.processInterviewPlaceholders(z.Id, 'PM', 3);
        System.assert(msgZone.contains('Successfully processed'));

        // generateInterviewDays simple smoke
        Id codeId = [SELECT Id FROM HGH_Zone_Code__c WHERE Zone__c = :z.Id LIMIT 1].Id;
        Test.startTest();
        InterviewDayGenerator.generateInterviewDays(codeId, 'Morning', 1, Date.today().year());
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Interview_Day__c WHERE Schedule_Mode__c = 'Morning' AND Year__c = :Date.today().year()]);
    }
}