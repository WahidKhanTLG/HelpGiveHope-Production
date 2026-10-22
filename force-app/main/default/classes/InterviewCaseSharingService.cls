/**
 * Manages Case access and Case ownership for volunteers assigned to
 * Interview_Day_Schedule__c records.
 *
 * Runs without sharing because it is invoked by
 * HGH_Interview_Volunteer_Assignment for users who may not already
 * have access to the related Case.
 *
 * Existing behavior is preserved:
 * - GRANT stores the original Case owner on the schedule.
 * - GRANT transfers Case ownership to the assigned volunteer.
 * - REMOVE deletes assignment-created manual Case access.
 * - REMOVE restores the original Case owner when appropriate.
 * - REMOVE clears Original_Case_Owner_Id__c so the slot can be reused.
 *
 * The invocable entry point is bulk-safe for bulk volunteer
 * reassignment.
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

        List<SharingRequest> validRequests =
            new List<SharingRequest>();

        Set<Id> caseIds =
            new Set<Id>();

        Set<Id> userIds =
            new Set<Id>();

        Set<Id> scheduleIds =
            new Set<Id>();

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

            if (
                operation != 'GRANT' &&
                operation != 'REMOVE'
            ) {
                continue;
            }

            request.operation = operation;

            validRequests.add(request);

            caseIds.add(request.caseId);
            userIds.add(request.userId);

            if (request.scheduleId != null) {
                scheduleIds.add(request.scheduleId);
            }
        }

        if (validRequests.isEmpty()) {
            return;
        }

        Map<Id, Case> casesById =
            new Map<Id, Case>();

        if (!caseIds.isEmpty()) {

            casesById = new Map<Id, Case>([
                SELECT Id,
                       OwnerId
                FROM Case
                WHERE Id IN :caseIds
                FOR UPDATE
            ]);
        }

        Map<Id, Interview_Day_Schedule__c> schedulesById =
            new Map<Id, Interview_Day_Schedule__c>();

        if (!scheduleIds.isEmpty()) {

            schedulesById =
                new Map<Id, Interview_Day_Schedule__c>([
                    SELECT Id,
                           Original_Case_Owner_Id__c
                    FROM Interview_Day_Schedule__c
                    WHERE Id IN :scheduleIds
                    FOR UPDATE
                ]);
        }

        List<SharingRequest> removeRequests =
            new List<SharingRequest>();

        List<SharingRequest> grantRequests =
            new List<SharingRequest>();

        List<SharingRequest> legacyRequests =
            new List<SharingRequest>();

        for (SharingRequest request : validRequests) {

            Case caseRecord =
                casesById.get(request.caseId);

            Interview_Day_Schedule__c schedule =
                request.scheduleId == null
                    ? null
                    : schedulesById.get(request.scheduleId);

            /*
             * Preserve the old fallback behavior when scheduleId
             * isn't available or the schedule no longer exists.
             */
            if (
                request.scheduleId == null ||
                schedule == null ||
                caseRecord == null
            ) {

                legacyRequests.add(request);
                continue;
            }

            if (request.operation == 'REMOVE') {
                removeRequests.add(request);
            } else {
                grantRequests.add(request);
            }
        }

        /*
         * Process REMOVE before GRANT.
         *
         * This is important for bulk reassignment:
         *
         * Volunteer A
         *   -> REMOVE
         *   -> restore original Case owner
         *   -> clear remembered owner
         *
         * Volunteer B
         *   -> GRANT
         *   -> capture original owner again
         *   -> assign Volunteer B
         */
        processBulkRemovals(
            removeRequests,
            casesById,
            schedulesById
        );

        processBulkGrants(
            grantRequests,
            casesById,
            schedulesById
        );

        /*
         * Legacy fallback.
         *
         * Existing callers that don't provide scheduleId continue
         * to use the previous manual CaseShare behavior.
         *
         * The new Bulk Volunteer Reassignment always supplies
         * scheduleId, so the bulk path above handles the 10-20
         * interview use case without SOQL/DML inside the loop.
         */
        for (SharingRequest request : legacyRequests) {

            if (request.operation == 'GRANT') {

                grantAccess(
                    request.caseId,
                    request.userId
                );

            } else if (request.operation == 'REMOVE') {

                removeAccess(
                    request.caseId,
                    request.userId
                );
            }
        }
    }

    private static void processBulkRemovals(
        List<SharingRequest> requests,
        Map<Id, Case> casesById,
        Map<Id, Interview_Day_Schedule__c> schedulesById
    ) {

        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> caseIds =
            new Set<Id>();

        Set<Id> userIds =
            new Set<Id>();

        for (SharingRequest request : requests) {

            caseIds.add(request.caseId);
            userIds.add(request.userId);
        }

        Map<String, CaseShare> manualSharesByPair =
            new Map<String, CaseShare>();

        if (
            !caseIds.isEmpty() &&
            !userIds.isEmpty()
        ) {

            for (CaseShare shareRow : [
                SELECT Id,
                       CaseId,
                       UserOrGroupId,
                       CaseAccessLevel,
                       RowCause
                FROM CaseShare
                WHERE CaseId IN :caseIds
                  AND UserOrGroupId IN :userIds
                  AND RowCause = 'Manual'
            ]) {

                manualSharesByPair.put(
                    pairKey(
                        shareRow.CaseId,
                        shareRow.UserOrGroupId
                    ),
                    shareRow
                );
            }
        }

        List<CaseShare> sharesToDelete =
            new List<CaseShare>();

        Map<Id, Case> casesToRestore =
            new Map<Id, Case>();

        Map<Id, Interview_Day_Schedule__c> schedulesToClear =
            new Map<Id, Interview_Day_Schedule__c>();

        for (SharingRequest request : requests) {

            String key =
                pairKey(
                    request.caseId,
                    request.userId
                );

            if (manualSharesByPair.containsKey(key)) {

                sharesToDelete.add(
                    manualSharesByPair.get(key)
                );

                manualSharesByPair.remove(key);
            }

            Case caseRecord =
                casesById.get(request.caseId);

            Interview_Day_Schedule__c schedule =
                schedulesById.get(request.scheduleId);

            if (
                caseRecord == null ||
                schedule == null ||
                String.isBlank(
                    schedule.Original_Case_Owner_Id__c
                )
            ) {
                continue;
            }

            /*
             * Preserve existing behavior:
             *
             * Only restore Case Owner when the Case is still owned
             * by the volunteer being removed.
             */
            if (caseRecord.OwnerId == request.userId) {

                caseRecord.OwnerId =
                    (Id) schedule.Original_Case_Owner_Id__c;

                casesToRestore.put(
                    caseRecord.Id,
                    caseRecord
                );
            }

            /*
             * Preserve existing behavior:
             * release the remembered owner when the volunteer
             * assignment is removed.
             */
            schedulesToClear.put(
                schedule.Id,
                schedule
            );
        }

        if (!sharesToDelete.isEmpty()) {

            Database.DeleteResult[] deleteResults =
                Database.delete(
                    sharesToDelete,
                    false,
                    AccessLevel.SYSTEM_MODE
                );

            logDeleteResults(
                'Manual CaseShare was not deleted',
                deleteResults
            );
        }

        /*
         * Restore the owner BEFORE clearing the saved owner.
         * This preserves the safety of the previous implementation.
         */
        if (!casesToRestore.isEmpty()) {

            Database.update(
                casesToRestore.values(),
                true,
                AccessLevel.SYSTEM_MODE
            );
        }

        if (!schedulesToClear.isEmpty()) {

            for (
                Interview_Day_Schedule__c schedule :
                schedulesToClear.values()
            ) {

                schedule.Original_Case_Owner_Id__c =
                    null;
            }

            Database.update(
                schedulesToClear.values(),
                true,
                AccessLevel.SYSTEM_MODE
            );
        }
    }

    private static void processBulkGrants(
        List<SharingRequest> requests,
        Map<Id, Case> casesById,
        Map<Id, Interview_Day_Schedule__c> schedulesById
    ) {

        if (requests == null || requests.isEmpty()) {
            return;
        }

        Map<Id, Interview_Day_Schedule__c> schedulesToUpdate =
            new Map<Id, Interview_Day_Schedule__c>();

        Map<Id, Case> casesToUpdate =
            new Map<Id, Case>();

        for (SharingRequest request : requests) {

            Case caseRecord =
                casesById.get(request.caseId);

            Interview_Day_Schedule__c schedule =
                schedulesById.get(request.scheduleId);

            if (
                caseRecord == null ||
                schedule == null
            ) {
                continue;
            }

            /*
             * Preserve existing owner before assigning volunteer.
             *
             * Never overwrite the original owner if it has already
             * been captured.
             */
            if (
                String.isBlank(
                    schedule.Original_Case_Owner_Id__c
                )
            ) {

                schedule.Original_Case_Owner_Id__c =
                    String.valueOf(caseRecord.OwnerId);

                schedulesToUpdate.put(
                    schedule.Id,
                    schedule
                );
            }

            /*
             * Preserve existing behavior:
             * assigned volunteer becomes Case Owner.
             */
            if (caseRecord.OwnerId != request.userId) {

                caseRecord.OwnerId =
                    request.userId;

                casesToUpdate.put(
                    caseRecord.Id,
                    caseRecord
                );
            }
        }

        /*
         * Save original owner BEFORE changing Case ownership.
         */
        if (!schedulesToUpdate.isEmpty()) {

            Database.update(
                schedulesToUpdate.values(),
                true,
                AccessLevel.SYSTEM_MODE
            );
        }

        if (!casesToUpdate.isEmpty()) {

            Database.update(
                casesToUpdate.values(),
                true,
                AccessLevel.SYSTEM_MODE
            );
        }

        /*
         * No manual CaseShare is required for the normal
         * schedule-backed GRANT path because the volunteer now owns
         * the Case and therefore already has edit access.
         *
         * This matches the previous grantAccess behavior, which
         * immediately returned after hasEditAccess() became true.
         */
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

        if (
            schedules.isEmpty() ||
            cases.isEmpty()
        ) {
            return;
        }

        Interview_Day_Schedule__c schedule =
            schedules[0];

        Case caseRecord =
            cases[0];

        if (
            String.isBlank(
                schedule.Original_Case_Owner_Id__c
            )
        ) {

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

        if (
            schedules.isEmpty() ||
            String.isBlank(
                schedules[0].Original_Case_Owner_Id__c
            )
        ) {
            return;
        }

        Interview_Day_Schedule__c schedule =
            schedules[0];

        List<Case> cases = [
            SELECT Id,
                   OwnerId
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        if (
            !cases.isEmpty() &&
            cases[0].OwnerId == userId
        ) {

            Case caseRecord =
                cases[0];

            caseRecord.OwnerId =
                (Id) schedule.Original_Case_Owner_Id__c;

            Database.update(
                caseRecord,
                AccessLevel.SYSTEM_MODE
            );
        }

        /*
         * The slot is being released.
         * Clear the remembered owner so a later booking of this
         * slot captures the correct original owner.
         */
        schedule.Original_Case_Owner_Id__c =
            null;

        Database.update(
            schedule,
            AccessLevel.SYSTEM_MODE
        );
    }

    public static void grantAccess(
        Id caseId,
        Id userId
    ) {

        if (
            caseId == null ||
            userId == null
        ) {
            return;
        }

        if (
            hasEditAccess(
                caseId,
                userId
            )
        ) {
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

            if (
                existingShare.CaseAccessLevel !=
                'Edit'
            ) {

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

        CaseShare shareRow =
            new CaseShare(
                CaseId = caseId,
                UserOrGroupId = userId,
                CaseAccessLevel = 'Edit',
                RowCause =
                    Schema.CaseShare.RowCause.Manual
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

        if (
            caseId == null ||
            userId == null
        ) {
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

        for (
            Database.DeleteResult deleteResult :
            deleteResults
        ) {

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

        return
            !accessRows.isEmpty() &&
            accessRows[0].HasEditAccess;
    }

    private static String pairKey(
        Id caseId,
        Id userId
    ) {

        return
            String.valueOf(caseId) +
            '|' +
            String.valueOf(userId);
    }

    private static void logDeleteResults(
        String messagePrefix,
        Database.DeleteResult[] results
    ) {

        if (results == null) {
            return;
        }

        for (
            Database.DeleteResult result :
            results
        ) {

            if (!result.isSuccess()) {

                logShareError(
                    messagePrefix,
                    result.getErrors()
                );
            }
        }
    }

    private static void logShareError(
        String messagePrefix,
        Database.Error[] errors
    ) {

        if (
            errors == null ||
            errors.isEmpty()
        ) {

            System.debug(
                LoggingLevel.WARN,
                messagePrefix
            );

            return;
        }

        System.debug(
            LoggingLevel.WARN,
            messagePrefix +
            '. Reason: ' +
            errors[0].getMessage()
        );
    }
}