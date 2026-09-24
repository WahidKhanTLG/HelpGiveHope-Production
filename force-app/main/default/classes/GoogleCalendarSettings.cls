/**
 * Typed view of HGH_Google_Calendar_Config__mdt (record "Default").
 * Loaded once per transaction. Tests inject an instance through instanceOverride
 * instead of depending on org custom metadata.
 */
public without sharing class GoogleCalendarSettings {

    public static final String CONFIG_NAME = 'Default';
    public static final Integer MAX_BATCH_SIZE = 45;

    public Boolean recordFound = false;
    public Boolean enabled = false;
    public String calendarId;
    public String timeZone = 'America/Chicago';
    public String eventTitlePattern = 'Help Give Hope Home Interview - {CaseNumber}';
    public String sendUpdates = 'none';
    public Boolean placeholderSyncEnabled = false;
    public String availableTitlePattern = 'Available - {ZoneName} {Mode} - Slot {Slot}';
    public String availableColorId;
    public String bookedColorId;
    public Boolean inviteApplicant = true;
    public Boolean inviteVolunteer = true;
    public Boolean includeHouseholdAddress = false;
    public Integer syncBatchSize = 25;
    public Integer sweepIntervalMinutes = 5;

    @TestVisible private static GoogleCalendarSettings instanceOverride;
    private static GoogleCalendarSettings cached;

    public static GoogleCalendarSettings load() {
        if (instanceOverride != null) {
            return instanceOverride;
        }
        if (cached != null) {
            return cached;
        }

        GoogleCalendarSettings settings = new GoogleCalendarSettings();
        HGH_Google_Calendar_Config__mdt config = HGH_Google_Calendar_Config__mdt.getInstance(CONFIG_NAME);

        if (config != null) {
            settings.recordFound = true;
            settings.enabled = config.Enabled__c == true;
            settings.calendarId = blankToNull(config.Calendar_Id__c);
            if (String.isNotBlank(config.Time_Zone__c)) {
                settings.timeZone = config.Time_Zone__c.trim();
            }
            if (String.isNotBlank(config.Event_Title_Pattern__c)) {
                settings.eventTitlePattern = config.Event_Title_Pattern__c;
            }
            settings.sendUpdates = normalizeSendUpdates(config.Send_Updates__c);
            settings.placeholderSyncEnabled = config.Placeholder_Sync_Enabled__c == true;
            if (String.isNotBlank(config.Available_Title_Pattern__c)) {
                settings.availableTitlePattern = config.Available_Title_Pattern__c;
            }
            settings.availableColorId = blankToNull(config.Available_Color_Id__c);
            settings.bookedColorId = blankToNull(config.Booked_Color_Id__c);
            settings.inviteApplicant = config.Invite_Applicant__c == true;
            settings.inviteVolunteer = config.Invite_Volunteer__c == true;
            settings.includeHouseholdAddress = config.Include_Household_Address__c == true;
            if (config.Sync_Batch_Size__c != null && config.Sync_Batch_Size__c > 0) {
                settings.syncBatchSize = config.Sync_Batch_Size__c.intValue();
            }
            if (config.Sweep_Interval_Minutes__c != null && config.Sweep_Interval_Minutes__c > 0) {
                settings.sweepIntervalMinutes = config.Sweep_Interval_Minutes__c.intValue();
            }
        }

        settings.syncBatchSize = Math.min(Math.max(settings.syncBatchSize, 1), MAX_BATCH_SIZE);
        settings.sweepIntervalMinutes = Math.max(settings.sweepIntervalMinutes, 1);
        cached = settings;
        return settings;
    }

    public static String normalizeSendUpdates(String value) {
        if (String.isBlank(value)) {
            return 'none';
        }
        String normalized = value.trim().toLowerCase();
        if (normalized == 'all') {
            return 'all';
        }
        if (normalized == 'externalonly') {
            return 'externalOnly';
        }
        return 'none';
    }

    private static String blankToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}