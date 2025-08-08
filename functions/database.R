# Database connectivity for AACT

# Load environment variables
load_env <- function() {
  env_file <- ".env"
  if (file.exists(env_file)) {
    env_vars <- readLines(env_file)
    env_vars <- env_vars[!grepl("^#", env_vars) & nchar(env_vars) > 0]
    
    for (var in env_vars) {
      parts <- strsplit(var, "=", fixed = TRUE)[[1]]
      if (length(parts) >= 2) {
        # Handle cases where value might contain "=" characters
        env_name <- trimws(parts[1])
        env_value <- trimws(paste(parts[-1], collapse = "="))
        
        # Set environment variable using assignment
        args <- list()
        args[[env_name]] <- env_value
        do.call(Sys.setenv, args)
      }
    }
  }
}

# Initialize database connection
init_aact_connection <- function() {
  load_env()
  
  # Check if required packages are available
  required_packages <- c("DBI", "RPostgres")
  missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]
  
  if (length(missing_packages) > 0) {
    message("Installing required database packages: ", paste(missing_packages, collapse = ", "))
    install.packages(missing_packages, quiet = TRUE)
  }
  
  # Load libraries
  library(DBI)
  library(RPostgres)
  
  tryCatch({
    # Create connection
    con <- DBI::dbConnect(
      RPostgres::Postgres(),
      host = Sys.getenv("AACT_HOST", "aact-db.ctti-clinicaltrials.org"),
      port = as.integer(Sys.getenv("AACT_PORT", "5432")),
      dbname = Sys.getenv("AACT_DATABASE", "aact"),
      user = Sys.getenv("AACT_USERNAME"),
      password = Sys.getenv("AACT_PASSWORD")
    )
    
    # Test connection with a simple query
    test_result <- DBI::dbGetQuery(con, "SELECT 1 as test_connection")
    
    if (nrow(test_result) == 1) {
      # Store connection globally
      globals$aact_connection <- con
      globals$aact_connected <- TRUE
      
      # Show success message
      cat("\n")
      cat("🟢 AACT Database Connected Successfully!\n")
      cat("✅ Connection to AACT database established\n")
      cat("📊 Ready to execute clinical trial queries\n")
      cat("\n")
      
      return(TRUE)
    } else {
      stop("Connection test failed")
    }
    
  }, error = function(e) {
    globals$aact_connected <- FALSE
    warning("Failed to connect to AACT database: ", e$message)
    cat("\n")
    cat("🔴 AACT Database Connection Failed\n")
    cat("❌ Could not establish connection\n")
    cat("💡 Please check your credentials and network connection\n")
    cat("\n")
    return(FALSE)
  })
}

# Execute SQL query safely
execute_aact_query <- function(sql_query, max_rows = NULL) {
  if (!globals$aact_connected || is.null(globals$aact_connection)) {
    stop("AACT database is not connected. Please check connection.")
  }
  
  # Clean up the SQL query - remove trailing semicolons and whitespace
  sql_query <- trimws(sql_query)
  sql_query <- gsub(";\\s*$", "", sql_query)
  
  # Do not enforce an automatic LIMIT here to avoid inconsistencies with counts
  
  tryCatch({
    # Log the SQL query
    cat("\n📝 Executing SQL Query:\n")
    cat("```sql\n")
    cat(sql_query)
    cat("\n```\n\n")
    
  # Execute the query as-is (no implicit LIMIT)
  result <- DBI::dbGetQuery(globals$aact_connection, sql_query)
    
    # Log results summary
    cat("✅ Query executed successfully\n")
  cat("📊 Returned", nrow(result), "rows,", ncol(result), "columns\n\n")
    
    return(result)
    
  }, error = function(e) {
    cat("❌ SQL Query failed:", e$message, "\n\n")
    stop("SQL execution error: ", e$message)
  })
}

# Count total rows for a given SQL query (ignoring any trailing LIMIT)
count_aact_query_rows <- function(sql_query) {
  if (!globals$aact_connected || is.null(globals$aact_connection)) {
    stop("AACT database is not connected. Please check connection.")
  }

  # Normalize SQL
  sql_query <- trimws(sql_query)
  sql_query <- gsub(";\\s*$", "", sql_query)
  # Remove trailing LIMIT (and optional OFFSET) if present
  sql_no_limit <- gsub("(?i)\\s*LIMIT\\s+\\d+(\\s+OFFSET\\s+\\d+)?\\s*$", "", sql_query, perl = TRUE)

  count_sql <- paste0(
    "SELECT COUNT(*) AS total_count FROM (\n",
    sql_no_limit,
    "\n) subquery"
  )

  res <- DBI::dbGetQuery(globals$aact_connection, count_sql)
  if (!is.null(res$total_count) && length(res$total_count) >= 1) {
    return(as.integer(res$total_count[[1]]))
  } else {
    stop("Unexpected COUNT(*) result structure")
  }
}

# Get database connection status
get_aact_status <- function() {
  if (exists("aact_connected", envir = globals) && globals$aact_connected) {
    return("🟢 Connected")
  } else {
    return("🔴 Not Connected")
  }
}

# Close database connection
close_aact_connection <- function() {
  if (exists("aact_connection", envir = globals) && !is.null(globals$aact_connection)) {
    DBI::dbDisconnect(globals$aact_connection)
    globals$aact_connection <- NULL
    globals$aact_connected <- FALSE
    cat("🔌 AACT database connection closed\n")
  }
}
