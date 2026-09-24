/**
 * Legacy single-record entry point. Kept so existing callers and the flow invocable keep compiling.
 * New code should set Google_Sync_Status__c and call GoogleCalendarSyncJob.enqueue() instead.
 */
public without sharing class GoogleCalendarSyncQueueable
    implements Queueable, Database.AllowsCallouts {

    private Id scheduleId;
    private String operation;

    public class SyncRequest {
        @InvocableVariable(required=true)
        public Id scheduleId;

        @InvocableVariable
        public String operation;
    }

    public GoogleCalendarSyncQueueable(Id scheduleId, String operation) {
        this.scheduleId = scheduleId;
        this.operation = operation;
    }

    /**
     * Flow entry point. Marks the schedules for synchronisation and enqueues the bulk job once,
     * instead of one queueable per record (which hit the 50-job limit on bulk updates and could
     * produce duplicate Google events when two producers fired for the same booking).
     */
    @InvocableMethod(
        label='Queue Google Calendar Sync'
        description='Marks interview schedules for Google Calendar create/update/delete processing.'
    )
    public static void enqueueFromFlow(List<SyncRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Map<Id, Interview_Day_Schedule__c> updates = new Map<Id, Interview_Day_Schedule__c>();
        for (SyncRequest request : requests) {
            if (request == null || request.scheduleId == null) {
                continue;
            }
            String requestedOperation = String.isBlank(request.operation)
                ? 'UPSERT'
                : request.operation.trim().toUpperCase();
            updates.put(request.scheduleId, new Interview_Day_Schedule__c(
                Id = request.scheduleId,
                Google_Sync_Status__c = requestedOperation == 'DELETE'
                    ? GoogleCalendarService.STATUS_DELETE_PENDING
                    : GoogleCalendarService.STATUS_PENDING
            ));
        }

        if (!updates.isEmpty()) {
            Database.update(updates.values(), false, AccessLevel.SYSTEM_MODE);
            GoogleCalendarSyncJob.enqueue();
        }
    }

    public void execute(QueueableContext context) {
        if (scheduleId == null) {
            return;
        }

        String requestedOperation = String.isBlank(operation)
            ? 'UPSERT'
            : operation.trim().toUpperCase();

        if (requestedOperation == 'DELETE') {
            GoogleCalendarService.deleteEvent(scheduleId);
        } else {
            GoogleCalendarService.upsertEvent(scheduleId);
        }
    }
}