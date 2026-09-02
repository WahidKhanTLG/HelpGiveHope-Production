@isTest
public class HouseholdShoppingControllerTest {

    @isTest
    static void testHouseholdShoppingController() {
        // ---------- STEP 1: Create Account ----------
        Account acc = new Account(Name = 'Test Household');
        insert acc;
		
        // ----------  Create Program ----------
        pmdm__Program__c program = new pmdm__Program__c(
            Name = 'Test Program',
            pmdm__Status__c = 'Planned'
        );
        insert program;
        
        // ---------- STEP 2: Create Service ----------
        pmdm__Service__c service = new pmdm__Service__c(
            Name = 'Test Service',
            Category__c = 'Bed',
            Subcategory__c = 'Twin',
            pmdm__Program__c = program.Id
        );
        insert service;

        // ---------- STEP 3: Create Service Delivery ----------
        pmdm__ServiceDelivery__c del = new pmdm__ServiceDelivery__c(
            Name = 'Test Delivery',
            pmdm__Account__c = acc.Id,
            pmdm__Service__c = service.Id
        );
        insert del;

        // ---------- STEP 4: Create Contact ----------
        Contact con = new Contact(
            LastName = 'Test Child',
            AccountId = acc.Id,
            GenderIdentity = 'Male'
        );
        insert con;

        // ---------- STEP 5: Create Products ----------
        Product2 prod1 = new Product2(Name = 'Gift Products', IsActive = true);
        Product2 prod2 = new Product2(Name = 'Child Clothes', IsActive = true);
        insert new List<Product2>{ prod1, prod2 };

        // ✅ STEP 6: Add Standard Pricebook Entries (required before custom pricebook)
        Id stdPricebookId = Test.getStandardPricebookId();

        PricebookEntry stdPbe1 = new PricebookEntry(
            Pricebook2Id = stdPricebookId,
            Product2Id = prod1.Id,
            UnitPrice = 100,
            IsActive = true
        );
        PricebookEntry stdPbe2 = new PricebookEntry(
            Pricebook2Id = stdPricebookId,
            Product2Id = prod2.Id,
            UnitPrice = 200,
            IsActive = true
        );
        insert new List<PricebookEntry>{ stdPbe1, stdPbe2 };

        // ✅ STEP 7: Create Custom Pricebook and Entries
        Pricebook2 pb = new Pricebook2(Name = 'Custom Pricebook', IsActive = true);
        insert pb;

        PricebookEntry pbe1 = new PricebookEntry(
            Product2Id = prod1.Id,
            Pricebook2Id = pb.Id,
            UnitPrice = 100,
            IsActive = true
        );
        PricebookEntry pbe2 = new PricebookEntry(
            Product2Id = prod2.Id,
            Pricebook2Id = pb.Id,
            UnitPrice = 200,
            IsActive = true
        );
        insert new List<PricebookEntry>{ pbe1, pbe2 };

        // ---------- STEP 8: Create Opportunity ----------
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Pricebook2Id = pb.Id // ✅ Link custom pricebook to opp
        );
        insert opp;

        // ---------- STEP 9: Create OpportunityLineItems ----------
        OpportunityLineItem oli1 = new OpportunityLineItem(
            OpportunityId = opp.Id,
            PricebookEntryId = pbe1.Id,
            Quantity = 1,
            TotalPrice = 100,
            Contact__c = con.Id,
            Name__c = 'Gift Item'
        );
        OpportunityLineItem oli2 = new OpportunityLineItem(
            OpportunityId = opp.Id,
            PricebookEntryId = pbe2.Id,
            Quantity = 2,
            TotalPrice = 200,
            Contact__c = con.Id,
            Name__c = 'Child Clothes'
        );
        insert new List<OpportunityLineItem>{ oli1, oli2 };

        // ---------- STEP 10: Call the Controller ----------
        Test.startTest();
        ApexPages.StandardController stdCtrl = new ApexPages.StandardController(acc);
        HouseholdShoppingController ctrl = new HouseholdShoppingController(stdCtrl);
        Test.stopTest();

        // ---------- STEP 11: Verify Controller Results ----------
        System.assertNotEquals(null, ctrl.acct, 'Account should be initialized');
        System.assert(ctrl.deliveryList.size() > 0, 'Delivery list should not be empty');
        System.assert(ctrl.serviceList.size() > 0, 'Service list should not be empty');
        System.assert(ctrl.oppList.size() > 0, 'Opportunity list should not be empty');
        System.assert(ctrl.oppContactMap.size() > 0, 'OppContactMap should not be empty');
    }
}