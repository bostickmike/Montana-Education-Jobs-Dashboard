# Real fixture captured 2026-08-07 from https://www.milescc.edu/employment/.

test_that("parse_miles_cc_postings extracts exactly the 6 real job titles, excluding boilerplate labels", {
  html <- paste(readLines(test_path("fixtures", "miles_cc_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_miles_cc_postings(html, "https://www.milescc.edu/employment/")

  expect_equal(nrow(result), 6)
  expect_setequal(result$Title, c(
    "Dining Services Assistant",
    "Learning Center Instructor",
    "Library Associate",
    "Director of Institutional Advancement",
    "Part-Time Clinical Resource Registered Nurse (CRRN)",
    "Adjunct Faculty Opportunities"
  ))
  # Regression: repeating section labels like "Qualifications:" and
  # "Application Process:" must never be mistaken for a job title.
  expect_false(any(result$Title %in% c("Qualifications", "Application Process", "Preferred", "Work Schedule")))
})

test_that("parse_miles_cc_postings uses the shared employment page URL and fixed campus city for every row", {
  html <- paste(readLines(test_path("fixtures", "miles_cc_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_miles_cc_postings(html, "https://www.milescc.edu/employment/")

  expect_true(all(result$Link == "https://www.milescc.edu/employment/"))
  expect_true(all(result$Location == "Miles City"))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_miles_cc_postings returns zero rows (not an error) when there are no real titles", {
  html <- "<html><body><p><strong>Qualifications:</strong> none listed</p></body></html>"
  result <- parse_miles_cc_postings(html, "https://www.milescc.edu/employment/")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_miles_cc_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "miles_cc_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_miles_cc_postings()

  expect_equal(nrow(result), 6)
})
