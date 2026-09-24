/**
 * Typed view of HGH_Interview_Self_Service_Config__mdt (record "Default").
 */
public without sharing class InterviewSelfServiceConfig {

    public static final String CONFIG_NAME = 'Default';

    public Boolean recordFound = false;
    public Boolean enabled = true;
    public Boolean autoSendLinkOnBooking = true;
    public Boolean sendConfirmationOnChange = true;
    public Boolean showInterviewerToApplicant = true;
    public Boolean enforceSingleInterviewPerTime = true;
    public Integer rescheduleCutoffHours = 24;
    public Integer maxReschedules = 3;          // 0 = unlimited
    public Integer tokenValidityDays = 45;
    public Integer daysAheadVisible = 90;       // 0 = unlimited
    public String siteBaseUrl;
    public String orgWideEmailDisplayName = 'Help Give Hope Support';
    public String emailTemplateDeveloperName;
    public String supportPhone;

    @TestVisible private static InterviewSelfServiceConfig instanceOverride;
    private static InterviewSelfServiceConfig cached;

    public static InterviewSelfServiceConfig load() {
        if (instanceOverride != null) {
            return instanceOverride;
        }
        if (cached != null) {
            return cached;
        }

        InterviewSelfServiceConfig cfg = new InterviewSelfServiceConfig();
        HGH_Interview_Self_Service_Config__mdt record =
            HGH_Interview_Self_Service_Config__mdt.getInstance(CONFIG_NAME);

        if (record != null) {
            cfg.recordFound = true;
            cfg.enabled = record.Enabled__c == true;
            cfg.autoSendLinkOnBooking = record.Auto_Send_Link_On_Booking__c == true;
            cfg.sendConfirmationOnChange = record.Send_Confirmation_On_Change__c == true;
            cfg.showInterviewerToApplicant = record.Show_Interviewer_To_Applicant__c == true;
            cfg.enforceSingleInterviewPerTime = record.Enforce_Single_Interview_Per_Time__c == true;
            if (record.Reschedule_Cutoff_Hours__c != null && record.Reschedule_Cutoff_Hours__c >= 0) {
                cfg.rescheduleCutoffHours = record.Reschedule_Cutoff_Hours__c.intValue();
            }
            if (record.Max_Reschedules__c != null && record.Max_Reschedules__c >= 0) {
                cfg.maxReschedules = record.Max_Reschedules__c.intValue();
            }
            if (record.Token_Validity_Days__c != null && record.Token_Validity_Days__c > 0) {
                cfg.tokenValidityDays = record.Token_Validity_Days__c.intValue();
            }
            if (record.Days_Ahead_Visible__c != null && record.Days_Ahead_Visible__c >= 0) {
                cfg.daysAheadVisible = record.Days_Ahead_Visible__c.intValue();
            }
            cfg.siteBaseUrl = blankToNull(record.Site_Base_Url__c);
            if (String.isNotBlank(record.Org_Wide_Email_Display_Name__c)) {
                cfg.orgWideEmailDisplayName = record.Org_Wide_Email_Display_Name__c.trim();
            }
            cfg.emailTemplateDeveloperName = blankToNull(record.Email_Template_Developer_Name__c);
            cfg.supportPhone = blankToNull(record.Support_Phone__c);
        }

        cached = cfg;
        return cfg;
    }

    private static String blankToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}