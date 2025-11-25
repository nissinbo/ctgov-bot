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
  assert_code_is_safe(code)
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
    
    df_json <- encode_df_for_model(df, max_rows = ROWS_START, show_end = ROWS_END)
    result <<- c(result, list(list(type = "text", text = df_json)))
    
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
  out$close()
  
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

assert_code_is_safe <- function(code) {
  restricted_patterns <- c(
    "\\bread\\.(csv|rds|rdata|table)\\s*\\(",
    "\\bload\\s*\\(",
    "\\bsave(R?DS)?\\s*\\(",
    "\\breadLines\\s*\\(",
    "\\bscan\\s*\\(",
    "\\bfile\\.(create|remove|rename|copy)\\s*\\(",
    "\\bdir\\.(create|remove)\\s*\\(",
    "\\bunlink\\s*\\(",
    "\\bsystem2?\\s*\\(",
    "\\bshell\\s*\\(",
    "\\bdownload\\.file\\s*\\(",
    "\\bsetwd\\s*\\(",
    "\\bsource\\s*\\("
  )
  triggered <- restricted_patterns[
    vapply(restricted_patterns, function(pattern) {
      grepl(pattern, code, ignore.case = TRUE, perl = TRUE)
    }, logical(1))
  ]
  if (length(triggered) > 0) {
    stop(sprintf(
      "Execution blocked. The submitted code references restricted functions (patterns: %s). Please revise the request to avoid local file or system access.",
      paste(unique(triggered), collapse = ", ")
    ))
  }
  invisible(TRUE)
}

# AACT Database Query Tool
query_aact_database <- function(sql_query, description = "Database query") {
  if (!aact_connection_valid()) {
    last_error <- get_aact_last_error()
    msg <- "❌ AACT database is not connected. Please check the connection."
    if (!is.null(last_error) && nzchar(last_error)) {
      msg <- paste0(msg, " Last error: ", last_error, ".")
    }
    return(msg)
  }
  
  sql_query <- trimws(sql_query)
  sql_query <- gsub(";\\s*$", "", sql_query)
  
  limit_in_sql <- NULL
  m <- regexpr("(?i)\\bLIMIT\\s+(\\d+)", sql_query, perl = TRUE)
  if (m > 0) {
    limit_in_sql <- as.integer(sub("(?i).*\\bLIMIT\\s+(\\d+).*", "\\1", 
                                    regmatches(sql_query, m, invert = FALSE), perl = TRUE))
  }
  

  if (in_shiny()) {
    out <- MarkdownStreamer$new(function(md_text) {
      save_output_chunk(md_text)
      chat_append_message("chat", list(role = "assistant", content = md_text), 
                         chunk = TRUE, operation = "append")
    })
    
    out$md(paste0("### 📊 ", description, "\n\n", "**SQL to be executed:**\n"), TRUE, FALSE)
    out$code(sql_query, TRUE, TRUE)
    out$md("Running query...\n", TRUE, FALSE)
    on.exit(out$close(), add = TRUE, after = FALSE)
  }
  
  tryCatch({
    result <- execute_aact_query(sql_query)
    assign("aact_query_result", result, envir = globalenv())
    
    if (in_shiny()) {
      if (nrow(result) == 0) {
        out$md("**Result:** No data matched your criteria.\n", TRUE, TRUE)
      } else {
        total <- NA_integer_
        need_total <- !is.null(limit_in_sql) && nrow(result) >= limit_in_sql
        if (need_total) {
          try({ total <- count_aact_query_rows(sql_query) }, silent = TRUE)
        }
        
        msg <- if (!is.na(total)) {
          paste0("**Result:** Showing the first ", nrow(result), " of ", total, " matching records.\n")
        } else {
          paste0("**Result:** Showing the first ", nrow(result), " matching records.\n")
        }
        
        if (!is.null(limit_in_sql)) {
          msg <- paste0(msg, sprintf("\nNote: Due to SQL LIMIT %d, showing the first %d rows.\n", 
                                     limit_in_sql, limit_in_sql))
        }
        out$md(msg, TRUE, TRUE)
        render_query_table(result, out)
      }
    }
    
    if (nrow(result) == 0) {
      return("Query executed successfully. No data found matching the criteria.")
    }
    
    lim_txt <- if (!is.null(limit_in_sql)) {
      paste0(" Note: Showing the first ", limit_in_sql, " rows due to SQL LIMIT.")
    } else ""
    
    total <- NA_integer_
    need_total <- !is.null(limit_in_sql) && nrow(result) >= limit_in_sql
    if (need_total) {
      try({ total <- count_aact_query_rows(sql_query) }, silent = TRUE)
    }
    
    if (!is.na(total)) {
      return(paste0("Query executed successfully.", lim_txt, " Showing the first ", 
                   nrow(result), " of ", total, " matching records."))
    } else {
      return(paste0("Query executed successfully.", lim_txt, " Showing the first ", 
                   nrow(result), " matching records."))
    }
  }, error = function(e) {
    error_msg <- paste0("❌ Failed to execute SQL query: ", e$message)
    if (in_shiny()) out$md(error_msg, TRUE, TRUE)
    return(error_msg)
  })
}

render_query_table <- function(df, streamer, max_rows = 20) {
  if (missing(streamer) || is.null(streamer)) return(invisible(NULL))
  rows_to_show <- min(nrow(df), max_rows)
  attrs <- "class=\"data-frame table table-sm table-striped\""
  table_html <- knitr::kable(head(df, rows_to_show), format = "html", table.attr = attrs)
  streamer$md(table_html, TRUE, TRUE)
  if (nrow(df) > rows_to_show) {
    streamer$md(sprintf("... %d additional rows omitted ...\n", nrow(df) - rows_to_show), TRUE, TRUE)
  }
  invisible(NULL)
}

in_shiny <- function() {
  !is.null(shiny::getDefaultReactiveDomain())
}

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
