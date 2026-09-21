library(shiny)
library(ggplot2)
library(dplyr)
library(scales)
required <- c("data/processed/sme_credit_clean.csv","data/processed/sme_credit_modeling.csv","models/train_data.rds","models/test_data.rds","models/logistic_workflow_fit.rds","models/random_forest_workflow_fit.rds","reports/modeling/final_test_metrics.csv","reports/scoring/risk_band_summary.csv","reports/scoring/score_summary.csv","reports/scoring/test_applicant_scores.csv")
missing <- required[!file.exists(required)]
if (length(missing)) {
 shinyApp(fluidPage(h2("Dashboard prerequisites are missing"),p("Run the earlier data, model, evaluation, and scoring scripts."),tags$ul(lapply(missing,tags$li))),function(input,output,session){})
} else {
 clean <- read.csv("data/processed/sme_credit_clean.csv",stringsAsFactors=FALSE)
 model_data <- read.csv("data/processed/sme_credit_modeling.csv",stringsAsFactors=FALSE)
 fit <- readRDS("models/logistic_workflow_fit.rds")
 metrics <- read.csv("reports/modeling/final_test_metrics.csv",stringsAsFactors=FALSE)
 disbursed <- clean %>% filter(application_status=="Disbursed") %>% mutate(default_n=as.numeric(as.character(default_flag)), bureau_band=cut(bureau_score_imputed,c(-Inf,549,599,649,699,Inf),labels=c("<550","550-599","600-649","650-699","700+")),dti_band=cut(debt_to_income_ratio,c(-Inf,.2,.35,.5,Inf),labels=c("<=20%","20-35%","35-50%",">50%")),age_band=cut(business_age_years,c(-Inf,2,5,10,Inf),labels=c("<=2","3-5","6-10","10+")))
 rate <- function(data,g) data %>% group_by({{g}}) %>% summarise(default_rate=mean(default_n,na.rm=TRUE),.groups="drop")
 factor_score <- 50/log(2); offset <- 600-factor_score*log(20)
 score_pd <- function(pd) {p<-pmin(pmax(pd,1e-6),1-1e-6);round(pmin(pmax(offset+factor_score*log((1-p)/p),300),850))}
 bands <- c("Very Low Risk","Low Risk","Moderate Risk","Elevated Risk","High Risk","Very High Risk")
 band_score <- function(x) factor(as.character(cut(x,c(299,549,599,649,699,749,850),labels=rev(bands),include.lowest=TRUE)),levels=bands,ordered=TRUE)
 flag_band <- function(x) ifelse(x%in%c("Very Low Risk","Low Risk"),"Routine monitoring",ifelse(x=="Moderate Risk","Standard review","Enhanced review"))
 safe <- function(a,b) ifelse(is.na(b)|b==0,0,a/b)
 card <- function(a,b) div(class="kpi-card",div(class="kpi-title",a),div(class="kpi-value",b))
 image_ui <- function(f) if(file.exists(f)) tags$img(src=paste0("../",f),class="metric-image") else p("Image unavailable; run scripts/06_model_evaluation.R.")
 btypes <- sort(unique(model_data$business_type)); purposes <- sort(unique(model_data$loan_purpose)); tenures <- sort(unique(model_data$loan_tenure_months))
 ui <- navbarPage("SME Credit Risk Management Dashboard",inverse=TRUE,header=tags$head(tags$link(rel="stylesheet",href="styles.css")),
 tabPanel("Executive Overview",
  fluidRow(column(3,card("Total Applications",comma(nrow(clean)))),column(3,card("Unique Customers",comma(n_distinct(clean$customer_id)))),column(3,card("Approval Rate",percent(mean(clean$application_status%in%c("Approved","Disbursed"))))),column(3,card("Disbursement Rate",percent(mean(clean$application_status=="Disbursed")))),column(3,card("Disbursed Loans",comma(sum(clean$application_status=="Disbursed")))),column(3,card("Default Rate",percent(mean(disbursed$default_n,na.rm=TRUE)))),column(3,card("Total Approved Amount",dollar(sum(clean$approved_amount,na.rm=TRUE)))),column(3,card("Total Outstanding Balance",dollar(sum(clean$outstanding_balance,na.rm=TRUE))))),
  fluidRow(column(6,plotOutput("status")),column(6,plotOutput("timeline"))),fluidRow(column(6,plotOutput("business")),column(6,plotOutput("purpose")))),
 tabPanel("Credit Risk Analysis",p("Lower bureau scores and prior-default history are associated with higher observed default rates in this synthetic portfolio. These descriptive patterns do not establish causality."),fluidRow(column(6,plotOutput("bureau")),column(6,plotOutput("dti"))),fluidRow(column(6,plotOutput("age")),column(6,plotOutput("history"))),plotOutput("purpose_risk")),
 tabPanel("Model Performance",h3("FINAL HOLDOUT TEST RESULTS"),tableOutput("metric_table"),p("Training grouped-CV results (separate from final test): Logistic ROC-AUC approximately 0.686, PR-AUC approximately 0.387; Random Forest ROC-AUC approximately 0.671, PR-AUC approximately 0.369."),p("Logistic Regression is the demonstration scoring model because it had slightly stronger holdout discrimination/calibration and is easier to interpret."),fluidRow(column(4,uiOutput("roc")),column(4,uiOutput("pr")),column(4,uiOutput("cal")))),
 tabPanel("Applicant Scoring",div(class="disclaimer","Demonstration only. This score is generated from synthetic data and is not a production lending decision, institutional scorecard, or regulatory credit score."),fluidRow(
  column(4,selectInput("bt","Business type",btypes),numericInput("age","Business age (years)",5,0,100),numericInput("emp","Employees",9,0),numericInput("mr","Monthly revenue",100000,1),numericInput("ar","Annual revenue",1200000,1),numericInput("amt","Requested loan amount",300000,1),selectInput("tenure","Loan tenure (months)",tenures),selectInput("purpose_in","Loan purpose",purposes)),
  column(4,numericInput("loans","Existing loans",0,0),numericInput("debt","Existing monthly debt",0,0),numericInput("dti_in","Debt-to-income ratio",.25,0,1,.01),numericInput("bureau_in","Bureau score",645,300,850),numericInput("history_in","Credit history (years)",5,0),numericInput("defaults_in","Previous defaults",0,0),numericInput("collateral","Collateral value",44272.68,0),numericInput("account","Bank account age (years)",4.9,0),actionButton("calculate","Calculate Credit Risk",class="btn-primary")),column(4,uiOutput("result")))),
 footer=div(class="app-footer","Synthetic portfolio only. No real borrower or IDLC Finance data. Not a production credit-decision system; illustrative portfolio project only."))
 server <- function(input,output,session) {
  output$status<-renderPlot(ggplot(clean,aes(application_status))+geom_bar(fill="#163A5F")+labs(title="Application status",x=NULL,y="Applications")+theme_minimal()+theme(axis.text.x=element_text(angle=25,hjust=1)))
  output$timeline<-renderPlot({x<-clean%>%mutate(date=as.Date(application_date))%>%count(date);ggplot(x,aes(date,n))+geom_line(color="#163A5F")+labs(title="Applications over time",x=NULL,y="Applications")+theme_minimal()})
  output$business<-renderPlot(ggplot(clean,aes(reorder(business_type,business_type,length)))+geom_bar(fill="#2C7FB8")+coord_flip()+labs(title="Business type distribution",x=NULL,y="Applications")+theme_minimal())
  output$purpose<-renderPlot(ggplot(clean,aes(reorder(loan_purpose,loan_purpose,length)))+geom_bar(fill="#238B45")+coord_flip()+labs(title="Loan purpose distribution",x=NULL,y="Applications")+theme_minimal())
  bar_rate<-function(x,title) { group_name <- names(x)[1]; ggplot(x,aes(x=.data[[group_name]],y=default_rate))+geom_col(fill="#C85A17")+scale_y_continuous(labels=percent_format())+labs(title=title,x=NULL,y="Observed default rate")+theme_minimal() }
  output$bureau<-renderPlot(bar_rate(rate(disbursed,bureau_band),"Default rate by bureau score band"))
  output$dti<-renderPlot(bar_rate(rate(disbursed,dti_band),"Default rate by DTI band"))
  output$age<-renderPlot(bar_rate(rate(disbursed,age_band),"Default rate by business age"))
  output$history<-renderPlot({x<-disbursed%>%mutate(previous_history=ifelse(previous_defaults>0,"Prior default","No prior default"))%>%group_by(previous_history)%>%summarise(default_rate=mean(default_n),.groups="drop");bar_rate(x,"Default rate by previous-default history")})
  output$purpose_risk<-renderPlot({x<-rate(disbursed,loan_purpose);ggplot(x,aes(reorder(loan_purpose,default_rate),default_rate))+geom_col(fill="#C85A17")+coord_flip()+scale_y_continuous(labels=percent_format())+labs(title="Default rate by loan purpose",x=NULL,y="Observed default rate")+theme_minimal()})
  output$metric_table<-renderTable(metrics%>%transmute(Model=model,ROC_AUC=round(roc_auc,4),PR_AUC=round(pr_auc,4),Gini=round(gini,4),KS=round(ks,4),Brier_Score=round(brier_score,4),Accuracy=round(accuracy,4),Precision=round(precision,4),Recall=round(recall,4),Specificity=round(specificity,4),F1=round(f1,4)),striped=TRUE,bordered=TRUE)
  output$roc<-renderUI(image_ui("reports/modeling/test_roc_curve.png"));output$pr<-renderUI(image_ui("reports/modeling/test_pr_curve.png"));output$cal<-renderUI(image_ui("reports/modeling/calibration_plot.png"))
  scored<-eventReactive(input$calculate,{validate(need(input$ar>0&&input$mr>0&&input$amt>0&&as.numeric(input$tenure)>0,"Revenue, amount, and tenure must be positive."),need(input$dti_in>=0&&input$dti_in<=1,"DTI must be between 0 and 1."),need(input$bureau_in>=300&&input$bureau_in<=850,"Bureau score must be 300-850."))
   d<-data.frame(application_id="DEMO-0001",customer_id="DEMO-CUSTOMER",business_type=input$bt,business_age_years=input$age,number_of_employees_imputed=input$emp,monthly_revenue=input$mr,annual_revenue=input$ar,requested_loan_amount=input$amt,loan_tenure_months=as.numeric(input$tenure),loan_purpose=input$purpose_in,existing_loans=input$loans,existing_monthly_debt=input$debt,debt_to_income_ratio=input$dti_in,bureau_score_imputed=input$bureau_in,credit_history_years=input$history_in,previous_defaults=input$defaults_in,collateral_value_imputed=input$collateral,bank_account_age_years_imputed=input$account,loan_to_annual_revenue_ratio=safe(input$amt,input$ar),collateral_coverage_ratio=safe(input$collateral,input$amt),monthly_debt_to_revenue_ratio=safe(input$debt,input$mr),revenue_per_employee=safe(input$ar,input$emp),requested_amount_per_tenure_month=safe(input$amt,as.numeric(input$tenure)),has_previous_default=as.integer(input$defaults_in>0),has_existing_loan=as.integer(input$loans>0),number_of_employees_missing=0,bureau_score_missing=0,collateral_value_missing=0,bank_account_age_years_missing=0,stringsAsFactors=FALSE)
   pd<-predict(fit,new_data=d,type="prob")$.pred_default;s<-score_pd(pd);b<-as.character(band_score(s));list(pd=pd,score=s,band=b,flag=flag_band(b))})
  output$result<-renderUI({x<-scored();req(x);div(class="score-card",h3("Demonstration score"),h2(percent(x$pd,accuracy=.01)),p("Predicted Probability of Default"),h2(paste0(x$score," / 850")),h3(x$band),p(paste("Monitoring:",x$flag)),div(class="risk-bar",div(class="risk-fill",style=paste0("width:",100*(850-x$score)/550,"%"))))})
 }
 shinyApp(ui,server)
}