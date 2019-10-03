library(dplyr)

#' getValidationData Gets the base types xsd so we know what data type each field should be and what the code list is
#'
#' @param fileLocation Location of the base types xsd file
#'
#' @return
#' @export
#'
#' @examples validationData <- getValidationData(fileLocation = './tableDefs/BaseTypes.xsd')
getValidationData <- function(fileLocation){
  
  # For testing
  #fileLocation <- './tableDefs/BaseTypes.xsd'
  
  # Parse the XML
  doc <- xmlTreeParse(fileLocation,useInternal= TRUE)
  myXML <- xmlToList(doc)

  # Data frame to hold out validation info
  myValidationDF <- NULL
  
  # Get the infromation we want from the xsd file - hard-code to the current structure...
  for (myElement in myXML){
      if(names(myElement)[[1]]=="sequence"){
        for (mySubElement in myElement[[1]]){
          myMin <- mySubElement[[1]]
          myMax <- mySubElement[[2]]
          myName <- mySubElement[[3]]
          myType <- mySubElement[[4]]
          myDF <- data.frame(min=myMin, max=myMax, name=myName, type=myType, stringsAsFactors = FALSE)
          if (is.null(myValidationDF)){
            myValidationDF <- myDF
          } else {
            myValidationDF <- rbind(myValidationDF,myDF)
          }
        }
    }
  }
  
  myValidationDF

  
}


logValidationError<- function(errorList,tableName, rowID, fieldName, problemType, problemDescription){
  
  
  myErrors <- data.frame(tableName = tableName
                         ,rowID = rowID
                         ,fieldName = fieldName
                         ,problemType = problemType
                         ,problemDescription = problemDescription
                         ,stringsAsFactors = FALSE)
  errorList <- rbind(errorList, myErrors)
  
}

