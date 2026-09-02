@IsTest
private class HouseholdShoppingEmailControllerTest {

    /* ==========  TEST DATA  ========== */
    @testSetup
    static void makeData() {
        String sfx = String.valueOf(Datetime.now().getTime());

        // ACCOUNT
        Account acc = new Account(
            Name             = 'Test Family Account ' + sfx,
            Pickup_Status__c = 'Warehouse',
            Pickup_Date__c   = Date.today().addDays(7),
            External_ID__c   = 'ACC-' + sfx
        );
        insert acc;

        // CONTACT
        Contact con = new Contact(
            FirstName      = 'Test',
            LastName       = 'Family',
            AccountId      = acc.Id,
            Email          = 'test' + sfx + '@example.com',
            GenderIdentity = 'Female'
        );
        insert con;

        // OPPORTUNITY with CLOTHING and BIKES items
        Opportunity opp = new Opportunity(
            Name      = 'Test Opp ' + sfx,
            AccountId = acc.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Prospecting'
        );
        insert opp;

        // PRODUCTS - use exact names that match the filters in the main class
        Product2 p1 = new Product2(
            Name        = 'Child Clothes',
            ProductCode = 'CC_' + sfx,
            IsActive    = true
        );
        Product2 p2 = new Product2(
            Name        = 'Clothing Item',
            ProductCode = 'CI_' + sfx,
            IsActive    = true
        );
        Product2 p3 = new Product2(
            Name        = 'Gift Products',
            ProductCode = 'GP_' + sfx,
            IsActive    = true
        );
        insert new List<Product2>{ p1, p2, p3 };

        // PRICEBOOK ENTRIES
        Id stdPB = Test.getStandardPricebookId();

        PricebookEntry pbe1 = new PricebookEntry(
            Pricebook2Id     = stdPB,
            Product2Id       = p1.Id,
            UnitPrice        = 100,
            IsActive         = true,
            UseStandardPrice = false
        );
        PricebookEntry pbe2 = new PricebookEntry(
            Pricebook2Id     = stdPB,
            Product2Id       = p2.Id,
            UnitPrice        = 50,
            IsActive         = true,
            UseStandardPrice = false
        );
        PricebookEntry pbe3 = new PricebookEntry(
            Pricebook2Id     = stdPB,
            Product2Id       = p3.Id,
            UnitPrice        = 75,
            IsActive         = true,
            UseStandardPrice = false
        );
        insert new List<PricebookEntry>{ pbe1, pbe2, pbe3 };

        // OPP LINE ITEMS - bikes with Child Clothes, clothing with different size types
        insert new List<OpportunityLineItem>{
            // Bike items (with Bike_Size__c and Child Clothes product)
            createOLI(opp.Id, pbe1.Id, con.Id, null, null, null, 'Large'),
            // Clothing items with different size fields (using Clothing Item product)
            createOLI(opp.Id, pbe2.Id, con.Id, 'Medium', null, null, null),
            createOLI(opp.Id, pbe2.Id, con.Id, null, 'XL', null, null),
            createOLI(opp.Id, pbe2.Id, con.Id, null, null, 'Small', null),
            // Clothing item with no sizes
            createOLI(opp.Id, pbe2.Id, con.Id, null, null, null, null)
        };

        // OPTIONAL SERVICE DATA (only if managed package is present & createable)
        if (isObjectAccessible('pmdm__Service__c') &&
            isObjectAccessible('pmdm__ServiceDelivery__c')) {

            try {
                pmdm__Service__c s1 = new pmdm__Service__c(
                    Category__c    = 'Furniture',
                    Subcategory__c = 'Sofa',
                    Quantity__c    = 1,
                    Gender__c      = 'Female'
                );
                pmdm__Service__c s2 = new pmdm__Service__c(
                    Category__c           = 'Furniture',
                    Subcategory__c        = 'Other',
                    Quantity__c           = 2,
                    Furniture_User_Entry__c = 'Custom ' + sfx,
                    Gender__c             = 'Female'
                );
                insert new List<pmdm__Service__c>{ s1, s2 };

                insert new List<pmdm__ServiceDelivery__c>{
                    new pmdm__ServiceDelivery__c(
                        pmdm__Account__c = acc.Id,
                        pmdm__Service__c = s1.Id
                    ),
                    new pmdm__ServiceDelivery__c(
                        pmdm__Account__c = acc.Id,
                        pmdm__Service__c = s2.Id
                    )
                };
            } catch (Exception e) {
                // ignore any package-specific validation in tests
            }
        }
    }

    /* ==========  TEST METHODS  ========== */

