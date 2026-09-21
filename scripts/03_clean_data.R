# SME Credit Risk Analytics & Scoring System
# Step 5: deterministic R data cleaning and feature engineering pipeline.
# Run from the repository root with:
#   Rscript scripts/03_clean_data.R

raw_path <- file.path("data", "raw", "sme_loan_applications.csv")
clean_path <- file.path("data", "processed", "sme_credit_clean.csv")
model_path <- file.path("data", "processed", "sme_credit_modeling.csv")

if (!file.exists(raw_path)) {
  stop("Raw dataset not found: ", raw_path)
}

# ------------------------------------------------------------------
# 1. Load source data and normalize core data types
# ------------------------------------------------------------------

d <- read.csv(
  raw_path,
  na.strings = "",
  stringsAsFactors = FALSE,
  check.names = FALSE
)

source_rows <- nrow(d)
source_cols <- ncol(d)

expected_columns <- c(
  "application_id",
  "customer_id",
  "application_date",
  "business_type",
  "business_age_years",
  "number_of_employees",
  "monthly_revenue",
  "annual_revenue",
  "requested_loan_amount",
  "loan_tenure_months",
  "loan_purpose",
  "existing_loans",
  "existing_monthly_debt",
  "debt_to_income_ratio",
  "bureau_score",
  "credit_history_years",
  "previous_defaults",
  "collateral_value",
  "bank_account_age_years",
  "application_status",
  "credit_review_date",
  "approval_date",
  "disbursement_date",
  "approved_amount",
  "outstanding_balance",
  "days_past_due",
  "missed_payments",
  "total_payments",
  "loan_status",
  "default_flag"
)

missing_columns <- setdiff(expected_columns, names(d))
extra_columns <- setdiff(names(d), expected_columns)

if (length(missing_columns) > 0L) {
  stop(
    "Required source columns are missing: ",
    paste(missing_columns, collapse = ", ")
  )
}

if (length(extra_columns) > 0L) {
  warning(
    "Unexpected source columns found and retained: ",
    paste(extra_columns, collapse = ", ")
  )
}

character_cols <- c(
  "application_id",
  "customer_id",
  "business_type",
  "loan_purpose",
  "application_status",
  "loan_status"
)

for (x in character_cols) {
  d[[x]] <- as.character(d[[x]])
}

date_cols <- c(
  "application_date",
  "credit_review_date",
  "approval_date",
  "disbursement_date"
)

for (x in date_cols) {
  d[[x]] <- as.Date(d[[x]])
}

numeric_cols <- c(
  "business_age_years",
  "number_of_employees",
  "monthly_revenue",
  "annual_revenue",
  "requested_loan_amount",
  "loan_tenure_months",
  "existing_loans",
  "existing_monthly_debt",
  "debt_to_income_ratio",
  "bureau_score",
  "credit_history_years",
  "previous_defaults",
  "collateral_value",
  "bank_account_age_years",
  "approved_amount",
  "outstanding_balance",
  "days_past_due",
  "missed_payments",
  "total_payments",
  "default_flag"
)

for (x in numeric_cols) {
  d[[x]] <- as.numeric(d[[x]])
}

d$default_flag <- as.integer(d$default_flag)

# ------------------------------------------------------------------
# 2. Pre-cleaning data-quality checks
# ------------------------------------------------------------------

application_status_levels <- c(
  "Rejected",
  "Submitted",
  "Under Review",
  "Approved",
  "Disbursed"
)

loan_status_levels <- c(
  "Not Disbursed",
  "Current",
  "DPD 1-29",
  "DPD 30-59",
  "DPD 60-89",
  "DPD 90+",
  "Default",
  "Closed"
)

money_cols <- c(
  "monthly_revenue",
  "annual_revenue",
  "requested_loan_amount",
  "existing_monthly_debt",
  "collateral_value",
  "approved_amount",
  "outstanding_balance"
)

duplicate_application_ids <- sum(duplicated(d$application_id))
duplicate_full_rows <- sum(duplicated(d))
missing_before <- colSums(is.na(d))

invalid_default_flag <- sum(
  !is.na(d$default_flag) & !(d$default_flag %in% c(0L, 1L))
)

invalid_application_status <- sum(
  is.na(d$application_status) |
    !(d$application_status %in% application_status_levels)
)

invalid_loan_status <- sum(
  is.na(d$loan_status) |
    !(d$loan_status %in% loan_status_levels)
)

