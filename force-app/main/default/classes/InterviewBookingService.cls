/**
 * Single implementation of interview slot booking, rescheduling and release.
 *
 * Used by SelectInterviewSlotController (staff, with sharing) and InterviewSelfServiceController
 * (site guest, without sharing) - the class inherits the caller's sharing so both keep their semantics.
 * DML runs in system mode because the site guest user has no CRUD on scheduling objects.
 *
 * Invariants enforced here (not in the UI):
 *  - a slot is locked (FOR UPDATE) and re-checked before it is booked, so two users cannot double book
 *  - applicants may only book Published days in their own zone and outside the reschedule cutoff
 *  - a household holds at most one booking (Account.Interview_Day_Schedule__c)
 *  - rescheduling releases the old slot first and books the new one second, in two DML statements,
 *    so the HGH_Interview_Volunteer_Assignment flow restores and re-assigns Case ownership correctly
 *  - Google synchronisation is signalled only by setting Google_Sync_Status__c; nothing is enqueued here
 */
public inherited sharing class InterviewBookingService {

    public class BookingException extends Exception {}

    public enum Actor { STAFF, APPLICANT }

    public class BookingResult {
        public Id accountId;
        public Id caseId;
        public Id scheduleId;
        public Id previousScheduleId;
        public Id volunteerId;
        public Id zoneId;
    }

    /** How the household maps to a zone: direct Zone__c match through HGH_Zone_Code__c, or numeric fallback. */
    public class ZoneResolution {
        public Id zoneId;
        public Decimal numericCode;
        public String censusTract;
        public Boolean isResolved() {
            return zoneId != null || numericCode != null;
        }
    }

    private static final Set<String> STAFF_BOOKABLE_DAY_STATUSES = new Set<String>{ 'Planned', 'Published' };
    private static final Set<String> APPLICANT_BOOKABLE_DAY_STATUSES = new Set<String>{ 'Published' };

    // ------------------------------------------------------------------
    // Resolution helpers
    // ------------------------------------------------------------------

    /** Accepts an Account Id or a Case Id and returns the Account Id. */
    public static Id resolveAccountId(Id recordId) {
        if (recordId == null) {
            return null;
        }
        if (recordId.getSObjectType() == Account.SObjectType) {
            return recordId;
        }
        if (recordId.getSObjectType() == Case.SObjectType) {
            List<Case> cases = [SELECT AccountId FROM Case WHERE Id = :recordId LIMIT 1];
            return cases.isEmpty() ? null : cases[0].AccountId;
        }
        return null;
    }

    public static ZoneResolution resolveZoneForAccount(Id accountId) {
        ZoneResolution resolution = new ZoneResolution();
        if (accountId == null) {
            return resolution;
        }
        List<Account> accounts = [SELECT Id, Census_Tract__c FROM Account WHERE Id = :accountId LIMIT 1];
        if (accounts.isEmpty() || String.isBlank(accounts[0].Census_Tract__c)) {
            return resolution;
        }
        resolution.censusTract = accounts[0].Census_Tract__c.trim();

        Decimal numeric;
        try {
            numeric = Decimal.valueOf(resolution.censusTract);
        } catch (Exception ignored) {
            numeric = null;
        }

        // Exact text match first, then numeric equality so "12.3" and "12.30" resolve to the same code.
        for (HGH_Zone_Code__c code : [
            SELECT Zone__c, Code__c
            FROM HGH_Zone_Code__c
            WHERE Active__c = true AND Zone__c != null
        ]) {
            if (code.Code__c == null) {
                continue;
            }
            if (code.Code__c.trim() == resolution.censusTract) {
                resolution.zoneId = code.Zone__c;
                return resolution;
            }
            if (numeric != null && resolution.zoneId == null) {
                try {
                    if (Decimal.valueOf(code.Code__c.trim()) == numeric) {
                        resolution.zoneId = code.Zone__c;
                    }
                } catch (Exception ignored) {
                    // non-numeric code
                }
            }
        }
        if (resolution.zoneId == null) {
            resolution.numericCode = numeric;
        }
        return resolution;
    }

    /**
     * Interview days (with their unbooked slots) the bookingActor may book for the resolved zone.
     * Days without an open slot are omitted.
     */
    public static List<Interview_Day__c> queryBookableDays(ZoneResolution zone, Actor bookingActor, Integer daysAhead) {
        List<Interview_Day__c> result = new List<Interview_Day__c>();
        if (zone == null || !zone.isResolved()) {
            return result;
        }
        Set<String> statuses = bookingActor == Actor.APPLICANT ? APPLICANT_BOOKABLE_DAY_STATUSES : STAFF_BOOKABLE_DAY_STATUSES;
        Date today = Date.today();
        Date horizon = daysAhead == null || daysAhead <= 0 ? today.addYears(5) : today.addDays(daysAhead);

        List<Interview_Day__c> days;
        if (zone.zoneId != null) {
            days = [
                SELECT Id, Interview_Date__c, Schedule_Mode__c, Status__c, Zone__c, Zone__r.Name, Zone_Code__c,
                       (SELECT Id, Name, Start_Time__c, End_Time__c, Booked__c
                        FROM Interview_Day_Schedules__r
                        WHERE Booked__c = false
                        ORDER BY Start_Time__c ASC NULLS LAST, Name ASC)
                FROM Interview_Day__c
                WHERE Zone__c = :zone.zoneId
                  AND Interview_Date__c >= :today
                  AND Interview_Date__c <= :horizon
                  AND Status__c IN :statuses
                ORDER BY Interview_Date__c ASC, Schedule_Mode__c ASC
            ];
        } else {
            days = [
                SELECT Id, Interview_Date__c, Schedule_Mode__c, Status__c, Zone__c, Zone__r.Name, Zone_Code__c,
                       (SELECT Id, Name, Start_Time__c, End_Time__c, Booked__c
                        FROM Interview_Day_Schedules__r
                        WHERE Booked__c = false
                        ORDER BY Start_Time__c ASC NULLS LAST, Name ASC)
                FROM Interview_Day__c
                WHERE Zone_Code__c = :zone.numericCode
                  AND Interview_Date__c >= :today
                  AND Interview_Date__c <= :horizon
                  AND Status__c IN :statuses
                ORDER BY Interview_Date__c ASC, Schedule_Mode__c ASC
            ];
        }

        Set<String> takenKeys = bookingActor == Actor.APPLICANT && InterviewSelfServiceConfig.load().enforceSingleInterviewPerTime
            ? bookedTimeKeys(days)
            : new Set<String>();

        for (Interview_Day__c day : days) {
            if (day.Interview_Day_Schedules__r == null || day.Interview_Day_Schedules__r.isEmpty()) {
                continue;
            }
            if (takenKeys.isEmpty()) {
                result.add(day);
                continue;
            }
            // Drop slots whose time is already taken on another zone's day. Subquery results are
            // read-only lists, so rebuild the day with a filtered copy.
            List<Interview_Day_Schedule__c> openSlots = new List<Interview_Day_Schedule__c>();
            for (Interview_Day_Schedule__c slot : day.Interview_Day_Schedules__r) {
                String key = String.valueOf(day.Interview_Date__c) + '|' + String.valueOf(slot.Start_Time__c);
                if (!takenKeys.contains(key)) {
                    openSlots.add(slot);
                }
            }
            if (!openSlots.isEmpty()) {
                result.add(withSlots(day, openSlots));
            }
        }
        return result;
    }

    private static Interview_Day__c withSlots(Interview_Day__c day, List<Interview_Day_Schedule__c> slots) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(day));
        data.remove('Interview_Day_Schedules__r');
        Interview_Day__c copy = (Interview_Day__c) JSON.deserialize(JSON.serialize(data), Interview_Day__c.class);
        Map<String, Object> children = new Map<String, Object>{
            'totalSize' => slots.size(), 'done' => true, 'records' => slots
        };
        Map<String, Object> withChildren = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(copy));
        withChildren.put('Interview_Day_Schedules__r', children);
        return (Interview_Day__c) JSON.deserialize(JSON.serialize(withChildren), Interview_Day__c.class);
    }

    // ------------------------------------------------------------------
    // Booking operations
    // ------------------------------------------------------------------

    /**
     * Books a slot for the household identified by recordId (Account or Case Id).
     * volunteerId is optional; when the caller passes a Case Id the slot is linked to that Case.
     */
    public static BookingResult book(Id scheduleId, Id recordId, Id volunteerId, Actor bookingActor) {
        if (scheduleId == null) {
            throw new BookingException('Interview schedule Id is required.');
        }
        Id accountId = resolveAccountId(recordId);
        if (accountId == null) {
            throw new BookingException('Unable to resolve a household for the selected booking.');
        }
        Id caseId = recordId != null && recordId.getSObjectType() == Case.SObjectType ? recordId : null;
        if (volunteerId != null) {
            validateActiveVolunteer(volunteerId);
        }

        Account household = loadAccount(accountId);
        if (household.Interview_Day_Schedule__c != null && household.Interview_Day_Schedule__c != scheduleId) {
            throw new BookingException('This household already has a booked interview. Unschedule it or use reschedule.');
        }

        ZoneResolution zone = resolveZoneForAccount(accountId);
        Savepoint sp = Database.setSavepoint();
        try {
            Interview_Day_Schedule__c slot = lockSlots(new Set<Id>{ scheduleId }).get(scheduleId);
            validateSlotForBooking(slot, bookingActor, zone);

            Interview_Day_Schedule__c slotUpdate = new Interview_Day_Schedule__c(
                Id = slot.Id,
                Booked__c = true,
                Case__c = caseId,
                Status__c = 'Booked',
                Assignment_Status__c = volunteerId == null ? 'Unassigned' : 'Assigned',
                Google_Sync_Status__c = GoogleCalendarService.STATUS_PENDING
            );
            if (volunteerId != null) {
                slotUpdate.Assigned_Volunteer__c = volunteerId;
            }
            Database.update(slotUpdate, AccessLevel.SYSTEM_MODE);

            Id zoneId = effectiveZoneId(slot, zone);
            updateAccountPointer(accountId, slot.Id, zoneId);

            BookingResult result = new BookingResult();
            result.accountId = accountId;
            result.caseId = caseId;
            result.scheduleId = slot.Id;
            result.volunteerId = volunteerId;
            result.zoneId = zoneId;
            return result;
        } catch (BookingException ex) {
            Database.rollback(sp);
            throw ex;
        } catch (Exception ex) {
            Database.rollback(sp);
            throw new BookingException('Error booking schedule: ' + ex.getMessage());
        }
    }

    /**
     * Moves the household's booking to newScheduleId. When carryVolunteer is true the volunteer assigned
     * to the old slot is assigned to the new slot. Falls back to book() when nothing is booked yet.
     */
    public static BookingResult reschedule(Id caseId, Id newScheduleId, Actor bookingActor, Boolean carryVolunteer) {
        if (caseId == null || newScheduleId == null) {
            throw new BookingException('Application and interview schedule are required.');
        }
        List<Case> cases = [SELECT Id, AccountId FROM Case WHERE Id = :caseId LIMIT 1];
        if (cases.isEmpty() || cases[0].AccountId == null) {
            throw new BookingException('The application is not linked to a household.');
        }
        Id accountId = cases[0].AccountId;
        Account household = loadAccount(accountId);
        Id oldScheduleId = household.Interview_Day_Schedule__c;

        if (oldScheduleId == null) {
            return book(newScheduleId, caseId, null, bookingActor);
        }
        if (oldScheduleId == newScheduleId) {
            throw new BookingException('That is already the booked interview slot.');
        }

        ZoneResolution zone = resolveZoneForAccount(accountId);
        InterviewSelfServiceConfig cfg = InterviewSelfServiceConfig.load();
        Savepoint sp = Database.setSavepoint();
        try {
            Map<Id, Interview_Day_Schedule__c> locked = lockSlots(new Set<Id>{ oldScheduleId, newScheduleId });
            Interview_Day_Schedule__c oldSlot = locked.get(oldScheduleId);
            Interview_Day_Schedule__c newSlot = locked.get(newScheduleId);

            if (oldSlot == null) {
                throw new BookingException('The current interview slot could not be found. Please contact Help Give Hope.');
            }
            if (oldSlot.Case__c != null && oldSlot.Case__c != caseId) {
                throw new BookingException('The current booking belongs to a different application.');
            }
            if (bookingActor == Actor.APPLICANT && isWithinCutoff(oldSlot, cfg.rescheduleCutoffHours)) {
                throw new BookingException('Your interview starts within ' + cfg.rescheduleCutoffHours
                    + ' hours and can no longer be changed online. Please call Help Give Hope.');
            }
            validateSlotForBooking(newSlot, bookingActor, zone);

            Id volunteerId = carryVolunteer == true ? oldSlot.Assigned_Volunteer__c : null;

            // 1) release the old slot - the assignment flow removes access and restores Case ownership
            Database.update(new Interview_Day_Schedule__c(
                Id = oldSlot.Id,
                Booked__c = false,
                Case__c = null,
                Status__c = 'Available',
                Assigned_Volunteer__c = null,
                Google_Sync_Status__c = GoogleCalendarService.STATUS_PENDING
            ), AccessLevel.SYSTEM_MODE);

            // 2) book the new slot - the assignment flow grants access and assigns Case ownership
            Interview_Day_Schedule__c newUpdate = new Interview_Day_Schedule__c(
                Id = newSlot.Id,
                Booked__c = true,
                Case__c = caseId,
                Status__c = 'Booked',
                Assignment_Status__c = volunteerId == null ? 'Unassigned' : 'Assigned',
                Google_Sync_Status__c = GoogleCalendarService.STATUS_PENDING
            );
            if (volunteerId != null) {
                newUpdate.Assigned_Volunteer__c = volunteerId;
            }
            Database.update(newUpdate, AccessLevel.SYSTEM_MODE);

            Id zoneId = effectiveZoneId(newSlot, zone);
            updateAccountPointer(accountId, newSlot.Id, zoneId);

            BookingResult result = new BookingResult();
            result.accountId = accountId;
            result.caseId = caseId;
            result.scheduleId = newSlot.Id;
            result.previousScheduleId = oldSlot.Id;
            result.volunteerId = volunteerId;
            result.zoneId = zoneId;
            return result;
        } catch (BookingException ex) {
            Database.rollback(sp);
            throw ex;
        } catch (Exception ex) {
            Database.rollback(sp);
            throw new BookingException('Error rescheduling interview: ' + ex.getMessage());
        }
    }

    /**
     * Removes the household's booking. The slot becomes Available again (and its Google event is
     * converted back to a placeholder or deleted, depending on configuration).
     */
    public static BookingResult release(Id recordId) {
        Id accountId = resolveAccountId(recordId);
        if (accountId == null) {
            throw new BookingException('Unable to resolve a household for the selected booking.');
        }
        Account household = loadAccount(accountId);
        if (household.Interview_Day_Schedule__c == null) {
            throw new BookingException('No existing booking found to unschedule.');
        }
        Id scheduleId = household.Interview_Day_Schedule__c;

        Savepoint sp = Database.setSavepoint();
        try {
            Database.update(new Interview_Day_Schedule__c(
                Id = scheduleId,
                Case__c = null,
                Booked__c = false,
                Status__c = 'Available',
                Assigned_Volunteer__c = null,
                Google_Sync_Status__c = GoogleCalendarService.STATUS_PENDING
            ), AccessLevel.SYSTEM_MODE);

            Database.update(new Account(Id = accountId, Interview_Day_Schedule__c = null), AccessLevel.SYSTEM_MODE);

            BookingResult result = new BookingResult();
            result.accountId = accountId;
            result.previousScheduleId = scheduleId;
            return result;
        } catch (Exception ex) {
            Database.rollback(sp);
            throw new BookingException('Error unscheduling interview: ' + ex.getMessage());
        }
    }

    // ------------------------------------------------------------------
    // Validation
    // ------------------------------------------------------------------

    /** True when the slot starts less than cutoffHours from now (in the configured calendar time zone). */
    public static Boolean isWithinCutoff(Interview_Day_Schedule__c slot, Integer cutoffHours) {
        if (slot == null) {
            return false;
        }
        Date interviewDate = slot.Interview_Date__c != null
            ? slot.Interview_Date__c
            : (slot.Interview_Day__r != null ? slot.Interview_Day__r.Interview_Date__c : null);
        return isWithinCutoff(interviewDate, slot.Start_Time__c, cutoffHours);
    }

    public static Boolean isWithinCutoff(Date interviewDate, Time startTime, Integer cutoffHours) {
        if (cutoffHours == null || cutoffHours <= 0) {
            return false;
        }
        Datetime start = slotStart(interviewDate, startTime);
        if (start == null) {
            return true; // no usable time on the slot: do not let applicants touch it
        }
        return start < System.now().addHours(cutoffHours);
    }

    /** Absolute start instant of a slot: Interview Date + Start Time interpreted in the calendar time zone. */
    public static Datetime slotStart(Date interviewDate, Time startTime) {
        if (interviewDate == null || startTime == null) {
            return null;
        }
        TimeZone tz = TimeZone.getTimeZone(GoogleCalendarSettings.load().timeZone);
        Datetime asGmt = Datetime.newInstanceGmt(interviewDate, startTime);
        Integer offsetMs = tz == null ? 0 : tz.getOffset(asGmt);
        return asGmt.addSeconds(-offsetMs / 1000);
    }

    private static void validateSlotForBooking(Interview_Day_Schedule__c slot, Actor bookingActor, ZoneResolution zone) {
        if (slot == null) {
            throw new BookingException('Selected interview slot was not found.');
        }
        if (slot.Booked__c == true) {
            throw new BookingException('This interview slot has already been booked. Please refresh and choose another slot.');
        }
        if (slot.Interview_Day__c == null || slot.Interview_Day__r == null) {
            throw new BookingException('This interview slot is not linked to an interview day.');
        }
        Set<String> statuses = bookingActor == Actor.APPLICANT ? APPLICANT_BOOKABLE_DAY_STATUSES : STAFF_BOOKABLE_DAY_STATUSES;
        if (!statuses.contains(slot.Interview_Day__r.Status__c)) {
            throw new BookingException('This interview day is not open for booking.');
        }
        if (slot.Interview_Day__r.Interview_Date__c == null || slot.Interview_Day__r.Interview_Date__c < Date.today()) {
            throw new BookingException('This interview day is in the past.');
        }
        if (InterviewSelfServiceConfig.load().enforceSingleInterviewPerTime && slot.Start_Time__c != null
            && isTimeTakenElsewhere(slot.Id, slot.Interview_Day__r.Interview_Date__c, slot.Start_Time__c)) {
            throw new BookingException('Another interview is already booked at this time. Please choose a different time.');
        }
        if (bookingActor == Actor.APPLICANT) {
            if (zone == null || !zone.isResolved()) {
                throw new BookingException('We could not determine your interview zone. Please call Help Give Hope.');
            }
            Boolean zoneMatches = zone.zoneId != null
                ? slot.Interview_Day__r.Zone__c == zone.zoneId
                : slot.Interview_Day__r.Zone_Code__c == zone.numericCode;
            if (!zoneMatches) {
                throw new BookingException('That interview slot is not available for your area.');
            }
            Integer cutoff = InterviewSelfServiceConfig.load().rescheduleCutoffHours;
            if (isWithinCutoff(slot, cutoff)) {
                throw new BookingException('Slots starting within ' + cutoff + ' hours cannot be booked online.');
            }
        }
    }

    /** True when a booked slot on any zone shares this date and start time. */
    private static Boolean isTimeTakenElsewhere(Id slotId, Date interviewDate, Time startTime) {
        return [
            SELECT COUNT()
            FROM Interview_Day_Schedule__c
            WHERE Booked__c = true
              AND Id != :slotId
              AND Start_Time__c = :startTime
              AND Interview_Day__r.Interview_Date__c = :interviewDate
        ] > 0;
    }

    /** Booked date + start-time keys for the given days, used to hide taken times from applicants. */
    private static Set<String> bookedTimeKeys(List<Interview_Day__c> days) {
        Set<Date> dates = new Set<Date>();
        for (Interview_Day__c day : days) {
            dates.add(day.Interview_Date__c);
        }
        Set<String> keys = new Set<String>();
        if (dates.isEmpty()) {
            return keys;
        }
        for (Interview_Day_Schedule__c booked : [
            SELECT Start_Time__c, Interview_Day__r.Interview_Date__c
            FROM Interview_Day_Schedule__c
            WHERE Booked__c = true AND Start_Time__c != null AND Interview_Day__r.Interview_Date__c IN :dates
        ]) {
            keys.add(String.valueOf(booked.Interview_Day__r.Interview_Date__c) + '|' + String.valueOf(booked.Start_Time__c));
        }
        return keys;
    }

    private static void validateActiveVolunteer(Id volunteerId) {
        if (volunteerId == null || volunteerId.getSObjectType() != User.SObjectType) {
            throw new BookingException('Please select a valid Salesforce User as the volunteer.');
        }
        if ([SELECT COUNT() FROM User WHERE Id = :volunteerId AND IsActive = true] == 0) {
            throw new BookingException('The selected volunteer is not an active Salesforce User.');
        }
    }

    // ------------------------------------------------------------------
    // Data access
    // ------------------------------------------------------------------

    private static Account loadAccount(Id accountId) {
        List<Account> accounts = [SELECT Id, Interview_Day_Schedule__c FROM Account WHERE Id = :accountId LIMIT 1];
        if (accounts.isEmpty()) {
            throw new BookingException('Household not found for the selected booking.');
        }
        return accounts[0];
    }

    private static Map<Id, Interview_Day_Schedule__c> lockSlots(Set<Id> scheduleIds) {
        return new Map<Id, Interview_Day_Schedule__c>([
            SELECT Id, Name, Booked__c, Case__c, Assigned_Volunteer__c, Start_Time__c, End_Time__c,
                   Interview_Date__c, Interview_Day__c,
                   Interview_Day__r.Zone__c, Interview_Day__r.Zone_Code__c, Interview_Day__r.Status__c,
                   Interview_Day__r.Interview_Date__c, Interview_Day__r.Schedule_Mode__c
            FROM Interview_Day_Schedule__c
            WHERE Id IN :scheduleIds
            FOR UPDATE
        ]);
    }

    private static Id effectiveZoneId(Interview_Day_Schedule__c slot, ZoneResolution zone) {
        if (slot != null && slot.Interview_Day__r != null && slot.Interview_Day__r.Zone__c != null) {
            return slot.Interview_Day__r.Zone__c;
        }
        return zone == null ? null : zone.zoneId;
    }

    private static void updateAccountPointer(Id accountId, Id scheduleId, Id zoneId) {
        Account accountUpdate = new Account(Id = accountId, Interview_Day_Schedule__c = scheduleId);
        if (zoneId != null) {
            accountUpdate.Zones__c = zoneId;
        }
        Database.update(accountUpdate, AccessLevel.SYSTEM_MODE);
    }
}