    @IsTest
    static void testConstructor() {
        Test.startTest();
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl, 'Controller should be instantiated');
    }

   // @IsTest
    static void testGetAccount() {
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        ctrl.accountId = acc.Id;

        Test.startTest();
        Account result = ctrl.getAccount();
        Test.stopTest();

        System.assertEquals(acc.Id, result.Id, 'Should return correct account');
        System.assertEquals(acc.Name, result.Name, 'Account name should match');
    }

    @IsTest
    static void testGetAccountCached() {
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        ctrl.accountId = acc.Id;

        Test.startTest();
        Account result1 = ctrl.getAccount();
        Account result2 = ctrl.getAccount();
        Test.stopTest();

        System.assertEquals(result1.Id, result2.Id, 'Should return cached account on second call');
    }

    @IsTest
    static void testGetAccountNullId() {
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();

        Test.startTest();
        Account result = ctrl.getAccount();
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when accountId is null');
    }

    @IsTest
    static void testGetServices() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        ctrl.accountId = acc.Id;

        Test.startTest();
        List<HouseholdShoppingEmailController.ServiceWrapper> services = ctrl.getServices();
        Test.stopTest();

        System.assertNotEquals(null, services, 'Services list should not be null');
        // Service data depends on pmdm package availability
    }

    @IsTest
    static void testGetServicesNullAccountId() {
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();

        Test.startTest();
        List<HouseholdShoppingEmailController.ServiceWrapper> services = ctrl.getServices();
        Test.stopTest();

        System.assertEquals(0, services.size(), 'Should return empty list when accountId is null');
    }

    @IsTest
    static void testServicesPropertyLazyLoad() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        ctrl.accountId = acc.Id;

        Test.startTest();
        List<HouseholdShoppingEmailController.ServiceWrapper> services1 = ctrl.services;
        List<HouseholdShoppingEmailController.ServiceWrapper> services2 = ctrl.services;
        Test.stopTest();

        System.assertNotEquals(null, services1, 'Services should be populated');
        System.assertEquals(services1.size(), services2.size(), 'Should return same cached list');
    }

    @IsTest
    static void testBikesPropertyLazyLoad() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        ctrl.accountId = acc.Id;

        Test.startTest();
        List<HouseholdShoppingEmailController.BikeWrapper> bikes1 = ctrl.bikes;
        List<HouseholdShoppingEmailController.BikeWrapper> bikes2 = ctrl.bikes;
        Test.stopTest();

        System.assertNotEquals(null, bikes1, 'Bikes should be populated');
        System.assertEquals(bikes1.size(), bikes2.size(), 'Should return same cached list');
        System.assert(bikes1.size() > 0, 'Should have at least one bike');
    }

    @IsTest
    static void testClothingPropertyLazyLoad() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        ctrl.accountId = acc.Id;

        Test.startTest();
        List<HouseholdShoppingEmailController.ClothingWrapper> clothing1 = ctrl.clothing;
        List<HouseholdShoppingEmailController.ClothingWrapper> clothing2 = ctrl.clothing;
        Test.stopTest();

        System.assertNotEquals(null, clothing1, 'Clothing should be populated');
        System.assertEquals(clothing1.size(), clothing2.size(), 'Should return same cached list');
        System.assert(clothing1.size() > 0, 'Should have at least one clothing item');
    }

    @IsTest
    static void testBikesNullAccountId() {
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();

        Test.startTest();
        List<HouseholdShoppingEmailController.BikeWrapper> bikes = ctrl.bikes;
        Test.stopTest();

        System.assertEquals(0, bikes.size(), 'Should return empty list when accountId is null');
    }

    @IsTest
    static void testClothingNullAccountId() {
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();

        Test.startTest();
        List<HouseholdShoppingEmailController.ClothingWrapper> clothing = ctrl.clothing;
        Test.stopTest();

        System.assertEquals(0, clothing.size(), 'Should return empty list when accountId is null');
    }

    @IsTest
    static void testClothingWithShirtSize() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        ctrl.accountId = acc.Id;

        Test.startTest();
        List<HouseholdShoppingEmailController.ClothingWrapper> clothing = ctrl.clothing;
        Test.stopTest();

        System.assert(clothing.size() > 0, 'Should have clothing items');
        Boolean foundShirt = false;
        for (HouseholdShoppingEmailController.ClothingWrapper item : clothing) {
            if (item.itemType == 'Shirt') {
                foundShirt = true;
                System.assertEquals('Medium', item.size, 'Shirt size should be Medium');
            }
        }
        System.assert(foundShirt, 'Should have a shirt item');
    }

    @IsTest
    static void testClothingWithPantSize() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        ctrl.accountId = acc.Id;

        Test.startTest();
        List<HouseholdShoppingEmailController.ClothingWrapper> clothing = ctrl.clothing;
        Test.stopTest();

        System.assert(clothing.size() > 0, 'Should have clothing items');
        Boolean foundPants = false;
        for (HouseholdShoppingEmailController.ClothingWrapper item : clothing) {
            if (item.itemType == 'Pants') {
                foundPants = true;
                System.assertEquals('XL', item.size, 'Pants size should be XL');
            }
        }
        System.assert(foundPants, 'Should have a pants item');
    }

    @IsTest
    static void testClothingWithCoatSize() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        ctrl.accountId = acc.Id;

        Test.startTest();
        List<HouseholdShoppingEmailController.ClothingWrapper> clothing = ctrl.clothing;
        Test.stopTest();

        System.assert(clothing.size() > 0, 'Should have clothing items');
        Boolean foundCoat = false;
        for (HouseholdShoppingEmailController.ClothingWrapper item : clothing) {
            if (item.itemType == 'Coat/Hoodie') {
                foundCoat = true;
                System.assertEquals('Small', item.size, 'Coat size should be Small');
            }
        }
        System.assert(foundCoat, 'Should have a coat/hoodie item');
    }

    @IsTest
    static void testClothingWithNoSize() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        ctrl.accountId = acc.Id;

        Test.startTest();
        List<HouseholdShoppingEmailController.ClothingWrapper> clothing = ctrl.clothing;
        Test.stopTest();

        System.assert(clothing.size() > 0, 'Should have clothing items');
        Boolean foundNoSize = false;
        for (HouseholdShoppingEmailController.ClothingWrapper item : clothing) {
            if (item.itemType == 'Clothing' && item.size == 'Not specified') {
                foundNoSize = true;
            }
        }
        System.assert(foundNoSize, 'Should have a clothing item with no size');
    }

    @IsTest
    static void testBikesWithValidBikeSize() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        ctrl.accountId = acc.Id;

        Test.startTest();
        List<HouseholdShoppingEmailController.BikeWrapper> bikes = ctrl.bikes;
        Test.stopTest();

        System.assert(bikes.size() > 0, 'Should have bike items');
        HouseholdShoppingEmailController.BikeWrapper bike = bikes[0];
        System.assertEquals('Large', bike.bikeSize, 'Bike size should be Large');
        System.assertNotEquals(null, bike.contactName, 'Contact name should be populated');
        System.assertNotEquals(null, bike.gender, 'Gender should be populated');
        System.assertEquals('Child Clothes', bike.productName, 'Product name should be Child Clothes');
    }

    @IsTest
    static void testAccountPropertySet() {
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        ctrl.account = acc;

        Test.startTest();
        Account result = ctrl.account;
        Test.stopTest();

        System.assertEquals(acc.Id, result.Id, 'Account should be settable and gettable');
    }

    @IsTest
    static void testAccountIdProperty() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        ctrl.accountId = acc.Id;

        Test.startTest();
        Id result = ctrl.accountId;
        Test.stopTest();

        System.assertEquals(acc.Id, result, 'AccountId should be settable and gettable');
    }

    @IsTest
    static void testServicesPropertySetter() {
        List<HouseholdShoppingEmailController.ServiceWrapper> testList = new List<HouseholdShoppingEmailController.ServiceWrapper>();

        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        
        Test.startTest();
        ctrl.services = testList;
        List<HouseholdShoppingEmailController.ServiceWrapper> result = ctrl.services;
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Services property should be settable');
    }

    @IsTest
    static void testBikesPropertySetter() {
        List<HouseholdShoppingEmailController.BikeWrapper> testList = new List<HouseholdShoppingEmailController.BikeWrapper>();

        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        
        Test.startTest();
        ctrl.bikes = testList;
        List<HouseholdShoppingEmailController.BikeWrapper> result = ctrl.bikes;
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Bikes property should be settable');
    }

    @IsTest
    static void testClothingPropertySetter() {
        List<HouseholdShoppingEmailController.ClothingWrapper> testList = new List<HouseholdShoppingEmailController.ClothingWrapper>();

        HouseholdShoppingEmailController ctrl = new HouseholdShoppingEmailController();
        
        Test.startTest();
        ctrl.clothing = testList;
        List<HouseholdShoppingEmailController.ClothingWrapper> result = ctrl.clothing;
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Clothing property should be settable');
    }

    @IsTest
    static void testServiceWrapperDisplayNameUserEntry() {
        Test.startTest();
        HouseholdShoppingEmailController.ServiceWrapper wrapper = 
            new HouseholdShoppingEmailController.ServiceWrapper('Furniture', 'Other', 1, 'Custom Item');
        Test.stopTest();

        System.assertEquals('Custom Item', wrapper.displayName, 'Display name should be user entry for Other subcategory');
        System.assertEquals('Furniture', wrapper.category, 'Category should be set');
        System.assertEquals('Other', wrapper.subcategory, 'Subcategory should be set');
        System.assertEquals(1, wrapper.quantity, 'Quantity should be set');
        System.assertEquals('Custom Item', wrapper.userEntry, 'User entry should be set');
    }

    @IsTest
    static void testServiceWrapperDisplayNameSubcategory() {
        Test.startTest();
        HouseholdShoppingEmailController.ServiceWrapper wrapper = 
            new HouseholdShoppingEmailController.ServiceWrapper('Furniture', 'Sofa', 2, null);
        Test.stopTest();

        System.assertEquals('Sofa', wrapper.displayName, 'Display name should be subcategory when not Other');
    }

    @IsTest
    static void testServiceWrapperDisplayNameUnknown() {
        Test.startTest();
        HouseholdShoppingEmailController.ServiceWrapper wrapper = 
            new HouseholdShoppingEmailController.ServiceWrapper('Furniture', null, 1, null);
        Test.stopTest();

        System.assertEquals('Unknown Item', wrapper.displayName, 'Display name should be Unknown Item when subcategory is null');
    }

    @IsTest
    static void testServiceWrapperDisplayNameEmptyUserEntry() {
        Test.startTest();
        HouseholdShoppingEmailController.ServiceWrapper wrapper = 
            new HouseholdShoppingEmailController.ServiceWrapper('Furniture', 'Other', 1, '');
        Test.stopTest();

        System.assertEquals('Other', wrapper.displayName, 'Display name should be Other when user entry is empty string');
    }

    @IsTest
    static void testBikeWrapper() {
        Test.startTest();
        HouseholdShoppingEmailController.BikeWrapper wrapper = new HouseholdShoppingEmailController.BikeWrapper();
        wrapper.contactName = 'John Doe';
        wrapper.bikeSize = 'Large';
        wrapper.gender = 'Male';
        wrapper.productName = 'Child Clothes';
        Test.stopTest();

        System.assertEquals('John Doe', wrapper.contactName, 'Contact name should be set');
        System.assertEquals('Large', wrapper.bikeSize, 'Bike size should be set');
        System.assertEquals('Male', wrapper.gender, 'Gender should be set');
        System.assertEquals('Child Clothes', wrapper.productName, 'Product name should be set');
    }

    @IsTest
    static void testClothingWrapper() {
        Test.startTest();
        HouseholdShoppingEmailController.ClothingWrapper wrapper = new HouseholdShoppingEmailController.ClothingWrapper();
        wrapper.contactName = 'Jane Doe';
        wrapper.itemType = 'Shirt';
        wrapper.size = 'Medium';
        wrapper.gender = 'Female';
        wrapper.productName = 'Child Clothes';
        Test.stopTest();

        System.assertEquals('Jane Doe', wrapper.contactName, 'Contact name should be set');
        System.assertEquals('Shirt', wrapper.itemType, 'Item type should be set');
        System.assertEquals('Medium', wrapper.size, 'Size should be set');
        System.assertEquals('Female', wrapper.gender, 'Gender should be set');
        System.assertEquals('Child Clothes', wrapper.productName, 'Product name should be set');
    }

    /* ==========  HELPER METHODS  ========== */

    private static OpportunityLineItem createOLI(
        Id oppId,
        Id pbeId,
        Id conId,
        String shirt,
        String pant,
        String coat,
        String bike
    ) {
        return new OpportunityLineItem(
            OpportunityId       = oppId,
            PricebookEntryId    = pbeId,
            Quantity            = 1,
            UnitPrice           = 100,
            Shirt_Size__c       = shirt,
            Pant_Size__c        = pant,
            Coat_Hoodie_Size__c = coat,
            Bike_Size__c        = bike,
            Contact__c          = conId
        );
    }

    private static Boolean isObjectAccessible(String objApiName) {
        try {
            Schema.SObjectType sobjType =
                Schema.getGlobalDescribe().get(objApiName);
            if (sobjType == null) return false;
            return sobjType.getDescribe().isCreateable();
        } catch (Exception e) {
            return false;
        }
    }
}