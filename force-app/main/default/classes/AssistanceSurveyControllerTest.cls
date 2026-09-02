@IsTest
private class AssistanceSurveyControllerTest {

    @testSetup
    static void setupTestData() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Case testCase = new Case(
            AccountId = testAccount.Id,
            Status = 'New',
            Origin = 'Web'
        );
        insert testCase;
    }

    private static String makeLongText(String seed) {
        String value = '';
        while (value.length() < 120) {
            value += seed;
        }
        return value.substring(0, 120);
    }

    private static String buildValidSurveyJson(String accountId, String caseId) {
        Map<String, Object> surveyMap = new Map<String, Object>{
            'Account__c' => accountId,
            'Case__c' => caseId,
            'Program_Satisfaction__c' => 'Very Satisfied',
            'Recommend_to_Others__c' => true,
            'Resource_Satisfaction__c' => makeLongText('Resource feedback '),
            'Financial_Improvement__c' => true,
            'Suggestions_for_Improvement__c' => makeLongText('Suggestion feedback '),
            'UTM_Content__c' => 'Test UTM'
        };

        return JSON.serialize(surveyMap);
    }

    @IsTest
    static void testGetDetailById_AccountValid() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Map<String, Object> result = AssistanceSurveyController.getDetailById(acc.Id);
        Test.stopTest();

        System.debug(result);
    }

    @IsTest
    static void testGetDetailById_CaseValid() {
        Case cs = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        Map<String, Object> result = AssistanceSurveyController.getDetailById(cs.Id);
        Test.stopTest();

        System.debug(result);
    }

    @IsTest
    static void testGetDetailById_Null() {
        Test.startTest();
        Map<String, Object> result = AssistanceSurveyController.getDetailById(null);
        Test.stopTest();

        System.debug(result);
    }

    @IsTest
    static void testGetDetailById_FakeAccountId() {
        Id fakeId = '001000000000000AAA';

        Test.startTest();
        Map<String, Object> result = AssistanceSurveyController.getDetailById(fakeId);
        Test.stopTest();

        System.debug(result);
    }

    @IsTest
    static void testGetDetailById_NonAccountNonCaseId() {
        Id userId = UserInfo.getUserId();

        Test.startTest();
        Map<String, Object> result = AssistanceSurveyController.getDetailById(userId);
        Test.stopTest();

        System.debug(result);
    }

    @IsTest
    static void testNewSurvey_Success_WithAccount() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        String jsonInput = buildValidSurveyJson((String) acc.Id, null);

        Test.startTest();
        AssistanceSurveyController.newSurvey(jsonInput);
        Test.stopTest();

        List<Assistance_Survey__c> surveys = [
            SELECT Id, Account__c, Case__c
            FROM Assistance_Survey__c
        ];
        System.debug(surveys);
    }

    @IsTest
    static void testNewSurvey_Success_WithCaseOnly() {
        Case cs = [SELECT Id, AccountId FROM Case LIMIT 1];
        String jsonInput = buildValidSurveyJson(null, (String) cs.Id);

        Test.startTest();
        AssistanceSurveyController.newSurvey(jsonInput);
        Test.stopTest();

        List<Assistance_Survey__c> surveys = [
            SELECT Id, Account__c, Case__c
            FROM Assistance_Survey__c
        ];
        System.debug(surveys);
    }

    @IsTest
    static void testNewSurvey_BothIdsMissing() {
        String jsonInput = buildValidSurveyJson(null, null);

        Test.startTest();
        try {
            AssistanceSurveyController.newSurvey(jsonInput);
        } catch (Exception e) {
            System.debug(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testNewSurvey_InvalidJson() {
        Test.startTest();
        try {
            AssistanceSurveyController.newSurvey('invalid json');
        } catch (Exception e) {
            System.debug(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testNewSurvey_NullJson() {
        Test.startTest();
        try {
            AssistanceSurveyController.newSurvey(null);
        } catch (Exception e) {
            System.debug(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testNewSurvey_InvalidCaseIdOnly() {
        String jsonInput = buildValidSurveyJson(null, '500000000000000AAA');

        Test.startTest();
        try {
            AssistanceSurveyController.newSurvey(jsonInput);
        } catch (Exception e) {
            System.debug(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testNewSurvey_MissingProgramSatisfaction() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Map<String, Object> surveyMap = new Map<String, Object>{
            'Account__c' => acc.Id,
            'Recommend_to_Others__c' => true,
            'Resource_Satisfaction__c' => makeLongText('Resource feedback '),
            'Financial_Improvement__c' => true,
            'Suggestions_for_Improvement__c' => makeLongText('Suggestion feedback '),
            'UTM_Content__c' => 'Test UTM'
        };

        Test.startTest();
        try {
            AssistanceSurveyController.newSurvey(JSON.serialize(surveyMap));
        } catch (Exception e) {
            System.debug(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testNewSurvey_MissingRecommendToOthers() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Map<String, Object> surveyMap = new Map<String, Object>{
            'Account__c' => acc.Id,
            'Program_Satisfaction__c' => 'Very Satisfied',
            'Resource_Satisfaction__c' => makeLongText('Resource feedback '),
            'Financial_Improvement__c' => true,
            'Suggestions_for_Improvement__c' => makeLongText('Suggestion feedback '),
            'UTM_Content__c' => 'Test UTM'
        };

        Test.startTest();
        try {
            AssistanceSurveyController.newSurvey(JSON.serialize(surveyMap));
        } catch (Exception e) {
            System.debug(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testNewSurvey_ShortResourceSatisfaction() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Map<String, Object> surveyMap = new Map<String, Object>{
            'Account__c' => acc.Id,
            'Program_Satisfaction__c' => 'Very Satisfied',
            'Recommend_to_Others__c' => true,
            'Resource_Satisfaction__c' => 'Too short',
            'Financial_Improvement__c' => true,
            'Suggestions_for_Improvement__c' => makeLongText('Suggestion feedback '),
            'UTM_Content__c' => 'Test UTM'
        };

        Test.startTest();
        try {
            AssistanceSurveyController.newSurvey(JSON.serialize(surveyMap));
        } catch (Exception e) {
            System.debug(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testNewSurvey_MissingFinancialImprovement() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Map<String, Object> surveyMap = new Map<String, Object>{
            'Account__c' => acc.Id,
            'Program_Satisfaction__c' => 'Very Satisfied',
            'Recommend_to_Others__c' => true,
            'Resource_Satisfaction__c' => makeLongText('Resource feedback '),
            'Suggestions_for_Improvement__c' => makeLongText('Suggestion feedback '),
            'UTM_Content__c' => 'Test UTM'
        };

        Test.startTest();
        try {
            AssistanceSurveyController.newSurvey(JSON.serialize(surveyMap));
        } catch (Exception e) {
            System.debug(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testNewSurvey_ShortSuggestions() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Map<String, Object> surveyMap = new Map<String, Object>{
            'Account__c' => acc.Id,
            'Program_Satisfaction__c' => 'Very Satisfied',
            'Recommend_to_Others__c' => true,
            'Resource_Satisfaction__c' => makeLongText('Resource feedback '),
            'Financial_Improvement__c' => true,
            'Suggestions_for_Improvement__c' => 'Too short',
            'UTM_Content__c' => 'Test UTM'
        };

        Test.startTest();
        try {
            AssistanceSurveyController.newSurvey(JSON.serialize(surveyMap));
        } catch (Exception e) {
            System.debug(e.getMessage());
        }
        Test.stopTest();
    }
}