-- SME Credit Risk Analytics & Scoring System
-- Step 4: Credit-SME analytical SQL for PostgreSQL
-- Source schema: database/schema.sql
-- Rerunnable analytical layer: CREATE OR REPLACE VIEW + read-only analysis queries.

-- ============================================================
-- 0. REUSABLE ANALYTICAL VIEWS
-- ============================================================

CREATE OR REPLACE VIEW vw_application_funnel AS
SELECT
    d.application_status,
    COUNT(*)::bigint AS application_count,
    ROUND(
        100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0),
        2
    ) AS percentage_of_applications
FROM loan_decisions d
GROUP BY d.application_status;

CREATE OR REPLACE VIEW vw_monthly_credit_kpis AS
SELECT
    DATE_TRUNC('month', a.application_date)::date AS month,
    COUNT(*)::bigint AS applications,
    COUNT(*) FILTER (
        WHERE d.application_status IN ('Approved', 'Disbursed')
    )::bigint AS approvals,
    COUNT(*) FILTER (
        WHERE d.application_status = 'Rejected'
    )::bigint AS rejections,
    COUNT(*) FILTER (
        WHERE d.application_status = 'Disbursed'
    )::bigint AS disbursements,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE d.application_status IN ('Approved', 'Disbursed')
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS approval_rate_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE d.application_status = 'Rejected'
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS rejection_rate_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE d.application_status = 'Disbursed'
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS disbursement_rate_pct,
    ROUND(SUM(a.requested_loan_amount), 2) AS requested_amount,
    ROUND(SUM(d.approved_amount), 2) AS approved_amount,
    COUNT(*) FILTER (
        WHERE d.application_status = 'Disbursed'
          AND p.default_flag = 1
    )::bigint AS defaults,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE d.application_status = 'Disbursed'
              AND p.default_flag = 1
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE d.application_status = 'Disbursed'
            ),
            0
        ),
        2
    ) AS default_rate_disbursed_pct
FROM loan_applications a
JOIN loan_decisions d USING (application_id)
JOIN loan_performance p USING (application_id)
GROUP BY DATE_TRUNC('month', a.application_date);

CREATE OR REPLACE VIEW vw_portfolio_performance AS
SELECT
    a.application_id,
    a.customer_id,
    a.application_date,
    a.business_type,
    a.business_age_years,
    a.number_of_employees,
    a.monthly_revenue,
    a.annual_revenue,
    a.requested_loan_amount,
    a.loan_tenure_months,
    a.loan_purpose,
    ca.existing_loans,
    ca.existing_monthly_debt,
    ca.debt_to_income_ratio,
    ca.bureau_score,
    ca.previous_defaults,
    ca.collateral_value,
    d.application_status,
    d.credit_review_date,
    d.approval_date,
    d.approved_amount,
    d.disbursement_date,
    p.outstanding_balance,
    p.days_past_due,
    p.missed_payments,
    p.total_payments,
    p.loan_status,
    p.default_flag
FROM loan_applications a
JOIN credit_assessments ca USING (application_id)
JOIN loan_decisions d USING (application_id)
JOIN loan_performance p USING (application_id);

