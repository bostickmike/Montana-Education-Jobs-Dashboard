# Google Doc job lists read through edjobs::fetch_googledoc_postings() (edjobs 0.24.0, 2026-11-14;
# claude-notes/2026-11-14_mt-leftovers/README.md): each registry row, with its Platform_Key (doc ids), City, Job_Link and
# registry list rules, against the district's captured doc. Expected titles are the old scrapers' titles (Victor's
# "Substitute" now "Substitutes"; Bainville's "Paraprofessional- small intervention group" now "Paraprofessional").
# Test titles name the parser so the auto-fix issue finds these fixtures.

gd_parse <- function(district, texts) {
  reg <- read.csv(test_path("..", "..", "k12_district_registry.csv"), stringsAsFactors = FALSE)
  row <- reg[reg$District == district, ]
  expect_equal(nrow(row), 1)
  expect_equal(row$Platform, "GoogleDoc")
  expect_true(nzchar(row$Platform_Key))
  rules <- read_k12_list_rules(test_path("..", "..", "k12_district_registry.csv"))
  r <- parse_googledoc_postings(texts, row$City, row$Job_Link, k12_list_rule(rules, district, "List_Start"),
                                k12_list_rule(rules, district, "List_Stop"), k12_list_rule(rules, district, "List_Skip"))
  expect_true(all(r$Location == row$City))
  expect_true(all(r$Link == row$Job_Link))
  r
}
fx <- function(name) paste(readLines(test_path("fixtures", name), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

test_that("the GoogleDoc rows resolve to the routine with their doc ids", {
  for (d in c("Victor School District", "Superior School District", "Bainville K-12 Schools", "Creston School District")) {
    call <- edjobs::resolve_scraper_call(d)
    expect_equal(call$fn, "fetch_googledoc_postings")
  }
  expect_length(strsplit(edjobs::resolve_scraper_call("Bainville K-12 Schools")$args[[1]], ";", fixed = TRUE)[[1]], 2)
})

test_that("parse_googledoc_postings: Victor School District (an uploaded doc's preview)", {
  r <- gd_parse("Victor School District", googledoc_preview_text(fx("victor_gdoc_2026-10-21.html")))
  expect_equal(r$Title, c("HS/MS Special Education Teacher", "Paraprofessional", "Head High School Track Coach", "Substitutes"))
  expect_true(all(!is.na(r$Posted_Date)))  # the doc's "updated" date, as the old scraper read it
})

test_that("parse_googledoc_postings: Superior School District", {
  r <- gd_parse("Superior School District", googledoc_preview_text(fx("superior_gdoc_2026-10-21.html")))
  expect_equal(r$Title, c("Bus Drivers", "Substitute Teachers", "Paraprofessionals"))
})

test_that("parse_googledoc_postings: Bainville K-12 Schools (two docs)", {
  texts <- strsplit(fx("googledoc_bainville_2026-11-14.txt"), "\n=====\n", fixed = TRUE)[[1]]
  r <- gd_parse("Bainville K-12 Schools", texts)
  expect_equal(r$Title, c("K-12 Art Teacher", "7-12 History", "Elementary Teacher", "Paraprofessional",
                          "Substitute Teachers", "Custodian Subs", "Substitute Bus Drivers"))
})

test_that("parse_googledoc_postings: Creston School District", {
  r <- gd_parse("Creston School District", fx("creston_jobs_doc.txt"))
  expect_equal(r$Title, "Guest Teacher (aka Substitute)")
})
