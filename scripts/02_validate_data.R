csv <- file.path("data", "raw", "sme_loan_applications.csv")
stopifnot(file.exists(csv))
d <- read.csv(csv, na.strings = "", stringsAsFactors = FALSE, check.names = FALSE)
date_cols <- c("application_date", "credit_review_date", "approval_date", "disbursement_date")
for (x in date_cols) d[[x]] <- as.Date(d[[x]])

money <- c("monthly_revenue", "annual_revenue", "requested_loan_amount", "approved_amount", "existing_monthly_debt", "collateral_value", "outstanding_balance")
critical <- c("application_id", "customer_id", "application_date", "application_status", "default_flag")
intended_missing <- c("number_of_employees", "bureau_score", "collateral_value", "bank_account_age_years", "credit_review_date", "approval_date", "disbursement_date")
app_levels <- c("Rejected", "Submitted", "Under Review", "Approved", "Disbursed")
loan_levels <- c("Not Disbursed", "Current", "DPD 1-29", "DPD 30-59", "DPD 60-89", "DPD 90+", "Default", "Closed")
checks <- c(
  rows_10000 = nrow(d) == 10000L,
  application_id_unique = !anyDuplicated(d$application_id),
  customer_id_present = !anyNA(d$customer_id),
  valid_default_flag = all(d$default_flag %in% c(0L, 1L)),
  valid_application_status = all(d$application_status %in% app_levels),
  valid_loan_status = all(d$loan_status %in% loan_levels),
  missingness_limited = all(names(d)[colSums(is.na(d)) > 0] %in% intended_missing),
  critical_present = !anyNA(d[critical]),
  nonnegative_money = all(vapply(d[money], function(x) all(is.na(x) | x >= 0), logical(1))),
  bureau_range = all(is.na(d$bureau_score) | d$bureau_score >= 300 & d$bureau_score <= 850),
  dti_range = all(d$debt_to_income_ratio >= .03 & d$debt_to_income_ratio <= .92),
  nonnegative_business_age = all(d$business_age_years >= 0),
  valid_tenure = all(d$loan_tenure_months %in% c(6L, 12L, 18L, 24L, 36L, 48L, 60L)),
  approval_cap = all(d$approved_amount <= d$requested_loan_amount),
  application_before_review = all(is.na(d$credit_review_date) | d$application_date <= d$credit_review_date),
  review_before_approval = all(is.na(d$approval_date) | d$credit_review_date <= d$approval_date),
  approval_before_disbursement = all(is.na(d$disbursement_date) | d$approval_date <= d$disbursement_date),
  rejected_not_disbursed = all(is.na(d$disbursement_date[d$application_status == "Rejected"])),
  pending_no_future_data = all(is.na(d$approval_date[d$application_status %in% c("Submitted", "Under Review")])) && all(is.na(d$disbursement_date[d$application_status %in% c("Submitted", "Under Review")])),
  rejected_no_default = all(d$default_flag[d$application_status == "Rejected"] == 0),
  nondisbursed_no_performance = all(d$default_flag[d$application_status != "Disbursed"] == 0 & d$loan_status[d$application_status != "Disbursed"] == "Not Disbursed" & d$days_past_due[d$application_status != "Disbursed"] == 0 & d$missed_payments[d$application_status != "Disbursed"] == 0 & d$outstanding_balance[d$application_status != "Disbursed"] == 0),
  default_status_consistent = all(d$loan_status[d$default_flag == 1] == "Default") && all(d$default_flag[d$loan_status == "Default"] == 1),
  dpd_status_consistent = all(d$days_past_due[d$loan_status == "Current"] == 0) && all(d$days_past_due[d$loan_status == "DPD 1-29"] >= 1 & d$days_past_due[d$loan_status == "DPD 1-29"] <= 29) && all(d$days_past_due[d$loan_status == "DPD 30-59"] >= 30 & d$days_past_due[d$loan_status == "DPD 30-59"] <= 59) && all(d$days_past_due[d$loan_status == "DPD 60-89"] >= 60 & d$days_past_due[d$loan_status == "DPD 60-89"] <= 89) && all(d$days_past_due[d$loan_status == "DPD 90+"] >= 90) && all(d$days_past_due[d$loan_status == "Default"] >= 90),
  balance_consistent = all(d$outstanding_balance[d$loan_status == "Not Disbursed"] == 0) && all(d$outstanding_balance[d$loan_status == "Closed"] == 0) && all(d$outstanding_balance[d$loan_status %in% c("Current", "DPD 1-29", "DPD 30-59", "DPD 60-89", "DPD 90+", "Default")] >= 0),
  closed_consistent = all(d$days_past_due[d$loan_status == "Closed"] == 0 & d$default_flag[d$loan_status == "Closed"] == 0)
)

