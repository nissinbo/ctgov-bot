databot_prompt <- function() {
  llms_txt <- if (file.exists(here::here("llms.txt"))) {
    paste(readLines(here::here("llms.txt"), encoding = "UTF-8", warn = FALSE), collapse = "\n")
  } else NULL
  
  template <- databot_prompt_template()
  
  whisker::whisker.render(
    template,
    data = list(
      has_project = TRUE,
      has_llms_txt = !is.null(llms_txt),
      llms_txt = llms_txt
    )
  )
}

databot_prompt_template <- function() {
  paste(
    readLines(file.path("inst", "prompt", "prompt.md"), encoding = "UTF-8", warn = FALSE),
    collapse = "\n"
  )
}
