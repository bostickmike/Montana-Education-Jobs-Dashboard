# Extracted from test-googledoc-family.R:27

# prequel ----------------------------------------------------------------------
gd_parse <- function(district, texts) {
  reg <- read.csv(test_path("..", "..", "k12_district_registry.csv"), stringsAsFactors = FALSE)
  row <- reg[reg$District == district, ]
  expect_equal(nrow(row), 1)
  expect_equal(row$Platform, "GoogleDoc")
  expect_true(nzchar(row$Slug))
  rules <- read_k12_list_rules(test_path("..", "..", "k12_list_rules.csv"))
  r <- parse_googledoc_postings(texts, row$City, row$Job_Link, k12_list_rule(rules, district, "List_Start"),
                                k12_list_rule(rules, district, "List_Stop"), k12_list_rule(rules, district, "Skip_Section"))
  expect_true(all(r$Location == row$City))
  expect_true(all(r$Link == row$Job_Link))
  r
}
fx <- function(name) paste(readLines(test_path("fixtures", name), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

# test -------------------------------------------------------------------------
for (d in c("Victor School District", "Superior School District", "Bainville K-12 Schools", "Creston School District")) {
    call <- edjobs::resolve_scraper_call(d)
    expect_equal(call$fn, "fetch_googledoc_postings")
  }
expect_length(googledoc_ids(edjobs::resolve_scraper_call("Bainville K-12 Schools")$args[[1]]), 2)