CREATE OR REPLACE VIEW vw_default_analysis AS
SELECT
    v.application_id,
    v.customer_id,
    v.application_date,
    v.business_type,
    v.loan_purpose,
    v.application_status,
    v.approved_amount,
    v.outstanding_balance,
    v.default_flag,
    v.previous_defaults,
    v.existing_loans,
    CASE
        WHEN v.bureau_score IS NULL THEN 'Unknown'
        WHEN v.bureau_score < 550 THEN '<550'
        WHEN v.bureau_score < 650 THEN '550-649'
        WHEN v.bureau_score < 700 THEN '650-699'
        WHEN v.bureau_score < 750 THEN '700-749'
        ELSE '750+'
    END AS bureau_score_band,
    CASE
        WHEN v.debt_to_income_ratio IS NULL THEN 'Unknown'
        WHEN v.debt_to_income_ratio < 0.20 THEN '<20%'
        WHEN v.debt_to_income_ratio < 0.35 THEN '20%-34.99%'
        WHEN v.debt_to_income_ratio < 0.50 THEN '35%-49.99%'
        ELSE '50%+'
    END AS dti_band,
    CASE
        WHEN v.business_age_years < 3 THEN '<3 years'
        WHEN v.business_age_years < 5 THEN '3-4.99 years'
        WHEN v.business_age_years < 10 THEN '5-9.99 years'
        ELSE '10+ years'
    END AS business_age_band,
    CASE
        WHEN v.annual_revenue IS NULL OR v.annual_revenue = 0 THEN 'Unknown'
        WHEN v.requested_loan_amount / v.annual_revenue < 0.15 THEN '<15%'
        WHEN v.requested_loan_amount / v.annual_revenue < 0.25 THEN '15%-24.99%'
        WHEN v.requested_loan_amount / v.annual_revenue < 0.40 THEN '25%-39.99%'
        ELSE '40%+'
    END AS loan_to_revenue_band,
    CASE
        WHEN v.collateral_value IS NULL
          OR v.requested_loan_amount = 0 THEN 'Unknown'
        WHEN v.collateral_value / v.requested_loan_amount < 0.50 THEN '<50%'
        WHEN v.collateral_value / v.requested_loan_amount < 1.00 THEN '50%-99.99%'
        WHEN v.collateral_value / v.requested_loan_amount < 1.50 THEN '100%-149.99%'
        ELSE '150%+'
    END AS collateral_coverage_band,
    CASE
        WHEN v.previous_defaults = 0 THEN '0'
        ELSE '1+'
    END AS previous_default_band,
    CASE
        WHEN v.requested_loan_amount < 25000 THEN '<25k'
        WHEN v.requested_loan_amount < 50000 THEN '25k-49.99k'
        WHEN v.requested_loan_amount < 100000 THEN '50k-99.99k'
        ELSE '100k+'
    END AS requested_loan_amount_band
FROM vw_portfolio_performance v;

CREATE OR REPLACE VIEW vw_business_segment_performance AS
SELECT
    a.business_type,
    COUNT(*)::bigint AS disbursed_loan_count,
    ROUND(SUM(d.approved_amount), 2) AS approved_amount,
    ROUND(SUM(p.outstanding_balance), 2) AS outstanding_balance,
    COUNT(*) FILTER (
        WHERE p.default_flag = 1
    )::bigint AS defaults,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE p.default_flag = 1
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS default_rate_pct
FROM loan_applications a
JOIN loan_decisions d USING (application_id)
JOIN loan_performance p USING (application_id)
WHERE d.application_status = 'Disbursed'
GROUP BY a.business_type;

CREATE OR REPLACE VIEW vw_customer_exposure AS
SELECT
    a.customer_id,
    COUNT(*)::bigint AS applications,
    COUNT(*) FILTER (
        WHERE d.application_status = 'Disbursed'
    )::bigint AS disbursed_loans,
    ROUND(SUM(a.requested_loan_amount), 2) AS total_requested_amount,
    ROUND(SUM(d.approved_amount), 2) AS total_approved_amount,
    ROUND(SUM(p.outstanding_balance), 2) AS outstanding_balance,
    COUNT(*) FILTER (
        WHERE p.default_flag = 1
    )::bigint AS defaults
FROM loan_applications a
JOIN loan_decisions d USING (application_id)
JOIN loan_performance p USING (application_id)
GROUP BY a.customer_id;

-- ============================================================
-- 1. PORTFOLIO OVERVIEW
-- Approval rate = (Approved + Disbursed) / all applications.
-- Default rate = defaults among disbursed / disbursed applications.
-- ============================================================

