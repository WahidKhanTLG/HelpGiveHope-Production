@IsTest
private class CaseScoringServiceTest {
  private static User createRunAsUser() {
    Profile profileRecord = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    String uniqueToken = String.valueOf(Datetime.now().getTime());

    return new User(
      FirstName = 'Case',
      LastName = 'ScoringUser',
      Alias = 'csc' +
        uniqueToken.substring(Math.max(0, uniqueToken.length() - 3)),
      Email = 'case.scoring.' + uniqueToken + '@example.com',
      Username = 'case.scoring.' + uniqueToken + '@example.com',
      TimeZoneSidKey = 'America/Chicago',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = profileRecord.Id
    );
  }

  @IsTest
  static void testAutoScoresOnInsert() {
    User runAsUser = createRunAsUser();
    insert runAsUser;

    System.runAs(runAsUser) {
      Case c = new Case(
        Subject = 'Scoring Insert',
        Status = 'New',
        Assistance_Type__c = 'Year Round Assistance',
        Application_Year__c = String.valueOf(Date.today().year()),
        Applicant_Employment_Status__c = 'Employed',
        Employment_Length_Months__c = 18,
        Jobs_In_Past_36_Months__c = 1,
        Residency_Length_Months__c = 40,
        Total_Household_Expense__c = 1000,
        TLG_Total_Household_Income__c = 2000,
        Assisted_in_Past_12_Months__c = false,
        Reason_for_Current_Situation__c = 'Prototype scoring validation.'
      );

      insert c;

      Case insertedCase = [
        SELECT
          Employment_Length_Score__c,
          Job_Stability_Score__c,
          Residency_Length_Score__c,
          Income_Debt_Score__c,
          Prior_Assistance_Score__c,
          Applicant_Score__c,
          Score_Tier__c,
          Household_Size_Score__c,
          Income_Score__c,
          Need_Score__c,
          Previous_Assistance_Score__c,
          Situation_Score__c,
          Total_Score__c
        FROM Case
        WHERE Id = :c.Id
        LIMIT 1
      ];

      System.assertEquals(
        3,
        insertedCase.Employment_Length_Score__c,
        'Employment length score should be auto-calculated.'
      );
      System.assertEquals(
        5,
        insertedCase.Job_Stability_Score__c,
        'Job stability score should be auto-calculated.'
      );
      System.assertEquals(
        5,
        insertedCase.Residency_Length_Score__c,
        'Residency length score should be auto-calculated.'
      );
      System.assertEquals(
        5,
        insertedCase.Income_Debt_Score__c,
        'Income-to-debt score should be auto-calculated.'
      );
      System.assertEquals(
        5,
        insertedCase.Prior_Assistance_Score__c,
        'Prior assistance score should be auto-calculated.'
      );
      System.assertEquals(
        23,
        insertedCase.Applicant_Score__c,
        'Applicant score formula should sum all component scores.'
      );
      System.assertEquals(
        'High',
        insertedCase.Score_Tier__c,
        'Score tier should classify the prototype score.'
      );
      System.assertEquals(
        23,
        insertedCase.Total_Score__c,
        'Legacy total score should stay aligned for existing reports.'
      );
      System.assertEquals(3, insertedCase.Household_Size_Score__c);
      System.assertEquals(5, insertedCase.Need_Score__c);
      System.assertEquals(5, insertedCase.Situation_Score__c);
      System.assertEquals(5, insertedCase.Income_Score__c);
      System.assertEquals(5, insertedCase.Previous_Assistance_Score__c);
    }
  }

  @IsTest
  static void testManualScoresAreRespectedAndPersist() {
    User runAsUser = createRunAsUser();
    insert runAsUser;

    System.runAs(runAsUser) {
      Case c = new Case(
        Subject = 'Scoring Manual',
        Status = 'New',
        Assistance_Type__c = 'Year Round Assistance',
        Application_Year__c = String.valueOf(Date.today().year()),
        Applicant_Employment_Status__c = 'Employed',
        Employment_Length_Months__c = 8,
        Jobs_In_Past_36_Months__c = 2,
        Residency_Length_Months__c = 18,
        Total_Household_Expense__c = 1400,
        TLG_Total_Household_Income__c = 1600,
        Assisted_in_Past_12_Months__c = true,
        Reason_for_Current_Situation__c = 'Manual override scenario.'
      );
      insert c;

      // User manually rates this case.
      c = [
        SELECT
          Id,
          Income_Debt_Score__c,
          Job_Stability_Score__c,
          TLG_Total_Household_Income__c
        FROM Case
        WHERE Id = :c.Id
        LIMIT 1
      ];

      c.Income_Debt_Score__c = 99;
      c.Job_Stability_Score__c = 88;
      c.TLG_Total_Household_Income__c = 3500;
      update c;

      // Subsequent non-score update should retain manual ratings.
      Case c2 = [
        SELECT
          Id,
          Income_Debt_Score__c,
          Job_Stability_Score__c,
          TLG_Total_Household_Income__c,
          Reason_for_Current_Situation__c
        FROM Case
        WHERE Id = :c.Id
        LIMIT 1
      ];

      c2.TLG_Total_Household_Income__c = 700;
      c2.Reason_for_Current_Situation__c = 'Updated reason to verify persistence of manual scoring.';
      update c2;

      Case afterManual = [
        SELECT Income_Debt_Score__c, Job_Stability_Score__c
        FROM Case
        WHERE Id = :c.Id
        LIMIT 1
      ];

      System.assertEquals(
        99,
        afterManual.Income_Debt_Score__c,
        'Manual income-to-debt score should persist.'
      );
      System.assertEquals(
        88,
        afterManual.Job_Stability_Score__c,
        'Manual job stability score should persist.'
      );
    }
  }

