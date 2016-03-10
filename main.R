
# fix logloss for validation and test set
# code to switch which models to ensemble
# optimisation on ensemble validation set
# compare cross validation results to test set

# Bagging glm models
# take pcas or each block of 3 that is correlated.
# fit models on pca 1 and separate on pca 2 and 3.
# fit glmnet models with regularisation

#setwd(paste0(getwd(),"/4-MachineLearning/numerai/logloss/"))

# Data Manipulation
require(readr)
require(dplyr)
require(tidyr)
require(Matrix)
require(reshape2)

# Data Visualisation 
require(ggplot2)
require(psych)
require(corrplot)

# Machine Learning
require(caret)
require(doParallel)
require(xgboost)

require(Metrics)
#require(caTools)
#require(pROC)

### Data Load and Manipulation ###

train <- read_csv("./data/numerai_training_data.csv")
test <- read_csv("./data/numerai_tournament_data.csv")
train$traintest <- "train"
test$traintest <- "test"

all <- bind_rows(train,test)
outcome_name <- "target"
feature_names <- names(all)[1:21]
trainindex <- which(all$traintest=="train")
testindex <- which(all$traintest=="test")
data <- data.frame(all)[,1:22]
ytrain <- data[trainindex,outcome_name]
ytrain_n <- length(ytrain)

testid <- all[testindex,"t_id"]
rm(list=c("train","test")) # drop train and test

### Data Visualisation ###

# Correlations
corrplot(cor(data[trainindex,feature_names]),"circle",tl.cex=0.6)
corrplot(cor(data[trainindex,feature_names]),"circle",order="hclust",tl.cex=0.6)
corrplot(cor(data[trainindex,c(outcome_name,feature_names)]),"circle",tl.cex=0.6)


clust <- paste("feature",c(19,1,8,5,17,20,13,
                           15,16,10,11,21,6,4,
                           14,2,3,18,12,7,9),sep="")
clust1 <- clust[seq(1,21,3)]
clust2 <- clust[seq(2,21,3)]
clust3 <- clust[seq(3,21,3)]

clust4 <- paste("feature",c(1,17,15,10,14,2,12),sep="")

# What is the distribution of the factors?
all %>%
  select(-t_id) %>%
  melt(id.vars=c("target","traintest")) %>% 
  ggplot(aes(variable,value)) + 
  geom_boxplot(aes(fill=as.factor(target))) + 
  coord_flip() 

all %>%
  select(-t_id) %>%
  melt(id.vars=c("target","traintest")) %>% 
  ggplot(aes(x=value,fill=variable)) + 
  geom_density(alpha=0.2)

all %>%
  ggplot(aes(x=feature1,y=feature2)) + 
  geom_point()
# Structure in the data not being able to take certain values!?
# This will impact tree methods?

# Call sampling routine
source("sampling.R")
samples <- samplingcv("option3",trainindex,testindex,ytrain)
# Check how to feed these into caret

# Extract sampling info:
sample_info = data.frame(t(sapply(samples, function(x) unlist(x[-length(x)]))))
str(lapply(samples,function(x) x$index$train))
str(lapply(samples,function(x) x$index$test))


# Save results for different models

source("models.R")

#models <- list()
ptm <- proc.time()
models <- fitallmodels(data,samples,TRUE)
proc.time() - ptm

# Create ensemble models here?



# Summarise results of models
samples_n <- nrow(sample_info)
models_n <- length(models)
models_names <- sapply(models,function(x) x[[1]]$name)

# How best to extract info? rows: samples, cols: models
logloss_train <- data.frame(sapply(models,function(x) sapply(x,function(x) x$logloss$train)))
logloss_test <- data.frame(sapply(models,function(x) sapply(x,function(x) x$logloss$test)))
logloss_valid <- data.frame(sapply(models,function(x) sapply(x,function(x) x$logloss$valid)))

names(logloss_train) <- models_names
names(logloss_test) <- models_names
names(logloss_valid) <- models_names

logloss_test

# Tidy output
logloss.train <- data.frame(logloss_train,id = sample_info$id) %>% 
                    gather(model,logloss.train,-id) 