SELECT
    COUNT(*) AS total_applications,
    COUNT(DISTINCT a.customer_id) AS unique_customers,
    COUNT(*) FILTER (
        WHERE d.application_status IN ('Approved', 'Disbursed')
    ) AS approved_or_disbursed,
    COUNT(*) FILTER (
        WHERE d.application_status = 'Rejected'
    ) AS rejected_applications,
    COUNT(*) FILTER (
        WHERE d.application_status = 'Disbursed'
    ) AS disbursed_loans,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE d.application_status IN ('Approved', 'Disbursed')
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS approval_rate_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE d.application_status = 'Rejected'
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS rejection_rate_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE d.application_status = 'Disbursed'
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS disbursement_rate_pct,
    ROUND(AVG(a.requested_loan_amount), 2) AS avg_requested_loan_amount,
    ROUND(
        AVG(d.approved_amount) FILTER (
            WHERE d.application_status IN ('Approved', 'Disbursed')
        ),
        2
    ) AS avg_approved_loan_amount,
    ROUND(SUM(a.requested_loan_amount), 2) AS total_requested_amount,
    ROUND(SUM(d.approved_amount), 2) AS total_approved_amount,
    ROUND(SUM(p.outstanding_balance), 2) AS total_outstanding_balance,
    COUNT(*) FILTER (
        WHERE d.application_status = 'Disbursed'
          AND p.default_flag = 1
    ) AS defaults_among_disbursed,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE d.application_status = 'Disbursed'
              AND p.default_flag = 1
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE d.application_status = 'Disbursed'
            ),
            0
        ),
        2
    ) AS default_rate_disbursed_pct
FROM loan_applications a
JOIN loan_decisions d USING (application_id)
JOIN loan_performance p USING (application_id);

-- ============================================================
-- 2. CURRENT-STATE APPLICATION FUNNEL
-- application_status is current/final state, not event history.
-- The first query reports current-state distribution.
-- The second derives reached-stage counts from recorded workflow dates.
-- ============================================================

SELECT
    application_status,
    application_count,
    percentage_of_applications
FROM vw_application_funnel
ORDER BY CASE application_status
    WHEN 'Submitted' THEN 1
    WHEN 'Under Review' THEN 2
    WHEN 'Approved' THEN 3
    WHEN 'Disbursed' THEN 4
    WHEN 'Rejected' THEN 5
    ELSE 99
END;

SELECT
    COUNT(*) AS total_applications,
    COUNT(*) FILTER (
        WHERE credit_review_date IS NOT NULL
    ) AS reached_credit_review,
    COUNT(*) FILTER (
        WHERE approval_date IS NOT NULL
    ) AS reached_approval,
    COUNT(*) FILTER (
        WHERE disbursement_date IS NOT NULL
    ) AS reached_disbursement,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE credit_review_date IS NOT NULL
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_reached_credit_review,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE approval_date IS NOT NULL
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_reached_approval,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE disbursement_date IS NOT NULL
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_reached_disbursement
FROM loan_decisions;

-- ============================================================
-- 3. PROCESSING-TIME ANALYSIS
-- Date subtraction returns elapsed whole days.
-- ============================================================

