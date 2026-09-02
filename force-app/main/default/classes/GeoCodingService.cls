public class GeoCodingService {
    @InvocableMethod
    public static void fetchAndSaveCensusData(List<string> accountIds) {
        // Fetch the Account record
        Account acc = [SELECT Id, BillingStreet, BillingCity,Census_Tract__c, BillingState, BillingPostalCode FROM Account WHERE Id = :accountIds[0]];

        // Construct the URL
        String url = 'https://geocoding.geo.census.gov/geocoder/geographies/address?';
        url += 'street=' + EncodingUtil.urlEncode(acc.BillingStreet, 'UTF-8') + '&';
        url += 'city=' + EncodingUtil.urlEncode(acc.BillingCity, 'UTF-8') + '&';
        url += 'state=' + EncodingUtil.urlEncode(acc.BillingState, 'UTF-8') + '&';
        url += 'benchmark=Public_AR_Current&vintage=Current_Current&layers=10&format=json';
        
        system.debug('url++'+url);

        // Create a new HTTP request
        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        
        // Send the request
        Http http = new Http();
        HttpResponse res;
        
        try {
            res = http.send(req);
        } catch(Exception e) {
            System.debug('Error: ' + e.getMessage());
            return;
        }
        
        // Parse the response
        if(res.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Map<String, Object> result = (Map<String, Object>) responseMap.get('result');
            Object addressMatchesObj = result.get('addressMatches');
            
            if (addressMatchesObj instanceof List<Object>) {
                List<Object> addressMatches = (List<Object>) addressMatchesObj;
                
                if(!addressMatches.isEmpty() && addressMatches[0] instanceof Map<String, Object>) {
                    Map<String, Object> match = (Map<String, Object>) addressMatches[0];
                    Map<String, Object> geographies = (Map<String, Object>) match.get('geographies');
                    Object censusBlockGroupsObj = geographies.get('Census Block Groups');
                    
                    if (censusBlockGroupsObj instanceof List<Object>) {
                        List<Object> censusBlockGroups = (List<Object>) censusBlockGroupsObj;
                        
                        if(!censusBlockGroups.isEmpty() && censusBlockGroups[0] instanceof Map<String, Object>) {
                            Map<String, Object> blockGroup = (Map<String, Object>) censusBlockGroups[0];
                            
                            Decimal censusTrack = Decimal.valueOf(((String) blockGroup.get('TRACT')))/100;
                            
                            // Assuming you have custom fields on the Account object to store the data
                            /*acc.Census_GEOID__c = (String) blockGroup.get('GEOID');
                            acc.Census_CENTLAT__c = (String) blockGroup.get('CENTLAT');
                            acc.Census_AREAWATER__c = (blockGroup.get('AREAWATER') != null) ? Integer.valueOf(blockGroup.get('AREAWATER')) : null;
                            acc.Census_STATE__c = (String) blockGroup.get('STATE');
                            acc.Census_BASENAME__c = (String) blockGroup.get('BASENAME');
                            acc.Census_LSADC__c = (String) blockGroup.get('LSADC');
                            acc.Census_FUNCSTAT__c = (String) blockGroup.get('FUNCSTAT');
                            acc.Census_INTPTLAT__c = (String) blockGroup.get('INTPTLAT');
                            acc.Census_NAME__c = (String) blockGroup.get('NAME');*/
                            acc.Census_Tract__c = String.valueOf(censusTrack.setScale(2));
                            /*acc.Census_CENTLON__c = (String) blockGroup.get('CENTLON');
                            acc.Census_BLKGRP__c = (String) blockGroup.get('BLKGRP');
                            acc.Census_AREALAND__c = (blockGroup.get('AREALAND') != null) ? Integer.valueOf(blockGroup.get('AREALAND')) : null;
                            acc.Census_INTPTLON__c = (String) blockGroup.get('INTPTLON');
                            acc.Census_MTFCC__c = (String) blockGroup.get('MTFCC');
                            acc.Census_COUNTY__c = (String) blockGroup.get('COUNTY');*/
                            
                            // Save the updated account
                            update acc;
                        }
                    }
                }
            }
        } else {
            System.debug('Error: Received status code ' + res.getStatusCode());
        }
    }
}