logloss.test <- data.frame(logloss_test,id = sample_info$id) %>% 
                    gather(model,logloss.test,-id)
logloss.valid <- data.frame(logloss_valid,id = sample_info$id) %>% 
                    gather(model,logloss.valid,-id)

metrics <- full_join(logloss.train,logloss.test,by=c("id","model"))
metrics <- full_join(metrics,logloss.valid,by=c("id","model"))

# Gather all data
fit <- sample_info
fit <- full_join(fit,metrics,by="id")

## Charts for showing fit relative to sample size:

# Test
fit %>% 
  group_by(model,interval) %>%
  summarise(ll.test = mean(logloss.test)) %>%
  ggplot(aes(x=interval,y=ll.test,colour=model)) +
  geom_line(size=2)

# Train
fit %>% 
  group_by(model,interval) %>%
  summarise(ll.train = mean(logloss.train)) %>%
  ggplot(aes(x=interval,y=ll.train,colour=model)) +
  geom_line(size=2)

# Plot together as facet
fit %>% 
  gather(metric,value,-(type:model))  %>% 
  group_by(model,interval,metric) %>%
  summarise(ll = mean(value)) %>%
  ggplot(aes(x=interval,y=ll,colour=model)) +
  geom_line(size=2) + 
  facet_wrap(~metric)

# Or show the distribution of the test set 
fit %>% 
  ggplot(aes(x=as.factor(interval),y=logloss.test)) +
  geom_boxplot(aes(fill=as.factor(model)))


## Correlations among models ##
# Extract predictions to use for correlation analysis

# Change ordering of nesting of list:
# Validation probs. List of sample ids, 10 elements, of dataframes with 
# columns as each of the models.
prob_valid <- list()
for (s in 1:samples_n) {
  for (m in 1:models_n) {
    col <- models[[m]][[s]]$prob$valid
    # make dataframe
    if (m==1) {
      df <- data.frame(col)
    } else {
      df <- data.frame(df,col)
    }
  }
  # save dataframe
  names(df) <- models_names
  prob_valid[[s]] <- df
}

# Combine this into a function. Or change the fit approach?
prob_test <- list()
for (s in 1:samples_n) {
  for (m in 1:models_n) {
    col <- models[[m]][[s]]$prob$test
    # make dataframe
    if (m==1) {
      df <- data.frame(col)
    } else {
      df <- data.frame(df,col)
    }
  }
  # save dataframe
  names(df) <- models_names
  prob_test[[s]] <- df
}

# When do we want the data as model_sample or sample_model?!

# Average correlation with other models, in test set say,
test_cor <- sapply(prob_test,function(x) cor(x))
test_cor_avg <- matrix(rowMeans(test_cor),models_n)
test_cor_avg

# Create ensemble models at this step? Separate module of functions?
# Feed in list of samples_models

ensemble_prob_valid <- lapply(prob_valid,function(x) rowMeans(x))
#ensemble_prob_valid <- lapply(prob_valid,function(x) apply(x,1,function(z) mean(z[2:4])))
# Code to create ensembles of equal weights across all models. 
# 
prob_valid[[1]]

ensemble_prob_test <- lapply(prob_test,function(x) rowMeans(x))

# Extract the actual y's using indices
samples_validindex_y <- lapply(lapply(samples, function(x) x$index$valid), 
                               function(y) data[y,outcome_name])
samples_testindex_y <- lapply(lapply(samples, function(x) x$index$test), 
                               function(y) data[y,outcome_name])

# Fit logLoss, by sample
ensemble_logloss_valid <- mapply(function(x,y) logLoss(x,y), samples_validindex_y,ensemble_prob_valid)
ensemble_logloss_test <- mapply(function(x,y) logLoss(x,y), samples_testindex_y,ensemble_prob_test)
# Averaged across all samples
mean(ensemble_logloss_valid)
mean(ensemble_logloss_test)

df_models <- fit[,c("rep","model","logloss.valid")]
df_ens <- data.frame(rep = 1:10,model="ensemble",logloss.valid = ensemble_logloss_valid)
df_all <- rbind(df_models,df_ens)
df_all %>% ggplot(aes(x=rep,y=logloss.valid,colour=model)) + geom_point(size=3)