WITH durations AS (
    SELECT
        a.application_id,
        a.application_date,
        d.credit_review_date,
        d.approval_date,
        d.disbursement_date,
        d.credit_review_date - a.application_date
            AS application_to_review_days,
        d.approval_date - d.credit_review_date
            AS review_to_approval_days,
        d.disbursement_date - d.approval_date
            AS approval_to_disbursement_days,
        d.approval_date - a.application_date
            AS application_to_approval_days,
        d.disbursement_date - a.application_date
            AS application_to_disbursement_days
    FROM loan_applications a
    JOIN loan_decisions d USING (application_id)
)
SELECT
    ROUND(AVG(application_to_review_days), 2)
        AS avg_application_to_review_days,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY application_to_review_days
        )::numeric,
        2
    ) AS median_application_to_review_days,
    MIN(application_to_review_days)
        AS min_application_to_review_days,
    MAX(application_to_review_days)
        AS max_application_to_review_days,

    ROUND(AVG(review_to_approval_days), 2)
        AS avg_review_to_approval_days,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY review_to_approval_days
        )::numeric,
        2
    ) AS median_review_to_approval_days,
    MIN(review_to_approval_days)
        AS min_review_to_approval_days,
    MAX(review_to_approval_days)
        AS max_review_to_approval_days,

    ROUND(AVG(approval_to_disbursement_days), 2)
        AS avg_approval_to_disbursement_days,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY approval_to_disbursement_days
        )::numeric,
        2
    ) AS median_approval_to_disbursement_days,
    MIN(approval_to_disbursement_days)
        AS min_approval_to_disbursement_days,
    MAX(approval_to_disbursement_days)
        AS max_approval_to_disbursement_days,

    ROUND(AVG(application_to_approval_days), 2)
        AS avg_application_to_approval_days,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY application_to_approval_days
        )::numeric,
        2
    ) AS median_application_to_approval_days,

    ROUND(AVG(application_to_disbursement_days), 2)
        AS avg_application_to_disbursement_days,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY application_to_disbursement_days
        )::numeric,
        2
    ) AS median_application_to_disbursement_days
FROM durations;

WITH monthly_processing AS (
    SELECT
        DATE_TRUNC('month', a.application_date)::date AS month,
        d.credit_review_date - a.application_date
            AS application_to_review_days,
        d.approval_date - d.credit_review_date
            AS review_to_approval_days,
        d.disbursement_date - d.approval_date
            AS approval_to_disbursement_days,
        d.disbursement_date - a.application_date
            AS application_to_disbursement_days
    FROM loan_applications a
    JOIN loan_decisions d USING (application_id)
)
SELECT
    month,
    ROUND(AVG(application_to_review_days), 2)
        AS avg_application_to_review_days,
    ROUND(AVG(review_to_approval_days), 2)
        AS avg_review_to_approval_days,
    ROUND(AVG(approval_to_disbursement_days), 2)
        AS avg_approval_to_disbursement_days,
    ROUND(AVG(application_to_disbursement_days), 2)
        AS avg_application_to_disbursement_days
FROM monthly_processing
GROUP BY month
ORDER BY month;

-- ============================================================
-- 4. MONTHLY CREDIT KPI TREND ANALYSIS
-- Current default outcomes are attributed to original application month;
-- this is not a month-by-month performance-history series.
-- ============================================================

SELECT
    month,
    applications,
    approvals,
    rejections,
    disbursements,
    approval_rate_pct,
    rejection_rate_pct,
    disbursement_rate_pct,
    requested_amount,
    approved_amount,
    defaults,
    default_rate_disbursed_pct
FROM vw_monthly_credit_kpis
ORDER BY month;

