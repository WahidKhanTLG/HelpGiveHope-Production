@isTest
private class InterviewDayUiHelperTest {
    // Helper to fetch any active Zone inserted by @testSetup without relying on Name (flows may change it)
    private static Zone__c getAnyActiveZone() {
        List<Zone__c> zones = [SELECT Id, Name FROM Zone__c WHERE Active__c = true ORDER BY CreatedDate DESC LIMIT 1];
        System.assert(!zones.isEmpty(), 'Expected at least one active zone from test setup');
        return zones[0];
    }

    @testSetup
    static void setup() {
        Zone__c z = new Zone__c(Name='UI Zone', Active__c=true);
        insert z;
        HGH_Zone_Code__c zc = new HGH_Zone_Code__c(Zone__c=z.Id, Code__c='50.01', Name='ZC 50.01', Active__c=true);
        insert zc;

        // Seed one Interview Day and Schedule for existing-queries
        Interview_Day__c iday = new Interview_Day__c(Zone__c=z.Id, Zone_Name__c='UI Zone', Zone_Code__c=50.01, Schedule_Mode__c='Morning', Total_Slots__c=1, Year__c=Date.today().year(), Status__c='Planned', Interview_Date__c=Date.today());
        insert iday;
        insert new Interview_Day_Schedule__c(Interview_Day__c=iday.Id, Zone__c=z.Id, Name='Morning Slot 1', Booked__c=false);

        // Schedule Year and Dates for getScheduleDatesForZone
        Schedule_Year__c y = new Schedule_Year__c(Name=String.valueOf(Date.today().year()), Year__c=Date.today().year(), Status__c='Planned');
        insert y;
        insert new Schedule_Date__c(Name='SD-UI', Schedule_Year__c=y.Id, Zone__c=z.Id, Status__c='Planned', Calculated_Date__c=Date.today());
    }

    @isTest
    static void testGetZones_andGetZoneCodes() {
        List<Zone__c> zones = InterviewDayUiHelper.getZones();
        System.assert(zones.size() > 0);
        List<HGH_Zone_Code__c> codes = InterviewDayUiHelper.getZoneCodes();
        System.assert(codes.size() > 0);
        List<HGH_Zone_Code__c> codesForZone = InterviewDayUiHelper.getZoneCodesForZone(zones[0].Id);
        System.assert(codesForZone.size() > 0);
    }

    @isTest
    static void testGetScheduleDatesForZone_andDeleteAllSchedules() {
        Id zoneId = getAnyActiveZone().Id;
        List<Schedule_Date__c> dates = InterviewDayUiHelper.getScheduleDatesForZone(zoneId, Date.today().year());
        System.assert(dates.size() >= 1);

        Interview_Day__c bookedDay = new Interview_Day__c(
            Zone__c = zoneId,
            Zone_Name__c = 'Booked Zone',
            Zone_Code__c = 50.02,
            Schedule_Mode__c = 'Morning',
            Total_Slots__c = 1,
            Year__c = Date.today().year(),
            Status__c = 'Planned',
            Interview_Date__c = Date.today().addDays(1)
        );
        insert bookedDay;
        insert new Interview_Day_Schedule__c(
            Interview_Day__c = bookedDay.Id,
            Zone__c = zoneId,
            Name = 'Morning Slot Booked',
            Booked__c = true
        );

        // Insert a Schedule_Date__c without Schedule_Year__c to exercise calendar-year fallback
        insert new Schedule_Date__c(Name='SD-UI-NoYear', Zone__c=zoneId, Status__c='Planned', Calculated_Date__c=Date.today());
        List<Schedule_Date__c> datesFallback = InterviewDayUiHelper.getScheduleDatesForZone(zoneId, Date.today().year());
        System.assert(datesFallback.size() >= dates.size(), 'Fallback should include no-year rows');

        // Null year path should default to current year and still return results
        List<Schedule_Date__c> datesDefaultYear = InterviewDayUiHelper.getScheduleDatesForZone(zoneId, null);
        System.assertNotEquals(null, datesDefaultYear);

        // Delete all Interview Day data
        InterviewDayUiHelper.deleteAllSchedules();
        System.assertEquals(1, [SELECT COUNT() FROM Interview_Day__c], 'Booked interview days should be preserved by the admin cleanup helper.');
        System.assertEquals(1, [SELECT COUNT() FROM Interview_Day_Schedule__c], 'Booked schedule rows should not be deleted by the admin cleanup helper.');
        // Call again to cover empty list branches for deletable records
        InterviewDayUiHelper.deleteAllSchedules();
        System.assertEquals(1, [SELECT COUNT() FROM Interview_Day__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Interview_Day_Schedule__c]);
        // Null zoneId should return empty list (early return)
        List<Schedule_Date__c> none = InterviewDayUiHelper.getScheduleDatesForZone(null, Date.today().year());
        System.assertEquals(0, none.size());
    }

