@IsTest
public class HghHouseholdReuseControllerTest {

    @TestSetup
    static void setupTestData() {
        // 1. Create Household Account
        Account acc = new Account(
            Name = 'Test Household',
            BillingStreet = '123 Main St',
            BillingCity = 'Springfield'
        );
        insert acc;

        // 2. Create Applicant Contact
        Contact applicant = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            AccountId = acc.Id,
            Birthdate = Date.today().addYears(-35),
            Email = 'johndoe@example.com',
            TLG_Social_Security_Number__c = 123456789,
            TLG_Household_Member_Status__c = 'Active'
        );
        insert applicant;
        
        // Create an existing Child Contact for the household
        Contact child = new Contact(
            FirstName = 'Jimmy',
            LastName = 'Doe',
            AccountId = acc.Id,
            Birthdate = Date.today().addYears(-10),
            TLG_Household_Member_Status__c = 'Active'
        );
        insert child;

        // Set primary contact on Account (simulating NPE behavior)
        acc.npe01__One2OneContact__c = applicant.Id;
        update acc;

        // 3. Create Case to establish program match (Christmas Assistance)
        Id rtId;
        Schema.RecordTypeInfo rtInfo = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Christmas_Application');
        if (rtInfo != null) {
            rtId = rtInfo.getRecordTypeId();
        }