WITH monthly AS (
    SELECT
        month,
        applications,
        approval_rate_pct,
        default_rate_disbursed_pct,
        requested_amount
    FROM vw_monthly_credit_kpis
)
SELECT
    month,
    applications,
    applications - LAG(applications) OVER (
        ORDER BY month
    ) AS application_change_vs_prior_month,
    approval_rate_pct,
    default_rate_disbursed_pct,
    requested_amount,
    ROUND(
        SUM(requested_amount) OVER (
            ORDER BY month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        2
    ) AS cumulative_requested_amount
FROM monthly
ORDER BY month;

-- ============================================================
-- 5. CREDIT-RISK SEGMENTATION
-- All default-rate denominators below are disbursed loans only.
-- ============================================================

SELECT
    bureau_score_band,
    COUNT(*) AS disbursed_loans,
    COUNT(*) FILTER (
        WHERE default_flag = 1
    ) AS defaults,
    ROUND(100.0 * AVG(default_flag), 2) AS default_rate_pct,
    ROUND(SUM(outstanding_balance), 2) AS outstanding_balance
FROM vw_default_analysis
WHERE application_status = 'Disbursed'
GROUP BY bureau_score_band
ORDER BY CASE bureau_score_band
    WHEN '<550' THEN 1
    WHEN '550-649' THEN 2
    WHEN '650-699' THEN 3
    WHEN '700-749' THEN 4
    WHEN '750+' THEN 5
    ELSE 6
END;

SELECT
    dti_band,
    COUNT(*) AS disbursed_loans,
    COUNT(*) FILTER (
        WHERE default_flag = 1
    ) AS defaults,
    ROUND(100.0 * AVG(default_flag), 2) AS default_rate_pct,
    ROUND(SUM(outstanding_balance), 2) AS outstanding_balance
FROM vw_default_analysis
WHERE application_status = 'Disbursed'
GROUP BY dti_band
ORDER BY CASE dti_band
    WHEN '<20%' THEN 1
    WHEN '20%-34.99%' THEN 2
    WHEN '35%-49.99%' THEN 3
    WHEN '50%+' THEN 4
    ELSE 5
END;

SELECT
    business_type,
    COUNT(*) AS disbursed_loans,
    COUNT(*) FILTER (
        WHERE default_flag = 1
    ) AS defaults,
    ROUND(100.0 * AVG(default_flag), 2) AS default_rate_pct,
    ROUND(SUM(outstanding_balance), 2) AS outstanding_balance
FROM vw_default_analysis
WHERE application_status = 'Disbursed'
GROUP BY business_type
ORDER BY default_rate_pct DESC, disbursed_loans DESC;

SELECT
    loan_purpose,
    COUNT(*) AS disbursed_loans,
    COUNT(*) FILTER (
        WHERE default_flag = 1
    ) AS defaults,
    ROUND(100.0 * AVG(default_flag), 2) AS default_rate_pct,
    ROUND(SUM(outstanding_balance), 2) AS outstanding_balance
FROM vw_default_analysis
WHERE application_status = 'Disbursed'
GROUP BY loan_purpose
ORDER BY default_rate_pct DESC, disbursed_loans DESC;

SELECT
    business_age_band,
    COUNT(*) AS disbursed_loans,
    COUNT(*) FILTER (
        WHERE default_flag = 1
    ) AS defaults,
    ROUND(100.0 * AVG(default_flag), 2) AS default_rate_pct
FROM vw_default_analysis
WHERE application_status = 'Disbursed'
GROUP BY business_age_band
ORDER BY CASE business_age_band
    WHEN '<3 years' THEN 1
    WHEN '3-4.99 years' THEN 2
    WHEN '5-9.99 years' THEN 3
    ELSE 4
END;

SELECT
    requested_loan_amount_band,
    COUNT(*) AS disbursed_loans,
    COUNT(*) FILTER (
        WHERE default_flag = 1
    ) AS defaults,
    ROUND(100.0 * AVG(default_flag), 2) AS default_rate_pct
FROM vw_default_analysis
WHERE application_status = 'Disbursed'
GROUP BY requested_loan_amount_band
ORDER BY requested_loan_amount_band;

SELECT
    previous_default_band,
    COUNT(*) AS disbursed_loans,
    COUNT(*) FILTER (
        WHERE default_flag = 1
    ) AS defaults,
    ROUND(100.0 * AVG(default_flag), 2) AS default_rate_pct
FROM vw_default_analysis
WHERE application_status = 'Disbursed'
GROUP BY previous_default_band
ORDER BY previous_default_band;

SELECT
    loan_to_revenue_band,
    COUNT(*) AS disbursed_loans,
    COUNT(*) FILTER (
        WHERE default_flag = 1
    ) AS defaults,
    ROUND(100.0 * AVG(default_flag), 2) AS default_rate_pct
FROM vw_default_analysis
WHERE application_status = 'Disbursed'
GROUP BY loan_to_revenue_band
ORDER BY CASE loan_to_revenue_band
    WHEN '<15%' THEN 1
    WHEN '15%-24.99%' THEN 2
    WHEN '25%-39.99%' THEN 3
    WHEN '40%+' THEN 4
    ELSE 5
END;

SELECT
    collateral_coverage_band,
    COUNT(*) AS disbursed_loans,
    COUNT(*) FILTER (
        WHERE default_flag = 1
    ) AS defaults,
    ROUND(100.0 * AVG(default_flag), 2) AS default_rate_pct
FROM vw_default_analysis
WHERE application_status = 'Disbursed'
GROUP BY collateral_coverage_band
ORDER BY collateral_coverage_band;

SELECT
    existing_loans,
    COUNT(*) AS disbursed_loans,
    COUNT(*) FILTER (
        WHERE default_flag = 1
    ) AS defaults,
    ROUND(100.0 * AVG(default_flag), 2) AS default_rate_pct
FROM vw_default_analysis
WHERE application_status = 'Disbursed'
GROUP BY existing_loans
ORDER BY existing_loans;

-- ============================================================
-- 6. DELINQUENCY AND PORTFOLIO QUALITY
-- Active portfolio denominator: disbursed loans excluding Closed.
-- PAR is balance-based. Account-based delinquency is also shown.
-- ============================================================

SELECT
    p.loan_status,
    COUNT(*) AS account_count,
    ROUND(SUM(p.outstanding_balance), 2) AS outstanding_balance,
    ROUND(
        100.0 * COUNT(*)
        / NULLIF(SUM(COUNT(*)) OVER (), 0),
        2
    ) AS account_share_pct,
    ROUND(
        100.0 * SUM(p.outstanding_balance)
        / NULLIF(
            SUM(SUM(p.outstanding_balance)) OVER (),
            0
        ),
        2
    ) AS balance_share_pct
FROM loan_performance p
JOIN loan_decisions d USING (application_id)
WHERE d.application_status = 'Disbursed'
GROUP BY p.loan_status
ORDER BY CASE p.loan_status
    WHEN 'Current' THEN 1
    WHEN 'DPD 1-29' THEN 2
    WHEN 'DPD 30-59' THEN 3
    WHEN 'DPD 60-89' THEN 4
    WHEN 'DPD 90+' THEN 5
    WHEN 'Default' THEN 6
    WHEN 'Closed' THEN 7
    ELSE 8
END;

WITH active AS (
    SELECT
        p.application_id,
        p.outstanding_balance,
        p.days_past_due,
        p.default_flag
    FROM loan_performance p
    JOIN loan_decisions d USING (application_id)
    WHERE d.application_status = 'Disbursed'
      AND p.loan_status <> 'Closed'
),
totals AS (
    SELECT
        SUM(outstanding_balance) AS total_active_balance,
        COUNT(*) AS active_accounts
    FROM active
)
SELECT
    ROUND(
        100.0 * COALESCE(
            SUM(outstanding_balance) FILTER (
                WHERE days_past_due >= 30 OR default_flag = 1
            ),
            0
        ) / NULLIF(MAX(total_active_balance), 0),
        2
    ) AS par_30_balance_pct,
    ROUND(
        100.0 * COALESCE(
            SUM(outstanding_balance) FILTER (
                WHERE days_past_due >= 60 OR default_flag = 1
            ),
            0
        ) / NULLIF(MAX(total_active_balance), 0),
        2
    ) AS par_60_balance_pct,
    ROUND(
        100.0 * COALESCE(
            SUM(outstanding_balance) FILTER (
                WHERE days_past_due >= 90 OR default_flag = 1
            ),
            0
        ) / NULLIF(MAX(total_active_balance), 0),
        2
    ) AS par_90_balance_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE days_past_due >= 30 OR default_flag = 1
        ) / NULLIF(MAX(active_accounts), 0),
        2
    ) AS delinquent_30_account_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE days_past_due >= 60 OR default_flag = 1
        ) / NULLIF(MAX(active_accounts), 0),
        2
    ) AS delinquent_60_account_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE days_past_due >= 90 OR default_flag = 1
        ) / NULLIF(MAX(active_accounts), 0),
        2
    ) AS delinquent_90_account_pct