    @isTest
    static void testProcessInterviewPlaceholders_andSelected_andByDates() {
        Zone__c z = getAnyActiveZone();
        HGH_Zone_Code__c zc = [SELECT Id FROM HGH_Zone_Code__c WHERE Zone__c = :z.Id LIMIT 1];

    // Generate interview days via helper wrapper (use Afternoon to avoid conflict with seeded Morning)
    String genMsg = InterviewDayUiHelper.generateInterviewDays(zc.Id, 'AfterNoon', 2, Date.today().year());
        System.assert(genMsg.contains('successfully'));

    // Process placeholders for entire zone (Morning)
    String msg = InterviewDayUiHelper.processInterviewPlaceholders(z.Id, 'Morning', 2);
        System.assert(!String.isBlank(msg));

    // Process placeholders for entire zone - Combined mode with odd slots to exercise split logic
    String msgCombined = InterviewDayUiHelper.processInterviewPlaceholders(z.Id, 'Morning & Afternoon', 5);
    System.assert(!String.isBlank(msgCombined));

        // Process selected codes: may succeed or throw if duplicates exist depending on earlier steps
        Boolean selectedThrew = false;
        String msg2;
        try {
            msg2 = InterviewDayUiHelper.processSelectedInterviewPlaceholders(new List<Id>{ zc.Id }, 'AfterNoon', 2);
        } catch (Exception ex) {
            selectedThrew = true;
        }
        System.assert(selectedThrew || !String.isBlank(msg2));

        // Trigger duplicate-exists path: attempt again for same mode to ensure error branch is covered
        Boolean threwDup = false;
        try {
            InterviewDayUiHelper.processSelectedInterviewPlaceholders(new List<Id>{ zc.Id }, 'AfterNoon', 2);
        } catch (Exception e) {
            threwDup = true;
        }
        System.assert(threwDup, 'Processing selected placeholders twice should hit duplicate-exists error branch');

        // Fetch schedule dates for use with processPlaceholdersByDates
        List<Schedule_Date__c> sds = [SELECT Id, Zone__c FROM Schedule_Date__c WHERE Zone__c = :z.Id LIMIT 1];
        if (sds.isEmpty()) {
            // If none exist, create one unconstrained record this year
            Schedule_Year__c sy = new Schedule_Year__c(Name=String.valueOf(Date.today().year()), Year__c=Date.today().year(), Status__c='Planned');
            insert sy;
            sds.add(new Schedule_Date__c(Name='SD-Temp', Schedule_Year__c=sy.Id, Zone__c=z.Id, Status__c='Planned', Calculated_Date__c=Date.today()));
            insert sds;
        }
        String msg3 = InterviewDayUiHelper.processPlaceholdersByDates(z.Id, new List<Id>{ sds[0].Id }, 'Morning', 3);
        System.assert(!String.isBlank(msg3));
        // Combined mode via processPlaceholdersByDates (splits slots)
        String msg3Combined = InterviewDayUiHelper.processPlaceholdersByDates(z.Id, new List<Id>{ sds[0].Id }, 'Morning & Afternoon', 5);
        System.assert(!String.isBlank(msg3Combined));
        // Invalid params branch (empty list)
        Boolean threwBad = false;
        try {
            InterviewDayUiHelper.processPlaceholdersByDates(z.Id, new List<Id>(), 'Morning', 2);
        } catch (AuraHandledException e) {
            threwBad = true;
        }
        System.assert(threwBad, 'Invalid inputs should throw');
    }

