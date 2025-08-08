# Clinical Trials Data Analysis Bot

A minimal Shiny app to search, analyze, and visualize ClinicalTrials.gov data via the AACT PostgreSQL database. Natural‑language requests are turned into SQL/R, and results are streamed back with optional ggplot2 charts. LLM priority: Azure OpenAI → AWS Bedrock (Claude) → Gemini.

## Requirements

- R (latest stable) and internet access to AACT
- A `.env` file for database credentials (and optional LLM keys)
- R packages (install once):

```r
install.packages(c(
    "shiny", "bslib", "shinychat", "ellmer",
    "DBI", "RPostgres",
    "tidyverse", "ggplot2",
    "promises", "coro", "evaluate",
    "jsonlite", "base64enc", "R6", "whisker",
    "withr", "here", "fastmap", "knitr"
))
```

## Environment variables

Place these in `.env` at the project root:

```env
# AACT database
AACT_HOST=your_aact_host
AACT_PORT=5432
AACT_DATABASE=aact
AACT_USERNAME=your_username
AACT_PASSWORD=your_password

# Azure OpenAI (preferred)
AZURE_OPENAI_ENDPOINT=https://your-resource-name.openai.azure.com
AZURE_OPENAI_API_KEY=your_azure_openai_api_key_here
AZURE_OPENAI_DEPLOYMENT=gpt-4o-mini
AZURE_OPENAI_API_VERSION=2024-06-01

# AWS Bedrock (optional)
BEDROCK_MODEL=anthropic.claude-3-5-sonnet-20240620-v1:0
AWS_PROFILE=default
# Or use standard AWS_* env vars and region

# Gemini (fallback)
GEMINI_API_KEY=your_gemini_api_key_here
```

## Quick start

- RStudio: open the folder, open `ui.R`, click “Run App”.
- R console:

```r
# setwd("C:/Users/you/Desktop/ctgov-bot")
shiny::runApp(".")
```

Notes
- If you use the report tool (create_quarto_report), install Quarto CLI. The app runs fine without it.
- On Windows, both `C:/path/...` and `C:\\path\\...` work.

## Troubleshooting

- Database connection fails: check `.env` (host, user, password) and network access to AACT.
- LLM errors or no responses: verify Azure OpenAI (preferred) or set Bedrock/Gemini keys.
