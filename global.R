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

# Database libraries (install if needed)
if (!require(DBI, quietly = TRUE)) install.packages("DBI")
if (!require(RPostgres, quietly = TRUE)) install.packages("RPostgres")
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

# Global state management
globals <- new.env(parent = emptyenv())
globals$turns <- NULL
globals$ui_messages <- fastmap::fastqueue()
globals$pending_output <- fastmap::fastqueue()
globals$last_chat <- NULL
globals$aact_connection <- NULL
globals$aact_connected <- FALSE

# Reactive value for session management
latest_session <- reactiveVal()

# Helper functions
reset_state <- function() {
  globals$turns <- NULL
  globals$ui_messages$reset()
  globals$pending_output$reset()
  invisible()
}

save_messages <- function(...) {
  for (msg in list(...)) {
    globals$ui_messages$add(msg)
  }
  invisible()
}

save_output_chunk <- function(chunk) {
  globals$pending_output$add(chunk)
  invisible()
}

take_pending_output <- function() {
  chunks <- unlist(globals$pending_output$as_list())
  globals$pending_output$reset()
  paste(collapse = "", chunks)
}

# Stream decorator that saves each chunk to pending_output
save_stream_output <- function() {
  coro::async_generator(function(stream) {
    session <- getDefaultReactiveDomain()
    for (chunk in coro::await_each(stream)) {
      if (session$isClosed()) {
        req(FALSE)
      }
      save_output_chunk(chunk)
      coro::yield(chunk)
    }
  })
}

last_chat <- function() {
  globals$last_chat
}
