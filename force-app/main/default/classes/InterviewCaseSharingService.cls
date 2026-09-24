/**
 * Manages Case access for volunteers assigned to
 * Interview_Day_Schedule__c records.
 *
 * Runs without sharing: it is invoked by the HGH_Interview_Volunteer_Assignment flow for whoever
 * saved the slot - including the Experience Cloud guest user during applicant self-service, who
 * cannot see the Case. All writes are already in system mode.
 */
public without sharing class InterviewCaseSharingService {

    public class SharingRequest {

        @InvocableVariable(required=true)
        public Id caseId;

        @InvocableVariable(required=true)
        public Id userId;

        @InvocableVariable(required=true)
        public String operation;

        @InvocableVariable
        public Id scheduleId;
    }

    @InvocableMethod(
        label='Manage Interview Case Access'
        description='Grants or removes Case access for an assigned interview volunteer.'
    )
    public static void manageAccess(
        List<SharingRequest> requests
    ) {

        if (requests == null || requests.isEmpty()) {
            return;
        }

        for (SharingRequest request : requests) {

            if (
                request == null ||
                request.caseId == null ||
                request.userId == null ||
                String.isBlank(request.operation)
            ) {
                continue;
            }

            String operation =
                request.operation.trim().toUpperCase();

            if (operation == 'GRANT') {

                assignCaseOwner(
                    request.caseId,
                    request.userId,
                    request.scheduleId
                );

                grantAccess(
                    request.caseId,
                    request.userId
                );

            } else if (operation == 'REMOVE') {

                removeAccess(
                    request.caseId,
                    request.userId
                );

                restoreCaseOwner(
                    request.caseId,
                    request.userId,
                    request.scheduleId
                );
            }
        }
    }

    public static void assignCaseOwner(
        Id caseId,
        Id userId,
        Id scheduleId
    ) {

        if (
            caseId == null ||
            userId == null ||
            scheduleId == null
        ) {
            return;
        }

        List<Interview_Day_Schedule__c> schedules = [
            SELECT Id,
                   Original_Case_Owner_Id__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :scheduleId
            LIMIT 1
        ];

        List<Case> cases = [
            SELECT Id,
                   OwnerId
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        if (schedules.isEmpty() || cases.isEmpty()) {
            return;
        }

        Interview_Day_Schedule__c schedule = schedules[0];
        Case caseRecord = cases[0];

        if (String.isBlank(schedule.Original_Case_Owner_Id__c)) {

            schedule.Original_Case_Owner_Id__c =
                String.valueOf(caseRecord.OwnerId);

            Database.update(
                schedule,
                AccessLevel.SYSTEM_MODE
            );
        }

        if (caseRecord.OwnerId != userId) {

            caseRecord.OwnerId =
                userId;

            Database.update(
                caseRecord,
                AccessLevel.SYSTEM_MODE
            );
        }
    }

    public static void restoreCaseOwner(
        Id caseId,
        Id userId,
        Id scheduleId
    ) {

        if (
            caseId == null ||
            userId == null ||
            scheduleId == null
        ) {
            return;
        }

        List<Interview_Day_Schedule__c> schedules = [
            SELECT Id,
                   Original_Case_Owner_Id__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :scheduleId
            LIMIT 1
        ];

        if (schedules.isEmpty() || String.isBlank(schedules[0].Original_Case_Owner_Id__c)) {
            return;
        }

        Interview_Day_Schedule__c schedule = schedules[0];

        List<Case> cases = [
            SELECT Id,
                   OwnerId
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        if (!cases.isEmpty() && cases[0].OwnerId == userId) {
            Case caseRecord = cases[0];
            caseRecord.OwnerId =
                (Id) schedule.Original_Case_Owner_Id__c;

            Database.update(
                caseRecord,
                AccessLevel.SYSTEM_MODE
            );
        }

        /*
         * The slot is being released. Clear the remembered owner so a later booking of the same
         * slot (possibly for a different household) captures its own original owner instead of
         * restoring this one.
         */
        schedule.Original_Case_Owner_Id__c = null;
        Database.update(
            schedule,
            AccessLevel.SYSTEM_MODE
        );
    }

    public static void grantAccess(
        Id caseId,
        Id userId
    ) {

        if (caseId == null || userId == null) {
            return;
        }

        if (hasEditAccess(caseId, userId)) {
            return;
        }

        List<CaseShare> existingShares = [
            SELECT Id,
                   CaseId,
                   UserOrGroupId,
                   CaseAccessLevel,
                   RowCause
            FROM CaseShare
            WHERE CaseId = :caseId
              AND UserOrGroupId = :userId
              AND RowCause = 'Manual'
            LIMIT 1
        ];

        if (!existingShares.isEmpty()) {

            CaseShare existingShare =
                existingShares[0];

            if (existingShare.CaseAccessLevel != 'Edit') {

                existingShare.CaseAccessLevel =
                    'Edit';

                Database.SaveResult updateResult =
                    Database.update(
                        new List<CaseShare>{
                            existingShare
                        },
                        false,
                        AccessLevel.SYSTEM_MODE
                    )[0];

                if (!updateResult.isSuccess()) {
                    logShareError(
                        'Manual CaseShare was not updated',
                        updateResult.getErrors()
                    );
                }
            }

            return;
        }

        CaseShare shareRow = new CaseShare(
            CaseId = caseId,
            UserOrGroupId = userId,
            CaseAccessLevel = 'Edit',
            RowCause = Schema.CaseShare.RowCause.Manual
        );

        Database.SaveResult insertResult =
            Database.insert(
                new List<CaseShare>{
                    shareRow
                },
                false,
                AccessLevel.SYSTEM_MODE
            )[0];

        if (!insertResult.isSuccess()) {
            logShareError(
                'Manual CaseShare was not created',
                insertResult.getErrors()
            );
        }
    }

    public static void removeAccess(
        Id caseId,
        Id userId
    ) {

        if (caseId == null || userId == null) {
            return;
        }

        List<CaseShare> sharesToDelete = [
            SELECT Id
            FROM CaseShare
            WHERE CaseId = :caseId
              AND UserOrGroupId = :userId
              AND RowCause = 'Manual'
        ];

        if (sharesToDelete.isEmpty()) {
            return;
        }

        Database.DeleteResult[] deleteResults =
            Database.delete(
                sharesToDelete,
                false,
                AccessLevel.SYSTEM_MODE
            );

        for (Database.DeleteResult deleteResult : deleteResults) {

            if (!deleteResult.isSuccess()) {
                logShareError(
                    'Manual CaseShare was not deleted',
                    deleteResult.getErrors()
                );
            }
        }
    }

    private static Boolean hasEditAccess(
        Id caseId,
        Id userId
    ) {

        List<UserRecordAccess> accessRows = [
            SELECT RecordId,
                   HasReadAccess,
                   HasEditAccess
            FROM UserRecordAccess
            WHERE UserId = :userId
              AND RecordId = :caseId
            LIMIT 1
        ];

        return !accessRows.isEmpty()
            && accessRows[0].HasEditAccess;
    }

    private static void logShareError(
        String messagePrefix,
        Database.Error[] errors
    ) {

        if (errors == null || errors.isEmpty()) {

            System.debug(
                LoggingLevel.WARN,
                messagePrefix
            );

            return;
        }

        System.debug(
            LoggingLevel.WARN,
            messagePrefix + '. Reason: ' + errors[0].getMessage()
        );
    }
}