  @IsTest
  static void testLegacyManualOverrideStillSyncsToNewFields() {
    User runAsUser = createRunAsUser();
    insert runAsUser;

    System.runAs(runAsUser) {
      Case c = new Case(
        Subject = 'Scoring Legacy Override',
        Status = 'New',
        Assistance_Type__c = 'Year Round Assistance',
        Application_Year__c = String.valueOf(Date.today().year()),
        Applicant_Employment_Status__c = 'Employed',
        Employment_Length_Months__c = 24,
        Jobs_In_Past_36_Months__c = 2,
        Residency_Length_Months__c = 12,
        Total_Household_Expense__c = 2000,
        TLG_Total_Household_Income__c = 2500,
        Assisted_in_Past_12_Months__c = false,
        Reason_for_Current_Situation__c = 'Legacy manual override validation.'
      );
      insert c;

      c = [
        SELECT
          Id,
          Income_Score__c,
          Income_Debt_Score__c,
          TLG_Total_Household_Income__c,
          Total_Household_Expense__c
        FROM Case
        WHERE Id = :c.Id
        LIMIT 1
      ];

      c.Income_Score__c = 99;
      update c;

      Case afterLegacyManual = [
        SELECT Income_Score__c, Income_Debt_Score__c
        FROM Case
        WHERE Id = :c.Id
        LIMIT 1
      ];

      System.assertEquals(
        99,
        afterLegacyManual.Income_Score__c,
        'Legacy manual score should persist.'
      );
      System.assertEquals(
        99,
        afterLegacyManual.Income_Debt_Score__c,
        'Legacy manual score should sync to the new component field.'
      );
    }
  }

  @IsTest
  static void testPartialManualScoresOnInsertStillCalculatesUntouchedFields() {
    User runAsUser = createRunAsUser();
    insert runAsUser;

    System.runAs(runAsUser) {
      Case c = new Case(
        Subject = 'Scoring Partial Insert Override',
        Status = 'New',
        Assistance_Type__c = 'Year Round Assistance',
        Application_Year__c = String.valueOf(Date.today().year()),
        Applicant_Employment_Status__c = 'Employed',
        Employment_Length_Months__c = 12,
        Jobs_In_Past_36_Months__c = 2,
        Residency_Length_Months__c = 8,
        Total_Household_Expense__c = 1500,
        TLG_Total_Household_Income__c = 1800,
        Assisted_in_Past_12_Months__c = false,
        Reason_for_Current_Situation__c = 'Partial manual override scenario.',
        Income_Debt_Score__c = 77
      );

      insert c;

      Case insertedCase = [
        SELECT
          Employment_Length_Score__c,
          Income_Debt_Score__c,
          Job_Stability_Score__c,
          Prior_Assistance_Score__c,
          Residency_Length_Score__c
        FROM Case
        WHERE Id = :c.Id
        LIMIT 1
      ];

      System.assertEquals(
        77,
        insertedCase.Income_Debt_Score__c,
        'Manual score supplied on insert should be preserved.'
      );
      System.assertEquals(
        3,
        insertedCase.Employment_Length_Score__c,
        'Untouched component scores should still auto-populate on insert.'
      );
      System.assertEquals(
        4,
        insertedCase.Job_Stability_Score__c,
        'Job stability score should still auto-populate on insert.'
      );
      System.assertEquals(
        5,
        insertedCase.Prior_Assistance_Score__c,
        'Previous assistance score should still auto-populate on insert.'
      );
      System.assertEquals(
        2,
        insertedCase.Residency_Length_Score__c,
        'Residency score should still auto-populate on insert.'
      );
    }
  }

  @IsTest
  static void testRecalculationWhenNoManualOverride() {
    User runAsUser = createRunAsUser();
    insert runAsUser;

    System.runAs(runAsUser) {
      Case c = new Case(
        Subject = 'Scoring Recalc',
        Status = 'New',
        Assistance_Type__c = 'Year Round Assistance',
        Application_Year__c = String.valueOf(Date.today().year()),
        Applicant_Employment_Status__c = 'Employed',
        Employment_Length_Months__c = 6,
        Jobs_In_Past_36_Months__c = 2,
        Residency_Length_Months__c = 6,
        Total_Household_Expense__c = 2000,
        TLG_Total_Household_Income__c = 2500,
        Assisted_in_Past_12_Months__c = false,
        Reason_for_Current_Situation__c = 'Automatic recalculation scenario.'
      );
      insert c;

      Case beforeUpdate = [
        SELECT Id, Income_Debt_Score__c, TLG_Total_Household_Income__c
        FROM Case
        WHERE Id = :c.Id
        LIMIT 1
      ];
      System.assertEquals(
        4,
        beforeUpdate.Income_Debt_Score__c,
        'Baseline auto score expected.'
      );

      beforeUpdate.TLG_Total_Household_Income__c = 3500;
      update beforeUpdate;

      Case afterUpdate = [
        SELECT Income_Debt_Score__c
        FROM Case
        WHERE Id = :c.Id
        LIMIT 1
      ];
      System.assertEquals(
        5,
        afterUpdate.Income_Debt_Score__c,
        'Auto score should recalculate when no manual override exists.'
      );
    }
  }
}