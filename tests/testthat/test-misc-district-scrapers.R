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

# ---------------------------------------------------------------------------
# Apptegy (chromote-driven) -- Wolf Point, Plentywood
# ---------------------------------------------------------------------------

# Real fixtures: document.body.innerText captured via a live chromote
# session 2026-08-07 (a plain httr2 request gets only a Fastly JS
# bot-challenge shell for these two districts, no real content at all).

test_that("parse_wolfpoint_postings extracts all 19 real postings, excluding EAE-filled positions and trailing page content", {
  text <- paste(readLines(test_path("fixtures", "apptegy_wolfpoint_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_wolfpoint_postings(text, "https://www.wolfpointschools.org/page/job-opportunities-1")

  expect_equal(nrow(result), 19)
  expect_true("JH/HS Assistant Principal" %in% result$Title)
  expect_true("HS Football Assistant Coach" %in% result$Title)
  # Regression: "CERTIFIED POSITIONS CURRENTLY FILLED BY EAE'S*:" titles
  # are real people's current assignments, not open postings.
  expect_false(any(result$Title %in% c(
    "Elementary Teachers -Grades Pre K, 2, 6*", "Elementary Librarian*",
    "Elementary Art Teacher*", "Elementary Alternative Learning*"
  )))
  # Regression: real prose after the last real section ("Join the Team"
  # staff-testimonial content, benefits info, application instructions)
  # must not be swept in as if it were a job title.
  expect_false(any(result$Title %in% c("Join the Team", "Certified Benefits", "4-Day School Week")))
  expect_true(all(result$Location == "Wolf Point"))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_wolfpoint_postings returns zero rows (not an error) when there's no JOB OPENINGS section", {
  result <- parse_wolfpoint_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_plentywood_postings extracts all 4 real titles and the real posted date from the same sentence", {
  text <- paste(readLines(test_path("fixtures", "apptegy_plentywood_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_plentywood_postings(text, "https://www.plentywood.k12.mt.us/o/plentywood/page/employment-opportunities")

  expect_equal(nrow(result), 4)
  expect_setequal(result$Title, c("Assistant Cook", "Activities Bus Driver", "Substitute Teachers", "Paraprofessional"))
  expect_true(all(result$Location == "Plentywood"))
  # Real Posted_Date extracted from "(as of July 13,2026)" in the same
  # sentence as the numbered list -- unlike Wolf Point/Stone Child, which
  # have no date signal at all.
  expect_true(all(result$Posted_Date == "2026-07-13"))
})

test_that("parse_plentywood_postings returns zero rows (not an error) when there's no Positions available paragraph", {
  result <- parse_plentywood_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

# Fake chromote session: a plain list standing in for a real
# ChromoteSession$new() -- provides just the $Page$navigate/
# $Page$loadEventFired/$Runtime$evaluate surface fetch_wolfpoint_postings()/
# fetch_plentywood_postings() actually call, returning a fixed innerText
# string regardless of URL. Tests the real fetch_*() function bodies
# (including their real navigate/wait/evaluate call sequence), not a
# mocked replacement of them -- no real browser needed.
fake_chromote_session <- function(rendered_text) {
  list(
    Page = list(
      navigate = function(url) invisible(NULL),
      loadEventFired = function(wait_ = TRUE, timeout_ = 30) invisible(NULL)
    ),
    Runtime = list(
      evaluate = function(expr) list(result = list(value = rendered_text))
    )
  )
}

test_that("fetch_wolfpoint_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_wolfpoint_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_wolfpoint_postings(session)

  expect_equal(nrow(result), 19)
})

test_that("fetch_plentywood_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_plentywood_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_plentywood_postings(session)

  expect_equal(nrow(result), 4)
})

test_that("fetch_apptegy_k12_postings returns an empty frame (not an error) when no session factory is available", {
  result <- fetch_apptegy_k12_postings(chromote_session_factory = NULL)
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link", "District"))
})

test_that("fetch_apptegy_k12_postings shares one session across both districts and tags each row with its real District", {
  wp_text <- paste(readLines(test_path("fixtures", "apptegy_wolfpoint_rendered.txt"), warn = FALSE), collapse = "\n")
  pw_text <- paste(readLines(test_path("fixtures", "apptegy_plentywood_rendered.txt"), warn = FALSE), collapse = "\n")

  # Same fake session serves both districts' fetches, real URL routing
  # comes from each fetch_*_postings()'s own default url= argument -- this
  # fake just returns Wolf Point's text for the Wolf Point call and
  # Plentywood's for the Plentywood call by checking the navigated URL.
  navigated_url <- NULL
  session_factory <- function() {
    list(
      Page = list(
        navigate = function(url) navigated_url <<- url,
        loadEventFired = function(wait_ = TRUE, timeout_ = 30) invisible(NULL)
      ),
      Runtime = list(
        evaluate = function(expr) {
          text <- if (grepl("wolfpoint", navigated_url)) wp_text else pw_text
          list(result = list(value = text))
        }
      ),
      close = function() invisible(NULL)
    )
  }

  result <- fetch_apptegy_k12_postings(chromote_session_factory = session_factory)

  expect_equal(nrow(result), 23)
  expect_equal(sum(result$District == "Wolf Point Public Schools"), 19)
  expect_equal(sum(result$District == "Plentywood Public Schools"), 4)
})
