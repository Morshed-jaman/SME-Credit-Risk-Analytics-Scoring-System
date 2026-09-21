# Synthetic SME lending portfolio generator. All observations are fictional.
set.seed(20260921)
n <- 10000L
out <- file.path("data", "raw", "sme_loan_applications.csv")
clip <- function(x, lo, hi) pmin(pmax(x, lo), hi)
inv_logit <- function(x) 1 / (1 + exp(-x))

# Business and application characteristics
application_id <- sprintf("APP%06d", seq_len(n))
customer_id <- sprintf("CUST%05d", sample(1:8500, n, TRUE))
application_date <- as.Date("2023-01-01") + sample(0:1338, n, TRUE)
business_type <- sample(c("Retail","Wholesale","Manufacturing","Services","Agriculture","Transport","Hospitality","Technology"), n, TRUE, c(.22,.13,.14,.20,.10,.08,.07,.06))
business_age_years <- round(clip(rgamma(n, 2.6, .32), .5, 30), 1)
number_of_employees <- pmax(1L, pmin(250L, round(rlnorm(n, log(9), .75))))
annual_revenue <- round(clip(rlnorm(n, log(150000), .9), 18000, 5000000), 2)
monthly_revenue <- round(annual_revenue / 12 * runif(n, .90, 1.10), 2)
requested_loan_amount <- round(clip(annual_revenue * rlnorm(n, log(.22), .55), 3000, 800000), 2)
loan_tenure_months <- sample(c(6L,12L,18L,24L,36L,48L,60L), n, TRUE, c(.08,.25,.10,.28,.18,.07,.04))
loan_purpose <- sample(c("Working Capital","Inventory Purchase","Equipment","Business Expansion","Vehicle","Renovation","Seasonal Financing"), n, TRUE, c(.31,.20,.16,.15,.07,.05,.06))

# Financial profile. Monetary amounts are fictional local-currency values.
existing_loans <- pmin(rpois(n, 1.15), 7L)
debt_to_income_ratio <- round(clip(rbeta(n, 2.2, 4.7) * .95 + existing_loans * .025, .03, .92), 3)
existing_monthly_debt <- round(monthly_revenue * debt_to_income_ratio, 2)
bureau_score <- round(clip(rnorm(n, 665 - existing_loans * 7 - debt_to_income_ratio * 35, 70), 300, 850))
credit_history_years <- round(clip(business_age_years * runif(n, .35, 1.15) + rnorm(n, 2, 2), 0, 30), 1)
previous_defaults <- pmin(rbinom(n, 3, inv_logit(-3 + (620 - bureau_score) / 90)), 3L)
collateral_value <- round(clip(requested_loan_amount * rlnorm(n, log(1.35), .60), 0, 2500000), 2)
bank_account_age_years <- round(clip(business_age_years * runif(n, .25, 1.05) + rnorm(n, .5, 1), .1, 25), 1)

# Risk-aware probabilities: higher DTI/leverage, lower scores, prior defaults,
# younger firms, lower revenue capacity, and more loans increase default risk.
loan_to_revenue <- requested_loan_amount / annual_revenue
risk <- -1.80 + 2.20 * (debt_to_income_ratio - .35) + .65 * ((680 - bureau_score) / 100) + .85 * previous_defaults + .55 * pmax((5 - business_age_years) / 5, 0) + .75 * pmax(loan_to_revenue - .25, 0) + .18 * pmax(existing_loans - 1, 0) + .55 * pmax(loan_to_revenue - .40, 0)
default_probability <- inv_logit(risk)
# Approval decisions use related risk drivers but retain underwriting variation.
approval_probability <- inv_logit(2.05 - 2.10 * debt_to_income_ratio + .85 * ((bureau_score - 650) / 100) - .90 * previous_defaults + .18 * pmin(business_age_years, 10) / 10 - .90 * pmax(loan_to_revenue - .30, 0) - .16 * existing_loans)
is_approved <- rbinom(n, 1, approval_probability) == 1
is_disbursed <- is_approved & rbinom(n, 1, .88) == 1

# Workflow dates are generated in chronological order.
application_status <- rep("Rejected", n)
pending <- which(!is_approved); p <- runif(length(pending))
application_status[pending[p < .08]] <- "Submitted"
application_status[pending[p >= .08 & p < .17]] <- "Under Review"
application_status[is_approved & !is_disbursed] <- "Approved"
application_status[is_disbursed] <- "Disbursed"
credit_review_date <- as.Date(rep(NA, n), origin = "1970-01-01")
reviewed <- application_status %in% c("Under Review","Approved","Rejected","Disbursed")
credit_review_date[reviewed] <- application_date[reviewed] + sample(1:14, sum(reviewed), TRUE)
approval_date <- as.Date(rep(NA, n), origin = "1970-01-01")
approval_date[is_approved] <- credit_review_date[is_approved] + sample(1:10, sum(is_approved), TRUE)
disbursement_date <- as.Date(rep(NA, n), origin = "1970-01-01")
disbursement_date[is_disbursed] <- approval_date[is_disbursed] + sample(1:7, sum(is_disbursed), TRUE)
approved_amount <- ifelse(is_approved, round(requested_loan_amount * runif(n, .65, 1), 2), 0)