tab <- function(x) { z <- as.data.frame(table(x, useNA = "ifany"), stringsAsFactors = FALSE); names(z) <- c("category", "count"); z$percent <- round(100 * z$count / nrow(d), 3); z }
rate_tab <- function(group, breaks = NULL, labels = NULL) { g <- if (is.null(breaks)) group else cut(group, breaks, labels = labels, right = FALSE); z <- data.frame(group = g[d$application_status == "Disbursed"], default_flag = d$default_flag[d$application_status == "Disbursed"]); z <- z[!is.na(z$group), ]; z$eligible <- 1L; z$defaults <- z$default_flag; out <- aggregate(cbind(eligible, defaults) ~ group, z, sum); out$default_rate <- out$defaults / out$eligible; out }
disbursed <- d$application_status == "Disbursed"
ratio <- d$requested_loan_amount / d$annual_revenue

cat("CHECKS\n"); print(data.frame(check = names(checks), pass = unname(checks), row.names = NULL))
cat("\nMISSINGNESS\n"); print(data.frame(column = names(d), missing = colSums(is.na(d)), percent = round(100 * colSums(is.na(d)) / nrow(d), 3), row.names = NULL))
cat("\nMETRICS\n"); print(data.frame(metric = c("approval_rate", "rejection_rate", "disbursement_rate", "default_rate_disbursed", "average_requested", "average_approved", "total_approved", "total_outstanding"), value = c(mean(d$application_status %in% c("Approved", "Disbursed")), mean(d$application_status == "Rejected"), mean(disbursed), mean(d$default_flag[disbursed]), mean(d$requested_loan_amount), mean(d$approved_amount[d$application_status %in% c("Approved", "Disbursed")]), sum(d$approved_amount), sum(d$outstanding_balance))))
cat("\nAPPLICATION_STATUS\n"); print(tab(d$application_status)); cat("\nLOAN_STATUS\n"); print(tab(d$loan_status)); cat("\nBUSINESS_TYPE\n"); print(tab(d$business_type)); cat("\nLOAN_PURPOSE\n"); print(tab(d$loan_purpose))
cat("\nRISK_BUREAU\n"); print(rate_tab(d$bureau_score, c(-Inf, 550, 650, 700, 750, Inf), c("<550", "550-649", "650-699", "700-749", "750+"))); cat("\nRISK_DTI\n"); print(rate_tab(d$debt_to_income_ratio, c(-Inf, .20, .35, .50, Inf), c("<20%", "20%-34.99%", "35%-49.99%", "50%+"))); cat("\nRISK_PREVIOUS_DEFAULTS\n"); print(rate_tab(ifelse(d$previous_defaults == 0, "0", "1+"))); cat("\nRISK_BUSINESS_AGE\n"); print(rate_tab(d$business_age_years, c(-Inf, 3, 5, 10, Inf), c("<3 years", "3-4.99 years", "5-9.99 years", "10+ years"))); cat("\nRISK_LOAN_TO_REVENUE\n"); print(rate_tab(ratio, c(-Inf, .15, .25, .40, Inf), c("<15%", "15%-24.99%", "25%-39.99%", "40%+")))
if (!all(checks)) stop("Validation checks failed.")
