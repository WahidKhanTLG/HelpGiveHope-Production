public with sharing class ScheduleGenService {

    public class PreviewRowDTO {
        @AuraEnabled public Id zoneId;
        @AuraEnabled public String zoneName;
        @AuraEnabled public Id ruleId;
        @AuraEnabled public Integer month;
        @AuraEnabled public Integer ordinal;
        @AuraEnabled public Integer dow; // 1=Sun..7=Sat (Apex Date.dayOfWeek)
        @AuraEnabled public String mode;
        @AuraEnabled public Id zoneCodeId;
        @AuraEnabled public String zoneCode;
        @AuraEnabled public Date calculatedDate;
        @AuraEnabled public Boolean exists;
        @AuraEnabled public Boolean isPublished;
        @AuraEnabled public String action; // CREATE / UPDATE / SKIP
    }

    // Lightweight DTO to audit rule -> calculated date
    public class RuleAuditRowDTO {
        @AuraEnabled public Id ruleId;
        @AuraEnabled public String ruleLabel; // e.g., "Zone A — Morning — 1st Monday of October"
        @AuraEnabled public Date calculatedDate;
        @AuraEnabled public String zoneName;
        @AuraEnabled public String mode;
        @AuraEnabled public Integer month;
        @AuraEnabled public Integer ordinal;
        @AuraEnabled public Integer dow; // 1..7 Sun..Sat
    }

    /**
     * Returns all rules (optionally filtered by zoneIds and includeInactive) with their computed date for the provided year.
     * The table consumer can show ruleLabel as column 1 and calculatedDate as column 2.
     */
    @AuraEnabled(cacheable=true)
    public static List<RuleAuditRowDTO> auditRules(Integer year, List<Id> zoneIds, Boolean includeInactive) {
        if (year == null) throw new AuraHandledException('Year is required');

        // Build base query: optionally filter by Zone__c and Active__c
        String whereClause = '';
        if (zoneIds != null && !zoneIds.isEmpty()) {
            whereClause = ' WHERE Zone__c IN :zoneIds';
        }
        List<Zone_Rule__c> rules;
        if (includeInactive == true) {
            rules = Database.query('SELECT Id, Zone__c, Month__c, Ordinal__c, DayOfWeek__c, Mode__c, Active__c FROM Zone_Rule__c' + whereClause);
        } else {
            String whereActive = String.isBlank(whereClause) ? ' WHERE Active__c = true' : whereClause + ' AND Active__c = true';
            rules = Database.query('SELECT Id, Zone__c, Month__c, Ordinal__c, DayOfWeek__c, Mode__c, Active__c FROM Zone_Rule__c' + whereActive);
        }

        if (rules.isEmpty()) return new List<RuleAuditRowDTO>();

        // Fetch zones for labeling
        Set<Id> zids = new Set<Id>();
        for (Zone_Rule__c r : rules) zids.add(r.Zone__c);
        Map<Id, Zone__c> zoneMap = new Map<Id, Zone__c>([
            SELECT Id, Name FROM Zone__c WHERE Id IN :zids
        ]);

        List<RuleAuditRowDTO> out = new List<RuleAuditRowDTO>();
        for (Zone_Rule__c r : rules) {
            Integer m = (Integer)r.Month__c;
            Integer ord = (Integer)r.Ordinal__c;
            Integer dw = dowFromPick(r.DayOfWeek__c);
            if (m == null || ord == null || dw == null) continue;

            Date d = nthWeekday(year, m, ord, dw);
            String zname = zoneMap.get(r.Zone__c)?.Name;
            String mode = String.isBlank(r.Mode__c) ? 'Default' : r.Mode__c;

            RuleAuditRowDTO row = new RuleAuditRowDTO();
            row.ruleId = r.Id;
            row.zoneName = zname;
            row.mode = mode;
            row.month = m;
            row.ordinal = ord;
            row.dow = dw;
            row.ruleLabel = buildRuleLabel(zname, mode, ord, dw, m);
            row.calculatedDate = d;
            out.add(row);
        }
        return out;
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
        @AuraEnabled public Date calculatedDate; // user-edited date
        @AuraEnabled public Boolean exists;
        @AuraEnabled public Boolean isPublished;
        @AuraEnabled public String action; // CREATE / UPDATE / SKIP (from preview)
    }

    /**
     * Common method to calculate schedule dates based on zone rules
     * Used by both preview and generate operations
     * 
     * @param year The year to generate dates for
     * @param zoneIds List of zone IDs to filter by, or null for all active zones
     * @return List of preview rows with calculated dates and action types
     */
    private static List<PreviewRowDTO> calculateScheduleDates(Integer year, List<Id> zoneIds) {
        if (year == null) throw new AuraHandledException('Year is required');

        // Get active zones
        List<Zone__c> zones = (zoneIds == null || zoneIds.isEmpty())
            ? [SELECT Id, Name, Active__c FROM Zone__c WHERE Active__c = true]
            : [SELECT Id, Name, Active__c FROM Zone__c WHERE Id IN :zoneIds AND Active__c = true];

        if (zones.isEmpty()) return new List<PreviewRowDTO>();

        Set<Id> zoneIdSet = new Map<Id, Zone__c>(zones).keySet();

        // Get zone codes for each zone
        Map<Id, List<HGH_Zone_Code__c>> zoneToCodes = new Map<Id, List<HGH_Zone_Code__c>>();
        for (HGH_Zone_Code__c zc : [
            SELECT Id, Code__c, Zone__c, Active__c FROM HGH_Zone_Code__c
            WHERE Zone__c IN :zoneIdSet AND Active__c = true
        ]) {
            if (!zoneToCodes.containsKey(zc.Zone__c)) zoneToCodes.put(zc.Zone__c, new List<HGH_Zone_Code__c>());
            zoneToCodes.get(zc.Zone__c).add(zc);
        }

        // Get active rules for these zones
        List<Zone_Rule__c> rules = [
            SELECT Id, Zone__c, Month__c, Ordinal__c, DayOfWeek__c, Mode__c, Active__c
            FROM Zone_Rule__c
            WHERE Zone__c IN :zoneIdSet AND Active__c = true
        ];

        // Check existing schedule dates
        Map<String, Schedule_Date__c> existingByKey = new Map<String, Schedule_Date__c>();
        Schedule_Year__c sYear = null;
        List<Schedule_Year__c> y = [SELECT Id FROM Schedule_Year__c WHERE Year__c = :year LIMIT 1];
        if (!y.isEmpty()) {
            sYear = y[0];
            for (Schedule_Date__c sd : [
                SELECT Id, Unique_Key__c, Status__c
                FROM Schedule_Date__c
                WHERE Schedule_Year__c = :sYear.Id
            ]) existingByKey.put(sd.Unique_Key__c, sd);
        }

        // Build preview rows
        Map<Id, Zone__c> zoneById = new Map<Id, Zone__c>(zones);
        List<PreviewRowDTO> outRows = new List<PreviewRowDTO>();

        for (Zone_Rule__c r : rules) {
            Integer m = (Integer)r.Month__c;
            Integer ord = (Integer)r.Ordinal__c;
            Integer dow = dowFromPick(r.DayOfWeek__c); // 1..7 Sun..Sat
            if (m == null || ord == null || dow == null) continue;

            Date d = nthWeekday(year, m, ord, dow);
            List<HGH_Zone_Code__c> codes = zoneToCodes.get(r.Zone__c);
            if (codes == null || codes.isEmpty()) continue;

            for (HGH_Zone_Code__c code : codes) {
                String mode = String.isBlank(r.Mode__c) ? 'Default' : r.Mode__c;
                String key = buildKey(year, r.Zone__c, code.Id, r.Id, mode, d);
                Schedule_Date__c ex = existingByKey.get(key);

                PreviewRowDTO row = new PreviewRowDTO();
                row.zoneId = r.Zone__c;
                row.zoneName = zoneById.get(r.Zone__c).Name;
                row.ruleId = r.Id;
                row.month = m;
                row.ordinal = ord;
                row.dow = dow;
                row.mode = mode;
                row.zoneCodeId = code.Id;
                row.zoneCode = code.Code__c;
                row.calculatedDate = d;
                row.exists = (ex != null);
                row.isPublished = (ex != null && ex.Status__c == 'Published');
                row.action = row.isPublished ? 'SKIP' : (row.exists ? 'UPDATE' : 'CREATE');
                outRows.add(row);
            }
        }
        return outRows;
    }

    /**
     * Preview schedule dates based on zone rules without creating any records
     * 
     * @param year The year to generate dates for
     * @param zoneIds List of zone IDs to filter by, or null for all active zones
     * @return List of preview rows with calculated dates and action types
     */
    @AuraEnabled(cacheable=true)
    public static List<PreviewRowDTO> preview(Integer year, List<Id> zoneIds) {
        return calculateScheduleDates(year, zoneIds);
    }

    /**
     * Generate schedule dates based on zone rules and save them to the database
     * 
     * @param year The year to generate dates for
     * @param zoneIds List of zone IDs to filter by, or null for all active zones
     * @param action The action to take ('CREATE_NEW' or 'OVERWRITE_PLANNED')
     * @return Result DTO with counts of created/updated/skipped records
     */
    @AuraEnabled
    public static GenerationResultDTO generate(Integer year, List<Id> zoneIds, String action) {
        if (year == null) throw new AuraHandledException('Year is required');
        if (String.isBlank(action)) throw new AuraHandledException('Action is required');

        // Ensure Schedule Year
        Schedule_Year__c sYear;
        List<Schedule_Year__c> y = [SELECT Id FROM Schedule_Year__c WHERE Year__c = :year LIMIT 1];
        if (y.isEmpty()) {
            // Set Name to Year so the record name isn't the record Id
            sYear = new Schedule_Year__c(Name = String.valueOf(year), Year__c = year, Status__c = 'Planned');
            insert sYear;
        } else {
            sYear = y[0];
        }

        // Use the common method to calculate schedule dates
        List<PreviewRowDTO> plan = calculateScheduleDates(year, zoneIds);

        // Generate a unique batch ID for this operation
        String batchId = String.valueOf(Crypto.getRandomInteger());
        Integer created = 0, updated = 0, skipped = 0;
        List<Schedule_Date__c> upserts = new List<Schedule_Date__c>();

        // Get existing records for the schedule year
        Map<String, Schedule_Date__c> existing = new Map<String, Schedule_Date__c>();
        for (Schedule_Date__c sd : [
            SELECT Id, Unique_Key__c, Status__c
            FROM Schedule_Date__c WHERE Schedule_Year__c = :sYear.Id
        ]) existing.put(sd.Unique_Key__c, sd);

        // Process each planned date based on action type
        for (PreviewRowDTO r : plan) {
            String key = buildKey(year, r.zoneId, r.zoneCodeId, r.ruleId, r.mode, r.calculatedDate);

            // Skip published records regardless of action
            if (r.isPublished) { 
                skipped++; 
                continue; 
            }

            // Skip existing records in CREATE_NEW mode
            if ('CREATE_NEW'.equalsIgnoreCase(action) && r.exists) {
                continue;
            }
            
            // Update planned records in OVERWRITE_PLANNED mode
            if ('OVERWRITE_PLANNED'.equalsIgnoreCase(action) && r.exists) {
                Schedule_Date__c cur = existing.get(key);
                if (cur != null && cur.Status__c == 'Planned') {
                    cur.Zone__c = r.zoneId;
                    cur.Zone_Code__c = r.zoneCodeId;
                    cur.Zone_Rule__c = r.ruleId;
                    cur.Mode__c = r.mode;
                    cur.Calculated_Date__c = r.calculatedDate;
                    cur.Generated_Batch_Id__c = batchId;
                    upserts.add(cur);
                    updated++;
                } else {
                    skipped++;
                }
                continue;
            }

            // Create new records
            if (!r.exists) {
                Schedule_Date__c sd = new Schedule_Date__c();
                sd.Name = buildScheduleDateName(r.zoneName, r.zoneCode, r.calculatedDate);
                sd.Schedule_Year__c = sYear.Id;
                sd.Zone__c = r.zoneId;
                sd.Zone_Code__c = r.zoneCodeId;
                sd.Zone_Rule__c = r.ruleId;
                sd.Mode__c = r.mode;
                sd.Calculated_Date__c = r.calculatedDate;
                sd.Status__c = 'Planned';
                sd.Generated_Batch_Id__c = batchId;
                sd.Unique_Key__c = key;
                upserts.add(sd);
                created++;
            }
        }
        
        // Save to database
        if (!upserts.isEmpty()) upsert upserts Unique_Key__c;

        // Return results
        GenerationResultDTO res = new GenerationResultDTO();
        res.batchId = batchId;
        res.createdCount = created;
        res.updatedCount = updated;
        res.skippedPublished = skipped;
        res.scheduleYearId = sYear.Id;
        res.totalPlanned = plan.size();
        return res;
    }

    public class DeleteResultDTO {
        @AuraEnabled public Integer deletedCount;
    }

    @AuraEnabled
    public static DeleteResultDTO deleteScheduleDates(Integer year, List<Id> zoneIds) {
        if (year == null) throw new AuraHandledException('Year is required');
        List<Schedule_Year__c> ys = [SELECT Id FROM Schedule_Year__c WHERE Year__c = :year LIMIT 1];
        DeleteResultDTO dto = new DeleteResultDTO();
        dto.deletedCount = 0;
        if (ys.isEmpty()) return dto;
        Id syId = ys[0].Id;

        String soql = 'SELECT Id FROM Schedule_Date__c WHERE Schedule_Year__c = :syId';
        List<Schedule_Date__c> toDelete;
        if (zoneIds != null && !zoneIds.isEmpty()) {
            toDelete = [SELECT Id FROM Schedule_Date__c WHERE Schedule_Year__c = :syId AND Zone__c IN :zoneIds];
        } else {
            toDelete = [SELECT Id FROM Schedule_Date__c WHERE Schedule_Year__c = :syId];
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
            dto.deletedCount = toDelete.size();
        }
        return dto;
    }

    /**
     * Generate schedule dates with overrides from user edits
     * 
     * @param year The year to generate dates for
     * @param action The action to take ('CREATE_NEW' or 'OVERWRITE_PLANNED')
     * @param overrides List of override rows with user-edited dates
     * @return Result DTO with counts of created/updated/skipped records
     */
    @AuraEnabled
    public static GenerationResultDTO generateWithOverrides(Integer year, String action, List<OverrideRowDTO> overrides) {
        if (year == null) throw new AuraHandledException('Year is required');
        if (String.isBlank(action)) throw new AuraHandledException('Action is required');
        if (overrides == null || overrides.isEmpty()) throw new AuraHandledException('No overrides provided');

        // Ensure Schedule Year
        Schedule_Year__c sYear;
        List<Schedule_Year__c> y = [SELECT Id FROM Schedule_Year__c WHERE Year__c = :year LIMIT 1];
        if (y.isEmpty()) {
            // Set Name to Year so the record name isn't the record Id
            sYear = new Schedule_Year__c(Name = String.valueOf(year), Year__c = year, Status__c = 'Planned');
            insert sYear;
        } else {
            sYear = y[0];
        }

        // Generate a unique batch ID for this operation
        String batchId = String.valueOf(Crypto.getRandomInteger());
        Integer created = 0, updated = 0, skipped = 0;

        // Get zone and zone code information for naming
        Set<Id> zoneIds = new Set<Id>();
        Set<Id> zoneCodeIds = new Set<Id>();
        for (OverrideRowDTO r : overrides) {
            zoneIds.add(r.zoneId);
            zoneCodeIds.add(r.zoneCodeId);
        }
        
        Map<Id, Zone__c> zoneMap = new Map<Id, Zone__c>([SELECT Id, Name FROM Zone__c WHERE Id IN :zoneIds]);
        Map<Id, HGH_Zone_Code__c> zoneCodeMap = new Map<Id, HGH_Zone_Code__c>([SELECT Id, Code__c FROM HGH_Zone_Code__c WHERE Id IN :zoneCodeIds]);

        // Get existing records for the schedule year
        Map<String, Schedule_Date__c> existing = new Map<String, Schedule_Date__c>();
        for (Schedule_Date__c sd : [
            SELECT Id, Unique_Key__c, Status__c
            FROM Schedule_Date__c WHERE Schedule_Year__c = :sYear.Id
        ]) existing.put(sd.Unique_Key__c, sd);

        List<Schedule_Date__c> upserts = new List<Schedule_Date__c>();

        // Process each override based on action type
        for (OverrideRowDTO r : overrides) {
            // Skip rows without a calculated date
            if (r.calculatedDate == null) continue;
            
            String key = buildKey(year, r.zoneId, r.zoneCodeId, r.ruleId, r.mode, r.calculatedDate);

            // Skip published records regardless of action
            if (r.isPublished == true) { 
                skipped++; 
                continue; 
            }

            Schedule_Date__c current = existing.get(key);
            Boolean exists = (current != null) || (r.exists == true);

            // Skip existing records in CREATE_NEW mode
            if ('CREATE_NEW'.equalsIgnoreCase(action) && exists) {
                continue;
            }

            // Update planned records in OVERWRITE_PLANNED mode
            if (exists) {
                if ('OVERWRITE_PLANNED'.equalsIgnoreCase(action)) {
                    Schedule_Date__c cur = current;
                    if (cur == null) {
                        // If exists but not found by new key, skip
                        skipped++;
                        continue;
                    }
                    if (cur.Status__c == 'Planned') {
                        cur.Zone__c = r.zoneId;
                        cur.Zone_Code__c = r.zoneCodeId;
                        cur.Zone_Rule__c = r.ruleId;
                        cur.Mode__c = r.mode;
                        cur.Calculated_Date__c = r.calculatedDate;
                        cur.Generated_Batch_Id__c = batchId;
                        upserts.add(cur);
                        updated++;
                    } else {
                        skipped++;
                    }
                }
                continue;
            }

            // Create new records
            Schedule_Date__c sd = new Schedule_Date__c();
            String zoneName = zoneMap.get(r.zoneId)?.Name;
            String zoneCode = zoneCodeMap.get(r.zoneCodeId)?.Code__c;
            sd.Name = buildScheduleDateName(zoneName, zoneCode, r.calculatedDate);
            sd.Schedule_Year__c = sYear.Id;
            sd.Zone__c = r.zoneId;
            sd.Zone_Code__c = r.zoneCodeId;
            sd.Zone_Rule__c = r.ruleId;
            sd.Mode__c = r.mode;
            sd.Calculated_Date__c = r.calculatedDate;
            sd.Status__c = 'Planned';
            sd.Generated_Batch_Id__c = batchId;
            sd.Unique_Key__c = key;
            upserts.add(sd);
            created++;
        }

        // Save to database
        if (!upserts.isEmpty()) upsert upserts Unique_Key__c;

        // Return results
        GenerationResultDTO res = new GenerationResultDTO();
        res.batchId = batchId;
        res.createdCount = created;
        res.updatedCount = updated;
        res.skippedPublished = skipped;
        res.scheduleYearId = sYear.Id;
        res.totalPlanned = overrides.size();
        return res;
    }

    private static String buildKey(Integer year, Id zoneId, Id zoneCodeId, Id ruleId, String mode, Date d) {
        List<String> parts = new List<String>();
        parts.add(String.valueOf(year));
        parts.add((String)zoneId);
        parts.add((String)zoneCodeId);
        parts.add((String)ruleId);
        parts.add(mode);
        parts.add(d == null ? 'null' : d.format());
        return String.join(parts, '|');
    }

    private static Integer dowFromPick(String pick) {
        if (pick == null) return null;
        // Apex Date.dayOfWeek(): 1=Sun .. 7=Sat
        // Handle both abbreviated and full day names
        pick = pick.toLowerCase();
        if (pick == 'sun' || pick == 'sunday') return 1;
        if (pick == 'mon' || pick == 'monday') return 2;
        if (pick == 'tue' || pick == 'tuesday') return 3;
        if (pick == 'wed' || pick == 'wednesday') return 4;
        if (pick == 'thu' || pick == 'thursday') return 5;
        if (pick == 'fri' || pick == 'friday') return 6;
        if (pick == 'sat' || pick == 'saturday') return 7;
        return null;
    }

    private static String buildRuleLabel(String zoneName, String mode, Integer ordinal, Integer dow, Integer month) {
        List<String> parts = new List<String>();
        if (!String.isBlank(zoneName)) parts.add(zoneName);
        if (!String.isBlank(mode)) parts.add(mode);
        parts.add(ordinalLabel(ordinal) + ' ' + dowName(dow) + ' of ' + monthName(month));
        return String.join(parts, ' — ');
    }

    private static String ordinalLabel(Integer ord) {
        if (ord == null) return '';
        if (ord == 1) return '1st';
        if (ord == 2) return '2nd';
        if (ord == 3) return '3rd';
        if (ord == 4) return '4th';
        if (ord == 5) return 'Last';
        return String.valueOf(ord) + 'th';
    }

    private static String monthName(Integer m) {
        if (m == null) return '';
        List<String> names = new List<String>{'January','February','March','April','May','June','July','August','September','October','November','December'};
        if (m >= 1 && m <= 12) return names[m - 1];
        return String.valueOf(m);
    }

    private static String dowName(Integer d) {
        switch on d {
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

    /**
     * Calculates the date for the nth occurrence of a specific weekday in a month.
     * 
     * Ordinal__c field standard:
     * - 1 = 1st occurrence (e.g., "1st Monday of the month")
     * - 2 = 2nd occurrence
     * - 3 = 3rd occurrence
     * - 4 = 4th occurrence
     * - 5 = Last occurrence (e.g., "Last Monday of the month")
     *
     * @param year The year
     * @param month The month (1-12)
     * @param ordinal The occurrence (1-4 for specific occurrences, 5 for last occurrence)
     * @param dow Day of week (1=Sunday, 2=Monday, ..., 7=Saturday)
     * @return Date The calculated date
     */
    private static Date nthWeekday(Integer year, Integer month, Integer ordinal, Integer dow) {
    Date first = Date.newInstance(year, month, 1);
    // Ensure delta is always non-negative (0..6) so firstTarget stays within the month
    Integer delta = Math.mod(dow - dayOfWeek(first) + 7, 7);
        Date firstTarget = first.addDays(delta);
        Integer ord = ordinal == null ? 1 : ordinal;
        
        // If ordinal is 5, it means "last" occurrence of that day in the month
        if (ord == 5) {
            // Find last occurrence by starting from 5th week and working backwards if needed
            Date lastTry = firstTarget.addDays(7 * 4); // 5th week
            if (lastTry.month() != month) lastTry = firstTarget.addDays(7 * 3); // 4th week
            return lastTry;
        } else {
            // Normal ordinal (1st, 2nd, 3rd, 4th)
            Date candidate = firstTarget.addDays(7 * (ord - 1));
            if (candidate.month() != month) {
                // This shouldn't happen for normal ordinals, but return last occurrence if it does
                Date lastTry = firstTarget.addDays(7 * 3); // 4th week
                if (lastTry.month() != month) lastTry = lastTry.addDays(-7);
                return lastTry;
            }
            return candidate;
        }
    }

    // Apex has DateTime methods; for Date, emulate 1=Sun..7=Sat
    private static Integer dayOfWeek(Date d) {
        // Zeller's congruence using integer math
        Integer q = d.day();
        Integer m = d.month();
        Integer Y = d.year();
        if (m == 1) { m = 13; Y = Y - 1; }
        if (m == 2) { m = 14; Y = Y - 1; }
        Integer K = Math.mod(Y, 100);
        Integer J = Y / 100;
        Integer term1 = (13 * (m + 1)) / 5;
        Integer term2 = K / 4;
        Integer term3 = J / 4;
        Integer h = Math.mod(q + term1 + K + term2 + term3 + (5 * J), 7);
        // Zeller: 0=Saturday, 1=Sunday, 2=Monday, ... -> map to 1..7 Sun..Sat
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
        
        // Fallback if all components are empty
        if (String.isBlank(name)) {
            name = 'Schedule Date - ' + formattedDate;
        }
        
        // Ensure the name doesn't exceed Salesforce Name field limit (80 characters)
        if (name.length() > 80) {
            name = name.substring(0, 77) + '...';
        }
        
        return name;
    }
}