public class InterviewDaysTriggerHandler {

    public static void handleBeforeUpdate(Map<Id, Interview_Day__c> oldMap, List<Interview_Day__c> newList) {
        Set<Id> interviewDayIds = new Set<Id>();
        
        for (Interview_Day__c interviewDay : newList) {
            Interview_Day__c oldInterviewDay = oldMap.get(interviewDay.Id);
            
            if (interviewDay.Total_Slots__c < oldInterviewDay.Total_Slots__c) {
                interviewDayIds.add(interviewDay.Id);
            }
        }

        if (!interviewDayIds.isEmpty()) {
            List<Interview_Day_Schedule__c> bookedSchedules = [
                SELECT Id, Interview_Day__c, Booked__c 
                FROM Interview_Day_Schedule__c 
                WHERE Interview_Day__c IN :interviewDayIds AND Booked__c = true
            ];
            
            if (!bookedSchedules.isEmpty()) {
                for (Interview_Day__c interviewDay : newList) {
                    Interview_Day__c oldInterviewDay = oldMap.get(interviewDay.Id);
                    if (interviewDay.Total_Slots__c < oldInterviewDay.Total_Slots__c) {
                        interviewDay.addError('Cannot reduce Total Slots because some schedules are already booked.');
                    }
                }
            }
        }
    }

    public static void handleAfterInsertOrUpdate(List<Interview_Day__c> interviewDaysList) {
        Set<Id> interviewDayIds = new Set<Id>();
        Set<Id> zoneIds = new Set<Id>();

        for (Interview_Day__c interviewDay : interviewDaysList) {
            interviewDayIds.add(interviewDay.Id);
            if (interviewDay.Zone__c != null) {
                zoneIds.add(interviewDay.Zone__c);
            }
        }

        Map<Id, Zone__c> zoneMap = new Map<Id, Zone__c>([
            SELECT Id, Schedule_Mode__c 
            FROM Zone__c 
            WHERE Id IN :zoneIds
        ]);

        Map<Id, List<Interview_Day_Schedule__c>> schedulesMap = new Map<Id, List<Interview_Day_Schedule__c>>();
        for (Interview_Day_Schedule__c schedule : [
            SELECT Id, Interview_Day__c, Name, Booked__c 
            FROM Interview_Day_Schedule__c 
            WHERE Interview_Day__c IN :interviewDayIds
        ]) {
            if (!schedulesMap.containsKey(schedule.Interview_Day__c)) {
                schedulesMap.put(schedule.Interview_Day__c, new List<Interview_Day_Schedule__c>());
            }
            schedulesMap.get(schedule.Interview_Day__c).add(schedule);
        }

        List<Interview_Day_Schedule__c> schedulesToCreate = new List<Interview_Day_Schedule__c>();
        List<Interview_Day_Schedule__c> schedulesToDelete = new List<Interview_Day_Schedule__c>();

        for (Interview_Day__c interviewDay : interviewDaysList) {
            Zone__c relatedZone = zoneMap.get(interviewDay.Zone__c);
            Integer totalExistingSchedules = schedulesMap.containsKey(interviewDay.Id) ? schedulesMap.get(interviewDay.Id).size() : 0;
            Integer slotsToCreate = Integer.valueOf(interviewDay.Total_Slots__c - totalExistingSchedules);

            if (slotsToCreate < 0) {
                Integer slotsToDelete = Math.abs(slotsToCreate);
                List<Interview_Day_Schedule__c> existingSchedules = schedulesMap.get(interviewDay.Id);
                
                Integer deletedCount = 0;
                
                existingSchedules.sort(new InterviewDayScheduleNameComparator());

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
            insert schedulesToCreate;
        }

        if (!schedulesToDelete.isEmpty()) {
            delete schedulesToDelete;
        }
    }

    public class InterviewDayScheduleNameComparator implements Comparator<Interview_Day_Schedule__c> {
        public Integer compare(Interview_Day_Schedule__c s1, Interview_Day_Schedule__c s2) {
            return s2.Name.compareTo(s1.Name);
        }
    }
}