negative_money_values <- sum(vapply(
  d[money_cols],
  function(x) sum(!is.na(x) & x < 0),
  integer(1)
))

invalid_bureau_score <- sum(
  !is.na(d$bureau_score) &
    (d$bureau_score < 300 | d$bureau_score > 850)
)

invalid_dti <- sum(
  !is.na(d$debt_to_income_ratio) &
    (d$debt_to_income_ratio < 0 | d$debt_to_income_ratio > 1)
)

invalid_workflow_dates <- sum(
  (!is.na(d$credit_review_date) &
     d$credit_review_date < d$application_date) |
    (!is.na(d$approval_date) &
       (is.na(d$credit_review_date) |
          d$approval_date < d$credit_review_date)) |
    (!is.na(d$disbursement_date) &
       (is.na(d$approval_date) |
          d$disbursement_date < d$approval_date))
)

cat("SOURCE DATA QUALITY CHECKS\n")
cat("Rows:", source_rows, "\n")
cat("Columns:", source_cols, "\n")
cat("Duplicate application IDs:", duplicate_application_ids, "\n")
cat("Duplicate full rows:", duplicate_full_rows, "\n")
cat("Invalid default_flag values:", invalid_default_flag, "\n")
cat("Invalid application statuses:", invalid_application_status, "\n")
cat("Invalid loan statuses:", invalid_loan_status, "\n")
cat("Negative monetary values:", negative_money_values, "\n")
cat("Invalid bureau scores:", invalid_bureau_score, "\n")
cat("Invalid DTI values:", invalid_dti, "\n")
cat("Invalid workflow date sequences:", invalid_workflow_dates, "\n\n")

cat("SOURCE MISSINGNESS\n")
print(data.frame(
  column = names(d),
  missing = as.integer(missing_before),
  percent = round(100 * missing_before / nrow(d), 3),
  row.names = NULL
))
cat("\n")

critical_violations <- c(
  source_rows != 10000L,
  source_cols != 30L,
  duplicate_application_ids > 0L,
  anyNA(d$application_id),
  anyNA(d$customer_id),
  anyNA(d$application_date),
  anyNA(d$application_status),
  anyNA(d$default_flag),
  invalid_default_flag > 0L,
  invalid_application_status > 0L,
  invalid_loan_status > 0L,
  negative_money_values > 0L,
  invalid_bureau_score > 0L,
  invalid_dti > 0L,
  invalid_workflow_dates > 0L
)

if (any(critical_violations)) {
  stop(
    "Critical structural/data-quality validation failed. ",
    "Run scripts/02_validate_data.R and inspect the source before cleaning."
  )
}

# ------------------------------------------------------------------
# 3. Missingness indicators and deterministic median imputation
# ------------------------------------------------------------------

imputation_source_cols <- c(
  "number_of_employees",
  "bureau_score",
  "collateral_value",
  "bank_account_age_years"
)

for (x in imputation_source_cols) {
  d[[paste0(x, "_missing")]] <- as.integer(is.na(d[[x]]))
}

median_or_stop <- function(x, column_name) {
  m <- median(x, na.rm = TRUE)
  if (!is.finite(m)) {
    stop("Cannot calculate finite median for ", column_name)
  }
  m
}

number_of_employees_median <- median_or_stop(
  d$number_of_employees,
  "number_of_employees"
)

bureau_score_median <- median_or_stop(
  d$bureau_score,
  "bureau_score"
)

collateral_value_median <- median_or_stop(
  d$collateral_value,
  "collateral_value"
)

bank_account_age_years_median <- median_or_stop(
  d$bank_account_age_years,
  "bank_account_age_years"
)

d$number_of_employees_imputed <- ifelse(
  is.na(d$number_of_employees),
  number_of_employees_median,
  d$number_of_employees
)

d$bureau_score_imputed <- ifelse(
  is.na(d$bureau_score),
  bureau_score_median,
  d$bureau_score
)

d$collateral_value_imputed <- ifelse(
  is.na(d$collateral_value),
  collateral_value_median,
  d$collateral_value
)

d$bank_account_age_years_imputed <- ifelse(
  is.na(d$bank_account_age_years),
  bank_account_age_years_median,
  d$bank_account_age_years
)

# ------------------------------------------------------------------
# 4. Credit-decision-time feature engineering
# ------------------------------------------------------------------

