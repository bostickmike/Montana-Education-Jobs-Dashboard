# One-command repro for a single scraper, named by its registry row:
#
#   Rscript scripts/repro_scraper.R "Lone Rock School District"
#   Rscript scripts/repro_scraper.R "Lone Rock School District" --save-text /tmp/lonerock.txt
#
# Prints which fetch_* function the registry row resolves to, its fixtures
# (newest first) and the tests that use them, runs just those tests, then
# runs the scraper against the live site and prints what it found. For
# innerText-based chromote scrapers it also saves the rendered page text
# (--save-text, default /tmp/<fetch_fn>_live.txt) in the exact form a
# fixture takes.
#
# Written for the Copilot coding agent's scraper auto-fix issues, whose
# first real run (issue #7) spent a dozen steps working out how to call
# the scraper and set up Chrome. Uses the same resolve/run path as the
# PR live check (drift_check.R), so "works here" means "works there".

suppressMessages({
  library(httr2); library(rvest); library(dplyr); library(chromote); library(here)
})
setwd(here::here())
source("scrape_helpers.R")
source("direct_api_scrapers.R")
source("misc_district_scrapers.R")
source("misc_college_scrapers.R")
source("drift_check.R")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) stop('usage: Rscript scripts/repro_scraper.R "<registry District/Institution>" [--save-text PATH]')
source_name <- args[1]
save_at <- which(args == "--save-text")
save_path <- if (length(save_at) == 1 && length(args) > save_at) args[save_at + 1] else NULL

k12 <- read.csv("k12_district_registry.csv", stringsAsFactors = FALSE)
he <- read.csv("he_institution_registry.csv", stringsAsFactors = FALSE)
registry_row <- if (source_name %in% k12$District) k12[k12$District == source_name, ][1, ] else
                if (source_name %in% he$Institution) he[he$Institution == source_name, ][1, ] else NULL
if (is.null(registry_row)) stop("No registry row named '", source_name, "' in k12_district_registry.csv or he_institution_registry.csv")

call <- resolve_scraper_call(registry_row)
if (is.null(call)) stop("Platform '", registry_row$Platform, "' has no single-source scraper call (see SCRAPER_CALL_SPECS in drift_check.R)")
evidence <- gather_autofix_evidence(call, NA_character_)
live_url <- c(registry_row$Job_Link, registry_row$Feed_URL)
live_url <- live_url[!is.na(live_url) & nzchar(live_url)][1]

cat("== ", source_name, " ==\n", sep = "")
cat("Platform:     ", registry_row$Platform, "\n")
cat("Entry point:  ", describe_scraper_call(call), "\n")
cat("fetch_* fn:   ", evidence$fetch_fn, "\n")
cat("Parses:       ", if (evidence$inner_text) "document.body.innerText (text fixtures)" else "raw HTML / API response", "\n")
cat("Live URL:     ", live_url, "\n")
cat("Fixtures:     ", if (length(evidence$fixtures)) paste(evidence$fixtures, collapse = ", ") else "(none found)", "\n\n")

# ---- fixture tests --------------------------------------------------------
fns <- c(evidence$fetch_fn, sub("^fetch_", "parse_", evidence$fetch_fn))
for (f in list.files("tests/testthat", pattern = "^test-.*[.]R$", full.names = TRUE)) {
  lines <- readLines(f, warn = FALSE)
  descs <- sub('^\\s*test_that\\("(.*?)",.*$', "\\1", grep("^\\s*test_that\\(", lines, value = TRUE), perl = TRUE)
  descs <- descs[vapply(descs, function(d) any(vapply(fns, grepl, logical(1), x = d, fixed = TRUE)), logical(1))]
  for (d in descs) {
    cat("-- test:", basename(f), "::", d, "\n")
    testthat::test_file(f, desc = d, reporter = "summary")
  }
}

# ---- live run -------------------------------------------------------------
# The Copilot agent's firewall intercepts TLS; headless Chrome rejects its
# certificate unless told not to. Sandbox-only -- never in a scraper.
in_copilot_sandbox <- identical(Sys.getenv("COPILOT_AGENT_FIREWALL_ENABLED"), "true")
if (call$session && in_copilot_sandbox) {
  chromote::set_chrome_args(c(chromote::get_chrome_args(), "--ignore-certificate-errors"))
}

cat("\n-- live run of", describe_scraper_call(call), "\n")
result <- tryCatch(run_scraper_call(call, session_factory = function() ChromoteSession$new()),
                   error = function(e) e)
if (inherits(result, "condition")) {
  cat("ERRORED:", conditionMessage(result), "\n")
} else {
  titles <- if ("Title" %in% names(result)) as.character(result$Title) else character(0)
  cat(length(titles), "posting(s):\n")
  if (length(titles)) cat(paste0("  - ", titles), sep = "\n")
}

if (call$session && evidence$inner_text && !is.na(live_url)) {
  if (is.null(save_path)) save_path <- file.path("/tmp", paste0(evidence$fetch_fn, "_live.txt"))
  s <- ChromoteSession$new()
  text <- tryCatch({
    s$Page$navigate(live_url, wait_ = TRUE)
    s$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
    Sys.sleep(2.5)
    s$Runtime$evaluate("document.body.innerText")$result$value
  }, error = function(e) NA_character_, finally = tryCatch(s$close(), error = function(e) NULL))
  if (length(text) == 1 && !is.na(text)) {
    writeLines(text, save_path, useBytes = TRUE)
    cat("\nRendered page text (", nchar(text), " chars) saved to ", save_path, "\n", sep = "")
  } else {
    cat("\nCouldn't render the page for its text.\n")
  }
  if (in_copilot_sandbox) {
    cat("NOTE: you're behind the Copilot firewall. If this render shows fewer postings than the issue's",
        "'Full page text captured in CI', trust the CI capture: a blocked asset host, not the site, is",
        "the likelier cause. Don't change how the scraper fetches the page to work around it.\n", sep = "\n")
  }
}
