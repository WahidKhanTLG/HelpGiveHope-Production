/**
 * @description       : Test class for SendEmailController
 * @author            : Syed Kashan
 * @group             : 
 * @last modified on  : 08-23-2024
 * @last modified by  : Syed Kashan
**/
@IsTest
private class SendEmailControllerTest {

    /**
     * @description Tests retrieval of email template metadata values.
     */
    @IsTest static void getMetaDataValuesTest() {
        Test.startTest();
        List<SendEmailController.EmailTemplateDTO> result = SendEmailController.getMetaDataValues();
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    /**
     * @description Tests retrieval of Account and related Contacts.
     */
    @IsTest static void getAccountRelatedContactsTest() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        Contact contact = new Contact(FirstName = 'Test', LastName = 'Contact', Email = 'test@test.com', temp_Primary_Contact__c = true, AccountId = acc.Id);
        insert contact;
        Test.startTest();
        SendEmailController.RecordDetail result = SendEmailController.getAccount_RelatedContacts(acc.Id);
        Test.stopTest();
        System.assertEquals(1, result.toEmails.size(), 'Should return one toEmail');
    }
    
    /**
     * @description Tests updating an Account.
     */
    @IsTest static void updateAccountTest() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        acc.Name = 'Hello';
        String result = SendEmailController.updateAccount(acc);
        System.assertEquals('OK', result);
    }

    /**
     * @description Tests sending email and inserting metadata without developer name.
     */
    @IsTest static void sendEmailAndInsertEmailBodyMetadataWithoutDeveloperNameTest() {
        Account acc = new Account(Name = 'Task Test Account');
        insert acc;
        Contact contact = new Contact(FirstName = 'Task', LastName = 'Contact', Email = 'test1@test.com', AccountId = acc.Id);
        insert contact;
        List<String> toEmails = new List<String>{'test1@test.com'};
        List<String> ccEmails = new List<String>{'test2@test.com'};
        List<String> bccEmails = new List<String>{'test3@test.com'};
        String emailSubject = 'Test Subject';
        String emailBody = 'Test Body';
        Test.startTest();
        String result = SendEmailController.sendEmailAndInsertEmailBodyMetadata(toEmails, ccEmails, bccEmails, emailSubject, emailBody, '', acc.Id, acc.Id);
        Test.stopTest();
        System.assertEquals('OK', result);
        List<EmailMessage> emails = [SELECT Id FROM EmailMessage WHERE ToAddress = :contact.Email AND RelatedToId = :acc.Id];
        //System.assertEquals(1, emails.size(), 'An EmailMessage should be created for the Contact');
    }

    /**
     * @description Tests sending email and inserting metadata with developer name.
     */
    @IsTest static void sendEmailAndInsertEmailBodyMetadataWithDeveloperNameTest() {
        Account acc = new Account(Name = 'Task Test Account 2');
        insert acc;
        Contact contact = new Contact(FirstName = 'Task2', LastName = 'Contact2', Email = 'test1@test.com', AccountId = acc.Id);
        insert contact;
        List<String> toEmails = new List<String>{'test1@test.com'};
        List<String> ccEmails = new List<String>{'test2@test.com'};
        List<String> bccEmails = new List<String>{'test3@test.com'};
        String emailSubject = 'Test Subject';
        String emailBody = 'Test Body';
        List<Email_Bodies__mdt> emailMetadataList = [SELECT Id, body__c, subject__c, DeveloperName FROM Email_Bodies__mdt LIMIT 1];
        Test.startTest();
        String result = SendEmailController.sendEmailAndInsertEmailBodyMetadata(toEmails, ccEmails, bccEmails, emailSubject, emailBody, emailMetadataList.isEmpty() ? '' : emailMetadataList[0].DeveloperName, acc.Id, acc.Id);
        Test.stopTest();
        System.assertEquals('OK', result);
        List<EmailMessage> emails = [SELECT Id FROM EmailMessage WHERE ToAddress = :contact.Email AND RelatedToId = :acc.Id];
        //System.assertEquals(1, emails.size(), 'An EmailMessage should be created for the Contact');
    }

    /**
     * @description Tests sending email.
     */
    @IsTest static void sendEmailTest() {
        Account acc = new Account(Name = 'Task Test Account 3');
        insert acc;
        Contact contact = new Contact(FirstName = 'Task3', LastName = 'Contact3', Email = 'test1@test.com', AccountId = acc.Id);
        insert contact;
        List<String> toEmails = new List<String>{'test1@test.com'};
        List<String> ccEmails = new List<String>{'test2@test.com'};
        List<String> bccEmails = new List<String>{'test3@test.com'};
        String emailSubject = 'Test Subject';
        String emailBody = 'Test Body';
        Test.startTest();
        String result = SendEmailController.sendEmail(toEmails, ccEmails, bccEmails, emailSubject, emailBody, acc.Id, acc.Id);
        Test.stopTest();
        System.assertEquals('OK', result);
        List<EmailMessage> emails = [SELECT Id FROM EmailMessage WHERE ToAddress = :contact.Email AND RelatedToId = :acc.Id];
        System.assertEquals(1, emails.size(), 'An EmailMessage should be created for the Contact');
    }

    /**
     * @description Tests picklist value retrieval for a valid field.
     */
    @IsTest static void getPicklistValuesValidFieldTest() {
        List<String> fieldPaths = new List<String>{'Account.Industry'};
        Test.startTest();
        List<SendEmailController.PickListOption> result = SendEmailController.getPicklistValues(fieldPaths).get('Account.Industry');
        Test.stopTest();
        System.assertNotEquals(null, result, 'Picklist options should not be null');
    }

    /**
     * @description Tests picklist value retrieval for an invalid field path.
     */
    @IsTest static void getPicklistValuesInvalidFieldPathTest() {
        List<String> invalidFieldPaths = new List<String>{'InvalidObject.InvalidField'};
        Test.startTest();
        Boolean caught = false;
        try {
            SendEmailController.getPicklistValues(invalidFieldPaths);
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();
        System.assert(caught, 'Exception should be thrown for invalid field path');
    }

    /**
     * @description Tests picklist value retrieval for a non-picklist field.
     */
    @IsTest static void getPicklistValuesNonPicklistFieldTest() {
        List<String> nonPicklistFieldPaths = new List<String>{'Account.Name'};
        Test.startTest();
        Boolean caught = false;
        try {
            SendEmailController.getPicklistValues(nonPicklistFieldPaths);
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();
        System.assert(caught, 'Exception should be thrown for non-picklist field');
    }

    /**
     * @description Tests custom exception throwing.
     */
    @IsTest static void throwExceptionTest() {
        Boolean caught = false;
        Test.startTest();
        try {
            SendEmailController.throwException('Custom exception test');
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();
        System.assert(caught, 'Exception should be thrown');
    }

    /**
     * @description Tests custom exception throwing with details.
     */
    @IsTest static void throwExceptionWithDetailsTest() {
        Boolean caught = false;
        Test.startTest();
        try {
            Integer x = 1 / 0; // Trigger an exception
        } catch (Exception ex) {
            try {
                SendEmailController.throwException('Detailed exception test', ex);
            } catch (AuraHandledException e) {
                caught = true;
            }
        }
        Test.stopTest();
        System.assert(caught, 'Exception should be thrown with details');
    }

    /**
     * @description Tests retrieval of related contacts when launched from a Case record.
     */
    @IsTest static void getAccountRelatedContactsFromCaseTest() {
        Account acc = new Account(Name = 'Case Context Account');
        insert acc;

        Contact primary = new Contact(FirstName = 'Primary', LastName = 'Contact', Email = 'primary@test.com', temp_Primary_Contact__c = true, AccountId = acc.Id);
        Contact secondary = new Contact(FirstName = 'Secondary', LastName = 'Contact', Email = 'secondary@test.com', AccountId = acc.Id);
        insert new List<Contact>{ primary, secondary };

        Case c = new Case(Subject = 'Case Context', Status = 'New', AccountId = acc.Id, ContactId = secondary.Id);
        insert c;

        Test.startTest();
        SendEmailController.RecordDetail result = SendEmailController.getAccount_RelatedContacts(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'RecordDetail should not be null.');
        System.assertNotEquals(null, result.account, 'Account should be returned from case context.');
        System.assertEquals(acc.Id, result.account.Id, 'Returned account should match case account.');
        System.assert(result.toEmails.contains('secondary@test.com'), 'Case contact email should be included in To emails.');
    }

    /**
     * @description Tests sending email from case context and linking EmailMessage to Case.
     */
    @IsTest static void sendEmailFromCaseContextTest() {
        Account acc = new Account(Name = 'Case Send Account');
        insert acc;

        Contact contact = new Contact(FirstName = 'Case', LastName = 'Recipient', Email = 'case.recipient@test.com', temp_Primary_Contact__c = true, AccountId = acc.Id);
        insert contact;

        Case c = new Case(Subject = 'Case Email', Status = 'New', AccountId = acc.Id, ContactId = contact.Id);
        insert c;

        List<String> toEmails = new List<String>{ 'case.recipient@test.com' };
        List<String> ccEmails = new List<String>();
        List<String> bccEmails = new List<String>();

        Test.startTest();
        String result = SendEmailController.sendEmail(toEmails, ccEmails, bccEmails, 'Case Subject', 'Case Body', acc.Id, c.Id);
        Test.stopTest();

        System.assertEquals('OK', result, 'sendEmail should return OK for case context.');

        List<EmailMessage> emails = [SELECT Id, RelatedToId FROM EmailMessage WHERE ToAddress = :contact.Email LIMIT 1];
        System.assertEquals(1, emails.size(), 'An EmailMessage should be created for case context.');
        System.assertEquals(c.Id, emails[0].RelatedToId, 'EmailMessage should be related to Case when launched from Case.');
    }
}