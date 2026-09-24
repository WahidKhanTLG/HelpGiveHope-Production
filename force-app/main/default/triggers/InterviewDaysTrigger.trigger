/**
 * Interview_Day__c trigger.
 *
 *  before insert / before update
 *      - derives the day's window: Start_Time__c defaults from the mode (Morning 08:00, Afternoon 12:30)
 *        unless a start time was entered; End_Time__c = Start_Time__c + Total_Slots__c x 15 minutes
 *      - blocks Total Slots / Start Time changes once a slot on the day is booked
 *  after insert / after update
 *      - creates, re-times or removes the 15-minute Interview_Day_Schedule__c slots so that the day
 *        holds exactly Total_Slots__c consecutive slots starting at Start_Time__c
 *
 * Slot numbering, naming and zone sync are completed by InterviewDayScheduleSyncZone.
 */
trigger InterviewDaysTrigger on Interview_Day__c (before insert, before update, after insert, after update) {

    Integer fixedSlotDurationMinutes = InterviewDayWindow.SLOT_MINUTES;

    // ------------------------------------------------------------------
    // BEFORE: window derivation and booked-day protection
    // ------------------------------------------------------------------
    if (Trigger.isBefore) {
        Set<Id> zoneIdsNeedingMode = new Set<Id>();
        for (Interview_Day__c interviewDay : Trigger.new) {
            if (String.isBlank(interviewDay.Schedule_Mode__c) && interviewDay.Zone__c != null) {
                zoneIdsNeedingMode.add(interviewDay.Zone__c);
            }
        }
        Map<Id, Zone__c> zoneModeMap = zoneIdsNeedingMode.isEmpty()
            ? new Map<Id, Zone__c>()
            : new Map<Id, Zone__c>([
                SELECT Id, Schedule_Mode__c FROM Zone__c WHERE Id IN :zoneIdsNeedingMode WITH USER_MODE
            ]);

        for (Interview_Day__c interviewDay : Trigger.new) {
            Interview_Day__c oldInterviewDay = Trigger.isUpdate ? Trigger.oldMap.get(interviewDay.Id) : null;

            String mode = String.isNotBlank(interviewDay.Schedule_Mode__c)
                ? interviewDay.Schedule_Mode__c
                : (zoneModeMap.containsKey(interviewDay.Zone__c) ? zoneModeMap.get(interviewDay.Zone__c).Schedule_Mode__c : null);
            Time defaultStart = InterviewDayWindow.defaultStartFor(mode);

            // Keep an explicitly entered start time; otherwise anchor to the mode. When the mode changes
            // and the old start was that mode's default, follow the new mode.
            Boolean useDefault = interviewDay.Start_Time__c == null;
            if (!useDefault && oldInterviewDay != null
                && oldInterviewDay.Schedule_Mode__c != interviewDay.Schedule_Mode__c
                && oldInterviewDay.Start_Time__c == InterviewDayWindow.defaultStartFor(oldInterviewDay.Schedule_Mode__c)) {
                useDefault = true;
            }
            if (useDefault && defaultStart != null) {
                interviewDay.Start_Time__c = defaultStart;
            }

            Integer totalSlots = interviewDay.Total_Slots__c == null ? 0 : Integer.valueOf(interviewDay.Total_Slots__c);
            interviewDay.End_Time__c = InterviewDayWindow.windowEnd(interviewDay.Start_Time__c, totalSlots);
        }

        if (Trigger.isUpdate) {
            Set<Id> interviewDayIdsWithWindowChanges = new Set<Id>();

            for (Interview_Day__c interviewDay : Trigger.new) {
                Interview_Day__c oldInterviewDay = Trigger.oldMap.get(interviewDay.Id);

                Decimal newTotalSlots = interviewDay.Total_Slots__c == null ? 0 : interviewDay.Total_Slots__c;
                Decimal oldTotalSlots = oldInterviewDay.Total_Slots__c == null ? 0 : oldInterviewDay.Total_Slots__c;

                if (newTotalSlots != oldTotalSlots
                    || (oldInterviewDay.Start_Time__c != null && interviewDay.Start_Time__c != oldInterviewDay.Start_Time__c)) {
                    interviewDayIdsWithWindowChanges.add(interviewDay.Id);
                }
            }

            if (!interviewDayIdsWithWindowChanges.isEmpty()) {
                Map<Id, Integer> bookedCountByInterviewDay = new Map<Id, Integer>();

                for (AggregateResult ar : [
                    SELECT Interview_Day__c interviewDayId, COUNT(Id) bookedCount
                    FROM Interview_Day_Schedule__c
                    WHERE Interview_Day__c IN :interviewDayIdsWithWindowChanges
                      AND Booked__c = true
                    WITH USER_MODE
                    GROUP BY Interview_Day__c
                ]) {
                    bookedCountByInterviewDay.put((Id) ar.get('interviewDayId'), (Integer) ar.get('bookedCount'));
                }

                for (Interview_Day__c interviewDay : Trigger.new) {
                    if (!interviewDayIdsWithWindowChanges.contains(interviewDay.Id)) {
                        continue;
                    }
                    Integer bookedCount = bookedCountByInterviewDay.containsKey(interviewDay.Id)
                        ? bookedCountByInterviewDay.get(interviewDay.Id)
                        : 0;
                    if (bookedCount > 0) {
                        interviewDay.addError(
                            'Total Slots and Start Time cannot be changed after an interview slot has been booked because existing appointment times would change.'
                        );
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // AFTER: slot inventory
    // ------------------------------------------------------------------
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        Set<Id> interviewDayIds = new Set<Id>();
        Set<Id> zoneIds = new Set<Id>();

        for (Interview_Day__c interviewDay : Trigger.new) {
            interviewDayIds.add(interviewDay.Id);
            if (interviewDay.Zone__c != null) {
                zoneIds.add(interviewDay.Zone__c);
            }
        }

        Map<Id, Zone__c> zoneMap = new Map<Id, Zone__c>();
        if (!zoneIds.isEmpty()) {
            zoneMap = new Map<Id, Zone__c>([
                SELECT Id, Schedule_Mode__c
                FROM Zone__c
                WHERE Id IN :zoneIds
                WITH USER_MODE
            ]);
        }

        Map<Id, List<Interview_Day_Schedule__c>> schedulesMap = new Map<Id, List<Interview_Day_Schedule__c>>();
        Map<Id, Integer> slotNumberByScheduleId = new Map<Id, Integer>();

        for (Interview_Day_Schedule__c scheduleRecord : [
            SELECT Id, Interview_Day__c, Name, Booked__c, Start_Time__c, End_Time__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c IN :interviewDayIds
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]) {
            if (!schedulesMap.containsKey(scheduleRecord.Interview_Day__c)) {
                schedulesMap.put(scheduleRecord.Interview_Day__c, new List<Interview_Day_Schedule__c>());
            }
            List<Interview_Day_Schedule__c> daySchedules = schedulesMap.get(scheduleRecord.Interview_Day__c);
            daySchedules.add(scheduleRecord);

            Integer fallbackSlotNumber = daySchedules.size();
            Integer parsedSlotNumber = fallbackSlotNumber;

            if (!String.isBlank(scheduleRecord.Name)) {
                List<String> nameParts = scheduleRecord.Name.split(' ');
                if (!nameParts.isEmpty()) {
                    try {
                        Integer candidate = Integer.valueOf(nameParts[nameParts.size() - 1]);
                        if (candidate > 0) {
                            parsedSlotNumber = candidate;
                        }
                    } catch (Exception ignored) {
                        parsedSlotNumber = fallbackSlotNumber;
                    }
                }
            }
            slotNumberByScheduleId.put(scheduleRecord.Id, parsedSlotNumber);
        }

        List<Interview_Day_Schedule__c> schedulesToCreate = new List<Interview_Day_Schedule__c>();
        List<Interview_Day_Schedule__c> schedulesToUpdate = new List<Interview_Day_Schedule__c>();
        List<Interview_Day_Schedule__c> schedulesToDelete = new List<Interview_Day_Schedule__c>();
        Set<Id> scheduleIdsToDelete = new Set<Id>();

        for (Interview_Day__c interviewDay : Trigger.new) {
            Zone__c relatedZone = zoneMap.get(interviewDay.Zone__c);

            String scheduleMode = String.isNotBlank(interviewDay.Schedule_Mode__c)
                ? interviewDay.Schedule_Mode__c
                : (relatedZone == null ? null : relatedZone.Schedule_Mode__c);

            Integer desiredSlots = interviewDay.Total_Slots__c == null ? 0 : Integer.valueOf(interviewDay.Total_Slots__c);

            List<Interview_Day_Schedule__c> existingSchedules = schedulesMap.containsKey(interviewDay.Id)
                ? schedulesMap.get(interviewDay.Id)
                : new List<Interview_Day_Schedule__c>();

            Integer totalExistingSchedules = existingSchedules.size();
            Integer slotsToCreate = desiredSlots - totalExistingSchedules;

            if (slotsToCreate < 0) {
                Integer slotsToDelete = Math.abs(slotsToCreate);
                Integer deletedCount = 0;
                for (Integer slotNumber = totalExistingSchedules; slotNumber >= 1 && deletedCount < slotsToDelete; slotNumber--) {
                    for (Interview_Day_Schedule__c scheduleToCheck : existingSchedules) {
                        if (slotNumberByScheduleId.get(scheduleToCheck.Id) == slotNumber && scheduleToCheck.Booked__c != true) {
                            schedulesToDelete.add(scheduleToCheck);
                            scheduleIdsToDelete.add(scheduleToCheck.Id);
                            deletedCount++;
                            break;
                        }
                    }
                }
            }

            // The day's window start drives every slot; it was derived in the before context.
            Time windowStartTime = interviewDay.Start_Time__c != null
                ? interviewDay.Start_Time__c
                : InterviewDayWindow.defaultStartFor(scheduleMode);
            Boolean canTime = windowStartTime != null;

            Boolean windowChanged = false;
            if (Trigger.isUpdate) {
                Interview_Day__c oldInterviewDay = Trigger.oldMap.get(interviewDay.Id);
                Decimal newTotalSlots = interviewDay.Total_Slots__c == null ? 0 : interviewDay.Total_Slots__c;
                Decimal oldTotalSlots = oldInterviewDay.Total_Slots__c == null ? 0 : oldInterviewDay.Total_Slots__c;
                windowChanged = newTotalSlots != oldTotalSlots || interviewDay.Start_Time__c != oldInterviewDay.Start_Time__c;
            }

            if (canTime && desiredSlots > 0) {
                for (Interview_Day_Schedule__c existingSchedule : existingSchedules) {
                    if (scheduleIdsToDelete.contains(existingSchedule.Id)) {
                        continue;
                    }
                    Integer slotNumber = slotNumberByScheduleId.get(existingSchedule.Id);
                    if (slotNumber == null || slotNumber < 1 || slotNumber > desiredSlots) {
                        continue;
                    }
                    Time expectedStart = InterviewDayWindow.slotStart(windowStartTime, slotNumber);
                    Time expectedEnd = InterviewDayWindow.slotEnd(windowStartTime, slotNumber);
                    Boolean needsTimeUpdate = windowChanged
                        || existingSchedule.Start_Time__c != expectedStart
                        || existingSchedule.End_Time__c != expectedEnd;
                    if (!needsTimeUpdate) {
                        continue;
                    }
                    existingSchedule.Start_Time__c = expectedStart;
                    existingSchedule.End_Time__c = expectedEnd;
                    schedulesToUpdate.add(existingSchedule);
                }
            }

            if (slotsToCreate > 0 && relatedZone != null) {
                for (Integer i = 0; i < slotsToCreate; i++) {
                    Integer slotNumber = totalExistingSchedules + i + 1;
                    Interview_Day_Schedule__c newSchedule = new Interview_Day_Schedule__c();
                    newSchedule.Interview_Day__c = interviewDay.Id;
                    newSchedule.Name = scheduleMode + ' Slot ' + slotNumber;
                    if (canTime && desiredSlots > 0) {
                        newSchedule.Start_Time__c = InterviewDayWindow.slotStart(windowStartTime, slotNumber);
                        newSchedule.End_Time__c = InterviewDayWindow.slotEnd(windowStartTime, slotNumber);
                    }
                    schedulesToCreate.add(newSchedule);
                }
            }
        }

        if (!schedulesToDelete.isEmpty()) {
            Database.delete(schedulesToDelete, AccessLevel.USER_MODE);
        }
        if (!schedulesToUpdate.isEmpty()) {
            Database.update(schedulesToUpdate, AccessLevel.USER_MODE);
        }
        if (!schedulesToCreate.isEmpty()) {
            Database.insert(schedulesToCreate, AccessLevel.USER_MODE);
        }
    }
}