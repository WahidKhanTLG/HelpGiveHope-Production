/**
 * Single consumer for Google Calendar synchronisation.
 *
 * Producers (triggers, flows, booking service) only set Interview_Day_Schedule__c.Google_Sync_Status__c to
 * Pending / Delete Pending. This job drains that work, oldest change first. Events of deleted slot
 * records are handled by GoogleCalendarEventDeleteJob.
 * It processes Sync_Batch_Size__c schedules per execution, keeps under the callout limit, writes all
 * results in one DML statement after the callouts, and chains itself while work remains.
 *
 * enqueue() is safe to call from any trigger: it de-duplicates per transaction, skips guest users (they
 * cannot reach the named principal) and skips when a job is already queued or running. The scheduled
 * sweep (GoogleCalendarSyncScheduler) catches anything that slips through those guards.
 */
public without sharing class GoogleCalendarSyncJob implements Queueable, Database.AllowsCallouts {

    public static final String CLASS_NAME = 'GoogleCalendarSyncJob';
    private static final Integer CALLOUT_BUDGET = 90;
    /** Apex allows 120 s of callout time per transaction; stop well before and let the chain continue. */
    private static final Long TIME_BUDGET_MS = 75000;

    @TestVisible private static Boolean allowInTests = false;
    @TestVisible private static Boolean enqueuedInThisTransaction = false;

    /**
     * Enqueues the job if useful. Returns the job Id, or null when skipped.
     */
    public static Id enqueue() {
        if (Test.isRunningTest() && !allowInTests) {
            return null;
        }
        if (enqueuedInThisTransaction) {
            return null;
        }
        if (UserInfo.getUserType() == 'Guest') {
            // Guest users do not have access to the named principal; the sweep will pick the work up.
            return null;
        }
        GoogleCalendarSettings settings = GoogleCalendarSettings.load();
        if (!settings.enabled) {
            return null;
        }
        if (isJobActive()) {
            return null;
        }
        try {
            Id jobId = System.enqueueJob(new GoogleCalendarSyncJob());
            enqueuedInThisTransaction = true;
            return jobId;
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'GoogleCalendarSyncJob could not be enqueued: ' + ex.getMessage());
            return null;
        }
    }

    @TestVisible
    private static Boolean isJobActive() {
        Set<String> activeStatuses = new Set<String>{ 'Queued', 'Preparing', 'Processing' };
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
              AND ApexClass.Name = :CLASS_NAME
              AND Status IN :activeStatuses
        ] > 0;
    }

    public void execute(QueueableContext context) {
        GoogleCalendarSettings settings = GoogleCalendarSettings.load();
        if (!settings.enabled) {
            return;
        }

        Integer callouts = 0;
        Boolean transientFailure = false;
        Long startedAt = System.currentTimeMillis();

        // ---- 2. schedules ----
        List<Interview_Day_Schedule__c> scheduleUpdates = new List<Interview_Day_Schedule__c>();
        if (!transientFailure && callouts < CALLOUT_BUDGET) {
            for (Interview_Day_Schedule__c schedule : GoogleCalendarService.queryForSync(null, settings.syncBatchSize)) {
                // A create can take up to three callouts (lookup, patch-miss, post).
                if (callouts + 3 > CALLOUT_BUDGET || System.currentTimeMillis() - startedAt > TIME_BUDGET_MS) {
                    break;
                }
                GoogleCalendarService.SyncOutcome outcome = GoogleCalendarService.syncSchedule(schedule, settings);
                callouts += outcome.calloutsUsed;
                if (outcome.transientFailure) {
                    transientFailure = true;
                    break;
                }
                if (outcome.updateRecord != null) {
                    scheduleUpdates.add(outcome.updateRecord);
                }
            }
        }

        // ---- 3. persist (after all callouts) ----
        if (!scheduleUpdates.isEmpty()) {
            Database.update(scheduleUpdates, false, AccessLevel.SYSTEM_MODE);
        }

        // ---- 4. chain while work remains (not on rate limiting: the sweep retries later) ----
        if (!transientFailure && !Test.isRunningTest() && GoogleCalendarService.countPendingWork() > 0) {
            try {
                System.enqueueJob(new GoogleCalendarSyncJob());
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'GoogleCalendarSyncJob could not chain: ' + ex.getMessage());
            }
        }
    }
}