df_all %>% ggplot(aes(x=model,y=logloss.valid)) + geom_boxplot()

# Code to optimise weights on validation set. 


# Then cross validate on test set.



# Validation logloss calculated from probability output. 
# same as logloss_valid and similar to data in fit
# rows: models, cols: iterations
logloss_valid_2 <- mapply(function(x,y) 
          sapply(1:models_n,function(z) logLoss(y,x[,z])), 
          prob_valid, samples_validindex_y)




###### Using caret to train ######

# training control parameters
set.seed(1)
trcontrol_1 = trainControl(
  method = "repeatedcv",
  number = 5,
  repeats = 3,
  returnResamp= "none",
  verboseIter = TRUE,
  returnData = FALSE,
  classProbs = TRUE, 
  summaryFunction = multiClassSummary,
  allowParallel = TRUE
)

xTrain = data.frame(all)[trainindex,feature_names]
yTrain <- factor(data.frame(all)[trainindex,outcome_name],,c("x0","x1"))
xTest = data.frame(all)[testindex,feature_names]

m1 = train(
  x = xTrain,
  y = yTrain,
  trControl = trcontrol_1,
  method = "glm",
  metric="logLoss"
)

m1$results$logLoss
m1$results$logLossSD

m1c1 = train(
  x = xTrain[,clust1],
  y = yTrain,
  trControl = trcontrol_1,
  method = "glm",
  metric="logLoss"
)


m1c2 = train(
  x = xTrain[,clust2],
  y = yTrain,
  trControl = trcontrol_1,
  method = "glm",
  metric="logLoss"
)

m1c3 = train(
  x = xTrain[,clust3],
  y = yTrain,
  trControl = trcontrol_1,
  method = "glm",
  metric="logLoss"
)


m1c4 = train(
  x = xTrain[,clust4],
  y = yTrain,
  trControl = trcontrol_1,
  method = "glm",
  metric="logLoss"
)

m1$results$logLoss
m1c1$results$logLoss
m1c2$results$logLoss
m1c3$results$logLoss
m1c4$results$logLoss

# Correlations among models
#models <- list(m1c1,m1c2,m1c3)
models <- list(m1,m1c1,m1c2,m1c3,m1c4)
#models <- list(m1c1,m1c2,m1c3)

models_prob <- function(models,xData) {
  p <- sapply(models,
              function(x) predict(x,xData,type="prob")[,2])
}

cor(models_prob(models,xTrain))
cor(models_prob(models,xTest))

ensemble_prob_train <- apply(models_prob(models,xTrain),1,mean)
ensemble_prob_test <- apply(models_prob(models,xTest),1,mean)

actual_train <- data.frame(all)[trainindex,outcome_name]
logLoss(actual_train, ensemble_prob_train)

submission <- data.frame(t_id = all[testindex,"t_id"],
                         probability = ensemble_prob_test)

write_csv(submission,"./predictions/predictions_7.csv")

# Now lets try bagging glm
# bagging logistic regression
# http://stackoverflow.com/questions/21785699/bagging-logistic-regression-in-r

library(foreach)
set.seed(1)
training2      <- data.frame(all)[trainindex,1:22]
length_divisor <- 2
iterations     <- 50
features <- 10
predictions <- foreach(m=1:iterations,.combine=rbind) %do% {
  training_positions <- sample(nrow(training2), 
                               size=floor((nrow(training2)/length_divisor)))
  #  train_pos<-1:nrow(training2) %in% training_positions
  glm_fit <- glm(target~ . ,
                 data=training2[training_positions,
                                c(sample(1:21,features),22)],
                 family=binomial(logit))
  predict(glm_fit,
                newdata=xTest, #xTest
                type="response")
}
#predictions
bag_prob <- apply(t(predictions),1,mean)
logLoss(actual_train, bag_prob)

cor(data.frame(bag_prob,models_prob(models,xTrain)))
cor(data.frame(bag_prob,models_prob(models,xTest)))

