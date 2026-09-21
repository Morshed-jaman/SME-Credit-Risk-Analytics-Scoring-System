# SME Credit Risk Analytics & Scoring System

An end-to-end portfolio project demonstrating SME credit analytics, PostgreSQL data modeling, an R data pipeline, leakage-safe machine learning, probability-of-default estimation, scorecard-style transformation, and a Shiny decision-support dashboard. All data is synthetic.

## Business Problem

The project demonstrates how SME loan application, financial, decision, and performance data can be organized and analyzed to support portfolio monitoring, credit-risk segmentation, default-risk modeling, management reporting, and applicant risk scoring. It does not represent any real financial institution.

## Technology Stack

R, tidymodels, ranger, Shiny, ggplot2, dplyr, PostgreSQL, SQL, and Git/GitHub.

## Project Architecture

\`\`\`mermaid
flowchart TD
  A[Synthetic Data Generation] --> B[Data Validation]
  B --> C[PostgreSQL Normalization]
  C --> D[SQL Analytics]
  D --> E[R Cleaning and Feature Engineering]
  E --> F[EDA and Statistical Analysis]
  F --> G[Customer-Grouped Modeling]
  G --> H[Final Holdout Evaluation]
  H --> I[PD to Credit Score]
  I --> J[Shiny Dashboard]
\`\`\`

## Database

The normalized PostgreSQL layer contains \`customers\`, \`loan_applications\`, \`credit_assessments\`, \`loan_decisions\`, and \`loan_performance\`. Reusable views include:

- \`vw_application_funnel\`
- \`vw_monthly_credit_kpis\`
- \`vw_portfolio_performance\`
- \`vw_default_analysis\`
- \`vw_business_segment_performance\`
- \`vw_customer_exposure\`

The SQL layer covers funnel metrics, monthly KPIs, processing times, default segmentation, PAR/delinquency, concentration analysis, and repeat-customer exposure.

## Data Pipeline

Run the scripts in this order:

1. \`01_generate_data.R\`  generates the synthetic portfolio.
2. \`02_validate_data.R\`  validates source data and business rules.
3. \`03_clean_data.R\`  cleans data and creates modeling features.
4. \`04_eda.R\`  produces exploratory and statistical analyses.
5. \`05_model_training.R\`  creates the customer-grouped split, grouped CV folds, and Logistic Regression fit.
6. \`05c_random_forest.R\`  evaluates the fixed-parameter Random Forest benchmark.
7. \`06_model_evaluation.R\`  evaluates both fitted models on the untouched holdout.
8. \`07_score_applicants.R\`  creates the demonstration score and risk bands.

## Leakage-Safe Modeling

Only disbursed loans have observed default outcomes. Rejected and non-disbursed applications are not treated as non-defaults. Customers are grouped so the same customer cannot occur in train and test; customer overlap is 0 and validation uses five grouped folds. The final test set remained untouched during training.

Post-disbursement fields are excluded as predictors, including \`days_past_due\`, \`missed_payments\`, \`loan_status\`, \`outstanding_balance\`, and \`total_payments\`.

## Model Results

### Grouped Cross-Validation

| Model | ROC-AUC | PR-AUC |
|---|---:|---:|
| Logistic Regression | 0.686 | 0.387 |
| Random Forest benchmark | 0.671 | 0.369 |

### Final Customer-Grouped Holdout Test

| Model | ROC-AUC | PR-AUC | Gini | KS | Brier | Precision | Recall | Specificity | F1 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Logistic Regression | 0.6496 | 0.3811 | 0.2991 | 0.2397 | 0.1666 | 0.5526 | 0.0719 | 0.9827 | 0.1273 |
| Random Forest | 0.6274 | 0.3519 | 0.2548 | 0.2078 | 0.1703 | 0.5862 | 0.0582 | 0.9878 | 0.1059 |

Logistic Regression demonstrated somewhat stronger discrimination and calibration than the Random Forest benchmark on this synthetic holdout set. The 0.50 classification threshold yields low default recall, illustrating the trade-off between sensitivity and false positives. Neither model is described as production-ready.

## Demonstration Credit Score

Logistic predicted PD is transformed into a 300850 demonstration score:

- Base Score = 600
- Base Odds = 20:1
- PDO = 50

Higher PD produces a lower score. Illustrative bands are 750850 Very Low Risk, 700749 Low Risk, 650699 Moderate Risk, 600649 Elevated Risk, 550599 High Risk, and 300549 Very High Risk. These are portfolio-demo bands, not regulatory or institutional credit-policy cutoffs.

## Shiny Dashboard

The dashboard has four tabs: Executive Overview, Credit Risk Analysis, Model Performance, and Applicant Scoring. The scoring interface returns predicted probability of default, a demonstration credit score, an illustrative risk band, and a monitoring label. It generates no approve/reject decision.

Launch locally:

\`\`\`bash
Rscript -e "shiny::runApp('app')"
\`\`\`

## Running the Project

Install R dependencies:

\`\`\`r
install.packages(c("ggplot2", "dplyr", "scales", "tidymodels", "ranger", "shiny"))
\`\`\`

Run the R scripts in the pipeline order above. Database steps require PostgreSQL; configure local, uncommitted environment values from \`.env.example\`, then run the schema, seed, and analytical SQL files with generic commands such as:

\`\`\`bash
psql -d your_database -f database/schema.sql
psql -d your_database -f database/seed.sql
psql -d your_database -f database/analytical_queries.sql
\`\`\`

Generated models, processed data, and reports are intentionally ignored by Git.

## Limitations

- Synthetic dataset; not real institution data.
- Modeling uses disbursed loans only.
- Approval/selection bias is possible and no reject inference is performed.
- Data represents a current-state workflow rather than a full event history.
- Loan performance is a snapshot.
- No external validation or out-of-time validation.
- Score bands are illustrative and are not production credit policy.
- No regulatory validation.

## Screenshots

The repository is ready for manually captured dashboard screenshots in \`docs/screenshots/\`; no placeholder screenshots are included.

## Disclaimer

**This repository is an educational and portfolio project built entirely with synthetic data. It does not contain or reproduce customer data, credit policy, scoring methodology, or proprietary information from IDLC Finance PLC or any other financial institution.**
