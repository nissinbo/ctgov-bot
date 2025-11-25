chat_bot <- function(system_prompt = NULL, default_turns = list()) {
  system_prompt <- system_prompt %||% databot_prompt()
  if (exists("load_env")) try(load_env(), silent = TRUE)

  chat <- initialize_chat_client(system_prompt)

  chat$set_turns(default_turns)
  
  chat$register_tool(tool(
    run_r_code,
    "Executes R code in the current session",
    arguments = list(
      code = type_string("R code to execute")
    )
  ))
  chat$register_tool(tool(
    create_quarto_report,
    "Creates a Quarto report and displays it to the user",
    arguments = list(
      filename = type_string(
        "The desired filename of the report. Should end in `.qmd`."
      ),
      content = type_string("The full content of the report, as a UTF-8 string.")
    )
  ))
  chat$register_tool(tool(
    query_aact_database,
    "Execute SQL queries against the AACT clinical trials database",
    arguments = list(
      sql_query = type_string("SQL query to execute against AACT database"),
      description = type_string("Brief description of what this query does for the user")
    )
  ))
  chat
}

initialize_chat_client <- function(system_prompt) {
  attempts <- build_chat_attempts(system_prompt)
  if (length(attempts) == 0) {
    stop("No chat providers are available. Please configure Azure OpenAI, AWS Bedrock, or Gemini credentials.")
  }
  errors <- list()
  for (attempt in attempts) {
    result <- try(attempt$factory(), silent = TRUE)
    if (!inherits(result, "try-error")) {
      message("Using ", attempt$name, " for chat completions")
      return(result)
    }
    condition <- attr(result, "condition")
    errors[[attempt$name]] <- if (inherits(condition, "condition")) {
      conditionMessage(condition)
    } else {
      as.character(result)
    }
  }
  stop(
    "Unable to initialize any chat provider. Errors: ",
    paste(sprintf("%s: %s", names(errors), unlist(errors)), collapse = "; ")
  )
}

build_chat_attempts <- function(system_prompt) {
  attempts <- list()
  azure_ctor <- get0("chat_azure_openai", mode = "function", inherits = TRUE)
  bedrock_ctor <- get0("chat_bedrock_claude", mode = "function", inherits = TRUE)
  if (is.null(bedrock_ctor)) {
    bedrock_ctor <- get0("chat_bedrock", mode = "function", inherits = TRUE)
  }
  gemini_ctor <- get0("chat_google_gemini", mode = "function", inherits = TRUE)

  if (!is.null(azure_ctor) && has_azure_credentials()) {
    attempts <- c(attempts, list(list(
      name = "Azure OpenAI",
      factory = function() {
        azure_ctor(
          endpoint = Sys.getenv("AZURE_OPENAI_ENDPOINT"),
          api_key = Sys.getenv("AZURE_OPENAI_API_KEY"),
          deployment = Sys.getenv("AZURE_OPENAI_DEPLOYMENT"),
          api_version = Sys.getenv("AZURE_OPENAI_API_VERSION", "2024-06-01"),
          system_prompt = system_prompt,
          echo = "none"
        )
      }
    )))
  }

  if (!is.null(bedrock_ctor) && has_bedrock_configuration()) {
    attempts <- c(attempts, list(list(
      name = "AWS Bedrock",
      factory = function() {
        bedrock_ctor(
          model = Sys.getenv("BEDROCK_MODEL"),
          profile = null_if_empty(Sys.getenv("AWS_PROFILE")),
          region = Sys.getenv("AWS_DEFAULT_REGION", "us-east-1"),
          system_prompt = system_prompt,
          echo = "none"
        )
      }
    )))
  }

  if (!is.null(gemini_ctor) && nzchar(Sys.getenv("GEMINI_API_KEY", ""))) {
    attempts <- c(attempts, list(list(
      name = "Google Gemini",
      factory = function() {
        gemini_ctor(
          api_key = Sys.getenv("GEMINI_API_KEY"),
          system_prompt = system_prompt,
          echo = "none"
        )
      }
    )))
  }

  attempts
}

has_azure_credentials <- function() {
  all(
    nzchar(Sys.getenv("AZURE_OPENAI_ENDPOINT", "")),
    nzchar(Sys.getenv("AZURE_OPENAI_API_KEY", "")),
    nzchar(Sys.getenv("AZURE_OPENAI_DEPLOYMENT", ""))
  )
}

has_bedrock_configuration <- function() {
  nzchar(Sys.getenv("BEDROCK_MODEL", ""))
}

null_if_empty <- function(value) {
  if (!nzchar(value)) return(NULL)
  value
}