    @isTest
    static void testExistingInterviewDaysQueries() {
        // Build a fake list of IDs (empty) -> returns empty map
        Map<String, List<String>> empty = InterviewDayUiHelper.getExistingInterviewDaysForZoneCodes(new List<Id>());
        System.assertEquals(0, empty.size());

        // With real zone code id list
    List<HGH_Zone_Code__c> codes = [SELECT Id FROM HGH_Zone_Code__c LIMIT 10];
    Map<String, List<String>> resultMap = InterviewDayUiHelper.getExistingInterviewDaysForZoneCodes(new List<Id>{ codes[0].Id });
    System.assertNotEquals(null, resultMap);

    // Non-numeric and blank zone code branches in buildZoneCodeKeyMap/normalizeZoneCode
    Zone__c z = getAnyActiveZone();
    HGH_Zone_Code__c nonNumeric = new HGH_Zone_Code__c(Zone__c=z.Id, Code__c='ABC', Name='NonNumeric', Active__c=true);
    HGH_Zone_Code__c blankCode = new HGH_Zone_Code__c(Zone__c=z.Id, Code__c=' ', Name='Blank', Active__c=true);
    insert new List<HGH_Zone_Code__c>{ nonNumeric, blankCode };
    Map<String, List<String>> mapNonNum = InterviewDayUiHelper.getExistingInterviewDaysForZoneCodes(new List<Id>{ nonNumeric.Id, blankCode.Id });
    System.assertNotEquals(null, mapNonNum);

        // getExistingInterviewDays and getInterviewDaysByBatchId
        List<Interview_Day__c> allExisting = InterviewDayUiHelper.getExistingInterviewDays();
        System.assertNotEquals(null, allExisting);

        // If we can find a Generated_Batch_Id__c, try fetching by batch; otherwise verify empty-path
        String batchId = null;
        for (Interview_Day__c d : [SELECT Generated_Batch_Id__c FROM Interview_Day__c WHERE Generated_Batch_Id__c != null LIMIT 1]) {
            batchId = d.Generated_Batch_Id__c; break;
        }
        List<Interview_Day__c> byBatch = InterviewDayUiHelper.getInterviewDaysByBatchId(batchId);
        System.assertNotEquals(null, byBatch);
        List<Interview_Day__c> byBatchEmpty = InterviewDayUiHelper.getInterviewDaysByBatchId(null);
        System.assertEquals(0, byBatchEmpty.size());
            List<Interview_Day__c> byBatchBlank = InterviewDayUiHelper.getInterviewDaysByBatchId(' ');
            System.assertEquals(0, byBatchBlank.size());
    }

    @isTest
    static void testDeleteSelectedInterviewSchedules_skipsBookedAndDeletesEmptyParent() {
        Zone__c zoneRecord = getAnyActiveZone();

        Interview_Day__c deletableDay = new Interview_Day__c(
            Zone__c = zoneRecord.Id,
            Zone_Name__c = 'Delete Me',
            Zone_Code__c = 50.03,
            Schedule_Mode__c = 'Morning',
            Total_Slots__c = 1,
            Year__c = Date.today().year(),
            Status__c = 'Planned',
            Interview_Date__c = Date.today().addDays(5)
        );
        insert deletableDay;

        Interview_Day__c bookedDay = new Interview_Day__c(
            Zone__c = zoneRecord.Id,
            Zone_Name__c = 'Keep Me',
            Zone_Code__c = 50.04,
            Schedule_Mode__c = 'Morning',
            Total_Slots__c = 1,
            Year__c = Date.today().year(),
            Status__c = 'Planned',
            Interview_Date__c = Date.today().addDays(6)
        );
        insert bookedDay;

        Interview_Day_Schedule__c deletableSchedule = [
            SELECT Id, Interview_Day__c, Booked__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c = :deletableDay.Id
            LIMIT 1
        ];

        Interview_Day_Schedule__c bookedSchedule = [
            SELECT Id, Interview_Day__c, Booked__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c = :bookedDay.Id
            LIMIT 1
        ];
        bookedSchedule.Booked__c = true;
        update bookedSchedule;

        Test.startTest();
        InterviewDayUiHelper.DeleteSelectedSchedulesResultDTO result = InterviewDayUiHelper.deleteSelectedInterviewSchedules(
            new List<Id>{ deletableSchedule.Id, bookedSchedule.Id }
        );
        Test.stopTest();

        System.assertEquals(1, result.deletedScheduleCount, 'Exactly one unbooked placeholder row should be deleted.');
        System.assertEquals(1, result.skippedBookedCount, 'Booked placeholder rows should be skipped.');
        System.assertEquals(1, result.deletedInterviewDayCount, 'Empty planned Interview Day parents should be cleaned up.');
        System.assertEquals(0, [SELECT COUNT() FROM Interview_Day_Schedule__c WHERE Id = :deletableSchedule.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM Interview_Day__c WHERE Id = :deletableDay.Id]);
        System.assertEquals(1, [SELECT COUNT() FROM Interview_Day_Schedule__c WHERE Id = :bookedSchedule.Id]);
        System.assertEquals(1, [SELECT COUNT() FROM Interview_Day__c WHERE Id = :bookedDay.Id]);
    }

