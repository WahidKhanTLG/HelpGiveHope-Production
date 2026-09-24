@isTest
public class GeoCodingServiceTest {
    
    @isTest
    static void testFetchAndSaveCensusData() {
        // Step 1: Create a test account
        Account testAccount = new Account(
            Name = 'Test Account',
            BillingStreet = '1600 Amphitheatre Parkway',
            BillingCity = 'Mountain View',
            BillingState = 'CA',
            BillingPostalCode = '94043'
        );
        insert testAccount;

        // Step 2: Create a mock HTTP response for the HTTP callout
        Test.startTest();
        // Register the mock
        Test.setMock(HttpCalloutMock.class, new GeoCodingServiceMock());

        // Step 3: Call the method to be tested
        GeoCodingService.fetchAndSaveCensusData(new List<String> { testAccount.Id });
        Test.stopTest();

        // Step 4: Retrieve the updated account and verify changes
        Account updatedAccount = [SELECT Id, Census_Tract__c FROM Account WHERE Id = :testAccount.Id];

        // Verify that the Census_Tract__c field is updated
        System.assertEquals('1234.56', updatedAccount.Census_Tract__c, 'Census_Tract__c should be updated with mock data.');
    }

    // Define a mock for the HttpCallout
    public class GeoCodingServiceMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake response
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{' +
                '"result": {' +
                '"addressMatches": [' +
                '{' +
                '"geographies": {' +
                '"Census Block Groups": [' +
                '{' +
                '"TRACT": "123456"' +
                '}' +
                ']' +
                '}' +
                '}' +
                ']' +
                '}' +
                '}'
            );
            return res;
        }
    }

    @isTest
    static void testFetchAndSaveCensusDataWithError() {
        // Step 1: Create a test account
        Account testAccount = new Account(
            Name = 'Test Account Error',
            BillingStreet = 'Invalid Address',
            BillingCity = 'Nowhere',
            BillingState = 'XX',
            BillingPostalCode = '00000'
        );
        insert testAccount;

        // Step 2: Create a mock HTTP response for a failed HTTP callout
        Test.startTest();
        // Register the mock
        Test.setMock(HttpCalloutMock.class, new GeoCodingServiceErrorMock());

        // Step 3: Call the method to be tested
        GeoCodingService.fetchAndSaveCensusData(new List<String> { testAccount.Id });
        Test.stopTest();

        // Step 4: Retrieve the updated account and verify no changes
        Account updatedAccount = [SELECT Id, Census_Tract__c FROM Account WHERE Id = :testAccount.Id];

        // Verify that the Census_Tract__c field is not updated
        System.assertEquals(null, updatedAccount.Census_Tract__c, 'Census_Tract__c should not be updated due to HTTP error.');
    }

    // Define a mock for HTTP error response
    public class GeoCodingServiceErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake error response
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }

    @isTest
    static void testEveryAccountInBatchIsUpdated() {
        List<Account> accounts = buildAccounts(3);
        insert accounts;

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeoCodingServiceMock());
        GeoCodingService.fetchAndSaveCensusData(idsOf(accounts));
        Test.stopTest();

        for (Account acc : [SELECT Census_Tract__c FROM Account WHERE Id IN :accounts]) {
            System.assertEquals('1234.56', acc.Census_Tract__c, 'Every account in the batch should be geocoded.');
        }
    }

    @isTest
    static void testIncompleteAddressIsSkipped() {
        Account testAccount = new Account(
            Name = 'Test Account No State',
            BillingStreet = '1600 Amphitheatre Parkway',
            BillingCity = 'Mountain View'
        );
        insert testAccount;

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new GeoCodingServiceMock());
        GeoCodingService.fetchAndSaveCensusData(new List<String> { testAccount.Id });
        Test.stopTest();

        Account updatedAccount = [SELECT Census_Tract__c FROM Account WHERE Id = :testAccount.Id];
        System.assertEquals(null, updatedAccount.Census_Tract__c, 'An account without a state should not be geocoded.');
    }

    @isTest
    static void testBlankIdsQueueNothing() {
        Test.startTest();
        GeoCodingService.fetchAndSaveCensusData(new List<String> { '', null });
        System.assertEquals(0, Limits.getQueueableJobs(), 'Blank ids should not queue a lookup.');
        Test.stopTest();
    }

    private static List<Account> buildAccounts(Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                BillingStreet = i + ' Main Street',
                BillingCity = 'Mountain View',
                BillingState = 'CA',
                BillingPostalCode = '94043'
            ));
        }
        return accounts;
    }

    private static List<String> idsOf(List<Account> accounts) {
        List<String> ids = new List<String>();
        for (Account acc : accounts) {
            ids.add(acc.Id);
        }
        return ids;
    }
}