/**
 * Aura/LWC-facing controller for staff interview-slot lookup and booking.
 * All booking logic lives in InterviewBookingService; this class only adapts it to the UI and
 * respects the running user's sharing.
 */
public with sharing class SelectInterviewSlotController {

    /**
     * Interview days that still have bookable slots for the Account's zone.
     * @param accountId Account Id or Case Id.
     */
    @AuraEnabled(cacheable=false)
    public static List<Interview_Day__c> getInterviewDays(Id accountId) {
        Id resolvedAccountId = InterviewBookingService.resolveAccountId(accountId);
        if (resolvedAccountId == null) {
            return new List<Interview_Day__c>();
        }
        InterviewBookingService.ZoneResolution zone = InterviewBookingService.resolveZoneForAccount(resolvedAccountId);
        return InterviewBookingService.queryBookableDays(zone, InterviewBookingService.Actor.STAFF, 0);
    }

    /** Backward-compatible booking entry point used from Account context (no volunteer). */
    @AuraEnabled
    public static void updateInterviewSchedule(Id scheduleId, Id accountId) {
        try {
            InterviewBookingService.BookingResult result =
                InterviewBookingService.book(scheduleId, accountId, null, InterviewBookingService.Actor.STAFF);
            autoSendSchedulingLink(result.caseId);
        } catch (InterviewBookingService.BookingException ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /** Books a slot and assigns the volunteer in the same save (Case context only). */
    @AuraEnabled
    public static void bookAndAssignInterview(Id scheduleId, Id accountId, Id volunteerId) {
        if (volunteerId == null) {
            throw new AuraHandledException('Please select a volunteer before booking the interview.');
        }
        if (accountId == null || accountId.getSObjectType() != Case.SObjectType) {
            throw new AuraHandledException('Open the booking from a Case to book and assign a volunteer.');
        }
        try {
            InterviewBookingService.BookingResult result =
                InterviewBookingService.book(scheduleId, accountId, volunteerId, InterviewBookingService.Actor.STAFF);
            autoSendSchedulingLink(result.caseId);
        } catch (InterviewBookingService.BookingException ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * Emails the applicant their personal scheduling link right after a staff booking made from a Case.
     * Never fails the booking: if the contact has no email or the site URL is not configured, the Case's
     * Self_Service_Link_Sent_On__c stays empty and staff can use the Send Scheduling Link action later.
     */
    private static void autoSendSchedulingLink(Id caseId) {
        if (caseId == null || !InterviewSelfServiceConfig.load().autoSendLinkOnBooking) {
            return;
        }
        try {
            InterviewSelfServiceService.GeneratedLink link = InterviewSelfServiceService.generateAndStore(caseId);
            InterviewSelfServiceService.sendEmailForLink(caseId, link);
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Scheduling link was not sent for Case ' + caseId + ': ' + ex.getMessage());
        }
    }

    /** Removes the current Case/Account interview booking; the slot becomes available again. */
    @AuraEnabled
    public static void unscheduleInterview(Id accountId) {
        try {
            InterviewBookingService.release(accountId);
        } catch (InterviewBookingService.BookingException ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /** Current booking and volunteer assignment for the quick action. */
    @AuraEnabled(cacheable=true)
    public static BookingInfo getCurrentBooking(Id accountId) {
        if (accountId == null) {
            return null;
        }

        Id scheduleId;
        Id contextCaseId;

        if (accountId.getSObjectType() == Case.SObjectType) {
            contextCaseId = accountId;
            List<Case> cases = [
                SELECT Id, Interview_Day_Schedule__c
                FROM Case
                WHERE Id = :contextCaseId
                WITH USER_MODE
                LIMIT 1
            ];
            if (cases.isEmpty()) {
                return null;
            }
            scheduleId = cases[0].Interview_Day_Schedule__c;
            if (scheduleId == null) {
                List<Interview_Day_Schedule__c> legacy = [
                    SELECT Id
                    FROM Interview_Day_Schedule__c
                    WHERE Case__c = :contextCaseId AND Booked__c = true
                    WITH USER_MODE
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                scheduleId = legacy.isEmpty() ? null : legacy[0].Id;
            }
        } else {
            Id resolvedAccountId = InterviewBookingService.resolveAccountId(accountId);
            if (resolvedAccountId == null) {
                return null;
            }
            List<Account> accounts = [
                SELECT Id, Interview_Day_Schedule__c
                FROM Account
                WHERE Id = :resolvedAccountId
                WITH USER_MODE
                LIMIT 1
            ];
            scheduleId = accounts.isEmpty() ? null : accounts[0].Interview_Day_Schedule__c;
        }

        if (scheduleId == null) {
            return null;
        }

        List<Interview_Day_Schedule__c> schedules = [
            SELECT Id, Booked__c, Case__c, Assigned_Volunteer__c, Assigned_Volunteer__r.Name, Assignment_Status__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :scheduleId
            WITH USER_MODE
            LIMIT 1
        ];
        if (schedules.isEmpty() || schedules[0].Booked__c != true) {
            return null;
        }
        Interview_Day_Schedule__c schedule = schedules[0];
        if (contextCaseId != null && schedule.Case__c != contextCaseId) {
            return null;
        }

        BookingInfo info = new BookingInfo();
        info.scheduleId = schedule.Id;
        info.caseId = schedule.Case__c;
        info.volunteerId = schedule.Assigned_Volunteer__c;
        info.volunteerName = schedule.Assigned_Volunteer__r == null ? null : schedule.Assigned_Volunteer__r.Name;
        info.assignmentStatus = schedule.Assignment_Status__c;
        return info;
    }

    /** Assigns or reassigns the volunteer on an already-booked interview. */
    @AuraEnabled
    public static void assignVolunteerToBookedInterview(Id accountId, Id volunteerId) {
        if (volunteerId == null || volunteerId.getSObjectType() != User.SObjectType) {
            throw new AuraHandledException('Please select a valid Salesforce User as the volunteer.');
        }
        if ([SELECT COUNT() FROM User WHERE Id = :volunteerId AND IsActive = true] == 0) {
            throw new AuraHandledException('The selected volunteer is not an active Salesforce User.');
        }
        Id contextCaseId = accountId != null && accountId.getSObjectType() == Case.SObjectType ? accountId : null;
        Id scheduleId;

        if (contextCaseId != null) {
            List<Case> cases = [
                SELECT Id, Interview_Day_Schedule__c
                FROM Case
                WHERE Id = :contextCaseId
                WITH USER_MODE
                LIMIT 1
            ];
            if (!cases.isEmpty()) {
                scheduleId = cases[0].Interview_Day_Schedule__c;
            }
            if (scheduleId == null) {
                List<Interview_Day_Schedule__c> legacy = [
                    SELECT Id
                    FROM Interview_Day_Schedule__c
                    WHERE Case__c = :contextCaseId AND Booked__c = true
                    WITH USER_MODE
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                scheduleId = legacy.isEmpty() ? null : legacy[0].Id;
            }
        } else {
            Id resolvedAccountId = InterviewBookingService.resolveAccountId(accountId);
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
            scheduleId = accounts.isEmpty() ? null : accounts[0].Interview_Day_Schedule__c;
        }

        if (scheduleId == null) {
            throw new AuraHandledException('No booked interview was found to assign.');
        }

        List<Interview_Day_Schedule__c> schedules = [
            SELECT Id, Booked__c, Case__c, Assigned_Volunteer__c
            FROM Interview_Day_Schedule__c
            WHERE Id = :scheduleId
            WITH USER_MODE
            LIMIT 1
        ];
        if (schedules.isEmpty() || schedules[0].Booked__c != true) {
            throw new AuraHandledException('The current interview schedule is not booked.');
        }
        Interview_Day_Schedule__c currentSchedule = schedules[0];
        if (contextCaseId != null && currentSchedule.Case__c != null && currentSchedule.Case__c != contextCaseId) {
            throw new AuraHandledException('This booked schedule is linked to a different Case.');
        }
        Id effectiveCaseId = currentSchedule.Case__c != null ? currentSchedule.Case__c : contextCaseId;
        if (effectiveCaseId == null) {
            throw new AuraHandledException('Open the booking from a Case before assigning a volunteer.');
        }
        Database.update(new Interview_Day_Schedule__c(
            Id = currentSchedule.Id,
            Case__c = effectiveCaseId,
            Assigned_Volunteer__c = volunteerId,
            Google_Sync_Status__c = GoogleCalendarService.STATUS_PENDING
        ), AccessLevel.USER_MODE);
    }

    public class BookingInfo {
        @AuraEnabled public Id scheduleId { get; set; }
        @AuraEnabled public Id caseId { get; set; }
        @AuraEnabled public Id volunteerId { get; set; }
        @AuraEnabled public String volunteerName { get; set; }
        @AuraEnabled public String assignmentStatus { get; set; }
    }
}