/**
 * Creates and delivers applicant scheduling links.
 *
 * Token model: 32 random bytes, base64url encoded (43 chars) in the link only; the Case stores the
 * SHA-256 hex of the token plus an expiry. Sending a new link replaces the old one. The hash field
 * is written in system mode so no profile needs (or should have) access to it.
 */
public with sharing class InterviewSelfServiceService {

    public static final String LINK_PLACEHOLDER = '{{SELF_SERVICE_LINK}}';
    private static final Pattern TOKEN_PATTERN = Pattern.compile('^[A-Za-z0-9_-]{43}$');

    public class LinkRequest {
        @InvocableVariable(required=true label='Case Id')
        public Id caseId;
        @InvocableVariable(label='Send Email' description='Send the built-in scheduling email to the Case contact (default true).')
        public Boolean sendEmail;
    }

    public class LinkResult {
        @InvocableVariable(label='Case Id')
        public Id caseId;
        @InvocableVariable(label='Self-Service URL' description='Only returned when Send Email is false; treat it as a secret.')
        public String url;
        @InvocableVariable(label='Expires On')
        public Datetime expiresOn;
        @InvocableVariable(label='Error')
        public String error;
    }

    public class GeneratedLink {
        public Id caseId;
        public String url;
        public String token;
        public Datetime expiresOn;
    }

    /**
     * Flow entry point. One row per Case.
     */
    @InvocableMethod(
        label='Generate Interview Self-Service Link'
        description='Creates a new scheduling link for the application and optionally emails it to the Case contact.'
        category='HGH Interviews'
    )
    public static List<LinkResult> generateLinks(List<LinkRequest> requests) {
        List<LinkResult> results = new List<LinkResult>();
        if (requests == null) {
            return results;
        }
        for (LinkRequest request : requests) {
            LinkResult result = new LinkResult();
            results.add(result);
            if (request == null || request.caseId == null) {
                result.error = 'Case Id is required.';
                continue;
            }
            result.caseId = request.caseId;
            try {
                GeneratedLink link = generateAndStore(request.caseId);
                result.expiresOn = link.expiresOn;
                if (request.sendEmail == false) {
                    result.url = link.url;
                } else {
                    sendEmailForLink(request.caseId, link);
                }
            } catch (Exception ex) {
                result.error = ex.getMessage();
            }
        }
        return results;
    }

    /** Quick-action entry point: new link + email. Returns a short confirmation for the toast. */
    @AuraEnabled
    public static String sendLink(Id caseId) {
        if (caseId == null || caseId.getSObjectType() != Case.SObjectType) {
            throw new AuraHandledException('Open this action from an application (Case).');
        }
        try {
            GeneratedLink link = generateAndStore(caseId);
            String recipient = sendEmailForLink(caseId, link);
            return 'Scheduling link sent to ' + recipient + '. It expires on '
                + link.expiresOn.format('MMM d, yyyy') + '.';
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // ------------------------------------------------------------------
    // Token handling
    // ------------------------------------------------------------------

    /** Generates a token, stores its hash on the Case and returns the link. */
    public static GeneratedLink generateAndStore(Id caseId) {
        InterviewSelfServiceConfig cfg = InterviewSelfServiceConfig.load();
        if (String.isBlank(cfg.siteBaseUrl)) {
            throw new AuraHandledException('Self-service Site Base URL is not configured (HGH Interview Self-Service Config).');
        }
        // Sharing check: the running user must be able to see the Case (with sharing class).
        List<Case> cases = [SELECT Id FROM Case WHERE Id = :caseId LIMIT 1];
        if (cases.isEmpty()) {
            throw new AuraHandledException('Application not found.');
        }

        GeneratedLink link = new GeneratedLink();
        link.caseId = caseId;
        link.token = generateToken();
        link.expiresOn = System.now().addDays(cfg.tokenValidityDays);
        link.url = buildUrl(cfg.siteBaseUrl, link.token);

        Database.update(new Case(
            Id = caseId,
            Self_Service_Token_Hash__c = hashToken(link.token),
            Self_Service_Token_Expires__c = link.expiresOn
        ), AccessLevel.SYSTEM_MODE);

        return link;
    }

    public static String generateToken() {
        Blob random = Crypto.generateAesKey(256);
        return EncodingUtil.base64Encode(random).replace('+', '-').replace('/', '_').replace('=', '');
    }

    public static Boolean looksLikeToken(String token) {
        return String.isNotBlank(token) && TOKEN_PATTERN.matcher(token.trim()).matches();
    }

    public static String hashToken(String token) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(token)));
    }

    public static String buildUrl(String baseUrl, String token) {
        String base = baseUrl.trim();
        String separator = base.contains('?') ? '&' : '?';
        return base + separator + 't=' + EncodingUtil.urlEncode(token, 'UTF-8');
    }

    // ------------------------------------------------------------------
    // Email
    // ------------------------------------------------------------------

    /** Sends the link to the Case contact. Returns the recipient address. */
    public static String sendEmailForLink(Id caseId, GeneratedLink link) {
        InterviewSelfServiceConfig cfg = InterviewSelfServiceConfig.load();
        List<Case> cases = [
            SELECT Id, CaseNumber, ContactId, Contact.Email, Contact.FirstName,
                   Account.Interview_Day_Schedule__c,
                   Account.Interview_Day_Schedule__r.Interview_Date__c,
                   Account.Interview_Day_Schedule__r.Start_Time__c,
                   Account.Interview_Day_Schedule__r.End_Time__c,
                   Account.Interview_Day_Schedule__r.Interview_Day__r.Zone__r.Name
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            throw new AuraHandledException('Application not found.');
        }
        Case application = cases[0];
        if (application.ContactId == null || String.isBlank(application.Contact.Email)) {
            throw new AuraHandledException('The application contact has no email address.');
        }

        Messaging.SingleEmailMessage mail;
        if (String.isNotBlank(cfg.emailTemplateDeveloperName)) {
            mail = renderTemplate(cfg.emailTemplateDeveloperName, application, link);
        }
        if (mail == null) {
            mail = buildDefaultEmail(application, link, cfg);
        }

        mail.setTargetObjectId(application.ContactId);
        mail.setWhatId(application.Id);
        mail.setSaveAsActivity(true);
        mail.setUseSignature(false);
        Id oweaId = orgWideEmailId(cfg.orgWideEmailDisplayName);
        if (oweaId != null) {
            mail.setOrgWideEmailAddressId(oweaId);
        }

        if (!Test.isRunningTest()) {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        }

        Database.update(new Case(Id = caseId, Self_Service_Link_Sent_On__c = System.now()), AccessLevel.SYSTEM_MODE);
        return application.Contact.Email;
    }

    /**
     * Confirmation after an online booking/change. Callable from the site guest context: takes the
     * already-resolved recipient data, sends to the address directly and logs nothing.
     */
    public static void sendChangeConfirmation(String toEmail, String firstName, String bookingLabel, String url) {
        if (String.isBlank(toEmail)) {
            return;
        }
        InterviewSelfServiceConfig cfg = InterviewSelfServiceConfig.load();
        String name = String.isBlank(firstName) ? 'there' : firstName;
        String safeUrl = url == null ? '' : url.escapeHtml4();
        String phoneLine = String.isBlank(cfg.supportPhone)
            ? 'If you need help, reply to this email.'
            : 'If you need help, call us at ' + cfg.supportPhone.escapeHtml4() + '.';
        String html = '<p>Hi ' + name.escapeHtml4() + ',</p>'
            + '<p>Your home interview is confirmed for <strong>' + bookingLabel.escapeHtml4() + '</strong>.</p>'
            + (String.isBlank(safeUrl) ? '' : '<p>You can review or change it here: <a href="' + safeUrl + '">' + safeUrl + '</a></p>')
            + '<p>' + phoneLine + '</p><p>Help Give Hope</p>';

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ toEmail });
        mail.setSubject('Your Help Give Hope home interview is confirmed');
        mail.setHtmlBody(html);
        mail.setPlainTextBody(html.stripHtmlTags());
        mail.setSaveAsActivity(false);
        try {
            Id oweaId = orgWideEmailId(cfg.orgWideEmailDisplayName);
            if (oweaId != null) {
                mail.setOrgWideEmailAddressId(oweaId);
            }
        } catch (Exception ignored) {
            // guest users may not be able to read org-wide addresses; fall back to the default sender
        }
        if (!Test.isRunningTest()) {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        }
    }

    private static Messaging.SingleEmailMessage renderTemplate(String developerName, Case application, GeneratedLink link) {
        List<EmailTemplate> templates = [
            SELECT Id FROM EmailTemplate WHERE DeveloperName = :developerName AND IsActive = true LIMIT 1
        ];
        if (templates.isEmpty()) {
            return null;
        }
        try {
            Messaging.SingleEmailMessage rendered =
                Messaging.renderStoredEmailTemplate(templates[0].Id, application.ContactId, application.Id);
            if (rendered.getHtmlBody() != null) {
                rendered.setHtmlBody(rendered.getHtmlBody().replace(LINK_PLACEHOLDER, link.url));
            }
            if (rendered.getPlainTextBody() != null) {
                rendered.setPlainTextBody(rendered.getPlainTextBody().replace(LINK_PLACEHOLDER, link.url));
            }
            return rendered;
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Template render failed, using built-in email: ' + ex.getMessage());
            return null;
        }
    }

    private static Messaging.SingleEmailMessage buildDefaultEmail(
    Case application,
    GeneratedLink link,
    InterviewSelfServiceConfig cfg
) {
    String firstName = String.isBlank(application.Contact.FirstName)
        ? 'there'
        : application.Contact.FirstName;

    String safeUrl = link.url.escapeHtml4();

    String bookingLine;
    String interviewWindowLine = '';

    Interview_Day_Schedule__c slot =
        application.Account == null
            ? null
            : application.Account.Interview_Day_Schedule__r;

    if (
        slot != null &&
        slot.Interview_Date__c != null &&
        slot.Start_Time__c != null
    ) {
        bookingLine =
            'Your home interview is currently scheduled for <strong>'
            + GoogleCalendarService.dateLabel(slot.Interview_Date__c)
            + ', '
            + GoogleCalendarService.timeLabel(slot.Start_Time__c)
            + ' - '
            + GoogleCalendarService.timeLabel(slot.End_Time__c)
            + '</strong>.';

        interviewWindowLine =
            'Please note that your home interview may take place at any time '
            + 'between 8:00 AM and 12:30 PM for the earlier time block, '
            + 'or between 12:30 PM and 5:00 PM for the later time block.';
    } else {
        bookingLine =
            'Your home interview has not been scheduled yet.';
    }

    String cutoffLine = cfg.rescheduleCutoffHours > 0
        ? 'Changes can be made online up to '
            + cfg.rescheduleCutoffHours
            + ' hours before the interview.'
        : '';

    String phoneLine = String.isBlank(cfg.supportPhone)
        ? 'If you need help, reply to this email.'
        : 'If you need help, call us at '
            + cfg.supportPhone.escapeHtml4()
            + '.';

    String html =
        '<p>Hi ' + firstName.escapeHtml4() + ',</p>'
        + '<p>' + bookingLine + '</p>'
        + (
            String.isBlank(interviewWindowLine)
                ? ''
                : '<p>' + interviewWindowLine + '</p>'
        )
        + '<p>You can view your interview time, choose a slot, or change it here:</p>'
        + '<p><a href="' + safeUrl + '">' + safeUrl + '</a></p>'
        + '<p>'
        + cutoffLine
        + ' This link is personal to your application and expires on '
        + link.expiresOn.format('MMMM d, yyyy')
        + '. Please do not share it.</p>'
        + '<p>' + phoneLine + '</p>'
        + '<p>Help Give Hope</p>';

    Messaging.SingleEmailMessage mail =
        new Messaging.SingleEmailMessage();

    mail.setSubject(
        'Your Help Give Hope home interview - view or change your time'
    );

    mail.setHtmlBody(html);
    mail.setPlainTextBody(html.stripHtmlTags());

    return mail;
}

    private static Id orgWideEmailId(String displayName) {
        if (String.isBlank(displayName)) {
            return null;
        }
        List<OrgWideEmailAddress> addresses = [
            SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = :displayName LIMIT 1
        ];
        return addresses.isEmpty() ? null : addresses[0].Id;
    }
}