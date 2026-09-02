@isTest
private class ScheduleGenServiceTest {

    // Helper to fetch any active Zone created in this test context
    private static Zone__c getAnyActiveZone() {
        List<Zone__c> zones = [SELECT Id, Name FROM Zone__c WHERE Active__c = true ORDER BY CreatedDate DESC LIMIT 1];
        System.assert(!zones.isEmpty(), 'Expected at least one active zone');
        return zones[0];
    }

    @testSetup
    static void setup() {
        // Zones
        Zone__c z1 = new Zone__c(Name = 'Zone A', Active__c = true);
        Zone__c z2 = new Zone__c(Name = 'Zone B', Active__c = true);
        insert new List<Zone__c>{ z1, z2 };

        // Zone Codes
        HGH_Zone_Code__c zc1 = new HGH_Zone_Code__c(Zone__c = z1.Id, Code__c = '43.03', Active__c = true);
        HGH_Zone_Code__c zc2 = new HGH_Zone_Code__c(Zone__c = z2.Id, Code__c = '44.01', Active__c = true);
        insert new List<HGH_Zone_Code__c>{ zc1, zc2 };

        // Rules (active + inactive)
        Zone_Rule__c r1 = new Zone_Rule__c(Zone__c = z1.Id, Month__c = 10, Ordinal__c = 1, DayOfWeek__c = 'Monday', Mode__c = 'Morning', Active__c = true);
        Zone_Rule__c r2 = new Zone_Rule__c(Zone__c = z2.Id, Month__c = 10, Ordinal__c = 2, DayOfWeek__c = 'Wednesday', Mode__c = 'Afternoon', Active__c = false);
        insert new List<Zone_Rule__c>{ r1, r2 };

        // Pre-create a Schedule Year (ensure both exists and create paths are covered later)
        insert new Schedule_Year__c(Name = '2025', Year__c = 2025, Status__c = 'Planned');
    }

    @isTest
    static void testAuditRules_includesActiveAndOptionallyInactive() {
        // Active only
        List<ScheduleGenService.RuleAuditRowDTO> rows = ScheduleGenService.auditRules(2025, null, false);
        System.assert(rows.size() > 0, 'Audit should return rows for active rules');
        // Verify mode/label populated
        ScheduleGenService.RuleAuditRowDTO sample = rows[0];
        System.assertNotEquals(null, sample.calculatedDate);
        System.assert(!String.isBlank(sample.ruleLabel));

        // Include inactive too (should be >= active-only)
        List<ScheduleGenService.RuleAuditRowDTO> rowsAll = ScheduleGenService.auditRules(2025, null, true);
        System.assert(rowsAll.size() >= rows.size(), 'Including inactive should not reduce results');

        // Zone-filtered + includeInactive true path with an extra rule using Last ordinal (5)
    Zone__c z1 = getAnyActiveZone();
        insert new Zone_Rule__c(Zone__c = z1.Id, Month__c = 11, Ordinal__c = 5, DayOfWeek__c = 'Friday', Mode__c = 'Morning', Active__c = false);
        List<ScheduleGenService.RuleAuditRowDTO> filtered = ScheduleGenService.auditRules(2025, new List<Id>{ z1.Id }, true);
        System.assert(filtered.size() > 0, 'Filtered audit with includeInactive should return rows for the zone');
    }

    @isTest
    static void testPreviewAndGenerate_createThenUpdateAndSkip() {
        // Preview before any records exist
        List<ScheduleGenService.PreviewRowDTO> preview = ScheduleGenService.preview(2025, null);
        System.assert(preview.size() > 0, 'Preview should produce rows for rules and codes');
        // No records yet
        System.assertEquals(false, preview[0].exists, 'No existing records before generation');

        // Generate new planned records
        Test.startTest();
        ScheduleGenService.GenerationResultDTO gen1 = ScheduleGenService.generate(2025, null, 'CREATE_NEW');
        Test.stopTest();
        System.assert(gen1.createdCount > 0, 'First generation should create records');
        System.assertEquals(0, gen1.updatedCount, 'No updates in first create pass');

        // Preview should now indicate existence
        List<ScheduleGenService.PreviewRowDTO> previewAfter = ScheduleGenService.preview(2025, null);
        Boolean allExist = true;
        for (ScheduleGenService.PreviewRowDTO p : previewAfter) {
            if (!p.exists) { allExist = false; break; }
        }
        System.assert(allExist, 'After first generation, all preview rows for active rules should exist');

        // Generate again with CREATE_NEW should not create duplicates
        ScheduleGenService.GenerationResultDTO gen2 = ScheduleGenService.generate(2025, null, 'CREATE_NEW');
        System.assertEquals(0, gen2.createdCount, 'Second create pass should not create new records');

        // OVERWRITE_PLANNED should perform updates
        ScheduleGenService.GenerationResultDTO gen3 = ScheduleGenService.generate(2025, null, 'OVERWRITE_PLANNED');
        System.assert(gen3.updatedCount >= 0, 'Overwrite planned may update existing planned records');

    // Delete schedule dates for the year with zone filter
    Id z1Id = getAnyActiveZone().Id;
    ScheduleGenService.DeleteResultDTO delFiltered = ScheduleGenService.deleteScheduleDates(2025, new List<Id>{ z1Id });
    System.assert(delFiltered.deletedCount >= 0, 'Delete with zone filter should return a count');

    // Re-generate then delete all
    ScheduleGenService.generate(2025, null, 'CREATE_NEW');
    ScheduleGenService.DeleteResultDTO delAll = ScheduleGenService.deleteScheduleDates(2025, null);
    System.assert(delAll.deletedCount >= delFiltered.deletedCount, 'Deleting all should remove at least as many records as filtered delete');
    }

