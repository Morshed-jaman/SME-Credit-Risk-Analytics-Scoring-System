library(tidymodels)

# STEP 9: demonstration-only SME credit scoring from the fitted Logistic Regression.
base_score <- 600
base_odds <- 20
pdo <- 50
factor_value <- pdo / log(2)
offset <- base_score - factor_value * log(base_odds)
probability_floor <- 1e-6
risk_levels <- c("Very Low Risk", "Low Risk", "Moderate Risk", "Elevated Risk", "High Risk", "Very High Risk")

score_from_pd <- function(pd, clamp = TRUE, round_score = TRUE) {
  clipped_pd <- pmin(pmax(pd, probability_floor), 1 - probability_floor)
  score <- offset + factor_value * log((1 - clipped_pd) / clipped_pd)
  if (clamp) score <- pmin(pmax(score, 300), 850)
  if (round_score) score <- round(score)
  score
}

assign_risk_band <- function(credit_score) {
  raw_band <- cut(
    credit_score,
    breaks = c(299, 549, 599, 649, 699, 749, 850),
    labels = c("Very High Risk", "High Risk", "Elevated Risk", "Moderate Risk", "Low Risk", "Very Low Risk"),
    include.lowest = TRUE,
    ordered_result = TRUE
  )
  factor(as.character(raw_band), levels = risk_levels, ordered = TRUE)
}

assign_monitoring_flag <- function(risk_band) {
  case_when(
    risk_band %in% c("Very Low Risk", "Low Risk") ~ "Routine monitoring",
    risk_band %in% c("Moderate Risk") ~ "Standard review",
    risk_band %in% c("Elevated Risk", "High Risk", "Very High Risk") ~ "Enhanced review",
    TRUE ~ NA_character_
  )
}

score_applicants <- function(new_data, model_fit) {
  probability_data <- predict(model_fit, new_data = new_data, type = "prob")
  if (!".pred_default" %in% names(probability_data)) {
    stop("The fitted model did not return the default probability column.")
  }
  output_ids <- new_data %>% select(any_of(c("application_id", "customer_id")))
  predicted_pd <- probability_data$.pred_default
  credit_score <- score_from_pd(predicted_pd)
  output_ids %>%
    mutate(
      predicted_pd = predicted_pd,
      credit_score = credit_score,
      risk_band = assign_risk_band(credit_score),
      risk_monitoring_flag = assign_monitoring_flag(risk_band)
    )
}

# Scorecard mathematics: all checks use the unrounded, unclamped conventional transform.
base_point_check <- score_from_pd(1 / 21, clamp = FALSE, round_score = FALSE)
forty_to_one_check <- score_from_pd(1 / 41, clamp = FALSE, round_score = FALSE)
ten_to_one_check <- score_from_pd(1 / 11, clamp = FALSE, round_score = FALSE)
if (abs(base_point_check - 600) > 1e-8 ||
    abs(forty_to_one_check - 650) > 1e-8 ||
    abs(ten_to_one_check - 550) > 1e-8) {
  stop("Scorecard base-point/PDO checks failed.")
}
if (!(score_from_pd(0.01, clamp = FALSE, round_score = FALSE) >
      score_from_pd(0.10, clamp = FALSE, round_score = FALSE) &&
      score_from_pd(0.10, clamp = FALSE, round_score = FALSE) >
      score_from_pd(0.40, clamp = FALSE, round_score = FALSE))) {
  stop("PD-to-score direction check failed.")
}

logistic_fit <- readRDS("models/logistic_workflow_fit.rds")
test_data <- readRDS("models/test_data.rds")
if (nrow(test_data) != 1275L) stop("Expected 1275 test rows.")
if (!identical(levels(test_data$default_flag), c("default", "non_default"))) {
  stop("default_flag levels must be: default, non_default")
}

# This test set was formally evaluated in Step 8 and is used here only to demonstrate scoring.
scored_test <- score_applicants(test_data, logistic_fit) %>%
  mutate(actual_default_flag = test_data$default_flag, .after = customer_id) %>%
  select(application_id, customer_id, actual_default_flag, predicted_pd, credit_score, risk_band, risk_monitoring_flag)

