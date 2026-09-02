/**
 * Aura-facing controller for interview-slot lookup and booking.
 */
public with sharing class SelectInterviewSlotController {
    private static final Set<String> BOOKABLE_DAY_STATUSES = new Set<String>{ 'Planned', 'Published' };
    private static final String ZONE_CODE_OBJECT = 'HGH_Zone_Code__c';
    private static final String ACCOUNT_ZONE_FIELD = 'Zones__c';

    /**
     * Returns interview days that still have bookable schedules for the Account's zone.
     *
     * @param accountId Account Id or Case Id received from the UI.
     * @return Interview day records with at least one unbooked schedule.
     */
    @AuraEnabled(cacheable=false)
    public static List<Interview_Day__c> getInterviewDays(Id accountId) {
        Id resolvedAccountId = resolveAccountId(accountId);
        Account accountRecord = fetchAccount(resolvedAccountId);
        if (accountRecord == null || accountRecord.Census_Tract__c == null) {
            return new List<Interview_Day__c>();
        }

        List<Interview_Day__c> interviewDays = queryInterviewDaysForCensusTract(
            String.valueOf(accountRecord.Census_Tract__c)
        );
        return filterAvailableDays(interviewDays);
    }

    /**
     * Books the selected interview slot and writes the selected schedule back to the Account.
     *
     * @param scheduleId Interview_Day_Schedule__c Id selected by the user.
     * @param accountId Account Id or Case Id passed from the quick action.
     */
    @AuraEnabled
    public static void updateInterviewSchedule(Id scheduleId, Id accountId) {
        if (scheduleId == null) {
            throw new AuraHandledException('Interview schedule Id is required.');
        }

        Id resolvedAccountId = resolveAccountId(accountId);
        if (resolvedAccountId == null) {
            throw new AuraHandledException('Unable to resolve an Account for the selected booking.');
        }

        Id caseId = accountId?.getSObjectType() == Case.SObjectType
            ? accountId
            : null;

        Savepoint bookingSavepoint = Database.setSavepoint();

        try {
            Interview_Day_Schedule__c lockedSchedule = lockScheduleForBooking(scheduleId);
            if (lockedSchedule.Booked__c == true) {
                throw new AuraHandledException(
                    'This interview slot has already been booked. Please refresh and choose another slot.'
                );
            }

            Id zoneId = resolveZoneIdForBooking(lockedSchedule, resolvedAccountId);

            Database.update(
                new Interview_Day_Schedule__c(
                    Id = lockedSchedule.Id,
                    Booked__c = true,
                    Case__c = caseId
                ),
                AccessLevel.USER_MODE
            );

            updateAccountBooking(resolvedAccountId, lockedSchedule.Id, zoneId);
        } catch (AuraHandledException ex) {
            Database.rollback(bookingSavepoint);
            throw ex;
        } catch (Exception ex) {
            Database.rollback(bookingSavepoint);
            throw new AuraHandledException('Error booking schedule: ' + ex.getMessage());
        }
    }

    @AuraEnabled
    public static void unscheduleInterview(Id accountId) {
        Id resolvedAccountId = resolveAccountId(accountId);
        if (resolvedAccountId == null) {
            throw new AuraHandledException('Unable to resolve an Account for the selected booking.');
        }

        List<Account> accounts = [
            SELECT Id, Interview_Day_Schedule__c
            FROM Account
            WHERE Id = :resolvedAccountId
            WITH USER_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new AuraHandledException('Account not found for the selected booking.');
        }

        Account acc = accounts[0];
        if (acc.Interview_Day_Schedule__c == null) {
            throw new AuraHandledException('No existing booking found to unschedule.');
        }

        Savepoint unscheduleSavepoint = Database.setSavepoint();
        try {
            Database.update(
                new Interview_Day_Schedule__c(
                    Id = acc.Interview_Day_Schedule__c,
                    Case__c = null,
                    Booked__c = false
                ),
                AccessLevel.USER_MODE
            );

            Database.update(
                new Account(
                    Id = acc.Id,
                    Interview_Day_Schedule__c = null
                ),
                AccessLevel.USER_MODE
            );
        } catch (Exception ex) {
            Database.rollback(unscheduleSavepoint);
            throw new AuraHandledException('Error unscheduling interview: ' + ex.getMessage());
        }
    }

    private static List<Interview_Day__c> queryInterviewDaysForCensusTract(String codeStr) {
        Id zoneId = tryResolveZoneIdByCode(codeStr);
        if (zoneId != null) {
            return queryInterviewDaysByZone(zoneId);
        }

        Decimal numericCode = parseZoneCode(codeStr);
        return numericCode == null
            ? new List<Interview_Day__c>()
            : queryInterviewDaysByZoneCode(numericCode);
    }

    private static List<Interview_Day__c> queryInterviewDaysByZone(Id zoneId) {
        Date today = Date.today();
        return [
            SELECT Id, Interview_Date__c, Schedule_Mode__c,
                (SELECT Id, Name FROM Interview_Day_Schedules__r WHERE Booked__c = FALSE)
            FROM Interview_Day__c
            WHERE Zone__c = :zoneId
                AND Interview_Date__c >= :today
                AND Status__c IN :BOOKABLE_DAY_STATUSES
            WITH USER_MODE
            ORDER BY Interview_Date__c ASC
        ];
    }

    private static List<Interview_Day__c> queryInterviewDaysByZoneCode(Decimal numericCode) {
        Date today = Date.today();
        return [
            SELECT Id, Interview_Date__c, Schedule_Mode__c,
                (SELECT Id, Name FROM Interview_Day_Schedules__r WHERE Booked__c = FALSE)
            FROM Interview_Day__c
            WHERE Zone_Code__c = :numericCode
                AND Interview_Date__c >= :today
                AND Status__c IN :BOOKABLE_DAY_STATUSES
            WITH USER_MODE
            ORDER BY Interview_Date__c ASC
        ];
    }

    private static List<Interview_Day__c> filterAvailableDays(List<Interview_Day__c> days) {
        List<Interview_Day__c> filtered = new List<Interview_Day__c>();
        for (Interview_Day__c interviewDay : days) {
            if (interviewDay.Interview_Day_Schedules__r != null && !interviewDay.Interview_Day_Schedules__r.isEmpty()) {
                filtered.add(interviewDay);
            }
        }
        return filtered;
    }

    private static Id resolveAccountId(Id recordId) {
        if (recordId == null) {
            return null;
        }

        if (recordId.getSObjectType() != Case.SObjectType) {
            return recordId;
        }

        List<Case> cases = [
            SELECT AccountId
            FROM Case
            WHERE Id = :recordId
            WITH USER_MODE
            LIMIT 1
        ];
        return cases.isEmpty() ? null : cases[0].AccountId;
    }

    private static Account fetchAccount(Id accountId) {
        if (accountId == null) {
            return null;
        }

        List<Account> accounts = [
            SELECT Id, Census_Tract__c
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }

    private static Id tryResolveZoneIdByCode(String codeStr) {
        if (String.isBlank(codeStr) || !Schema.getGlobalDescribe().containsKey(ZONE_CODE_OBJECT)) {
            return null;
        }

        try {
            List<SObject> rows = Database.query(
                'SELECT Zone__c FROM HGH_Zone_Code__c ' +
                'WHERE Active__c = true AND Code__c = :codeStr ' +
                'WITH USER_MODE LIMIT 1'
            );
            return rows.isEmpty() ? null : (Id) rows[0].get('Zone__c');
        } catch (Exception ex) {
            touchSuppressedException('Zone lookup by code failed', ex);
            return null;
        }
    }

    private static Decimal parseZoneCode(String codeStr) {
        try {
            return Decimal.valueOf(codeStr);
        } catch (Exception ex) {
            touchSuppressedException('Zone code parsing failed', ex);
            return null;
        }
    }

    private static Boolean hasAccountZoneField() {
        return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap().containsKey(ACCOUNT_ZONE_FIELD);
    }

    private static void applyZoneLookup(Account accountUpdate, Id zoneId) {
        if (zoneId != null && hasAccountZoneField()) {
            accountUpdate.put(ACCOUNT_ZONE_FIELD, zoneId);
        }
    }

    private static Interview_Day_Schedule__c lockScheduleForBooking(Id scheduleId) {
        List<Interview_Day_Schedule__c> schedules = [
            SELECT Id, Booked__c, Interview_Day__r.Zone__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :scheduleId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        if (schedules.isEmpty()) {
            throw new AuraHandledException('Selected interview slot was not found.');
        }

        return schedules[0];
    }

    private static Id resolveZoneIdForBooking(Interview_Day_Schedule__c lockedSchedule, Id accountId) {
        try {
            if (
                lockedSchedule != null &&
                lockedSchedule.Interview_Day__r != null &&
                lockedSchedule.Interview_Day__r.Zone__c != null
            ) {
                return lockedSchedule.Interview_Day__r.Zone__c;
            }

            return resolveZoneIdFromAccount(accountId);
        } catch (Exception ex) {
            touchSuppressedException('Zone resolution for booking failed', ex);
            return null;
        }
    }

    private static Id resolveZoneIdFromAccount(Id accountId) {
        Account accountRecord = fetchAccount(accountId);
        if (accountRecord == null || accountRecord.Census_Tract__c == null) {
            return null;
        }

        return tryResolveZoneIdByCode(String.valueOf(accountRecord.Census_Tract__c));
    }

    private static void updateAccountBooking(Id accountId, Id scheduleId, Id zoneId) {
        if (accountId == null) {
            return;
        }

        Account accountUpdate = new Account(Id = accountId);
        accountUpdate.Interview_Day_Schedule__c = scheduleId;
        applyZoneLookup(accountUpdate, zoneId);
        Database.update(accountUpdate, AccessLevel.USER_MODE);
    }

    private static void touchSuppressedException(String context, Exception ex) {
        String.valueOf(context);
        ex.getMessage();
    }
}