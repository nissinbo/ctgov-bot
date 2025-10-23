chat_bot <- function(system_prompt = NULL, default_turns = list()) {
  system_prompt <- system_prompt %||% databot_prompt()
  if (exists("load_env")) try(load_env(), silent = TRUE)

  gemini_key <- Sys.getenv("GEMINI_API_KEY", "")
  if (!nzchar(gemini_key)) {
    stop("GEMINI_API_KEY must be set in .env file")
  }
  if (!exists("chat_google_gemini")) {
    stop("Gemini client not available; please install/update the ellmer package.")
  }
  
  chat <- chat_google_gemini(
    api_key = gemini_key,
    system_prompt = system_prompt,
    echo = "none"
  )

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
