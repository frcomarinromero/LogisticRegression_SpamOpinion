# 1. Cargar librerías =========================================================

library(tidyverse) #collección de las principales bibliotecas 
library(here)      #Para optimizar el manejo de rutas a archivos

library(NLP)       #Requerido por libreria tm
library(tm)   #text mining (más información en: 
              #https://miamioh.instructure.com/courses/38953/pages/text-mining)

library (RColorBrewer)  #Requerido por wordcloud
library(wordcloud)      #Para visualizar nubes de palabras

library(lattice)  #requerido por caret
library(caret)    #Para dividir los datos en conjunto de prueba y entrenamiento

library(Matrix)     #Requerido por Glmnet
library(glmnet)     # Para entrenear modelos lineales generalizados (GLM) 
                    #con penalizacion 



# 2. Lectura de los datos  =====================================================

df <- read.csv(here("Datos","deceptive-opinion.csv"))

# 3. Exploración de datos  =====================================================

str(df)

# 3.1 Conversión de tipo de columnas----------------------------------------

df$deceptive <- as.factor(df$deceptive)
df$hotel <- as.factor(df$hotel)
df$polarity <- as.factor(df$polarity)
df$source <- as.factor (df$source)

summary(df)

table(df$deceptive,df$polarity)

# 4. Vectorización mediante Bolsa de Palabras ==================================

# 4.1 Crear Corpus -------------------------------------------------------

corpus <- VCorpus (VectorSource(df$text)) #crear el corpus de opiniones

inspect(corpus[100])  #ver características un elemento del corpus
                      
inspect(corpus[[100]]) #leer el documento del elemento 100 del corpus

corpus[[100]]$content

# 4.2 Preprocesamiento de texto -------------------------------------------

#Transformar todas las letras a minúsculas
corpus <- tm_map(corpus, content_transformer(tolower))

#Remover "stopwords" (Palabras muy comunes sin significado importante)
corpus <- tm_map (corpus, removeWords, stopwords("english"))

corpus <- tm_map (corpus, removeWords, c("hotel", "hotels", 'room', 
                                         "chicago", "stay"))
#Remover signos de puntuación
corpus <- tm_map (corpus, removePunctuation)

#Obtener la raiz de las palabras (stemming)
corpus <- tm_map (corpus, stemDocument)

#Remover números
corpus <- tm_map (corpus, removeNumbers)

#Remover espacios en blanco de más
corpus <- tm_map (corpus, stripWhitespace) 


# 4.3 Tokenización  -------------------------------------------------------

#(crear matriz Termino-Documento donde los textos o documentos son columnas
# y cada palabra un renglón. las palabras (Terminos) y los renglones 
# cada texto (documentos))

tdm <- TermDocumentMatrix(corpus, control = list(weighting = weightTfIdf))

dim(tdm)

tdm$dimnames$Terms

#4.4 Reducir la dimensionalidad --------------------------------------------

#La siguiente línea elimina términos que en el 90% de los docs no aparecen:
#tdm_90 <- removeSparseTerms(tdm, 0.90) #113 términos restantes

#La siguiente línea elimina términos que en el 99% de los docs no aparecen
#tdm_99 <- removeSparseTerms(tdm, 0.99) #957 términos restantes

#elimina términos que en el 99.9% de los docs no aparecen
tdm_999 <- removeSparseTerms(tdm, 0.999) #3528 términos restantes

# 4.5 Visualizar nube de palabras -------------------------------------------


plot_wordclouds <- function(tdm){
  m <- as.matrix(tdm)
  v <- sort(rowSums(m), decreasing=TRUE)
  d <- data.frame(word = names(v), frec=v)  
  
  set.seed(1234)
  print(dim(tdm))
  return (wordcloud(words = d$word, freq = d$frec, min.freq = 1,
                    max.words = 50, random.order = FALSE, rot.per = 0.35, 
                    colors = brewer.pal(8, "Dark2")))
}

plot_wordclouds(tdm = tdm_999)  


# 4.6 Separar etiquetas(Z) de caracteristicas (X) -----------------------------

dtm <- as.DocumentTermMatrix(tdm_999)

X <- as.matrix(dtm)

Z <- df$deceptive

# 5. Dividir datos en conjunto de entrenamiento y prueba ======================

set.seed(28)

test_index <- createDataPartition(df$deceptive, p=0.2, list=FALSE)

X_test <- X[test_index,]
Z_test <- Z[test_index]
X_train <- X[-test_index,]
Z_train <- Z[-test_index]

#Ver tamaño de conjunto de entrenamiento

dim(X_train)
length(Z_train)

#Ver tamaño de conjunto de prueba  

dim(X_test)
length(Z_test)

#6 Realizar una regresión logistica sin penalización ===========================

or <- glmnet(X_train, Z_train, family = "binomial", alpha = 0, 
             standarize = TRUE,lambda=0)  #alpha=0: Ridge; alpha=1: Lasso

#6.1  Predicción conjunto de entrenamiento -------------------------------------
x = X_train
z = Z_train
conjunto ='Entrenamiento'

Z_predicted <- predict(or, newx= x, type="class")

# Evaluación
accuracy <- mean(z == Z_predicted)

confusion <- caret::confusionMatrix(data = as.factor(Z_predicted), 
                                    reference = z)

fourfoldplot(confusion$table, main=paste("SET: ",conjunto, " Lambda = 0", 
                                         "   Accuracy =", accuracy*100, "%"))  

