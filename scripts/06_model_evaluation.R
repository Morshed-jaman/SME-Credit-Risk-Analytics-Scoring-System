library(tidymodels)

# STEP 8: final holdout evaluation. Models and data partitions are loaded, never refit.
threshold <- 0.50
test_data <- readRDS("models/test_data.rds")
logistic_fit <- readRDS("models/logistic_workflow_fit.rds")
rf_fit <- readRDS("models/random_forest_workflow_fit.rds")

expected_levels <- c("default", "non_default")
if (nrow(test_data) != 1275L) stop("Expected 1275 holdout rows.")
if (!identical(levels(test_data$default_flag), expected_levels)) stop("default_flag levels must be: default, non_default")
dir.create("reports/modeling", recursive = TRUE, showWarnings = FALSE)

make_predictions <- function(fit, model_name) {
  probabilities <- predict(fit, new_data = test_data, type = "prob") %>% transmute(.pred_default = .pred_default)
  test_data %>% select(default_flag) %>% bind_cols(probabilities) %>%
    mutate(.pred_class = factor(if_else(.pred_default >= threshold, "default", "non_default"), levels = expected_levels), model = model_name)
}
ks_statistic <- function(truth, probability) {
  defaults <- probability[truth == "default"]
  non_defaults <- probability[truth == "non_default"]
  cutoffs <- sort(unique(c(defaults, non_defaults)))
  max(abs(vapply(cutoffs, function(x) mean(defaults <= x), numeric(1)) - vapply(cutoffs, function(x) mean(non_defaults <= x), numeric(1))))
}
safe_ratio <- function(numerator, denominator) if (denominator == 0) NA_real_ else numerator / denominator
evaluate_model <- function(predictions, model_name) {
  truth <- predictions$default_flag
  estimate <- predictions$.pred_class
  tp <- sum(truth == "default" & estimate == "default")
  fp <- sum(truth == "non_default" & estimate == "default")
  tn <- sum(truth == "non_default" & estimate == "non_default")
  fn <- sum(truth == "default" & estimate == "non_default")
  precision_value <- safe_ratio(tp, tp + fp)
  recall_value <- safe_ratio(tp, tp + fn)
  metrics <- tibble(
    model = model_name,
    roc_auc = roc_auc(predictions, default_flag, .pred_default, event_level = "first")$.estimate,
    pr_auc = pr_auc(predictions, default_flag, .pred_default, event_level = "first")$.estimate,
    gini = 0,
    ks = ks_statistic(truth, predictions$.pred_default),
    brier_score = mean((as.numeric(truth == "default") - predictions$.pred_default)^2),
    accuracy = safe_ratio(tp + tn, tp + fp + tn + fn),
    precision = precision_value,
    recall = recall_value,
    specificity = safe_ratio(tn, tn + fp),
    f1 = safe_ratio(2 * precision_value * recall_value, precision_value + recall_value),
    threshold = threshold
  ) %>% mutate(gini = 2 * roc_auc - 1)
  confusion <- tibble(statistic = c("TP", "FP", "TN", "FN"), value = c(tp, fp, tn, fn))
  list(metrics = metrics, confusion = confusion)
}
calibration_data <- function(predictions, model_name) {
  predictions %>% mutate(bin = ntile(.pred_default, 10L)) %>% group_by(bin) %>%
    summarise(mean_predicted_probability = mean(.pred_default), actual_default_rate = mean(default_flag == "default"), observations = n(), .groups = "drop") %>%
    mutate(model = model_name, .before = 1)
}

# Each fitted workflow is scored once against the untouched final test set.
logistic_predictions <- make_predictions(logistic_fit, "Logistic Regression")
rf_predictions <- make_predictions(rf_fit, "Random Forest")
logistic_evaluation <- evaluate_model(logistic_predictions, "Logistic Regression")
rf_evaluation <- evaluate_model(rf_predictions, "Random Forest")
final_metrics <- bind_rows(logistic_evaluation$metrics, rf_evaluation$metrics)
logistic_calibration <- calibration_data(logistic_predictions, "Logistic Regression")
rf_calibration <- calibration_data(rf_predictions, "Random Forest")

write.csv(final_metrics, "reports/modeling/final_test_metrics.csv", row.names = FALSE)
write.csv(logistic_evaluation$confusion, "reports/modeling/logistic_confusion_matrix.csv", row.names = FALSE)
write.csv(rf_evaluation$confusion, "reports/modeling/random_forest_confusion_matrix.csv", row.names = FALSE)
write.csv(logistic_calibration, "reports/modeling/logistic_calibration.csv", row.names = FALSE)
write.csv(rf_calibration, "reports/modeling/random_forest_calibration.csv", row.names = FALSE)

all_predictions <- bind_rows(logistic_predictions, rf_predictions)
roc_data <- all_predictions %>% group_by(model) %>% group_modify(~ roc_curve(.x, default_flag, .pred_default, event_level = "first")) %>% ungroup()
pr_data <- all_predictions %>% group_by(model) %>% group_modify(~ pr_curve(.x, default_flag, .pred_default, event_level = "first")) %>% ungroup()
roc_plot <- ggplot(roc_data, aes(x = 1 - specificity, y = sensitivity, color = model)) + geom_line(linewidth = 0.9) + geom_abline(linetype = "dashed", color = "grey50") + coord_equal() + labs(title = "Final test ROC curves", x = "False positive rate", y = "True positive rate", color = NULL) + theme_minimal(base_size = 11)
pr_plot <- ggplot(pr_data, aes(x = recall, y = precision, color = model)) + geom_line(linewidth = 0.9) + labs(title = "Final test precision-recall curves", x = "Recall", y = "Precision", color = NULL) + theme_minimal(base_size = 11)
calibration_plot <- bind_rows(logistic_calibration, rf_calibration) %>% ggplot(aes(x = mean_predicted_probability, y = actual_default_rate, color = model)) + geom_point(size = 2) + geom_line(linewidth = 0.8) + geom_abline(linetype = "dashed", color = "grey50") + coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) + labs(title = "Final test calibration", x = "Mean predicted default probability", y = "Observed default rate", color = NULL) + theme_minimal(base_size = 11)
ggsave("reports/modeling/test_roc_curve.png", roc_plot, width = 7, height = 5, dpi = 160)
ggsave("reports/modeling/test_pr_curve.png", pr_plot, width = 7, height = 5, dpi = 160)
ggsave("reports/modeling/calibration_plot.png", calibration_plot, width = 7, height = 5, dpi = 160)

cat("STEP 8 FINAL MODEL EVALUATION -- PASS\n")
cat("Test rows:", nrow(test_data), "\n")
cat("Defaults:", sum(test_data$default_flag == "default"), "\n")
cat("Non-defaults:", sum(test_data$default_flag == "non_default"), "\n")
print(final_metrics)
