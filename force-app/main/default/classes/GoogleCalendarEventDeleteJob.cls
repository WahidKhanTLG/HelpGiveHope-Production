/**
 * Deletes Google events whose Interview_Day_Schedule__c record was deleted (slot count reduced,
 * interview day removed). The targets travel in memory: no queue object. A transient Google failure
 * re-queues the remaining targets with a short delay; a hard failure is logged and the event stays
 * on the calendar (the sync job never recreates it, so at worst an orphan "Available" event remains).
 */
public without sharing class GoogleCalendarEventDeleteJob implements Queueable, Database.AllowsCallouts {

    private static final Integer CALLOUT_BUDGET = 90;
    private static final Long TIME_BUDGET_MS = 75000;
    private static final Integer RETRY_DELAY_MINUTES = 5;

    @TestVisible private static Boolean allowInTests = false;

    public class Target {
        public String calendarId;
        public String eventId;
        public String sourceName;
        public Target(String calendarId, String eventId, String sourceName) {
            this.calendarId = calendarId;
            this.eventId = eventId;
            this.sourceName = sourceName;
        }
    }

    private List<Target> targets;

    public GoogleCalendarEventDeleteJob(List<Target> targets) {
        this.targets = targets == null ? new List<Target>() : targets;
    }

    public static Id enqueue(List<Target> targets) {
        if (targets == null || targets.isEmpty()) {
            return null;
        }
        if (Test.isRunningTest() && !allowInTests) {
            return null;
        }
        if (UserInfo.getUserType() == 'Guest') {
            System.debug(LoggingLevel.WARN, 'Guest user deleted mirrored slots; Google events must be removed manually.');
            return null;
        }
        if (!GoogleCalendarSettings.load().enabled) {
            return null;
        }
        try {
            return System.enqueueJob(new GoogleCalendarEventDeleteJob(targets));
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'GoogleCalendarEventDeleteJob could not be enqueued: ' + ex.getMessage());
            return null;
        }
    }

    public void execute(QueueableContext context) {
        GoogleCalendarSettings settings = GoogleCalendarSettings.load();
        List<Target> remaining = new List<Target>();
        Integer callouts = 0;
        Boolean transientFailure = false;
        Long startedAt = System.currentTimeMillis();

        for (Target target : targets) {
            if (transientFailure || callouts >= CALLOUT_BUDGET || System.currentTimeMillis() - startedAt > TIME_BUDGET_MS) {
                remaining.add(target);
                continue;
            }
            String calendarId = String.isNotBlank(target.calendarId) ? target.calendarId : settings.calendarId;
            GoogleCalendarService.DeleteOutcome outcome =
                GoogleCalendarService.deleteEventById(calendarId, target.eventId, settings);
            callouts += outcome.calloutsUsed;
            if (outcome.transientFailure) {
                transientFailure = true;
                remaining.add(target);
            } else if (!outcome.success) {
                System.debug(LoggingLevel.ERROR, 'Google event ' + target.eventId + ' (' + target.sourceName
                    + ') could not be deleted: ' + outcome.message);
            }
        }

        if (!remaining.isEmpty() && !Test.isRunningTest()) {
            try {
                System.enqueueJob(new GoogleCalendarEventDeleteJob(remaining), transientFailure ? RETRY_DELAY_MINUTES : 0);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'GoogleCalendarEventDeleteJob could not chain: ' + ex.getMessage());
            }
        }
    }
}