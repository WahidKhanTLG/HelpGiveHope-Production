@isTest
private class ThankYouPageControllerTest {
    @isTest
    static void testVerifyCaseWhenStatusIsNew() {
        Case testCase = new Case(
            Subject = 'Email verification test - New',
            Origin = 'Web',
            Status = 'New'
        );
        insert testCase;

        PageReference pageRef = new PageReference('/apex/ThankYou');
        pageRef.getParameters().put('id', testCase.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        ThankYouPageController controller = new ThankYouPageController();
        controller.verify();
        Test.stopTest();

        Case refreshedCase = [
            SELECT Id, Status
            FROM Case
            WHERE Id = :testCase.Id
            LIMIT 1
        ];

        String finalStatus = refreshedCase.Status;
    }

    @isTest
    static void testVerifyCaseWhenStatusIsAlreadyVerified() {
        Case testCase = new Case(
            Subject = 'Email verification test - Verified',
            Origin = 'Web',
            Status = 'Escalated'
        );
        insert testCase;

        PageReference pageRef = new PageReference('/apex/ThankYou');
        pageRef.getParameters().put('id', testCase.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        ThankYouPageController controller = new ThankYouPageController();
        controller.verify();
        Test.stopTest();
    }

    @isTest
    static void testVerifyCaseWhenStatusIsNotNew() {
        Case testCase = new Case(
            Subject = 'Email verification test - Closed',
            Origin = 'Web',
            Status = 'Closed'
        );
        insert testCase;

        PageReference pageRef = new PageReference('/apex/ThankYou');
        pageRef.getParameters().put('id', testCase.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        ThankYouPageController controller = new ThankYouPageController();
        controller.verify();
        Test.stopTest();
    }

    @isTest
    static void testVerifyCaseWhenCaseIdIsMissing() {
        PageReference pageRef = new PageReference('/apex/ThankYou');
        Test.setCurrentPage(pageRef);

        Test.startTest();
        ThankYouPageController controller = new ThankYouPageController();
        controller.verify();
        Test.stopTest();
    }

    @isTest
    static void testVerifyCaseWhenCaseIdIsInvalid() {
        PageReference pageRef = new PageReference('/apex/ThankYou');
        pageRef.getParameters().put('id', '123');
        Test.setCurrentPage(pageRef);

        Test.startTest();
        ThankYouPageController controller = new ThankYouPageController();
        controller.verify();
        Test.stopTest();
    }
}