validateTables <- function(RDBESdata, RDBESvalidationdata, RDBEScodeLists, shortOutput = FALSE){
  
  # For testing
  RDBESdata <- myRDBESData
  RDBESvalidationdata <- validationData
  RDBEScodeLists <- allowedValues
  shortOutput <- TRUE
  
  # To hold the output
  #errorList <- list()
  errorList <- data.frame(tableName=character(0)
                          ,rowID = integer(0)
                          ,fieldName=character(0)
                          ,problemType=character(0)
                          ,problemDescription=character(0), stringsAsFactors = FALSE)
  
  DE <- RDBESdata[['DE']]
  SD <- RDBESdata[['SD']]
  OS <- RDBESdata[['OS']]
  BV <- RDBESdata[['BV']]

  # We'll only validate these table types at the moment
  RDBESdata <- RDBESdata[c("BV","DE","FM","FO","FT","LE","LO","OS","SA","SD","SL","SS","TE","VD","VS" )]
  
  # for each data frame in our list
  for (dfToCheck in RDBESdata){
    
    #dfToCheck <- head(BV,10)
    #dfToCheck <- BV
    
    # Get the field names as a data frame
    myDF <- data.frame(fieldName = names(dfToCheck), stringsAsFactors = FALSE)
    # Join the field names to the field type data frame
    fieldsAndTypes <- left_join(myDF,RDBESvalidationdata,by=c("fieldName" = "name"))
    ## Assume the id is always the first field - might be better to check the field names instead
    myIDField <- names(dfToCheck)[[1]]
    myTableName <- substr(myIDField,1,2)
    print(myTableName)

    # For each field in the frame
    for (i in 1:length(names(dfToCheck))) {
    
      #i <- 6
      #print(i)
      #print(nrow(errorList))
        
      myFieldName <- names(dfToCheck)[[i]]
      myFT <- fieldsAndTypes[fieldsAndTypes$fieldName == names(dfToCheck)[[i]],]
      
      ## Check 1) NA values
      myValuesNA <- dfToCheck[is.na(dfToCheck[,myFieldName]),]
      # If we have NA values check if thats ok
      if (nrow(myValuesNA)>0){
        # if we are not allowed to have empty values here then log an error
        if (ifelse(is.na(myFT$min),0,myFT$min) >0){
          #Log the error
          errorList <- logValidationError(errorList = errorList
                                 ,tableName = myTableName
                                 ,rowID = myValuesNA[,1]
                                 ,fieldName = myFieldName
                                 ,problemType = "Null value check"
                                 ,problemDescription = paste("Null value problem;",myIDField,":", myValuesNA[,1], " ;Column:",myFieldName, ";Unallowed value:",myValuesNA[,myFieldName], sep = " "))
        }
      } # Endif NA check
      
      # Now that we have passed the NA check point lets get rid of any NA values so 
      # we don't need to worry about them again
      #dfToCheck <- dfToCheck[!is.na(dfToCheck[,myFieldName]),]
      dfToCheckNotNA <- dfToCheck[!is.na(dfToCheck[,myFieldName]),]
      
      # Check 2 Do we kniw what type this field shoudl be?
      # If not, there's nothing much else we can do so skip to the end and log the error
      
      #Check if we know what types this field should have
      if (!is.na(myFT$type)){
        myType <- myFT$type
        
        # CHeck 3 For simple data types we'll see if we have the right format data
        
        # IF simple type
        if (length(grep("xs:",myType)) > 0) {
          ## simple type, so check data type 
          # Ints
          if (myType == "xs:int"){
            # Check for any non integer values
            myNonIntValues <- dfToCheckNotNA[!is.integer(dfToCheckNotNA[,myFieldName]),]
            if (nrow(myNonIntValues)>0){
              #Log the error
              #print(myNonIntValues)
              errorList <- logValidationError(errorList = errorList
                                              ,tableName = myTableName
                                              ,rowID = myNonIntValues[,1]
                                              ,fieldName = myFieldName
                                              ,problemType = "Data type check"
                                              ,problemDescription = paste("Data type problem (int);",myIDField,":", myNonIntValues[,1], " ;Column:",myFieldName, ";Unallowed value:",myNonIntValues[,myFieldName], sep = " "))
            }
          # Decimal
          } else if (myType == "xs:decimal"){
            # Check for any non numeric values
            myNonDecValues <- dfToCheckNotNA[!is.numeric(dfToCheckNotNA[,myFieldName]),]
            if (nrow(myNonDecValues)>0){
              #Log the error
              errorList <- logValidationError(errorList = errorList
                                              ,tableName = myTableName
                                              ,rowID = myNonDecValues[,1]
                                              ,fieldName = myFieldName
                                              ,problemType = "Data type check"
                                              ,problemDescription = paste("Data type problem (decimal);",myIDField,":", myNonDecValues[,1], " ;Column:",myFieldName, ";Unallowed value:",myNonDecValues[,myFieldName], sep = " "))
            }
          # String
          } else if (myType == "xs:string"){
            # Everythign can be converted to a string so no problem here
          }
        
        # Check 4 If we're dealing with code lists we need to see if we have allowed values  
        
        # ELSE code list
        } else {

          #myValuesNotNA <- dfToCheck[!is.na(dfToCheck[,myFieldName]),]
          #myValuesNotNA <- dfToCheck
          # if we have some non-NA values lets check them
          if (nrow(dfToCheckNotNA)){
            # see if we can find the correct code list
            myAllowedValues <- RDBEScodeLists[RDBEScodeLists$listName == myType,"allowedValues"]
            # If we found which values are allowed then we can check our data against them
            if (length(myAllowedValues)>0){
              # Check if our values are in the allowed list of values
              myResults <- dfToCheckNotNA[!dfToCheckNotNA[,myFieldName] %in% myAllowedValues,]
              # If we have soem values that aren't in the allowed list flag them as errors
              if (nrow(myResults)>0){
                #Log the error
                errorList <- logValidationError(errorList = errorList
                                                ,tableName = myTableName
                                                ,rowID = myResults[,1]
                                                ,fieldName = myFieldName
                                                ,problemType = "Code list problem"
                                                ,problemDescription = paste("Code list problem;",myIDField,":", myResults[,1], " ;Column:",myFieldName, ";Unallowed value:",myResults[,myFieldName], ";Code list name:",myType, sep = " "))
              }
            # ELSE if we didn't find a list of allowed values then log that as an error
            } else {
              #Log the error
              errorList <- logValidationError(errorList = errorList
                                              ,tableName = myTableName
                                              ,rowID = NA
                                              ,fieldName = myFieldName
                                              ,problemType = "Missing code list"
                                              ,problemDescription = paste("Could not find code list", myType, " for ", myFieldName, sep = " "))
            } # ENDIF find allowed values
          } # Endif NA/non na values
        } # ENDIF simple type 
      # Could not find validation inforation on this field
      } else {
          # id and recordType fields don't have validation information so don't bother recording an error for those types of fields
          if (length(grep("^..id$",myFieldName)) == 0 & length(grep("^..recordType$",myFieldName)) == 0){
            errorList <- logValidationError(errorList = errorList
                                            ,tableName = myTableName
                                            ,rowID = NA
                                            ,fieldName = myFieldName
                                            ,problemType = "Code list missing"
                                            ,problemDescription = paste("Could not find validation information for ", myFieldName, sep = " "))
          }
      }
    } # Endfor each field in frame
  
  } # Endfor each frame in RDBES data list
  
  #errorList[[1]][[1]]
  
  # If we want shorter output we won't show every error  - just the first of each type
  if (shortOutput){
    
    fieldsToKeep <- names(errorList)
    # Sort the errors
    errorList <- errorList[order(errorList$tableName, errorList$fieldName, errorList$problemType, errorList$rowID),]
    # Get the row number within a group
    numberedErrorList <- errorList %>% group_by(errorList$tableName, errorList$fieldName, errorList$problemType) %>% mutate(rowNum = row_number())

    # Generate our extra rows that will show there were more errors present
    myExtraRows <- numberedErrorList[numberedErrorList$rowNum == 2,fieldsToKeep]
    myExtraRows$rowID <- NA
    myExtraRows$problemDescription <- "Multiple similar error error rows removed for clarity"
    
    # Combine the first row within each group with the extra rows
    shortErrorList <- rbind(numberedErrorList[numberedErrorList$rowNum == 1,fieldsToKeep],myExtraRows)
    shortErrorList <- shortErrorList[order(shortErrorList$tableName, shortErrorList$fieldName, shortErrorList$problemType, shortErrorList$rowID),]
    
    errorList <- shortErrorList
    
  }
  
  # Our list of errors
  errorList
  
  
  
  
}