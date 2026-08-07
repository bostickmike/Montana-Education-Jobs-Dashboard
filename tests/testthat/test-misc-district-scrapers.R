# Real fixture captured 2026-08-07 from
# https://www.livingston.k12.mt.us/apps/pages/index.jsp?uREC_ID=2055955&type=d&pREC_ID=2121638.

test_that("parse_livingston_postings extracts the 20 real postings, excluding boilerplate forms/documents", {
  html <- paste(readLines(test_path("fixtures", "livingston_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_livingston_postings(html, "https://www.livingston.k12.mt.us/apps/pages/index.jsp?uREC_ID=2055955&type=d&pREC_ID=2121638")

  expect_equal(nrow(result), 20)
  expect_true("PHS Custodian 2026 (2)" %in% result$Title)
  # Regression: the "OTHER DISTRICT POSTINGS" section genuinely mixes one
  # real-postings block with a second, boilerplate-forms block under the
  # SAME header -- title-pattern filtering (not section-heading scoping)
  # is what has to catch these.
  expect_false(any(result$Title %in% c(
    "Administrator Application", "Certified Staff Application",
    "classified employee application (Classified, Coaches, Substitutes)",
    "MT W-4 2026", "Fed W-4 2026", "I-9 2026",
    "LEA Professional Agreement 2024-2026", "LCEA CBA 2024-2026", "LCEA CBA 2026 2028"
  )))
})

test_that("parse_livingston_postings uses the preceding school-building header as Location", {
  html <- paste(readLines(test_path("fixtures", "livingston_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_livingston_postings(html, "https://www.livingston.k12.mt.us/apps/pages/index.jsp?uREC_ID=2055955&type=d&pREC_ID=2121638")

  phs <- result[result$Title == "PHS Custodian 2026 (2)", ]
  expect_equal(phs$Location, "PARK HIGH SCHOOL")
  sgms <- result[result$Title == "SGMS Volleyball Coach 26 27", ]
  expect_equal(sgms$Location, "SLEEPING GIANT MIDDLE SCHOOL")
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_livingston_postings returns zero rows (not an error) when there are no real postings", {
  result <- parse_livingston_postings("<html><body><p>no openings</p></body></html>", "https://www.livingston.k12.mt.us/employment")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_livingston_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "livingston_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_livingston_postings()

  expect_equal(nrow(result), 20)
})

# Real fixtures captured 2026-08-07 from lgschools.org's Employment page
# (uREC_ID=373420) across its 3 real tabs.

test_that("parse_lodgegrass_postings dedupes a real content-authoring duplicate and excludes the Apply Now CTA (Certified tab)", {
  html <- paste(readLines(test_path("fixtures", "lodgegrass_certified.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_lodgegrass_postings(html, "Certified", "https://www.lgschools.org/apps/pages/index.jsp?uREC_ID=373420&type=d")

  expect_equal(nrow(result), 11)
  expect_true("Elementary Principal k-6" %in% result$Title)
  # "Agriculture Education HS 7-12" and 5 others are genuinely pasted
  # twice in the raw page -- must appear exactly once after dedup.
  expect_equal(sum(result$Title == "Agriculture Education HS 7-12"), 1)
  expect_false("Apply Now – Certified Educator Application" %in% result$Title)
  expect_true(all(result$Location == "Certified"))
})

test_that("parse_lodgegrass_postings extracts the 4 real Classified postings", {
  html <- paste(readLines(test_path("fixtures", "lodgegrass_classified.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_lodgegrass_postings(html, "Classified", "url")

  expect_equal(nrow(result), 4)
  expect_true("Athletic Director" %in% result$Title)
  expect_false("Apply Now – Classified Application" %in% result$Title)
})

test_that("parse_lodgegrass_postings returns zero rows for a genuinely empty tab (Coach, no current openings)", {
  html <- paste(readLines(test_path("fixtures", "lodgegrass_coach.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_lodgegrass_postings(html, "Coach", "url")

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_lodgegrass_postings fetches all 3 tabs and combines them", {
  certified <- paste(readLines(test_path("fixtures", "lodgegrass_certified.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  classified <- paste(readLines(test_path("fixtures", "lodgegrass_classified.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  coach <- paste(readLines(test_path("fixtures", "lodgegrass_coach.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  httr2::local_mocked_responses(list(
    httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(certified)),
    httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(classified)),
    httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(coach))
  ))

  result <- fetch_lodgegrass_postings()

  expect_equal(nrow(result), 15)
  expect_setequal(unique(result$Location), c("Certified", "Classified"))
})
