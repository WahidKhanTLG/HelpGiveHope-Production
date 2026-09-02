/**
 * Thin trigger handler for Case scoring automation.
 */
public with sharing class CaseScoringTriggerHandler {

    /**
     * Executes scoring in before insert/update contexts.
     */
    public static void run() {
        if (!(Trigger.isInsert || Trigger.isUpdate)) {
            return;
        }

        List<Case> newCases = (List<Case>)Trigger.new;
        Map<Id, Case> oldCases = Trigger.isInsert ? null : (Map<Id, Case>)Trigger.oldMap;
        CaseScoringService.applyScores(newCases, oldCases);
    }
}