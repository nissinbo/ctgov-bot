# Server logic
server <- function(input, output, session) {
  # Initialize session-specific storage
  session$userData$storage <- list(
    pending_output = fastmap::fastqueue(),
    last_chat = NULL
  )
  
  # Create new chat bot for this session
  chat <- chat_bot(default_turns = list())
  init_aact_connection()
  
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

  # Kick start the chat session with greeting
  start_chat_request("Hello")
}
