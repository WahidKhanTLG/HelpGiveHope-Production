trigger InterviewDaysTrigger on Interview_Day__c (before update, after insert, after update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        Set<Id> interviewDayIds = new Set<Id>();

        for (Interview_Day__c interviewDay : Trigger.new) {
            Interview_Day__c oldInterviewDay = Trigger.oldMap.get(interviewDay.Id);
            if (interviewDay.Total_Slots__c < oldInterviewDay.Total_Slots__c) {
                interviewDayIds.add(interviewDay.Id);
            }
        }

        if (!interviewDayIds.isEmpty()) {
            Map<Id, Integer> bookedCountByInterviewDay = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT Interview_Day__c interviewDayId, COUNT(Id) bookedCount
                FROM Interview_Day_Schedule__c
                WHERE Interview_Day__c IN :interviewDayIds AND Booked__c = true
                WITH USER_MODE
                GROUP BY Interview_Day__c
            ]) {
                bookedCountByInterviewDay.put(
                    (Id) ar.get('interviewDayId'),
                    (Integer) ar.get('bookedCount')
                );
            }

            for (Interview_Day__c interviewDay : Trigger.new) {
                Interview_Day__c oldInterviewDay = Trigger.oldMap.get(interviewDay.Id);
                if (interviewDay.Total_Slots__c < oldInterviewDay.Total_Slots__c) {
                    Integer bookedCount = bookedCountByInterviewDay.containsKey(interviewDay.Id)
                        ? bookedCountByInterviewDay.get(interviewDay.Id)
                        : 0;
                    if (Integer.valueOf(interviewDay.Total_Slots__c) < bookedCount) {
                        interviewDay.addError('Cannot reduce Total Slots below the number of already booked schedules.');
                    }
                }
            }
        }
    }

    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        Set<Id> interviewDayIds = new Set<Id>();
        Set<Id> zoneIds = new Set<Id>();

        for (Interview_Day__c interviewDay : Trigger.new) {
            interviewDayIds.add(interviewDay.Id);
            if (interviewDay.Zone__c != null) {
                zoneIds.add(interviewDay.Zone__c);
            }
        }

        Map<Id, Zone__c> zoneMap = new Map<Id, Zone__c>([
            SELECT Id, Schedule_Mode__c
            FROM Zone__c
            WHERE Id IN :zoneIds
            WITH USER_MODE
        ]);

        Map<Id, List<Interview_Day_Schedule__c>> schedulesMap = new Map<Id, List<Interview_Day_Schedule__c>>();
        for (Interview_Day_Schedule__c scheduleRecord : [
            SELECT Id, Interview_Day__c, Name, Booked__c
            FROM Interview_Day_Schedule__c
            WHERE Interview_Day__c IN :interviewDayIds
            WITH USER_MODE
            ORDER BY Name DESC
        ]) {
            if (!schedulesMap.containsKey(scheduleRecord.Interview_Day__c)) {
                schedulesMap.put(scheduleRecord.Interview_Day__c, new List<Interview_Day_Schedule__c>());
            }
            schedulesMap.get(scheduleRecord.Interview_Day__c).add(scheduleRecord);
        }

        List<Interview_Day_Schedule__c> schedulesToCreate = new List<Interview_Day_Schedule__c>();
        List<Interview_Day_Schedule__c> schedulesToDelete = new List<Interview_Day_Schedule__c>();

        for (Interview_Day__c interviewDay : Trigger.new) {
            Zone__c relatedZone = zoneMap.get(interviewDay.Zone__c);
            Integer totalExistingSchedules = schedulesMap.containsKey(interviewDay.Id)
                ? schedulesMap.get(interviewDay.Id).size()
                : 0;
            Integer slotsToCreate = Integer.valueOf(interviewDay.Total_Slots__c - totalExistingSchedules);

            if (slotsToCreate < 0) {
                Integer slotsToDelete = Math.abs(slotsToCreate);
                List<Interview_Day_Schedule__c> existingSchedules = schedulesMap.get(interviewDay.Id);
                Integer deletedCount = 0;

                for (Interview_Day_Schedule__c scheduleToDelete : existingSchedules) {
                    if (!scheduleToDelete.Booked__c) {
                        schedulesToDelete.add(scheduleToDelete);
                        deletedCount++;
                    }
                    if (deletedCount == slotsToDelete) {
                        break;
                    }
                }
            }

            if (slotsToCreate > 0 && relatedZone != null) {
                for (Integer i = 0; i < slotsToCreate; i++) {
                    Interview_Day_Schedule__c newSchedule = new Interview_Day_Schedule__c();
                    newSchedule.Interview_Day__c = interviewDay.Id;
                    newSchedule.Name = relatedZone.Schedule_Mode__c + ' Slot ' + i;
                    schedulesToCreate.add(newSchedule);
                }
            }
        }

        if (!schedulesToCreate.isEmpty()) {
            insert as user schedulesToCreate;
        }

        if (!schedulesToDelete.isEmpty()) {
            delete as user schedulesToDelete;
        }
    }

}