    @isTest
    static void testHelperErrorPaths_throwingCatchBlocks() {
        Zone__c z = getAnyActiveZone();
        HGH_Zone_Code__c zc = [SELECT Id FROM HGH_Zone_Code__c WHERE Zone__c = :z.Id LIMIT 1];

        Boolean threw;

        // Invalid mode for zone-wide processing
        threw = false;
        try { InterviewDayUiHelper.processInterviewPlaceholders(z.Id, 'InvalidMode', 1); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Invalid mode should throw in processInterviewPlaceholders');

        // Invalid mode for selected codes
        threw = false;
        try { InterviewDayUiHelper.processSelectedInterviewPlaceholders(new List<Id>{ zc.Id }, 'InvalidMode', 1); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Invalid mode should throw in processSelectedInterviewPlaceholders');

        // Empty list for selected codes
        threw = false;
        try { InterviewDayUiHelper.processSelectedInterviewPlaceholders(new List<Id>(), 'Morning', 1); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Empty selected list should throw');

        // Invalid mode for generateInterviewDays
        threw = false;
        try { InterviewDayUiHelper.generateInterviewDays(zc.Id, 'InvalidMode', 1, Date.today().year()); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Invalid mode should throw in generateInterviewDays');

        // Null zone code Id for generateInterviewDays
        threw = false;
        try { InterviewDayUiHelper.generateInterviewDays(null, 'Morning', 1, Date.today().year()); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Null zoneCodeId should throw in generateInterviewDays');
    }

    @isTest
    static void testScheduleUtilitiesAuditPreviewAndGenerateLifecycle() {
        Integer scheduleYear = Date.today().year() + 1;
        Zone__c zoneRecord = new Zone__c(Name = 'Schedule Utility Zone', Active__c = true, Schedule_Mode__c = 'Morning');
        insert zoneRecord;
        HGH_Zone_Code__c zoneCodeOne = new HGH_Zone_Code__c(Zone__c = zoneRecord.Id, Code__c = '61.01', Name = '61.01', Active__c = true);
        HGH_Zone_Code__c zoneCodeTwo = new HGH_Zone_Code__c(Zone__c = zoneRecord.Id, Code__c = '61.02', Name = '61.02', Active__c = true);
        insert new List<HGH_Zone_Code__c>{ zoneCodeOne, zoneCodeTwo };
        insert new List<Zone_Rule__c>{
            new Zone_Rule__c(Zone__c = zoneRecord.Id, Month__c = 10, Ordinal__c = 1, DayOfWeek__c = 'Monday', Mode__c = 'Morning', Active__c = true),
            new Zone_Rule__c(Zone__c = zoneRecord.Id, Month__c = 11, Ordinal__c = 5, DayOfWeek__c = 'Friday', Mode__c = 'Afternoon', Active__c = false)
        };

        List<InterviewDayUiHelper.OptionDTO> zoneOptions = InterviewDayUiHelper.getZoneOptions();
        System.assert(zoneOptions.size() > 0, 'Zone options should include active zones.');

        Id ensuredYearId = InterviewDayUiHelper.ensureScheduleYear(scheduleYear);
        System.assertNotEquals(null, ensuredYearId, 'ensureScheduleYear should create or return a record.');
        System.assertEquals(ensuredYearId, InterviewDayUiHelper.ensureScheduleYear(scheduleYear), 'ensureScheduleYear should reuse an existing record.');

        List<InterviewDayUiHelper.OptionDTO> yearOptions = InterviewDayUiHelper.getYearOptions();
        System.assert(yearOptions.size() > 0, 'Year options should include the ensured schedule year.');

        List<InterviewDayUiHelper.RuleAuditRowDTO> activeOnlyRows = InterviewDayUiHelper.auditRules(scheduleYear, new List<Id>{ zoneRecord.Id }, false);
        System.assert(activeOnlyRows.size() > 0, 'Active rules should be surfaced in the audit.');
        List<InterviewDayUiHelper.RuleAuditRowDTO> includingInactiveRows = InterviewDayUiHelper.auditRules(scheduleYear, new List<Id>{ zoneRecord.Id }, true);
        System.assert(includingInactiveRows.size() >= activeOnlyRows.size(), 'Including inactive rules should not reduce the result set.');

        List<InterviewDayUiHelper.PreviewRowDTO> previewRows = InterviewDayUiHelper.preview(scheduleYear, new List<Id>{ zoneRecord.Id });
        System.assert(previewRows.size() >= 2, 'Preview should create one row per active zone code.');
        System.assertEquals(false, previewRows[0].exists, 'Preview rows should start as non-existent before generation.');

        InterviewDayUiHelper.GenerationResultDTO firstGeneration = InterviewDayUiHelper.generate(
            scheduleYear,
            new List<Id>{ zoneRecord.Id },
            'CREATE_NEW'
        );

        System.assert(firstGeneration.createdCount > 0, 'Initial generation should create planned schedule dates.');

        List<InterviewDayUiHelper.PreviewRowDTO> previewAfterGenerate = InterviewDayUiHelper.preview(scheduleYear, new List<Id>{ zoneRecord.Id });
        System.assertEquals(true, previewAfterGenerate[0].exists, 'Generated rows should be detected on preview.');

        InterviewDayUiHelper.YearSummaryDTO summary = InterviewDayUiHelper.getScheduleYearSummary(scheduleYear);
        System.assert(summary.totalCount >= firstGeneration.createdCount, 'Year summary should reflect generated rows.');
        System.assert(summary.byZone.size() > 0, 'Zone breakdown should be populated after generation.');

        InterviewDayUiHelper.OverrideRowDTO overrideRow = new InterviewDayUiHelper.OverrideRowDTO();
        overrideRow.zoneId = previewAfterGenerate[0].zoneId;
        overrideRow.zoneCodeId = previewAfterGenerate[0].zoneCodeId;
        overrideRow.ruleId = previewAfterGenerate[0].ruleId;
        overrideRow.mode = previewAfterGenerate[0].mode;
        overrideRow.calculatedDate = previewAfterGenerate[0].calculatedDate.addDays(7);
        overrideRow.exists = true;
        overrideRow.isPublished = false;

        InterviewDayUiHelper.GenerationResultDTO overwriteResult = InterviewDayUiHelper.generateWithOverrides(
            scheduleYear,
            'OVERWRITE_PLANNED',
            new List<InterviewDayUiHelper.OverrideRowDTO>{ overrideRow }
        );

        System.assertEquals(1, overwriteResult.updatedCount, 'Override generation should update the matching planned row.');
    }

    @isTest
    static void testOverrideDeleteCleansUpGeneratedPlaceholdersAndSelectedYear() {
        Integer scheduleYear = Date.today().year() + 2;
        Zone__c zoneRecord = new Zone__c(Name = 'Cleanup Zone', Active__c = true, Schedule_Mode__c = 'Morning');
        insert zoneRecord;
        HGH_Zone_Code__c zoneCodeOne = new HGH_Zone_Code__c(Zone__c = zoneRecord.Id, Code__c = '71.01', Name = '71.01', Active__c = true);
        HGH_Zone_Code__c zoneCodeTwo = new HGH_Zone_Code__c(Zone__c = zoneRecord.Id, Code__c = '71.02', Name = '71.02', Active__c = true);
        insert new List<HGH_Zone_Code__c>{ zoneCodeOne, zoneCodeTwo };
        insert new Zone_Rule__c(Zone__c = zoneRecord.Id, Month__c = 10, Ordinal__c = 1, DayOfWeek__c = 'Monday', Mode__c = 'Morning', Active__c = true);

        InterviewDayUiHelper.generate(scheduleYear, new List<Id>{ zoneRecord.Id }, 'CREATE_NEW');

        List<Schedule_Date__c> generatedDates = [
            SELECT Id, Zone__c, Zone_Code__c, Zone_Rule__c, Mode__c, Calculated_Date__c
            FROM Schedule_Date__c
            WHERE Zone__c = :zoneRecord.Id AND Schedule_Year__r.Year__c = :scheduleYear
            ORDER BY CreatedDate ASC
        ];
        System.assert(generatedDates.size() >= 2, 'Two active zone codes should produce at least two schedule-date rows.');

        Schedule_Date__c selectedDate = generatedDates[0];

        String processMessage = InterviewDayUiHelper.processPlaceholdersByDates(
            zoneRecord.Id,
            new List<Id>{ selectedDate.Id },
            'Morning',
            3
        );
        System.assert(processMessage.contains('Processed'), 'Placeholder generation should succeed for the selected schedule date.');

        Interview_Day__c generatedDay = [
            SELECT Id, Year__c, Interview_Date__c
            FROM Interview_Day__c
            WHERE Zone__c = :zoneRecord.Id
              AND Interview_Date__c = :selectedDate.Calculated_Date__c
              AND Schedule_Mode__c = 'Morning'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(scheduleYear, Integer.valueOf(generatedDay.Year__c), 'Generated interview days must honor the selected schedule year.');

        InterviewDayUiHelper.OverrideRowDTO deleteRow = new InterviewDayUiHelper.OverrideRowDTO();
        deleteRow.zoneId = selectedDate.Zone__c;
        deleteRow.zoneCodeId = selectedDate.Zone_Code__c;
        deleteRow.ruleId = selectedDate.Zone_Rule__c;
        deleteRow.mode = selectedDate.Mode__c;
        deleteRow.calculatedDate = selectedDate.Calculated_Date__c;
        deleteRow.exists = true;
        deleteRow.isPublished = false;

        InterviewDayUiHelper.DeleteResultDTO deleteResult = InterviewDayUiHelper.deleteScheduleDatesWithOverrides(
            scheduleYear,
            new List<InterviewDayUiHelper.OverrideRowDTO>{ deleteRow }
        );

        System.assert(deleteResult.deletedCount >= 1, 'Deleting a selected preview date should remove at least one planned schedule-date row.');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Interview_Day__c WHERE Id = :generatedDay.Id],
            'Deleting the selected schedule date should clean up generated planned interview days for the same zone/date.'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Interview_Day_Schedule__c WHERE Interview_Day__c = :generatedDay.Id],
            'Deleting the selected schedule date should also remove generated placeholder schedules.'
        );

        InterviewDayUiHelper.DeleteResultDTO emptyDeleteResult = InterviewDayUiHelper.deleteScheduleDates(1991, null);
        System.assertEquals(0, emptyDeleteResult.deletedCount, 'Deleting a year with no schedule year record should return zero.');
    }

    @isTest
    static void testInterviewDayTriggersAndScheduleSyncBehavior() {
        Zone__c zoneRecord = new Zone__c(Name = 'Trigger Zone', Active__c = true, Schedule_Mode__c = 'Morning');
        insert zoneRecord;

        Date interviewDate = Date.today().addDays(10);
        Interview_Day__c interviewDay = new Interview_Day__c(
            Zone__c = zoneRecord.Id,
            Zone_Name__c = zoneRecord.Name,
            Schedule_Mode__c = 'Morning',
            Interview_Date__c = interviewDate,
            Total_Slots__c = 2,
            Year__c = interviewDate.year(),
            Status__c = 'Planned'
        );
        insert interviewDay;

        List<Interview_Day_Schedule__c> autoSchedules = [
            SELECT Id, Name, Zone__c, Booked__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c = :interviewDay.Id
            ORDER BY Name ASC
        ];
        System.assertEquals(2, autoSchedules.size(), 'Interview day insert should create the requested number of child schedules.');

        Interview_Day_Schedule__c renamedSchedule = new Interview_Day_Schedule__c(
            Interview_Day__c = interviewDay.Id,
            Name = ''
        );
        insert renamedSchedule;

        renamedSchedule = [
            SELECT Id, Name, Zone__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :renamedSchedule.Id
        ];
        System.assertEquals(zoneRecord.Id, renamedSchedule.Zone__c, 'The schedule sync trigger should copy the parent zone to the child.');
        System.assert(renamedSchedule.Name.contains('Slot'), 'Blank names should be rebuilt by the schedule sync trigger.');

        autoSchedules[0].Booked__c = true;
        update autoSchedules[0];

        interviewDay.Total_Slots__c = 0;
        Boolean threw = false;
        try {
            update interviewDay;
        } catch (DmlException ex) {
            threw = true;
        }
        System.assert(threw, 'Reducing total slots below the number of booked schedules should be blocked.');

        Boolean deleteBlocked = false;
        try {
            delete autoSchedules[0];
        } catch (DmlException ex) {
            deleteBlocked = true;
        }
        System.assert(deleteBlocked, 'Booked schedules should not be deletable.');

        delete autoSchedules[1];
        System.assertEquals(0, [SELECT COUNT() FROM Interview_Day_Schedule__c WHERE Id = :autoSchedules[1].Id], 'Unbooked schedules should remain deletable.');
    }
}