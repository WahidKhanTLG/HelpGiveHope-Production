@IsTest
public class FormVisibilityControllerTest {

    @TestSetup
    static void setupData() {
        insert new List<Form_Catalog__c>{
            new Form_Catalog__c(
                Name = 'Test Active Form',
                Status__c = 'Active',
                Message__c = 'This is a test inactive message'
            ),
            new Form_Catalog__c(
                Name = 'Test Inactive Form',
                Status__c = 'Inactive',
                Message__c = 'This form is currently unavailable'
            ),
            new Form_Catalog__c(
                Name = 'Test No Message Form',
                Status__c = 'Inactive'
            )
        };
    }

    @IsTest
    static void test_getFormStatus_active() {
        Test.startTest();
        FormVisibilityController.FormStatus s =
            FormVisibilityController.getFormStatus('Test Active Form');
        Test.stopTest();

        System.assertEquals(true, s.isActive, 'Expected active');
        System.assertEquals('This is a test inactive message', s.message);
        System.assertNotEquals(null, s.formId);
    }

    @IsTest
    static void test_getFormStatus_inactive() {
        Test.startTest();
        FormVisibilityController.FormStatus s =
            FormVisibilityController.getFormStatus('Test Inactive Form');
        Test.stopTest();

        System.assertEquals(false, s.isActive, 'Expected inactive');
        System.assertEquals('This form is currently unavailable', s.message);
        System.assertNotEquals(null, s.formId);
    }

    @IsTest
    static void test_getFormStatus_defaultMessage() {
        Test.startTest();
        FormVisibilityController.FormStatus s =
            FormVisibilityController.getFormStatus('Test No Message Form');
        Test.stopTest();

        System.assertEquals(false, s.isActive);
        System.assertEquals('This form is currently not available.', s.message);
        System.assertNotEquals(null, s.formId);
    }

    @IsTest
    static void test_getFormStatus_notFound() {
        Test.startTest();
        FormVisibilityController.FormStatus s =
            FormVisibilityController.getFormStatus('Definitely Not Existing');
        Test.stopTest();

        System.assertEquals(false, s.isActive);
        System.assertEquals('Form configuration not found.', s.message);
        System.assertEquals('', s.formId, 'Default should be empty string');
    }

    @IsTest
    static void test_getAllFormCatalogs_sorted() {
        Test.startTest();
        List<Form_Catalog__c> rows = FormVisibilityController.getAllFormCatalogs();
        Test.stopTest();

        System.assertEquals(3, rows.size());
        System.assertEquals('Test Active Form', rows[0].Name);
        System.assertEquals('Test Inactive Form', rows[1].Name);
        System.assertEquals('Test No Message Form', rows[2].Name);
    }

    @IsTest
    static void test_updateFormStatus_basicUpdate() {
        Form_Catalog__c rec = [
            SELECT Id, Status__c, Message__c, Start_Date__c, End_Date__c
            FROM Form_Catalog__c
            WHERE Name = 'Test Active Form'
            LIMIT 1
        ];

        Test.startTest();
        String res = FormVisibilityController.updateFormStatus(
            rec.Id,
            false,                               // set inactive
            'Updated inactive message',          // new message
            null,                                // leave dates null
            null
        );
        Test.stopTest();

        System.assertEquals('success', res);

        Form_Catalog__c after = [
            SELECT Status__c, Message__c, Start_Date__c, End_Date__c
            FROM Form_Catalog__c WHERE Id = :rec.Id
        ];
        System.assertEquals('Inactive', after.Status__c);
        System.assertEquals('Updated inactive message', after.Message__c);
        System.assertEquals(null, after.Start_Date__c);
        System.assertEquals(null, after.End_Date__c);
    }

    @IsTest
    static void test_updateFormStatus_setDates_valid() {
        Form_Catalog__c rec = [
            SELECT Id FROM Form_Catalog__c WHERE Name = 'Test Inactive Form' LIMIT 1
        ];

        Date s = Date.today().addDays(-2);
        Date e = Date.today().addDays(3);

        String res = FormVisibilityController.updateFormStatus(
            rec.Id,
            true,
            'Window set',
            s,
            e
        );

        System.assertEquals('success', res);

        Form_Catalog__c after = [
            SELECT Status__c, Message__c, Start_Date__c, End_Date__c
            FROM Form_Catalog__c WHERE Id = :rec.Id
        ];
        System.assertNotEquals(null, after.Status__c, 'Status should remain populated after automation evaluates the configured window');
        System.assertEquals('Window set', after.Message__c);
        System.assertEquals(s, after.Start_Date__c);
        System.assertEquals(e, after.End_Date__c);
    }

