library(tidymodels)

set.seed(20260922)

# STEP 7C: fixed-parameter Random Forest benchmark using the validated Step 7A data.
train_data <- readRDS("models/train_data.rds")
cv_folds <- readRDS("models/cv_folds.rds")

expected_levels <- c("default", "non_default")
if (!identical(levels(train_data$default_flag), expected_levels)) {
  stop("default_flag levels must be: default, non_default")
}
if (nrow(cv_folds) != 5L) {
  stop("Expected exactly five existing customer-grouped CV folds.")
}

leakage_columns <- c(
  "outstanding_balance", "days_past_due", "missed_payments",
  "total_payments", "loan_status", "application_status", "approved_amount",
  "credit_review_date", "approval_date", "disbursement_date"
)
id_columns <- c("application_id", "customer_id")
predictor_columns <- setdiff(names(train_data), c("default_flag", id_columns))
present_leakage <- intersect(predictor_columns, leakage_columns)
if (length(present_leakage) != 0L) {
  stop("LEAKAGE WARNING: ", paste(present_leakage, collapse = ", "))
}
if (!all(id_columns %in% names(train_data))) {
  stop("Both application_id and customer_id must be present for ID roles.")
}

# Confirm the supplied resamples remain customer-grouped and class-valid.
for (i in seq_len(nrow(cv_folds))) {
  analysis_customers <- unique(analysis(cv_folds$splits[[i]])$customer_id)
  assessment_data <- assessment(cv_folds$splits[[i]])
  if (length(intersect(analysis_customers, unique(assessment_data$customer_id))) != 0L) {
    stop("Customer overlap detected in CV fold ", i)
  }
  if (!all(expected_levels %in% unique(assessment_data$default_flag))) {
    stop("CV fold ", i, " does not contain both outcome classes.")
  }
}

rf_recipe <- recipe(default_flag ~ ., data = train_data) %>%
  update_role(application_id, customer_id, new_role = "id") %>%
  step_unknown(all_nominal_predictors()) %>%
  step_novel(all_nominal_predictors()) %>%
  step_dummy(all_nominal_predictors()) %>%
  step_zv(all_predictors())

rf_spec <- rand_forest(
  mtry = 6,
  min_n = 15,
  trees = 500
) %>%
  set_engine("ranger", importance = "impurity") %>%
  set_mode("classification")

rf_workflow <- workflow() %>%
  add_recipe(rf_recipe) %>%
  add_model(rf_spec)

rf_metrics <- metric_set(roc_auc, pr_auc)
rf_cv_results <- fit_resamples(
  rf_workflow,
  resamples = cv_folds,
  metrics = rf_metrics,
  control = control_resamples(save_pred = FALSE, allow_par = FALSE)
)

rf_cv_metrics <- collect_metrics(rf_cv_results) %>%
  select(.metric, mean, n, std_err)
if (!identical(rf_cv_metrics$.metric, c("pr_auc", "roc_auc"))) {
  rf_cv_metrics <- rf_cv_metrics %>% arrange(match(.metric, c("roc_auc", "pr_auc")))
}

dir.create("reports/modeling", recursive = TRUE, showWarnings = FALSE)
write.csv(rf_cv_metrics, "reports/modeling/random_forest_cv_metrics.csv", row.names = FALSE)

roc_result <- filter(rf_cv_metrics, .metric == "roc_auc")
pr_result <- filter(rf_cv_metrics, .metric == "pr_auc")
cat("RF CV ROC-AUC:", roc_result$mean, "\n")
cat("RF CV ROC-AUC standard error:", roc_result$std_err, "\n")
cat("RF CV PR-AUC:", pr_result$mean, "\n")
cat("RF CV PR-AUC standard error:", pr_result$std_err, "\n")

# Train only on the complete validated training partition; Step 8 owns test evaluation.
rf_final_fit <- fit(rf_workflow, data = train_data)
saveRDS(rf_final_fit, "models/random_forest_workflow_fit.rds")

importance_values <- ranger::importance(extract_fit_engine(rf_final_fit))
rf_importance <- data.frame(
  variable = names(importance_values),
  importance = unname(importance_values),
  row.names = NULL
) %>%
  arrange(desc(importance))
write.csv(rf_importance, "reports/modeling/random_forest_importance.csv", row.names = FALSE)

cat("STEP 7C RANDOM FOREST BENCHMARK -- PASS\n")
cat("Grouped folds:", nrow(cv_folds), "\n")
cat("Leakage predictors:", length(present_leakage), "\n")
cat("Final training fit: PASS\n")
cat("Test predictions: NO\n")
cat("Test metrics: NO\n")
