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
  ensure_db_dependencies()

  if (aact_connection_valid()) {
    globals$aact_connected <- TRUE
    return(TRUE)
  }

  close_aact_connection()
  credentials <- get_aact_credentials()

  tryCatch({
    con <- DBI::dbConnect(
      RPostgres::Postgres(),
      host = credentials$host,
      port = credentials$port,
      dbname = credentials$dbname,
      user = credentials$user,
      password = credentials$password
    )

    DBI::dbGetQuery(con, "SELECT 1 as test_connection")

    globals$aact_connection <- con
    globals$aact_connected <- TRUE
    globals$aact_last_error <- NULL
    cat("\n🟢 AACT Database Connected Successfully!\n")
    cat("✅ Connection to AACT database established\n")
    cat("📊 Ready to execute clinical trial queries\n\n")
    TRUE
  }, error = function(e) {
    globals$aact_connected <- FALSE
    record_aact_error(conditionMessage(e))
    message("Failed to connect to AACT database: ", conditionMessage(e))
    cat("\n🔴 AACT Database Connection Failed\n")
    cat("❌ Could not establish connection\n")
    cat("💡 Please check your credentials and network connection\n\n")
    FALSE
  })
}

execute_aact_query <- function(sql_query, max_rows = NULL) {
  if (!aact_connection_valid()) {
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
  if (!aact_connection_valid()) {
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
  if (!aact_connection_valid()) {
    globals$aact_connection <- NULL
    globals$aact_connected <- FALSE
    globals$aact_last_error <- NULL
    return(invisible(FALSE))
  }
  try(DBI::dbDisconnect(globals$aact_connection), silent = TRUE)
  globals$aact_connection <- NULL
  globals$aact_connected <- FALSE
  globals$aact_last_error <- NULL
  cat("🔌 AACT database connection closed\n")
  invisible(TRUE)
}

aact_connection_valid <- function() {
  if (is.null(globals$aact_connection)) {
    return(FALSE)
  }
  tryCatch({
    DBI::dbIsValid(globals$aact_connection)
  }, error = function(...) FALSE)
}

ensure_db_dependencies <- function() {
  required_packages <- c("DBI", "RPostgres")
  missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]
  if (length(missing_packages) > 0) {
    stop(
      "Required database packages are missing: ",
      paste(missing_packages, collapse = ", "),
      ". Install them before starting the app."
    )
  }
  invisible(TRUE)
}

get_aact_credentials <- function() {
  creds <- list(
    host = Sys.getenv("AACT_HOST", "aact-db.ctti-clinicaltrials.org"),
    port = as.integer(Sys.getenv("AACT_PORT", "5432")),
    dbname = Sys.getenv("AACT_DATABASE", "aact"),
    user = Sys.getenv("AACT_USERNAME"),
    password = Sys.getenv("AACT_PASSWORD")
  )

  missing_fields <- names(Filter(function(x) is.null(x) || !nzchar(x), creds[c("user", "password")]))
  if (length(missing_fields) > 0) {
    stop(
      "Missing required AACT credentials: ",
      paste(missing_fields, collapse = ", "),
      ". Please set them in the environment or .env file."
    )
  }

  creds
}

register_aact_session <- function(session) {
  if (is.null(session)) return(invisible(FALSE))
  globals$aact_session_count <- globals$aact_session_count + 1L
  session$onSessionEnded(function() {
    unregister_aact_session()
  })
  invisible(TRUE)
}

unregister_aact_session <- function() {
  globals$aact_session_count <- max(0L, globals$aact_session_count - 1L)
  if (globals$aact_session_count == 0L) {
    close_aact_connection()
  }
  invisible(TRUE)
}

record_aact_error <- function(message) {
  globals$aact_last_error <- message
  invisible(TRUE)
}

get_aact_last_error <- function() {
  globals$aact_last_error
}
