# Extracted from test-drift-check.R:144

# prequel ----------------------------------------------------------------------
lonerock_capture <- function() {
  paste(readLines(test_path("fixtures", "drift_autofix_lonerock_innertext_2026-09-30.txt"),
                  warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}
scraper_source_lines <- function() {
  unlist(lapply(here::here(SCRAPER_FILES), readLines, warn = FALSE))
}
lonerock_row <- function() {
  data.frame(name = "Lone Rock School District", type = "K-12", mean_count = 1, count = 0,
             url = "https://www.lonerockschool.org/page/employment",
             llm_titles = "Special Education Paraprofessional | Bus Driver and Maintenance Director",
             stringsAsFactors = FALSE)
}

# test -------------------------------------------------------------------------
row <- data.frame(name = "Hinsdale Public Schools", type = "K-12", mean_count = 3, count = 0,
                    url = "https://hinsdale.k12.mt.us/District/1557-Untitled.html",
                    llm_titles = NA_character_, stringsAsFactors = FALSE)
call <- resolve_scraper_call(row$name)
ev <- gather_autofix_evidence(call, row$name, "Route Bus Drivers\nDaycare Manager", repo_root = here::here())
expect_false(ev$inner_text)
expect_equal(ev$diff, character(0))
expect_true(length(ev$fixtures) > 0)
body <- paste(build_autofix_issue_body(row, call, evidence = ev), collapse = "\n")
expect_match(body, "`fetch_hinsdale_postings()`", fixed = TRUE)
