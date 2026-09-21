-- PostgreSQL schema for the dedicated SME Credit Risk project database.
-- Source profiles vary per repeated customer_id, so application-time snapshots
-- are retained on loan_applications rather than incorrectly overwritten in customers.
DROP TABLE IF EXISTS loan_performance;
DROP TABLE IF EXISTS loan_decisions;
DROP TABLE IF EXISTS credit_assessments;
DROP TABLE IF EXISTS loan_applications;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (customer_id VARCHAR(16) PRIMARY KEY);
CREATE TABLE loan_applications (
 application_id VARCHAR(16) PRIMARY KEY,
 customer_id VARCHAR(16) NOT NULL REFERENCES customers(customer_id),
 application_date DATE NOT NULL, business_type VARCHAR(32) NOT NULL,
 business_age_years NUMERIC(4,1) NOT NULL CHECK (business_age_years >= 0),
 number_of_employees INTEGER CHECK (number_of_employees >= 1),
 monthly_revenue NUMERIC(14,2) NOT NULL CHECK (monthly_revenue >= 0),
 annual_revenue NUMERIC(14,2) NOT NULL CHECK (annual_revenue >= 0),
 credit_history_years NUMERIC(4,1) NOT NULL CHECK (credit_history_years >= 0),
 bank_account_age_years NUMERIC(4,1) CHECK (bank_account_age_years >= 0),
 requested_loan_amount NUMERIC(14,2) NOT NULL CHECK (requested_loan_amount >= 0),
 loan_tenure_months INTEGER NOT NULL CHECK (loan_tenure_months > 0), loan_purpose VARCHAR(32) NOT NULL
);
CREATE TABLE credit_assessments (
 application_id VARCHAR(16) PRIMARY KEY REFERENCES loan_applications(application_id),
 existing_loans INTEGER NOT NULL CHECK (existing_loans >= 0),
 existing_monthly_debt NUMERIC(14,2) NOT NULL CHECK (existing_monthly_debt >= 0),
 debt_to_income_ratio NUMERIC(5,3) NOT NULL CHECK (debt_to_income_ratio >= 0),
 bureau_score INTEGER CHECK (bureau_score BETWEEN 300 AND 850),
 previous_defaults INTEGER NOT NULL CHECK (previous_defaults >= 0), collateral_value NUMERIC(14,2) CHECK (collateral_value >= 0)
);
CREATE TABLE loan_decisions (
 application_id VARCHAR(16) PRIMARY KEY REFERENCES loan_applications(application_id),
 application_status VARCHAR(16) NOT NULL CHECK (application_status IN ('Submitted','Under Review','Approved','Rejected','Disbursed')),
 credit_review_date DATE, approval_date DATE, approved_amount NUMERIC(14,2) NOT NULL CHECK (approved_amount >= 0), disbursement_date DATE,
 CHECK (approval_date IS NULL OR credit_review_date IS NOT NULL AND approval_date >= credit_review_date),
 CHECK (disbursement_date IS NULL OR approval_date IS NOT NULL AND disbursement_date >= approval_date),
 CHECK (application_status <> 'Rejected' OR disbursement_date IS NULL),
 CHECK (application_status NOT IN ('Submitted','Under Review') OR (approval_date IS NULL AND disbursement_date IS NULL))
);
CREATE TABLE loan_performance (
 application_id VARCHAR(16) PRIMARY KEY REFERENCES loan_applications(application_id),
 outstanding_balance NUMERIC(14,2) NOT NULL CHECK (outstanding_balance >= 0), days_past_due INTEGER NOT NULL CHECK (days_past_due >= 0),
 missed_payments INTEGER NOT NULL CHECK (missed_payments >= 0), total_payments INTEGER NOT NULL CHECK (total_payments >= 0),
 loan_status VARCHAR(20) NOT NULL CHECK (loan_status IN ('Not Disbursed','Current','DPD 1-29','DPD 30-59','DPD 60-89','DPD 90+','Default','Closed')),
 default_flag SMALLINT NOT NULL CHECK (default_flag IN (0,1)),
 CHECK ((default_flag = 1 AND loan_status = 'Default') OR (default_flag = 0 AND loan_status <> 'Default')),
 CHECK (loan_status <> 'Not Disbursed' OR (outstanding_balance=0 AND days_past_due=0 AND missed_payments=0 AND total_payments=0 AND default_flag=0)),
 CHECK (loan_status <> 'Closed' OR (outstanding_balance=0 AND days_past_due=0 AND default_flag=0))
);
CREATE INDEX idx_loan_applications_application_date ON loan_applications(application_date);
CREATE INDEX idx_loan_applications_customer_id ON loan_applications(customer_id);
CREATE INDEX idx_loan_applications_loan_purpose ON loan_applications(loan_purpose);
CREATE INDEX idx_loan_applications_business_type ON loan_applications(business_type);
CREATE INDEX idx_credit_assessments_bureau_score ON credit_assessments(bureau_score);
CREATE INDEX idx_credit_assessments_dti ON credit_assessments(debt_to_income_ratio);
CREATE INDEX idx_loan_decisions_application_status ON loan_decisions(application_status);
CREATE INDEX idx_loan_decisions_disbursement_date ON loan_decisions(disbursement_date);
CREATE INDEX idx_loan_performance_loan_status ON loan_performance(loan_status);
CREATE INDEX idx_loan_performance_default_flag ON loan_performance(default_flag);
CREATE INDEX idx_loan_performance_days_past_due ON loan_performance(days_past_due);
-- Cross-table rules (approved <= requested; only disbursed may have outcomes;
-- application-to-review chronology) remain validated by the R pipeline and seed.sql.
-- PostgreSQL CHECK constraints cannot safely reference other table rows; no triggers are used.
