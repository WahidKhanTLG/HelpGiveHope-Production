public class HouseholdShoppingController {
    
    public Account acct { get; set; }
    public List<pmdm__ServiceDelivery__c> deliveryList { get; set; }
    public List<pmdm__Service__c> serviceList { get; set; }
    public List<Opportunity> oppList { get; set; }
    public List<OpportunityLineItem> giftList { get; set; }
    public List<OpportunityLineItem> childClothesList { get; set; }
    public List<OpportunityLineItem> clothingList { get; set; }
	public Map<Id, Map<Id, CategoryWrapper>> oppContactMap { get; set; }
    
    public class CategoryWrapper {
    	public String contactName {get; set;}
        public String contactGender {get; set;}
        public double contactAge {get; set;}
    	public List<OpportunityLineItem> clothList {get; set;}
    	public List<OpportunityLineItem> giftList {get; set;}

        public CategoryWrapper() {
            clothList = new List<OpportunityLineItem>();
            giftList = new List<OpportunityLineItem>();
        }
	}

    
    public HouseholdShoppingController(ApexPages.StandardController std) {
	oppContactMap = new Map<Id, Map<Id, CategoryWrapper>>();
        // 1) Account
        acct = (Account) std.getRecord();

        // 2) Service Deliveries (indirect via Household)
        deliveryList = [
            SELECT Id, Name, pmdm__Account__c, pmdm__Service__c
            FROM pmdm__ServiceDelivery__c
            WHERE pmdm__Account__c = :acct.Id AND CreatedDate = THIS_YEAR  LIMIT 200
        ];

        // 3) Services from those deliveries (to show Category + Subcategory)
        serviceList = [
            SELECT Id, Name, Category__c, Subcategory__c, Quantity__c, Appliances_User_Entry__c, Furniture_User_Entry__c, Gender__c
            FROM pmdm__Service__c
            WHERE Id IN (SELECT pmdm__Service__c FROM pmdm__ServiceDelivery__c WHERE pmdm__Account__c = :acct.Id) 
            AND CreatedDate = THIS_YEAR 
            LIMIT 200
        ];
    
        // 4) Get Opportunities 
        oppList = [
            SELECT Id, Name, StageName, Amount,
            (SELECT Id, Name__c, Description, Shirt_Size__c, Bike_Size__c, Coat_Hoodie_Size__c, PricebookEntry.Product2.Name,
             		 Pant_Size__c, Contact__r.Name, Contact__c, Contact__r.TLG_Age__c, Contact__r.GenderIdentity
         	FROM OpportunityLineItems)
            FROM Opportunity
            WHERE AccountId = :acct.Id  AND CreatedDate = THIS_YEAR ORDER BY CreatedDate DESC LIMIT 1
        ];
        
        
         for(Opportunity opp : oppList) // run only 1 time
         {
            Map<Id, CategoryWrapper> contactMap = new Map<Id, CategoryWrapper>();
    
            for(OpportunityLineItem oli : opp.OpportunityLineItems)
            {
                // If no contact found, skip that OLI
                if (oli.Contact__c == null) {
                    continue;
                }
    
                if(!contactMap.containsKey(oli.Contact__c))
                {
                    CategoryWrapper cw = new CategoryWrapper();
                    cw.contactName = oli.Contact__r.Name;
                    cw.contactGender = oli.Contact__r.GenderIdentity;
                    cw.contactAge = oli.Contact__r.TLG_Age__c;
                    contactMap.put(oli.Contact__c, cw);
                }
    
                CategoryWrapper wrap = contactMap.get(oli.Contact__c);
    
                // Product Category Split
                if(oli.PricebookEntry.Product2.Name == 'Gift Products'){
                    wrap.giftList.add(oli);
                }
                else if(
                    	oli.PricebookEntry.Product2.Name == 'Child Clothes' ||
                       	oli.PricebookEntry.Product2.Name == 'Clothing Item'
                       ){
                    wrap.clothList.add(oli);
                }
            }
            oppContactMap.put(opp.Id, contactMap);
    	}
        
    }
}