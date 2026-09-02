global class HouseholdShoppingEmailController {

    /*------------------------------------
     RECEIVING FIELD FROM COMPONENT
    -------------------------------------*/
    global Id accountId { get; set; }

    /*------------------------------------
     STORAGE - Add these as properties for Visualforce access
    -------------------------------------*/
    global Account account { get; set; }
    
    // Services property with proper getter
    global List<ServiceWrapper> services { 
        get {
            if (services == null) {
                services = getServices();
            }
            return services;
        }
        set;
    }
    
    // Bikes property with proper getter
    global List<BikeWrapper> bikes { 
        get {
            if (bikes == null) {
                bikes = getBikes();
            }
            return bikes;
        }
        set;
    }
    
    // Clothing property with proper getter
    global List<ClothingWrapper> clothing { 
        get {
            if (clothing == null) {
                clothing = getClothing();
            }
            return clothing;
        }
        set;
    }

    /*------------------------------------
     WRAPPER CLASSES
    -------------------------------------*/
    global class ServiceWrapper {
        global String category { get; set; }
        global String subcategory { get; set; }
        global String userEntry { get; set; }
        global Decimal quantity { get; set; }
        global String displayName { get; set; }

        // Constructor
        global ServiceWrapper(String cat, String subcat, Decimal qty, String entry) {
            category = cat;
            subcategory = subcat;
            quantity = qty;
            userEntry = entry;

            // Assign displayName based on the logic
            if (subcategory != null && subcategory == 'Other' && userEntry != null && userEntry != '') {
                displayName = userEntry;
            } else if (subcategory != null) {
                displayName = subcategory;
            } else {
                displayName = 'Unknown Item';
            }
        }
    }

    global class BikeWrapper {
        global String contactName { get; set; }
        global String bikeSize { get; set; }
        global String gender { get; set; }
        global String productName { get; set; }
    }

    global class ClothingWrapper {
        global String contactName { get; set; }
        global String itemType { get; set; }
        global String size { get; set; }
        global String gender { get; set; }
        global String productName { get; set; }
    }

    /*------------------------------------
     CONSTRUCTOR
    -------------------------------------*/
    global HouseholdShoppingEmailController() {}

    /*------------------------------------
     GET ACCOUNT
    -------------------------------------*/
    global Account getAccount() {
        if (account == null && accountId != null) {
            try {
                account = [SELECT Id, Name FROM Account WHERE Id = :accountId LIMIT 1];
            } catch (Exception e) {
                System.debug('Error getting account: ' + e.getMessage());
            }
        }
        return account;
    }

    /*------------------------------------
     GET SERVICES (Furniture/Appliances)
    -------------------------------------*/
    global List<ServiceWrapper> getServices() {
        List<ServiceWrapper> serviceList = new List<ServiceWrapper>();
        
        if (accountId != null) {
            try {
                List<pmdm__Service__c> serviceRecords = [
                    SELECT Id, Category__c, Subcategory__c, Quantity__c,
                           Appliances_User_Entry__c, Furniture_User_Entry__c
                    FROM pmdm__Service__c
                    WHERE Id IN (
                        SELECT pmdm__Service__c 
                        FROM pmdm__ServiceDelivery__c 
                        WHERE pmdm__Account__c = :accountId
                    )
                    AND Category__c = 'Furniture'
                ];
                
                for (pmdm__Service__c service : serviceRecords) {
                    // Only add services that have valid data
                    if (service.Subcategory__c != null || service.Furniture_User_Entry__c != null) {
                        ServiceWrapper wrapper = new ServiceWrapper(
                            service.Category__c,
                            service.Subcategory__c,
                            service.Quantity__c,
                            service.Furniture_User_Entry__c
                        );
                        serviceList.add(wrapper);
                    }
                }

            } catch (Exception e) {
                System.debug('Error getting services: ' + e.getMessage());
            }
        }
        return serviceList;
    }

    /*------------------------------------
     GET BIKE ITEMS (Private method)
    -------------------------------------*/
    private List<BikeWrapper> getBikes() {
        List<BikeWrapper> bikeList = new List<BikeWrapper>();
        
        if (accountId != null) {
            try {
                List<Opportunity> opportunities = [
                    SELECT Id, (
                        SELECT Id, Bike_Size__c, Contact__r.Name, Contact__r.GenderIdentity,
                               PricebookEntry.Product2.Name
                        FROM OpportunityLineItems
                        WHERE Bike_Size__c != null
                        AND PricebookEntry.Product2.Name = 'Child Clothes'
                    )
                    FROM Opportunity
                    WHERE AccountId = :accountId
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                
                if (!opportunities.isEmpty() && !opportunities[0].OpportunityLineItems.isEmpty()) {
                    for (OpportunityLineItem item : opportunities[0].OpportunityLineItems) {
                        if (item.Bike_Size__c != null) {
                            BikeWrapper wrapper = new BikeWrapper();
                            wrapper.contactName = item.Contact__r.Name;
                            wrapper.bikeSize = item.Bike_Size__c;
                            wrapper.gender = item.Contact__r.GenderIdentity;
                            wrapper.productName = item.PricebookEntry.Product2.Name;
                            bikeList.add(wrapper);
                        }
                    }
                }
            } catch (Exception e) {
                System.debug('Error getting bikes: ' + e.getMessage());
            }
        }
        return bikeList;
    }

    /*------------------------------------
     GET CLOTHING ITEMS (Private method)
    -------------------------------------*/
    private List<ClothingWrapper> getClothing() {
        List<ClothingWrapper> clothingList = new List<ClothingWrapper>();
        
        if (accountId != null) {
            try {
                List<Opportunity> opportunities = [
                    SELECT Id, (
                        SELECT Id, Contact__r.Name, Contact__r.GenderIdentity, Shirt_Size__c, Pant_Size__c,
                               Coat_Hoodie_Size__c, PricebookEntry.Product2.Name
                        FROM OpportunityLineItems
                        WHERE (PricebookEntry.Product2.Name = 'Child Clothes' 
                               OR PricebookEntry.Product2.Name = 'Clothing Item')
                        AND Bike_Size__c = null  // Exclude bike items
                    )
                    FROM Opportunity
                    WHERE AccountId = :accountId
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                
                if (!opportunities.isEmpty()) {
                    for (OpportunityLineItem item : opportunities[0].OpportunityLineItems) {
                        ClothingWrapper wrapper = new ClothingWrapper();
                        wrapper.contactName = item.Contact__r.Name;
                        wrapper.productName = item.PricebookEntry.Product2.Name;
                        wrapper.gender = item.Contact__r.GenderIdentity;
                        
                        // Determine size based on what's available
                        if (item.Shirt_Size__c != null) {
                            wrapper.size = item.Shirt_Size__c;
                            wrapper.itemType = 'Shirt';
                        } else if (item.Pant_Size__c != null) {
                            wrapper.size = item.Pant_Size__c;
                            wrapper.itemType = 'Pants';
                        } else if (item.Coat_Hoodie_Size__c != null) {
                            wrapper.size = item.Coat_Hoodie_Size__c;
                            wrapper.itemType = 'Coat/Hoodie';
                        } else {
                            wrapper.size = 'Not specified';
                            wrapper.itemType = 'Clothing';
                        }
                        
                        clothingList.add(wrapper);
                    }
                }
            } catch (Exception e) {
                System.debug('Error getting clothing: ' + e.getMessage());
            }
        }
        return clothingList;
    }
}