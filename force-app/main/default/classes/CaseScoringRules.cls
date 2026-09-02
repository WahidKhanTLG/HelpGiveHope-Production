/**
 * Encapsulates the score calculation rules used by CaseScoringService.
 */
public with sharing class CaseScoringRules {

    /**
     * Value object for component scores.
     */
    public class ScoreComponents {
        public Decimal employmentLength;
        public Decimal jobStability;
        public Decimal residencyLength;
        public Decimal incomeDebt;
        public Decimal priorAssistance;
    }

    /**
     * Computes component scores from Case attributes.
     *
     * @param c Case record used for scoring.
     * @return Computed score component bundle.
     */
    public static ScoreComponents calculate(Case c) {
        ScoreComponents score = new ScoreComponents();

        Integer employmentMonths = toInteger(c.Employment_Length_Months__c);
        Integer totalTimeEmployedMonths = toInteger(c.Total_Time_Employed_Months__c);
        Integer jobsPast36Months = toInteger(c.Jobs_In_Past_36_Months__c);
        Integer residencyMonths = toInteger(c.Residency_Length_Months__c);
        Decimal income = toDecimal(c.TLG_Total_Household_Income__c);
        Decimal totalExpense = toDecimal(c.Total_Household_Expense__c);
        String employmentStatus = normalizeValue(c.Applicant_Employment_Status__c);

        score.employmentLength = getEmploymentLengthScore(
            employmentStatus,
            employmentMonths,
            totalTimeEmployedMonths
        );
        score.jobStability = getJobStabilityScore(jobsPast36Months);
        score.residencyLength = getResidencyLengthScore(residencyMonths);
        score.incomeDebt = getIncomeDebtScore(income, totalExpense);
        score.priorAssistance = getPriorAssistanceScore(c.Assisted_in_Past_12_Months__c);

        return score;
    }

    private static Decimal getEmploymentLengthScore(
        String employmentStatus,
        Integer employmentMonths,
        Integer totalTimeEmployedMonths
    ) {
        Integer normalizedEmploymentMonths = totalTimeEmployedMonths > 0
            ? totalTimeEmployedMonths
            : employmentMonths;

        if (normalizedEmploymentMonths <= 0) {
            return 0;
        }

        if (employmentStatus != 'employed' && totalTimeEmployedMonths <= 0) {
            return 2;
        }

        if (normalizedEmploymentMonths < 6) {
            return 1;
        }
        if (normalizedEmploymentMonths < 12) {
            return 2;
        }
        if (normalizedEmploymentMonths < 24) {
            return 3;
        }
        if (normalizedEmploymentMonths < 36) {
            return 4;
        }
        return 5;
    }

    private static Decimal getJobStabilityScore(Integer jobsPast36Months) {
        if (jobsPast36Months <= 0) {
            return 0;
        }
        if (jobsPast36Months == 1) {
            return 5;
        }
        if (jobsPast36Months == 2) {
            return 4;
        }
        if (jobsPast36Months == 3) {
            return 3;
        }
        if (jobsPast36Months == 4) {
            return 2;
        }
        return 1;
    }

    private static Decimal getResidencyLengthScore(Integer residencyMonths) {
        if (residencyMonths <= 0) {
            return 0;
        }
        if (residencyMonths < 6) {
            return 1;
        }
        if (residencyMonths < 12) {
            return 2;
        }
        if (residencyMonths < 24) {
            return 3;
        }
        if (residencyMonths < 36) {
            return 4;
        }
        return 5;
    }

    private static Decimal getIncomeDebtScore(Decimal income, Decimal totalExpense) {
        if (income <= 0 || totalExpense <= 0) {
            return 0;
        }

        Decimal ratio = income / totalExpense;

        if (ratio < 0.75) {
            return 1;
        }
        if (ratio < 1) {
            return 2;
        }
        if (ratio < 1.25) {
            return 3;
        }
        if (ratio < 1.5) {
            return 4;
        }
        return 5;
    }

    private static Decimal getPriorAssistanceScore(Boolean assistedInPast12Months) {
        return assistedInPast12Months == true ? 1 : 5;
    }

    private static Integer toInteger(Decimal val) {
        if (val == null) {
            return 0;
        }

        try {
            return Integer.valueOf(val);
        } catch (Exception ex) {
            return 0;
        }
    }

    private static Decimal toDecimal(Decimal val) {
        return val == null ? 0 : val;
    }

    private static String normalizeValue(String val) {
        return String.isBlank(val) ? null : val.trim().toLowerCase();
    }
}