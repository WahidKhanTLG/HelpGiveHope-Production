public with sharing class BulkVolunteerReassignmentController {
    private static final Integer MAX_BATCH_SIZE = 20;
    private static final Set<String> TERMINAL_STATUSES = new Set<String>{
        'Completed',
        'Reviewed',
        'Canceled'
    };

    public class OptionItem {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }

        public OptionItem(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class InterviewRow {
        @AuraEnabled public Id scheduleId { get; set; }
        @AuraEnabled public Id caseId { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public String householdName { get; set; }
        @AuraEnabled public String zoneName { get; set; }
        @AuraEnabled public Date interviewDate { get; set; }
        @AuraEnabled public String interviewDateLabel { get; set; }
        @AuraEnabled public String startTimeLabel { get; set; }
        @AuraEnabled public String endTimeLabel { get; set; }
        @AuraEnabled public String timeWindow { get; set; }
        @AuraEnabled public Id currentVolunteerId { get; set; }
        @AuraEnabled public String currentVolunteerName { get; set; }
        @AuraEnabled public String assignmentStatus { get; set; }
        @AuraEnabled public Boolean selectable { get; set; }
        @AuraEnabled public String lockedReason { get; set; }
    }

    public class ReassignmentResult {
        @AuraEnabled public Integer requestedCount { get; set; }
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public Integer skippedCount { get; set; }
        @AuraEnabled public Integer failedCount { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public List<String> details { get; set; }

        public ReassignmentResult() {
            requestedCount = 0;
            successCount = 0;
            skippedCount = 0;
            failedCount = 0;
            details = new List<String>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<OptionItem> getZones() {
        List<OptionItem> options = new List<OptionItem>();

        // Show every configured Zone in the selector.
        // Scheduled Date remains dependent on the selected Zone and only
        // returns booked, Case-linked interview dates from the current year.
        for (Zone__c zoneRecord : [
            SELECT Id, Name
            FROM Zone__c
            ORDER BY Name
        ]) {
            options.add(
                new OptionItem(
                    zoneRecord.Name,
                    String.valueOf(zoneRecord.Id)
                )
            );
        }

        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<OptionItem> getScheduleDates(Id zoneId) {
        validateZoneId(zoneId);

        Date startDate = Date.newInstance(Date.today().year(), 1, 1);
        Date endDate = Date.newInstance(Date.today().year() + 1, 1, 1);

        List<OptionItem> options = new List<OptionItem>();
        for (AggregateResult resultRow : [
            SELECT Interview_Date__c interviewDate
            FROM Interview_Day_Schedule__c
            WHERE Zone__c = :zoneId
              AND Booked__c = true
              AND Case__c != null
              AND Interview_Date__c >= :startDate
              AND Interview_Date__c < :endDate
            GROUP BY Interview_Date__c
            ORDER BY Interview_Date__c
        ]) {
            Date interviewDate = (Date) resultRow.get('interviewDate');
            if (interviewDate != null) {
                options.add(
                    new OptionItem(
                        formatDate(interviewDate),
                        String.valueOf(interviewDate)
                    )
                );
            }
        }

        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<OptionItem> getVolunteers() {
        List<OptionItem> options = new List<OptionItem>();

        for (User volunteer : [
            SELECT Id, Name, Email
            FROM User
            WHERE IsActive = true
            ORDER BY Name
            LIMIT 500
        ]) {
            String label = volunteer.Name;
            if (String.isNotBlank(volunteer.Email)) {
                label += ' - ' + volunteer.Email;
            }
            options.add(new OptionItem(label, String.valueOf(volunteer.Id)));
        }

        return options;
    }

    @AuraEnabled
    public static List<InterviewRow> getInterviews(Id zoneId, Date interviewDate) {
        validateZoneId(zoneId);
        validateCurrentYearDate(interviewDate);

        List<InterviewRow> rows = new List<InterviewRow>();

        for (Interview_Day_Schedule__c schedule : [
            SELECT Id,
                   Case__c,
                   Case__r.CaseNumber,
                   Case__r.Account.Name,
                   Interview_Date__c,
                   Start_Time__c,
                   End_Time__c,
                   Zone__c,
                   Zone__r.Name,
                   Assigned_Volunteer__c,
                   Assigned_Volunteer__r.Name,
                   Assignment_Status__c,
                   Booked__c
            FROM Interview_Day_Schedule__c
            WHERE Zone__c = :zoneId
              AND Interview_Date__c = :interviewDate
              AND Booked__c = true
              AND Case__c != null
            ORDER BY Start_Time__c, Case__r.CaseNumber
        ]) {
            InterviewRow row = new InterviewRow();
            row.scheduleId = schedule.Id;
            row.caseId = schedule.Case__c;
            row.caseNumber = schedule.Case__r == null ? '' : schedule.Case__r.CaseNumber;
            row.householdName =
                schedule.Case__r != null && schedule.Case__r.Account != null
                    ? schedule.Case__r.Account.Name
                    : '';
            row.zoneName = schedule.Zone__r == null ? '' : schedule.Zone__r.Name;
            row.interviewDate = schedule.Interview_Date__c;
            row.interviewDateLabel = formatDate(schedule.Interview_Date__c);
            row.startTimeLabel = formatTime(schedule.Start_Time__c);
            row.endTimeLabel = formatTime(schedule.End_Time__c);
            row.timeWindow = row.startTimeLabel + ' - ' + row.endTimeLabel;
            row.currentVolunteerId = schedule.Assigned_Volunteer__c;
            row.currentVolunteerName =
                schedule.Assigned_Volunteer__r == null
                    ? 'Unassigned'
                    : schedule.Assigned_Volunteer__r.Name;
            row.assignmentStatus = String.isBlank(schedule.Assignment_Status__c)
                ? 'Unassigned'
                : schedule.Assignment_Status__c;
            row.selectable = !TERMINAL_STATUSES.contains(row.assignmentStatus);
            row.lockedReason = row.selectable
                ? ''
                : 'This interview is ' + row.assignmentStatus + ' and cannot be reassigned.';
            rows.add(row);
        }

        return rows;
    }

    @AuraEnabled
    public static ReassignmentResult reassignVolunteers(
        List<Id> scheduleIds,
        Id volunteerId
    ) {
        ReassignmentResult response = new ReassignmentResult();

        if (scheduleIds == null || scheduleIds.isEmpty()) {
            throw new AuraHandledException('Select at least one interview to reassign.');
        }

        Set<Id> uniqueScheduleIds = new Set<Id>();
        for (Id scheduleId : scheduleIds) {
            if (scheduleId != null) {
                uniqueScheduleIds.add(scheduleId);
            }
        }

        response.requestedCount = uniqueScheduleIds.size();

        if (uniqueScheduleIds.isEmpty()) {
            throw new AuraHandledException('Select at least one valid interview to reassign.');
        }

        if (uniqueScheduleIds.size() > MAX_BATCH_SIZE) {
            throw new AuraHandledException(
                'A maximum of ' + MAX_BATCH_SIZE + ' interviews can be reassigned at one time.'
            );
        }

        validateVolunteer(volunteerId);

        Date startDate = Date.newInstance(Date.today().year(), 1, 1);
        Date endDate = Date.newInstance(Date.today().year() + 1, 1, 1);

        List<Interview_Day_Schedule__c> lockedSchedules = [
            SELECT Id,
                   Case__c,
                   Case__r.CaseNumber,
                   Booked__c,
                   Interview_Date__c,
                   Assigned_Volunteer__c,
                   Assignment_Status__c
            FROM Interview_Day_Schedule__c
            WHERE Id IN :uniqueScheduleIds
            FOR UPDATE
        ];

        Map<Id, Interview_Day_Schedule__c> foundById =
            new Map<Id, Interview_Day_Schedule__c>(lockedSchedules);

        List<Interview_Day_Schedule__c> updates = new List<Interview_Day_Schedule__c>();
        List<String> updateCaseNumbers = new List<String>();

        for (Id scheduleId : uniqueScheduleIds) {
            Interview_Day_Schedule__c schedule = foundById.get(scheduleId);

            if (schedule == null) {
                response.failedCount++;
                response.details.add('One selected interview could not be found or accessed.');
                continue;
            }

            String caseNumber =
                schedule.Case__r == null
                    ? String.valueOf(schedule.Id)
                    : schedule.Case__r.CaseNumber;

            if (schedule.Booked__c != true || schedule.Case__c == null) {
                response.failedCount++;
                response.details.add(caseNumber + ': interview is not an active booked Case.');
                continue;
            }

            if (
                schedule.Interview_Date__c == null ||
                schedule.Interview_Date__c < startDate ||
                schedule.Interview_Date__c >= endDate
            ) {
                response.failedCount++;
                response.details.add(caseNumber + ': interview is outside the current year.');
                continue;
            }

            String currentStatus = String.isBlank(schedule.Assignment_Status__c)
                ? 'Unassigned'
                : schedule.Assignment_Status__c;

            if (TERMINAL_STATUSES.contains(currentStatus)) {
                response.failedCount++;
                response.details.add(
                    caseNumber + ': ' + currentStatus + ' interviews cannot be reassigned.'
                );
                continue;
            }

            if (schedule.Assigned_Volunteer__c == volunteerId) {
                response.skippedCount++;
                response.details.add(caseNumber + ': already assigned to the selected volunteer.');
                continue;
            }

            // Intentionally update only the authoritative assignment lookup.
            // The existing HGH volunteer-assignment automation is responsible for
            // Assignment_Status__c, Assigned_On__c, Case ownership/sharing, and
            // related assignment-side effects, exactly as it does for individual reassignment.
            updates.add(
                new Interview_Day_Schedule__c(
                    Id = schedule.Id,
                    Assigned_Volunteer__c = volunteerId
                )
            );
            updateCaseNumbers.add(caseNumber);
        }

        if (!updates.isEmpty()) {
            Database.SaveResult[] saveResults =
                Database.update(updates, false, AccessLevel.USER_MODE);

            for (Integer index = 0; index < saveResults.size(); index++) {
                if (saveResults[index].isSuccess()) {
                    response.successCount++;
                } else {
                    response.failedCount++;
                    String message = saveResults[index].getErrors().isEmpty()
                        ? 'Unknown Salesforce update error.'
                        : saveResults[index].getErrors()[0].getMessage();
                    response.details.add(
                        updateCaseNumbers[index] + ': ' + message
                    );
                }
            }
        }

        response.message =
            'Updated ' + response.successCount +
            ' of ' + response.requestedCount +
            ' selected interview' +
            (response.requestedCount == 1 ? '' : 's') + '.';

        if (response.skippedCount > 0) {
            response.message += ' Skipped ' + response.skippedCount + '.';
        }

        if (response.failedCount > 0) {
            response.message += ' Failed ' + response.failedCount + '.';
        }

        return response;
    }

    private static void validateZoneId(Id zoneId) {
        if (zoneId == null || zoneId.getSObjectType() != Zone__c.SObjectType) {
            throw new AuraHandledException('Select a valid Zone.');
        }
    }

    private static void validateVolunteer(Id volunteerId) {
        if (volunteerId == null || volunteerId.getSObjectType() != User.SObjectType) {
            throw new AuraHandledException('Select a valid volunteer.');
        }

        List<User> users = [
            SELECT Id
            FROM User
            WHERE Id = :volunteerId
              AND IsActive = true
            LIMIT 1
        ];

        if (users.isEmpty()) {
            throw new AuraHandledException('The selected volunteer is not an active Salesforce User.');
        }
    }

    private static void validateCurrentYearDate(Date interviewDate) {
        if (interviewDate == null) {
            throw new AuraHandledException('Select a Scheduled Date.');
        }

        if (interviewDate.year() != Date.today().year()) {
            throw new AuraHandledException('Scheduled Date must be in the current year.');
        }
    }

    private static String formatDate(Date value) {
        if (value == null) {
            return '';
        }

        return DateTime.newInstance(
            value,
            Time.newInstance(12, 0, 0, 0)
        ).format('MMMM d, yyyy');
    }

    private static String formatTime(Time value) {
        if (value == null) {
            return '';
        }

        return DateTime.newInstance(
            Date.today(),
            value
        ).format('h:mm a');
    }
}