FROM active
CROSS JOIN totals;

-- ============================================================
-- 7. PORTFOLIO CONCENTRATION
-- ============================================================

SELECT
    a.business_type,
    COUNT(*) FILTER (
        WHERE d.application_status = 'Disbursed'
    ) AS disbursed_loans,
    ROUND(
        SUM(d.approved_amount) FILTER (
            WHERE d.application_status = 'Disbursed'
        ),
        2
    ) AS approved_amount,
    ROUND(
        SUM(p.outstanding_balance) FILTER (
            WHERE d.application_status = 'Disbursed'
        ),
        2
    ) AS outstanding_balance,
    ROUND(
        100.0 * SUM(p.outstanding_balance) FILTER (
            WHERE d.application_status = 'Disbursed'
        )
        / NULLIF(
            SUM(
                SUM(p.outstanding_balance) FILTER (
                    WHERE d.application_status = 'Disbursed'
                )
            ) OVER (),
            0
        ),
        2
    ) AS outstanding_portfolio_share_pct
FROM loan_applications a
JOIN loan_decisions d USING (application_id)
JOIN loan_performance p USING (application_id)
GROUP BY a.business_type
ORDER BY outstanding_balance DESC NULLS LAST;

SELECT
    a.loan_purpose,
    COUNT(*) FILTER (
        WHERE d.application_status = 'Disbursed'
    ) AS disbursed_loans,
    ROUND(
        SUM(d.approved_amount) FILTER (
            WHERE d.application_status = 'Disbursed'
        ),
        2
    ) AS approved_amount,
    ROUND(
        SUM(p.outstanding_balance) FILTER (
            WHERE d.application_status = 'Disbursed'
        ),
        2
    ) AS outstanding_balance,
    ROUND(
        100.0 * SUM(p.outstanding_balance) FILTER (
            WHERE d.application_status = 'Disbursed'
        )
        / NULLIF(
            SUM(
                SUM(p.outstanding_balance) FILTER (
                    WHERE d.application_status = 'Disbursed'
                )
            ) OVER (),
            0
        ),
        2
    ) AS outstanding_portfolio_share_pct
