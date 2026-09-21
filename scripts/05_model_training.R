library(tidymodels)
set.seed(20260922)
input_file <- file.path("data","processed","sme_credit_modeling.csv")
d <- read.csv(input_file, stringsAsFactors=FALSE, check.names=FALSE)
stopifnot(nrow(d)==6373L, sum(d$default_flag)==1350L)
d$default_flag <- factor(ifelse(d$default_flag==1,"default","non_default"),levels=c("default","non_default"))
prohibited <- c("outstanding_balance","days_past_due","missed_payments","total_payments","loan_status","application_status","approved_amount","credit_review_date","approval_date","disbursement_date","application_to_review_days","review_to_approval_days","approval_to_disbursement_days","application_to_approval_days","application_to_disbursement_days","application_id","customer_id")
predictors <- setdiff(names(d),c("default_flag","application_id","customer_id"))
if(length(intersect(predictors,prohibited)))stop("LEAKAGE WARNING: prohibited predictor present.")
# Deterministic complete-customer split; customer IDs are shuffled once, then allocated near 80% of rows.
customer_sizes <- dplyr::count(d, customer_id, name="rows")
customer_sizes <- customer_sizes[sample(nrow(customer_sizes)),]
customer_sizes$cumulative_rows <- cumsum(customer_sizes$rows)
train_customers <- customer_sizes$customer_id[customer_sizes$cumulative_rows <= .80*nrow(d)]
train <- d[d$customer_id %in% train_customers,]
test <- d[!d$customer_id %in% train_customers,]
overlap <- length(intersect(unique(train$customer_id),unique(test$customer_id)))
if(overlap != 0L || !all(levels(d$default_flag)%in% unique(train$default_flag)) || !all(levels(d$default_flag)%in% unique(test$default_flag))) stop("Grouped split validation failed.")
folds <- group_vfold_cv(train, group=customer_id, v=5)
fold_report <- dplyr::bind_rows(lapply(seq_len(nrow(folds)),function(i){a<-assessment(folds$splits[[i]]);if(length(unique(a$default_flag))<2)stop("CV fold lacks a class.");data.frame(fold=i,rows=nrow(a),customers=dplyr::n_distinct(a$customer_id),defaults=sum(a$default_flag=="default"),non_defaults=sum(a$default_flag=="non_default"),default_rate=mean(a$default_flag=="default"))}))
for(i in seq_len(nrow(folds))) if(length(intersect(unique(analysis(folds$splits[[i]])$customer_id),unique(assessment(folds$splits[[i]])$customer_id))))stop("Customer overlap within CV fold.")
dir.create("models",showWarnings=FALSE)
saveRDS(train,"models/train_data.rds");saveRDS(test,"models/test_data.rds");saveRDS(folds,"models/cv_folds.rds")
cat("STEP 7A REPORT\ntraining rows:",nrow(train),"\ntesting rows:",nrow(test),"\ntraining customers:",dplyr::n_distinct(train$customer_id),"\ntesting customers:",dplyr::n_distinct(test$customer_id),"\ntraining defaults:",sum(train$default_flag=="default"),"\ntesting defaults:",sum(test$default_flag=="default"),"\ntraining default rate:",sprintf("%.4f",mean(train$default_flag=="default")),"\ntesting default rate:",sprintf("%.4f",mean(test$default_flag=="default")),"\ncustomer overlap:",overlap,"\nCV folds:",nrow(folds),"\nall CV folds contain both classes: YES\nleakage predictors present: 0\ntest metrics calculated: NO\n");print(fold_report);train<-readRDS('models/train_data.rds');folds<-readRDS('models/cv_folds.rds');rec<-recipe(default_flag~.,data=train)%>%update_role(application_id,customer_id,new_role='id')%>%step_unknown(all_nominal_predictors())%>%step_novel(all_nominal_predictors())%>%step_dummy(all_nominal_predictors())%>%step_zv(all_predictors())%>%step_normalize(all_numeric_predictors());wf<-workflow()%>%add_recipe(rec)%>%add_model(logistic_reg()%>%set_engine('glm')%>%set_mode('classification'));met<-metric_set(roc_auc,pr_auc,accuracy,precision,recall,specificity,f_meas);cv<-fit_resamples(wf,folds,metrics=met);z<-collect_metrics(cv)%>%select(.metric,mean,std_err,n);dir.create('reports/modeling',recursive=TRUE,showWarnings=FALSE);write.csv(z,'reports/modeling/logistic_cv_metrics.csv',row.names=FALSE);fit<-fit(wf,train);saveRDS(fit,'models/logistic_workflow_fit.rds');write.csv(tidy(extract_fit_parsnip(fit))%>%transmute(term,coefficient=estimate,odds_ratio=exp(estimate)),'reports/modeling/logistic_coefficients.csv',row.names=FALSE);print(z)
# STEP 7C-1 RF tuning: grouped training CV only; test is never used.
train<-readRDS("models/train_data.rds");folds<-readRDS("models/cv_folds.rds");stopifnot(length(intersect(unique(train$customer_id),unique(readRDS("models/test_data.rds")$customer_id)))==0L);bad<-intersect(setdiff(names(train),c("default_flag","application_id","customer_id")),prohibited);if(length(bad))stop("LEAKAGE WARNING")
for(i in seq_len(nrow(folds)))if(length(unique(assessment(folds$splits[[i]])$default_flag))<2)stop("Fold missing class")
rfrec<-recipe(default_flag~.,data=train)%>%update_role(application_id,customer_id,new_role="id")%>%step_unknown(all_nominal_predictors())%>%step_novel(all_nominal_predictors())%>%step_dummy(all_nominal_predictors())%>%step_zv(all_predictors())
rfs<-rand_forest(mtry=tune(),min_n=tune(),trees=500)%>%set_engine("ranger",importance="impurity",probability=TRUE)%>%set_mode("classification");rfwf<-workflow()%>%add_recipe(rfrec)%>%add_model(rfs);grid<-expand_grid(mtry=c(3,6,9,12),min_n=c(5,15,25))
set.seed(20260922);tm<-metric_set(roc_auc,pr_auc,accuracy,precision,recall,specificity,f_meas);rfres<-tune_grid(rfwf,resamples=folds,grid=grid,metrics=tm);rr<-collect_metrics(rfres);write.csv(rr,"reports/modeling/random_forest_tuning_results.csv",row.names=FALSE);best<-select_best(rfres,"roc_auc");bm<-rr%>%filter(.metric=="roc_auc",mtry==best$mtry,min_n==best$min_n);bp<-data.frame(mtry=best$mtry,min_n=best$min_n,trees=500,cv_roc_auc=bm$mean,cv_roc_auc_std_err=bm$std_err);write.csv(bp,"reports/modeling/random_forest_best_parameters.csv",row.names=FALSE);saveRDS(bp,"models/random_forest_best_parameters.rds");print(bp);print(rr%>%filter(mtry==best$mtry,min_n==best$min_n))