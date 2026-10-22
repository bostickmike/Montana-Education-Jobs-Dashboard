#!/usr/bin/env Rscript
# scripts/verify_batch.R
# One-shot test and integrity verification runner for new district additions.
# Runs all coupled test suites and prints a concise pass/fail summary.
#
# Usage:
#   Rscript scripts/verify_batch.R
#   Rscript scripts/verify_batch.R --filter "<pattern>"

suppressMessages({
  library(testthat)
  library(here)
})

args <- commandArgs(trailingOnly = TRUE)
filter_pattern <- NULL
if ("--filter" %in% args) {
  idx <- which(args == "--filter")
  if (length(args) >= idx + 1) filter_pattern <- args[idx + 1]
}

suites <- c(
  "test-copilot-allowlist.R",
  "test-salary-scrapers.R",
  "test-schema-check.R",
  "test-data-integrity.R",
  "test-opi-direct-deduplication.R",
  "test-misc-district-scrapers.R"
)

cat("====================================================\n")
cat("       MONTANA JOBS DASH: BATCH VERIFICATION       \n")
cat("====================================================\n\n")

results <- list()
any_failed <- FALSE

for (s in suites) {
  path <- here::here("tests", "testthat", s)
  cat(sprintf("[TEST] Running %s ...\n", s))

  out <- tryCatch({
    if (!is.null(filter_pattern) && s == "test-misc-district-scrapers.R") {
      lines <- readLines(path, warn = FALSE)
      parsed <- parse(text = lines)
      matched_lines <- c("library(testthat)", "source(here::here(\"misc_district_scrapers.R\"))")
      for (i in seq_along(parsed)) {
        e <- parsed[[i]]
        if (is.call(e) && identical(as.character(e[[1]]), "test_that")) {
          desc_txt <- as.character(e[[2]])
          if (grepl(filter_pattern, desc_txt, ignore.case = TRUE)) {
            matched_lines <- c(matched_lines, deparse(e), "")
          }
        }
      }
      temp_path <- here::here("tests", "testthat", "_temp_verify_batch.R")
      writeLines(matched_lines, temp_path)
      res_out <- testthat::test_file(temp_path, stop_on_failure = FALSE)
      unlink(temp_path)
      res_out
    } else {
      testthat::test_file(path, stop_on_failure = FALSE)
    }
  }, error = function(e) {
    cat(sprintf("  ERROR during execution: %s\n", e$message))
    return(NULL)
  })

  if (is.null(out)) {
    results[[s]] <- list(passed = FALSE, failed = 1, total = 1)
    any_failed <- TRUE
  } else {
    df <- as.data.frame(out)
    failed_count <- sum(df$failed) + sum(df$error)
    passed_count <- sum(df$passed)
    total_count <- nrow(df)

    if (failed_count > 0) {
      any_failed <- TRUE
      cat(sprintf("  FAIL: %d failure(s) in %s\n", failed_count, s))
    } else {
      cat(sprintf("  PASS: All %d test(s) passed.\n", total_count))
    }
    results[[s]] <- list(passed = (failed_count == 0), failed = failed_count, total = total_count)
  }
}

cat("\n====================================================\n")
cat("                 SUMMARY OF RESULTS                 \n")
cat("====================================================\n")
for (s in suites) {
  res <- results[[s]]
  status_str <- if (res$passed) "PASS" else "FAIL"
  cat(sprintf("%-32s : [%s] (%d tests)\n", s, status_str, res$total))
}

# Check git status for forbidden files
forbidden_files <- c(
  ".github/scripts/file_autofix_issues.R",
  ".github/workflows/weekly-scrape.yml",
  ".gitignore",
  "drift_check.R",
  "tests/testthat/test-drift-check.R",
  ".claude",
  ".github/workflows/claude-autofix.yml"
)

git_st <- tryCatch({
  system("git status --porcelain", intern = TRUE)
}, error = function(e) character(0))

staged_forbidden <- character(0)
for (f in forbidden_files) {
  for (line in git_st) {
    if (grepl(paste0("^[AMRD].*", gsub("\\.", "\\\\.", f)), line)) {
      staged_forbidden <- c(staged_forbidden, f)
    }
  }
}

if (length(staged_forbidden) > 0) {
  cat("\n[ALERT] FORBIDDEN EXPERIMENT FILES STAGED IN GIT:\n")
  for (f in staged_forbidden) {
    cat(sprintf("  ! %s\n", f))
  }
  cat("DO NOT COMMIT THESE FILES. Unstage them with `git reset HEAD <file>`\n")
  any_failed <- TRUE
}

cat("====================================================\n")
if (any_failed) {
  cat("[RESULT] FAILED: One or more test suites failed or forbidden files staged.\n")
  quit(status = 1)
} else {
  cat("[RESULT] SUCCESS: All verification checks passed cleanly!\n")
  quit(status = 0)
}