ensemble_prob_test <- apply(data.frame(bag_prob,
                                       models_prob(models,xTest)),
                                       1,mean)

submission <- data.frame(t_id = all[testindex,"t_id"],
                         probability = ensemble_prob_test)

write_csv(submission,"./predictions/predictions_8.csv")

# add in proper cross validation on above.

# Check individual factor signs
coeff <- NA
for (i in 1:21) {
  fit <- glm(target~.,binomial,
             all[trainindex,c(i,22)])
  summary(fit)
  coeff[i] <- fit$coefficients[2]
}
signs <- sign(coeff)

# Set up validation set
set.seed(1)
trainindex1 <- sample(trainindex,floor(0.7*length(trainindex)))
trainindex2 <- setdiff(trainindex,trainindex1)
require(gbm)
set.seed(5)
mgbm1 <- gbm(target~.,
             "bernoulli",
             data=all[trainindex1,c(outcome_name,feature_names)],
             var.monotone=signs,
             n.trees=50,
             interaction.depth=1,
             n.minobsinnode = 1,
             shrinkage = 0.05,
             bag.fraction = 0.5,
             train.fraction = 0.5,
             n.cores = 7)

probgbm = predict(mgbm1,all[trainindex2,],type="response") 
actualv <- data.frame(all)[trainindex2,outcome_name]
logLoss(actualv, probgbm)

probgbm <- predict(mgbm1,xTrain,type="response") 

cor(data.frame(probgbm,models_prob(models,xTrain)))

probgbm <- predict(mgbm1,xTest,type="response") 

ensemble_prob_test <- apply(data.frame(probgbm,bag_prob,
                                       models_prob(models,xTest)),
                            1,mean)

submission <- data.frame(t_id = all[testindex,"t_id"],
                         probability = ensemble_prob_test)

write_csv(submission,"./predictions/predictions_9.csv")

# Maybe look to remove the gbm. Or learn to fit better?

# Fit a basic neural network?
require(nnet)
yTrain1 <- data.frame(all)[trainindex1,outcome_name]

yNet1 <- class.ind(yTrain)
nnet1 <- nnet(xTrain[trainindex1,clust1],yNet1[trainindex1,],
              size=9,maxit = 500,softmax=TRUE)
# Change the decay?
nnet1_prob <- predict(nnet1,xTrain[trainindex2,clust1])[,2]
summary(nnet1_prob)
logLoss(data.frame(all)[trainindex2,outcome_name], 
        as.numeric(nnet1_prob))

# Try knn
require(class)
xTrainExValid <- data.frame(all)[trainindex1,feature_names]
yTrainExValid <- factor(data.frame(all)[trainindex1,outcome_name],,c("x0","x1"))
xValid <- data.frame(all)[trainindex2,feature_names]
yValid <- factor(data.frame(all)[trainindex2,outcome_name],,c("x0","x1"))

knn1 <- knn(xTrainExValid[,clust4], xValid[,clust4], yTrainExValid, 
            k = 50, l = 0, prob = TRUE, use.all = TRUE)
# Bit tricky to extract probabilities
knn_pred <- as.numeric(knn1)-1

knn_prob1 <- attr(knn1, "prob")
knn_prob <- ifelse(knn_pred==1,knn_prob1,1-knn_prob1)
summary(knn_prob)
logLoss(actualv,knn_prob)
# hmm.. not working
# how does it work with many factors..

# No information
logLoss(actual,rep(0.5,length(actual)))
# Random noise?


# Next try SVMs. Although may need to train on smaller sample size?
# takes foreever to train!
require(kernlab)
datat <- data.frame(target=yTrainExValid,xTrainExValid)

# ok with 5000, slows down with >10K
svm1 <- ksvm(target~.,data=datat[1:10000,c("target",clust4)],
             kernel="rbfdot",
             kpar=list(sigma=0.1),C=1,
             prob.model=TRUE)
svm_prob <- predict(svm1,xValid[,clust4], type="probabilities")
logLoss(actualv,svm_prob)
# Still pretty rubbish fit
# Tube with other costs and sigma?
svm2 <- ksvm(target~.,data=datat[30001:40000,c("target",clust4)],
             kernel="rbfdot",C=0.5,
             prob.model=TRUE)
