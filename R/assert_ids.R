#' Assert that a data.frame contains all unique combinations of specified ID variables, and doesn't contain duplicates within combinations
#'
#' Given a data.frame or data.table object and a named list of id_vars, assert that all possible combinations of id_vars exist in the dataset,
#' that no combinations of id_vars exist in the dataset but not in id_vars,
#' and that there are no duplicate values within the dataset within unique combinations of id_vars. \cr \cr
#' If ids_only = T and assert_dups = T, returns all combinations of id_vars along with the \emph{n_duplicates}: the count of duplicates within each combination.
#' If ids_only = F, returns all duplicate observations from the original dataset along with \emph{n_duplicates}
#' and \emph{duplicate_id}: a unique ID for each duplicate value within each combination of id_vars. \cr
#'
#' Note: if assert_combos = T and is violated, then assert_ids will stop execution and return results for assert_combos
#'        before evaluating the assert_dups segment of the code.
#'        If you want to make sure both options are evaluated even in case of a violation in assert_combos,
#'        call assert_ids twice (once with assert_dups = F, then assert_combos = F) with warn_only = T,
#'        and then conditionally stop your code if either call returns results.

#' @param data A data.frame or data.table
#' @param id_vars A named list of vectors, where the name of each vector must correspond to a column in \emph{data}
#' @param assert_combos Assert that the data object must contain all combinations of \emph{id_vars}. Default = T.
#' @param assert_dups Assert that the data object must not contain duplicate values within any combinations of \emph{id_vars}. Default = T.
#' @param ids_only By default, with assert_dups = T, the function returns the unique combinations of id_vars that have duplicate observations.
#'                  If ids_only = F, will return every observation in the original dataset that are duplicates.
#' @param warn_only Do you want to warn, rather than error? Will return all offending rows from the first violation of the assertion. Default=F.
#' @param quiet Do you want to suppress the printed message when a test is passed? Default = F.

#' @return Throws error if test is violated. Will print the offending rows. If warn_only=T, will return all offending rows and only warn.
#' @export

#' @examples
#' plants <- as.character(unique(CO2$Plant))
#' concs <- unique(CO2$conc)
#' ids <- list(Plant=plants,conc=concs)
#' assert_ids(CO2, ids)

#' @import data.table