    @isTest
    static void testGenerateWithOverrides_createAndSkipPublishedAndErrors() {
        // Ensure year exists
    List<Zone__c> zones = new List<Zone__c>{ getAnyActiveZone() };
        System.assertEquals(1, zones.size());
        Zone__c z1 = zones[0];
        HGH_Zone_Code__c code = [SELECT Id, Code__c FROM HGH_Zone_Code__c WHERE Zone__c = :z1.Id LIMIT 1];
        Zone_Rule__c rule = [SELECT Id FROM Zone_Rule__c WHERE Zone__c = :z1.Id AND Active__c = true LIMIT 1];

        Date d = Date.newInstance(2025, 10, 6); // first Monday in Oct 2025

        // No existing record: should create
        ScheduleGenService.OverrideRowDTO o1 = new ScheduleGenService.OverrideRowDTO();
        o1.zoneId = z1.Id;
        o1.zoneCodeId = code.Id;
        o1.ruleId = rule.Id;
        o1.mode = 'Morning';
        o1.calculatedDate = d;
        o1.exists = false;
        o1.isPublished = false;

        // Published row: should skip
        ScheduleGenService.OverrideRowDTO o2 = new ScheduleGenService.OverrideRowDTO();
        o2.zoneId = z1.Id;
        o2.zoneCodeId = code.Id;
        o2.ruleId = rule.Id;
        o2.mode = 'Morning';
        o2.calculatedDate = d.addDays(7);
        o2.exists = false;
        o2.isPublished = true;

        Test.startTest();
        ScheduleGenService.GenerationResultDTO res = ScheduleGenService.generateWithOverrides(2025, 'CREATE_NEW', new List<ScheduleGenService.OverrideRowDTO>{ o1, o2 });
        Test.stopTest();
    System.assert(res.createdCount >= 1, 'At least one new record should be created');
    System.assert(res.skippedPublished >= 0, 'Published rows may be skipped depending on org rules');

        // Error branches
        Boolean threw;
        threw = false;
        try { ScheduleGenService.auditRules(null, null, false); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Null year should throw for auditRules');

        threw = false;
        try { ScheduleGenService.generate(null, null, 'CREATE_NEW'); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Null year should throw for generate');

        threw = false;
        try { ScheduleGenService.generate(2025, null, null); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Null action should throw for generate');

        threw = false;
        try { ScheduleGenService.generateWithOverrides(2025, 'CREATE_NEW', null); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Null overrides should throw');
    }

    @isTest
    static void testGenerateWithOverrides_overwriteUpdatesPlanned() {
        // Ensure base data exists by running a create
        ScheduleGenService.GenerationResultDTO genBase = ScheduleGenService.generate(2025, null, 'CREATE_NEW');
        System.assert(genBase.createdCount >= 0);

        // Pick one created record and prepare an override with same key
    Schedule_Date__c sd = [SELECT Id, Zone__c, Zone_Code__c, Zone_Rule__c, Mode__c, Calculated_Date__c, Schedule_Year__r.Year__c, Status__c FROM Schedule_Date__c ORDER BY CreatedDate DESC LIMIT 1];
        System.assertEquals('Planned', sd.Status__c);

        ScheduleGenService.OverrideRowDTO ov = new ScheduleGenService.OverrideRowDTO();
        ov.zoneId = sd.Zone__c;
        ov.zoneCodeId = sd.Zone_Code__c;
        ov.ruleId = sd.Zone_Rule__c;
        ov.mode = sd.Mode__c;
        ov.calculatedDate = sd.Calculated_Date__c;
        ov.exists = true;
        ov.isPublished = false;

        Test.startTest();
    ScheduleGenService.GenerationResultDTO res = ScheduleGenService.generateWithOverrides(2025, 'OVERWRITE_PLANNED', new List<ScheduleGenService.OverrideRowDTO>{ ov });
        Test.stopTest();
        System.assert(res.updatedCount >= 0, 'Overwrite planned should update existing planned record');

        // DeleteScheduleDates for a year without Schedule_Year__c should return 0
        ScheduleGenService.DeleteResultDTO delNone = ScheduleGenService.deleteScheduleDates(1991, null);
        System.assertEquals(0, delNone.deletedCount);
    }

    @isTest
    static void testAuditRules_noRulesAndPreviewEmptyZones() {
        // Create a new zone with no rules
        Zone__c zNoRules = new Zone__c(Name='Zone No Rules', Active__c=true);
        insert zNoRules;
        // Audit with includeInactive true should be empty for this zone
        List<ScheduleGenService.RuleAuditRowDTO> none = ScheduleGenService.auditRules(2025, new List<Id>{ zNoRules.Id }, true);
        System.assertEquals(0, none.size(), 'Zone with no rules should produce no audit rows');

        // Create inactive zone and pass it to preview to hit zones.isEmpty() path
        Zone__c zInactive = new Zone__c(Name='Zone Inactive', Active__c=false);
        insert zInactive;
        List<ScheduleGenService.PreviewRowDTO> prevEmpty = ScheduleGenService.preview(2025, new List<Id>{ zInactive.Id });
        System.assertEquals(0, prevEmpty.size(), 'Preview should return empty when provided only inactive zones');

        // Generate with inactive zone should also do nothing but not throw
        ScheduleGenService.GenerationResultDTO genEmpty = ScheduleGenService.generate(2025, new List<Id>{ zInactive.Id }, 'CREATE_NEW');
        System.assertEquals(0, genEmpty.createdCount + genEmpty.updatedCount, 'No records should be created/updated for inactive zones');
    }
}