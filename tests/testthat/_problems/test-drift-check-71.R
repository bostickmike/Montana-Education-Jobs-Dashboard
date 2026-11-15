# Extracted from test-drift-check.R:71

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
k12 <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
for (i in seq_len(nrow(k12))) {
    call <- resolve_scraper_call(k12$District[i])
    expect_false(is.null(call), info = k12$Platform[i])
    expect_equal(call$where, "k12_district_registry.csv")
    if (call$map) {
      expect_equal(k12$Platform[i], "ApptegyBespoke", info = k12$District[i])
      expect_true(call$session)
      expect_true(k12$District[i] %in% names(APPTEGY_DISTRICT_SCRAPERS), info = k12$District[i])
    } else {
      expect_true(exists(call$fn, mode = "function"), info = paste(k12$Platform[i], "->", call$fn))
    }
  }
hinsdale <- resolve_scraper_call("Hinsdale Public Schools")
expect_equal(hinsdale[c("fn", "session")], list(fn = "fetch_hinsdale_postings", session = FALSE))
