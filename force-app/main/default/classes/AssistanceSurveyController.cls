/**
 * Handles Experience Cloud assistance survey validation and persistence.
 */
public without sharing class AssistanceSurveyController {
  /**
   * Validates whether the incoming record id is an Account or Case and returns the related identifiers.
   * @param recordId The Id of the record to look up (Account or Case)
   * @return A map containing statusCode, status, isValidId, accountId, and caseId
   */
  @AuraEnabled(cacheable=true)
  public static Map<string, object> getDetailById(Id recordId) {
    Map<String, Object> response = new Map<String, Object>{
      'statusCode' => 200,
      'status' => 'ok',
      'isValidId' => false,
      'accountId' => null,
      'caseId' => null
    };

    if (recordId == null) {
      response.put('statusCode', 400);
      response.put('status', 'invalid');
      return response;
    }

    try {
      SObjectType recordType = recordId.getSObjectType();
      if (recordType == Account.SObjectType) {
        if (!Schema.sObjectType.Account.isAccessible()) {
          throw new AuraHandledException('You do not have access to Accounts.');
        }
        List<Account> accounts = [SELECT Id FROM Account WHERE Id = :recordId LIMIT 1];
        if (!accounts.isEmpty()) {
          response.put('isValidId', true);
          response.put('accountId', accounts[0].Id);
        }
      } else if (recordType == Case.SObjectType) {
        if (!Schema.sObjectType.Case.isAccessible()) {
          throw new AuraHandledException(
            'You do not have access to Assistance Applications.'
          );
        }
        List<Case> cases = [
          SELECT Id, AccountId
          FROM Case
          WHERE Id = :recordId
          LIMIT 1
        ];
        if (!cases.isEmpty()) {
          response.put('isValidId', true);
          response.put('caseId', cases[0].Id);
          response.put('accountId', cases[0].AccountId);
        }
      }
    } catch (Exception ex) {
      response.put('statusCode', 404);
      response.put('status', 'invalid');
    }

    return response;
  }

  /**
   * Persists a completed assistance survey against the related Account and optional Case.
   * @param surveyJson JSON string containing survey field values
   */
  @AuraEnabled
  @SuppressWarnings('PMD.ApexCRUDViolation')
  public static void newSurvey(String surveyJson) {
    try {
      Map<String, Object> surveyData = (Map<String, Object>) JSON.deserializeUntyped(
        surveyJson
      );

      String accountId = (String) surveyData.get('Account__c');
      String caseId = (String) surveyData.get('Case__c');
      String programSatisfaction = (String) surveyData.get(
        'Program_Satisfaction__c'
      );
      Boolean recommendToOthers = (Boolean) surveyData.get(
        'Recommend_to_Others__c'
      );
      String resourceSatisfaction = (String) surveyData.get(
        'Resource_Satisfaction__c'
      );
      Boolean financialImprovement = (Boolean) surveyData.get(
        'Financial_Improvement__c'
      );
      String suggestions = (String) surveyData.get(
        'Suggestions_for_Improvement__c'
      );
      String utmContent = (String) surveyData.get('UTM_Content__c');

      accountId = resolveAccountId(accountId, caseId);
      validateSurveyPayload(
        programSatisfaction,
        recommendToOthers,
        resourceSatisfaction,
        financialImprovement,
        suggestions
      );

      Assistance_Survey__c surveyRec = new Assistance_Survey__c(
        Account__c = accountId,
        Case__c = caseId,
        Program_Satisfaction__c = programSatisfaction,
        Recommend_to_Others__c = recommendToOthers,
        Resource_Satisfaction__c = resourceSatisfaction,
        Financial_Improvement__c = financialImprovement,
        Suggestions_for_Improvement__c = suggestions,
        UTM_Content__c = utmContent
      );

      insert surveyRec; // without sharing — class is intentionally elevated for Experience Cloud guest submissions
    } catch (Exception e) {
      throw new AuraHandledException('Error saving survey: ' + e.getMessage());
    }
  }

  private static String resolveAccountId(String accountId, String caseId) {
    if (String.isBlank(accountId) && String.isBlank(caseId)) {
      throw new AuraHandledException(
        'A valid account or assistance application is required.'
      );
    }

    if (String.isBlank(accountId) && String.isNotBlank(caseId)) {
      if (!Schema.sObjectType.Case.isAccessible()) {
        throw new AuraHandledException(
          'You do not have access to Assistance Applications.'
        );
      }

      Case assistanceCase = [
        SELECT AccountId
        FROM Case
        WHERE Id = :caseId
        LIMIT 1
      ];
      return assistanceCase.AccountId;
    }

    return accountId;
  }

  @SuppressWarnings('PMD.ExcessiveParameterList,PMD.CyclomaticComplexity')
  private static void validateSurveyPayload(
    String programSatisfaction,
    Boolean recommendToOthers,
    String resourceSatisfaction,
    Boolean financialImprovement,
    String suggestions
  ) {
    if (String.isBlank(programSatisfaction)) {
      throw new AuraHandledException('Program satisfaction is required.');
    }
    if (recommendToOthers == null) {
      throw new AuraHandledException('Recommend to others is required.');
    }
    if (
      String.isBlank(resourceSatisfaction) ||
      resourceSatisfaction.length() < 100
    ) {
      throw new AuraHandledException(
        'Resource satisfaction must be at least 100 characters.'
      );
    }
    if (financialImprovement == null) {
      throw new AuraHandledException('Financial improvement is required.');
    }
    if (String.isBlank(suggestions) || suggestions.length() < 100) {
      throw new AuraHandledException(
        'Suggestions must be at least 100 characters.'
      );
    }
  }
}