if (nrow(scored_test) != 1275L ||
    any(scored_test$predicted_pd < 0 | scored_test$predicted_pd > 1) ||
    any(scored_test$credit_score < 300 | scored_test$credit_score > 850) ||
    any(!is.finite(scored_test$credit_score)) ||
    any(is.na(scored_test$credit_score)) ||
    !all(scored_test$risk_band %in% risk_levels) ||
    !all(diff(scored_test$credit_score[order(scored_test$predicted_pd)]) <= 0)) {
  stop("Scoring output validation failed.")
}

dir.create("reports/scoring", recursive = TRUE, showWarnings = FALSE)
write.csv(scored_test, "reports/scoring/test_applicant_scores.csv", row.names = FALSE)

score_summary <- tibble(
  metric = c("observations", "mean_score", "median_score", "min_score", "max_score", "score_25th_percentile", "score_75th_percentile"),
  value = c(
    nrow(scored_test),
    mean(scored_test$credit_score),
    median(scored_test$credit_score),
    min(scored_test$credit_score),
    max(scored_test$credit_score),
    quantile(scored_test$credit_score, 0.25),
    quantile(scored_test$credit_score, 0.75)
  )
)
risk_band_summary <- scored_test %>%
  group_by(risk_band, .drop = FALSE) %>%
  summarise(
    applicants = n(),
    mean_predicted_pd = if_else(applicants > 0, mean(predicted_pd), NA_real_),
    actual_defaults = sum(actual_default_flag == "default"),
    actual_default_rate = if_else(applicants > 0, mean(actual_default_flag == "default"), NA_real_),
    mean_credit_score = if_else(applicants > 0, mean(credit_score), NA_real_),
    .groups = "drop"
  )

write.csv(score_summary, "reports/scoring/score_summary.csv", row.names = FALSE)
write.csv(risk_band_summary, "reports/scoring/risk_band_summary.csv", row.names = FALSE)

distribution_plot <- ggplot(scored_test, aes(x = credit_score)) +
  geom_histogram(binwidth = 10, fill = "#2C7FB8", color = "white") +
  labs(title = "Demonstration credit score distribution", x = "Credit score", y = "Applicants") +
  theme_minimal(base_size = 11)
default_rate_plot <- risk_band_summary %>% filter(applicants > 0) %>% ggplot(aes(x = risk_band, y = actual_default_rate)) +
  geom_col(fill = "#D95F0E") +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(title = "Observed default rate by illustrative risk band", x = NULL, y = "Observed default rate") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))
pd_score_plot <- ggplot(scored_test, aes(x = predicted_pd, y = credit_score)) +
  geom_point(alpha = 0.35, color = "#238B45") +
  labs(title = "Predicted default probability and credit score", x = "Predicted PD", y = "Credit score") +
  theme_minimal(base_size = 11)

ggsave("reports/scoring/credit_score_distribution.png", distribution_plot, width = 7, height = 5, dpi = 160)
ggsave("reports/scoring/default_rate_by_risk_band.png", default_rate_plot, width = 8, height = 5, dpi = 160)
ggsave("reports/scoring/pd_vs_credit_score.png", pd_score_plot, width = 7, height = 5, dpi = 160)

monotonic_default_rates <- risk_band_summary$actual_default_rate
direction_message <- if (all(diff(monotonic_default_rates[!is.na(monotonic_default_rates)]) >= 0)) {
  "Observed default rates rise monotonically as illustrative risk worsens."
} else {
  "Observed default rates are not perfectly monotonic across neighboring illustrative bands."
}

cat("SCORING MODEL\nmodel: Logistic Regression\nbase score:", base_score, "\nbase odds:", base_odds, ":1\nPDO:", pdo, "\n")
cat("SCORED TEST POPULATION\nrows:", nrow(scored_test), "\nmean PD:", mean(scored_test$predicted_pd), "\nmean score:", mean(scored_test$credit_score), "\nmedian score:", median(scored_test$credit_score), "\nminimum score:", min(scored_test$credit_score), "\nmaximum score:", max(scored_test$credit_score), "\n")
cat("RISK BANDS\n")
print(risk_band_summary)
cat(direction_message, "\n")
cat("VALIDATION\nPD range valid: YES\nscore range valid: YES\nPD/score direction valid: YES\nscorecard base-point checks: YES\nmissing scores:", sum(is.na(scored_test$credit_score)), "\n")