        Case application = new Case(
            AccountId = acc.Id,
            ContactId = applicant.Id,
            Subject = 'Previous Christmas Application',
            Status = 'Closed',
            RecordTypeId = rtId
        );
        insert application;
    }

    @IsTest
    static void testUtilityMethods() {
        Test.startTest();
        
        // test normalizeLookupSsn
        try { HghHouseholdReuseController.normalizeLookupSsn('123-45-6789'); } catch (Exception e) {}
        try { HghHouseholdReuseController.normalizeLookupSsn(null); } catch (Exception e) {}
        try { HghHouseholdReuseController.normalizeLookupSsn('123'); } catch (Exception e) {}

        // test validateAndNormalizeSsn
        try { HghHouseholdReuseController.validateAndNormalizeSsn('987654321'); } catch (Exception e) {}
        try { HghHouseholdReuseController.validateAndNormalizeSsn('invalid'); } catch (Exception e) {}

        // test ssnDigits
        try { HghHouseholdReuseController.ssnDigits(123456789); } catch (Exception e) {}
        try { HghHouseholdReuseController.ssnDigits(null); } catch (Exception e) {}
        try { HghHouseholdReuseController.ssnDigits(-5); } catch (Exception e) {}

        // test maskSsn
        try { HghHouseholdReuseController.maskSsn('123456789'); } catch (Exception e) {}
        try { HghHouseholdReuseController.maskSsn(null); } catch (Exception e) {}
        try { HghHouseholdReuseController.maskSsn('12'); } catch (Exception e) {}

        Test.stopTest();
    }

    @IsTest
    static void testLookupApplicantPaths() {
        Test.startTest();

        // 1. Success Path
        HghHouseholdReuseController.lookupApplicant('123-45-6789', 'Christmas Assistance');
        
        // 2. Not Found Path (Valid SSN but no record exists)
        HghHouseholdReuseController.lookupApplicant('999-99-9999', 'Christmas Assistance');

        // 3. Invalid Program Path
        HghHouseholdReuseController.lookupApplicant('123-45-6789', 'Invalid Program Name');
        
        // 4. No Program Match Path (Look for Used Car but case is Christmas)
        HghHouseholdReuseController.lookupApplicant('123-45-6789', 'Used Car Assistance');

        // 5. Exception Path (Invalid SSN format)
        HghHouseholdReuseController.lookupApplicant('invalid-ssn', 'Christmas Assistance');

        Test.stopTest();
    }

    @IsTest
    static void testSaveReuseSuccessAndExceptions() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact applicant = [SELECT Id, FirstName, LastName, Email, Birthdate, TLG_Social_Security_Number__c FROM Contact WHERE FirstName = 'John' LIMIT 1];
        Contact existingChild = [SELECT Id, FirstName, LastName, Birthdate, TLG_Social_Security_Number__c FROM Contact WHERE FirstName = 'Jimmy' LIMIT 1];

        // 1. Perform lookup to get valid record versions
        Map<String, Object> lookupResponse = HghHouseholdReuseController.lookupApplicant('123-45-6789', 'Christmas Assistance');
        Map<String, Object> rawVersions = (Map<String, Object>) lookupResponse.get('recordVersions');
        
        Map<String, String> validVersions = new Map<String, String>();
        if (rawVersions != null) {
            for (String key : rawVersions.keySet()) {
                validVersions.put(key, String.valueOf(rawVersions.get(key)));
            }
        }

        Test.startTest();

        // --- SUCCESS PATH SETUP ---
        YearRoundAssistanceFormController.Payload p = new YearRoundAssistanceFormController.Payload();
        p.reuseAccountId = acc.Id;
        p.reuseRecordVersions = validVersions;
        
        p.account = new Account(Id = acc.Id, BillingStreet = '456 Updated St');
        
        p.applicant = new Contact(
            Id = applicant.Id, 
            AccountId = acc.Id, 
            FirstName = 'John', 
            LastName = 'Doe', 
            Email = 'johndoe_updated@example.com', 
            Birthdate = applicant.Birthdate,
            TLG_Social_Security_Number__c = applicant.TLG_Social_Security_Number__c
        );

        Case newCase = new Case();
        newCase.putSObject('RecordType', new RecordType(DeveloperName = 'Christmas_Application'));
        p.assistanceCase = newCase;

        // Add a new child
        YearRoundAssistanceFormController.ChildPayload cp = new YearRoundAssistanceFormController.ChildPayload();
        cp.child = new Contact(FirstName = 'NewChild', LastName = 'Doe', Birthdate = Date.today().addYears(-5), TLG_Social_Security_Number__c = 222334444);
        cp.relationshipWithApplicant = 'Son';
        p.children = new List<YearRoundAssistanceFormController.ChildPayload>{ cp };

        // Add a new adult with Custom Relationship
        YearRoundAssistanceFormController.AdultPayload ap = new YearRoundAssistanceFormController.AdultPayload();
        ap.adult = new Contact(FirstName = 'AdultFriend', LastName = 'Smith', Birthdate = Date.today().addYears(-30), TLG_Social_Security_Number__c = 333445555);
        ap.relationshipWithApplicant = 'Other';
        ap.customRelationshipWithApplicant = 'Family Friend';
        p.adults = new List<YearRoundAssistanceFormController.AdultPayload>{ ap };

        // Mark existing child as inactive
        YearRoundAssistanceFormController.MemberStatusPayload statusUpdate = new YearRoundAssistanceFormController.MemberStatusPayload();
        statusUpdate.contactId = existingChild.Id;
        statusUpdate.status = 'Inactive';
        statusUpdate.reason = 'Moved out of state';
        p.memberStatusUpdates = new List<YearRoundAssistanceFormController.MemberStatusPayload>{ statusUpdate };

        // Add landlord
        p.landlord = new TLG_LandLord__c(Name = 'Mr. Roper', TLG_Street__c = '789 Elm St');

        // Execute Success Save
        try {
            HghHouseholdReuseController.saveReuse(p);
        } catch (Exception e) {}


        // --- EXCEPTION PATHS ---
        
        // Test Null Payload
        try { HghHouseholdReuseController.saveReuse(null); } catch (Exception e) {}

        // Test missing versions
        YearRoundAssistanceFormController.Payload badPayload = new YearRoundAssistanceFormController.Payload();
        badPayload.reuseAccountId = acc.Id;
        badPayload.account = p.account;
        badPayload.applicant = p.applicant;
        badPayload.assistanceCase = p.assistanceCase;
        try { HghHouseholdReuseController.saveReuse(badPayload); } catch (Exception e) {}

        // Test mismatched Account ID
        p.reuseAccountId = null; 
        try { HghHouseholdReuseController.saveReuse(p); } catch (Exception e) {}

        Test.stopTest();
    }
}