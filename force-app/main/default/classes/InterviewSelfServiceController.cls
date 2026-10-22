/**
 * Apex behind the applicant self-service page (Experience Cloud, site guest user).
 *
 * Authorization is the scheduling token only: it is hashed and matched against
 * Case.Self_Service_Token_Hash__c, must not be expired, and the feature must be enabled.
 * The response never contains record Ids other than slot Ids the applicant may pick, and the only
 * personal data returned is the applicant's first name.
 *
 * Runs without sharing on purpose (the guest user has no record access); every read and write is
 * limited to the Case/Account behind the token and to slots in that household's zone.
 */
public without sharing class InterviewSelfServiceController {

    public class SlotDTO {
        @AuraEnabled public Id scheduleId;
        @AuraEnabled public String label;
        @AuraEnabled public String startLabel;
        @AuraEnabled public String endLabel;
        @AuraEnabled public Boolean selectable;
        @AuraEnabled public String reason;
    }

    public class DayDTO {
        @AuraEnabled public Id interviewDayId;
        @AuraEnabled public String dateValue;      // yyyy-MM-dd
        @AuraEnabled public String dateLabel;
        @AuraEnabled public String mode;
        @AuraEnabled public String zoneName;
        @AuraEnabled public List<SlotDTO> slots = new List<SlotDTO>();
    }

    public class BookingDTO {
        @AuraEnabled public String status;          // OK | INVALID | EXPIRED | DISABLED | NO_ZONE | ERROR
        @AuraEnabled public String message;
        @AuraEnabled public String firstName;
        @AuraEnabled public Boolean hasBooking = false;
        @AuraEnabled public Id currentScheduleId;
        @AuraEnabled public String currentDateLabel;
        @AuraEnabled public String currentTimeLabel;
        @AuraEnabled public String currentZoneName;
        @AuraEnabled public String currentInterviewer;
        @AuraEnabled public Boolean canChange = false;
        @AuraEnabled public String cannotChangeReason;
        @AuraEnabled public Integer cutoffHours;
        @AuraEnabled public Integer reschedulesRemaining;  // null = unlimited
        @AuraEnabled public String supportPhone;
        @AuraEnabled public List<DayDTO> days = new List<DayDTO>();
    }

    private class TokenContext {
        Case application;
        InterviewSelfServiceConfig cfg;
        BookingDTO failure;
    }

    @AuraEnabled(cacheable=false)
    public static BookingDTO getBooking(String token) {
        TokenContext ctx = resolve(token);
        if (ctx.failure != null) {
            return ctx.failure;
        }
        return buildBooking(ctx);
    }

    /**
     * Books (no current booking) or reschedules (existing booking) the applicant's interview.
     */
    @AuraEnabled
    public static BookingDTO selectSlot(String token, Id scheduleId) {
        TokenContext ctx = resolve(token);
        if (ctx.failure != null) {
            return ctx.failure;
        }
        if (scheduleId == null || scheduleId.getSObjectType() != Interview_Day_Schedule__c.SObjectType) {
            return fail('ERROR', 'Please choose an interview slot.', ctx);
        }

        Case application = ctx.application;
        Boolean hasBooking = currentSchedule(application) != null;

        if (hasBooking && ctx.cfg.maxReschedules > 0) {
            Integer used = application.Reschedule_Count__c == null ? 0 : application.Reschedule_Count__c.intValue();
            if (used >= ctx.cfg.maxReschedules) {
                return fail('ERROR', 'You have reached the maximum number of online changes. Please call Help Give Hope.', ctx);
            }
        }

        try {
            InterviewBookingService.BookingResult result = InterviewBookingService.reschedule(
                application.Id, scheduleId, InterviewBookingService.Actor.APPLICANT, true
            );

            Case caseUpdate = new Case(Id = application.Id, Self_Service_Last_Action_On__c = System.now());
            if (result.previousScheduleId != null) {
                Integer used = application.Reschedule_Count__c == null ? 0 : application.Reschedule_Count__c.intValue();
                caseUpdate.Reschedule_Count__c = used + 1;
            }
            Database.update(caseUpdate, AccessLevel.SYSTEM_MODE);
        } catch (InterviewBookingService.BookingException ex) {
            return fail('ERROR', ex.getMessage(), ctx);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Self-service booking failed: ' + ex.getMessage());
            return fail('ERROR', 'We could not save your selection. Please try again or call Help Give Hope.', ctx);
        }

        // Re-read everything so the confirmation reflects the committed state.
        TokenContext refreshed = resolve(token);
        if (refreshed.failure != null) {
            return refreshed.failure;
        }
        BookingDTO dto = buildBooking(refreshed);
        dto.message = 'Your interview time is confirmed.';
        if (refreshed.cfg.sendConfirmationOnChange && dto.hasBooking) {
            try {
                InterviewSelfServiceService.sendChangeConfirmation(
                    applicantEmail(refreshed.application), dto.firstName,
                    dto.currentDateLabel + ', ' + dto.currentTimeLabel,
                    InterviewSelfServiceService.buildUrl(refreshed.cfg.siteBaseUrl, token.trim())
                );
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'Confirmation email not sent: ' + ex.getMessage());
            }
        }
        return dto;
    }

    // ------------------------------------------------------------------
    // Token resolution
    // ------------------------------------------------------------------

    private static TokenContext resolve(String token) {
        TokenContext ctx = new TokenContext();
        ctx.cfg = InterviewSelfServiceConfig.load();

        if (!ctx.cfg.enabled) {
            ctx.failure = failure('DISABLED', 'Online interview scheduling is currently unavailable. Please call Help Give Hope.', ctx.cfg);
            return ctx;
        }
        if (!InterviewSelfServiceService.looksLikeToken(token)) {
            ctx.failure = failure('INVALID', 'This scheduling link is not valid. Please use the link from your email or contact Help Give Hope.', ctx.cfg);
            return ctx;
        }

        String hash = InterviewSelfServiceService.hashToken(token.trim());
        List<Case> cases = [
            SELECT Id, CaseNumber, AccountId, Reschedule_Count__c, Self_Service_Token_Expires__c,
                   Contact.FirstName, Contact.Email,
                   Account.npe01__One2OneContact__r.FirstName, Account.npe01__One2OneContact__r.Email,
                   Interview_Day_Schedule__c,
                   Interview_Day_Schedule__r.Id,
                   Interview_Day_Schedule__r.Name,
                   Interview_Day_Schedule__r.Interview_Date__c,
                   Interview_Day_Schedule__r.Start_Time__c,
                   Interview_Day_Schedule__r.End_Time__c,
                   Interview_Day_Schedule__r.Booked__c,
                   Interview_Day_Schedule__r.Assigned_Volunteer__r.Name,
                   Interview_Day_Schedule__r.Assigned_Volunteer__r.FirstName,
                   Interview_Day_Schedule__r.Assigned_Volunteer__r.LastName,
                   Interview_Day_Schedule__r.Interview_Day__r.Interview_Date__c,
                   Interview_Day_Schedule__r.Interview_Day__r.Zone__r.Name
            FROM Case
            WHERE Self_Service_Token_Hash__c = :hash
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            ctx.failure = failure('INVALID', 'This scheduling link is not valid. Please use the link from your email or contact Help Give Hope.', ctx.cfg);
            return ctx;
        }
        Case application = cases[0];
        if (application.Self_Service_Token_Expires__c == null || application.Self_Service_Token_Expires__c < System.now()) {
            ctx.failure = failure('EXPIRED', 'This scheduling link has expired. Please contact Help Give Hope for a new one.', ctx.cfg);
            return ctx;
        }
        if (application.AccountId == null) {
            ctx.failure = failure('ERROR', 'Your application is missing household details. Please contact Help Give Hope.', ctx.cfg);
            return ctx;
        }
        ctx.application = application;
        return ctx;
    }

    private static BookingDTO buildBooking(TokenContext ctx) {
        Case application = ctx.application;
        InterviewSelfServiceConfig cfg = ctx.cfg;

        BookingDTO dto = new BookingDTO();
        dto.status = 'OK';
        dto.firstName = firstName(application);
        dto.cutoffHours = cfg.rescheduleCutoffHours;
        dto.supportPhone = cfg.supportPhone;

        Integer used = application.Reschedule_Count__c == null ? 0 : application.Reschedule_Count__c.intValue();
        dto.reschedulesRemaining = cfg.maxReschedules > 0 ? Math.max(cfg.maxReschedules - used, 0) : null;

        Interview_Day_Schedule__c current = currentSchedule(application);
        if (current != null) {
            dto.hasBooking = true;
            dto.currentScheduleId = current.Id;
            Date interviewDate = current.Interview_Date__c != null
                ? current.Interview_Date__c
                : (current.Interview_Day__r == null ? null : current.Interview_Day__r.Interview_Date__c);
            dto.currentDateLabel = GoogleCalendarService.dateLabel(interviewDate);
            dto.currentTimeLabel = current.Start_Time__c == null ? '' :
                GoogleCalendarService.timeLabel(current.Start_Time__c) + ' - ' + GoogleCalendarService.timeLabel(current.End_Time__c);
            dto.currentZoneName = current.Interview_Day__r != null && current.Interview_Day__r.Zone__r != null
                ? current.Interview_Day__r.Zone__r.Name : null;
            dto.currentInterviewer = cfg.showInterviewerToApplicant ? interviewerName(current.Assigned_Volunteer__r) : null;
        }

        // Can the applicant change anything?
        if (dto.hasBooking && InterviewBookingService.isWithinCutoff(current, cfg.rescheduleCutoffHours)) {
            dto.canChange = false;
            dto.cannotChangeReason = 'Your interview starts within ' + cfg.rescheduleCutoffHours
                + ' hours and can no longer be changed online.';
        } else if (dto.hasBooking && dto.reschedulesRemaining != null && dto.reschedulesRemaining == 0) {
            dto.canChange = false;
            dto.cannotChangeReason = 'You have reached the maximum number of online changes.';
        } else {
            dto.canChange = true;
        }

        if (!dto.canChange) {
            return dto;
        }

        InterviewBookingService.ZoneResolution zone = InterviewBookingService.resolveZoneForAccount(application.AccountId);
        if (!zone.isResolved()) {
            dto.status = 'NO_ZONE';
            dto.canChange = false;
            dto.cannotChangeReason = 'We could not determine your interview area from your address. Please call Help Give Hope to schedule.';
            return dto;
        }

        for (Interview_Day__c day : InterviewBookingService.queryBookableDays(
            zone, InterviewBookingService.Actor.APPLICANT, cfg.daysAheadVisible
        )) {
            DayDTO dayDto = new DayDTO();
            dayDto.interviewDayId = day.Id;
            dayDto.dateValue = String.valueOf(day.Interview_Date__c);
            dayDto.dateLabel = GoogleCalendarService.dateLabel(day.Interview_Date__c);
            dayDto.mode = GoogleCalendarService.modeLabel(day.Schedule_Mode__c);
            dayDto.zoneName = day.Zone__r == null ? null : day.Zone__r.Name;

            for (Interview_Day_Schedule__c slot : day.Interview_Day_Schedules__r) {
                if (slot.Start_Time__c == null || slot.End_Time__c == null) {
                    continue; // never offer an un-timed slot
                }
                SlotDTO slotDto = new SlotDTO();
                slotDto.scheduleId = slot.Id;
                slotDto.startLabel = GoogleCalendarService.timeLabel(slot.Start_Time__c);
                slotDto.endLabel = GoogleCalendarService.timeLabel(slot.End_Time__c);
                slotDto.label = slotDto.startLabel + ' - ' + slotDto.endLabel;
                slotDto.selectable = !InterviewBookingService.isWithinCutoff(
                    day.Interview_Date__c, slot.Start_Time__c, cfg.rescheduleCutoffHours
                );
                slotDto.reason = slotDto.selectable ? null : 'Too close to book online';
                dayDto.slots.add(slotDto);
            }
            if (!dayDto.slots.isEmpty()) {
                dto.days.add(dayDto);
            }
        }
        return dto;
    }

    private static Interview_Day_Schedule__c currentSchedule(Case application) {
        if (application == null) {
            return null;
        }
        if (application.Interview_Day_Schedule__c != null
            && application.Interview_Day_Schedule__r != null
            && application.Interview_Day_Schedule__r.Booked__c == true) {
            return application.Interview_Day_Schedule__r;
        }

        List<Interview_Day_Schedule__c> legacy = [
            SELECT Id, Name, Interview_Date__c, Start_Time__c, End_Time__c, Booked__c,
                   Assigned_Volunteer__r.Name, Assigned_Volunteer__r.FirstName, Assigned_Volunteer__r.LastName,
                   Interview_Day__r.Interview_Date__c, Interview_Day__r.Zone__r.Name
            FROM Interview_Day_Schedule__c
            WHERE Case__c = :application.Id AND Booked__c = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return legacy.isEmpty() ? null : legacy[0];
    }

    /** First + last name of the volunteer; null when unassigned or when the name looks auto-generated. */
    @TestVisible
    private static String interviewerName(User volunteer) {
        if (volunteer == null) {
            return null;
        }
        String name;
        if (String.isNotBlank(volunteer.FirstName)) {
            name = volunteer.FirstName + (String.isBlank(volunteer.LastName) ? '' : ' ' + volunteer.LastName);
        } else if (String.isNotBlank(volunteer.Name)) {
            name = volunteer.Name;
        } else {
            name = volunteer.LastName;
        }
        if (String.isBlank(name) || Pattern.matches('(?i)^(user|test|integration|api)?\\s*\\d{6,}.*$', name.trim())) {
            return null;
        }
        return name.trim();
    }

    private static String applicantEmail(Case application) {
        if (application.Contact != null && String.isNotBlank(application.Contact.Email)) {
            return application.Contact.Email;
        }
        if (application.Account != null && application.Account.npe01__One2OneContact__r != null) {
            return application.Account.npe01__One2OneContact__r.Email;
        }
        return null;
    }

    private static String firstName(Case application) {
        if (application.Contact != null && String.isNotBlank(application.Contact.FirstName)) {
            return application.Contact.FirstName;
        }
        if (application.Account != null && application.Account.npe01__One2OneContact__r != null
            && String.isNotBlank(application.Account.npe01__One2OneContact__r.FirstName)) {
            return application.Account.npe01__One2OneContact__r.FirstName;
        }
        return null;
    }

    private static BookingDTO failure(String status, String message, InterviewSelfServiceConfig cfg) {
        BookingDTO dto = new BookingDTO();
        dto.status = status;
        dto.message = message;
        dto.supportPhone = cfg == null ? null : cfg.supportPhone;
        return dto;
    }

    /** Error response that still shows the current state of the booking. */
    private static BookingDTO fail(String status, String message, TokenContext ctx) {
        BookingDTO dto = buildBooking(ctx);
        dto.status = status;
        dto.message = message;
        return dto;
    }
}