safe_ratio <- function(numerator, denominator) {
  out <- numerator / denominator
  out[
    is.na(numerator) |
      is.na(denominator) |
      denominator == 0 |
      !is.finite(out)
  ] <- NA_real_
  out
}

d$loan_to_annual_revenue_ratio <- safe_ratio(
  d$requested_loan_amount,
  d$annual_revenue
)

# Keep the reporting ratio based on the original collateral value.
d$collateral_coverage_ratio <- safe_ratio(
  d$collateral_value,
  d$requested_loan_amount
)

# Modeling-friendly counterpart based on the deterministic imputed collateral.
d$collateral_coverage_ratio_imputed <- safe_ratio(
  d$collateral_value_imputed,
  d$requested_loan_amount
)

d$monthly_debt_to_revenue_ratio <- safe_ratio(
  d$existing_monthly_debt,
  d$monthly_revenue
)

d$revenue_per_employee <- safe_ratio(
  d$monthly_revenue,
  d$number_of_employees_imputed
)

d$requested_amount_per_tenure_month <- safe_ratio(
  d$requested_loan_amount,
  d$loan_tenure_months
)

d$has_previous_default <- as.integer(d$previous_defaults >= 1)
d$has_existing_loan <- as.integer(d$existing_loans >= 1)

d$has_collateral <- ifelse(
  is.na(d$collateral_value),
  NA_integer_,
  as.integer(d$collateral_value > 0)
)

# ------------------------------------------------------------------
# 5. Reporting risk bands
# ------------------------------------------------------------------

make_ordered_band <- function(
  values,
  breaks,
  labels,
  unknown_label = "Unknown"
) {
  band <- cut(
    values,
    breaks = breaks,
    labels = labels,
    right = FALSE,
    include.lowest = TRUE
  )
  band <- as.character(band)
  band[is.na(band)] <- unknown_label
  factor(
    band,
    levels = c(labels, unknown_label),
    ordered = TRUE
  )
}

d$bureau_score_band <- make_ordered_band(
  d$bureau_score,
  breaks = c(-Inf, 550, 650, 700, 750, Inf),
  labels = c("<550", "550-649", "650-699", "700-749", "750+")
)

d$dti_band <- make_ordered_band(
  d$debt_to_income_ratio,
  breaks = c(-Inf, 0.20, 0.35, 0.50, Inf),
  labels = c("<20%", "20%-34.99%", "35%-49.99%", "50%+")
)

d$business_age_band <- make_ordered_band(
  d$business_age_years,
  breaks = c(-Inf, 3, 5, 10, Inf),
  labels = c(
    "<3 years",
    "3-4.99 years",
    "5-9.99 years",
    "10+ years"
  )
)

d$loan_to_revenue_band <- make_ordered_band(
  d$loan_to_annual_revenue_ratio,
  breaks = c(-Inf, 0.15, 0.25, 0.40, Inf),
  labels = c("<15%", "15%-24.99%", "25%-39.99%", "40%+")
)

d$collateral_coverage_band <- make_ordered_band(
  d$collateral_coverage_ratio,
  breaks = c(-Inf, 0.50, 1.00, 1.50, Inf),
  labels = c("<50%", "50%-99.99%", "100%-149.99%", "150%+")
)

d$requested_loan_amount_band <- make_ordered_band(
  d$requested_loan_amount,
  breaks = c(-Inf, 25000, 50000, 100000, Inf),
  labels = c("<25k", "25k-49.99k", "50k-99.99k", "100k+")
)

# ------------------------------------------------------------------
# 6. Reporting-only workflow duration features
# ------------------------------------------------------------------

date_diff_days <- function(later, earlier) {
  out <- as.numeric(later - earlier)
  out[is.na(later) | is.na(earlier)] <- NA_real_
  out
}

d$application_to_review_days <- date_diff_days(
  d$credit_review_date,
  d$application_date
)

d$review_to_approval_days <- date_diff_days(
  d$approval_date,
  d$credit_review_date
)

d$approval_to_disbursement_days <- date_diff_days(
  d$disbursement_date,
  d$approval_date
)

d$application_to_approval_days <- date_diff_days(
  d$approval_date,
  d$application_date
)

d$application_to_disbursement_days <- date_diff_days(
  d$disbursement_date,
  d$application_date
)

# ------------------------------------------------------------------
# 7. Explicit leakage controls and modeling-safe predictor dataset
# ------------------------------------------------------------------

