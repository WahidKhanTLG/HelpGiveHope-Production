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
        Contact applicant = new Contact(FirstName = 'John', LastName = 'Doe', Email = 'john.doe@example.com');
        TLG_LandLord__c landlord = new TLG_LandLord__c(Name = 'Test Landlord');
        Case assistanceCase = new Case(
            Status = 'New',
            Origin = 'Web',
            Subject = 'General Assistance Application',
            Assistance_Type__c = 'General Assistance'
        );
        
        List<YearRoundAssistanceFormController.ChildPayload> children = new List<YearRoundAssistanceFormController.ChildPayload>();
        Contact childContact = new Contact(FirstName = 'Child1', LastName = 'Doe');
        YearRoundAssistanceFormController.ChildPayload childPayload = new YearRoundAssistanceFormController.ChildPayload();
        childPayload.child = childContact;
        childPayload.relationshipWithApplicant = 'Child';
        children.add(childPayload);

        List<YearRoundAssistanceFormController.AdultPayload> adults = new List<YearRoundAssistanceFormController.AdultPayload>();
        Contact adultContact = new Contact(FirstName = 'Adult1', LastName = 'Doe');
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
                'Email' => 'jane.noel.recordtype@example.com'
            },
            'children' => new List<Object>(),
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
}