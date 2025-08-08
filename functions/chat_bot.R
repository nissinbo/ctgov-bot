chat_bot <- function(system_prompt = NULL, default_turns = list()) {
  system_prompt <- system_prompt %||% databot_prompt()

  # Ensure env vars from .env are loaded (defined in database.R)
  if (exists("load_env")) try(load_env(), silent = TRUE)

  # Prefer Azure OpenAI if credentials are present
  azure_key <- Sys.getenv("AZURE_OPENAI_API_KEY", "")
  if (nzchar(azure_key)) {
    endpoint    <- Sys.getenv("AZURE_OPENAI_ENDPOINT", "")
    deployment  <- Sys.getenv("AZURE_OPENAI_DEPLOYMENT", "")
    api_version <- Sys.getenv("AZURE_OPENAI_API_VERSION", "2024-06-01")

    if (!nzchar(endpoint) || !nzchar(deployment)) {
      abort("Azure OpenAI is selected but AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_DEPLOYMENT must be set in .env")
    }

    # Use official Azure helper from ellmer (reference-correct args)
    if (!exists("chat_azure_openai")) {
      abort("Azure OpenAI client (chat_azure_openai) is not available. Please update the ellmer package to a version that supports Azure OpenAI.")
    }
    chat <- chat_azure_openai(
      endpoint = endpoint,
      deployment_id = deployment,
      api_version = api_version,
      system_prompt = system_prompt,
      api_key = azure_key,
      echo = "none"
    )
  } else {
    # Try AWS Bedrock (Claude) next
    bedrock_model <- Sys.getenv("BEDROCK_MODEL", "")
    bedrock_profile <- Sys.getenv("AWS_PROFILE", "")
    bedrock_base_url <- Sys.getenv("BEDROCK_BASE_URL", "")
    # Heuristics: use Bedrock if model/profile/credentials hint is present
    use_bedrock <- nzchar(bedrock_model) || nzchar(bedrock_profile) ||
      nzchar(Sys.getenv("AWS_ACCESS_KEY_ID", "")) || nzchar(Sys.getenv("AWS_DEFAULT_REGION", ""))

    if (use_bedrock) {
      if (!exists("chat_aws_bedrock")) {
        abort("AWS Bedrock client (chat_aws_bedrock) is not available. Please update the ellmer package to a version that supports AWS Bedrock.")
      }
      if (!nzchar(bedrock_model)) {
        # Provide a sensible default but encourage explicit configuration in README
        bedrock_model <- "anthropic.claude-3-5-sonnet-20240620-v1:0"
      }
      args <- list(
        system_prompt = system_prompt,
        model = bedrock_model,
        echo = "none"
      )
      if (nzchar(bedrock_profile)) args$profile <- bedrock_profile
      if (nzchar(bedrock_base_url)) args$base_url <- bedrock_base_url
      chat <- do.call(chat_aws_bedrock, args)
    } else {
      # Fallback to Gemini if neither Azure nor Bedrock is configured
    gemini_key <- Sys.getenv("GEMINI_API_KEY", "")
    if (!nzchar(gemini_key)) {
        abort("No LLM credentials found; set AZURE_OPENAI_* or configure AWS Bedrock (BEDROCK_MODEL/AWS_PROFILE) or set GEMINI_API_KEY in .env")
    }
    if (!exists("chat_google_gemini")) {
      abort("Gemini client not available; please install/update the ellmer package or provide Azure OpenAI credentials.")
    }
    chat <- chat_google_gemini(
      model = "gemini-2.5-flash",
      api_key = gemini_key,
      system_prompt = system_prompt,
      echo = "none"
    )
    }
  }

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
