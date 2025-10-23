load_env <- function() {
  env_file <- ".env"
  if (file.exists(env_file)) {
    env_vars <- readLines(env_file)
    env_vars <- env_vars[!grepl("^#", env_vars) & nchar(env_vars) > 0]
    
    for (var in env_vars) {
      parts <- strsplit(var, "=", fixed = TRUE)[[1]]
      if (length(parts) >= 2) {
        env_name <- trimws(parts[1])
        env_value <- trimws(paste(parts[-1], collapse = "="))
        args <- list()
        args[[env_name]] <- env_value
        do.call(Sys.setenv, args)
      }
    }
  }
}

init_aact_connection <- function() {
  load_env()
  
  required_packages <- c("DBI", "RPostgres")
  missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]
  
  if (length(missing_packages) > 0) {
    message("Installing required database packages: ", paste(missing_packages, collapse = ", "))
    install.packages(missing_packages, quiet = TRUE)
  }
  
  library(DBI)
  library(RPostgres)
  
  tryCatch({
    con <- DBI::dbConnect(
      RPostgres::Postgres(),
      host = Sys.getenv("AACT_HOST", "aact-db.ctti-clinicaltrials.org"),
      port = as.integer(Sys.getenv("AACT_PORT", "5432")),
      dbname = Sys.getenv("AACT_DATABASE", "aact"),
      user = Sys.getenv("AACT_USERNAME"),
      password = Sys.getenv("AACT_PASSWORD")
    )
    
    test_result <- DBI::dbGetQuery(con, "SELECT 1 as test_connection")
    
    if (nrow(test_result) == 1) {
      globals$aact_connection <- con
      globals$aact_connected <- TRUE
      
      cat("\n🟢 AACT Database Connected Successfully!\n")
      cat("✅ Connection to AACT database established\n")
      cat("📊 Ready to execute clinical trial queries\n\n")
      
      return(TRUE)
    } else {
      stop("Connection test failed")
    }
  }, error = function(e) {
    globals$aact_connected <- FALSE
    warning("Failed to connect to AACT database: ", e$message)
    cat("\n🔴 AACT Database Connection Failed\n")
    cat("❌ Could not establish connection\n")
    cat("💡 Please check your credentials and network connection\n\n")
    return(FALSE)
  })
}

execute_aact_query <- function(sql_query, max_rows = NULL) {
  if (!globals$aact_connected || is.null(globals$aact_connection)) {
    stop("AACT database is not connected. Please check connection.")
  }
  
  sql_query <- trimws(sql_query)
  sql_query <- gsub(";\\s*$", "", sql_query)
  
  tryCatch({
    cat("\n📝 Executing SQL Query:\n```sql\n", sql_query, "\n```\n\n")
    
    result <- DBI::dbGetQuery(globals$aact_connection, sql_query)
    
    cat("✅ Query executed successfully\n")
    cat("📊 Returned", nrow(result), "rows,", ncol(result), "columns\n\n")
    
    return(result)
  }, error = function(e) {
    cat("❌ SQL Query failed:", e$message, "\n\n")
    stop("SQL execution error: ", e$message)
  })
}

count_aact_query_rows <- function(sql_query) {
  if (!globals$aact_connected || is.null(globals$aact_connection)) {
    stop("AACT database is not connected. Please check connection.")
  }
  
  sql_query <- trimws(sql_query)
  sql_query <- gsub(";\\s*$", "", sql_query)
  sql_no_limit <- gsub("(?i)\\s*LIMIT\\s+\\d+(\\s+OFFSET\\s+\\d+)?\\s*$", "", sql_query, perl = TRUE)
  
  count_sql <- paste0("SELECT COUNT(*) AS total_count FROM (\n", sql_no_limit, "\n) subquery")

  res <- DBI::dbGetQuery(globals$aact_connection, count_sql)
  if (!is.null(res$total_count) && length(res$total_count) >= 1) {
    return(as.integer(res$total_count[[1]]))
  }
  stop("Unexpected COUNT(*) result structure")
}

get_aact_status <- function() {
  if (exists("aact_connected", envir = globals) && globals$aact_connected) {
    return("🟢 Connected")
  }
  return("🔴 Not Connected")
}

close_aact_connection <- function() {
  if (exists("aact_connection", envir = globals) && !is.null(globals$aact_connection)) {
    DBI::dbDisconnect(globals$aact_connection)
    globals$aact_connection <- NULL
    globals$aact_connected <- FALSE
    cat("🔌 AACT database connection closed\n")
  }
}
