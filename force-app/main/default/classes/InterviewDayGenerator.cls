public class InterviewDayGenerator {
    
    // Helper method to calculate the first Monday of next month
    private static Date getFirstMondayOfNextMonth() {
        Date today = Date.today();
        Date firstDayOfNextMonth = today.toStartOfMonth().addMonths(1);
        
        // Get the day of week (1=Sunday, 2=Monday, ..., 7=Saturday)
        Integer dayOfWeek = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(firstDayOfNextMonth), 7) + 1;
        
        // Calculate days to add to get to first Monday
        // If first day is Monday (2), add 0 days
        // If first day is Tuesday (3), add 6 days to get to next Monday
        // If first day is Sunday (1), add 1 day to get to Monday
        Integer daysToAdd = dayOfWeek == 1 ? 1 : Math.mod((9 - dayOfWeek), 7);
        
        return firstDayOfNextMonth.addDays(daysToAdd);
    }
    
    // New: generate placeholders for a Zone by selected Schedule_Date__c records
    public static String processPlaceholdersByDates(Id zoneId, List<Id> scheduleDateIds, String mode, Integer totalSlots) {
        if (zoneId == null || scheduleDateIds == null || scheduleDateIds.isEmpty() || String.isBlank(mode) || totalSlots == null || totalSlots <= 0) {
            throw new IllegalArgumentException('Invalid parameters provided');
        }

    // Normalize legacy short codes and map Afternoon to AfterNoon for picklist consistency
    String normalizedMode = mode;
    if (normalizedMode == 'AM') normalizedMode = 'Morning';
    if (normalizedMode == 'PM') normalizedMode = 'Afternoon';
    String mappedMode = normalizedMode == 'Afternoon' ? 'AfterNoon' : normalizedMode;

        // Combined mode allowed? If passed as "Morning & Afternoon", we split evenly
    Boolean isCombined = (mode == 'Morning & Afternoon');
        List<String> modesToCreate = isCombined ? new List<String>{ 'Morning', 'AfterNoon' } : new List<String>{ mappedMode };
        Integer slotsPerMode = isCombined ? Math.max(1, totalSlots / 2) : totalSlots;

        String batchId = generateBatchId();
        Integer currentYear = Date.today().year();

        // Pull selected schedule dates and validate Zone
        Map<Id, Schedule_Date__c> datesById = new Map<Id, Schedule_Date__c>([
            SELECT Id, Zone__c, Zone_Code__c, Zone_Rule__c, Calculated_Date__c, Mode__c
            FROM Schedule_Date__c WHERE Id IN :scheduleDateIds
        ]);
        if (datesById.isEmpty()) {
            throw new IllegalArgumentException('No schedule dates found for the provided selection');
        }

        // Validate all belong to zoneId
        for (Schedule_Date__c sd : datesById.values()) {
            if (sd.Zone__c != zoneId) {
                throw new IllegalArgumentException('Selected dates must all belong to the chosen zone');
            }
        }

        // Build Interview Day records and schedules; honor idempotency:
        // Unique key based on Zone + Date + Mode, not Zone Code.
        List<Interview_Day__c> dayUpserts = new List<Interview_Day__c>();
        List<Interview_Day_Schedule__c> schedulesToInsert = new List<Interview_Day_Schedule__c>();

        // Track unique keys to avoid duplicates in the same batch
        Set<String> processedKeys = new Set<String>();

        for (Schedule_Date__c sd : datesById.values()) {
            for (String m : modesToCreate) {
                // Generate unique key with consistent formatting
                String uniqueKey = String.valueOf(zoneId) + '|' + String.valueOf(sd.Calculated_Date__c) + '|' + m + '|' + String.valueOf(currentYear);
                
                // Skip if we've already processed this key in this batch
                if (processedKeys.contains(uniqueKey)) {
                    System.debug('Skipping duplicate key in batch: ' + uniqueKey);
                    continue;
                }
                processedKeys.add(uniqueKey);

                Interview_Day__c day = new Interview_Day__c();
                day.Zone__c = zoneId;
                day.Schedule_Mode__c = m;
                day.Total_Slots__c = slotsPerMode;
                day.Year__c = currentYear;
                day.Status__c = 'Planned';
                day.Generated_Batch_Id__c = batchId;
                day.Interview_Date__c = sd.Calculated_Date__c;
                day.Unique_Key__c = uniqueKey;
                dayUpserts.add(day);
                
                System.debug('Created Interview Day with key: ' + uniqueKey);
            }
        }

        if (!dayUpserts.isEmpty()) {
            upsert dayUpserts Interview_Day__c.Unique_Key__c;
        }

        // Fetch IDs for created/existing days to determine schedules to top-up
        Map<String, Interview_Day__c> dayByKey = new Map<String, Interview_Day__c>();
        Set<Date> selectedDates = new Set<Date>();
        for (Schedule_Date__c sdx : datesById.values()) {
            if (sdx.Calculated_Date__c != null) selectedDates.add(sdx.Calculated_Date__c);
        }
        if (!selectedDates.isEmpty()) {
            for (Interview_Day__c d : [
                SELECT Id, Zone__c, Schedule_Mode__c, Interview_Date__c, Total_Slots__c
                FROM Interview_Day__c WHERE Zone__c = :zoneId AND Interview_Date__c IN :selectedDates
            ]) {
                String key = String.valueOf(d.Zone__c) + '|' + String.valueOf(d.Interview_Date__c) + '|' + d.Schedule_Mode__c + '|' + String.valueOf(currentYear);
                dayByKey.put(key, d);
            }
        }

        // Ensure schedule count per day equals slotsPerMode
        for (Interview_Day__c d : dayByKey.values()) {
            Integer existingCount = 0;
            for (AggregateResult ar : [SELECT COUNT(Id) c FROM Interview_Day_Schedule__c WHERE Interview_Day__c = :d.Id]) {
                existingCount = (Integer) ar.get('c');
            }
            Integer totalSlotsInt = (d.Total_Slots__c == null) ? 0 : d.Total_Slots__c.intValue();
            Integer toCreate = Math.max(0, totalSlotsInt - existingCount);
            
            // Format date for naming: MM/dd/yyyy
            String formattedDate = d.Interview_Date__c != null ? 
                d.Interview_Date__c.format() : 'No Date';
            
            for (Integer i = existingCount + 1; i <= existingCount + toCreate; i++) {
                Interview_Day_Schedule__c s = new Interview_Day_Schedule__c();
                s.Interview_Day__c = d.Id;
                s.Zone__c = d.Zone__c;  // Direct relationship to Zone as primary parent
                // Name format: Date+Mode+Slot number (e.g., "10/15/2025 Morning Slot 1")
                s.Name = formattedDate + ' ' + d.Schedule_Mode__c + ' Slot ' + i;
                s.Booked__c = false;
                schedulesToInsert.add(s);
            }
        }

        if (!schedulesToInsert.isEmpty()) insert schedulesToInsert;

        Integer totalCreated = schedulesToInsert.size();
        return 'Processed ' + dayByKey.size() + ' date(s) for mode "' + mode + '" with ' + totalCreated + ' schedule(s) created or ensured.' + '\nBatchId: ' + batchId;
    }
    public static void generateInterviewDays(Id zoneCodeId, String mode, Integer totalSlots, Integer year) {
        // Validate inputs
        if (zoneCodeId == null || totalSlots == null || totalSlots <= 0 || year == null) {
            throw new IllegalArgumentException('Invalid parameters provided');
        }
        
        try {
            // Generate unique batch ID
            String batchId = generateBatchId();
            
            // Get zone code information and associated zone
            HGH_Zone_Code__c zoneCode = [SELECT Id, Name, Code__c, Zone__c FROM HGH_Zone_Code__c WHERE Id = :zoneCodeId];
            
            // Create Interview Day record
            Interview_Day__c interviewDay = new Interview_Day__c();
            interviewDay.Zone__c = zoneCode.Zone__c;
            // Use Schedule_Mode__c for consistency across generation paths
            interviewDay.Schedule_Mode__c = mode;
            interviewDay.Total_Slots__c = totalSlots;
            interviewDay.Year__c = year;
            interviewDay.Status__c = 'Planned';
            interviewDay.Generated_Batch_Id__c = batchId;
            interviewDay.Unique_Key__c = zoneCode.Code__c + '_' + mode + '_' + year;
            
            // Use upsert to prevent duplicates
            Database.UpsertResult result = Database.upsert(interviewDay, Interview_Day__c.Unique_Key__c);
            
            // Schedules will be created by service logic elsewhere if needed.
            
        } catch (Exception e) {
            System.debug('Error generating interview days: ' + e.getMessage());
            throw e;
        }
    }
    
    private static void generatePlaceholderSlots(Id interviewDayId, Integer totalSlots, String batchId) {
        // Get Interview Day info to populate Zone relationship
        Interview_Day__c interviewDay = [SELECT Id, Zone__c, Interview_Date__c, Schedule_Mode__c FROM Interview_Day__c WHERE Id = :interviewDayId LIMIT 1];
        
        List<Interview_Day_Schedule__c> schedules = new List<Interview_Day_Schedule__c>();
        
        for (Integer i = 1; i <= totalSlots; i++) {
            Interview_Day_Schedule__c schedule = new Interview_Day_Schedule__c();
            schedule.Interview_Day__c = interviewDayId;
            schedule.Zone__c = interviewDay.Zone__c;  // Direct relationship to Zone
            schedule.Status__c = 'Available';
            schedule.Unique_Key__c = interviewDayId + '_' + i + '_' + batchId;
            
            schedules.add(schedule);
        }
        
        if (!schedules.isEmpty()) {
            Database.upsert(schedules, Interview_Day_Schedule__c.Unique_Key__c);
        }
    }
    
    public static String processInterviewPlaceholders(Id zoneId, String mode, Integer totalSlots) {
        // Validate inputs
        if (zoneId == null || String.isBlank(mode) || totalSlots == null || totalSlots <= 0) {
            throw new IllegalArgumentException('Invalid parameters provided');
        }
        
        try {
            // Get all zone codes for the selected zone
            List<HGH_Zone_Code__c> zoneCodes = [
                SELECT Id, Name, Code__c, Zone__c
                FROM HGH_Zone_Code__c 
                WHERE Zone__c = :zoneId AND Active__c = true
            ];
            
            if (zoneCodes.isEmpty()) {
                throw new IllegalArgumentException('No active zone codes found for the selected zone');
            }
            
            // Generate unique batch ID
            String batchId = generateBatchId();
            Integer currentYear = Date.today().year();
            
            List<Interview_Day_Schedule__c> schedulesToCreate = new List<Interview_Day_Schedule__c>();
            Integer totalRecords = 0;
            
            // Determine modes to process
            List<String> modesToProcess = new List<String>();
            Integer slotsPerMode = totalSlots;
            
            if (mode == 'Morning & Afternoon') {
                modesToProcess.add('Morning');
                modesToProcess.add('AfterNoon');
                slotsPerMode = totalSlots / 2; // Split slots between modes
            } else {
                // Normalize and map Afternoon to AfterNoon to match picklist values
                String normalizedMode2 = mode;
                if (normalizedMode2 == 'AM') normalizedMode2 = 'Morning';
                if (normalizedMode2 == 'PM') normalizedMode2 = 'Afternoon';
                String mappedMode = normalizedMode2 == 'Afternoon' ? 'AfterNoon' : normalizedMode2;
                modesToProcess.add(mappedMode);
            }
            
            // Create schedules for each zone code and mode combination
            for (HGH_Zone_Code__c zoneCode : zoneCodes) {
                for (String currentMode : modesToProcess) {
                    // Create Interview_Day__c record first
                    Interview_Day__c interviewDay = new Interview_Day__c();
                    interviewDay.Zone__c = zoneCode.Zone__c;
                    interviewDay.Zone_Name__c = zoneCode.Name;
                    interviewDay.Zone_Code__c = Decimal.valueOf(zoneCode.Code__c);
                    interviewDay.Schedule_Mode__c = currentMode;
                    interviewDay.Total_Slots__c = slotsPerMode;
                    interviewDay.Year__c = currentYear;
                    interviewDay.Status__c = 'Planned';
                    interviewDay.Generated_Batch_Id__c = batchId;
                    interviewDay.Interview_Date__c = getFirstMondayOfNextMonth(); // First Monday of next month
                    interviewDay.Unique_Key__c = zoneCode.Code__c + '_' + currentMode + '_' + currentYear;
                    
                    // Use upsert to prevent duplicates
                    Database.UpsertResult result = Database.upsert(interviewDay, Interview_Day__c.Unique_Key__c);
                    
                    // Generate Schedule records for this Interview Day
                    for (Integer i = 1; i <= slotsPerMode; i++) {
                        Interview_Day_Schedule__c schedule = new Interview_Day_Schedule__c();
                        schedule.Interview_Day__c = interviewDay.Id;
                        schedule.Zone__c = zoneCode.Zone__c;  // Direct relationship to Zone
                        schedule.Name = currentMode + ' Slot ' + i;
                        schedule.Booked__c = false;
                        
                        schedulesToCreate.add(schedule);
                        totalRecords++;
                    }
                }
            }
            
            // Insert all schedules
            if (!schedulesToCreate.isEmpty()) {
                insert schedulesToCreate;
            }
            
            // Build success message
            String message = String.format(
                'Successfully processed {0} zone codes with mode "{1}" and {2} slots. Created {3} Interview_Day_Schedule__c records.',
                new List<Object>{ zoneCodes.size(), mode, totalSlots, totalRecords }
            );
            
            return message;
            
        } catch (Exception e) {
            System.debug('Error processing interview placeholders: ' + e.getMessage());
            throw e;
        }
    }
    
    public static String processSelectedInterviewPlaceholders(List<Id> selectedZoneCodeIds, String mode, Integer totalSlots) {
        // Validate inputs
        if (selectedZoneCodeIds == null || selectedZoneCodeIds.isEmpty() || String.isBlank(mode) || totalSlots == null || totalSlots <= 0) {
            throw new IllegalArgumentException('Invalid parameters provided');
        }
        
        try {
            // Get selected zone codes
            List<HGH_Zone_Code__c> zoneCodes = [
                SELECT Id, Name, Code__c, Zone__c
                FROM HGH_Zone_Code__c 
                WHERE Id IN :selectedZoneCodeIds AND Active__c = true
            ];
            
            if (zoneCodes.isEmpty()) {
                throw new IllegalArgumentException('No active zone codes found for the selected IDs');
            }
            
            // Determine modes to check for existing records
            List<String> modesToProcess = new List<String>();
            Boolean isCombinedMode = mode == 'Morning & Afternoon';
            if (isCombinedMode) {
                modesToProcess.add('Morning');
                modesToProcess.add('AfterNoon');
            } else {
                String normalizedMode3 = mode;
                if (normalizedMode3 == 'AM') normalizedMode3 = 'Morning';
                if (normalizedMode3 == 'PM') normalizedMode3 = 'Afternoon';
                String mappedMode = normalizedMode3 == 'Afternoon' ? 'AfterNoon' : normalizedMode3;
                modesToProcess.add(mappedMode);
            }

            // Normalize zone codes for consistent lookups
            Map<Id, String> normalizedCodeById = new Map<Id, String>();
            Set<Decimal> zoneCodeNumbers = new Set<Decimal>();
            for (HGH_Zone_Code__c zoneCode : zoneCodes) {
                String normalized = normalizeZoneCode(zoneCode.Code__c);
                if (normalized != null) {
                    normalizedCodeById.put(zoneCode.Id, normalized);
                    zoneCodeNumbers.add(Decimal.valueOf(normalized));
                }
            }

            // Check for existing Interview_Day__c records for the selected zone codes and modes (current year only)
            Map<String, Set<String>> existingModesPerCode = new Map<String, Set<String>>();
            Integer currentYearForExisting = Date.today().year();
            if (!zoneCodeNumbers.isEmpty()) {
                List<Interview_Day__c> existing = [
                    SELECT Id, Zone_Code__c, Schedule_Mode__c, Year__c 
                    FROM Interview_Day__c 
                    WHERE Zone_Code__c IN :zoneCodeNumbers 
                    AND Schedule_Mode__c IN :modesToProcess
                    AND Year__c = :currentYearForExisting
                ];

                for (Interview_Day__c existingRecord : existing) {
                    String codeKey = String.valueOf(existingRecord.Zone_Code__c);
                    if (!existingModesPerCode.containsKey(codeKey)) {
                        existingModesPerCode.put(codeKey, new Set<String>());
                    }
                    existingModesPerCode.get(codeKey).add(existingRecord.Schedule_Mode__c);
                }
            }

            Set<String> skippedCombinationSet = new Set<String>();
            List<HGH_Zone_Code__c> validZoneCodes = new List<HGH_Zone_Code__c>();
            Map<String, List<String>> validModesPerZoneCode = new Map<String, List<String>>();

            for (HGH_Zone_Code__c zoneCode : zoneCodes) {
                String normalized = normalizedCodeById.get(zoneCode.Id);
                Set<String> existingForCode = (normalized != null && existingModesPerCode.containsKey(normalized))
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
                    validModesPerZoneCode.put(zoneCode.Id, validModes);
                }
            }

            if (validZoneCodes.isEmpty()) {
                List<String> skippedList = new List<String>(skippedCombinationSet);
                skippedList.sort();
                throw new IllegalArgumentException('All selected zone codes and modes already have Interview Day records: ' + String.join(skippedList, ', '));
            }
            
            // Generate unique batch ID and set current year for Interview Day uniqueness
            String batchId = generateBatchId();
            Integer currentYear = Date.today().year();
            
            List<Interview_Day_Schedule__c> schedulesToCreate = new List<Interview_Day_Schedule__c>();
            Integer totalRecords = 0;
            Integer slotsPerMode = totalSlots;
            
            if (isCombinedMode) {
                slotsPerMode = Math.max(1, totalSlots / 2); // Split slots between modes
            }
            
            // Create schedules for valid zone code and mode combinations
            for (HGH_Zone_Code__c zoneCode : validZoneCodes) {
                Decimal zoneCodeNumber;
                try {
                    zoneCodeNumber = Decimal.valueOf(zoneCode.Code__c);
                } catch (Exception ex) {
                    throw new IllegalArgumentException('Zone Code ' + zoneCode.Code__c + ' must be numeric to generate interview placeholders.');
                }

                List<String> validModes = validModesPerZoneCode.get(zoneCode.Id);
                for (String currentMode : validModes) {
                    // Create or reuse Interview_Day__c via unique key to avoid duplicates
                    Interview_Day__c interviewDay = new Interview_Day__c();
                    interviewDay.Zone__c = zoneCode.Zone__c;
                    interviewDay.Zone_Name__c = zoneCode.Name;
                    interviewDay.Zone_Code__c = zoneCodeNumber;
                    interviewDay.Schedule_Mode__c = currentMode;
                    interviewDay.Total_Slots__c = slotsPerMode;
                    interviewDay.Year__c = currentYear;
                    interviewDay.Status__c = 'Planned';
                    interviewDay.Generated_Batch_Id__c = batchId;
                    interviewDay.Interview_Date__c = getFirstMondayOfNextMonth(); // First Monday of next month
                    interviewDay.Unique_Key__c = zoneCode.Code__c + '_' + currentMode + '_' + currentYear;

                    Database.UpsertResult upsertResult = Database.upsert(interviewDay, Interview_Day__c.Unique_Key__c);

                    // Ensure we have the Interview Day Id from the upsert
                    Id interviewDayId = upsertResult.getId();
                    interviewDay.Id = interviewDayId;

                    // Create schedules when the Interview Day was newly created OR
                    // if it already existed but has fewer schedules than requested (e.g., after a delete)
                    Integer existingCount = 0;
                    for (AggregateResult ar : [
                        SELECT COUNT(Id) cnt
                        FROM Interview_Day_Schedule__c
                        WHERE Interview_Day__c = :interviewDayId
                    ]) {
                        existingCount = (Integer) ar.get('cnt');
                    }

                    Integer toCreate = Math.max(0, slotsPerMode - existingCount);
                    if (toCreate > 0) {
                        // Start numbering after existing schedules to avoid duplicate names
                        for (Integer i = existingCount + 1; i <= existingCount + toCreate; i++) {
                            Interview_Day_Schedule__c schedule = new Interview_Day_Schedule__c();
                            schedule.Interview_Day__c = interviewDay.Id;
                            schedule.Zone__c = zoneCode.Zone__c;  // Direct relationship to Zone
                            schedule.Name = currentMode + ' Slot ' + i + ' - Code ' + zoneCode.Code__c;
                            schedule.Booked__c = false;
                            
                            schedulesToCreate.add(schedule);
                            totalRecords++;
                        }
                    }
                }
            }
            
            // Insert all schedules
            if (!schedulesToCreate.isEmpty()) {
                insert schedulesToCreate;
            }
            
            // Build detailed success message
            List<String> processedZoneCodes = new List<String>();
            for (HGH_Zone_Code__c validZone : validZoneCodes) {
                processedZoneCodes.add('Zone Code ' + validZone.Code__c + ' (' + validZone.Name + ')');
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

            // Include BatchId so client can fetch details for last run
            message += '\nBatchId: ' + batchId;
            
            return message;
            
        } catch (Exception e) {
            System.debug('Error processing selected interview placeholders: ' + e.getMessage());
            throw e;
        }
    }

    private static String normalizeZoneCode(String codeValue) {
        if (String.isBlank(codeValue)) {
            return null;
        }
        try {
            return String.valueOf(Decimal.valueOf(codeValue.trim()));
        } catch (Exception e) {
            System.debug('Unable to normalize zone code: ' + codeValue);
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

    private static String generateBatchId() {
        return DateTime.now().format('yyyyMMddHHmmss') + '_' + String.valueOf(Math.random()).substring(2, 8);
    }
}