@isTest
private class ScheduleGenHelperTest {

    @testSetup
    static void setup() {
        // Active + inactive zones
        Zone__c z1 = new Zone__c(Name = 'Helper Zone 1', Active__c = true);
        Zone__c z2 = new Zone__c(Name = 'Helper Zone 2', Active__c = false);
        insert new List<Zone__c>{ z1, z2 };

        // Create schedule year and some schedule dates
        Schedule_Year__c sy2026 = new Schedule_Year__c(Name='2026', Year__c=2026, Status__c='Planned');
        insert sy2026;

        // Minimal schedule rows across zones
        Schedule_Date__c sd1 = new Schedule_Date__c(Name='SD1', Schedule_Year__c=sy2026.Id, Zone__c=z1.Id, Status__c='Planned', Calculated_Date__c=Date.newInstance(2026,1,4));
        Schedule_Date__c sd2 = new Schedule_Date__c(Name='SD2', Schedule_Year__c=sy2026.Id, Zone__c=z1.Id, Status__c='Published', Calculated_Date__c=Date.newInstance(2026,2,4));
        insert new List<Schedule_Date__c>{ sd1, sd2 };
    }

    @isTest
    static void testGetZoneOptions_onlyActive() {
        List<ScheduleGenHelper.OptionDTO> opts = ScheduleGenHelper.getZoneOptions();
        System.assert(!opts.isEmpty(), 'Active zone should be returned');
        for (ScheduleGenHelper.OptionDTO o : opts) {
            System.assert(!String.isBlank(o.label) && !String.isBlank(o.value));
        }
    }

    @isTest
    static void testEnsureScheduleYear_createAndReuse() {
        // Create new year
        Id id2027 = ScheduleGenHelper.ensureScheduleYear(2027);
        System.assertNotEquals(null, id2027);
        // Reuse existing
        Id id2027Again = ScheduleGenHelper.ensureScheduleYear(2027);
        System.assertEquals(id2027, id2027Again);

        // Error case
        Boolean threw = false;
        try { ScheduleGenHelper.ensureScheduleYear(null); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Null year should throw');
    }

    @isTest
    static void testGetYearOptions_returnsExisting() {
        List<ScheduleGenHelper.OptionDTO> years = ScheduleGenHelper.getYearOptions();
        System.assert(years.size() > 0, 'Should include existing schedule years');
    }

    @isTest
    static void testGetScheduleYearSummary_counts() {
        ScheduleGenHelper.YearSummaryDTO dto = ScheduleGenHelper.getScheduleYearSummary(2026);
        System.assertNotEquals(null, dto);
        System.assertEquals(true, dto.totalCount >= 2);
        System.assert(dto.plannedCount >= 1);
        System.assert(dto.publishedCount >= 1);

        // Missing year -> empty DTO
        ScheduleGenHelper.YearSummaryDTO empty = ScheduleGenHelper.getScheduleYearSummary(1999);
        System.assertEquals(0, empty.totalCount);
        System.assertEquals(0, empty.byZone.size());

        // Error case
        Boolean threw = false;
        try { ScheduleGenHelper.getScheduleYearSummary(null); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Null year should throw');
    }
}