# 6.2 Predicción conjunto de prueba --------------------------------------------
x = X_test
z = Z_test
conjunto ='Prueba'

Z_predicted <- predict(or, newx= x, type="class")

# Evaluación
accuracy <- mean(z == Z_predicted)

confusion <- caret::confusionMatrix(data = as.factor(Z_predicted), 
                                    reference = z)

fourfoldplot(confusion$table, main=paste("SET: ",conjunto, " Lambda = 0", 
                                         "   Accuracy =", accuracy*100, "%"))  


#Coeficientes
temp_coeff_or <- coef(or)
coeff_or <- data.frame(name = temp_coeff_or@Dimnames[[1]][temp_coeff_or@i + 1], 
                       coefficient = temp_coeff_or@x)
coeff_or <- coeff_or[order(coeff_or$coefficient),]  #ordenar coeficientes

print("Primeros 20 coeficientes")
print(head(coeff_or, 20))


#7. Regresión Logística - Ridge ------------------------------------------------

# encontrar el valor óptimo de lambda

cv_ridge <- cv.glmnet(X_train, Z_train, family="binomial", 
                      alpha=0, standarize=TRUE)
plot(cv_ridge) #El punto más bajo en la curva indica el valor óptimo para lambda

lambda_min_ridge <- cv_ridge$lambda.min
lambda_1se_ridge <- cv_ridge$lambda.1se

#guardamos todos los modelos de la validación cruzada
modelos_ridge <- cv_ridge$glmnet.fit
plot(cv_ridge, xvar=lambda)

#8. Regresión Logística - Lasso ------------------------------------------------

# encontrar el valor óptimo de lambda

cv_lasso <- cv.glmnet(X_train, Z_train, family="binomial", 
                      alpha=1, standarize=TRUE)

plot(cv_lasso)  #El punto más bajo en la curva indica el valor óptimo para lambda

lambda_min_lasso <- cv_lasso$lambda.min
lambda_1se_lasso <- cv_lasso$lambda.1se

#guardamos todos los modelos de la validación cruzada
modelos_lasso <- cv_lasso$glmnet.fit

# 8. Evaluación de los modelos =================================================

clasifica_con_penalizacion <- function(penalizacion, lambda, datos){

  # penalizacion: "Lasso" o "Ridge"
  # lambda: valor de lambda a usar
  # datos: "entrenamiento" o "prueba"
  
  ifelse(penalizacion == 'Ridge',
         modelos <- modelos_ridge,
         ifelse(penalizacion=='Lasso',
                modelos <- modelos_lasso,
                warning('penalizacion solo puede ser Ridge o Lasso')))
  if(datos=='entrenamiento'){
    xs <- X_train
    zs <- Z_train
  }
  if(datos=='prueba'){
    xs <- X_test
    zs <- Z_test
  }
  
  # Predicción 
  Z_pred_class <- predict(modelos, s=lambda, newx= xs, type="class")
  Z_pred_prob <-  predict(modelos, s = lambda, newx = xs, type ="response")
  
  #Creación de dataframe con la clase verdadera, la predicción de clase y  
  # probabilidad
  
  Z_evaluacion <- data.frame(zs, Z_pred_class, Z_pred_prob)
  names(Z_evaluacion)[2] <- "clase"
  names(Z_evaluacion)[3] <- "probabilidad"
  
  # Evaluación
  
  accuracy <- mean(zs == Z_pred_class)
  
  confusion <- caret::confusionMatrix(data = as.factor(Z_pred_class), 
                                      reference = zs)

  fourfoldplot(confusion$table, main = paste(penalizacion, datos, "Lambda =",
                                             format(round((lambda), 2), 
                                                    nsmall=2),
                                             "Exactitud =",
                                             format(round((accuracy*100), 2),
                                                    nsmall=2), "%"))  
  # Coeficientes 
  
  tmp_coeffs <- coef(modelos, s = lambda)
  coeficientes <- data.frame(name = tmp_coeffs@Dimnames[[1]][tmp_coeffs@i + 1], 
                             coefficient = tmp_coeffs@x)
  coeficientes <- coeficientes[order(coeficientes$coefficient),]
  print("Primeros 20 coeficientes")
  print(head(coeficientes, 20))
  
  resultados <- list(accuracy, coeficientes, Z_evaluacion, confusion)  
  return(resultados)
}


# Obtener resultados para ambos regularizadores y distintas lambdas
#(lambda_min_ridge, lambda_1se_ridge, cv_ridge$lambda[1], cv_ridge$lambda[10]...)
#(lambda_min_ridge, lambda_1se_ridge, cv_ridge$lambda[1], cv_ridge$lambda[10]...)

lambda = lambda_1se_ridge
modelo = "Ridge"

res_train <- clasifica_con_penalizacion(modelo,
                                        lambda,
                                        "entrenamiento") 

res_test <- clasifica_con_penalizacion(modelo, 
                                       lambda,
                                       "prueba")



lambda = lambda_1se_lasso
modelo = "Lasso"

res_train <- clasifica_con_penalizacion(modelo,
                                        lambda,
                                        "entrenamiento") 

res_test <- clasifica_con_penalizacion(modelo, 
                                       lambda,
                                       "prueba")


                              
##Para ver los coeficientes
coeficientes <- res_train[[2]]

view(coeficientes)


## Para guardar la predicción en términos de clase y probabilidad:


Z_evaluacion <- res_test[[3]]


head(Z_evaluacion, 20)













                        