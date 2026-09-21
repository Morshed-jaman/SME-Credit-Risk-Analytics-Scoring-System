# Interview Notes

## 30-Second Project Summary

I built an end-to-end SME credit risk analytics system using R, PostgreSQL, SQL, and Shiny. I created a normalized credit database, developed portfolio and risk analytics, built a leakage-safe modeling pipeline with customer-grouped validation, compared Logistic Regression and Random Forest, evaluated both on an untouched holdout set, transformed PD into a demonstration credit score, and built an interactive Shiny management dashboard.

## Key Technical Decisions

- **Only disbursed loans:** only disbursed loans have observed performance outcomes.
- **Rejected applications:** they were not assigned \`default_flag = 0\`; absence of a loan outcome is not evidence of repayment.
- **Customer grouping:** repeat customers must not appear in both partitions, preventing entity leakage.
- **Logistic Regression for scoring:** it had stronger holdout ROC-AUC, PR-AUC, KS, and slightly better Brier score, with clearer coefficient/odds-ratio interpretation.
- **Random Forest benchmark:** it provides a useful nonlinear benchmark with fixed conventional parameters, without unnecessary tuning.
- **Post-disbursement exclusion:** fields such as delinquency, outstanding balance, and loan status are unavailable at application time and would leak outcomes.
- **Locked test set:** the holdout was not used until final evaluation.
- **Low recall at 0.50:** the fixed threshold favors very high specificity, so it misses many defaults; threshold policy requires separate business analysis.
- **Not production-ready:** ROC-AUC around 0.65 on synthetic data is evidence of modest discrimination, not deployment validation.

## Questions and Answers

1. **Tell me about this project.**  
   It is a synthetic SME credit-risk portfolio system spanning PostgreSQL, SQL analytics, R feature engineering, grouped model validation, holdout evaluation, score transformation, and Shiny reporting.

2. **Why Logistic Regression?**  
   It performed better on the holdout metrics and is easier to explain to risk stakeholders through coefficients and odds ratios.

3. **Why did you not train on rejected loans?**  
   Rejected applicants have no observed repayment outcome, so labeling them non-default would introduce target-label bias.

4. **How did you prevent data leakage?**  
   I excluded post-disbursement predictors, used application-time features, grouped splits by customer, and locked the test set until final evaluation.

5. **Why group by customer?**  
   Multiple applications from one customer can carry shared financial behavior. Grouping keeps that information from crossing train and test.

6. **What does ROC-AUC mean here?**  
   It measures how well the model ranks defaults above non-defaults across probability thresholds.

7. **Why is recall low?**  
   The reported threshold is fixed at 0.50; the resulting high specificity comes with low sensitivity. A production threshold would require cost and capacity analysis.

8. **What are KS and Gini?**  
   KS is the maximum separation between cumulative default and non-default score distributions. Gini is \(2 \times ROC\text{-}AUC - 1\).

9. **How is the credit score calculated?**  
   Clipped PD is converted to good:bad odds, then mapped with Base Score 600, Base Odds 20:1, and PDO 50. Higher PD means a lower score.

10. **What would you improve for production?**  
    I would add real governed data, reject inference, temporal and external validation, monitoring, fairness testing, calibration review, policy thresholds, audit controls, and independent model-risk validation.
