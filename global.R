# Load required libraries
library(tidyverse)
library(bslib)
library(ellmer)
library(shinychat)
library(htmltools)
library(coro)
library(promises)
library(evaluate)
library(base64enc)
library(jsonlite)
library(R6)
library(whisker)
library(withr)
library(here)
library(tools)
library(utils)
library(DBI)
library(RPostgres)

# Source required functions
source("functions/chat_bot.R")
source("functions/core.R")
source("functions/prompt.R")
source("functions/utilities.R")
source("functions/database.R")

# Define HTML dependencies
html_deps <- function() {
  htmltools::htmlDependency(
    "databot",
    "0.1.0",
    src = "inst/www",
    stylesheet = "style.css"
  )
}

# Global database connection (shared across sessions)
globals <- new.env(parent = emptyenv())
globals$aact_connection <- NULL
globals$aact_connected <- FALSE

# Session-specific storage (accessed via getDefaultReactiveDomain)
get_session_storage <- function() {
  session <- shiny::getDefaultReactiveDomain()
  if (is.null(session)) {
    stop("No active Shiny session found")
  }
  if (is.null(session$userData$storage)) {
    session$userData$storage <- list(
      pending_output = fastmap::fastqueue(),
      last_chat = NULL
    )
  }
  session$userData$storage
}

# Helper functions that work across sessions
save_output_chunk <- function(chunk) {
  storage <- get_session_storage()
  storage$pending_output$add(chunk)
  invisible()
}

take_pending_output <- function() {
  storage <- get_session_storage()
  chunks <- unlist(storage$pending_output$as_list())
  storage$pending_output$reset()
  paste(collapse = "", chunks)
}
