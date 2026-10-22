@IsTest
private class InterviewSelfServiceServiceTest {

    @TestSetup
    static void setup() {
        Zone__c zone = InterviewSchedulingTestData.createZone('Link Zone', '84.01', 'Morning');
        InterviewSchedulingTestData.createInterviewDay(zone, Date.today().addDays(9), 'Morning', 2, 'Published');
        Account household = InterviewSchedulingTestData.createHousehold('Link Household', '84.01');
        Contact contact = InterviewSchedulingTestData.createContact(household, 'Lin', 'lin@example.org');
        InterviewSchedulingTestData.createApplication(household, contact);
    }

    @IsTest
    static void tokensAreRandomUrlSafeAndHashedOnTheCase() {
        InterviewSchedulingTestData.selfServiceConfig(24, 3);
        Case app = [SELECT Id FROM Case LIMIT 1];

        String tokenA = InterviewSelfServiceService.generateToken();
        String tokenB = InterviewSelfServiceService.generateToken();
        System.assertEquals(43, tokenA.length(), '32 random bytes -> 43 base64url characters');
        System.assertNotEquals(tokenA, tokenB);
        System.assertEquals(true, InterviewSelfServiceService.looksLikeToken(tokenA));
        System.assertEquals(false, InterviewSelfServiceService.looksLikeToken(tokenA + '='));
        System.assertEquals(false, InterviewSelfServiceService.looksLikeToken('abc'));
        System.assertEquals(false, InterviewSelfServiceService.looksLikeToken(null));

        Test.startTest();
        InterviewSelfServiceService.GeneratedLink link = InterviewSelfServiceService.generateAndStore(app.Id);
        Test.stopTest();

        Case stored = [SELECT Self_Service_Token_Hash__c, Self_Service_Token_Expires__c FROM Case WHERE Id = :app.Id];
        System.assertEquals(InterviewSelfServiceService.hashToken(link.token), stored.Self_Service_Token_Hash__c);
        System.assertEquals(64, stored.Self_Service_Token_Hash__c.length(), 'SHA-256 hex');
        System.assertNotEquals(link.token, stored.Self_Service_Token_Hash__c, 'Raw token is never stored');
        System.assert(stored.Self_Service_Token_Expires__c > System.now().addDays(44), 'Expiry follows Token_Validity_Days__c');
        System.assertEquals('https://example.my.site.com/Christmas/s/interview?t=' + link.token, link.url);
        System.assertEquals('https://x.test/page?a=1&t=abc', InterviewSelfServiceService.buildUrl('https://x.test/page?a=1', 'abc'));
    }

    @IsTest
    static void sendLinkEmailsContactAndStampsCase() {
        InterviewSchedulingTestData.selfServiceConfig(24, 3);
        Case app = [SELECT Id, AccountId FROM Case LIMIT 1];
        // Give the household a booking so the email shows the current time.
        Interview_Day__c day = [SELECT Id FROM Interview_Day__c LIMIT 1];
        InterviewBookingService.book(InterviewSchedulingTestData.slotsFor(day.Id)[0].Id, app.Id, null, InterviewBookingService.Actor.STAFF);

        Test.startTest();
        String message = InterviewSelfServiceService.sendLink(app.Id);
        Test.stopTest();

        System.assert(message.contains('lin@example.org'), '' + message);
        Case stored = [SELECT Self_Service_Token_Hash__c, Self_Service_Link_Sent_On__c, Self_Service_Token_Expires__c FROM Case WHERE Id = :app.Id];
        System.assertNotEquals(null, stored.Self_Service_Token_Hash__c);
        System.assertNotEquals(null, stored.Self_Service_Link_Sent_On__c);
        System.assertNotEquals(null, stored.Self_Service_Token_Expires__c);
    }

    @IsTest
    static void sendLinkRequiresContactEmailAndConfiguredUrl() {
        InterviewSchedulingTestData.selfServiceConfig(24, 3);
        Case app = [SELECT Id, ContactId FROM Case LIMIT 1];
        update new Contact(Id = app.ContactId, Email = null);

        String noEmail;
        try {
            InterviewSelfServiceService.sendLink(app.Id);
        } catch (AuraHandledException ex) {
            noEmail = ex.getMessage();
        }
        System.assertNotEquals(null, noEmail, 'Missing contact email must be reported');

        InterviewSelfServiceConfig.instanceOverride.siteBaseUrl = null;
        String noUrl;
        try {
            InterviewSelfServiceService.sendLink(app.Id);
        } catch (AuraHandledException ex) {
            noUrl = ex.getMessage();
        }
        System.assertNotEquals(null, noUrl, 'Missing Site Base URL must be reported');

        Boolean rejectedNonCase = false;
        try {
            InterviewSelfServiceService.sendLink([SELECT Id FROM Account LIMIT 1].Id);
        } catch (AuraHandledException ex) {
            rejectedNonCase = true;
        }
        System.assert(rejectedNonCase);
    }

    @IsTest
    static void invocableReturnsUrlOnlyWhenNotEmailing() {
        InterviewSchedulingTestData.selfServiceConfig(24, 3);
        Case app = [SELECT Id FROM Case LIMIT 1];

        InterviewSelfServiceService.LinkRequest silent = new InterviewSelfServiceService.LinkRequest();
        silent.caseId = app.Id;
        silent.sendEmail = false;
        InterviewSelfServiceService.LinkRequest emailed = new InterviewSelfServiceService.LinkRequest();
        emailed.caseId = app.Id;
        InterviewSelfServiceService.LinkRequest broken = new InterviewSelfServiceService.LinkRequest();

        Test.startTest();
        List<InterviewSelfServiceService.LinkResult> results = InterviewSelfServiceService.generateLinks(
            new List<InterviewSelfServiceService.LinkRequest>{ silent, emailed, broken }
        );
        Test.stopTest();

        System.assertEquals(3, results.size());
        System.assert(results[0].url.startsWith('https://example.my.site.com/Christmas/s/interview?t='), results[0].url);
        System.assertEquals(null, results[0].error);
        System.assertEquals(null, results[1].url, 'URL is withheld when the email is sent');
        System.assertEquals(null, results[1].error);
        System.assertNotEquals(null, results[2].error);
        // The last generated token wins: the silent one is now invalid.
        Case stored = [SELECT Self_Service_Token_Hash__c FROM Case WHERE Id = :app.Id];
        String silentToken = results[0].url.substringAfter('t=');
        System.assertNotEquals(InterviewSelfServiceService.hashToken(silentToken), stored.Self_Service_Token_Hash__c);
    }
}