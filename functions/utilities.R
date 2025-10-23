as_str <- function(..., collapse = "\n", sep = "") {
  lst <- list(...)
  strings <- vapply(lst, paste, character(1), collapse = collapse)
  paste(strings, collapse = sep)
}

rule <- function(...) {
  text <- paste0(..., collapse = "")
  width <- getOption("width") - nchar(text) - 3
  paste0("- ", text, " ", strrep("-", width))
}

MarkdownStreamer <- R6::R6Class("MarkdownStreamer",
  public = list(
    initialize = function(callback) {
      if (!is.function(callback)) {
        stop("`callback` must be a function")
      }
      if (length(formals(callback)) != 1) {
        stop("`callback` must accept exactly one argument")
      }
      private$callback <- callback
      private$in_code_block <- FALSE
      private$last_ends_with_newline <- TRUE
      private$empty <- TRUE
    },
    
    md = function(text, ensure_newline_before = FALSE, ensure_newline_after = FALSE) {
      if (!is.character(text)) stop("`text` must be a character vector")
      if (length(text) == 0 || all(text == "")) return(invisible(self))
      if (length(text) > 1) text <- paste(text, collapse = "\n")
      if (private$in_code_block) private$close_code_block()
      private$send(text, ensure_newline_before, ensure_newline_after)
      invisible(self)
    },
    
    code = function(text, ensure_newline_before = FALSE, ensure_newline_after = FALSE) {
      if (!is.character(text)) stop("`text` must be a character vector")
      if (length(text) == 0 || all(text == "")) return(invisible(self))
      if (length(text) > 1) text <- paste(text, collapse = "\n")
      
      if (!private$in_code_block) {
        private$send(as_str("\n``````\n"), TRUE, FALSE)
        private$in_code_block <- TRUE
      }
      
      private$send(text, ensure_newline_before, ensure_newline_after)
      invisible(self)
    },
    
    close = function() {
      if (private$in_code_block) {
        private$close_code_block()
      }
      invisible(self)
    }
  ),
  
  private = list(
    callback = NULL,
    in_code_block = FALSE,
    last_ends_with_newline = TRUE,
    empty = TRUE,
    
    send = function(text, ensure_newline_before = FALSE, ensure_newline_after = FALSE) {
      text_begins_with_newline <- grepl("^\n", text)
      
      if (ensure_newline_before && !private$last_ends_with_newline && !text_begins_with_newline) {
        private$callback("\n")
        private$last_ends_with_newline <- TRUE
      }
      
      private$callback(text)
      private$last_ends_with_newline <- grepl("\n$", text)
      
      if (ensure_newline_after && !private$last_ends_with_newline) {
        private$callback("\n")
        private$last_ends_with_newline <- TRUE
      }
      
      if (private$empty) private$empty <- FALSE
    },
    
    close_code_block = function() {
      private$send("``````\n", TRUE, FALSE)
      private$in_code_block <- FALSE
    }
  )
)

NullStreamer <- R6::R6Class("NullStreamer", public = list(
  md = function(text, ...) invisible(self),
  code = function(text, ...) invisible(self),
  close = function() invisible(self)
))
