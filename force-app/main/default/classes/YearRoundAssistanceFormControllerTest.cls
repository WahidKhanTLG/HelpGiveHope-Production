@IsTest
public class YearRoundAssistanceFormControllerTest {

    @IsTest
    static void testGetPicklistValues() {
        Test.startTest();
        Map<String, List<YearRoundAssistanceFormController.PickListOption>> picklistValues = YearRoundAssistanceFormController.getPicklistValues();
        Test.stopTest();

        System.assertNotEquals(null, picklistValues);
        System.assert(picklistValues.containsKey('TLG_Employed_or_unemployed__c'), 'The map should contain the TLG_Employed_or_unemployed__c field');
    }

    @IsTest
    static void testGetPovertyGuidelines() {
        TLG_Poverty_Guideline__c povertyGuideline = new TLG_Poverty_Guideline__c(
            Name = 'Test Guideline',
            TLG_Year__c = '2024',
            TLG_Household_Size__c = 4,
            TLG_Income__c = 50000,
            TLG_External_Id__c = '20244'
        );
        insert povertyGuideline;

        Test.startTest();
        List<TLG_Poverty_Guideline__c> guidelines = YearRoundAssistanceFormController.getPovertyGuidelines();
        Test.stopTest();

        System.assertNotEquals(0, guidelines.size(), 'At least one poverty guideline record should be returned');
    }

    @IsTest
    static void testSave() {
        Account account = new Account(Name = 'Test Account', BillingState = 'Missouri');
        Contact applicant = new Contact(FirstName = 'John', LastName = 'Doe', Email = 'john.doe@example.com', Birthdate = Date.today().addYears(-30), TLG_Social_Security_Number__c = 111223333);
        TLG_LandLord__c landlord = new TLG_LandLord__c(Name = 'Test Landlord');
        Case assistanceCase = new Case(
            Status = 'New',
            Origin = 'Web',
            Subject = 'General Assistance Application',
            Assistance_Type__c = 'General Assistance'
        );
        
        List<YearRoundAssistanceFormController.ChildPayload> children = new List<YearRoundAssistanceFormController.ChildPayload>();
        Contact childContact = new Contact(FirstName = 'Child1', LastName = 'Doe', Birthdate = Date.today().addYears(-8), TLG_Social_Security_Number__c = 222334444);
        YearRoundAssistanceFormController.ChildPayload childPayload = new YearRoundAssistanceFormController.ChildPayload();
        childPayload.child = childContact;
        childPayload.relationshipWithApplicant = 'Child';
        children.add(childPayload);

        List<YearRoundAssistanceFormController.AdultPayload> adults = new List<YearRoundAssistanceFormController.AdultPayload>();
        Contact adultContact = new Contact(FirstName = 'Adult1', LastName = 'Doe', Birthdate = Date.today().addYears(-40), TLG_Social_Security_Number__c = 333445555);
        YearRoundAssistanceFormController.AdultPayload adultPayload = new YearRoundAssistanceFormController.AdultPayload();
        adultPayload.adult = adultContact;
        adultPayload.relationshipWithApplicant = 'Spouse';
        adultPayload.customRelationshipWithApplicant = 'Custom Spouse';
        adults.add(adultPayload);

        YearRoundAssistanceFormController.Payload payload = new YearRoundAssistanceFormController.Payload();
        payload.account = account;
        payload.assistanceCase = assistanceCase;
        payload.applicant = applicant;
        payload.children = children;
        payload.adults = adults;
        payload.landlord = landlord;

        String payloadJson = JSON.serialize(payload);

        Test.startTest();
        String result = YearRoundAssistanceFormController.save(payloadJson);
        Test.stopTest();

        System.assertEquals('OK', result, 'The save method should return OK');

        Contact savedApplicant = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Email = 'john.doe@example.com'
            LIMIT 1
        ];

        Account savedAccount = [
            SELECT Id, npe01__One2OneContact__c
            FROM Account
            WHERE Id = :savedApplicant.AccountId
            LIMIT 1
        ];
        System.assertNotEquals(null, savedAccount.Id, 'Expected account to be created');

        System.assertEquals(savedAccount.Id, savedApplicant.AccountId, 'Applicant should be linked to the new household account');
        System.assertEquals(savedApplicant.Id, savedAccount.npe01__One2OneContact__c, 'One-to-one contact should be updated to the applicant');

