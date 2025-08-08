# Server logic
server <- function(input, output, session) {
  # Allow reconnection and manage sessions
  session$allowReconnect(TRUE)
  latest_session(session$token)
  
  # Monitor for multiple sessions
  observe({
    if (!identical(latest_session(), session$token)) {
      showModal(modalDialog(
        "Your session ended because a new session was started in a ",
        "different browser tab.",
        fade = FALSE,
        easyClose = TRUE
      ))
      session$close()
    }
  })

  restored_since_last_turn <- FALSE

  # Restore previous chat session, if applicable
  if (globals$ui_messages$size() > 0) {
    ui_msgs <- globals$ui_messages$as_list()
    if (identical(ui_msgs[[1]], list(role = "user", content = "Hello"))) {
      ui_msgs <- ui_msgs[-1]
    }
    for (msg in ui_msgs) {
      chat_append_message("chat", msg, chunk = FALSE)
    }
    restored_since_last_turn <- TRUE
  }

  chat <- chat_bot(default_turns = globals$turns)
  
  # Initialize AACT database connection
  init_aact_connection()
  
  start_chat_request <- function(user_input) {
    # For local debugging
    if (interactive()) {
      globals$last_chat <- chat
    }

    prefix <- if (restored_since_last_turn) {
      paste0(
        "(Continuing previous chat session. The R environment may have ",
        "changed since the last request/response.)\n\n"
      )
    } else {
      ""
    }
    restored_since_last_turn <<- FALSE

    stream <- save_stream_output()(
      chat$stream_async(paste0(prefix, user_input))
    )
    chat_append("chat", stream) |>
      promises::then(
        ~ {
          if (session$isClosed()) {
            req(FALSE)
          }

          # After each successful turn, save everything in case we need to
          # restore (i.e. user stops the app and restarts it)
          globals$turns <- chat$get_turns()
          save_messages(
            list(role = "user", content = user_input),
            list(role = "assistant", content = take_pending_output())
          )
        }
      ) |>
      promises::finally(
        ~ {
          tokens <- chat$get_tokens()
          last_input <- tail(tokens[tokens$role == "user", "tokens_total"], 1)
          last_output <- tail(tokens[tokens$role == "assistant", "tokens_total"], 1)
          total_input <- sum(tokens[tokens$role == "user", "tokens_total"])
          total_output <- sum(tokens[tokens$role == "assistant", "tokens_total"])

          cat("\n")
          cat(rule("Turn ", nrow(tokens)), "\n", sep = "")
          cat("Input tokens:  ", last_input, "\n", sep = "")
          cat("Output tokens: ", last_output, "\n", sep = "")
          cat("Total input tokens:  ", total_input, "\n", sep = "")
          cat("Total output tokens: ", total_output, "\n", sep = "")
          cat("\n")
        }
      )
  }

  observeEvent(input$chat_user_input, {
    start_chat_request(input$chat_user_input)
  })

  # Kick start the chat session (unless we've restored a previous session)
  if (length(chat$get_turns()) == 0) {
    start_chat_request("Hello")
  }
}
