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

# Real fixture captured 2026-08-07 from
# https://www.dawson.edu/employment-opportunities.html.

test_that("parse_dawson_cc_postings extracts exactly the 7 real postings from labeled Openings sections", {
  html <- paste(readLines(test_path("fixtures", "dawson_cc_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_dawson_cc_postings(html, "https://www.dawson.edu/employment-opportunities.html")

  expect_equal(nrow(result), 7)
  expect_setequal(result$Title, c(
    "Assistant I Track Coach",
    "Faculty - Animal-Agricultural Instructor",
    "Faculty - General Science, Physics, Chemistry",
    "Faculty - Communications",
    "Director of Basic & Continuing Education",
    "Maintenance Technician/Custodian Part-Time",
    "Bus Drivers"
  ))
  # Regression: the page's own boilerplate application-form links (under
  # the unrelated "How to Apply:" heading, same markup/URL pattern as real
  # postings) must never be mistaken for a job title.
  expect_false(any(result$Title %in% c(
    "DCC Employment Application", "Fill out our secure employment application online", "EEO Form"
  )))
})

test_that("parse_dawson_cc_postings resolves relative /file_download/ links to absolute URLs, fixed city, no posted date", {
  html <- paste(readLines(test_path("fixtures", "dawson_cc_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_dawson_cc_postings(html, "https://www.dawson.edu/employment-opportunities.html")

  expect_true(all(grepl("^https://www\\.dawson\\.edu/file_download/", result$Link)))
  expect_true(all(result$Location == "Glendive"))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_dawson_cc_postings returns zero rows (not an error) when no Openings section has any postings", {
  html <- '<html><body><h4>Coach Openings:</h4><h4>How to Apply:</h4></body></html>'
  result <- parse_dawson_cc_postings(html, "https://www.dawson.edu/employment-opportunities.html")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_dawson_cc_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "dawson_cc_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_dawson_cc_postings()

  expect_equal(nrow(result), 7)
})

# Real fixture captured 2026-08-07 from
# https://www.carroll.edu/faculty-staff-positions.

test_that("parse_carroll_college_postings extracts all 16 real accordion job titles", {
  html <- paste(readLines(test_path("fixtures", "carroll_college_positions.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_carroll_college_postings(html, "https://www.carroll.edu/faculty-staff-positions")

  expect_equal(nrow(result), 16)
  expect_true("Library Director" %in% result$Title)
  expect_true(all(result$Location == "Helena"))
  expect_true(all(result$Link == "https://www.carroll.edu/faculty-staff-positions"))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_carroll_college_postings returns zero rows (not an error) when there's no accordion", {
  result <- parse_carroll_college_postings("<html><body><p>no openings</p></body></html>", "https://www.carroll.edu/faculty-staff-positions")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_carroll_college_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "carroll_college_positions.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_carroll_college_postings()

  expect_equal(nrow(result), 16)
})

# Real fixture captured 2026-08-07 from https://rocky.edu/employment.

test_that("parse_rocky_mountain_college_postings extracts the 7 real postings, skipping the empty template loop item", {
  html <- paste(readLines(test_path("fixtures", "rocky_mountain_college_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_rocky_mountain_college_postings(html)

  expect_equal(nrow(result), 7)
  expect_equal(result$Title[1], "Admissions Counselor")
  expect_equal(result$Location[1], "Admissions")
  expect_equal(result$Link[1], "https://rocky.edu/employment/opportunities/admissions-counselor/")
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_rocky_mountain_college_postings returns zero rows (not an error) when there are no loop items", {
  result <- parse_rocky_mountain_college_postings("<html><body><p>no openings</p></body></html>")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_rocky_mountain_college_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "rocky_mountain_college_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_rocky_mountain_college_postings()

  expect_equal(nrow(result), 7)
})