FROM loan_applications a
JOIN loan_decisions d USING (application_id)
JOIN loan_performance p USING (application_id)
GROUP BY a.loan_purpose
ORDER BY outstanding_balance DESC NULLS LAST;

SELECT
    bureau_score_band,
    COUNT(*) AS disbursed_loans,
    ROUND(SUM(approved_amount), 2) AS approved_amount,
    ROUND(SUM(outstanding_balance), 2) AS outstanding_balance,
    ROUND(
        100.0 * SUM(outstanding_balance)
        / NULLIF(
            SUM(SUM(outstanding_balance)) OVER (),
            0
        ),
        2
    ) AS outstanding_portfolio_share_pct,
    DENSE_RANK() OVER (
        ORDER BY SUM(outstanding_balance) DESC
    ) AS exposure_rank
FROM vw_default_analysis
WHERE application_status = 'Disbursed'
GROUP BY bureau_score_band
ORDER BY exposure_rank, bureau_score_band;

SELECT
    customer_id,
    applications,
    disbursed_loans,
    total_requested_amount,
    total_approved_amount,
    outstanding_balance,
    defaults,
    DENSE_RANK() OVER (
        ORDER BY outstanding_balance DESC
    ) AS exposure_rank
FROM vw_customer_exposure
WHERE outstanding_balance > 0
ORDER BY exposure_rank, customer_id
LIMIT 20;

