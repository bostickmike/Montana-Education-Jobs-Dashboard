# CyberSchool (IES) districts read through edjobs::fetch_cyberschool_postings()
# (edjobs 0.17.0, 2026-11-14): each registry row, with its own Job_Link and
# City, against this district's captured page. The routine's own tests live in
# edjobs; these check this state's registry rows and the Rmd block's inputs.
# Test titles name the parser so the auto-fix issue finds these fixtures.

cs_registry <- function() {
  reg <- read.csv(test_path("..", "..", "k12_district_registry.csv"), stringsAsFactors = FALSE)
  reg[reg$Platform == "CyberSchool", ]
}
cs_row <- function(district) {
  r <- cs_registry()
  r[r$District == district, ]
}
cs_parse <- function(fixture, district) {
  row <- cs_row(district)
  expect_equal(nrow(row), 1)
  html <- paste(readLines(fixture, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  parse_cyberschool_postings(html, row$Job_Link, row$City)
}

test_that("the CyberSchool registry rows are the three migrated districts, each with a spec", {
  expect_setequal(cs_registry()$District, c("Highwood Public Schools", "Vaughn Elementary School District #74",
                                            "Power Public Schools"))
  for (d in cs_registry()$District) {
    call <- edjobs::resolve_scraper_call(d)
    expect_equal(call$fn, "fetch_cyberschool_postings")
  }
})

test_that("parse_cyberschool_postings: Highwood Public Schools", {
  r <- cs_parse(test_path("fixtures", "highwood_cyberschool_2026-10-21.html"), "Highwood Public Schools")
  expect_equal(r$Title, c("Route or Substitute Expedition Driver", "Route, Activity or Substitute Bus Drivers",
                          "Janitorial", "Substitute Teachers"))
  expect_true(all(r$Location == "Highwood"))
  expect_equal(r$Posted_Date, c("2026-08-14", "2026-08-14", "2026-04-23", "2025-08-18"))
})

test_that("parse_cyberschool_postings: Power Public Schools", {
  r <- cs_parse(test_path("fixtures", "power_jobs.html"), "Power Public Schools")
  expect_setequal(r$Title, c("Substitute Teachers", "Substitute After-School Custodians", "Substitute Kitchen Aides"))
  expect_true(all(r$Location == "Power"))
  expect_true(all(grepl("^https://power\\.k12\\.mt\\.us/District/Jobs/[0-9]+-", r$Link)))
})

test_that("parse_cyberschool_postings: Vaughn Elementary, before and after its move to IES's newer platform", {
  old <- cs_parse(test_path("fixtures", "vaughn_jobs.html"), "Vaughn Elementary School District #74")
  new <- cs_parse(test_path("fixtures", "vaughn_ies_jobs_2026-11-14.html"), "Vaughn Elementary School District #74")
  expect_equal(old$Title, "Substitutes Needed")
  expect_equal(new$Title, "Substitutes Needed")
  expect_equal(new$Posted_Date, old$Posted_Date)
  expect_equal(new$Link, "https://vaughn.l.iescentral.com/jobs/substitutes-needed")
  expect_true(all(c(old$Location, new$Location) == "Vaughn"))
})

# Platform "CyberSchoolText" (edjobs 0.24.0, 2026-11-14; claude-notes/2026-11-14_mt-leftovers/): the whole list
# written as text in one item, read with mode "text". Expected titles are the old parsers' titles on the same pages.
cst_parse <- function(fixture, district) {
  reg <- read.csv(test_path("..", "..", "k12_district_registry.csv"), stringsAsFactors = FALSE)
  row <- reg[reg$District == district, ]
  expect_equal(nrow(row), 1)
  expect_equal(row$Platform, "CyberSchoolText")
  rules <- read_k12_list_rules(test_path("..", "..", "k12_list_rules.csv"))
  html <- paste(readLines(fixture, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  r <- parse_cyberschool_postings(html, row$Job_Link, row$City, "text", k12_list_rule(rules, district, "List_Start"),
                                  k12_list_rule(rules, district, "List_Stop"), k12_list_rule(rules, district, "Skip_Section"))
  expect_true(all(r$Location == row$City))
  r
}

test_that("the CyberSchoolText rows resolve to the routine in mode text", {
  for (d in c("Nashua Public Schools", "Frazer Public Schools", "Lavina Public Schools", "Hinsdale Public Schools")) {
    call <- edjobs::resolve_scraper_call(d)
    expect_equal(call$fn, "fetch_cyberschool_postings")
    expect_equal(call$args[[3]], "text")
  }
})

test_that("parse_cyberschool_postings (text): Nashua Public Schools", {
  r <- cst_parse(test_path("fixtures", "nashua_jobs_2026-10-20.html"), "Nashua Public Schools")
  expect_equal(r$Title, c("Part-Time Custodian", "K-12 Librarian (full or part-time)", "Music (full or part-time)",
                          "Special Education", "Concessions", "Substitute Teacher",
                          "Substitute Bus Driver/Activity Bus Driver"))
})

test_that("parse_cyberschool_postings (text): Frazer Public Schools", {
  r <- cst_parse(test_path("fixtures", "frazer_cyberschool_2026-10-21.html"), "Frazer Public Schools")
  expect_equal(length(r$Title), 26)
  expect_true(all(c("Family and Consumer Sciences", "Business Education", "World Languages: Nakoda & Other",
                    "Business Manager/Clerk", "Route Bus Driver") %in% r$Title))
})

test_that("parse_cyberschool_postings (text): Lavina Public Schools", {
  r <- cst_parse(test_path("fixtures", "lavina_jobs.html"), "Lavina Public Schools")
  expect_equal(r$Title, c("Junior High Assistant Volleyball Coach", "Junior High Assistant Football Coach"))
})

test_that("parse_cyberschool_postings (text): Hinsdale Public Schools, numbered and unnumbered", {
  r <- cst_parse(test_path("fixtures", "hinsdale_untitled.html"), "Hinsdale Public Schools")
  expect_equal(r$Title, c("Daycare Manager", "Childcare Worker at Little Raiders Daycare", "Route Bus Drivers"))
  # The pay footnote and the superintendent's contact block are not postings
  r2 <- cst_parse(test_path("fixtures", "hinsdale_untitled_2026-09-22.html"), "Hinsdale Public Schools")
  expect_equal(r2$Title, "Route Bus Drivers")
})
