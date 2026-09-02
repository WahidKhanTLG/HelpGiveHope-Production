/**
 * Trigger to synchronize Zone__c between Interview_Day__c and Interview_Day_Schedule__c
 * This ensures that the direct Zone relationship on Interview_Day_Schedule__c stays in sync
 * with the Zone on the parent Interview_Day__c record
 */
trigger InterviewDayScheduleSyncZone on Interview_Day_Schedule__c (before insert, before update, before delete) {

    if (Trigger.isDelete) {
        for (Interview_Day_Schedule__c sched : Trigger.old) {
            if (sched.Booked__c == true) {
                sched.addError('Booked schedules cannot be deleted. Unbooked schedules only can be deleted.');
            }
        }
        return;
    }

    // Collect parent Interview Day Ids
    Set<Id> interviewDayIds = new Set<Id>();
    for (Interview_Day_Schedule__c s : Trigger.new) {
        if (s.Interview_Day__c != null) {
            interviewDayIds.add(s.Interview_Day__c);
        }
    }
    if (interviewDayIds.isEmpty()) return;

    // Query parents with fields needed for Zone sync & name generation
    Map<Id, Interview_Day__c> dayById = new Map<Id, Interview_Day__c>([
        SELECT Id, Zone__c, Interview_Date__c, Schedule_Mode__c
        FROM Interview_Day__c
        WHERE Id IN :interviewDayIds
    ]);

    // Pre-compute existing schedule counts (for before insert only) so we can assign slot numbers sequentially.
    Map<Id, Integer> nextSlotNumber = new Map<Id, Integer>();
    if (Trigger.isInsert) {
        // Aggregate existing (already stored) schedule counts per Interview Day
        for (AggregateResult ar : [
            SELECT Interview_Day__c iDay, COUNT(Id) cnt
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c IN :interviewDayIds
            GROUP BY Interview_Day__c
        ]) {
            nextSlotNumber.put((Id)ar.get('iDay'), (Integer)ar.get('cnt') + 1);
        }
        // Initialize missing keys with 1
        for (Id idDay : interviewDayIds) {
            if (!nextSlotNumber.containsKey(idDay)) nextSlotNumber.put(idDay, 1);
        }
    }

    // Helper to decide if we should (re)name a schedule
    Boolean isUpdate = Trigger.isUpdate;
    for (Interview_Day_Schedule__c sched : Trigger.new) {
        if (sched.Interview_Day__c == null) continue; // cannot derive
        Interview_Day__c parent = dayById.get(sched.Interview_Day__c);
        if (parent == null) continue;

        // Always sync Zone from parent
        sched.Zone__c = parent.Zone__c;

        // Naming rules:
        //  - On insert: always assign if Name blank OR starts with 'null' OR contains 'Slot 0'
        //  - On update: assign only if Name is blank/invalid OR Interview_Day__c changed (old parent differs)
        Boolean parentChanged = isUpdate && (sched.Interview_Day__c != null && sched.Interview_Day__c != Trigger.oldMap.get(sched.Id).Interview_Day__c);
        Boolean invalidName = String.isBlank(sched.Name) || sched.Name.startsWithIgnoreCase('null') || sched.Name.containsIgnoreCase('Slot 0');
        if (Trigger.isInsert || parentChanged || invalidName) {
            // Build base components
            String dateLabel = parent.Interview_Date__c == null ? 'No Date' : parent.Interview_Date__c.format();
            String modeLabel = String.isBlank(parent.Schedule_Mode__c) ? 'Unknown' : parent.Schedule_Mode__c;
            Integer slotNum;
            if (Trigger.isInsert) {
                // Use running counter per parent
                slotNum = nextSlotNumber.get(parent.Id);
                nextSlotNumber.put(parent.Id, slotNum + 1);
            } else {
                // On update keep existing trailing slot number if parsable, else assign 1
                slotNum = 1;
                if (!String.isBlank(sched.Name)) {
                    // Attempt to parse last integer token
                    List<String> parts = sched.Name.split(' ');
                    if (!parts.isEmpty()) {
                        try {
                            slotNum = Integer.valueOf(parts[parts.size()-1]);
                            if (slotNum <= 0) slotNum = 1;
                        } catch (Exception ignore) {
                            slotNum = 1;
                        }
                    }
                }
            }
            sched.Name = dateLabel + ' ' + modeLabel + ' Slot ' + slotNum;
        }
    }
}