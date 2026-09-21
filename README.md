# SME Credit Risk Analytics & Scoring System

## Objective

This portfolio project will demonstrate an end-to-end SME credit risk analytics and scoring workflow: from data preparation and PostgreSQL-based analysis to statistical exploration, predictive modeling, applicant scoring, and Shiny-based management reporting.

## Technology stack

- **R** for data processing, statistical analysis, machine learning, and reporting
- **Shiny** for interactive management dashboards
- **PostgreSQL** and **SQL** for data storage, transformation, and analytical queries
- **Git** for version control

## Planned architecture

1. Synthetic SME loan and application data will be generated and stored under `data/`.
2. PostgreSQL schema, seed, and analytical SQL will be maintained under `database/`.
3. Ordered R scripts will clean data, conduct EDA, train and evaluate models, and score applicants.
4. Reusable model artifacts will be stored under `models/`.
5. Analysis outputs will be documented under `reports/`.
6. A Shiny application in `app/` will surface KPIs, funnel metrics, portfolio performance, and scoring outputs.

## Disclaimer

All datasets used in this project will be synthetic and created solely for educational and portfolio purposes. They do not contain real customer, borrower, or financial-institution data.
