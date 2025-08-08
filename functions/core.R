# Core functionality for R code execution and Quarto reports

# R Code Evaluation Engine

#' Evaluate R code and capture all outputs in a structured format
#' @param code Character string containing R code to evaluate
#' @return List containing structured output information
#' @noRd
evaluate_r_code <- function(code, on_console_out, on_console_err, on_plot, on_dataframe) {
  cat("Running code...\n")
  cat(code, "\n", sep = "")
  
  # Evaluate the code and capture all outputs
  evaluate::evaluate(
    code,
    envir = globalenv(), # evaluate in the global environment
    stop_on_error = 1, # stop on first error
    output_handler = evaluate::new_output_handler(
      text = function(value) {
        on_console_out(as_str(value))
      },
      graphics = function(recorded_plot) {
        plot <- recorded_plot_to_png(recorded_plot)
        on_plot(plot$mime, plot$content)
      },
      message = function(cond) {
        on_console_out(as_str(conditionMessage(cond), "\n"))
      },
      warning = function(cond) {
        on_console_out(as_str("Warning: ", conditionMessage(cond), "\n"))
      },
      error = function(cond) {
        on_console_out(as_str("Error: ", conditionMessage(cond), "\n"))
      },
      value = function(value) {
        # Mostly to get ggplot2 to plot
        # Find the appropriate S3 method for `print` using class(value)
        if (is.data.frame(value)) {
          on_dataframe(value)
        } else {
          printed_str <- as_str(utils::capture.output(print(value)))
          if (nchar(printed_str) > 0 && !grepl("\n$", printed_str)) {
            printed_str <- paste0(printed_str, "\n")
          }
          on_console_out(printed_str)
        }
      }
    )
  )
  invisible()
}

#' Save a recorded plot to base64 encoded PNG
#' 
#' @param recorded_plot Recorded plot to save
#' @param ... Additional arguments passed to [png()]
#' @noRd
recorded_plot_to_png <- function(recorded_plot, ...) {
  plot_file <- tempfile(fileext = ".png")
  on.exit(if (plot_file != "" && file.exists(plot_file)) unlink(plot_file))

  grDevices::png(plot_file, ...)
  tryCatch(
    {
      grDevices::replayPlot(recorded_plot)
    },
    finally = {
      grDevices::dev.off()
    }
  )
  
  # Convert the plot to base64
  plot_data <- base64enc::base64encode(plot_file)
  list(mime = "image/png", content = plot_data)
}

# Data Frame Utilities

split_df <- function(n, show_start = 5, show_end = 0) {
  if (n <= show_start + show_end) {
    return(list(
      head = n,
      skip = 0,
      tail = 0
    ))
  } else {
    return(list(
      head = show_start,
      skip = n - show_start - show_end,
      tail = show_end
    ))
  }
}

encode_df_for_model <- function(df, max_rows = 5, show_end = 0) {
  if (nrow(df) == 0) {
    return(paste(collapse = "\n", utils::capture.output(print(as_tibble(df)))))
  }

  split <- split_df(nrow(df), show_start = max_rows, show_end = show_end)

  if (split$skip == 0) {
    return(df_to_json(df))
  }

  parts <- c(
    df_to_json(head(df, split$head)),
    sprintf("... %d rows omitted ...", split$skip)
  )
  if (split$tail > 0) {
    parts <- c(parts, df_to_json(tail(df, split$tail)))
  }
  paste(parts, collapse = "\n")
}

df_to_json <- function(df) {
  jsonlite::toJSON(df, dataframe = "rows", na = "string")
}

# Tool Functions

# Creates a Quarto report and displays it to the user
#
# @param filename The desired filename of the report. Should end in `.qmd`.
# @param content The full content of the report, as a UTF-8 string.
create_quarto_report <- function(filename, content) {
  dir.create(here::here("reports"), showWarnings = FALSE)
  dest <- file.path("reports", basename(filename))
  # TODO: Ensure UTF-8 encoding, even on Windows
  writeLines(content, dest)
  message("Saved report to ", dest)
  system2("quarto", c("render", dest))
  # change extension to .html
  rendered <- paste0(tools::file_path_sans_ext(dest), ".html")
  if (file.exists(rendered)) {
    message("Opening report in browser...")
    utils::browseURL(rendered)
  }
  invisible(NULL)
}

