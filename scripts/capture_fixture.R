#!/usr/bin/env Rscript
# scripts/capture_fixture.R
# Fetches live HTML from a URL, automatically sanitizes any sensitive API keys
# (such as Google Maps/Client API keys "AIza..."), and saves the fixture to
# tests/testthat/fixtures/<slug>_jobs.html.
#
# Usage:
#   Rscript scripts/capture_fixture.R --url "<URL>" --slug "<slug>"
#   Rscript scripts/capture_fixture.R "<URL>" "<slug>"
#   Rscript scripts/capture_fixture.R --apptegy --url "<URL>" --slug "<slug>"
#
# --apptegy: Apptegy sites sit behind a Fastly "Client Challenge" a plain
# request can't pass, so this renders the page in headless Chrome the way the
# pipeline does (navigate, wait for load, 4 s, document.documentElement.outerHTML)
# and saves, from the same render, the two inputs edjobs::fetch_apptegy_postings()
# reads: tests/testthat/fixtures/apptegy_<slug>_rendered_<today>.txt
# (document.body.innerText, mode "text") and apptegy_<slug>_pagedata_<today>.html
# (the HTML with the page-builder data, mode "pagebuilder"): the names
# scripts/scaffold_district.R's apptegy mode looks for. It refuses to save a
# page without the page-builder data (a challenge page or a wrong URL).

suppressMessages({
  library(httr2)
  library(here)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  cat("Usage:\n")
  cat("  Rscript scripts/capture_fixture.R --url <URL> --slug <slug>\n")
  cat("  Rscript scripts/capture_fixture.R <URL> <slug>\n")
  cat("  Rscript scripts/capture_fixture.R --apptegy --url <URL> --slug <slug>\n")
  quit(status = 1)
}
apptegy <- "--apptegy" %in% args
args <- args[args != "--apptegy"]

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

if (apptegy) {
  # The scaffold builds R function names from the slug, so no hyphens here.
  slug <- gsub("-", "", slug)
  out_file <- here::here("tests", "testthat", "fixtures",
                         sprintf("apptegy_%s_pagedata_%s.html", slug, Sys.Date()))
  suppressMessages(library(chromote))
  cat(sprintf("Rendering in headless Chrome: %s\n", url))
  session <- ChromoteSession$new()
  inner_text <- NULL
  body <- tryCatch({
    session$Page$navigate(url)
    session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
    Sys.sleep(4)
    inner_text <- session$Runtime$evaluate("document.body.innerText")$result$value
    session$Runtime$evaluate("document.documentElement.outerHTML")$result$value
  }, finally = session$close())
  if (is.null(body) || !grepl("window.clientWorkStateTemp = JSON.parse(", body, fixed = TRUE)) {
    stop("The rendered page has no Apptegy page-builder data (Fastly challenge, wrong URL, or not Apptegy). Nothing saved.")
  }
  text_file <- sub("_pagedata_(.*)[.]html$", "_rendered_\\1.txt", out_file)
  writeLines(if (is.null(inner_text)) "" else inner_text, text_file, useBytes = TRUE)
  cat(sprintf("Saved the rendered text to fixture: %s\n", text_file))
} else {
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
}

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
