public without sharing class TimeTrackerController {

    // ---------- Public Apex called by LWC ----------

    @AuraEnabled
    public static String checkTimeEntryStatus(String email_phone) {
        try {
            List<Contact> contacts = [
                SELECT Id, Name
                FROM Contact
                WHERE (Phone = :email_phone OR Email = :email_phone)
                LIMIT 1
            ];

            if (contacts.isEmpty()) {
                return 'No contact found for the provided Phone or Email.::Error';
            }

            Time_Entry__c openEntry = getTimeEntryStatus(contacts[0].Id);
            return (openEntry == null) ? 'No active check-in::Success' : 'Checked in::Success';

        } catch (Exception ex) {
            System.debug('TimeTrackerController.checkTimeEntryStatus: ' + ex.getMessage());
            throw new AuraHandledException('Something went wrong, contact your Administrator.');
        }
    }

    @AuraEnabled
    public static String createTimeEntry(String email_phone) {
        try {
            List<Contact> contacts = [
                SELECT Id, Name
                FROM Contact
                WHERE (Phone = :email_phone OR Email = :email_phone)
                LIMIT 1
            ];

            if (contacts.isEmpty()) {
                return 'No contact found for the provided Phone or Email.::Error';
            }

            Contact c = contacts[0];
            Time_Entry__c openEntry = getTimeEntryStatus(c.Id);

            Time_Entry__c toUpsert = new Time_Entry__c();
            toUpsert.Contact__c = c.Id;
            toUpsert.Name = c.Name + ' - ' + Datetime.now().format('dd/MM/yyyy');

            if (openEntry == null) {
                // Check in
                toUpsert.Start_Time__c = Datetime.now();
                upsert toUpsert;
                return c.Name + ' has been checked in.::Success';
            } else {
                // Check out
                toUpsert.Id = openEntry.Id;
                toUpsert.End_Time__c = Datetime.now();
                upsert toUpsert;
                return c.Name + ' has been checked out.::Success';
            }

        } catch (Exception ex) {
            System.debug('TimeTrackerController.createTimeEntry: ' + ex.getMessage());
            throw new AuraHandledException('Something went wrong, contact your Administrator.');
        }
    }

    // Returns the currently open entry (no End_Time__c) for a contact, if any
    public static Time_Entry__c getTimeEntryStatus(Id contactId) {
        List<Time_Entry__c> timeEntryList = [
            SELECT Id, Start_Time__c
            FROM Time_Entry__c
            WHERE End_Time__c = NULL
              AND Contact__c = :contactId
            ORDER BY Start_Time__c DESC
            LIMIT 1
        ];
        return timeEntryList.isEmpty() ? null : timeEntryList[0];
    }

    // ---------- DTO for Today’s table ----------

    public class TimeEntryRow {
        @AuraEnabled public Id entryId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime endTime;
        @AuraEnabled public Decimal totalHours; // portion falling inside "today" (null if open & no overlap)
    }

    // ---------- Today’s entries (cacheable) ----------

    @AuraEnabled(cacheable=true)
    public static List<TimeEntryRow> getTodaysEntries() {
        // Compute org-local "today" bounds
        Date today = Date.today();
        Datetime start = Datetime.newInstance(today, Time.newInstance(0, 0, 0, 0));
        Datetime endday   = Datetime.newInstance(today.addDays(1), Time.newInstance(0, 0, 0, 0)).addSeconds(-1);

        // Overlap logic: any entry that touches today
        List<Time_Entry__c> entries = [
            SELECT Id,
                   Contact__c,
                   Contact__r.Name,
                   Start_Time__c,
                   End_Time__c
            FROM Time_Entry__c
            WHERE Start_Time__c <= :endday
              AND (End_Time__c = NULL OR End_Time__c >= :start)
            ORDER BY Contact__r.Name ASC, Start_Time__c DESC
            LIMIT 500
        ];

        List<TimeEntryRow> rows = new List<TimeEntryRow>();
        Datetime nowUtc = System.now();

        for (Time_Entry__c te : entries) {
            TimeEntryRow r = new TimeEntryRow();
            r.entryId = te.Id;
            r.contactId = te.Contact__c;
            r.contactName = (te.Contact__r != null) ? te.Contact__r.Name : null;
            r.startTime = te.Start_Time__c;
            r.endTime = te.End_Time__c;

            // Clip duration to today's window; treat open entries as "now"
            Datetime effStart = (r.startTime > start) ? r.startTime : start;
            Datetime effEnd   = (r.endTime != null) ? r.endTime : nowUtc;
            effEnd = (effEnd < endday) ? effEnd : endday;

            if (effEnd.getTime() > effStart.getTime()) {
                Long ms = effEnd.getTime() - effStart.getTime();
                r.totalHours = ((Decimal) ms) / 3600000; // 3,600,000 ms/hr
            } else {
                r.totalHours = null;
            }

            rows.add(r);
        }
        return rows;
    }
}