# Executes R code in the current session
#
# @param code R code to execute
# @returns The results of the evaluation
# @noRd
run_r_code <- function(code) {
  # Try hard to suppress ANSI terminal formatting characters
  withr::local_envvar(NO_COLOR = 1)
  withr::local_options(rlib_interactive = FALSE, rlang_interactive = FALSE)

  if (in_shiny()) {
    out <- MarkdownStreamer$new(function(md_text) {
      save_output_chunk(md_text)
      chat_append_message(
        "chat",
        list(role = "assistant", content = md_text),
        chunk = TRUE,
        operation = "append"
      )
    })
  } else {
    out <- NullStreamer$new()
  }
  on.exit(out$close(), add = TRUE, after = FALSE)

  # What gets returned to the LLM
  result <- list()

  out_img <- function(media_type, b64data) {
    result <<- c(
      result,
      list(list(
        type = "image_url",
        image_url = list(
          url = sprintf("data:%s;base64,%s", media_type, b64data)
        )
      ))
    )
    out$md(
      sprintf("![Plot](data:%s;base64,%s)\n\n", media_type, b64data),
      TRUE,
      FALSE
    )
  }

  out_df <- function(df) {
  ROWS_START <- 5
  ROWS_END <- 0

    # For the model
    df_json <- encode_df_for_model(
      df,
      max_rows = ROWS_START,
      show_end = ROWS_END
    )
    result <<- c(result, list(list(type = "text", text = df_json)))
    # For human
    # Make sure human sees same EXACT rows as model, this includes omitting the same rows
    split <- split_df(nrow(df), show_start = ROWS_START, show_end = ROWS_END)
    attrs <- "class=\"data-frame table table-sm table-striped\""
    md_tbl <- paste0(
      collapse = "\n",
      knitr::kable(head(df, split$head), format = "html", table.attr = attrs)
    )
    if (split$skip > 0) {
      md_tbl_skip <- sprintf("... %d rows omitted ...", split$skip)
      if (split$tail > 0) {
        md_tbl_tail <- knitr::kable(
          tail(df, split$tail),
          format = "html",
          table.attr = attrs
        )
        md_tbl <- as_str(md_tbl, md_tbl_skip, md_tbl_tail)
      } else {
        md_tbl <- as_str(md_tbl, md_tbl_skip)
      }
    }
    out$md(md_tbl, TRUE, TRUE)
  }

  out_txt <- function(txt, end = NULL) {
    txt <- paste(txt, collapse = "\n")
    if (txt == "") {
      return()
    }
    if (!is.null(end)) {
      txt <- paste0(txt, end)
    }
    result <<- c(result, list(list(type = "text", text = txt)))
    out$code(txt)
  }

  out$code(code)
  # End the source code block so the outputs all appear in a separate block
  out$close()

  # Use the new evaluate_r_code function
  if (in_shiny()) {
    shiny::withLogErrors({
      evaluate_r_code(
        code,
        on_console_out = out_txt,
        on_console_err = out_txt,
        on_plot = out_img,
        on_dataframe = out_df
      )
    })
  } else {
    evaluate_r_code(
      code,
      on_console_out = out_txt,
      on_console_err = out_txt,
      on_plot = out_img,
      on_dataframe = out_df
    )
  }

  result <- coalesce_text_outputs(result)

  I(result)
}