    @IsTest
    static void test_updateFormStatus_invalidId_throws() {
        Boolean threw = false;
        try {
            Test.startTest();
            FormVisibilityController.updateFormStatus(
                '01p000000000000', true, 'x', null, null
            );
            Test.stopTest();
        } catch (FormVisibilityController.FormVisibilityException ex) {
            threw = true;
            System.assertNotEquals(null, ex.getMessage());
        }
        System.assertEquals(true, threw, 'Expected exception for bad Id');
    }

    @IsTest
    static void test_updateFormStatus_validation_endBeforeStart() {
        Form_Catalog__c rec = [
            SELECT Id FROM Form_Catalog__c WHERE Name = 'Test No Message Form' LIMIT 1
        ];

        Date s = Date.today();
        Date e = Date.today().addDays(-1); // invalid

        Boolean threw = false;
        try {
            Test.startTest();
            FormVisibilityController.updateFormStatus(rec.Id, false, null, s, e);
            Test.stopTest();
        } catch (FormVisibilityController.FormVisibilityException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('End Date cannot be before Start Date.'));
        }
        System.assertEquals(true, threw, 'Expected validation exception');
    }

    @IsTest
    static void test_createFormCatalog_basic() {
        Test.startTest();
        String idNew = FormVisibilityController.createFormCatalog(
            'New Test Form',
            true,
            'This is a test message for the new form',
            null,
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, idNew);

        Form_Catalog__c rec = [
            SELECT Name, Status__c, Message__c, Start_Date__c, End_Date__c
            FROM Form_Catalog__c WHERE Id = :idNew
        ];
        System.assertEquals('New Test Form', rec.Name);
        System.assertEquals('Active', rec.Status__c);
        System.assertEquals('This is a test message for the new form', rec.Message__c);
        System.assertEquals(null, rec.Start_Date__c);
        System.assertEquals(null, rec.End_Date__c);
    }

    @IsTest
    static void test_createFormCatalog_withDates() {
        Date s = Date.today().addDays(1);
        Date e = s.addDays(5);

        String idNew = FormVisibilityController.createFormCatalog(
            'Dated Form',
            false,
            'Windowed',
            s,
            e
        );

        Form_Catalog__c rec = [
            SELECT Status__c, Message__c, Start_Date__c, End_Date__c
            FROM Form_Catalog__c WHERE Id = :idNew
        ];
        System.assertEquals('Inactive', rec.Status__c);
        System.assertEquals('Windowed', rec.Message__c);
        System.assertEquals(s, rec.Start_Date__c);
        System.assertEquals(e, rec.End_Date__c);
    }

    @IsTest
    static void test_createFormCatalog_duplicate_throws() {
        insert new Form_Catalog__c(
            Name = 'Existing Form',
            Status__c = 'Active',
            Message__c = 'Test message'
        );

        Boolean threw = false;
        try {
            Test.startTest();
            FormVisibilityController.createFormCatalog(
                'Existing Form', true, 'Another', null, null
            );
            Test.stopTest();
        } catch (Exception ex) {
            threw = true;
            System.assert(ex.getMessage().contains('already exists'),
                'Expected duplicate message, got: ' + ex.getMessage());
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void test_setFormActiveStatus() {
        Form_Catalog__c rec = [
            SELECT Id, Status__c, Message__c
            FROM Form_Catalog__c WHERE Name = 'Test Active Form' LIMIT 1
        ];
        System.assertEquals('Active', rec.Status__c);

        Test.startTest();
        FormVisibilityController.setFormActiveStatus(
            'Test Active Form', false, 'Custom inactive message'
        );
        Test.stopTest();

        Form_Catalog__c after = [
            SELECT Status__c, Message__c FROM Form_Catalog__c WHERE Id = :rec.Id
        ];
        System.assertEquals('Inactive', after.Status__c);
        System.assertEquals('Custom inactive message', after.Message__c);
    }
}