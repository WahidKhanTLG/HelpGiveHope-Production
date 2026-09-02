/**
 * @description       : Controller for sending emails, logging EmailMessage activities, and managing email templates.
 * @author            : Syed Kashan
 * @group             :
 * @last modified on  : 08-28-2024
 * @last modified by  : Syed Kashan
 */
public with sharing class SendEmailController implements Metadata.DeployCallback {

    /**
     * Gets picklist values for the specified field paths.
     * @param fieldPaths List of field API names (Object.Field)
     * @return Map of field path to picklist options
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<PickListOption>> getPicklistValues(List<String> fieldPaths) {
        Map<String, List<PickListOption>> picklistFieldValues = new Map<String, List<PickListOption>>();
        try {
            for(String fieldPath : fieldPaths) {
                List<String> parts = fieldPath.split('\\.');
                if(parts.size() != 2) {
                    throwException('Invalid field path format. Expected "ObjectName.FieldName"');
                }
                String objectName = parts[0];
                String fieldName = parts[1];
                Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
                if(objectType == null) {
                    throwException('Invalid object name: ' + objectName);
                }
                Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
                Schema.SObjectField field = fieldMap.get(fieldName);
                if(field == null) {
                    throwException('Invalid field name: ' + fieldName);
                }
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                if(fieldDescribe.getType() != Schema.DisplayType.PICKLIST && 
                   fieldDescribe.getType() != Schema.DisplayType.MULTIPICKLIST) {
                    throwException('Field is not a picklist: ' + fieldName);
                }
                List<PickListOption> pickListOptions = new List<PickListOption>();
                List<Schema.PicklistEntry> entries = fieldDescribe.getPicklistValues();
                for (Schema.PicklistEntry entry : entries) {
                    if(entry.isActive()) {
                        pickListOptions.add(new PickListOption(entry.getLabel(), entry.getValue()));
                    }
                }
                picklistFieldValues.put(fieldPath, pickListOptions);
            }
        } catch (Exception ex) {
            throwException('Error getting picklist values: ', ex);
        }
        return picklistFieldValues;
    }

    /**
     * Gets all email template metadata records.
     * @return List of EmailTemplateDTO
     */
    @AuraEnabled
    public static List<EmailTemplateDTO> getMetaDataValues() {
        try {
            if (!Schema.sObjectType.Email_Bodies__mdt.isAccessible()) {
                throw new AuraHandledException('No access to Email_Bodies__mdt');
            }
            List<EmailTemplateDTO> listEmailTemplate = new List<EmailTemplateDTO>();
            List<Email_Bodies__mdt> metaDataList = [SELECT Id, body__c, subject__c, DeveloperName FROM Email_Bodies__mdt LIMIT 100];
            if (!metaDataList.isEmpty()) {
                for (Email_Bodies__mdt emailBodies : metaDataList) {
                    listEmailTemplate.add(new EmailTemplateDTO(emailBodies.body__c, emailBodies.subject__c, emailBodies.DeveloperName));
                }
            }
            return listEmailTemplate;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * Gets Account and related Contacts for a given Account or Case Id.
     * @param recordId Account Id or Case Id
     * @return RecordDetail with Account and email lists
     */
    @AuraEnabled(cacheable=true)
    public static RecordDetail getAccount_RelatedContacts(Id recordId){
        try {
            if (!Schema.sObjectType.Account.isAccessible() || !Schema.sObjectType.Contact.isAccessible()) {
                throw new AuraHandledException('No access to Account or Contact');
            }

            Id accountId = null;
            Id caseContactId = null;
            RecordDetail recordDetail = new RecordDetail();

            if (recordId != null && recordId.getSObjectType() == Account.SObjectType) {
                accountId = recordId;
            } else if (recordId != null && recordId.getSObjectType() == Case.SObjectType) {
                List<Case> caseList = [SELECT Id, AccountId, ContactId, Status FROM Case WHERE Id = :recordId LIMIT 1];
                if (!caseList.isEmpty()) {
                    accountId = caseList[0].AccountId;
                    caseContactId = caseList[0].ContactId;
                    recordDetail.caseStatus = caseList[0].Status;
                }
            }

            if (accountId == null) {
                throw new AuraHandledException('No related Account found for the selected record.');
            }

            List<Account> accList = [SELECT Id, Name, Application_Status__c, (SELECT Id, npsp__Primary_Contact__c, temp_Primary_Contact__c, Email FROM Contacts WHERE Email != null) FROM Account WHERE Id =: accountId LIMIT 1];
            // RecordDetail recordDetail = new RecordDetail();
            List<String> toEmails = new List<String>();
            List<String> ccEmails = new List<String>();
            Set<String> seenEmails = new Set<String>();

            if (caseContactId != null) {
                List<Contact> caseContacts = [SELECT Id, Email FROM Contact WHERE Id = :caseContactId LIMIT 1];
                if (!caseContacts.isEmpty() && !String.isBlank(caseContacts[0].Email)) {
                    String primaryCaseEmail = caseContacts[0].Email.trim();
                    toEmails.add(primaryCaseEmail);
                    seenEmails.add(primaryCaseEmail.toLowerCase());
                }
            }

            if (!accList.isEmpty()) {
                List<String> emails;
                Account account = accList[0];
                for (Contact ocr : account.Contacts) {
                    if (String.isBlank(ocr.Email)) {
                        continue;
                    }

                    String normalizedEmail = ocr.Email.trim().toLowerCase();
                    if (seenEmails.contains(normalizedEmail)) {
                        continue;
                    }

                    emails = ocr.npsp__Primary_Contact__c || ocr.temp_Primary_Contact__c ? toEmails : ccEmails;
                    emails.add(ocr.Email.trim());
                    seenEmails.add(normalizedEmail);
                }
                recordDetail.account = account;
            }
            recordDetail.toEmails = toEmails;
            recordDetail.ccEmails = ccEmails;
            return recordDetail;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * Handles the result of a Metadata deployment.
     * @param result Metadata deployment result
     * @param context Metadata deployment callback context
     */
    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
        if (result.status == Metadata.DeployStatus.Succeeded) {
            // Logging for metadata deployment success (can be removed in production)
            System.debug(LoggingLevel.INFO, 'Metadata deployment succeeded: ' + result);
        } else {
            // Logging for metadata deployment failure (can be removed in production)
            System.debug(LoggingLevel.ERROR, 'Metadata deployment failed: ' + result);
        }
    }

    /**
     * Updates an Account record.
     * @param account Account to update
     * @return 'OK' if successful, error message otherwise
     */
    @AuraEnabled
    public static string updateAccount(Account account) {
        try {
            if (!Schema.sObjectType.Account.isUpdateable()) {
                return 'No update access to Account';
            }
            update account;
            return 'OK';
        } catch (Exception ex) {
            // Logging for updateAccount error (can be removed in production)
            System.debug(LoggingLevel.ERROR, 'updateAccount : ' + ex.getMessage());
            return ex.getMessage();
        }
    }

    @AuraEnabled
    public static String updateCaseStatus(Case caseRecord) {
        try {
            if (!Schema.sObjectType.Case.isUpdateable()) {
                return 'No update access to Case';
            }
            update caseRecord;
            return 'OK';
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'updateCaseStatus : ' + ex.getMessage());
            return ex.getMessage();
        }
    }

    /**
     * Sends an email, logs EmailMessage, and inserts/updates email template metadata.
     * @param toEmails List of To addresses
     * @param ccEmails List of CC addresses
     * @param bccEmails List of BCC addresses
     * @param emailSubject Email subject
     * @param emailBody Email body (HTML)
     * @param developerName Metadata developer name
     * @param accountId Related Account Id
    * @param relatedRecordId Related record id (Case or Account) for email activity logging
     * @return 'OK' if successful, error message otherwise
     */
    @AuraEnabled
    public static string sendEmailAndInsertEmailBodyMetadata(List<String> toEmails, List<String> ccEmails, List<String> bccEmails, String emailSubject, String emailBody, String developerName, Id accountId, Id relatedRecordId) {
        try {
            // Logging for developerName (can be removed in production)
            System.debug(LoggingLevel.INFO, 'developerName :: ' + developerName);
            if(developerName == ''){
                // Logging for new metadata creation (can be removed in production)
                System.debug(LoggingLevel.INFO, 'creating new');
                Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
                customMetadata.fullName = 'Email_Bodies__mdt.' + emailSubject.replace(' ', '_');
                customMetadata.label = emailSubject; 
                Metadata.CustomMetadataValue subjectValue = new Metadata.CustomMetadataValue();
                subjectValue.field = 'subject__c';
                subjectValue.value = emailSubject;
                Metadata.CustomMetadataValue bodyValue = new Metadata.CustomMetadataValue();
                bodyValue.field = 'body__c';
                bodyValue.value = emailBody;
                customMetadata.values.add(subjectValue);
                customMetadata.values.add(bodyValue);
                Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
                mdContainer.addMetadata(customMetadata);
                SendEmailController callback = new SendEmailController();
                if(!Test.isRunningTest()){
                    Id deploymentId = Metadata.Operations.enqueueDeployment(mdContainer, callback);
                }
            }
            else{
                List<Metadata.Metadata> components = Metadata.Operations.retrieve(Metadata.MetadataType.CustomMetadata, new List<String> { 'Email_Bodies__mdt.'+developerName });
                if (components.isEmpty()) {
                    // Logging for missing metadata (can be removed in production)
                    System.debug(LoggingLevel.WARN, 'No custom metadata records found.');
                } else {
                    Metadata.CustomMetadata customMetadataRecord = (Metadata.CustomMetadata) components.get(0);
                    Metadata.CustomMetadataValue bodyValue = new Metadata.CustomMetadataValue();
                    bodyValue.field = 'body__c';
                    bodyValue.value = emailBody;
                    Metadata.CustomMetadataValue subjectValue = new Metadata.CustomMetadataValue();
                    subjectValue.field = 'subject__c';
                    subjectValue.value = emailSubject;
                    customMetadataRecord.values.add(subjectValue);
                    customMetadataRecord.values.add(bodyValue);
                    Metadata.DeployContainer myContainer = new Metadata.DeployContainer();
                    myContainer.addMetadata(customMetadataRecord);
                    SendEmailController callback = new SendEmailController();
                    if(!Test.isRunningTest()){ 
                        Metadata.Operations.enqueueDeployment(myContainer, callback);
                    }
                }
            }
            sendEmailAsync(toEmails, ccEmails, bccEmails, emailSubject, emailBody, accountId, relatedRecordId);
            return 'OK';
        } catch (Exception ex) {
            // Logging for error (can be removed in production)
            System.debug(LoggingLevel.ERROR, 'sendEmailAndInsertEmailBodyMetadata : ' + ex.getMessage());
            return ex.getMessage();
        }
    }

    /**
     * Sends an email and logs EmailMessage activity.
     * @param toEmails List of To addresses
     * @param ccEmails List of CC addresses
     * @param bccEmails List of BCC addresses
     * @param emailSubject Email subject
     * @param emailBody Email body (HTML)
     * @param accountId Related Account Id
    * @param relatedRecordId Related record id (Case or Account) for email activity logging
     * @return 'OK' if successful, error message otherwise
     */
    @AuraEnabled
    public static string sendEmail(List<String> toEmails, List<String> ccEmails, List<String> bccEmails, String emailSubject, String emailBody, Id accountId, Id relatedRecordId) {
        try{
            toEmails = cleanAndValidateEmails(toEmails);
            ccEmails = cleanAndValidateEmails(ccEmails);
            bccEmails = cleanAndValidateEmails(bccEmails);
            string ccEmailsCommaSeperated = '';
            string bccEmailsCommaSeperated = '';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setUseSignature(false);
            mail.setSubject(emailSubject);
            mail.setHtmlBody(emailBody);
            mail.setToAddresses(toEmails);
            if(ccEmails.size() > 0) { 
                mail.setCcAddresses(ccEmails); 
                ccEmailsCommaSeperated = string.Join(ccEmails, ',');
            }
            if(bccEmails.size() > 0) { 
                mail.setBCcAddresses(bccEmails); 
                bccEmailsCommaSeperated = string.Join(bccEmails, ',');
            }
            Id oweaId = getOWEAIdByDisplayName('Help Give Hope Support');
            if (oweaId != null) {
                mail.setOrgWideEmailAddressId(oweaId);
            } else {
                // Logging for missing OWEA (can be removed in production)
                System.debug(LoggingLevel.WARN, 'OWEA with display name \"Help Give Hope Support\" not found.');
            }
            // Logging for sending email (can be removed in production)
            System.debug(LoggingLevel.INFO, 'Sending Email');
            if(!Test.isRunningTest()){
                 Messaging.SendEmailResult[] mailResult = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            }
            if (accountId != null && toEmails != null && !toEmails.isEmpty()) {
                if (!Schema.sObjectType.Contact.isAccessible() || !Schema.sObjectType.EmailMessage.isCreateable()) {
                    return 'No access to Contact or EmailMessage';
                }
                List<Contact> contacts = [SELECT Id, Email FROM Contact WHERE AccountId = :accountId AND Email IN :toEmails LIMIT 50];
                List<EmailMessage> emailsToInsert = new List<EmailMessage>();
                for (Contact c : contacts) {
                    EmailMessage em = new EmailMessage();
                    em.Subject = emailSubject;
                    em.HtmlBody = emailBody;
                    em.ToAddress = c.Email;
                    // em.FromAddress = 'noreply@helpgivehope.org';
                    em.FromAddress = 'help@helpgivehope.org';
                    em.RelatedToId = relatedRecordId != null ? relatedRecordId : accountId;
                    em.Status = '3'; // Sent
                    em.Incoming = false;
                    em.MessageDate = System.now();
                    em.FromName = 'Help Give Hope';
                    em.ToIds = new List<Id>{c.Id};
                    emailsToInsert.add(em);
                }
                if (!emailsToInsert.isEmpty()) {
                    insert emailsToInsert;
                }
            }
            return 'OK';
        } catch (Exception ex) {
            // Logging for error (can be removed in production)
            System.debug(LoggingLevel.ERROR, 'sendEmail : ' + ex.getMessage());
            throw new AuraHandledException(ex.getMessage());
        }
    }
    
    /**
     * Gets Org-Wide Email Address Id by display name.
     */
    private static Id getOWEAIdByDisplayName(String displayName) {
        List<OrgWideEmailAddress> oweaList = [SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = :displayName LIMIT 1];
        if (!oweaList.isEmpty()) {
            return oweaList[0].Id;
        }
        return null;
    }

    /**
     * Cleans and validates a list of email addresses.
     */
    private static List<String> cleanAndValidateEmails(List<String> emailList) {
        List<String> validEmails = new List<String>();
        for (String email : emailList) {
            email = email.trim();
            if (isValidEmail(email)) {
                validEmails.add(email);
            } else {
                // Logging for invalid email (can be removed in production)
                System.debug(LoggingLevel.WARN, 'Invalid email address: ' + email);
            }
        }
        return validEmails;
    }

    /**
     * Validates an email address using regex.
     */
    private static Boolean isValidEmail(String email) {
        Pattern emailPattern = Pattern.compile('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$');
        Matcher matcher = emailPattern.matcher(email);
        return matcher.matches();
    }

    /**
     * Sends email asynchronously (future method).
     */
    @future
	public static void sendEmailAsync(
    	List<String> toEmails,
    	List<String> ccEmails,
    	List<String> bccEmails,
    	String emailSubject,
    	String emailBody,
        Id accountId,
        Id relatedRecordId
	) {
    	try {
        	sendEmail(toEmails, ccEmails, bccEmails, emailSubject, emailBody, accountId, relatedRecordId);
        	System.debug(LoggingLevel.INFO, 'Email sent asynchronously with AccountId: ' + accountId + ', RelatedRecordId: ' + relatedRecordId);
    	} catch (Exception ex) {
        	System.debug(LoggingLevel.ERROR, 'Error in sendEmailAsync: ' + ex.getMessage());
    	}
	}

    /**
     * Throws an AuraHandledException with a message.
     */
    public static void throwException(String message) {
        AuraHandledException customException = new AuraHandledException(message);
        customException.setMessage(message);
        throw customException;
    }

    /**
     * Throws an AuraHandledException with details from an Exception.
     */
    public static void throwException(String title, Exception ex) {
        string message = (title != null ? title : '') +
            '\nMessage: ' + ex.getMessage() +
            '\nLineNumber: ' + ex.getLineNumber() +
            '\nStackTrace: ' + ex.getStackTraceString() +
            '\nExceptionType: ' + ex.getTypeName();
        System.debug(LoggingLevel.ERROR, message);
        throwException(message);        
    }

    public class RecordDetail {
        @AuraEnabled public Account account { get; set; }
        @AuraEnabled public List<string> toEmails { get; set; }
        @AuraEnabled public List<string> ccEmails { get; set; }
        @AuraEnabled public String caseStatus { get; set; }
    }

    public class EmailTemplateDTO {
        @AuraEnabled public String body { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String developerName { get; set; }
    
        public EmailTemplateDTO(String body, String subject,String developerName) {
            this.body = body;
            this.subject = subject;
            this.developerName = developerName;
        }
    }

    public class PickListOption {
        @AuraEnabled public string label { get; set; }
        @AuraEnabled public string value { get; set; }

        public PickListOption(string label, string value) {
            this.label = label;
            this.value = value;
        }
    }
}