# Defaults can occur only after disbursement.
default_flag <- integer(n); default_flag[is_disbursed] <- rbinom(sum(is_disbursed), 1, default_probability[is_disbursed])
outstanding_balance <- numeric(n); days_past_due <- integer(n); missed_payments <- integer(n); total_payments <- integer(n); loan_status <- rep("Not Disbursed", n)
for (i in which(is_disbursed)) {
  mob <- max(1L, floor(as.numeric(as.Date("2026-09-21") - disbursement_date[i]) / 30.4)); total_payments[i] <- min(loan_tenure_months[i], mob)
  if (default_flag[i] == 1L) {
    days_past_due[i] <- sample(90:180, 1); missed_payments[i] <- sample(3:8, 1); outstanding_balance[i] <- round(approved_amount[i] * runif(1,.35,.90),2); loan_status[i] <- "Default"
  } else {
    d <- runif(1)
    if (d < .68) { days_past_due[i] <- 0L; missed_payments[i] <- 0L; loan_status[i] <- "Current" }
    else if (d < .82) { days_past_due[i] <- sample(1:29,1); missed_payments[i] <- sample(1:2,1); loan_status[i] <- "DPD 1-29" }
    else if (d < .91) { days_past_due[i] <- sample(30:59,1); missed_payments[i] <- sample(1:3,1); loan_status[i] <- "DPD 30-59" }
    else if (d < .96) { days_past_due[i] <- sample(60:89,1); missed_payments[i] <- sample(2:4,1); loan_status[i] <- "DPD 60-89" }
    else { days_past_due[i] <- sample(90:120,1); missed_payments[i] <- sample(3:5,1); loan_status[i] <- "DPD 90+" }
    if (total_payments[i] >= loan_tenure_months[i] && loan_status[i] == "Current" && runif(1) < .75) { loan_status[i] <- "Closed"; outstanding_balance[i] <- 0 } else { outstanding_balance[i] <- round(approved_amount[i] * (1 - clip(total_payments[i] / loan_tenure_months[i] + rnorm(1,0,.08), .05, .98)), 2) }
  }
}

# Add 1.5% missingness to selected non-critical profile fields for cleaning demos.
make_missing <- function(x) { x[sample.int(length(x), round(length(x) * .015))] <- NA; x }
number_of_employees <- make_missing(number_of_employees); bureau_score <- make_missing(bureau_score); collateral_value <- make_missing(collateral_value); bank_account_age_years <- make_missing(bank_account_age_years)

d <- data.frame(application_id, customer_id, application_date, business_type, business_age_years, number_of_employees, monthly_revenue, annual_revenue, requested_loan_amount, loan_tenure_months, loan_purpose, existing_loans, existing_monthly_debt, debt_to_income_ratio, bureau_score, credit_history_years, previous_defaults, collateral_value, bank_account_age_years, application_status, credit_review_date, approval_date, disbursement_date, approved_amount, outstanding_balance, days_past_due, missed_payments, total_payments, loan_status, default_flag)

# Validation before export.
money <- c("monthly_revenue","annual_revenue","requested_loan_amount","existing_monthly_debt","collateral_value","approved_amount","outstanding_balance")
stopifnot(nrow(d) == 10000L, !anyDuplicated(d$application_id), all(d$default_flag %in% c(0L,1L)), all(vapply(d[money], function(x) all(is.na(x) | x >= 0), logical(1))), all(is.na(d$credit_review_date) | d$credit_review_date >= d$application_date), all(is.na(d$approval_date) | d$approval_date >= d$credit_review_date), all(is.na(d$disbursement_date) | d$disbursement_date >= d$approval_date))
default_rate <- mean(d$default_flag); approval_rate <- mean(d$application_status %in% c("Approved","Disbursed"))
stopifnot(default_rate >= .08, default_rate <= .15)
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE); write.csv(d, out, row.names = FALSE, na = "")
cat("Dataset dimensions:\n"); print(dim(d)); cat("\nColumn names:\n"); print(names(d)); cat("\nDefault rate:", round(default_rate,4), "\nApproval rate:", round(approval_rate,4), "\n\nMissing value counts:\n"); print(colSums(is.na(d))); cat("\nSummary statistics:\n"); print(summary(d))
