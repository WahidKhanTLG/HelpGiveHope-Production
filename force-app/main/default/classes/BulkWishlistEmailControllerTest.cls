@IsTest
private class BulkWishlistEmailControllerTest {

    private static Id getCaseRecordTypeId(
        String developerName
    ) {
        return Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get(developerName)
            .getRecordTypeId();
    }

    @TestSetup
    static void createTemplate() {

        EmailTemplate templateRecord =
            new EmailTemplate(
                Name =
                    'Bulk Wishlist Test Template',

                DeveloperName =
                    'Bulk_Wishlist_Test_Template',

                FolderId =
                    UserInfo.getUserId(),

                TemplateType =
                    'text',

                Subject =
                    'Help Give Hope Wishlist',

                Body =
                    'Hello {!Contact.FirstName}'
            );

        insert templateRecord;
    }

    @IsTest
    static void sendChristmasWishlistEmailTest() {

        Account accountRecord =
            new Account(
                Name =
                    'Bulk Wishlist Household'
            );

        insert accountRecord;

        Contact contactRecord =
            new Contact(
                FirstName =
                    'Test',

                LastName =
                    'Applicant',

                Email =
                    'wishlist.test@example.com',

                AccountId =
                    accountRecord.Id
            );

        insert contactRecord;

        Case caseRecord =
            new Case(
                Subject =
                    'Christmas Bulk Wishlist Test',

                Status =
                    'New',

                Origin =
                    'Web',

                RecordTypeId =
                    getCaseRecordTypeId(
                        'Christmas_Application'
                    ),

                AccountId =
                    accountRecord.Id,

                ContactId =
                    contactRecord.Id,

                Christmas_Form_Sent_Count__c =
                    0,

                Wishlist_Reminder_Emails_Enabled__c =
                    false
            );

        insert caseRecord;

        EmailTemplate templateRecord = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName =
                'Bulk_Wishlist_Test_Template'
            LIMIT 1
        ];

        BulkWishlistEmailController.Request request =
            new BulkWishlistEmailController.Request();

        request.caseIds =
            new List<String>{
                caseRecord.Id
            };

        request.templateId =
            templateRecord.Id;

        Test.startTest();

        BulkWishlistEmailController.sendWishlistEmails(
            new List<
                BulkWishlistEmailController.Request
            >{
                request
            }
        );

        Test.stopTest();

        Case refreshedCase = [
            SELECT
                Christmas_Form_Sent_Count__c,
                Wishlist_Reminder_Emails_Enabled__c
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
    }

    @IsTest
    static void missingContactEmailTest() {

        Account accountRecord =
            new Account(
                Name =
                    'Missing Email Household'
            );

        insert accountRecord;

        Contact contactRecord =
            new Contact(
                FirstName =
                    'No',

                LastName =
                    'Email',

                AccountId =
                    accountRecord.Id
            );

        insert contactRecord;

        Case caseRecord =
            new Case(
                Subject =
                    'Missing Email Test',

                Status =
                    'New',

                Origin =
                    'Web',

                RecordTypeId =
                    getCaseRecordTypeId(
                        'Christmas_Application'
                    ),

                AccountId =
                    accountRecord.Id,

                ContactId =
                    contactRecord.Id,

                Christmas_Form_Sent_Count__c =
                    0,

                Wishlist_Reminder_Emails_Enabled__c =
                    false
            );

        insert caseRecord;

        EmailTemplate templateRecord = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName =
                'Bulk_Wishlist_Test_Template'
            LIMIT 1
        ];

        BulkWishlistEmailController.Request request =
            new BulkWishlistEmailController.Request();

        request.caseIds =
            new List<String>{
                caseRecord.Id
            };

        request.templateId =
            templateRecord.Id;

        Test.startTest();

        BulkWishlistEmailController.sendWishlistEmails(
            new List<
                BulkWishlistEmailController.Request
            >{
                request
            }
        );

        Test.stopTest();
    }

    @IsTest
    static void nonChristmasCaseIsSkippedTest() {

        Account accountRecord =
            new Account(
                Name =
                    'General Assistance Household'
            );

        insert accountRecord;

        Contact contactRecord =
            new Contact(
                FirstName =
                    'General',

                LastName =
                    'Applicant',

                Email =
                    'general@example.com',

                AccountId =
                    accountRecord.Id
            );

        insert contactRecord;

        Case caseRecord =
            new Case(
                Subject =
                    'General Assistance Test',

                Status =
                    'New',

                Origin =
                    'Web',

                RecordTypeId =
                    getCaseRecordTypeId(
                        'Assistance_Application'
                    ),

                AccountId =
                    accountRecord.Id,

                ContactId =
                    contactRecord.Id
            );

        insert caseRecord;

        EmailTemplate templateRecord = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName =
                'Bulk_Wishlist_Test_Template'
            LIMIT 1
        ];

        BulkWishlistEmailController.Request request =
            new BulkWishlistEmailController.Request();

        request.caseIds =
            new List<String>{
                caseRecord.Id
            };

        request.templateId =
            templateRecord.Id;

        Test.startTest();

        BulkWishlistEmailController.sendWishlistEmails(
            new List<
                BulkWishlistEmailController.Request
            >{
                request
            }
        );

        Test.stopTest();
    }

    @IsTest
    static void emptySelectionTest() {

        BulkWishlistEmailController.Request request =
            new BulkWishlistEmailController.Request();

        request.caseIds =
            new List<String>();

        request.templateId =
            null;

        Test.startTest();

        BulkWishlistEmailController.sendWishlistEmails(
            new List<
                BulkWishlistEmailController.Request
            >{
                request
            }
        );

        Test.stopTest();
    }
}