-- ============================================================
-- 8. SNAPSHOT COHORT / VINTAGE ANALYSIS
-- This is not true longitudinal vintage tracking because the data
-- contains one current performance snapshot, not monthly histories.
-- ============================================================

SELECT
    DATE_TRUNC('month', d.disbursement_date)::date
        AS disbursement_cohort,
    COUNT(*) AS disbursed_loans,
    ROUND(SUM(d.approved_amount), 2) AS approved_amount,
    ROUND(SUM(p.outstanding_balance), 2) AS outstanding_balance,
    COUNT(*) FILTER (
        WHERE p.default_flag = 1
    ) AS defaults,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE p.default_flag = 1
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS snapshot_default_rate_pct
FROM loan_decisions d
JOIN loan_performance p USING (application_id)
WHERE d.application_status = 'Disbursed'
  AND d.disbursement_date IS NOT NULL
GROUP BY DATE_TRUNC('month', d.disbursement_date)
ORDER BY disbursement_cohort;

-- ============================================================
-- 9. CUSTOMER-LEVEL REPEAT-APPLICATION / EXPOSURE ANALYSIS
-- Repeat applications are treated only as repeat borrowing/application
-- behavior, never as evidence of fraud or abuse.
-- ============================================================

SELECT
    customer_id,
    applications,
    disbursed_loans,
    total_requested_amount,
    total_approved_amount,
    outstanding_balance,
    defaults
FROM vw_customer_exposure
WHERE applications > 1
ORDER BY applications DESC, total_requested_amount DESC, customer_id;

SELECT
    COUNT(*) AS customers_with_repeat_applications,
    ROUND(AVG(applications), 2) AS avg_applications_among_repeat_customers,
    MAX(applications) AS max_applications_for_one_customer
FROM vw_customer_exposure
WHERE applications > 1;

-- ============================================================
-- 10. FINAL RECONCILIATION / SMOKE TEST
-- Expected validated portfolio values:
-- applications=10000, approved+disbursed=7221, rejected=2279,
-- disbursed=6373, defaults=1350, approval=72.21%,
-- rejection=22.79%, disbursement=63.73%, default=21.18%.
-- ============================================================

SELECT
    COUNT(*) AS applications,
    COUNT(*) FILTER (
        WHERE d.application_status IN ('Approved', 'Disbursed')
    ) AS approved_plus_disbursed,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE d.application_status IN ('Approved', 'Disbursed')
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS approval_rate_pct,
    COUNT(*) FILTER (
        WHERE d.application_status = 'Rejected'
    ) AS rejected,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE d.application_status = 'Rejected'
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS rejection_rate_pct,
    COUNT(*) FILTER (
        WHERE d.application_status = 'Disbursed'
    ) AS disbursed,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE d.application_status = 'Disbursed'
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS disbursement_rate_pct,
    COUNT(*) FILTER (
        WHERE d.application_status = 'Disbursed'
          AND p.default_flag = 1
    ) AS defaults,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE d.application_status = 'Disbursed'
              AND p.default_flag = 1
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE d.application_status = 'Disbursed'
            ),
            0
        ),
        2
    ) AS default_rate_disbursed_pct
FROM loan_applications a
JOIN loan_decisions d USING (application_id)
JOIN loan_performance p USING (application_id);

SELECT
    (SELECT COUNT(*) FROM vw_application_funnel)
        AS funnel_rows,
    (SELECT COUNT(*) FROM vw_monthly_credit_kpis)
        AS monthly_kpi_rows,
    (SELECT COUNT(*) FROM vw_portfolio_performance)
        AS portfolio_performance_rows,
    (SELECT COUNT(*) FROM vw_default_analysis)
        AS default_analysis_rows,
    (SELECT COUNT(*) FROM vw_business_segment_performance)
        AS business_segment_rows,
    (SELECT COUNT(*) FROM vw_customer_exposure)
        AS customer_exposure_rows;
