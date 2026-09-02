public with sharing class InterviewDayUiHelper {

    public class DeleteSelectedSchedulesResultDTO {
        @AuraEnabled public Integer deletedScheduleCount;
        @AuraEnabled public Integer skippedBookedCount;
        @AuraEnabled public Integer deletedInterviewDayCount;
    }

    public class OptionDTO {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class YearSummaryDTO {
        @AuraEnabled public Id scheduleYearId;
        @AuraEnabled public Integer plannedCount;
        @AuraEnabled public Integer publishedCount;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public List<ZoneSummaryDTO> byZone;
    }

    public class ZoneSummaryDTO {
        @AuraEnabled public Id zoneId;
        @AuraEnabled public String zoneName;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Integer plannedRecords;
        @AuraEnabled public Integer publishedRecords;
    }

    public class PreviewRowDTO {
        @AuraEnabled public Id zoneId;
        @AuraEnabled public String zoneName;
        @AuraEnabled public Id ruleId;
        @AuraEnabled public Integer month;
        @AuraEnabled public Integer ordinal;
        @AuraEnabled public Integer dow;
        @AuraEnabled public String mode;
        @AuraEnabled public Id zoneCodeId;
        @AuraEnabled public String zoneCode;
        @AuraEnabled public Date calculatedDate;
        @AuraEnabled public Boolean exists;
        @AuraEnabled public Boolean isPublished;
        @AuraEnabled public String action;
    }

    public class RuleAuditRowDTO {
        @AuraEnabled public Id ruleId;
        @AuraEnabled public String ruleLabel;
        @AuraEnabled public Date calculatedDate;
        @AuraEnabled public String zoneName;
        @AuraEnabled public String mode;
        @AuraEnabled public Integer month;
        @AuraEnabled public Integer ordinal;
        @AuraEnabled public Integer dow;
    }

    public class GenerationResultDTO {
        @AuraEnabled public String batchId;
        @AuraEnabled public Integer createdCount;
        @AuraEnabled public Integer updatedCount;
        @AuraEnabled public Integer skippedPublished;
        @AuraEnabled public Id scheduleYearId;
        @AuraEnabled public Integer totalPlanned;
    }

    public class OverrideRowDTO {
        @AuraEnabled public Id zoneId;
        @AuraEnabled public Id zoneCodeId;
        @AuraEnabled public Id ruleId;
        @AuraEnabled public String mode;
        @AuraEnabled public Date calculatedDate;
        @AuraEnabled public Boolean exists;
        @AuraEnabled public Boolean isPublished;
        @AuraEnabled public String action;
    }

    public class DeleteResultDTO {
        @AuraEnabled public Integer deletedCount;
    }

    @AuraEnabled(cacheable=true)
    public static List<OptionDTO> getZoneOptions() {
        List<OptionDTO> options = new List<OptionDTO>();
        for (Zone__c zoneRecord : [
            SELECT Id, Name
            FROM Zone__c
            WHERE Active__c = true
            WITH USER_MODE
            ORDER BY Name
        ]) {
            OptionDTO option = new OptionDTO();
            option.label = zoneRecord.Name;
            option.value = (String) zoneRecord.Id;
            options.add(option);
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<Zone__c> getZones() {
        try {
            return [
                SELECT Id, Name
                FROM Zone__c
                WHERE Active__c = true
                WITH USER_MODE
                ORDER BY Name ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching zones: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Id ensureScheduleYear(Integer year) {
        if (year == null) {
            throw new AuraHandledException('Year is required');
        }
        return ensureScheduleYearRecord(year).Id;
    }

    @AuraEnabled(cacheable=true)
    public static List<OptionDTO> getYearOptions() {
        List<OptionDTO> options = new List<OptionDTO>();
        for (Schedule_Year__c scheduleYear : [
            SELECT Year__c
            FROM Schedule_Year__c
            WITH USER_MODE
            ORDER BY Year__c DESC
            LIMIT 100
        ]) {
            OptionDTO option = new OptionDTO();
            option.label = String.valueOf(scheduleYear.Year__c);
            option.value = String.valueOf(scheduleYear.Year__c);
            options.add(option);
        }
        return options;
    }

    @AuraEnabled
    public static YearSummaryDTO getScheduleYearSummary(Integer year) {
        if (year == null) {
            throw new AuraHandledException('Year is required');
        }

        YearSummaryDTO dto = new YearSummaryDTO();
        dto.plannedCount = 0;
        dto.publishedCount = 0;
        dto.totalCount = 0;
        dto.byZone = new List<ZoneSummaryDTO>();

        List<Schedule_Year__c> years = [
            SELECT Id
            FROM Schedule_Year__c
            WHERE Year__c = :year
            WITH USER_MODE
            LIMIT 1
        ];
        if (years.isEmpty()) {
            return dto;
        }

        Id scheduleYearId = years[0].Id;
        dto.scheduleYearId = scheduleYearId;

        for (AggregateResult ar : [
            SELECT Status__c statusValue, COUNT(Id) totalCount
            FROM Schedule_Date__c
            WHERE Schedule_Year__c = :scheduleYearId
            WITH USER_MODE
            GROUP BY Status__c
        ]) {
            String statusValue = (String) ar.get('statusValue');
            Integer totalCount = (Integer) ar.get('totalCount');
            dto.totalCount += totalCount;
            if (statusValue == 'Planned') {
                dto.plannedCount += totalCount;
            } else if (statusValue == 'Published') {
                dto.publishedCount += totalCount;
            }
        }

        Map<Id, ZoneSummaryDTO> zoneSummariesById = new Map<Id, ZoneSummaryDTO>();
        for (AggregateResult ar : [
            SELECT Zone__c zoneId, Zone__r.Name zoneName, Status__c statusValue, COUNT(Id) totalCount
            FROM Schedule_Date__c
            WHERE Schedule_Year__c = :scheduleYearId
            WITH USER_MODE
            GROUP BY Zone__c, Zone__r.Name, Status__c
        ]) {
            Id zoneId = (Id) ar.get('zoneId');
            String zoneName = (String) ar.get('zoneName');
            String statusValue = (String) ar.get('statusValue');
            Integer totalCount = (Integer) ar.get('totalCount');

            if (!zoneSummariesById.containsKey(zoneId)) {
                ZoneSummaryDTO zoneSummary = new ZoneSummaryDTO();
                zoneSummary.zoneId = zoneId;
                zoneSummary.zoneName = zoneName;
                zoneSummary.totalRecords = 0;
                zoneSummary.plannedRecords = 0;
                zoneSummary.publishedRecords = 0;
                zoneSummariesById.put(zoneId, zoneSummary);
            }

            ZoneSummaryDTO zoneSummary = zoneSummariesById.get(zoneId);
            zoneSummary.totalRecords += totalCount;
            if (statusValue == 'Planned') {
                zoneSummary.plannedRecords += totalCount;
            } else if (statusValue == 'Published') {
                zoneSummary.publishedRecords += totalCount;
            }
        }

        dto.byZone = zoneSummariesById.values();
        return dto;
    }

    @AuraEnabled(cacheable=true)
    public static List<RuleAuditRowDTO> auditRules(Integer year, List<Id> zoneIds, Boolean includeInactive) {
        if (year == null) {
            throw new AuraHandledException('Year is required');
        }

        List<Zone_Rule__c> rules;
        if (zoneIds != null && !zoneIds.isEmpty()) {
            if (includeInactive == true) {
                rules = [
                    SELECT Id, Zone__c, Month__c, Ordinal__c, DayOfWeek__c, Mode__c, Active__c
                    FROM Zone_Rule__c
                    WHERE Zone__c IN :zoneIds
                    WITH USER_MODE
                ];
            } else {
                rules = [
                    SELECT Id, Zone__c, Month__c, Ordinal__c, DayOfWeek__c, Mode__c, Active__c
                    FROM Zone_Rule__c
                    WHERE Zone__c IN :zoneIds AND Active__c = true
                    WITH USER_MODE
                ];
            }
        } else {
            if (includeInactive == true) {
                rules = [
                    SELECT Id, Zone__c, Month__c, Ordinal__c, DayOfWeek__c, Mode__c, Active__c
                    FROM Zone_Rule__c
                    WITH USER_MODE
                ];
            } else {
                rules = [
                    SELECT Id, Zone__c, Month__c, Ordinal__c, DayOfWeek__c, Mode__c, Active__c
                    FROM Zone_Rule__c
                    WHERE Active__c = true
                    WITH USER_MODE
                ];
            }
        }

        if (rules.isEmpty()) {
            return new List<RuleAuditRowDTO>();
        }

        Set<Id> zoneIdSet = new Set<Id>();
        for (Zone_Rule__c rule : rules) {
            zoneIdSet.add(rule.Zone__c);
        }

        Map<Id, Zone__c> zoneMap = new Map<Id, Zone__c>([
            SELECT Id, Name
            FROM Zone__c
            WHERE Id IN :zoneIdSet
            WITH USER_MODE
        ]);

        List<RuleAuditRowDTO> rows = new List<RuleAuditRowDTO>();
        for (Zone_Rule__c rule : rules) {
            Integer monthValue = (Integer) rule.Month__c;
            Integer ordinalValue = (Integer) rule.Ordinal__c;
            Integer dowValue = dowFromPick(rule.DayOfWeek__c);
            if (monthValue == null || ordinalValue == null || dowValue == null) {
                continue;
            }

            RuleAuditRowDTO row = new RuleAuditRowDTO();
            row.ruleId = rule.Id;
            row.zoneName = zoneMap.get(rule.Zone__c)?.Name;
            row.mode = String.isBlank(rule.Mode__c) ? 'Default' : rule.Mode__c;
            row.month = monthValue;
            row.ordinal = ordinalValue;
            row.dow = dowValue;
            row.calculatedDate = nthWeekday(year, monthValue, ordinalValue, dowValue);
            row.ruleLabel = buildRuleLabel(row.zoneName, row.mode, ordinalValue, dowValue, monthValue);
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<PreviewRowDTO> preview(Integer year, List<Id> zoneIds) {
        return calculateScheduleDates(year, zoneIds);
    }

    @AuraEnabled
    public static GenerationResultDTO generate(Integer year, List<Id> zoneIds, String action) {
        if (year == null) {
            throw new AuraHandledException('Year is required');
        }
        if (String.isBlank(action)) {
            throw new AuraHandledException('Action is required');
        }

        Schedule_Year__c scheduleYear = ensureScheduleYearRecord(year);
        List<PreviewRowDTO> plannedRows = calculateScheduleDates(year, zoneIds);

        String batchId = String.valueOf(Crypto.getRandomInteger());
        Integer createdCount = 0;
        Integer updatedCount = 0;
        Integer skippedCount = 0;
        List<Schedule_Date__c> recordsToUpsert = new List<Schedule_Date__c>();

        Map<String, Schedule_Date__c> existingByIdentity = new Map<String, Schedule_Date__c>();
        for (Schedule_Date__c scheduleDate : [
            SELECT Id, Unique_Key__c, Status__c, Zone__c, Zone_Code__c, Zone_Rule__c, Mode__c, Calculated_Date__c
            FROM Schedule_Date__c
            WHERE Schedule_Year__c = :scheduleYear.Id
            WITH USER_MODE
        ]) {
            existingByIdentity.put(
                buildIdentityKey(year, scheduleDate.Zone__c, scheduleDate.Zone_Code__c, scheduleDate.Zone_Rule__c, scheduleDate.Mode__c),
                scheduleDate
            );
        }

        for (PreviewRowDTO row : plannedRows) {
            String key = buildKey(year, row.zoneId, row.zoneCodeId, row.ruleId, row.mode, row.calculatedDate);
            String identityKey = buildIdentityKey(year, row.zoneId, row.zoneCodeId, row.ruleId, row.mode);

            if (row.isPublished) {
                skippedCount++;
                continue;
            }

            if ('CREATE_NEW'.equalsIgnoreCase(action) && row.exists) {
                continue;
            }

            if ('OVERWRITE_PLANNED'.equalsIgnoreCase(action) && row.exists) {
                Schedule_Date__c currentRecord = existingByIdentity.get(identityKey);
                if (currentRecord != null && currentRecord.Status__c == 'Planned') {
                    currentRecord.Zone__c = row.zoneId;
                    currentRecord.Zone_Code__c = row.zoneCodeId;
                    currentRecord.Zone_Rule__c = row.ruleId;
                    currentRecord.Mode__c = row.mode;
                    currentRecord.Calculated_Date__c = row.calculatedDate;
                    currentRecord.Name = buildScheduleDateName(row.zoneName, row.zoneCode, row.calculatedDate);
                    currentRecord.Generated_Batch_Id__c = batchId;
                    currentRecord.Unique_Key__c = key;
                    recordsToUpsert.add(currentRecord);
                    updatedCount++;
                } else {
                    skippedCount++;
                }
                continue;
            }

            if (!row.exists) {
                Schedule_Date__c scheduleDate = new Schedule_Date__c();
                scheduleDate.Name = buildScheduleDateName(row.zoneName, row.zoneCode, row.calculatedDate);
                scheduleDate.Schedule_Year__c = scheduleYear.Id;
                scheduleDate.Zone__c = row.zoneId;
                scheduleDate.Zone_Code__c = row.zoneCodeId;
                scheduleDate.Zone_Rule__c = row.ruleId;
                scheduleDate.Mode__c = row.mode;
                scheduleDate.Calculated_Date__c = row.calculatedDate;
                scheduleDate.Status__c = 'Planned';
                scheduleDate.Generated_Batch_Id__c = batchId;
                scheduleDate.Unique_Key__c = key;
                recordsToUpsert.add(scheduleDate);
                createdCount++;
            }
        }

        if (!recordsToUpsert.isEmpty()) {
            upsert as user recordsToUpsert Unique_Key__c;
        }

        GenerationResultDTO result = new GenerationResultDTO();
        result.batchId = batchId;
        result.createdCount = createdCount;
        result.updatedCount = updatedCount;
        result.skippedPublished = skippedCount;
        result.scheduleYearId = scheduleYear.Id;
        result.totalPlanned = plannedRows.size();
        return result;
    }

    @AuraEnabled
    public static GenerationResultDTO generateWithOverrides(Integer year, String action, List<OverrideRowDTO> overrides) {
        if (year == null) {
            throw new AuraHandledException('Year is required');
        }
        if (String.isBlank(action)) {
            throw new AuraHandledException('Action is required');
        }
        if (overrides == null || overrides.isEmpty()) {
            throw new AuraHandledException('No overrides provided');
        }

        Schedule_Year__c scheduleYear = ensureScheduleYearRecord(year);
        String batchId = String.valueOf(Crypto.getRandomInteger());
        Integer createdCount = 0;
        Integer updatedCount = 0;
        Integer skippedCount = 0;

        Set<Id> zoneIds = new Set<Id>();
        Set<Id> zoneCodeIds = new Set<Id>();
        for (OverrideRowDTO row : overrides) {
            zoneIds.add(row.zoneId);
            zoneCodeIds.add(row.zoneCodeId);
        }

        Map<Id, Zone__c> zoneMap = new Map<Id, Zone__c>([
            SELECT Id, Name
            FROM Zone__c
            WHERE Id IN :zoneIds
            WITH USER_MODE
        ]);
        Map<Id, HGH_Zone_Code__c> zoneCodeMap = new Map<Id, HGH_Zone_Code__c>([
            SELECT Id, Code__c
            FROM HGH_Zone_Code__c
            WHERE Id IN :zoneCodeIds
            WITH USER_MODE
        ]);

        Map<String, Schedule_Date__c> existingByKey = new Map<String, Schedule_Date__c>();
        Map<String, Schedule_Date__c> existingByIdentity = new Map<String, Schedule_Date__c>();
        for (Schedule_Date__c scheduleDate : [
            SELECT Id, Unique_Key__c, Status__c, Zone__c, Zone_Code__c, Zone_Rule__c, Mode__c, Calculated_Date__c
            FROM Schedule_Date__c
            WHERE Schedule_Year__c = :scheduleYear.Id
            WITH USER_MODE
        ]) {
            existingByKey.put(scheduleDate.Unique_Key__c, scheduleDate);
            existingByIdentity.put(
                buildIdentityKey(year, scheduleDate.Zone__c, scheduleDate.Zone_Code__c, scheduleDate.Zone_Rule__c, scheduleDate.Mode__c),
                scheduleDate
            );
        }

        List<Schedule_Date__c> recordsToUpdate = new List<Schedule_Date__c>();
        List<Schedule_Date__c> recordsToInsert = new List<Schedule_Date__c>();

        for (OverrideRowDTO row : overrides) {
            if (row.calculatedDate == null) {
                continue;
            }

            String key = buildKey(year, row.zoneId, row.zoneCodeId, row.ruleId, row.mode, row.calculatedDate);
            String identityKey = buildIdentityKey(year, row.zoneId, row.zoneCodeId, row.ruleId, row.mode);

            if (row.isPublished == true) {
                skippedCount++;
                continue;
            }

            Schedule_Date__c currentRecord = existingByKey.get(key);
            if (currentRecord == null) {
                currentRecord = existingByIdentity.get(identityKey);
            }
            Boolean exists = currentRecord != null || row.exists == true;

            if ('CREATE_NEW'.equalsIgnoreCase(action) && exists) {
                continue;
            }

            if (exists) {
                if ('OVERWRITE_PLANNED'.equalsIgnoreCase(action)) {
                    if (currentRecord == null) {
                        skippedCount++;
                        continue;
                    }
                    if (currentRecord.Status__c == 'Planned') {
                        currentRecord.Zone__c = row.zoneId;
                        currentRecord.Zone_Code__c = row.zoneCodeId;
                        currentRecord.Zone_Rule__c = row.ruleId;
                        currentRecord.Mode__c = row.mode;
                        currentRecord.Calculated_Date__c = row.calculatedDate;
                        currentRecord.Name = buildScheduleDateName(zoneMap.get(row.zoneId)?.Name, zoneCodeMap.get(row.zoneCodeId)?.Code__c, row.calculatedDate);
                        currentRecord.Generated_Batch_Id__c = batchId;
                        currentRecord.Unique_Key__c = key;
                        recordsToUpdate.add(currentRecord);
                        updatedCount++;
                    } else {
                        skippedCount++;
                    }
                }
                continue;
            }

            Schedule_Date__c scheduleDate = new Schedule_Date__c();
            scheduleDate.Name = buildScheduleDateName(zoneMap.get(row.zoneId)?.Name, zoneCodeMap.get(row.zoneCodeId)?.Code__c, row.calculatedDate);
            scheduleDate.Schedule_Year__c = scheduleYear.Id;
            scheduleDate.Zone__c = row.zoneId;
            scheduleDate.Zone_Code__c = row.zoneCodeId;
            scheduleDate.Zone_Rule__c = row.ruleId;
            scheduleDate.Mode__c = row.mode;
            scheduleDate.Calculated_Date__c = row.calculatedDate;
            scheduleDate.Status__c = 'Planned';
            scheduleDate.Generated_Batch_Id__c = batchId;
            scheduleDate.Unique_Key__c = key;
            recordsToInsert.add(scheduleDate);
            createdCount++;
        }

        if (!recordsToUpdate.isEmpty()) {
            update as user recordsToUpdate;
        }
        if (!recordsToInsert.isEmpty()) {
            upsert as user recordsToInsert Unique_Key__c;
        }

        GenerationResultDTO result = new GenerationResultDTO();
        result.batchId = batchId;
        result.createdCount = createdCount;
        result.updatedCount = updatedCount;
        result.skippedPublished = skippedCount;
        result.scheduleYearId = scheduleYear.Id;
        result.totalPlanned = overrides.size();
        return result;
    }

    @AuraEnabled
    public static DeleteResultDTO deleteScheduleDates(Integer year, List<Id> zoneIds) {
        if (year == null) {
            throw new AuraHandledException('Year is required');
        }

        DeleteResultDTO dto = new DeleteResultDTO();
        dto.deletedCount = 0;

        List<Schedule_Year__c> years = [
            SELECT Id
            FROM Schedule_Year__c
            WHERE Year__c = :year
            WITH USER_MODE
            LIMIT 1
        ];
        if (years.isEmpty()) {
            return dto;
        }

        List<Schedule_Date__c> toDelete;
        if (zoneIds != null && !zoneIds.isEmpty()) {
            toDelete = [
                SELECT Id
                FROM Schedule_Date__c
                WHERE Schedule_Year__c = :years[0].Id AND Zone__c IN :zoneIds
                WITH USER_MODE
            ];
        } else {
            toDelete = [
                SELECT Id
                FROM Schedule_Date__c
                WHERE Schedule_Year__c = :years[0].Id
                WITH USER_MODE
            ];
        }

        if (!toDelete.isEmpty()) {
            delete as user toDelete;
            dto.deletedCount = toDelete.size();
        }
        return dto;
    }

    @AuraEnabled
    public static DeleteResultDTO deleteScheduleDatesWithOverrides(Integer year, List<OverrideRowDTO> overrides) {
        if (year == null) {
            throw new AuraHandledException('Year is required');
        }
        if (overrides == null || overrides.isEmpty()) {
            throw new AuraHandledException('Select at least one schedule row to delete.');
        }

        DeleteResultDTO dto = new DeleteResultDTO();
        dto.deletedCount = 0;

        List<Schedule_Year__c> years = [
            SELECT Id
            FROM Schedule_Year__c
            WHERE Year__c = :year
            WITH USER_MODE
            LIMIT 1
        ];
        if (years.isEmpty()) {
            return dto;
        }

        Set<String> selectedIdentityKeys = new Set<String>();
        Set<String> selectedZoneDateKeys = new Set<String>();
        for (OverrideRowDTO row : overrides) {
            if (row == null) {
                continue;
            }
            if (row.zoneId != null && row.zoneCodeId != null && row.ruleId != null && !String.isBlank(row.mode)) {
                selectedIdentityKeys.add(buildIdentityKey(year, row.zoneId, row.zoneCodeId, row.ruleId, row.mode));
            }
            if (row.zoneId != null && row.calculatedDate != null) {
                selectedZoneDateKeys.add(buildZoneDateKey(row.zoneId, row.calculatedDate));
            }
        }

        if (selectedIdentityKeys.isEmpty() && selectedZoneDateKeys.isEmpty()) {
            return dto;
        }

        List<Schedule_Date__c> toDelete = new List<Schedule_Date__c>();
        Set<String> deletedZoneDateKeys = new Set<String>();
        Set<Id> deletedZoneIds = new Set<Id>();
        Set<Date> deletedDates = new Set<Date>();
        for (Schedule_Date__c scheduleDate : [
            SELECT Id, Zone__c, Zone_Code__c, Zone_Rule__c, Mode__c, Status__c, Calculated_Date__c
            FROM Schedule_Date__c
            WHERE Schedule_Year__c = :years[0].Id
            WITH USER_MODE
        ]) {
            if (scheduleDate.Status__c == 'Published') {
                continue;
            }

            String identityKey = buildIdentityKey(year, scheduleDate.Zone__c, scheduleDate.Zone_Code__c, scheduleDate.Zone_Rule__c, scheduleDate.Mode__c);
            String zoneDateKey = buildZoneDateKey(scheduleDate.Zone__c, scheduleDate.Calculated_Date__c);
            if (selectedIdentityKeys.contains(identityKey) || selectedZoneDateKeys.contains(zoneDateKey)) {
                toDelete.add(scheduleDate);
                if (scheduleDate.Zone__c != null && scheduleDate.Calculated_Date__c != null) {
                    deletedZoneDateKeys.add(zoneDateKey);
                    deletedZoneIds.add(scheduleDate.Zone__c);
                    deletedDates.add(scheduleDate.Calculated_Date__c);
                }
            }
        }

        if (!toDelete.isEmpty()) {
            delete as user toDelete;
            dto.deletedCount = toDelete.size();
            cleanupGeneratedPlaceholderRecords(deletedZoneIds, deletedDates, deletedZoneDateKeys);
        }
        return dto;
    }

    @AuraEnabled
    public static DeleteSelectedSchedulesResultDTO deleteAllSchedules() {
        DeleteSelectedSchedulesResultDTO dto = new DeleteSelectedSchedulesResultDTO();
        dto.deletedScheduleCount = 0;
        dto.skippedBookedCount = 0;
        dto.deletedInterviewDayCount = 0;

        try {
            List<Interview_Day_Schedule__c> unbookedSchedules = [
                SELECT Id
                FROM Interview_Day_Schedule__c
                WHERE Booked__c = false OR Booked__c = null
                WITH USER_MODE
            ];
            if (!unbookedSchedules.isEmpty()) {
                delete as user unbookedSchedules;
                dto.deletedScheduleCount = unbookedSchedules.size();
            }

            Set<Id> protectedInterviewDayIds = new Set<Id>();
            for (AggregateResult ar : [
                SELECT Interview_Day__c interviewDayId
                FROM Interview_Day_Schedule__c
                WHERE Interview_Day__c != null AND Booked__c = true
                WITH USER_MODE
                GROUP BY Interview_Day__c
            ]) {
                protectedInterviewDayIds.add((Id) ar.get('interviewDayId'));
            }

            List<Interview_Day__c> interviewDaysToDelete = protectedInterviewDayIds.isEmpty()
                ? [SELECT Id FROM Interview_Day__c WHERE Status__c = 'Planned' WITH USER_MODE]
                : [
                    SELECT Id
                    FROM Interview_Day__c
                    WHERE Status__c = 'Planned' AND Id NOT IN :protectedInterviewDayIds
                    WITH USER_MODE
                ];

            if (!interviewDaysToDelete.isEmpty()) {
                delete as user interviewDaysToDelete;
                dto.deletedInterviewDayCount = interviewDaysToDelete.size();
            }

            return dto;
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting Interview Day records: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Schedule_Date__c> getScheduleDatesForZone(Id zoneId, Integer year) {
        try {
            if (zoneId == null) {
                return new List<Schedule_Date__c>();
            }
            Integer resolvedYear = year == null ? Date.today().year() : year;
            return [
                SELECT Id, Calculated_Date__c, Mode__c, Status__c, Zone__c, Schedule_Year__c
                FROM Schedule_Date__c
                WHERE Zone__c = :zoneId
                AND (
                    Schedule_Year__r.Year__c = :resolvedYear
                    OR (Schedule_Year__c = NULL AND CALENDAR_YEAR(Calculated_Date__c) = :resolvedYear)
                )
                WITH USER_MODE
                ORDER BY Calculated_Date__c ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching schedule dates: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String processPlaceholdersByDates(Id zoneId, List<Id> scheduleDateIds, String mode, Integer totalSlots) {
        if (zoneId == null || scheduleDateIds == null || scheduleDateIds.isEmpty() || String.isBlank(mode) || totalSlots == null || totalSlots <= 0) {
            throw new AuraHandledException('Invalid parameters provided');
        }

        String normalizedMode = mode;
        if (normalizedMode == 'AM') normalizedMode = 'Morning';
        if (normalizedMode == 'PM') normalizedMode = 'Afternoon';
        String mappedMode = normalizedMode == 'Afternoon' ? 'AfterNoon' : normalizedMode;

        Boolean isCombinedMode = mode == 'Morning & Afternoon';
        List<String> modesToCreate = isCombinedMode
            ? new List<String>{ 'Morning', 'AfterNoon' }
            : new List<String>{ mappedMode };

        String batchId = generateBatchId();
        Map<Id, Schedule_Date__c> datesById = new Map<Id, Schedule_Date__c>([
            SELECT Id, Zone__c, Zone_Code__c, Zone_Rule__c, Calculated_Date__c, Mode__c, Schedule_Year__c, Schedule_Year__r.Year__c
            FROM Schedule_Date__c
            WHERE Id IN :scheduleDateIds
            WITH USER_MODE
        ]);
        if (datesById.isEmpty()) {
            throw new AuraHandledException('No schedule dates found for the provided selection');
        }

        Integer generationYear;
        for (Schedule_Date__c scheduleDate : datesById.values()) {
            if (scheduleDate.Zone__c != zoneId) {
                throw new AuraHandledException('Selected dates must all belong to the chosen zone');
            }
            if (scheduleDate.Calculated_Date__c == null) {
                throw new AuraHandledException('Selected dates must have a calculated interview date before placeholders can be generated');
            }

            Integer resolvedYear = scheduleDate.Schedule_Year__r != null && scheduleDate.Schedule_Year__r.Year__c != null
                ? Integer.valueOf(scheduleDate.Schedule_Year__r.Year__c)
                : scheduleDate.Calculated_Date__c.year();
            if (generationYear == null) {
                generationYear = resolvedYear;
            } else if (generationYear != resolvedYear) {
                throw new AuraHandledException('Selected dates must all belong to the same schedule year');
            }
        }

        List<Interview_Day__c> dayUpserts = new List<Interview_Day__c>();
        List<Interview_Day_Schedule__c> schedulesToInsert = new List<Interview_Day_Schedule__c>();
        Set<String> processedKeys = new Set<String>();

        for (Schedule_Date__c scheduleDate : datesById.values()) {
            for (String currentMode : modesToCreate) {
                Integer slotsForCurrentMode = getSlotsForMode(totalSlots, isCombinedMode, currentMode);
                if (slotsForCurrentMode <= 0) {
                    continue;
                }

                String uniqueKey = String.valueOf(zoneId) + '|' + String.valueOf(scheduleDate.Calculated_Date__c) + '|' + currentMode + '|' + String.valueOf(generationYear);
                if (processedKeys.contains(uniqueKey)) {
                    continue;
                }
                processedKeys.add(uniqueKey);

                Interview_Day__c interviewDay = new Interview_Day__c();
                interviewDay.Zone__c = zoneId;
                interviewDay.Schedule_Mode__c = currentMode;
                interviewDay.Total_Slots__c = slotsForCurrentMode;
                interviewDay.Year__c = generationYear;
                interviewDay.Status__c = 'Planned';
                interviewDay.Generated_Batch_Id__c = batchId;
                interviewDay.Interview_Date__c = scheduleDate.Calculated_Date__c;
                interviewDay.Unique_Key__c = uniqueKey;
                dayUpserts.add(interviewDay);
            }
        }

        if (!dayUpserts.isEmpty()) {
            upsert as user dayUpserts Interview_Day__c.Unique_Key__c;
        }

        Map<String, Interview_Day__c> dayByKey = new Map<String, Interview_Day__c>();
        Set<Date> selectedDates = new Set<Date>();
        for (Schedule_Date__c scheduleDate : datesById.values()) {
            if (scheduleDate.Calculated_Date__c != null) {
                selectedDates.add(scheduleDate.Calculated_Date__c);
            }
        }
        if (!selectedDates.isEmpty()) {
            for (Interview_Day__c interviewDay : [
                SELECT Id, Zone__c, Schedule_Mode__c, Interview_Date__c, Total_Slots__c, Year__c
                FROM Interview_Day__c
                WHERE Zone__c = :zoneId AND Interview_Date__c IN :selectedDates AND Year__c = :generationYear
                WITH USER_MODE
            ]) {
                String key = String.valueOf(interviewDay.Zone__c) + '|' + String.valueOf(interviewDay.Interview_Date__c) + '|' + interviewDay.Schedule_Mode__c + '|' + String.valueOf(generationYear);
                dayByKey.put(key, interviewDay);
            }
        }

        for (Interview_Day__c interviewDay : dayByKey.values()) {
            Integer existingCount = 0;
            for (AggregateResult ar : [
                SELECT COUNT(Id) totalCount
                FROM Interview_Day_Schedule__c
                WHERE Interview_Day__c = :interviewDay.Id
                WITH USER_MODE
            ]) {
                existingCount = (Integer) ar.get('totalCount');
            }
            Integer totalSlotsInt = interviewDay.Total_Slots__c == null ? 0 : interviewDay.Total_Slots__c.intValue();
            Integer toCreate = Math.max(0, totalSlotsInt - existingCount);
            String formattedDate = interviewDay.Interview_Date__c != null ? interviewDay.Interview_Date__c.format() : 'No Date';

            for (Integer i = existingCount + 1; i <= existingCount + toCreate; i++) {
                Interview_Day_Schedule__c scheduleRecord = new Interview_Day_Schedule__c();
                scheduleRecord.Interview_Day__c = interviewDay.Id;
                scheduleRecord.Zone__c = interviewDay.Zone__c;
                scheduleRecord.Name = formattedDate + ' ' + interviewDay.Schedule_Mode__c + ' Slot ' + i;
                scheduleRecord.Booked__c = false;
                schedulesToInsert.add(scheduleRecord);
            }
        }

        if (!schedulesToInsert.isEmpty()) {
            insert as user schedulesToInsert;
        }

        return 'Processed ' + dayByKey.size() + ' date(s) for mode "' + mode + '" with ' + schedulesToInsert.size() + ' schedule(s) created or ensured.' + '\nBatchId: ' + batchId;
    }

    @AuraEnabled(cacheable=true)
    public static List<HGH_Zone_Code__c> getZoneCodesForZone(Id zoneId) {
        try {
            return [
                SELECT Id, Name, Code__c, Zone__c
                FROM HGH_Zone_Code__c
                WHERE Zone__c = :zoneId AND Active__c = true
                WITH USER_MODE
                ORDER BY Code__c ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching zone codes: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<HGH_Zone_Code__c> getZoneCodes() {
        try {
            return [
                SELECT Id, Name, Code__c, Zone__r.Name
                FROM HGH_Zone_Code__c
                WHERE Active__c = true
                WITH USER_MODE
                ORDER BY Name ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching zone codes: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String generateInterviewDays(Id zoneCodeId, String mode, Integer totalSlots, Integer year) {
        try {
            if (zoneCodeId == null) {
                throw new AuraHandledException('Zone Code is required.');
            }
            Set<String> allowedModes = new Set<String>{ 'Morning', 'Afternoon', 'AfterNoon', 'Morning & Afternoon' };
            if (String.isBlank(mode) || !allowedModes.contains(mode)) {
                throw new AuraHandledException('Invalid mode.');
            }
            if (totalSlots == null || totalSlots <= 0 || year == null) {
                throw new AuraHandledException('Invalid parameters provided');
            }

            String normalizedMode = mode == 'Afternoon' ? 'AfterNoon' : mode;
            String batchId = generateBatchId();
            HGH_Zone_Code__c zoneCode = [
                SELECT Id, Name, Code__c, Zone__c
                FROM HGH_Zone_Code__c
                WHERE Id = :zoneCodeId
                WITH USER_MODE
            ];

            Interview_Day__c interviewDay = new Interview_Day__c();
            interviewDay.Zone__c = zoneCode.Zone__c;
            interviewDay.Schedule_Mode__c = normalizedMode;
            interviewDay.Total_Slots__c = totalSlots;
            interviewDay.Year__c = year;
            interviewDay.Status__c = 'Planned';
            interviewDay.Generated_Batch_Id__c = batchId;
            interviewDay.Unique_Key__c = zoneCode.Code__c + '_' + normalizedMode + '_' + year;
            upsert as user interviewDay Interview_Day__c.Unique_Key__c;
            return 'Interview day and placeholder slots generated successfully!';
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String processInterviewPlaceholders(Id zoneId, String mode, Integer totalSlots) {
        if (zoneId == null || String.isBlank(mode) || totalSlots == null || totalSlots <= 0) {
            throw new AuraHandledException('Invalid parameters provided');
        }

        try {
            List<HGH_Zone_Code__c> zoneCodes = [
                SELECT Id, Name, Code__c, Zone__c
                FROM HGH_Zone_Code__c
                WHERE Zone__c = :zoneId AND Active__c = true
                WITH USER_MODE
            ];
            if (zoneCodes.isEmpty()) {
                throw new AuraHandledException('No active zone codes found for the selected zone');
            }

            String batchId = generateBatchId();
            Integer currentYear = Date.today().year();
            List<Interview_Day_Schedule__c> schedulesToCreate = new List<Interview_Day_Schedule__c>();
            Integer totalRecords = 0;

            List<String> modesToProcess = new List<String>();
            Boolean isCombinedMode = mode == 'Morning & Afternoon';
            if (isCombinedMode) {
                modesToProcess.add('Morning');
                modesToProcess.add('AfterNoon');
            } else {
                String normalizedMode = mode;
                if (normalizedMode == 'AM') normalizedMode = 'Morning';
                if (normalizedMode == 'PM') normalizedMode = 'Afternoon';
                modesToProcess.add(normalizedMode == 'Afternoon' ? 'AfterNoon' : normalizedMode);
            }

            for (HGH_Zone_Code__c zoneCode : zoneCodes) {
                for (String currentMode : modesToProcess) {
                    Integer slotsForCurrentMode = getSlotsForMode(totalSlots, isCombinedMode, currentMode);
                    if (slotsForCurrentMode <= 0) {
                        continue;
                    }

                    Interview_Day__c interviewDay = new Interview_Day__c();
                    interviewDay.Zone__c = zoneCode.Zone__c;
                    interviewDay.Zone_Name__c = zoneCode.Name;
                    interviewDay.Zone_Code__c = Decimal.valueOf(zoneCode.Code__c);
                    interviewDay.Schedule_Mode__c = currentMode;
                    interviewDay.Total_Slots__c = slotsForCurrentMode;
                    interviewDay.Year__c = currentYear;
                    interviewDay.Status__c = 'Planned';
                    interviewDay.Generated_Batch_Id__c = batchId;
                    interviewDay.Interview_Date__c = getFirstMondayOfNextMonth();
                    interviewDay.Unique_Key__c = zoneCode.Code__c + '_' + currentMode + '_' + currentYear;

                    upsert as user interviewDay Interview_Day__c.Unique_Key__c;
                    Id interviewDayId = interviewDay.Id;

                    Integer existingCount = 0;
                    for (AggregateResult ar : [
                        SELECT COUNT(Id) totalCount
                        FROM Interview_Day_Schedule__c
                        WHERE Interview_Day__c = :interviewDayId
                        WITH USER_MODE
                    ]) {
                        existingCount = (Integer) ar.get('totalCount');
                    }

                    Integer toCreate = Math.max(0, slotsForCurrentMode - existingCount);
                    for (Integer i = existingCount + 1; i <= existingCount + toCreate; i++) {
                        Interview_Day_Schedule__c scheduleRecord = new Interview_Day_Schedule__c();
                        scheduleRecord.Interview_Day__c = interviewDayId;
                        scheduleRecord.Zone__c = zoneCode.Zone__c;
                        scheduleRecord.Name = currentMode + ' Slot ' + i;
                        scheduleRecord.Booked__c = false;
                        schedulesToCreate.add(scheduleRecord);
                        totalRecords++;
                    }
                }
            }

            if (!schedulesToCreate.isEmpty()) {
                insert as user schedulesToCreate;
            }

            return String.format(
                'Successfully processed {0} zone codes with mode "{1}" and {2} slots. Created {3} Interview_Day_Schedule__c records.',
                new List<Object>{ zoneCodes.size(), mode, totalSlots, totalRecords }
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String processSelectedInterviewPlaceholders(List<Id> selectedZoneCodeIds, String mode, Integer totalSlots) {
        if (selectedZoneCodeIds == null || selectedZoneCodeIds.isEmpty() || String.isBlank(mode) || totalSlots == null || totalSlots <= 0) {
            throw new AuraHandledException('Invalid parameters provided');
        }

        try {
            List<HGH_Zone_Code__c> zoneCodes = [
                SELECT Id, Name, Code__c, Zone__c
                FROM HGH_Zone_Code__c
                WHERE Id IN :selectedZoneCodeIds AND Active__c = true
                WITH USER_MODE
            ];
            if (zoneCodes.isEmpty()) {
                throw new AuraHandledException('No active zone codes found for the selected IDs');
            }

            List<String> modesToProcess = new List<String>();
            Boolean isCombinedMode = mode == 'Morning & Afternoon';
            if (isCombinedMode) {
                modesToProcess.add('Morning');
                modesToProcess.add('AfterNoon');
            } else {
                String normalizedMode = mode;
                if (normalizedMode == 'AM') normalizedMode = 'Morning';
                if (normalizedMode == 'PM') normalizedMode = 'Afternoon';
                modesToProcess.add(normalizedMode == 'Afternoon' ? 'AfterNoon' : normalizedMode);
            }

            Map<Id, String> normalizedCodeById = new Map<Id, String>();
            Set<Decimal> zoneCodeNumbers = new Set<Decimal>();
            for (HGH_Zone_Code__c zoneCode : zoneCodes) {
                String normalized = normalizeZoneCode(zoneCode.Code__c);
                if (normalized != null) {
                    normalizedCodeById.put(zoneCode.Id, normalized);
                    zoneCodeNumbers.add(Decimal.valueOf(normalized));
                }
            }

            Map<String, Set<String>> existingModesPerCode = new Map<String, Set<String>>();
            Integer currentYear = Date.today().year();
            if (!zoneCodeNumbers.isEmpty()) {
                for (Interview_Day__c interviewDay : [
                    SELECT Id, Zone_Code__c, Schedule_Mode__c, Year__c
                    FROM Interview_Day__c
                    WHERE Zone_Code__c IN :zoneCodeNumbers
                    AND Schedule_Mode__c IN :modesToProcess
                    AND Year__c = :currentYear
                    WITH USER_MODE
                ]) {
                    String codeKey = String.valueOf(interviewDay.Zone_Code__c);
                    if (!existingModesPerCode.containsKey(codeKey)) {
                        existingModesPerCode.put(codeKey, new Set<String>());
                    }
                    existingModesPerCode.get(codeKey).add(interviewDay.Schedule_Mode__c);
                }
            }

            Set<String> skippedCombinationSet = new Set<String>();
            List<HGH_Zone_Code__c> validZoneCodes = new List<HGH_Zone_Code__c>();
            Map<Id, List<String>> validModesByZoneCodeId = new Map<Id, List<String>>();

            for (HGH_Zone_Code__c zoneCode : zoneCodes) {
                String normalized = normalizedCodeById.get(zoneCode.Id);
                Set<String> existingForCode = normalized != null && existingModesPerCode.containsKey(normalized)
                    ? existingModesPerCode.get(normalized)
                    : new Set<String>();

                List<String> validModes = new List<String>();
                if (isCombinedMode) {
                    Boolean hasMorning = existingForCode.contains('Morning');
                    Boolean hasAfternoon = existingForCode.contains('AfterNoon');

                    if (!hasMorning) {
                        validModes.add('Morning');
                    } else {
                        skippedCombinationSet.add(buildSkipLabel(zoneCode.Code__c, 'Morning'));
                    }
                    if (!hasAfternoon) {
                        validModes.add('AfterNoon');
                    } else {
                        skippedCombinationSet.add(buildSkipLabel(zoneCode.Code__c, 'AfterNoon'));
                    }
                } else {
                    String targetMode = modesToProcess[0];
                    if (existingForCode.contains(targetMode)) {
                        skippedCombinationSet.add(buildSkipLabel(zoneCode.Code__c, targetMode));
                    } else {
                        validModes.add(targetMode);
                    }
                }

                if (!validModes.isEmpty()) {
                    validZoneCodes.add(zoneCode);
                    validModesByZoneCodeId.put(zoneCode.Id, validModes);
                }
            }

            if (validZoneCodes.isEmpty()) {
                List<String> skippedList = new List<String>(skippedCombinationSet);
                skippedList.sort();
                throw new AuraHandledException('All selected zone codes and modes already have Interview Day records: ' + String.join(skippedList, ', '));
            }

            String batchId = generateBatchId();
            List<Interview_Day_Schedule__c> schedulesToCreate = new List<Interview_Day_Schedule__c>();
            Integer totalRecords = 0;

            for (HGH_Zone_Code__c zoneCode : validZoneCodes) {
                Decimal zoneCodeNumber;
                try {
                    zoneCodeNumber = Decimal.valueOf(zoneCode.Code__c);
                } catch (Exception e) {
                    throw new AuraHandledException('Zone Code ' + zoneCode.Code__c + ' must be numeric to generate interview placeholders.');
                }

                for (String currentMode : validModesByZoneCodeId.get(zoneCode.Id)) {
                    Integer slotsForCurrentMode = getSlotsForMode(totalSlots, isCombinedMode, currentMode);
                    if (slotsForCurrentMode <= 0) {
                        continue;
                    }

                    Interview_Day__c interviewDay = new Interview_Day__c();
                    interviewDay.Zone__c = zoneCode.Zone__c;
                    interviewDay.Zone_Name__c = zoneCode.Name;
                    interviewDay.Zone_Code__c = zoneCodeNumber;
                    interviewDay.Schedule_Mode__c = currentMode;
                    interviewDay.Total_Slots__c = slotsForCurrentMode;
                    interviewDay.Year__c = currentYear;
                    interviewDay.Status__c = 'Planned';
                    interviewDay.Generated_Batch_Id__c = batchId;
                    interviewDay.Interview_Date__c = getFirstMondayOfNextMonth();
                    interviewDay.Unique_Key__c = zoneCode.Code__c + '_' + currentMode + '_' + currentYear;

                    upsert as user interviewDay Interview_Day__c.Unique_Key__c;
                    Id interviewDayId = interviewDay.Id;

                    Integer existingCount = 0;
                    for (AggregateResult ar : [
                        SELECT COUNT(Id) totalCount
                        FROM Interview_Day_Schedule__c
                        WHERE Interview_Day__c = :interviewDayId
                        WITH USER_MODE
                    ]) {
                        existingCount = (Integer) ar.get('totalCount');
                    }

                    Integer toCreate = Math.max(0, slotsForCurrentMode - existingCount);
                    for (Integer i = existingCount + 1; i <= existingCount + toCreate; i++) {
                        Interview_Day_Schedule__c scheduleRecord = new Interview_Day_Schedule__c();
                        scheduleRecord.Interview_Day__c = interviewDayId;
                        scheduleRecord.Zone__c = zoneCode.Zone__c;
                        scheduleRecord.Name = currentMode + ' Slot ' + i + ' - Code ' + zoneCode.Code__c;
                        scheduleRecord.Booked__c = false;
                        schedulesToCreate.add(scheduleRecord);
                        totalRecords++;
                    }
                }
            }

            if (!schedulesToCreate.isEmpty()) {
                insert as user schedulesToCreate;
            }

            List<String> processedZoneCodes = new List<String>();
            for (HGH_Zone_Code__c validZoneCode : validZoneCodes) {
                processedZoneCodes.add('Zone Code ' + validZoneCode.Code__c + ' (' + validZoneCode.Name + ')');
            }

            String message = String.format(
                'Successfully processed {0} out of {1} selected zone codes with mode "{2}" and {3} slots. Created {4} Interview_Day_Schedule__c records.',
                new List<Object>{ validZoneCodes.size(), zoneCodes.size(), mode, totalSlots, totalRecords }
            );
            if (!processedZoneCodes.isEmpty()) {
                message += '\n\nProcessed: ' + String.join(processedZoneCodes, ', ') + '.';
            }
            if (!skippedCombinationSet.isEmpty()) {
                List<String> skippedList = new List<String>(skippedCombinationSet);
                skippedList.sort();
                message += '\n\nSkipped (already exist): ' + String.join(skippedList, ', ') + '.';
            }
            message += '\nBatchId: ' + batchId;
            return message;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, List<String>> getExistingInterviewDaysForZoneCodes(List<Id> zoneCodeIds) {
        try {
            Map<String, List<String>> existingRecords = new Map<String, List<String>>();
            if (zoneCodeIds == null || zoneCodeIds.isEmpty()) {
                return existingRecords;
            }

            Integer currentYear = Date.today().year();
            List<HGH_Zone_Code__c> zoneCodes = [
                SELECT Id, Code__c
                FROM HGH_Zone_Code__c
                WHERE Id IN :zoneCodeIds
                WITH USER_MODE
            ];

            Map<String, Id> codeKeyToId = buildZoneCodeKeyMap(zoneCodes);
            Set<Decimal> zoneCodeNumbers = new Set<Decimal>();
            for (String codeKey : codeKeyToId.keySet()) {
                String normalizedCode = normalizeZoneCode(codeKey);
                if (normalizedCode != null) {
                    zoneCodeNumbers.add(Decimal.valueOf(normalizedCode));
                }
            }

            if (zoneCodeNumbers.isEmpty()) {
                return existingRecords;
            }

            for (Interview_Day__c interviewDay : [
                SELECT Id, Zone_Code__c, Schedule_Mode__c, Year__c
                FROM Interview_Day__c
                WHERE Zone_Code__c IN :zoneCodeNumbers AND Year__c = :currentYear
                WITH USER_MODE
            ]) {
                String normalizedCode = String.valueOf(interviewDay.Zone_Code__c);
                Id zoneCodeId = codeKeyToId.get(normalizedCode);
                if (zoneCodeId == null) {
                    continue;
                }

                String mapKey = String.valueOf(zoneCodeId);
                if (!existingRecords.containsKey(mapKey)) {
                    existingRecords.put(mapKey, new List<String>());
                }
                existingRecords.get(mapKey).add(interviewDay.Schedule_Mode__c);
            }
            return existingRecords;
        } catch (Exception e) {
            throw new AuraHandledException('Error checking existing interview days: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Interview_Day__c> getExistingInterviewDays() {
        try {
            return [
                SELECT Id, Zone__c, Zone__r.Name, Zone_Code__c, Schedule_Mode__c, Mode__c,
                       Interview_Date__c, Total_Slots__c, Year__c, Status__c, Generated_Batch_Id__c,
                       (SELECT Id, Name, Status__c, Booked__c FROM Interview_Day_Schedules__r ORDER BY Name ASC)
                FROM Interview_Day__c
                WITH USER_MODE
                ORDER BY Year__c DESC, Zone__r.Name ASC, Schedule_Mode__c ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching existing interview days: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static DeleteSelectedSchedulesResultDTO deleteSelectedInterviewSchedules(List<Id> scheduleIds) {
        try {
            if (scheduleIds == null || scheduleIds.isEmpty()) {
                throw new AuraHandledException('Select at least one placeholder row to delete.');
            }

            DeleteSelectedSchedulesResultDTO dto = new DeleteSelectedSchedulesResultDTO();
            dto.deletedScheduleCount = 0;
            dto.skippedBookedCount = 0;
            dto.deletedInterviewDayCount = 0;

            List<Interview_Day_Schedule__c> schedules = [
                SELECT Id, Interview_Day__c, Booked__c
                FROM Interview_Day_Schedule__c
                WHERE Id IN :scheduleIds
                WITH USER_MODE
            ];
            if (schedules.isEmpty()) {
                return dto;
            }

            List<Interview_Day_Schedule__c> schedulesToDelete = new List<Interview_Day_Schedule__c>();
            Set<Id> affectedInterviewDayIds = new Set<Id>();
            for (Interview_Day_Schedule__c scheduleRecord : schedules) {
                if (scheduleRecord.Booked__c == true) {
                    dto.skippedBookedCount++;
                    continue;
                }

                schedulesToDelete.add(scheduleRecord);
                if (scheduleRecord.Interview_Day__c != null) {
                    affectedInterviewDayIds.add(scheduleRecord.Interview_Day__c);
                }
            }

            if (!schedulesToDelete.isEmpty()) {
                delete as user schedulesToDelete;
                dto.deletedScheduleCount = schedulesToDelete.size();
            }

            if (!affectedInterviewDayIds.isEmpty()) {
                Set<Id> interviewDayIdsWithRemainingSchedules = new Set<Id>();
                for (Interview_Day_Schedule__c remainingSchedule : [
                    SELECT Id, Interview_Day__c
                    FROM Interview_Day_Schedule__c
                    WHERE Interview_Day__c IN :affectedInterviewDayIds
                    WITH USER_MODE
                ]) {
                    if (remainingSchedule.Interview_Day__c != null) {
                        interviewDayIdsWithRemainingSchedules.add(remainingSchedule.Interview_Day__c);
                    }
                }

                List<Interview_Day__c> interviewDaysToDelete = new List<Interview_Day__c>();
                for (Interview_Day__c interviewDay : [
                    SELECT Id, Status__c
                    FROM Interview_Day__c
                    WHERE Id IN :affectedInterviewDayIds
                    WITH USER_MODE
                ]) {
                    if (interviewDay.Status__c == 'Planned' && !interviewDayIdsWithRemainingSchedules.contains(interviewDay.Id)) {
                        interviewDaysToDelete.add(interviewDay);
                    }
                }

                if (!interviewDaysToDelete.isEmpty()) {
                    delete as user interviewDaysToDelete;
                    dto.deletedInterviewDayCount = interviewDaysToDelete.size();
                }
            }

            return dto;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting selected placeholder rows: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Interview_Day__c> getInterviewDaysByBatchId(String batchId) {
        try {
            if (String.isBlank(batchId)) {
                return new List<Interview_Day__c>();
            }
            return [
                SELECT Id, Zone__r.Name, Zone_Code__c, Schedule_Mode__c, Mode__c,
                       Interview_Date__c, Total_Slots__c, Year__c, Status__c, Generated_Batch_Id__c,
                       (SELECT Id, Name, Status__c, Booked__c FROM Interview_Day_Schedules__r ORDER BY Name ASC)
                FROM Interview_Day__c
                WHERE Generated_Batch_Id__c = :batchId
                WITH USER_MODE
                ORDER BY Zone__r.Name ASC, Schedule_Mode__c ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching interview days by batch: ' + e.getMessage());
        }
    }

    private static Schedule_Year__c ensureScheduleYearRecord(Integer year) {
        List<Schedule_Year__c> years = [
            SELECT Id
            FROM Schedule_Year__c
            WHERE Year__c = :year
            WITH USER_MODE
            LIMIT 1
        ];
        if (!years.isEmpty()) {
            return years[0];
        }

        Schedule_Year__c scheduleYear = new Schedule_Year__c(
            Name = String.valueOf(year),
            Year__c = year,
            Status__c = 'Planned'
        );
        insert as user scheduleYear;
        return scheduleYear;
    }

    private static List<PreviewRowDTO> calculateScheduleDates(Integer year, List<Id> zoneIds) {
        if (year == null) {
            throw new AuraHandledException('Year is required');
        }

        List<Zone__c> zones = (zoneIds == null || zoneIds.isEmpty())
            ? [SELECT Id, Name, Active__c FROM Zone__c WHERE Active__c = true WITH USER_MODE]
            : [SELECT Id, Name, Active__c FROM Zone__c WHERE Id IN :zoneIds AND Active__c = true WITH USER_MODE];
        if (zones.isEmpty()) {
            return new List<PreviewRowDTO>();
        }

        Set<Id> zoneIdSet = new Map<Id, Zone__c>(zones).keySet();
        Map<Id, List<HGH_Zone_Code__c>> zoneCodesByZoneId = new Map<Id, List<HGH_Zone_Code__c>>();
        for (HGH_Zone_Code__c zoneCode : [
            SELECT Id, Code__c, Zone__c, Active__c
            FROM HGH_Zone_Code__c
            WHERE Zone__c IN :zoneIdSet AND Active__c = true
            WITH USER_MODE
        ]) {
            if (!zoneCodesByZoneId.containsKey(zoneCode.Zone__c)) {
                zoneCodesByZoneId.put(zoneCode.Zone__c, new List<HGH_Zone_Code__c>());
            }
            zoneCodesByZoneId.get(zoneCode.Zone__c).add(zoneCode);
        }

        List<Zone_Rule__c> rules = [
            SELECT Id, Zone__c, Month__c, Ordinal__c, DayOfWeek__c, Mode__c, Active__c
            FROM Zone_Rule__c
            WHERE Zone__c IN :zoneIdSet AND Active__c = true
            WITH USER_MODE
        ];

        Map<String, Schedule_Date__c> existingByIdentity = new Map<String, Schedule_Date__c>();
        List<Schedule_Year__c> years = [SELECT Id FROM Schedule_Year__c WHERE Year__c = :year WITH USER_MODE LIMIT 1];
        if (!years.isEmpty()) {
            for (Schedule_Date__c scheduleDate : [
                SELECT Id, Unique_Key__c, Status__c, Zone__c, Zone_Code__c, Zone_Rule__c, Mode__c, Calculated_Date__c
                FROM Schedule_Date__c
                WHERE Schedule_Year__c = :years[0].Id
                WITH USER_MODE
            ]) {
                existingByIdentity.put(
                    buildIdentityKey(year, scheduleDate.Zone__c, scheduleDate.Zone_Code__c, scheduleDate.Zone_Rule__c, scheduleDate.Mode__c),
                    scheduleDate
                );
            }
        }

        Map<Id, Zone__c> zoneById = new Map<Id, Zone__c>(zones);
        List<PreviewRowDTO> previewRows = new List<PreviewRowDTO>();
        for (Zone_Rule__c rule : rules) {
            Integer monthValue = (Integer) rule.Month__c;
            Integer ordinalValue = (Integer) rule.Ordinal__c;
            Integer dowValue = dowFromPick(rule.DayOfWeek__c);
            if (monthValue == null || ordinalValue == null || dowValue == null) {
                continue;
            }

            Date calculatedDate = nthWeekday(year, monthValue, ordinalValue, dowValue);
            List<HGH_Zone_Code__c> zoneCodes = zoneCodesByZoneId.get(rule.Zone__c);
            if (zoneCodes == null || zoneCodes.isEmpty()) {
                continue;
            }

            for (HGH_Zone_Code__c zoneCode : zoneCodes) {
                String mode = String.isBlank(rule.Mode__c) ? 'Default' : rule.Mode__c;
                Schedule_Date__c existingRecord = existingByIdentity.get(
                    buildIdentityKey(year, rule.Zone__c, zoneCode.Id, rule.Id, mode)
                );

                PreviewRowDTO row = new PreviewRowDTO();
                row.zoneId = rule.Zone__c;
                row.zoneName = zoneById.get(rule.Zone__c).Name;
                row.ruleId = rule.Id;
                row.month = monthValue;
                row.ordinal = ordinalValue;
                row.dow = dowValue;
                row.mode = mode;
                row.zoneCodeId = zoneCode.Id;
                row.zoneCode = zoneCode.Code__c;
                row.calculatedDate = calculatedDate;
                row.exists = existingRecord != null;
                row.isPublished = existingRecord != null && existingRecord.Status__c == 'Published';
                row.action = row.isPublished ? 'SKIP' : (row.exists ? 'UPDATE' : 'CREATE');
                previewRows.add(row);
            }
        }
        return previewRows;
    }

    private static void cleanupGeneratedPlaceholderRecords(Set<Id> zoneIds, Set<Date> interviewDates, Set<String> zoneDateKeys) {
        if (zoneIds == null || zoneIds.isEmpty() || interviewDates == null || interviewDates.isEmpty() || zoneDateKeys == null || zoneDateKeys.isEmpty()) {
            return;
        }

        List<Interview_Day__c> impactedDays = new List<Interview_Day__c>();
        for (Interview_Day__c interviewDay : [
            SELECT Id, Zone__c, Interview_Date__c, Status__c
            FROM Interview_Day__c
            WHERE Status__c = 'Planned'
            AND Zone__c IN :zoneIds
            AND Interview_Date__c IN :interviewDates
            WITH USER_MODE
        ]) {
            String zoneDateKey = buildZoneDateKey(interviewDay.Zone__c, interviewDay.Interview_Date__c);
            if (zoneDateKeys.contains(zoneDateKey)) {
                impactedDays.add(interviewDay);
            }
        }

        if (impactedDays.isEmpty()) {
            return;
        }

        Set<Id> impactedDayIds = new Map<Id, Interview_Day__c>(impactedDays).keySet();
        Set<Id> protectedDayIds = new Set<Id>();
        List<Interview_Day_Schedule__c> schedulesToDelete = new List<Interview_Day_Schedule__c>();
        for (Interview_Day_Schedule__c scheduleRecord : [
            SELECT Id, Interview_Day__c, Booked__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c IN :impactedDayIds
            WITH USER_MODE
        ]) {
            if (scheduleRecord.Booked__c == true) {
                protectedDayIds.add(scheduleRecord.Interview_Day__c);
            } else {
                schedulesToDelete.add(scheduleRecord);
            }
        }

        if (!schedulesToDelete.isEmpty()) {
            delete as user schedulesToDelete;
        }

        List<Interview_Day__c> daysToDelete = new List<Interview_Day__c>();
        for (Interview_Day__c interviewDay : impactedDays) {
            if (!protectedDayIds.contains(interviewDay.Id)) {
                daysToDelete.add(interviewDay);
            }
        }

        if (!daysToDelete.isEmpty()) {
            delete as user daysToDelete;
        }
    }

    private static Map<String, Id> buildZoneCodeKeyMap(List<HGH_Zone_Code__c> zoneCodes) {
        Map<String, Id> codeKeyToId = new Map<String, Id>();
        for (HGH_Zone_Code__c zoneCode : zoneCodes) {
            if (zoneCode == null || String.isBlank(zoneCode.Code__c)) {
                continue;
            }

            String rawValue = zoneCode.Code__c.trim();
            codeKeyToId.put(rawValue, zoneCode.Id);
            String normalized = normalizeZoneCode(zoneCode.Code__c);
            if (normalized != null) {
                codeKeyToId.put(normalized, zoneCode.Id);
            }
        }
        return codeKeyToId;
    }

    private static String buildIdentityKey(Integer year, Id zoneId, Id zoneCodeId, Id ruleId, String mode) {
        List<String> parts = new List<String>();
        parts.add(String.valueOf(year));
        parts.add((String) zoneId);
        parts.add((String) zoneCodeId);
        parts.add((String) ruleId);
        parts.add(mode);
        return String.join(parts, '|');
    }

    private static String buildZoneDateKey(Id zoneId, Date calculatedDate) {
        if (zoneId == null || calculatedDate == null) {
            return null;
        }
        return String.valueOf(zoneId) + '|' + formatDateForKey(calculatedDate);
    }

    private static String buildKey(Integer year, Id zoneId, Id zoneCodeId, Id ruleId, String mode, Date calculatedDate) {
        List<String> parts = new List<String>();
        parts.add(buildIdentityKey(year, zoneId, zoneCodeId, ruleId, mode));
        parts.add(formatDateForKey(calculatedDate));
        return String.join(parts, '|');
    }

    private static String formatDateForKey(Date value) {
        if (value == null) {
            return 'null';
        }
        return String.valueOf(value.year()) + '-' + twoDigit(value.month()) + '-' + twoDigit(value.day());
    }

    private static String twoDigit(Integer value) {
        String rawValue = String.valueOf(value);
        return rawValue.length() == 1 ? '0' + rawValue : rawValue;
    }

    private static Integer dowFromPick(String picklistValue) {
        if (picklistValue == null) return null;
        String normalized = picklistValue.toLowerCase();
        if (normalized == 'sun' || normalized == 'sunday') return 1;
        if (normalized == 'mon' || normalized == 'monday') return 2;
        if (normalized == 'tue' || normalized == 'tuesday') return 3;
        if (normalized == 'wed' || normalized == 'wednesday') return 4;
        if (normalized == 'thu' || normalized == 'thursday') return 5;
        if (normalized == 'fri' || normalized == 'friday') return 6;
        if (normalized == 'sat' || normalized == 'saturday') return 7;
        return null;
    }

    private static String buildRuleLabel(String zoneName, String mode, Integer ordinal, Integer dow, Integer month) {
        List<String> parts = new List<String>();
        if (!String.isBlank(zoneName)) parts.add(zoneName);
        if (!String.isBlank(mode)) parts.add(mode);
        parts.add(ordinalLabel(ordinal) + ' ' + dowName(dow) + ' of ' + monthName(month));
        return String.join(parts, ' — ');
    }

    private static String ordinalLabel(Integer ordinal) {
        if (ordinal == null) return '';
        if (ordinal == 1) return '1st';
        if (ordinal == 2) return '2nd';
        if (ordinal == 3) return '3rd';
        if (ordinal == 4) return '4th';
        if (ordinal == 5) return 'Last';
        return String.valueOf(ordinal) + 'th';
    }

    private static String monthName(Integer month) {
        if (month == null) return '';
        List<String> monthNames = new List<String>{ 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December' };
        return month >= 1 && month <= 12 ? monthNames[month - 1] : String.valueOf(month);
    }

    private static String dowName(Integer dow) {
        switch on dow {
            when 1 { return 'Sunday'; }
            when 2 { return 'Monday'; }
            when 3 { return 'Tuesday'; }
            when 4 { return 'Wednesday'; }
            when 5 { return 'Thursday'; }
            when 6 { return 'Friday'; }
            when 7 { return 'Saturday'; }
            when else { return ''; }
        }
    }

    private static Date nthWeekday(Integer year, Integer month, Integer ordinal, Integer dow) {
        Date first = Date.newInstance(year, month, 1);
        Integer delta = Math.mod(dow - dayOfWeek(first) + 7, 7);
        Date firstTarget = first.addDays(delta);
        Integer ordinalValue = ordinal == null ? 1 : ordinal;

        if (ordinalValue == 5) {
            Date lastTry = firstTarget.addDays(7 * 4);
            if (lastTry.month() != month) {
                lastTry = firstTarget.addDays(7 * 3);
            }
            return lastTry;
        }

        Date candidate = firstTarget.addDays(7 * (ordinalValue - 1));
        if (candidate.month() != month) {
            Date lastTry = firstTarget.addDays(7 * 3);
            if (lastTry.month() != month) {
                lastTry = lastTry.addDays(-7);
            }
            return lastTry;
        }
        return candidate;
    }

    private static Integer dayOfWeek(Date value) {
        Integer q = value.day();
        Integer m = value.month();
        Integer y = value.year();
        if (m == 1) { m = 13; y = y - 1; }
        if (m == 2) { m = 14; y = y - 1; }
        Integer k = Math.mod(y, 100);
        Integer j = y / 100;
        Integer term1 = (13 * (m + 1)) / 5;
        Integer term2 = k / 4;
        Integer term3 = j / 4;
        Integer h = Math.mod(q + term1 + k + term2 + term3 + (5 * j), 7);
        return h == 0 ? 7 : h;
    }

    private static String buildScheduleDateName(String zoneName, String zoneCode, Date calculatedDate) {
        String formattedDate = calculatedDate != null ? calculatedDate.format() : 'TBD';
        String name = '';
        if (String.isNotBlank(zoneName)) {
            name += zoneName;
        }
        if (String.isNotBlank(zoneCode)) {
            name += (String.isNotBlank(name) ? ' - ' : '') + zoneCode;
        }
        if (String.isNotBlank(formattedDate)) {
            name += (String.isNotBlank(name) ? ' - ' : '') + formattedDate;
        }
        if (String.isBlank(name)) {
            name = 'Schedule Date - ' + formattedDate;
        }
        if (name.length() > 80) {
            name = name.substring(0, 77) + '...';
        }
        return name;
    }

    private static Date getFirstMondayOfNextMonth() {
        Date today = Date.today();
        Date firstDayOfNextMonth = today.toStartOfMonth().addMonths(1);
        Integer dayOfWeekValue = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(firstDayOfNextMonth), 7) + 1;
        Integer daysToAdd = dayOfWeekValue == 1 ? 1 : Math.mod((9 - dayOfWeekValue), 7);
        return firstDayOfNextMonth.addDays(daysToAdd);
    }

    private static String normalizeZoneCode(String codeValue) {
        if (String.isBlank(codeValue)) {
            return null;
        }
        String trimmedValue = codeValue.trim();
        try {
            return String.valueOf(Decimal.valueOf(trimmedValue));
        } catch (Exception ex) {
            return null;
        }
    }

    private static String formatModeLabel(String mode) {
        return mode == 'AfterNoon' ? 'Afternoon' : mode;
    }

    private static String buildSkipLabel(String zoneCodeValue, String mode) {
        String safeZoneCode = String.isBlank(zoneCodeValue) ? 'Unknown' : zoneCodeValue;
        return 'Zone Code ' + safeZoneCode + ' (' + formatModeLabel(mode) + ')';
    }

    private static Integer getSlotsForMode(Integer totalSlots, Boolean isCombinedMode, String mode) {
        if (totalSlots == null || totalSlots <= 0) {
            return 0;
        }
        if (!isCombinedMode) {
            return totalSlots;
        }
        Integer morningSlots = (totalSlots + 1) / 2;
        Integer afternoonSlots = totalSlots / 2;
        return mode == 'Morning' ? morningSlots : afternoonSlots;
    }

    private static String generateBatchId() {
        return DateTime.now().format('yyyyMMddHHmmss') + '_' + String.valueOf(Math.random()).substring(2, 8);
    }
}