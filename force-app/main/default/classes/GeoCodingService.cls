public class GeoCodingService {
    // Each lookup can take up to the 10-second callout timeout, so a job of 10 stays inside
    // the 120-second callout limit. Anything beyond that goes to a chained job.
    private static final Integer ACCOUNTS_PER_JOB = 10;

    // Called by the Account record-triggered flow while the record is being saved, when
    // callouts aren't allowed, so the lookups run in a queueable job instead.
    @InvocableMethod
    public static void fetchAndSaveCensusData(List<string> accountIds) {
        List<Id> ids = new List<Id>();
        for (String accountId : new Set<String>(accountIds)) {
            if (String.isNotBlank(accountId)) {
                ids.add(accountId);
            }
        }
        if (ids.isEmpty() || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return;
        }

        // A failed lookup must never stop the Account from saving.
        try {
            System.enqueueJob(new CensusTractJob(ids));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Could not queue census tract lookup: ' + e.getMessage());
        }
    }

    public class CensusTractJob implements Queueable, Database.AllowsCallouts {
        private final List<Id> accountIds;

        public CensusTractJob(List<Id> accountIds) {
            this.accountIds = accountIds;
        }

        public void execute(QueueableContext context) {
            List<Id> batch = new List<Id>();
            List<Id> remaining = new List<Id>();
            for (Id accountId : accountIds) {
                if (batch.size() < ACCOUNTS_PER_JOB) {
                    batch.add(accountId);
                } else {
                    remaining.add(accountId);
                }
            }

            // All callouts first: a callout can't follow DML in the same transaction.
            List<Account> updates = new List<Account>();
            for (Account acc : [SELECT Id, BillingStreet, BillingCity, BillingState FROM Account WHERE Id IN :batch]) {
                String censusTract;
                try {
                    censusTract = lookUpCensusTract(acc);
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, 'Census tract lookup failed for ' + acc.Id + ': ' + e.getMessage());
                }
                if (censusTract != null) {
                    updates.add(new Account(Id = acc.Id, Census_Tract__c = censusTract));
                }
            }
            Database.update(updates, false);

            // Apex tests can't chain queueable jobs.
            if (!remaining.isEmpty() && !Test.isRunningTest()) {
                System.enqueueJob(new CensusTractJob(remaining));
            }
        }
    }

    private static String lookUpCensusTract(Account acc) {
        if (String.isBlank(acc.BillingStreet) || String.isBlank(acc.BillingCity) || String.isBlank(acc.BillingState)) {
            return null;
        }

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
            return null;
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
                            return String.valueOf(censusTrack.setScale(2));
                            /*acc.Census_CENTLON__c = (String) blockGroup.get('CENTLON');
                            acc.Census_BLKGRP__c = (String) blockGroup.get('BLKGRP');
                            acc.Census_AREALAND__c = (blockGroup.get('AREALAND') != null) ? Integer.valueOf(blockGroup.get('AREALAND')) : null;
                            acc.Census_INTPTLON__c = (String) blockGroup.get('INTPTLON');
                            acc.Census_MTFCC__c = (String) blockGroup.get('MTFCC');
                            acc.Census_COUNTY__c = (String) blockGroup.get('COUNTY');*/
                        }
                    }
                }
            }
        } else {
            System.debug('Error: Received status code ' + res.getStatusCode());
        }
        return null;
    }
}