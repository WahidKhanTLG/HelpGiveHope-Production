trigger CaseScoringTrigger on Case (before insert, before update) {
    CaseScoringTriggerHandler.run();
}