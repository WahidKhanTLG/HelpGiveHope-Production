/**
 * Applies applicant scoring automation for assistance cases while preserving manual ratings.
 */
public with sharing class CaseScoringService {
  private class ComponentFieldPair {
    String primaryField;
    String legacyField;

    ComponentFieldPair(String primaryField, String legacyField) {
      this.primaryField = primaryField;
      this.legacyField = legacyField;
    }
  }

  private class OverrideDecision {
    Boolean isManual = false;
    Decimal value;
  }

  private static final ComponentFieldPair EMPLOYMENT_LENGTH_PAIR =
    new ComponentFieldPair('Employment_Length_Score__c', 'Household_Size_Score__c');
  private static final ComponentFieldPair INCOME_DEBT_PAIR =
    new ComponentFieldPair('Income_Debt_Score__c', 'Income_Score__c');
  private static final ComponentFieldPair JOB_STABILITY_PAIR =
    new ComponentFieldPair('Job_Stability_Score__c', 'Need_Score__c');
  private static final ComponentFieldPair RESIDENCY_LENGTH_PAIR =
    new ComponentFieldPair('Residency_Length_Score__c', 'Situation_Score__c');
  private static final ComponentFieldPair PRIOR_ASSISTANCE_PAIR =
    new ComponentFieldPair('Prior_Assistance_Score__c', 'Previous_Assistance_Score__c');

  /**
   * Applies scores to Case records in a before-trigger context.
   *
   * @param newList Incoming Case records in trigger context.
   * @param oldMap Existing Case map for update contexts (null for insert).
   */
  public static void applyScores(List<Case> newList, Map<Id, Case> oldMap) {
    if (newList == null || newList.isEmpty()) {
      return;
    }

    for (Case currentCase : newList) {
      if (!isAssistanceCase(currentCase)) {
        continue;
      }

      Boolean isInsert = oldMap == null || !oldMap.containsKey(currentCase.Id);
      Case oldCase = isInsert ? null : oldMap.get(currentCase.Id);

      CaseScoringRules.ScoreComponents computed = CaseScoringRules.calculate(
        currentCase
      );

      OverrideDecision employmentLengthOverride = determineOverride(
        currentCase,
        oldCase,
        isInsert,
        EMPLOYMENT_LENGTH_PAIR,
        isInsert ? null : CaseScoringRules.calculate(oldCase).employmentLength
      );
      OverrideDecision incomeDebtOverride = determineOverride(
        currentCase,
        oldCase,
        isInsert,
        INCOME_DEBT_PAIR,
        isInsert ? null : CaseScoringRules.calculate(oldCase).incomeDebt
      );
      OverrideDecision jobStabilityOverride = determineOverride(
        currentCase,
        oldCase,
        isInsert,
        JOB_STABILITY_PAIR,
        isInsert ? null : CaseScoringRules.calculate(oldCase).jobStability
      );
      OverrideDecision residencyLengthOverride = determineOverride(
        currentCase,
        oldCase,
        isInsert,
        RESIDENCY_LENGTH_PAIR,
        isInsert ? null : CaseScoringRules.calculate(oldCase).residencyLength
      );
      OverrideDecision priorAssistanceOverride = determineOverride(
        currentCase,
        oldCase,
        isInsert,
        PRIOR_ASSISTANCE_PAIR,
        isInsert ? null : CaseScoringRules.calculate(oldCase).priorAssistance
      );

      applyCalculatedScore(
        currentCase,
        EMPLOYMENT_LENGTH_PAIR,
        computed.employmentLength,
        employmentLengthOverride
      );
      applyCalculatedScore(
        currentCase,
        INCOME_DEBT_PAIR,
        computed.incomeDebt,
        incomeDebtOverride
      );
      applyCalculatedScore(
        currentCase,
        JOB_STABILITY_PAIR,
        computed.jobStability,
        jobStabilityOverride
      );
      applyCalculatedScore(
        currentCase,
        RESIDENCY_LENGTH_PAIR,
        computed.residencyLength,
        residencyLengthOverride
      );
      applyCalculatedScore(
        currentCase,
        PRIOR_ASSISTANCE_PAIR,
        computed.priorAssistance,
        priorAssistanceOverride
      );
    }
  }

  private static OverrideDecision determineOverride(
    Case currentCase,
    Case oldCase,
    Boolean isInsert,
    ComponentFieldPair pair,
    Decimal expectedOldValue
  ) {
    OverrideDecision decision = new OverrideDecision();

    Decimal currentPrimary = getDecimalField(currentCase, pair.primaryField);
    Decimal currentLegacy = getDecimalField(currentCase, pair.legacyField);

    if (isInsert) {
      if (currentPrimary != null || currentLegacy != null) {
        decision.isManual = true;
        decision.value = currentPrimary != null ? currentPrimary : currentLegacy;
      }

      return decision;
    }

    Decimal oldPrimary = getDecimalField(oldCase, pair.primaryField);
    Decimal oldLegacy = getDecimalField(oldCase, pair.legacyField);

    Boolean userEdited =
      !decimalEqualsNullable(currentPrimary, oldPrimary) ||
      !decimalEqualsNullable(currentLegacy, oldLegacy);
    Boolean persistedManual =
      isPersistentlyManual(oldPrimary, expectedOldValue) ||
      isPersistentlyManual(oldLegacy, expectedOldValue);

    Boolean primaryEdited = !decimalEqualsNullable(currentPrimary, oldPrimary);
    Boolean legacyEdited = !decimalEqualsNullable(currentLegacy, oldLegacy);

    if (userEdited || persistedManual) {
      decision.isManual = true;
      if (primaryEdited && currentPrimary != null) {
        decision.value = currentPrimary;
      } else if (legacyEdited && currentLegacy != null) {
        decision.value = currentLegacy;
      } else {
        decision.value = firstNonNull(
          new List<Decimal>{
            currentPrimary,
            currentLegacy,
            oldPrimary,
            oldLegacy
          }
        );
      }
    }

    return decision;
  }

  private static void applyCalculatedScore(
    Case targetCase,
    ComponentFieldPair pair,
    Decimal computedValue,
    OverrideDecision decision
  ) {
    Decimal finalValue = decision.isManual ? decision.value : computedValue;
    setScoreValue(targetCase, pair, finalValue);
  }

  private static Boolean isAssistanceCase(Case c) {
    if (c == null) {
      return false;
    }

    return !String.isBlank(c.Assistance_Type__c) ||
      c.Application_Year__c != null ||
      c.TLG_Number_of_Individuals_in_household__c != null ||
      c.TLG_Total_Household_Income__c != null;
  }

  private static Boolean hasAnyComponentScore(Case c) {
    return c.Household_Size_Score__c != null ||
      c.Income_Score__c != null ||
      c.Need_Score__c != null ||
      c.Previous_Assistance_Score__c != null ||
      c.Situation_Score__c != null ||
      getDecimalField(c, EMPLOYMENT_LENGTH_PAIR.primaryField) != null ||
      getDecimalField(c, INCOME_DEBT_PAIR.primaryField) != null ||
      getDecimalField(c, JOB_STABILITY_PAIR.primaryField) != null ||
      getDecimalField(c, RESIDENCY_LENGTH_PAIR.primaryField) != null ||
      getDecimalField(c, PRIOR_ASSISTANCE_PAIR.primaryField) != null;
  }

  private static Boolean isUserEditingScore(
    Decimal newValue,
    Decimal oldValue
  ) {
    return newValue != oldValue;
  }

  private static Boolean isPersistentlyManual(
    Decimal savedValue,
    Decimal expectedValue
  ) {
    return !decimalEquals(savedValue, expectedValue);
  }

  private static Boolean decimalEquals(Decimal leftValue, Decimal rightValue) {
    Decimal l = leftValue == null ? 0 : leftValue;
    Decimal r = rightValue == null ? 0 : rightValue;
    return l == r;
  }

  private static Boolean decimalEqualsNullable(
    Decimal leftValue,
    Decimal rightValue
  ) {
    if (leftValue == null && rightValue == null) {
      return true;
    }

    if (leftValue == null || rightValue == null) {
      return false;
    }

    return leftValue == rightValue;
  }

  private static Decimal firstNonNull(List<Decimal> values) {
    for (Decimal value : values) {
      if (value != null) {
        return value;
      }
    }

    return null;
  }

  private static Decimal getDecimalField(SObject target, String fieldName) {
    if (target == null || String.isBlank(fieldName)) {
      return null;
    }

    Object value = target.get(fieldName);

    if (value == null) {
      return null;
    }

    if (value instanceof Decimal) {
      return (Decimal)value;
    }

    try {
      return Decimal.valueOf(String.valueOf(value));
    } catch (Exception ex) {
      return null;
    }
  }

  private static void setScoreValue(
    SObject target,
    ComponentFieldPair pair,
    Decimal value
  ) {
    target.put(pair.primaryField, value);
    target.put(pair.legacyField, value);
  }
}