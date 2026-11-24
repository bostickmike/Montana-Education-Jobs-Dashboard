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

# Stone Child College (Apptegy, chromote-driven -- same platform as
# misc_district_scrapers.R's Wolf Point/Plentywood). Real fixture:
# document.body.innerText captured via a live chromote session 2026-08-07
# (a plain httr2 request gets only a Fastly JS bot-challenge shell).

test_that("parse_stonechild_postings extracts all 5 real postings, excluding the RFP section and application link", {
  text <- paste(readLines(test_path("fixtures", "apptegy_stonechild_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_stonechild_postings(text, "https://www.stonechild.edu/page/employment-rfps")

  expect_equal(nrow(result), 5)
  expect_setequal(result$Title, c(
    "Liberal Arts Instructor", "Information Systems Instructor",
    "NYCP (Native Youth Community Project) School Liaison",
    "SCC Daycare Supervisor", "H1 B Hiring Notification"
  ))
  # Regression: "Open Bids/Requests for Proposals (RFP)" and "Grant
  # Writing Service" are a genuinely different content type (RFPs, not
  # jobs) further down the same page -- must not be swept in.
  expect_false(any(grepl("RFP|Grant Writing", result$Title)))
  expect_true(all(result$Location == "Box Elder"))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_stonechild_postings returns zero rows (not an error) when there's no Current Job Openings section", {
  result <- parse_stonechild_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_stonechild_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_stonechild_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- list(
    Page = list(
      navigate = function(url) invisible(NULL),
      loadEventFired = function(wait_ = TRUE, timeout_ = 30) invisible(NULL)
    ),
    Runtime = list(
      evaluate = function(expr) list(result = list(value = text))
    )
  )

  result <- fetch_stonechild_postings(session)

  expect_equal(nrow(result), 5)
})

# Real fixture captured 2026-08-07 from https://www.ancollege.edu/careers.

test_that("parse_ancollege_postings pairs each real title with the 'here' link right after it", {
  html <- paste(readLines(test_path("fixtures", "ancollege_careers.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_ancollege_postings(html)

  expect_equal(nrow(result), 11)
  expect_true("CIS Assistant" %in% result$Title)
  expect_true("Traditional Ecological Knowledge (TEK) Education and Youth Development Coordinator" %in% result$Title)
  expect_true(all(result$Location == "Harlem"))
  expect_true(all(is.na(result$Posted_Date)))

  cis <- result[result$Title == "CIS Assistant", ]
  expect_equal(cis$Link, "https://www.ancollege.edu/_files/ugd/8f3705_0f4ab04d2b464123a8b3972d9bde23a4.pdf")

  # Regression: the 3 unrelated intro links (Campus Safety/Clery Act,
  # Catalog, the blank Application form) must not be misread as titles --
  # none of them is immediately followed by a "here" link.
  expect_false(any(result$Title %in% c("Campus Safety/Clery Act", "Catalog", "Application")))
})

test_that("parse_ancollege_postings returns zero rows (not an error) when there are no postings", {
  result <- parse_ancollege_postings("<html><body><p>no openings</p></body></html>")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_ancollege_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "ancollege_careers.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_ancollege_postings()

  expect_equal(nrow(result), 11)
})

# Real fixture captured 2026-08-07 from
# https://www.cdkc.edu/faculty-staff/employment/ -- as of that date the
# page's one real File block is a Trustee board-seat application, not a
# job posting, so this fixture proves the exclusion filter, not real
# postings extraction (see the synthetic test below for that).

test_that("parse_cdkc_postings excludes the real Trustee board-seat notice, not a job posting", {
  html <- paste(readLines(test_path("fixtures", "cdkc_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_cdkc_postings(html)

  expect_equal(nrow(result), 0)
})

test_that("parse_cdkc_postings extracts a real job posting once one exists, alongside an excluded Trustee notice", {
  html <- '
    <html><body>
      <div class="wp-block-file">
        <a href="https://www.cdkc.edu/wp-content/uploads/Adjunct-Instructor.pdf">Adjunct Instructor - Mathematics</a>
        <a href="https://www.cdkc.edu/wp-content/uploads/Adjunct-Instructor.pdf" class="wp-block-file__button">Download</a>
      </div>
      <div class="wp-block-file">
        <a href="https://www.cdkc.edu/wp-content/uploads/Birney-Trustee-App.pdf">Birney Trustee App 08 2026</a>
        <a href="https://www.cdkc.edu/wp-content/uploads/Birney-Trustee-App.pdf" class="wp-block-file__button">Download</a>
      </div>
    </body></html>
  '

  result <- parse_cdkc_postings(html)

  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "Adjunct Instructor - Mathematics")
  expect_equal(result$Location, "Lame Deer")
  expect_true(is.na(result$Posted_Date))
  expect_equal(result$Link, "https://www.cdkc.edu/wp-content/uploads/Adjunct-Instructor.pdf")
})

test_that("parse_cdkc_postings returns zero rows (not an error) when there are no File blocks", {
  result <- parse_cdkc_postings("<html><body><p>no openings</p></body></html>")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_cdkc_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "cdkc_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_cdkc_postings()

  expect_equal(nrow(result), 0)
})

# 2026-11-22 capture: two File blocks titled by file name. "Birney Vacancy Open Until Filled" is a Board of
# Trustees seat (its document says so, its name doesn't); "HR Job Posting 9 2026" is the Human Resources Manager job.
test_that("parse_cdkc_postings reads the 2026-11-22 page's two File blocks", {
  html <- paste(readLines(test_path("fixtures", "cdkc_employment_2026-11-22.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  result <- parse_cdkc_postings(html)
  expect_equal(result$Title, c("Birney Vacancy Open Until Filled", "HR Job Posting 9 2026"))
  expect_equal(result$Link, c("https://www.cdkc.edu/wp-content/uploads/Birney-Vacancy-Open-Until-Filled.docx",
                              "https://www.cdkc.edu/wp-content/uploads/HR-Job-Posting-9-2026.docx"))
})

test_that("refine_cdkc_postings drops a trustee vacancy by its text and titles a job from its document", {
  html <- paste(readLines(test_path("fixtures", "cdkc_employment_2026-11-22.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  rows <- parse_cdkc_postings(html)
  birney <- paste(readLines(test_path("fixtures", "cdkc_birney_vacancy_2026-11-22.txt"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  hr_xml <- paste(readLines(unz(test_path("fixtures", "cdkc_hr_job_posting_2026-11-22.docx"), "word/document.xml"),
                            warn = FALSE, encoding = "UTF-8"), collapse = "")
  result <- refine_cdkc_postings(rows, c(birney, cdkc_docx_xml_text(hr_xml)))
  expect_equal(result$Title, "Human Resources Manager")
  expect_equal(result$Link, "https://www.cdkc.edu/wp-content/uploads/HR-Job-Posting-9-2026.docx")
  # A document that couldn't be read keeps its row and file-name title
  expect_equal(refine_cdkc_postings(rows, c(NA, NA))$Title, rows$Title)
  expect_equal(refine_cdkc_postings(rows, c(birney, "Job Posting: Payroll Clerk\nStatus: Full-Time"))$Title, "Payroll Clerk")
})

test_that("fetch_cdkc_postings reads each linked document (2026-11-22 capture)", {
  page <- readBin(test_path("fixtures", "cdkc_employment_2026-11-22.html"), "raw", 2e5)
  hr <- readBin(test_path("fixtures", "cdkc_hr_job_posting_2026-11-22.docx"), "raw", 1e6)
  # A one-paragraph .docx saying "Board of Trustee's Vacancy Announcement" stands in for the 910 KB Birney file
  birney_docx <- local({
    d <- withr::local_tempdir(); dir.create(file.path(d, "word"))
    writeLines('<w:document><w:body><w:p><w:r><w:t>CDKC Board of Trustee&#8217;s Vacancy Announcement</w:t></w:r></w:p></w:body></w:document>',
               file.path(d, "word", "document.xml"))
    z <- tempfile(fileext = ".docx"); withr::with_dir(d, utils::zip(z, "word/document.xml", flags = "-q")); readBin(z, "raw", 1e5)
  })
  httr2::local_mocked_responses(function(req) {
    body <- if (grepl("Birney", req$url)) birney_docx else if (grepl("HR-Job", req$url)) hr else page
    httr2::response(200, body = body)
  })
  result <- fetch_cdkc_postings()
  expect_equal(result$Title, "Human Resources Manager")
  expect_equal(result$Location, "Lame Deer")
})
