/**
 * Interview_Day_Schedule__c trigger logic called from InterviewDayScheduleSyncZone:
 * time labels (Start/End_Time_Text__c) and the Google Calendar producer side.
 *
 *  before insert : new slots are marked Pending (placeholder sync on, or already booked)
 *  before update : slots whose calendar-relevant fields changed are marked Pending
 *  after delete  : slots that had a Google event are deleted from Google by GoogleCalendarEventDeleteJob
 *  after insert/update/delete : enqueue GoogleCalendarSyncJob once per transaction when work exists
 *
 * Nothing here performs callouts or extra DML on the triggering records.
 */
public without sharing class InterviewDayScheduleTriggerHandler {

    private static Boolean workProducedThisTransaction = false;

    /** Keeps the display fields Start_Time_Text__c / End_Time_Text__c in step with the Time fields. */
    public static void stampTimeLabels(List<Interview_Day_Schedule__c> records) {
        for (Interview_Day_Schedule__c record : records) {
            record.Start_Time_Text__c = InterviewDayWindow.label(record.Start_Time__c);
            record.End_Time_Text__c = InterviewDayWindow.label(record.End_Time__c);
        }
    }

    public static void beforeInsert(List<Interview_Day_Schedule__c> records) {
        GoogleCalendarSettings settings = GoogleCalendarSettings.load();
        if (!settings.enabled) {
            return;
        }
        for (Interview_Day_Schedule__c record : records) {
            if (record.Google_Sync_Status__c == GoogleCalendarService.STATUS_PENDING
                || record.Google_Sync_Status__c == GoogleCalendarService.STATUS_DELETE_PENDING) {
                workProducedThisTransaction = true;
                continue;
            }
            if (settings.placeholderSyncEnabled || record.Booked__c == true) {
                record.Google_Sync_Status__c = GoogleCalendarService.STATUS_PENDING;
                workProducedThisTransaction = true;
            }
        }
    }

    public static void beforeUpdate(List<Interview_Day_Schedule__c> records, Map<Id, Interview_Day_Schedule__c> oldMap) {
        GoogleCalendarSettings settings = GoogleCalendarSettings.load();
        if (!settings.enabled) {
            return;
        }
        for (Interview_Day_Schedule__c record : records) {
            Interview_Day_Schedule__c old = oldMap.get(record.Id);
            if (record.Google_Sync_Status__c == GoogleCalendarService.STATUS_DELETE_PENDING) {
                workProducedThisTransaction = true;
                continue;
            }
            if (record.Google_Sync_Status__c == GoogleCalendarService.STATUS_PENDING
                && old.Google_Sync_Status__c != GoogleCalendarService.STATUS_PENDING) {
                workProducedThisTransaction = true;
                continue;
            }
            if (calendarFieldsChanged(record, old)) {
                record.Google_Sync_Status__c = GoogleCalendarService.STATUS_PENDING;
                workProducedThisTransaction = true;
            }
        }
    }

    public static void afterDelete(List<Interview_Day_Schedule__c> records) {
        GoogleCalendarSettings settings = GoogleCalendarSettings.load();
        List<GoogleCalendarEventDeleteJob.Target> targets = new List<GoogleCalendarEventDeleteJob.Target>();
        for (Interview_Day_Schedule__c record : records) {
            if (String.isBlank(record.Google_Event_Id__c)) {
                continue;
            }
            targets.add(new GoogleCalendarEventDeleteJob.Target(
                String.isNotBlank(record.Google_Calendar_Id__c) ? record.Google_Calendar_Id__c : settings.calendarId,
                record.Google_Event_Id__c,
                record.Name
            ));
        }
        GoogleCalendarEventDeleteJob.enqueue(targets);
    }

    /** Call from every after context. */
    public static void afterAny() {
        if (workProducedThisTransaction) {
            GoogleCalendarSyncJob.enqueue();
        }
    }

    @TestVisible
    private static Boolean calendarFieldsChanged(Interview_Day_Schedule__c record, Interview_Day_Schedule__c old) {
        return record.Booked__c != old.Booked__c
            || record.Case__c != old.Case__c
            || record.Assigned_Volunteer__c != old.Assigned_Volunteer__c
            || record.Start_Time__c != old.Start_Time__c
            || record.End_Time__c != old.End_Time__c
            || record.Interview_Day__c != old.Interview_Day__c;
    }
}