        Case savedCase = [
            SELECT Id, AccountId, ContactId, Subject, Assistance_Type__c
            FROM Case
            WHERE AccountId = :savedAccount.Id
            AND ContactId = :savedApplicant.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(savedAccount.Id, savedCase.AccountId, 'Assistance Case should be linked to the new household account');
        System.assertEquals(savedApplicant.Id, savedCase.ContactId, 'Assistance Case should be linked to the primary applicant');
        System.assertEquals('General Assistance', savedCase.Assistance_Type__c, 'Assistance Case should retain submitted assistance type');

        TLG_LandLord__c savedLandlord = [
            SELECT Id, TLG_Contact__c, Case__c
            FROM TLG_LandLord__c
            WHERE Name = 'Test Landlord'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(savedApplicant.Id, savedLandlord.TLG_Contact__c, 'Landlord should be linked to the applicant');
        System.assertEquals(savedCase.Id, savedLandlord.Case__c, 'Landlord should be linked to the assistance case');

        System.assertEquals(
            2,
            [SELECT COUNT() FROM npe4__Relationship__c WHERE npe4__Contact__c = :savedApplicant.Id],
            'Expected one child and one adult relationship for the applicant'
        );

    }

    @IsTest
    static void testSave_withCaseRecordTypeDeveloperNamePayload() {
        Map<String, Object> payload = new Map<String, Object>{
            'account' => new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Account' },
                'Name' => 'RecordType Payload Household',
                'BillingState' => 'Missouri'
            },
            'assistanceCase' => new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Case' },
                'Subject' => 'RecordType Payload Case',
                'Status' => 'New',
                'Assistance_Type__c' => 'Christmas Assistance',
                'RecordType' => new Map<String, Object>{
                    'DeveloperName' => 'Assistance_Application'
                }
            },
            'applicant' => new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Contact' },
                'FirstName' => 'Jane',
                'LastName' => 'Noel',
                'Email' => 'jane.noel.recordtype@example.com',
                'Birthdate' => String.valueOf(Date.today().addYears(-35)),
                'TLG_Social_Security_Number__c' => 444556666
            },
            'children' => new List<Object>{
                new Map<String, Object>{
                    'child' => new Map<String, Object>{
                        'attributes' => new Map<String, Object>{ 'type' => 'Contact' },
                        'FirstName' => 'Ava',
                        'LastName' => 'Noel',
                        'Birthdate' => String.valueOf(Date.today().addYears(-6)),
                        'TLG_Social_Security_Number__c' => 444556667
                    },
                    'relationshipWithApplicant' => 'Daughter'
                }
            },
            'adults' => new List<Object>(),
            'landlord' => null
        };

        Test.startTest();
        String result = YearRoundAssistanceFormController.save(JSON.serialize(payload));
        Test.stopTest();

        System.assertEquals('OK', result, 'The save method should resolve RecordType by DeveloperName and return OK');

        Case savedCase = [
            SELECT Id, RecordType.DeveloperName, Subject
            FROM Case
            WHERE Subject = 'RecordType Payload Case'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('Assistance_Application', savedCase.RecordType.DeveloperName, 'Expected the Case record type to be resolved from DeveloperName');
    }

    private static YearRoundAssistanceFormController.Payload buildPayload(
        String lastName, Decimal applicantSsn, Decimal childSsn, Decimal adultSsn, String street
    ) {
        YearRoundAssistanceFormController.Payload payload = new YearRoundAssistanceFormController.Payload();
        payload.account = new Account(Name = lastName + ' Household', BillingStreet = street, BillingState = 'Missouri');
        payload.applicant = new Contact(
            FirstName = 'Pat', LastName = lastName, Email = lastName.toLowerCase() + '.pat@example.com',
            Birthdate = Date.today().addYears(-33), TLG_Social_Security_Number__c = applicantSsn
        );
        payload.assistanceCase = new Case(Status = 'New', Origin = 'Web', Subject = lastName + ' Application', Assistance_Type__c = 'General Assistance');
        payload.children = new List<YearRoundAssistanceFormController.ChildPayload>();
        payload.adults = new List<YearRoundAssistanceFormController.AdultPayload>();
        if (childSsn != null) {
            YearRoundAssistanceFormController.ChildPayload cp = new YearRoundAssistanceFormController.ChildPayload();
            cp.child = new Contact(FirstName = 'Kid', LastName = lastName, Birthdate = Date.today().addYears(-7), TLG_Social_Security_Number__c = childSsn);
            cp.relationshipWithApplicant = 'Son';
            payload.children.add(cp);
        }
        if (adultSsn != null) {
            YearRoundAssistanceFormController.AdultPayload ap = new YearRoundAssistanceFormController.AdultPayload();
            ap.adult = new Contact(FirstName = 'Sam', LastName = lastName, Birthdate = Date.today().addYears(-36), TLG_Social_Security_Number__c = adultSsn);
            ap.relationshipWithApplicant = 'Spouse';
            payload.adults.add(ap);
        }
        return payload;
    }

    @IsTest
    static void testSave_existingHouseholdIsUpdatedWhenSsnsMatch() {
        String first = YearRoundAssistanceFormController.save(JSON.serialize(buildPayload('Reuse', 120130140, 120130141, 120130142, '1 First St')));
        System.assertEquals('OK', first, 'First submission should create the household');

        Test.startTest();
        String second = YearRoundAssistanceFormController.save(JSON.serialize(buildPayload('Reuse', 120130140, 120130141, 120130142, '2 Second St')));
        Test.stopTest();

        System.assertEquals('OK', second, 'Second submission with the same SSNs should update the existing household');
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE TLG_Social_Security_Number__c = 120130140], 'Applicant should not be duplicated');
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE TLG_Social_Security_Number__c = 120130141], 'Child should not be duplicated');
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE TLG_Social_Security_Number__c = 120130142], 'Adult should not be duplicated');
        Contact applicant = [SELECT AccountId FROM Contact WHERE TLG_Social_Security_Number__c = 120130140 LIMIT 1];
        System.assertEquals('2 Second St', [SELECT BillingStreet FROM Account WHERE Id = :applicant.AccountId].BillingStreet, 'Household address should be updated');
        System.assertEquals(2, [SELECT COUNT() FROM Case WHERE AccountId = :applicant.AccountId], 'Each submission should create a Case');
    }

    @IsTest
    static void testSave_requestValidationMessages() {
        Account acc = new Account(Name = 'Existing Household');
        insert acc;
        Contact existing = new Contact(FirstName = 'Old', LastName = 'Record', AccountId = acc.Id, Birthdate = Date.today().addYears(-40));
        insert existing;

        System.assertNotEquals('OK', YearRoundAssistanceFormController.save(''), 'Blank payload is rejected');
        System.assertNotEquals('OK', YearRoundAssistanceFormController.save('x'.repeat(200001)), 'Oversized payload is rejected');
        System.assertNotEquals('OK', YearRoundAssistanceFormController.save('{}'), 'Payload without account/applicant is rejected');
        System.assertNotEquals('OK', YearRoundAssistanceFormController.save('not json'), 'Malformed JSON is rejected');

        YearRoundAssistanceFormController.Payload reuse = buildPayload('Guard', 120130150, 120130153, null, '3 Third St');
        reuse.reuseAccountId = acc.Id;
        System.assertNotEquals('OK', YearRoundAssistanceFormController.save(JSON.serialize(reuse)), 'Reuse without record versions is rejected');

        YearRoundAssistanceFormController.Payload withApplicantId = buildPayload('Guard', 120130150, 120130154, null, '3 Third St');
        withApplicantId.applicant.Id = existing.Id;
        System.assertNotEquals('OK', YearRoundAssistanceFormController.save(JSON.serialize(withApplicantId)), 'Existing applicant Id must use the reuse path');

        YearRoundAssistanceFormController.Payload withChildId = buildPayload('Guard', 120130150, 120130151, null, '3 Third St');
        withChildId.children[0].child.Id = existing.Id;
        System.assertNotEquals('OK', YearRoundAssistanceFormController.save(JSON.serialize(withChildId)), 'Child Id must use the reuse path');

        YearRoundAssistanceFormController.Payload withAdultId = buildPayload('Guard', 120130150, 120130155, 120130152, '3 Third St');
        withAdultId.adults[0].adult.Id = existing.Id;
        System.assertNotEquals('OK', YearRoundAssistanceFormController.save(JSON.serialize(withAdultId)), 'Adult Id must use the reuse path');

        YearRoundAssistanceFormController.Payload tooMany = buildPayload('Many', 120130160, null, null, '4 Fourth St');
        for (Integer i = 0; i < 51; i++) {
            YearRoundAssistanceFormController.ChildPayload cp = new YearRoundAssistanceFormController.ChildPayload();
            cp.child = new Contact(FirstName = 'Kid' + i, LastName = 'Many', Birthdate = Date.today().addYears(-5));
            tooMany.children.add(cp);
        }
        System.assertNotEquals('OK', YearRoundAssistanceFormController.save(JSON.serialize(tooMany)), 'Households over the member limit need assisted processing');
        System.assertEquals(0, [SELECT COUNT() FROM Contact WHERE LastName = 'Guard' OR LastName = 'Many'], 'No records should be saved by rejected requests');
    }

    @IsTest
    static void testSave_requiresAtLeastOneChild() {
        String expected = 'Please add at least one child to the household before submitting.';

        YearRoundAssistanceFormController.Payload noChildren = buildPayload('Nokids', 120130200, null, 120130201, '10 Tenth St');
        System.assertEquals(expected, YearRoundAssistanceFormController.save(JSON.serialize(noChildren)), 'A new application without a child is rejected');

        noChildren.children = null;
        System.assertEquals(expected, YearRoundAssistanceFormController.save(JSON.serialize(noChildren)), 'A missing children list is rejected');

        Account acc = new Account(Name = 'Childless Household');
        insert acc;
        YearRoundAssistanceFormController.Payload reuse = buildPayload('Nokids', 120130200, null, null, '10 Tenth St');
        reuse.reuseAccountId = acc.Id;
        System.assertEquals(expected, YearRoundAssistanceFormController.save(JSON.serialize(reuse)), 'A household reuse without a child is rejected');

        System.assertEquals(0, [SELECT COUNT() FROM Contact WHERE LastName = 'Nokids'], 'No records should be saved when the child requirement fails');
    }

    @IsTest
    static void testSave_ssnValidationMessages() {
        System.assertNotEquals('OK', YearRoundAssistanceFormController.save(JSON.serialize(buildPayload('Nossn', null, 120130171, null, '5 Fifth St'))), 'Applicant SSN is required');
        System.assertNotEquals('OK', YearRoundAssistanceFormController.save(JSON.serialize(buildPayload('Dupe', 120130170, 120130170, null, '6 Sixth St'))), 'Duplicate SSNs in one household are rejected');
        System.assertNotEquals('OK', YearRoundAssistanceFormController.save(JSON.serialize(buildPayload('Long', 1234567890, 120130172, null, '7 Seventh St'))), 'SSNs longer than 9 digits are rejected');
        System.assertEquals(0, [SELECT COUNT() FROM Contact WHERE LastName IN ('Nossn', 'Dupe', 'Long')], 'No records should be saved when SSN validation fails');
    }

    @IsTest
    static void testSave_ssnBelongingToAnotherHouseholdOrManyContacts() {
        Account other = new Account(Name = 'Other Household');
        insert other;
        insert new List<Contact>{
            new Contact(FirstName = 'Kid', LastName = 'Other', AccountId = other.Id, Birthdate = Date.today().addYears(-6), TLG_Social_Security_Number__c = 120130181),
            new Contact(FirstName = 'Sam', LastName = 'Other', AccountId = other.Id, Birthdate = Date.today().addYears(-38), TLG_Social_Security_Number__c = 120130182),
            new Contact(FirstName = 'Twin', LastName = 'One', AccountId = other.Id, Birthdate = Date.today().addYears(-30), TLG_Social_Security_Number__c = 120130183),
            new Contact(FirstName = 'Twin', LastName = 'Two', AccountId = other.Id, Birthdate = Date.today().addYears(-31), TLG_Social_Security_Number__c = 120130183)
        };

        String childResult = YearRoundAssistanceFormController.save(JSON.serialize(buildPayload('Mover', 120130180, 120130181, null, '8 Eighth St')));
        String adultResult = YearRoundAssistanceFormController.save(JSON.serialize(buildPayload('Mover', 120130180, 120130184, 120130182, '8 Eighth St')));
        String manyResult = YearRoundAssistanceFormController.save(JSON.serialize(buildPayload('Mover', 120130183, 120130185, null, '8 Eighth St')));

        System.assertNotEquals('OK', childResult, 'A child SSN that belongs to another household is rejected');
        System.assertNotEquals('OK', adultResult, 'An adult SSN that belongs to another household is rejected');
        System.assertNotEquals('OK', manyResult, 'An applicant SSN matching several Contacts needs staff review');
        System.assertEquals(0, [SELECT COUNT() FROM Contact WHERE LastName = 'Mover'], 'No records should be saved by rejected requests');
    }

    @IsTest
    static void testSave_databaseErrorsRollBackEverything() {
        YearRoundAssistanceFormController.Payload payload = buildPayload('Broken', 120130190, 120130191, null, '9 Ninth St');
        payload.applicant.Email = 'not-an-email';

        String result = YearRoundAssistanceFormController.save(JSON.serialize(payload));

        System.assertNotEquals('OK', result, 'A DML failure should be reported to the caller');
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name = 'Broken Household'], 'The household insert should be rolled back');
        System.assertEquals(0, [SELECT COUNT() FROM Contact WHERE LastName = 'Broken'], 'The contact inserts should be rolled back');
    }
}