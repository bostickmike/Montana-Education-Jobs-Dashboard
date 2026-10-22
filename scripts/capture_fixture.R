#!/usr/bin/env Rscript
# scripts/capture_fixture.R
# Fetches live HTML from a URL, automatically sanitizes any sensitive API keys
# (such as Google Maps/Client API keys "AIza..."), and saves the fixture to
# tests/testthat/fixtures/<slug>_jobs.html.
#
# Usage:
#   Rscript scripts/capture_fixture.R --url "<URL>" --slug "<slug>"
#   Rscript scripts/capture_fixture.R "<URL>" "<slug>"

suppressMessages({
  library(httr2)
  library(here)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  cat("Usage:\n")
  cat("  Rscript scripts/capture_fixture.R --url <URL> --slug <slug>\n")
  cat("  Rscript scripts/capture_fixture.R <URL> <slug>\n")
  quit(status = 1)
}

url <- NULL
slug <- NULL

if ("--url" %in% args) {
  idx <- which(args == "--url")
  if (length(args) >= idx + 1) url <- args[idx + 1]
}
if ("--slug" %in% args) {
  idx <- which(args == "--slug")
  if (length(args) >= idx + 1) slug <- args[idx + 1]
}

if (is.null(url) || is.null(slug)) {
  # Positional fallback
  positional <- args[!startsWith(args, "--")]
  if (length(positional) >= 2) {
    url <- positional[1]
    slug <- positional[2]
  }
}

if (is.null(url) || is.null(slug) || !nzchar(url) || !nzchar(slug)) {
  stop("Both --url and --slug must be specified.")
}

slug <- tolower(gsub("[^a-zA-Z0-9_-]", "", slug))
out_file <- here::here("tests", "testthat", "fixtures", paste0(slug, "_jobs.html"))

cat(sprintf("Fetching live HTML from: %s\n", url))
req <- request(url) %>%
  req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
  req_timeout(25) %>%
  req_retry(max_tries = 3, backoff = ~ 2)

resp <- req_perform(req)
status <- resp_status(resp)
cat(sprintf("HTTP Status: %d\n", status))

if (status >= 400) {
  stop(sprintf("Failed to fetch URL. HTTP status: %d", status))
}

body <- resp_body_string(resp)

# Secret sanitization: Redact any AIza... Google API keys
google_keys <- unique(unlist(regmatches(body, gregexpr("AIza[0-9A-Za-z_-]{35}", body))))
redacted_count <- length(google_keys)

if (redacted_count > 0) {
  for (i in seq_along(google_keys)) {
    replacement <- sprintf("REDACTED_API_KEY_GOOGLE_CLIENT_TOKEN_%02d", i)
    body <- gsub(google_keys[i], replacement, body, fixed = TRUE)
  }
  cat(sprintf("[SECURITY] Redacted %d Google client token(s) from fixture.\n", redacted_count))
}

writeLines(body, out_file, useBytes = TRUE)
file_size <- file.info(out_file)$size
cat(sprintf("Saved %d bytes to fixture: %s\n", file_size, out_file))