# AACT Database Query Tool
query_aact_database <- function(sql_query, description = "Database query") {
  if (!globals$aact_connected) {
    return("❌ AACT database is not connected. Please check the connection.")
  }
  
  # Clean up SQL query - remove trailing semicolons and extra whitespace
  sql_query <- trimws(sql_query)
  sql_query <- gsub(";\\s*$", "", sql_query)

  # Detect LIMIT clause in the original SQL (case-insensitive)
  # Capture the numeric value after LIMIT if present (e.g., LIMIT 50 or LIMIT\n 50)
  limit_in_sql <- NULL
  m <- regexpr("(?i)\\bLIMIT\\s+(\\d+)", sql_query, perl = TRUE)
  if (m > 0) {
    limit_in_sql <- as.integer(regmatches(sql_query, m, invert = FALSE))
    # Extract just the number group
    # regmatches returns the full match; extract the digits using sub
    limit_in_sql <- as.integer(sub("(?i).*\\bLIMIT\\s+(\\d+).*", "\\1", regmatches(sql_query, m, invert = FALSE), perl = TRUE))
  }
  # No implicit safety cap enforced at execution time
  
  # Create output streamer for user feedback if in Shiny
  if (in_shiny()) {
    out <- MarkdownStreamer$new(function(md_text) {
      save_output_chunk(md_text)
      chat_append_message(
        "chat",
        list(role = "assistant", content = md_text),
        chunk = TRUE,
        operation = "append"
      )
    })
    
    # Show SQL query to user immediately
      # Show SQL query to user in a collapsible block (collapsed by default)
      out$md(paste0(
        "### 📊 ", description, "\n\n",
    "<details class=\"sql-block\">\n",
    "<summary class=\"sql-summary\"><strong>Show SQL</strong> <span class=\"hint-closed\">(click to expand)</span><span class=\"hint-open\">(click to collapse)</span></summary>\n\n",
        "```sql\n",
        sql_query,
        "\n```\n",
        "</details>\n"
      ), TRUE, TRUE)
    
    # Show loading message
  out$md("Running query...\n", TRUE, FALSE)
    
    on.exit(out$close(), add = TRUE, after = FALSE)
  }
  
  # Execute the query
  tryCatch({
  result <- execute_aact_query(sql_query)
    
    # Store result for R analysis
    assign("aact_query_result", result, envir = globalenv())
    
    # Show results to user if in Shiny
    if (in_shiny()) {
      if (nrow(result) == 0) {
        out$md("**Result:** No data matched your criteria.\n", TRUE, TRUE)
      } else {
        # Determine if we likely hit a cap or LIMIT and get the total count when appropriate
        total <- NA_integer_
  need_total <- FALSE
  if (!is.null(limit_in_sql) && nrow(result) >= limit_in_sql) need_total <- TRUE
        if (need_total) {
          # Best-effort total count; ignore errors
          try({ total <- count_aact_query_rows(sql_query) }, silent = TRUE)
        }

        # Build message that avoids implying ordering (no 'first')
        if (!is.na(total)) {
          msg <- paste0("**Result:** Showing ", nrow(result), " of ", total, " matching records.\n")
        } else {
          msg <- paste0("**Result:** Showing ", nrow(result), " matching records.\n")
        }
        # If SQL had LIMIT, explicitly mention that the preview shows the first N rows
        if (!is.null(limit_in_sql)) {
          msg <- paste0(
            msg,
            sprintf("\nNote: Due to SQL LIMIT %d, showing up to %d rows.\n", limit_in_sql, limit_in_sql)
          )
        }
        # Do not mention app-level safety cap here
        out$md(msg, TRUE, TRUE)
      }
    }
    
    # Return simplified response for LLM
    if (nrow(result) == 0) {
      return("Query executed successfully. No data found matching the criteria.")
    } else {
      # Provide a concise textual summary without exposing internal variables
  lim_txt <- if (!is.null(limit_in_sql)) paste0(" Note: Showing up to ", limit_in_sql, " rows due to SQL LIMIT.") else ""
      # Build concise model-facing summary without implying full retrieval
      total_suffix <- ""
      total <- NA_integer_
  need_total <- FALSE
  if (!is.null(limit_in_sql) && nrow(result) >= limit_in_sql) need_total <- TRUE
      if (need_total) {
        try({ total <- count_aact_query_rows(sql_query) }, silent = TRUE)
      }
      if (!is.na(total)) {
        return(paste0("Query executed successfully.", lim_txt, " Showing ", nrow(result), " of ", total, " matching records."))
      } else {
        return(paste0("Query executed successfully.", lim_txt, " Showing ", nrow(result), " matching records."))
      }
    }
    
  }, error = function(e) {
    error_msg <- paste0("❌ Failed to execute SQL query: ", e$message)
    
    if (in_shiny()) {
      out$md(error_msg, TRUE, TRUE)
    }
    
    return(error_msg)
  })
}

# Utility Functions

in_shiny <- function() {
  !is.null(shiny::getDefaultReactiveDomain())
}

# Combine consecutive text outputs into one, for better readability (for both us
# and the model).
coalesce_text_outputs <- function(content_list) {
  txt_buffer <- character(0)
  result_content_list <- list()

  flush_buffer <- function() {
    if (length(txt_buffer) > 0) {
      result_content_list <<- c(
        result_content_list,
        list(list(type = "text", text = paste(txt_buffer, collapse = "\n")))
      )
      txt_buffer <<- character(0)
    }
  }

  for (content in content_list) {
    if (content[["type"]] == "text") {
      if (nzchar(content[["text"]])) {
        txt_buffer <- c(txt_buffer, content[["text"]])
      }
    } else {
      flush_buffer()
      result_content_list <- c(result_content_list, list(content))
    }
  }
  if (length(txt_buffer) > 0) {
    flush_buffer()
  }

  result_content_list
}
