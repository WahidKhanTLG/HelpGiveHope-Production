/**
 * Periodic sweep for Google Calendar synchronisation.
 *
 * Runs every Sweep_Interval_Minutes__c, enqueues GoogleCalendarSyncJob when work is pending, and
 * re-schedules itself. It is the safety net for work produced by guest users (self-service page),
 * for rows left Pending after a rate-limit pause, and for anything created while a job was running.
 *
 * Start once from Anonymous Apex:   GoogleCalendarSyncScheduler.start();
 * Stop:                              GoogleCalendarSyncScheduler.stop();
 */
public without sharing class GoogleCalendarSyncScheduler implements Schedulable {

    public static final String JOB_NAME_PREFIX = 'HGH Google Calendar Sync Sweep';

    public void execute(SchedulableContext context) {
        sweep();
        if (!Test.isRunningTest()) {
            scheduleNextSafely();
            abortQuietly(context == null ? null : context.getTriggerId());
        }
    }

    /** Enqueues the sync job when anything is waiting. Never throws. */
    @TestVisible
    private static void sweep() {
        try {
            if (GoogleCalendarService.countPendingWork() > 0) {
                GoogleCalendarSyncJob.enqueue();
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Google Calendar sweep failed: ' + ex.getMessage());
        }
    }

    /** Schedules the next one-off run; returns null when scheduling fails. */
    @TestVisible
    private static Id scheduleNextSafely() {
        try {
            return scheduleNext();
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Google Calendar sweep could not reschedule: ' + ex.getMessage());
            return null;
        }
    }

    /** Retires a finished one-off trigger; a missing or already-deleted trigger is harmless. */
    @TestVisible
    private static void abortQuietly(Id cronTriggerId) {
        if (cronTriggerId == null) {
            return;
        }
        try {
            System.abortJob(cronTriggerId);
        } catch (Exception ignored) {
            // already gone
        }
    }

    /** Aborts any existing sweep and schedules a new one. */
    public static Id start() {
        stop();
        return scheduleNext();
    }

    public static void stop() {
        for (CronTrigger ct : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :(JOB_NAME_PREFIX + '%')
        ]) {
            try {
                System.abortJob(ct.Id);
            } catch (Exception ignored) {
                // already gone
            }
        }
    }

    @TestVisible
    private static Id scheduleNext() {
        Integer minutes = GoogleCalendarSettings.load().sweepIntervalMinutes;
        Datetime nextRun = System.now().addMinutes(minutes);
        String cron = nextRun.second() + ' ' + nextRun.minute() + ' ' + nextRun.hour() + ' '
            + nextRun.day() + ' ' + nextRun.month() + ' ? ' + nextRun.year();
        return System.schedule(JOB_NAME_PREFIX + ' ' + nextRun.getTime(), cron, new GoogleCalendarSyncScheduler());
    }
}