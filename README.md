# SME Credit Risk Analytics & Scoring System

## Objective

This portfolio project demonstrates an end-to-end SME credit risk analytics and scoring workflow: from synthetic data generation and PostgreSQL-based analysis to statistical exploration, predictive modeling, applicant scoring, and Shiny-based management reporting.

## Technology stack

- **R** for data processing, statistical analysis, machine learning, and reporting
- **Shiny** for interactive management dashboards
- **PostgreSQL** and **SQL** for data storage, transformation, and analytical queries
- **Git** for version control

## Current architecture

1. Synthetic SME loan and application data is generated and validated with R.
2. A normalized PostgreSQL schema stores applications, credit assessments, decisions, and loan performance.
3. The SQL analytics layer provides Credit-SME KPIs, current-state application funnel reporting, processing-time analysis, risk segmentation, delinquency/PAR metrics, exposure concentration, snapshot cohort analysis, and repeat-customer exposure reporting.
4. Reusable PostgreSQL views support later R and Shiny integration:
   - `vw_application_funnel`
   - `vw_monthly_credit_kpis`
   - `vw_portfolio_performance`
   - `vw_default_analysis`
   - `vw_business_segment_performance`
   - `vw_customer_exposure`
5. The R data-quality pipeline preserves original source values while adding deterministic median-imputed helper fields, missingness indicators, risk bands, operational duration metrics, and credit-decision-time engineered features.
6. A leakage-safe modeling dataset is created from disbursed loans only, so default modeling uses borrowers with genuine performance exposure and excludes post-disbursement performance variables from predictors.
7. Ordered R scripts will next handle EDA, model training/evaluation, and applicant scoring.
8. A Shiny application in `app/` will surface management KPIs, portfolio risk, model performance, and interactive scoring.

## Credit-SME KPI definitions

- **Approval rate:** Approved + Disbursed applications divided by all applications
- **Disbursement rate:** Disbursed applications divided by all applications
- **Default rate:** Defaults among disbursed loans divided by disbursed loans
- **PAR 30/60/90:** Balance-based portfolio-at-risk measures using the active disbursed portfolio, excluding closed loans

The dataset stores current/final application status rather than a full historical event log, so application-funnel analysis is presented as current-state distribution plus stage-reached counts inferred from workflow dates.

Vintage/cohort analysis is snapshot-based because the synthetic dataset contains current loan-performance outcomes rather than full monthly performance histories.

For default modeling, only disbursed loans are eligible because rejected, submitted, under-review, and approved-but-not-disbursed applications do not have genuine loan-performance outcomes in this synthetic portfolio.

## Disclaimer

All datasets used in this project are synthetic and created solely for educational and portfolio purposes. They do not contain real customer, borrower, or financial-institution data and do not represent any real institution's credit policy or lending decisions.

## Credit risk model training

Default modeling uses disbursed loans only, because they are the records with genuine performance exposure. The data is split by customer, ensuring the same customer cannot appear in both the training and final test sets. Training uses five-fold customer-grouped cross-validation.

The current training benchmarks are Logistic Regression and a fixed-parameter Random Forest benchmark (`mtry = 6`, `min_n = 15`, `trees = 500`). Both use application-time predictors only; post-disbursement leakage fields are excluded. The final test set remained untouched throughout training.

These are grouped cross-validation results, **not final test performance**:

- Logistic Regression: ROC-AUC approximately 0.686; PR-AUC approximately 0.387.
- Random Forest benchmark: ROC-AUC approximately 0.671; PR-AUC approximately 0.369.

No final model winner has been declared. Final test-set evaluation is reserved for the subsequent evaluation step.
