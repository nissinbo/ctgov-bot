# Server logic
server <- function(input, output, session) {
  # Initialize session-specific storage
  session$userData$storage <- list(
    pending_output = fastmap::fastqueue(),
    last_chat = NULL
  )
  
  # Create new chat bot for this session
  chat <- chat_bot(default_turns = list())
  if (init_aact_connection()) {
    register_aact_session(session)
  }
  
  log_chat_token_usage <- function(chat_client) {
    tokens <- try(chat_client$get_tokens(), silent = TRUE)
    if (inherits(tokens, "try-error") || !is.data.frame(tokens)) {
      return(invisible(NULL))
    }
    required_cols <- c("role", "tokens_total")
    if (!all(required_cols %in% names(tokens)) || nrow(tokens) == 0) {
      return(invisible(NULL))
    }
    user_tokens <- tokens$tokens_total[tokens$role == "user"]
    assistant_tokens <- tokens$tokens_total[tokens$role == "assistant"]

    last_input <- if (length(user_tokens)) tail(user_tokens, 1) else NA
    last_output <- if (length(assistant_tokens)) tail(assistant_tokens, 1) else NA
    total_input <- if (length(user_tokens)) sum(user_tokens) else NA
    total_output <- if (length(assistant_tokens)) sum(assistant_tokens) else NA

    cat("\n")
    cat(rule("Turn ", nrow(tokens)), "\n", sep = "")
    cat("Input tokens:  ", last_input, "\n", sep = "")
    cat("Output tokens: ", last_output, "\n", sep = "")
    cat("Total input tokens:  ", total_input, "\n", sep = "")
    cat("Total output tokens: ", total_output, "\n", sep = "")
    cat("\n")
    invisible(NULL)
  }

  start_chat_request <- function(user_input) {
    if (interactive()) session$userData$storage$last_chat <- chat
    
    stream <- coro::async_generator(function(stream) {
      for (chunk in coro::await_each(stream)) {
        if (session$isClosed()) {
          req(FALSE)
        }
        save_output_chunk(chunk)
        coro::yield(chunk)
      }
    })(chat$stream_async(user_input))
    chat_append("chat", stream) |>
      promises::then(
        ~ {
          if (session$isClosed()) req(FALSE)
          take_pending_output()
        }
      ) |>
      promises::finally(~ log_chat_token_usage(chat))
  }

  observeEvent(input$chat_user_input, {
    start_chat_request(input$chat_user_input)
  })

  # Kick start the chat session with greeting
  start_chat_request("Hello")
}