leakage_columns <- c(
  "outstanding_balance",
  "days_past_due",
  "missed_payments",
  "total_payments",
  "loan_status",
  "application_status",
  "credit_review_date",
  "approval_date",
  "disbursement_date",
  "approved_amount",
  "application_to_review_days",
  "review_to_approval_days",
  "approval_to_disbursement_days",
  "application_to_approval_days",
  "application_to_disbursement_days"
)

modeling_columns <- c(
  "application_id",
  "customer_id",
  "default_flag",
  "business_type",
  "business_age_years",
  "number_of_employees_imputed",
  "monthly_revenue",
  "annual_revenue",
  "requested_loan_amount",
  "loan_tenure_months",
  "loan_purpose",
  "existing_loans",
  "existing_monthly_debt",
  "debt_to_income_ratio",
  "bureau_score_imputed",
  "credit_history_years",
  "previous_defaults",
  "collateral_value_imputed",
  "bank_account_age_years_imputed",
  "loan_to_annual_revenue_ratio",
  "collateral_coverage_ratio_imputed",
  "monthly_debt_to_revenue_ratio",
  "revenue_per_employee",
  "requested_amount_per_tenure_month",
  "has_previous_default",
  "has_existing_loan",
  "number_of_employees_missing",
  "bureau_score_missing",
  "collateral_value_missing",
  "bank_account_age_years_missing"
)

modeling_source <- d[d$application_status == "Disbursed", , drop = FALSE]
modeling <- modeling_source[, modeling_columns, drop = FALSE]

# Keep model-facing feature name concise and consistent with later scripts.
names(modeling)[
  names(modeling) == "collateral_coverage_ratio_imputed"
] <- "collateral_coverage_ratio"

predictor_columns <- setdiff(
  names(modeling),
  c("application_id", "customer_id", "default_flag")
)

prohibited_model_predictors <- intersect(
  predictor_columns,
  c(leakage_columns, "default_flag")
)

if (length(prohibited_model_predictors) > 0L) {
  stop(
    "Leakage columns found in modeling predictors: ",
    paste(prohibited_model_predictors, collapse = ", ")
  )
}

# ------------------------------------------------------------------
# 8. Output validation
# ------------------------------------------------------------------

clean_rows <- nrow(d)
clean_cols <- ncol(d)
model_rows <- nrow(modeling)
model_defaults <- sum(modeling$default_flag == 1L)
model_non_defaults <- sum(modeling$default_flag == 0L)
model_default_rate <- mean(modeling$default_flag)

ratio_cols_clean <- c(
  "loan_to_annual_revenue_ratio",
  "collateral_coverage_ratio",
  "collateral_coverage_ratio_imputed",
  "monthly_debt_to_revenue_ratio",
  "revenue_per_employee",
  "requested_amount_per_tenure_month"
)

has_infinite_ratio <- any(vapply(
  d[ratio_cols_clean],
  function(x) any(is.infinite(x), na.rm = TRUE),
  logical(1)
))

numeric_predictors <- predictor_columns[
  vapply(modeling[predictor_columns], is.numeric, logical(1))
]

invalid_numeric_predictor <- any(vapply(
  modeling[numeric_predictors],
  function(x) any(is.infinite(x), na.rm = TRUE),
  logical(1)
))

expected_band_values <- list(
  bureau_score_band = c(
    "<550",
    "550-649",
    "650-699",
    "700-749",
    "750+",
    "Unknown"
  ),
  dti_band = c(
    "<20%",
    "20%-34.99%",
    "35%-49.99%",
    "50%+",
    "Unknown"
  ),
  business_age_band = c(
    "<3 years",
    "3-4.99 years",
    "5-9.99 years",
    "10+ years",
    "Unknown"
  ),
  loan_to_revenue_band = c(
    "<15%",
    "15%-24.99%",
    "25%-39.99%",
    "40%+",
    "Unknown"
  ),
  collateral_coverage_band = c(
    "<50%",
    "50%-99.99%",
    "100%-149.99%",
    "150%+",
    "Unknown"
  ),
  requested_loan_amount_band = c(
    "<25k",
    "25k-49.99k",
    "50k-99.99k",
    "100k+",
    "Unknown"
  )
)