assert_ids <- function(data, id_vars, assert_combos=TRUE, assert_dups=TRUE, ids_only = TRUE, warn_only=FALSE, quiet=FALSE) {
  id_varnames <- names(id_vars)

  for(varname in id_varnames) {
    if(!varname %in% colnames(data)) stop(paste("The following id_var must exist as a column name in your dataset:",varname))
    ## Coerce factors to characters to avoid any merge or display issues
    if(is.factor(id_vars[[varname]])) id_vars[[varname]] <- as.character(id_vars[[varname]])

    ## Stop if trying to use assert_ids on a factor that contains underlying numeric values
    ## Too difficult to match them (data.table matches numerics to the underlying numeric value, not the label)
    ## And don't want to coerce the character types back-and-forth
    if(is.data.table(data)){
      if(is.factor(data[, get(varname)])) {
        if(typeof(id_vars[[varname]]) != "character")
          stop(paste0("Cannot evaluate ", varname, ": the variable in the data is factor while the values for the variable in the id_vars list are not character values or factors. ",
                      "Either convert variable from factor to character/numeric or express id_vars as character values of the levels or as a factor itself"))
      }
    } else {
      if(is.factor(data[, varname])){
        if(typeof(id_vars[[varname]]) != "character")
          stop(paste0("Cannot evaluate ", varname, ": the variable in the data is factor while the values for the variable in the id_vars list are not character values or factors. ",
                      "Either convert variable from factor to character/numeric or express id_vars as character values of the levels or as a factor itself"))
      }
    }
  }

  ## Extract the combinations of id variables from the dataset
  if(is.data.table(data)) {
    data_ids <- data[, .SD, .SDcols=id_varnames]
    setkey(data_ids, NULL) # Remove key to avoid unique() issues for older versions of data.table
    data_ids <- unique(data_ids, by = id_varnames)
  } else {
    data_ids <- data.table(unique(data[, id_varnames]))
    if(length(id_varnames) == 1) {
      if(colnames(data_ids) == "V1") setnames(data_ids, "V1", id_varnames)
    }
  }

  ## Create unique combinations of all id variables based on input id_vars
  target_ids <- data.table(do.call(CJ, id_vars))
  if(assert_combos==TRUE){
    target_ids$in_target <- 1
    data_ids$in_data <- 1

    merged_ids <- merge(data_ids, target_ids, by=id_varnames, all=TRUE)

    if(nrow(merged_ids[merged_ids$in_data==1]) != nrow(merged_ids)) {
      if(warn_only == FALSE) {
        stop(paste0(
          "\n", paste0(capture.output(merged_ids[is.na(merged_ids$in_data), .SD, .SDcols=id_varnames]), collapse="\n"),
          "\nThe above combinations of id variables do not exist in your dataset")
        )
      } else {
        warning("The following combinations of id variables do not exist in your dataset")
        return(merged_ids[is.na(merged_ids$in_data), .SD, .SDcols=id_varnames])
      }
    }
    if(nrow(merged_ids[merged_ids$in_target==1]) != nrow(merged_ids)) {
      if(warn_only == FALSE) {
        stop(paste0(
          "\n", paste0(capture.output(merged_ids[is.na(merged_ids$in_target), .SD, .SDcols=id_varnames]), collapse="\n"),
          "\nThe above combinations of id variables exist in your dataset but not in your id_vars list")
        )
      } else {
        warning("The following combinations of id variables exist in your dataset but not in your id_vars list")
        return(merged_ids[is.na(merged_ids$in_target), .SD, .SDcols=id_varnames])
      }
    }
  }
  if(assert_dups == TRUE & nrow(data_ids) != nrow(data)) {
    data <- data.table(data)
    duplicates <- data[duplicated(data[, .SD, .SDcols=id_varnames])]
    duplicates <- duplicates[, .SD, .SDcols=id_varnames] # Subset columns separately to avoid dt lock issue in <1.9.8 https://github.com/Rdatatable/data.table/issues/1341
    nrow_duplicates <- nrow(duplicates)

    ## Get the total number of duplicates in each id combination.
    ## The duplicated function returns all rows after the first unique combination, so add 1 to the length
    ## Then, take unique to get one row per combination of id_varnames
    ## Use the ("new_var") syntax of data.table to avoid CRAN warnings
    duplicate_ids <- unique(duplicates[, ("n_duplicates") := .N + 1, by=id_varnames])
    nrow_duplicates <- nrow_duplicates + nrow(duplicate_ids)

    if(ids_only == TRUE) {
      err_message <- paste0("These combinations of id variables have n_duplicates ",
          "duplicate observations per combination (",
          nrow_duplicates," total duplicates)")
    } else {
      # Get all rows from the original dataset that are duplicates
      duplicate_ids <- merge(data, duplicate_ids, by=id_varnames)
      # Add duplicate_id, which is an incrementing value (e.g. the first observation is 1, the first duplicate is 2, etc.)
      duplicate_ids[, ("duplicate_id") := 1:.N, by=id_varnames]
      err_message <- paste0("These rows of data are all of the observations with duplicated id_vars, ",
          "and have n_duplicates duplicate observations per combination of id_varnames (",
          nrow_duplicates," total duplicates)")
    }

    if(warn_only == FALSE) {
      stop(
        paste0(
          "\n", paste0(capture.output(duplicate_ids), collapse="\n"),
          "\n", err_message))
    } else {
      warning(err_message)
      return(duplicate_ids)
    }
  }
  if(quiet != TRUE) print(paste0("Data is identified by id_vars: ",paste(id_varnames,collapse=" ")))
}