svm_prob <- predict(svm2,xValid, type="probabilities")[,2]
logLoss(actualv,svm_prob)

#svm_prob1 <- svm_prob
#svm_prob2 <- svm_prob
svm_prob3 <- svm_prob
cor(data.frame(svm_prob1,svm_prob2,svm_prob3))

cor(data.frame(svm_prob,models_prob(models,xValid)))

library(doParallel)
cl <- makeCluster(detectCores()-1) 
registerDoParallel(cl)
Train <- data.frame(target=yTrain,xTrain)
trcontrol_2 = trainControl(
  method = "repeatedcv",
  number = 3,
  repeats = 3,
  returnResamp= "none",
  verboseIter = TRUE,
  returnData = FALSE,
  classProbs = TRUE, 
  summaryFunction = multiClassSummary,
  allowParallel = TRUE
)
set.seed(1)
svm_grid <- expand.grid(sigma = c(.015),C = c(0.25))
svm_sample_size = 3000
svm_sample_index <- sample(1:length(yTrain),svm_sample_size)
svm3 <- train(target ~ ., data=Train[svm_sample_index,
                                     c("target",clust1)], 
                      method="svmRadial",
                      trControl = trcontrol_2,
                      tuneGrid = svm_grid,
                      metric = "logLoss")
svm_prob <- predict(svm3,xValid[,clust1], type="prob")[,2]
logLoss(actualv,svm_prob)

svm_prob <- predict(svm3,xTest, type="prob")[,2]




#######
# svm bagging
set.seed(1)
training2 <- data.frame(target=yTrain,xTrain)

bags <- createFolds(yTrain,5)
yTrain1 <- data.frame(all)[trainindex,outcome_name]

probs4 <- NA
fitsvmpredict <- function(index) {
  #index = bags[[4]]
  svm_fit <- ksvm(target~.,
                  data=training2[index,
                                 c("target",clust4)],
                  kernel="rbfdot",C=0.5,
                  prob.model=TRUE)
  #predict(svm_fit, xTest, type="probabilities")[,2]  
  probs <- predict(svm_fit, xTrain[-index,], type="probabilities")[,2] 
  print(logLoss(yTrain1[-index],probs))
  probsTest <- predict(svm_fit, xTest, type="probabilities")[,2]
  probs4 <- cbind(probs4,probsTest)
}

for (k in 1:5) {
  fitsvmpredict(bags[[k]])
}


# sapply(bags,fitsvmpredict)

#predictions
bag_prob4 <- apply(t(predictions),1,mean)


cor(data.frame(bag_prob4,models_prob(models,xTest)))
ensemble_prob_test <- apply(data.frame(bag_prob4,
                                       models_prob(models,xTest)),
                            1,mean)
submission <- data.frame(t_id = all[testindex,"t_id"],
                         probability = ensemble_prob_test)
submission <- data.frame(t_id = all[testindex,"t_id"],
                         probability = bag_prob4)
write_csv(submission,"./predictions/predictions_10.csv")







### use caret to tune the xgb parameters by grid search ###
xgb_grid_1 = expand.grid(
  nrounds = c(50),
  eta = c(0.1),
  max_depth = c(1,2,3,4,5),
  gamma = c(0,1),
  colsample_bytree = c(0.2,0.5,0.8),
  min_child_weight = c(1,5,8,10,20)
)

# Train model
xgb = train(
  x = xTrain,
  y = yTrain,
  trControl = trcontrol_1,
  tuneGrid = xgb_grid_1,
  subsample = 1,
  method = "xgbTree",
  metric = "logLoss",
  nthread = detectCores()-1
)

xgb$results$logLoss
xTest = all[testindex,feature_names] 

#pred = predict(xgb_2,xValids) # prob = TRUE not working?
probability = predict(xgb$finalModel$handle,data.matrix(xTest)) 

# Make submission file
submission <- data.frame(t_id = all[testindex,"t_id"],probability)

write_csv(submission,"./predictions/predictions_6.csv")