invalid_band_values <- vapply(
  names(expected_band_values),
  function(x) {
    observed <- unique(as.character(d[[x]]))
    any(!(observed %in% expected_band_values[[x]]))
  },
  logical(1)
)

stopifnot(
  clean_rows == 10000L,
  model_rows == 6373L,
  model_defaults == 1350L,
  model_non_defaults == 5023L,
  abs(model_default_rate - 0.2118) < 0.001,
  !anyDuplicated(d$application_id),
  !anyDuplicated(modeling$application_id),
  all(d$default_flag %in% c(0L, 1L)),
  all(modeling$default_flag %in% c(0L, 1L)),
  !has_infinite_ratio,
  !invalid_numeric_predictor,
  !any(invalid_band_values),
  length(prohibited_model_predictors) == 0L
)

# ------------------------------------------------------------------
# 9. Reproducible output files
# ------------------------------------------------------------------

dir.create(
  dirname(clean_path),
  recursive = TRUE,
  showWarnings = FALSE
)

write.csv(
  d,
  clean_path,
  row.names = FALSE,
  na = ""
)

write.csv(
  modeling,
  model_path,
  row.names = FALSE,
  na = ""
)

# ------------------------------------------------------------------
# 10. Concise execution report
# ------------------------------------------------------------------

engineered_features <- c(
  "loan_to_annual_revenue_ratio",
  "collateral_coverage_ratio",
  "collateral_coverage_ratio_imputed",
  "monthly_debt_to_revenue_ratio",
  "revenue_per_employee",
  "requested_amount_per_tenure_month",
  "has_previous_default",
  "has_existing_loan",
  "has_collateral",
  "bureau_score_band",
  "dti_band",
  "business_age_band",
  "loan_to_revenue_band",
  "collateral_coverage_band",
  "requested_loan_amount_band",
  "application_to_review_days",
  "review_to_approval_days",
  "approval_to_disbursement_days",
  "application_to_approval_days",
  "application_to_disbursement_days"
)

cat("\nSTEP 5 DATA CLEANING & FEATURE ENGINEERING REPORT\n")
cat("------------------------------------------------\n")

cat("\nSOURCE\n")
cat("Rows:", source_rows, "\n")
cat("Columns:", source_cols, "\n")
cat("Duplicate application IDs:", duplicate_application_ids, "\n")

cat("\nCLEAN DATA\n")
cat("Rows:", clean_rows, "\n")
cat("Columns:", clean_cols, "\n")
cat("Output:", clean_path, "\n")

cat("\nMODELING DATA\n")
cat("Rows:", model_rows, "\n")
cat("Defaults:", model_defaults, "\n")
cat("Non-defaults:", model_non_defaults, "\n")
cat("Default rate:", sprintf("%.2f%%", 100 * model_default_rate), "\n")
cat("Output:", model_path, "\n")

cat("\nMISSING-VALUE STRATEGY\n")
cat(
  "Median-imputed helper fields created for: ",
  paste(imputation_source_cols, collapse = ", "),
  "\n",
  sep = ""
)
cat("Original source columns remain unchanged.\n")
cat(
  "Missingness indicator totals: ",
  "number_of_employees=",
  sum(d$number_of_employees_missing),
  ", bureau_score=",
  sum(d$bureau_score_missing),
  ", collateral_value=",
  sum(d$collateral_value_missing),
  ", bank_account_age_years=",
  sum(d$bank_account_age_years_missing),
  "\n",
  sep = ""
)

cat("\nIMPUTATION MEDIANS\n")
cat(
  "number_of_employees:", number_of_employees_median,
  "| bureau_score:", bureau_score_median,
  "| collateral_value:", collateral_value_median,
  "| bank_account_age_years:", bank_account_age_years_median,
  "\n"
)

cat("\nENGINEERED FEATURES\n")
cat(paste(engineered_features, collapse = ", "), "\n")

cat("\nLEAKAGE CHECK\n")
cat(
  "Prohibited performance/workflow predictors present in model set: ",
  length(prohibited_model_predictors),
  "\n",
  sep = ""
)
cat("Model predictor count:", length(predictor_columns), "\n")

cat("\nVALIDATION\n")
cat("No Inf/-Inf engineered ratios: PASS\n")
cat("Risk-band labels: PASS\n")
cat("Modeling population reconciliation: PASS\n")
cat("Leakage exclusion: PASS\n")
cat("\nSTEP 5 R CLEANING & FEATURE ENGINEERING — PASS\n")
