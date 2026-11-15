# Mock Sys.sleep to no-op so fake-chromote session tests do not sleep 4-5s per scraper:
testthat::local_mocked_bindings(Sys.sleep = function(...) invisible(NULL), .package = "base")

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

# Real fixtures captured 2026-08-16 from broadviewschools.org's 4 real
# posting pages.

test_that("parse_broadview_page returns zero rows for the currently-empty Certified page", {
  html <- paste(readLines(test_path("fixtures", "broadview_certified.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_broadview_page(html, "Certified", "dash", "url")

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_broadview_page extracts the 3 real dash-listed Classified postings", {
  html <- paste(readLines(test_path("fixtures", "broadview_classified.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_broadview_page(html, "Classified", "dash", "url")

  expect_equal(nrow(result), 3)
  expect_setequal(result$Title, c("BUS DRIVERS", "E-Bus Driver to Billings", "Business Manager"))
  expect_true(all(result$Location == "Classified"))
})

test_that("parse_broadview_page extracts the single real Extra Curricular title, not the surrounding prose", {
  html <- paste(readLines(test_path("fixtures", "broadview_extracurricular.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_broadview_page(html, "Extra Curricular", "titleline", "url")

  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "Transportation Director")
})

test_that("parse_broadview_page extracts the 3 real ALL-CAPS Coaching co-op postings, stopping before the contact block", {
  html <- paste(readLines(test_path("fixtures", "broadview_coaching.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_broadview_page(html, "Coaching (Broadview/Lavina Co-op)", "allcaps", "url")

  expect_equal(nrow(result), 3)
  expect_setequal(result$Title, c("JUNIOR HIGH ASSISTANT VOLLEYBALL", "JUNIOR HIGH ASSISTANT FOOTBALL", "CHEERLEADING ADVISOR (HS/JH)"))
  # Regression: the contact block ("Please submit letters of interest to...
  # Chad Fordyce...Broadview Public School...") must not be swept in as if
  # its ALL-CAPS-looking fragments were job titles.
  expect_false(any(grepl("BROADVIEW|LAVINA|SUPERINTENDENT", result$Title, ignore.case = TRUE)))
})

test_that("fetch_broadview_postings fetches all 4 pages and combines them into the real 7 live postings", {
  certified <- paste(readLines(test_path("fixtures", "broadview_certified.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  classified <- paste(readLines(test_path("fixtures", "broadview_classified.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  extracurricular <- paste(readLines(test_path("fixtures", "broadview_extracurricular.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  coaching <- paste(readLines(test_path("fixtures", "broadview_coaching.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  httr2::local_mocked_responses(list(
    httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(certified)),
    httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(classified)),
    httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(extracurricular)),
    httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(coaching))
  ))

  result <- fetch_broadview_postings()

  expect_equal(nrow(result), 7)
  expect_setequal(unique(result$Location), c("Classified", "Extra Curricular", "Coaching (Broadview/Lavina Co-op)"))
})

# Real fixture captured 2026-08-16 from custerschools.org/employment (a
# plain httr2 request -- genuinely Finalsite, not Apptegy like every other
# district in this same batch, no chromote needed).

test_that("parse_custer_postings extracts the 6 real postings from the Job Openings list", {
  html <- paste(readLines(test_path("fixtures", "custer_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_custer_postings(html, "url")

  expect_equal(nrow(result), 6)
  expect_setequal(result$Title, c(
    "Superintendent with Principal Duties", "PE Teaching Position", "Vo-Ag Teaching Position",
    "Music Teaching Position", "Route Bus Drivers (CDL or Non CDL)", "Activity Bus Drivers (CDL or Non CDL)"
  ))
  expect_true(all(result$Location == "Custer"))
})

test_that("parse_custer_postings returns zero rows (not an error) when there's no Job Openings list", {
  result <- parse_custer_postings("<html><body><p>no openings</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_custer_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "custer_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_custer_postings()

  expect_equal(nrow(result), 6)
})

# Real fixture captured 2026-08-16 from scobeyschools.com/employment.html
# (a Weebly site, only reachable over plain http).

test_that("parse_scobey_postings extracts all 13 real postings across 4 real category headers", {
  html <- paste(readLines(test_path("fixtures", "scobey_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_scobey_postings(html, "url")

  expect_equal(nrow(result), 13)
  expect_equal(sum(result$Location == "TEACHING STAFF"), 7)
  expect_equal(sum(result$Location == "SUPPORT TEACHING STAFF"), 2)
  expect_equal(sum(result$Location == "BUS DRIVERS"), 2)
  expect_equal(sum(result$Location == "COACHING STAFF"), 2)
  expect_true("ELEMENTARY TEACHER" %in% result$Title)
  # Regression: every real header/posting line in the raw page carries a
  # leading zero-width space (U+200B) baked into the site's own content --
  # must be stripped, not leak into Title/Location.
  expect_false(any(grepl("​", c(result$Title, result$Location))))
})

test_that("parse_scobey_postings returns zero rows (not an error) when there's no TEACHING STAFF section", {
  result <- parse_scobey_postings("<html><body><p>no openings</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_scobey_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "scobey_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_scobey_postings()

  expect_equal(nrow(result), 13)
})

# ---------------------------------------------------------------------------
# Apptegy (chromote-driven) -- Wolf Point, Plentywood, Conrad, Westby,
# Choteau, Gardiner, Malta, Drummond
# ---------------------------------------------------------------------------

# Real fixtures: document.body.innerText captured via a live chromote
# session 2026-08-07 (a plain httr2 request gets only a Fastly JS
# bot-challenge shell for these two districts, no real content at all).


# Real fixtures captured 2026-08-16: trimmed page-builder JSON payloads
# (Conrad, Gardiner, Drummond) or full rendered pages (Westby, Choteau,
# Malta) from each district's own real Employment page.


# Real fixture captured 2026-08-16 (trimmed page-builder JSON payload) from
# deerlodgeschools.org/page/employment.


# Real fixture captured 2026-08-16 from townsend.k12.mt.us/page/employment.


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-23 from hlpschools.k12.mt.us/page/jobs.


# Real fixture captured 2026-08-23 from plevnacougars.com's Employment page.


# Real fixture captured 2026-08-23 from sunburst.k12.mt.us/page/employment-opportunities.


# Real fixture captured 2026-08-23 from ramsayschool.com/employment/ (a
# plain WordPress site).

test_that("parse_ramsay_postings extracts the 2 real postings from the Open Positions heading", {
  html <- paste(readLines(test_path("fixtures", "ramsay_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_ramsay_postings(html, "url")

  expect_equal(nrow(result), 2)
  expect_equal(result$Title, c("Bus Monitor", "Para-Professional"))
  expect_true(all(result$Location == "Ramsay"))
})

test_that("parse_ramsay_postings returns zero rows (not an error) when there's no Open Positions heading", {
  result <- parse_ramsay_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_ramsay_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "ramsay_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_ramsay_postings()

  expect_equal(nrow(result), 2)
})

# Real fixture captured 2026-08-23 from roy.k12.mt.us (a plain Joomla site).

test_that("parse_roy_postings extracts all 3 real postings from 2 prose sentences and 1 bold line", {
  html <- paste(readLines(test_path("fixtures", "roy_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_roy_postings(html, "url")

  expect_equal(nrow(result), 3)
  expect_equal(result$Title, c("Head Cook", "Full-time Paraprofessional", "Bus Driver"))
  expect_true(all(result$Location == "Roy"))
})

test_that("parse_roy_postings returns zero rows (not an error) when there's no real posting text", {
  result <- parse_roy_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_roy_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "roy_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_roy_postings()

  expect_equal(nrow(result), 3)
})

# Real fixture captured 2026-08-23 from arrowheadk8.com/careers/ (a modern
# WordPress/Divi site serving Pray and Emigrant).

test_that("parse_arrowhead_postings extracts the 3 real h2-heading postings between the intro and boilerplate headings", {
  html <- paste(readLines(test_path("fixtures", "arrowhead_careers.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_arrowhead_postings(html, "url")

  expect_equal(nrow(result), 3)
  expect_equal(result$Title, c("Substitute Employment", "Special Education Paraprofessional", "Certified Teachers"))
  expect_true(all(result$Location == "Pray"))
})

test_that("parse_arrowhead_postings returns zero rows (not an error) when there's no Join the Arrowhead Team heading", {
  result <- parse_arrowhead_postings("<html><body><h2>Nothing here.</h2></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_arrowhead_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "arrowhead_careers.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_arrowhead_postings()

  expect_equal(nrow(result), 3)
})

# Real fixture captured 2026-08-23 from sites.google.com/nsschools.org's
# Employment page (North Star Public Schools, serving both Rudyard and
# Gildford).


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-23 from beltschool.com's Employment Opportunities page.


# Real fixture captured 2026-08-23 from bssd72.org's Employment Opportunities page.


# Real fixture captured 2026-08-23 from melstonepublicschools.org's
# Employment Opportunities page (a repeated "Title:"/"Description:"/
# "Benefits:" field-label card layout).


# Real fixture captured 2026-08-23 from svalleyk12.org's Employment page
# (genuinely Finalsite, serving both Clyde Park and Wilsall).

test_that("parse_shieldsvalley_postings extracts the 4 real currently-open postings, excluding the 8 already-Filled ones", {
  html <- paste(readLines(test_path("fixtures", "shieldsvalley_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_shieldsvalley_postings(html, "url")

  expect_equal(nrow(result), 4)
  expect_true(all(c("K-12 Art", "Maintenance / Grounds / Custodial Technician",
                     "High Needs Para Educator", "Occupational Therapist") %in% result$Title))
  expect_equal(result$Location[result$Title == "K-12 Art"], "Certified Teacher")
  expect_equal(result$Location[result$Title == "Occupational Therapist"], "Park Special Education Co-op")
  # Regression: 8 of 12 real posting lines on this page are already Filled
  # -- none of their titles should survive.
  expect_false(any(grepl("5th Grade Teacher|Head Cook|Head HS Football Coach", result$Title)))
})

test_that("parse_shieldsvalley_postings returns zero rows (not an error) when there's no Certified Teacher Openings container", {
  result <- parse_shieldsvalley_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_shieldsvalley_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "shieldsvalley_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_shieldsvalley_postings()

  expect_equal(nrow(result), 4)
})

# Fake chromote session: a plain list standing in for a real
# ChromoteSession$new() -- provides just the $Page$navigate/
# $Page$loadEventFired/$Runtime$evaluate surface fetch_shelbymt_postings()/
# fetch_geyser_postings() actually call, returning a fixed innerText
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


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-23 from roundup.k12.mt.us's Employment page.


# Real fixture captured 2026-08-23 from whitesulphur.k12.mt.us's Employment page.


# Real fixture captured 2026-08-23 from shelbypublicschools.org (Montana --
# not shelbypublicschools.net, a real, unrelated district in Michigan).

test_that("parse_shelbymt_postings extracts all 6 real postings embedded in 2 prose sentences, with the page's shared date", {
  text <- paste(readLines(test_path("fixtures", "apptegy_shelbymt_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_shelbymt_postings(text, "url")

  expect_equal(nrow(result), 6)
  expect_true(all(c("PAYROLL SECRETARY", "PARAPROFESSIONALS", "CAFETERIA EMPLOYEE", "ASSISTANT TECHNOLOGY COORDINATOR",
                     "JH Girls' Basketball Coaches", "JH Assistant Football Coach") %in% result$Title))
  expect_true(all(result$Posted_Date == "2026-08-13"))
})

test_that("parse_shelbymt_postings returns zero rows (not an error) when there's no 'is looking for' sentence", {
  result <- parse_shelbymt_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_shelbymt_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_shelbymt_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_shelbymt_postings(session)

  expect_equal(nrow(result), 6)
})

# Real fixture captured 2026-08-23 from geyser.k12.mt.us's CyberSchool-
# hosted Jobs page.

test_that("parse_geyser_postings extracts all 5 real postings from the keycap-emoji numbered list", {
  text <- paste(readLines(test_path("fixtures", "geyser_jobs_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_geyser_postings(text, "url")

  expect_equal(nrow(result), 5)
  expect_true(all(c("Industrial Arts/Agriculture Teacher", "Physical Education Teacher", "Boiler Operator",
                     "Paraprofessional Aide / SPED Aide", "Head Cook") %in% result$Title))
  expect_true(all(result$Location == "Geyser"))
})

test_that("parse_geyser_postings returns zero rows (not an error) when there's no keycap-numbered list", {
  result <- parse_geyser_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_geyser_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "geyser_jobs_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_geyser_postings(session)

  expect_equal(nrow(result), 5)
})

# Real fixture captured 2026-08-23 from thompsonfalls.net/employment
# (genuinely Finalsite).

test_that("parse_thompsonfalls_postings extracts the 5 real postings listed before the Load More button", {
  html <- paste(readLines(test_path("fixtures", "thompsonfalls_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_thompsonfalls_postings(html, "url")

  expect_equal(nrow(result), 5)
  expect_true(all(c("Para Professional", "Assistant High School Football Coach", "Food Service Worker",
                     "Food Service Worker - Dishwasher", "Assistant High School Soccer Coach") %in% result$Title))
  expect_true(all(result$Location == "Thompson Falls"))
})

test_that("parse_thompsonfalls_postings returns zero rows (not an error) when there's no Post RSS Feeds marker", {
  result <- parse_thompsonfalls_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

# Real fixture re-captured 2026-09-07 (drift-check issue #1): only 3
# postings now, and the "Load More" button is gone -- the boundary is the
# "Employment Information" section header. The 2026-08 version keyed only on
# "Load More" and silently returned 0.
test_that("parse_thompsonfalls_postings returns zero rows when the page has no postings between its markers", {
  # Regression (found by the reviewer regression run, 2026-10-06): with the
  # two markers back to back, (start + 1):(stop - 1) counted backwards and
  # returned the marker lines themselves as 2 fake postings.
  html <- "<html><body><p>Post RSS Feeds for Jobs</p><p>Employment Information</p></body></html>"
  result <- parse_thompsonfalls_postings(html, "url")
  expect_equal(nrow(result), 0)
})

test_that("parse_thompsonfalls_postings stops at 'Employment Information' when there's no 'Load More'", {
  html <- paste(readLines(test_path("fixtures", "thompsonfalls_employment_2026-09.html"),
                          warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  result <- parse_thompsonfalls_postings(html, "url")

  expect_equal(nrow(result), 3)
  expect_setequal(result$Title,
                  c("Food Service Worker", "Assistant High School Soccer Coach",
                    "Concession Coordinator"))
  # the boilerplate section that follows must NOT leak in
  expect_false(any(c("Employment Information", "APPLICATIONS", "CONTRACTS",
                     "JOB DESCRIPTIONS", "SALARY SCHEDULE") %in% result$Title))
})

test_that("fetch_thompsonfalls_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "thompsonfalls_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_thompsonfalls_postings()

  expect_equal(nrow(result), 5)
})

# Real fixture captured 2026-08-23 from centerville.k12.mt.us's Job
# Openings page (Centerville Public Schools, serving Sand Coulee).


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-23 from arleeschools.org's Employment Opportunities page.


# Real fixture captured 2026-08-23 from chinookschools.org's Employment page.


# Real fixture captured 2026-08-23 from darby.k12.mt.us's Employment page.


# Real fixture captured 2026-08-23 from dbps.k12.mt.us's Careers page.


# Red Rover (St. Ignatius, Hamilton, Columbia Falls) is read through its API since edjobs 0.14.0; the
# Chrome parser and its rendered-text fixtures went with it (edjobs tests the API parser).

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from stanfordmtschool.com's Job Openings page.


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from loloschools.org's Employment page.


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from froidschool.com's Open Positions/Applications
# page.


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from huntley.k12.mt.us's Employment Opportunities
# page (Worden).


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from parkcityschools.org's Employment information
# page, found via its own clientWorkStateTemp menu tree (no plain nav
# link).


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from alberton.k12.mt.us's Employment Opportunities
# page (first pass against OPI's own full district list).


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from dillonschools.org's Employment Opportunities
# page.


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from ennisschools.org's Job Opportunities page.


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from columbuscougars.com's District Employment
# page, found via its own clientWorkStateTemp menu tree.


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from stregisschool.org's Employment page.


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from florencecarlton.org's Available Positions
# page, found via its own "CLICK HERE TO VIEW AVAILABLE POSITIONS" link.


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from wolverine.life's Employment Opportunities page
# (West Yellowstone School, Apptegy, gated behind a "Client Challenge"
# bot-check that only a real browser render passes).


# Real fixture captured 2026-08-23 from ekalaka.net's Job Postings page (a
# real, tagged Job Postings module, CSS classes prefixed `ss-`).

test_that("parse_ekalaka_postings extracts the 7 real postings with real per-posting dates, excluding the boilerplate applications row", {
  html <- paste(readLines(test_path("fixtures", "ekalaka_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_ekalaka_postings(html, "url")

  expect_equal(nrow(result), 7)
  expect_true(all(c("Paraprofessional for the 26-27 school year", "Temporary Custodial Position",
                     "Elementary Teacher for 2026-2027 Year", "Coaching Positions", "Bus Drivers") %in% result$Title))
  expect_true(all(result$Location == "Ekalaka"))
  expect_false("Certified and Classified Applications" %in% result$Title)
  expect_equal(result$Posted_Date[result$Title == "Paraprofessional for the 26-27 school year"], "2026-07-10")
})

test_that("parse_ekalaka_postings returns zero rows (not an error) when there's no real posting row", {
  result <- parse_ekalaka_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_ekalaka_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "ekalaka_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_ekalaka_postings()

  expect_equal(nrow(result), 7)
})

# Real fixture captured 2026-08-24 from tregoschool.org's Employment page
# (a publicly published Google Sites page, same platform as North Star
# above).


# Real fixture captured 2026-08-24 from baker.k12.mt.us's Employment
# page (Finalsite, same platform as Thompson Falls/Hobson/Shepherd
# above; found in the first pass against OPI's own full district list).

test_that("parse_baker_postings extracts the 3 real Classified postings, excluding the Certified section that defers entirely to OPI", {
  html <- paste(readLines(test_path("fixtures", "baker_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_baker_postings(html, "url")

  expect_equal(nrow(result), 3)
  expect_true(all(c("Full-Time Elementary Secretary (6/4/26 open until filled)",
                     "Paraprofessional (open until filled)") %in% result$Title))
  expect_true(all(result$Location == "Baker"))
})

test_that("parse_baker_postings returns zero rows (not an error) when there's no CLASSIFIED POSITIONS AVAILABLE header", {
  result <- parse_baker_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_baker_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "baker_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_baker_postings()

  expect_equal(nrow(result), 3)
})

# Real fixture captured 2026-08-24 from sites.google.com/view/cutbankjobs
# (Google Sites -- a real candidate left unresolved in an earlier
# session, closed out here).


# Real fixture captured 2026-08-24 from hinsdale.k12.mt.us's real
# employment page (an unbranded CMS; "-Untitled.html" in the URL, the
# same naming pattern that meant "no real content" for Lavina's own
# decline this session, but this one genuinely has real content).

test_that("parse_hinsdale_postings extracts all 3 real numbered postings, stripping list markers and .docx extensions", {
  html <- paste(readLines(test_path("fixtures", "hinsdale_untitled.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_hinsdale_postings(html, "url")

  expect_equal(nrow(result), 3)
  expect_true(all(c("Daycare Manager", "Childcare Worker at Little Raiders Daycare",
                     "Route Bus Drivers") %in% result$Title))
  expect_true(all(result$Location == "Hinsdale"))
})

# Real fixture captured 2026-09-22 after the list shrank to one posting
# and the district dropped the hand-typed "1. " marker -- the old
# numbered-lines-only parser returned 0 here (drift-check flag, Issue #1).
test_that("parse_hinsdale_postings extracts a single unnumbered posting and skips the pay footnote", {
  html <- paste(readLines(test_path("fixtures", "hinsdale_untitled_2026-09-22.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_hinsdale_postings(html, "url")

  expect_equal(result$Title, "Route Bus Drivers")
  expect_true(all(result$Location == "Hinsdale"))
})

test_that("parse_hinsdale_postings returns zero rows (not an error) when there's no real intro sentence", {
  result <- parse_hinsdale_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_hinsdale_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "hinsdale_untitled.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_hinsdale_postings()

  expect_equal(nrow(result), 3)
})

# Real fixture captured 2026-08-24 from valier.k12.mt.us's Employment
# page (Google Sites).


# Real fixture captured 2026-08-24 from robertsrockets.org's District
# Employment page (a Joomla-based CMS).

test_that("parse_roberts_postings extracts the 3 real postings from the table's .el-title cells, scoped to the real table", {
  html <- paste(readLines(test_path("fixtures", "roberts_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_roberts_postings(html, "url")

  expect_equal(nrow(result), 3)
  expect_true(all(c("Full Time Custodian", "Substitute Teachers Needed", "Classroom Aide") %in% result$Title))
  expect_true(all(result$Location == "Roberts"))
  expect_false(any(result$Title == "Certified Online Application"))
})

test_that("parse_roberts_postings returns zero rows (not an error) when there's no real table", {
  result <- parse_roberts_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_roberts_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "roberts_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_roberts_postings()

  expect_equal(nrow(result), 3)
})

test_that("a maintenance page with no HTML is a clear error, not a file-path error", {
  # Real body captured 2026-11-04 (HTTP 200).
  body <- paste(readLines(test_path("fixtures", "roberts_maintenance.txt"), warn = FALSE), collapse = "\n")
  expect_error(parse_roberts_postings(body, "url"), "no HTML: \"site under maintenance\"")
})

# Real fixture captured 2026-08-24 from winnettschool.org's Employment
# page (Squarespace, same platform as Terry above).

test_that("parse_winnett_postings extracts the 4 real postings, splitting the 1 'Title - description' combined line", {
  html <- paste(readLines(test_path("fixtures", "winnett_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_winnett_postings(html, "url")

  expect_equal(nrow(result), 4)
  expect_true(all(c("Bus Driver/Substitute Bus Drivers", "Practice Bus Driver", "Activity Bus Driver",
                     "High School Track Coach") %in% result$Title))
  expect_true(all(result$Location == "Winnett"))
  expect_false(any(grepl("^#block-", result$Title)))
})

test_that("parse_winnett_postings returns zero rows (not an error) when there's no Certified Positions Open: header", {
  result <- parse_winnett_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_winnett_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "winnett_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_winnett_postings()

  expect_equal(nrow(result), 4)
})

# Real fixture captured 2026-08-24 from sites.google.com/a/lincoln.k12.mt.us's
# Employment page (Google Sites, old "sites.google.com/a/domain/..."
# format, publicly reachable unlike Wyola's own sign-in-walled site).


# Real fixture captured 2026-08-24 from independent.k12.mt.us's Job
# Openings page (a real public county district, not private, despite
# the "INDEPENDENT SCHOOL - BILLINGS" OPI-feed label; Google Sites).


# Real fixture captured 2026-08-24 from shepherd.k12.mt.us's Jobs page
# (Finalsite, same platform as Thompson Falls/Hobson above).

test_that("parse_shepherd_postings extracts all 18 real postings across 3 non-empty categories, including a genuine duplicate title", {
  html <- paste(readLines(test_path("fixtures", "shepherd_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_shepherd_postings(html, "url")

  expect_equal(nrow(result), 18)
  expect_equal(sum(result$Location == "Certified Teaching Positions"), 5)
  expect_equal(sum(result$Location == "Classified Positions"), 4)
  expect_equal(sum(result$Location == "Coaching Positions"), 9)
  expect_equal(sum(result$Title == "Assistant High School Wrestling Coach"), 2)
  expect_false(any(result$Location == "Administrator Positions"))
})

test_that("parse_shepherd_postings returns zero rows (not an error) when there's no Administrator Positions: header", {
  result <- parse_shepherd_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_shepherd_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "shepherd_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_shepherd_postings()

  expect_equal(nrow(result), 18)
})

# Real fixture captured 2026-08-24 from hyshamschools.com's Jobs page
# (an unbranded CMS, "Lightbox Page" marker-line technique).

test_that("parse_hysham_postings extracts the 2 real postings via the 'Lightbox Page' marker line", {
  html <- paste(readLines(test_path("fixtures", "hysham_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_hysham_postings(html, "url")

  expect_equal(nrow(result), 2)
  expect_true(all(c("Head of Maintenance", "Vo-Ag Teacher") %in% result$Title))
  expect_true(all(result$Location == "Hysham"))
})

test_that("parse_hysham_postings returns zero rows (not an error) when there's no real intro sentence", {
  result <- parse_hysham_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_hysham_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "hysham_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_hysham_postings()

  expect_equal(nrow(result), 2)
})

# Real fixture captured 2026-08-24 from swanriverschool.org's Human
# Resources page (WordPress, Bigfork, category headers marked in the raw
# HTML rather than separated by real newlines in the rendered text).


# Real fixture captured 2026-08-24 from bigforkschools.org's Employment
# page (WordPress; a real candidate left unresolved in an earlier
# session, closed out here).

test_that("parse_bigfork_postings extracts all 10 real postings via the 'BIGFORK SCHOOL DISTRICT NO. 38' marker line", {
  html <- paste(readLines(test_path("fixtures", "bigfork_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_bigfork_postings(html, "url")

  expect_equal(nrow(result), 10)
  expect_true(all(c("Food Service Associate 6 hours/day", "Full Time Instructional Paraprofessional",
                     "Substitute Bus Driver", "2026-2027 High School Boys Assistant Soccer Coach") %in% result$Title))
  expect_true(all(result$Location == "Bigfork"))
  expect_false(any(grepl("^EEO:", result$Title)))
})

test_that("parse_bigfork_postings returns zero rows (not an error) when there's no BIGFORK SCHOOL DISTRICT marker line", {
  result <- parse_bigfork_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_bigfork_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "bigfork_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_bigfork_postings()

  expect_equal(nrow(result), 10)
})

# Real fixture captured 2026-08-24 from reedpoint.k12.mt.us's Employment
# page (a publicly published Google Sites page, same platform as North
# Star/Trego above).


# Real fixture captured 2026-08-24 from hobson.k12.mt.us's Employment
# page (Finalsite, same platform as Thompson Falls above).

test_that("parse_hobson_postings extracts the 3 real postings under the year-suffixed 'Current Openings...' header", {
  html <- paste(readLines(test_path("fixtures", "hobson_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_hobson_postings(html, "url")

  expect_equal(nrow(result), 3)
  expect_true(all(c("Vo-Ag Teacher", "Physical Education", "Elementary Education") %in% result$Title))
  expect_true(all(result$Location == "Hobson"))
})

test_that("parse_hobson_postings returns zero rows (not an error) when there's no year-suffixed header", {
  result <- parse_hobson_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_hobson_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "hobson_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_hobson_postings()

  expect_equal(nrow(result), 3)
})

# Real fixture captured 2026-08-24 from turner.k12.mt.us's Employment
# page (WordPress, same platform as Ramsay above).

test_that("parse_turner_postings extracts the 3 real postings, skipping the empty Administrative/Coaching panels and their boilerplate links", {
  html <- paste(readLines(test_path("fixtures", "turner_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_turner_postings(html, "url")

  expect_equal(nrow(result), 3)
  expect_equal(sum(result$Location == "Certified Positions"), 2)
  expect_equal(sum(result$Location == "Classified Positions"), 1)
  expect_true(all(c("Vo-Ag Teacher – Part-time", "Business Teacher – Part-time") %in% result$Title[result$Location == "Certified Positions"]))
  expect_false(any(result$Title %in% TURNER_BOILERPLATE))
})

test_that("parse_turner_postings returns zero rows (not an error) when there's no Current Open Positions header", {
  result <- parse_turner_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_turner_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "turner_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_turner_postings()

  expect_equal(nrow(result), 3)
})

# Real fixture captured 2026-08-24 from terryschools.org's Employment
# page (Squarespace, a new platform for this project).

test_that("parse_terry_postings extracts all 14 real postings across the 2 asymmetric Certified/Classified sections", {
  html <- paste(readLines(test_path("fixtures", "terry_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_terry_postings(html, "url")

  expect_equal(nrow(result), 14)
  expect_equal(sum(result$Location == "Certified"), 7)
  expect_equal(sum(result$Location == "Classified"), 7)
  expect_true(all(c("3 Elementary Teachers", "Title 1 Elementary Teacher") %in% result$Title[result$Location == "Certified"]))
  expect_true(all(c("Special Education Paraprofessional", "Sub custodian") %in% result$Title[result$Location == "Classified"]))
})

test_that("parse_terry_postings returns zero rows (not an error) when there's no real section marker", {
  result <- parse_terry_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_terry_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "terry_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_terry_postings()

  expect_equal(nrow(result), 14)
})

# Real fixture from gallatingatewayschool.com's Employment page (CatapultCMS),
# recaptured 2026-11-04 at its new address, About-Us/Employment/.

test_that("parse_gallatingateway_postings extracts the 3 real 'always hiring' postings", {
  html <- paste(readLines(test_path("fixtures", "gallatingateway_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_gallatingateway_postings(html, "url")

  expect_equal(nrow(result), 3)
  expect_true(all(c("Substitute Teacher", "Athletic Director", "Business Manager") %in% result$Title))
  expect_true(all(result$Location == "Gallatin Gateway"))
})

test_that("parse_gallatingateway_postings returns zero rows (not an error) when there's no real ON CALL header", {
  result <- parse_gallatingateway_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_gallatingateway_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "gallatingateway_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_gallatingateway_postings()

  expect_equal(nrow(result), 3)
})

test_that("fetch_apptegy_k12_postings returns an empty frame (not an error) when no session factory is available", {
  result <- fetch_apptegy_k12_postings(chromote_session_factory = NULL, log_path = tempfile())
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link", "District"))
})

test_that("fetch_apptegy_k12_postings keeps healthy districts when one fetch fails", {
  session_factory <- function() list(
    close = function() invisible(NULL)
  )
  scrapers <- list(
    "Broken district" = function(session) stop("Page structure changed"),
    "Healthy district" = function(session) data.frame(
      Title = "Healthy posting", Location = "Healthy", Posted_Date = NA_character_,
      Link = "url", stringsAsFactors = FALSE
    )
  )

  result <- fetch_apptegy_k12_postings(
    session_factory, log_path = tempfile(), scrapers = scrapers
  )

  expect_equal(nrow(result), 1)
  expect_equal(result$District, "Healthy district")
  expect_equal(result$Title, "Healthy posting")
})

test_that("APPTEGY_DISTRICT_SCRAPERS exactly matches the registry's ApptegyBespoke rows in both directions", {
  # This is the actual bug class the 2026-09 AppliTrack migrations exposed
  # in miniature (a registry row whose scraper doesn't run, or vice versa)
  # -- catching it here means a forgotten sync surfaces as an immediate,
  # specific test failure instead of a district silently scraping nothing
  # (or a scraped district with no registry row to join against on the
  # Map/District Summary) for however many weeks until someone notices.
  registry <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  # The family routine's rows (Apptegy, ApptegyPageBuilder) are read from the registry itself (edjobs 0.18.0).
  registry_districts <- registry$District[registry$Platform == "ApptegyBespoke"]

  expect_setequal(names(APPTEGY_DISTRICT_SCRAPERS), registry_districts)
})


# Real fixture captured 2026-08-24 from Miles City's Google Sheets CSV
# export (Custer County District 1, SCHOOLinSITES CMS with jobs listed on
# a live Google Sheet rather than any HTML page).

test_that("parse_milescity_postings extracts the 20 real open postings, excluding Filled rows and trailing blank/footer rows", {
  csv_text <- paste(readLines(test_path("fixtures", "milescity_jobs.csv"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_milescity_postings(csv_text, "url")

  expect_equal(nrow(result), 20)
  expect_true(all(c("Bus/Cruiser Drivers for Activities", "Business Teacher", "Assistant Principal",
                     "Spirit Squad Head Coach") %in% result$Title))
  expect_false(any(grepl("^For additional information", result$Title)))
  expect_false(any(result$Title == "Boys Basketball Assistant Coach"))
})

test_that("parse_milescity_postings returns zero rows (not an error) when the expected columns are missing", {
  result <- parse_milescity_postings("Title,Notes\nSomething,Else\n", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_milescity_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "milescity_jobs.csv"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/csv; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_milescity_postings()

  expect_equal(nrow(result), 20)
})

# Real fixture captured 2026-08-24 from augustaschool.org's Job Openings
# page (a Wix site, a platform new to this project).

test_that("parse_augusta_postings extracts the 3 real postings, using each block's own 'Application' link-label line as its boundary", {
  html <- paste(readLines(test_path("fixtures", "augusta_job_openings.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_augusta_postings(html, "url")

  expect_equal(nrow(result), 3)
  expect_true(all(c("Special Education Full-Time Aide", "Become a Bus Driver", "Substitute Teachers") %in% result$Title))
  expect_true(all(result$Location == "Augusta"))
  expect_false(any(grepl("^#comp-", result$Title)))
})

test_that("parse_augusta_postings returns zero rows (not an error) when there's no real start marker", {
  result <- parse_augusta_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_augusta_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "augusta_job_openings.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_augusta_postings()

  expect_equal(nrow(result), 3)
})

# Real fixture captured 2026-08-24 from mtbrocktonps.schoolinsites.com's
# Employment page (SCHOOLinSITES CMS, same platform as Miles City above).

test_that("parse_brockton_postings extracts the 2 real postings between the header and the closing sentence", {
  html <- paste(readLines(test_path("fixtures", "brockton_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_brockton_postings(html, "url")

  expect_equal(nrow(result), 2)
  expect_true(all(c("Maintenance", "Bus Driver") %in% result$Title))
  expect_true(all(result$Location == "Brockton"))
})

test_that("parse_brockton_postings extracts the 3 real postings from the updated 2026 website", {
  html <- paste(readLines(test_path("fixtures", "brockton_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_brockton_postings(html, "https://www.brockton.k12.mt.us/employment")

  expect_equal(nrow(result), 3)
  expect_true(all(c("Elementary Teacher (Multiple Openings)",
                    "Secondary Teacher – STEM (Multiple Openings)",
                    "Secondary Teacher – Humanities (Multiple Openings)") %in% result$Title))
  expect_true(all(result$Location == "Brockton"))
})

test_that("parse_brockton_postings returns zero rows (not an error) when there's no real start marker", {
  result <- parse_brockton_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_brockton_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "brockton_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_brockton_postings()

  expect_equal(nrow(result), 2)
})

# Real fixture captured 2026-08-24 from culbertsonschool.com's Employment
# page (Finalsite).

test_that("parse_culbertson_postings extracts the 2 real Classified postings, excluding the empty Certified and Roos-Valley Coop sections", {
  html <- paste(readLines(test_path("fixtures", "culbertson_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_culbertson_postings(html, "url")

  expect_equal(nrow(result), 2)
  expect_true(all(c("Substitute Teachers", "Activity Bus Drivers") %in% result$Title))
  expect_true(all(result$Location == "Culbertson"))
  expect_false(any(grepl("Application", result$Title, fixed = TRUE)))
})

test_that("parse_culbertson_postings returns zero rows (not an error) when there's no real start marker", {
  result <- parse_culbertson_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_culbertson_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "culbertson_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_culbertson_postings()

  expect_equal(nrow(result), 2)
})

# Real fixture captured 2026-08-24 from cottonwood57.org's Job Openings
# page (a publicly published Google Sites page, same platform as
# Lincoln/Independent above). Genuinely empty right now.


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-25 from bonner.k12.mt.us's Employment page (Apptegy).


# Real fixture captured 2026-08-25 from Creston School's linked Google
# Doc (plain-text export) of job postings.

test_that("parse_creston_postings extracts the 1 real posting, excluding the 3 'No positions are currently available' categories", {
  doc_text <- paste(readLines(test_path("fixtures", "creston_jobs_doc.txt"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_creston_postings(doc_text, "url")

  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "Guest Teacher (aka Substitute)")
  expect_true(all(result$Location == "Creston"))
})

test_that("parse_creston_postings returns zero rows (not an error) when every category is empty", {
  result <- parse_creston_postings("Administrative\n\nNo positions are currently available\n\nCertified\n\nNo positions are currently available\n\nClassified\n\nNo positions are currently available\n\nGuest Teacher (aka Substitute)\n\nNo positions are currently available\n", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_creston_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "creston_jobs_doc.txt"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/plain; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_creston_postings()

  expect_equal(nrow(result), 1)
})

# Real fixture captured 2026-08-25 from clintoncougars.com's Employment
# page (an unbranded CMS).

test_that("parse_clinton_postings extracts the 2 real postings via the 'Clinton School is looking for...' marker line", {
  html <- paste(readLines(test_path("fixtures", "clinton_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_clinton_postings(html, "url")

  expect_equal(nrow(result), 2)
  expect_true(all(c("Substitute Teachers", "Para Position for 26-27") %in% result$Title))
  expect_true(all(result$Location == "Clinton"))
})

test_that("parse_clinton_postings returns zero rows (not an error) when there's no real marker line", {
  result <- parse_clinton_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_clinton_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "clinton_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_clinton_postings()

  expect_equal(nrow(result), 2)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-25 from deerpark.k12.mt.us's Employment Opportunities
# page (Apptegy).


# Real fixture captured 2026-08-25 from dixonschool.org's Employment
# Opportunities page (a publicly published Google Sites page).


# Real fixture captured 2026-08-25 from Elysian School District #23's
# Employment page (a publicly published Google Sites page).


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-25 from evergreensd50.com's Employment Opportunities
# page (Apptegy).


# Real fixture captured 2026-08-25 from fmemontana.net's Employment page
# (a publicly published Google Sites page).


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-25 from lonerockschool.org's Employment page (Apptegy,
# real slug is "/page/employment").


# Real fixture: document.body.innerText captured via a live chromote
# session 2026-10-20 from sgchs.com's Employment page (Apptegy).


# Real fixture captured 2026-08-25 from lustregradeschool.com's
# Employment page (a publicly published Google Sites page).


# Real fixture captured 2026-08-25 from miamielementary.com's Employment
# page (a Hutterite colony school near Conrad).

test_that("parse_miami_postings extracts the 1 real standing 'Substitute Teachers' posting", {
  html <- paste(readLines(test_path("fixtures", "miami_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_miami_postings(html, "url")

  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "Substitute Teachers")
  expect_true(all(result$Location == "Miami"))
})

test_that("parse_miami_postings returns zero rows (not an error) when the marker sentence isn't found", {
  result <- parse_miami_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_miami_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "miami_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_miami_postings()

  expect_equal(nrow(result), 1)
})

# Real fixture captured 2026-08-25 from zurichelementary17.org's
# Employment page (a Wix site, same platform as Augusta above). Genuinely
# empty right now.

test_that("parse_zurich_postings returns zero rows (not an error) for the current real 'no jobs open' state", {
  html <- paste(readLines(test_path("fixtures", "zurich_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_zurich_postings(html, "url")

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_zurich_postings returns zero rows (not an error) when there's no real start/stop marker at all", {
  result <- parse_zurich_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_zurich_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "zurich_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_zurich_postings()

  expect_equal(nrow(result), 0)
})

# Real fixture captured 2026-08-25 from daytonschool.net's Employment
# page (Upper West Shore School District #33).

test_that("parse_dayton_postings extracts the 2 real postings, excluding the empty 'Teachers:' category", {
  html <- paste(readLines(test_path("fixtures", "dayton_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_dayton_postings(html, "url")

  expect_equal(nrow(result), 2)
  expect_true(all(c("Paraprofessionals", "Substitute Teachers") %in% result$Title))
  expect_true(all(result$Location == "Dayton"))
  expect_false("Teachers" %in% result$Title)
})

test_that("parse_dayton_postings returns zero rows (not an error) when there's no real start/stop marker", {
  result <- parse_dayton_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_dayton_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "dayton_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_dayton_postings()

  expect_equal(nrow(result), 2)
})

test_that("parse_belfry_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "belfry_employment_2026-10-20.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.belfrybats.org/index.php/our-school/employment"

  result <- parse_belfry_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, c("Substitute Teachers", "School Bus Drivers"))
  expect_true(all(result$Location == "Belfry"))
  expect_true(all(grepl("jotform\\.com", result$Link)))
})

test_that("parse_belfry_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_belfry_postings("<html><body><p>No table</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_belfry_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "belfry_employment_2026-10-20.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_belfry_postings()

  expect_equal(nrow(result), 2)
})

test_that("parse_nashua_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "nashua_jobs_2026-10-20.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.nashua.k12.mt.us/District/Jobs/"

  result <- parse_nashua_postings(fixture, url)

  expect_equal(nrow(result), 7)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, c(
    "Part-Time Custodian",
    "K-12 Librarian (full or part-time)",
    "Music (full or part-time)",
    "Special Education",
    "Concessions",
    "Substitute Teacher",
    "Substitute Bus Driver/Activity Bus Driver"
  ))
  expect_true(all(result$Location == "Nashua"))
  expect_true(all(result$Link == url))
})

test_that("parse_nashua_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_nashua_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_nashua_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "nashua_jobs_2026-10-20.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_nashua_postings()

  expect_equal(nrow(result), 7)
})

test_that("parse_whitehall_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "whitehall_jobs_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.whitehallschools.org/apps/jobs/"

  result <- parse_whitehall_postings(fixture, url)

  expect_equal(nrow(result), 4)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, c(
    "Extracurricular Position ( Advisor or Coach)",
    "Paraprofessional / Teacher's Aide",
    "School Custodian",
    "Substitute Teacher"
  ))
  expect_equal(result$Location, c(
    "Whitehall",
    "Whitehall Elementary",
    "Whitehall School District",
    "Whitehall Elementary, Whitehall Middle and High Schools"
  ))
  expect_true(all(grepl("^https://www\\.whitehallschools\\.org/apps/jobs/show_job\\.jsp\\?REC_ID=", result$Link)))
})

test_that("parse_whitehall_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_whitehall_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_whitehall_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "whitehall_jobs_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_whitehall_postings()

  expect_equal(nrow(result), 4)
})


test_that("parse_wibaux_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "wibaux_employment_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.wibauxschools.net/employment"

  result <- parse_wibaux_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "Special Education Teacher")
  expect_equal(result$Location, "Wibaux")
  expect_true(grepl("\\.pdf$", result$Link))
})

test_that("parse_wibaux_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_wibaux_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_wibaux_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "wibaux_employment_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_wibaux_postings()

  expect_equal(nrow(result), 1)
})

test_that("parse_westvalley_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "westvalley_submittable_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://westvalleyschool.submittable.com/submit"

  result <- parse_westvalley_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "Paraprofessional Position")
  expect_equal(result$Location, "Kalispell")
  expect_true(grepl("paraprofessional-position$", result$Link))
})

test_that("parse_westvalley_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_westvalley_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_westvalley_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "westvalley_submittable_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_westvalley_postings()

  expect_equal(nrow(result), 1)
})

test_that("parse_luther_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "luther_documents_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.lutherschool.org/index.php/documents"

  result <- parse_luther_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, c("Bus Driver", "Cook"))
  expect_equal(result$Location, c("Luther", "Luther"))
  expect_true(all(grepl("\\.pdf$", result$Link)))
})

test_that("parse_luther_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_luther_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_luther_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "luther_documents_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_luther_postings()

  expect_equal(nrow(result), 2)
})

test_that("parse_swanvalley_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "swanvalley_careers_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.swanvalleyelementary.org/careers.html"

  result <- parse_swanvalley_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "Instructional paraprofessional, or a candidate interested in a part-time teaching/part-time paraprofessional role")
  expect_equal(result$Location, "Condon")
  expect_equal(result$Link, url)
})

test_that("parse_swanvalley_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_swanvalley_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_swanvalley_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "swanvalley_careers_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_swanvalley_postings()

  expect_equal(nrow(result), 1)
})


test_that("parse_smithvalley_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "smithvalley_googlesites_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.smithvalleyschool.org/employment-opportunities"

  result <- parse_smithvalley_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, c("7/8 Grade Girls Basketball Coach", "Substitute Teacher"))
  expect_true(all(result$Location == "Kalispell"))
  expect_true(all(result$Link == url))
})

test_that("parse_smithvalley_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_smithvalley_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_smithvalley_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "smithvalley_googlesites_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_smithvalley_postings()

  expect_equal(nrow(result), 2)
})

test_that("parse_moore_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "moore_weebly_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.mooreschoolmt.com/employment.html"

  result <- parse_moore_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "Full-Time Custodial Position")
  expect_equal(result$Location, "Moore")
  expect_equal(result$Posted_Date, "7/22/26")
  expect_true(grepl("\\.pdf$", result$Link))
})

test_that("parse_moore_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_moore_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_moore_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "moore_weebly_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_moore_postings()

  expect_equal(nrow(result), 1)
})


test_that("parse_boulder_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "boulder_schoolcms_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.bgs.k12.mt.us/employment"

  result <- parse_boulder_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_true("Girls Basketball Coach" %in% result$Title)
  expect_true("After School Program Teachers/Subs" %in% result$Title)
  expect_equal(unique(result$Location), "Boulder")
  expect_equal(unique(result$Link), url)
})

test_that("parse_boulder_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_boulder_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_boulder_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "boulder_schoolcms_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_boulder_postings()

  expect_equal(nrow(result), 2)
})

test_that("parse_jeffersonhigh_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "jeffersonhigh_eschoolview_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.jhs.k12.mt.us/EmploymentOpportunities.aspx"

  result <- parse_jeffersonhigh_postings(fixture, url)

  expect_equal(nrow(result), 6)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_true("Teachers" %in% result$Title)
  expect_true("Assistant Football" %in% result$Title)
  expect_true("Head and Assistant Cheer" %in% result$Title)
  expect_equal(unique(result$Location), "Boulder")
  expect_equal(unique(result$Link), url)
})

test_that("parse_jeffersonhigh_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_jeffersonhigh_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_jeffersonhigh_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "jeffersonhigh_eschoolview_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_jeffersonhigh_postings()

  expect_equal(nrow(result), 6)
})


test_that("parse_lockwood_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "lockwood_edlio_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.lockwoodschool.org/apps/pages/index.jsp?uREC_ID=409277&type=d"

  result <- parse_lockwood_postings(fixture, url)

  expect_equal(nrow(result), 8)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_true("Special Education Teacher (K12)" %in% result$Title)
  expect_true("Part-Time Crosswalk Guard" %in% result$Title)
  expect_equal(unique(result$Location), "Lockwood")
  expect_equal(unique(result$Link), url)
})

test_that("parse_lockwood_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_lockwood_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_lockwood_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "lockwood_edlio_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_lockwood_postings()

  expect_equal(nrow(result), 8)
})

test_that("parse_frazer_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "frazer_cyberschool_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.frazer.k12.mt.us/District/Jobs/"

  result <- parse_frazer_postings(fixture, url)

  expect_equal(nrow(result), 26)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_true("Elementary Teacher" %in% result$Title)
  expect_true("K - 12 Physical Education Teacher" %in% result$Title)
  expect_true("Business Manager/Clerk" %in% result$Title)
  expect_equal(unique(result$Location), "Frazer")
  expect_equal(unique(result$Link), url)
})

test_that("parse_frazer_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_frazer_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_frazer_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "frazer_cyberschool_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_frazer_postings()

  expect_equal(nrow(result), 26)
})

test_that("parse_lambert_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "lambert_finalsite_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.lambertschool.net/career-opportunities/employment-opportunities"

  result <- parse_lambert_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "Music K-12")
  expect_equal(result$Location, "Lambert")
  expect_equal(result$Link, url)
})

test_that("parse_lambert_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_lambert_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_lambert_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "lambert_finalsite_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_lambert_postings()

  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "Music K-12")
})

test_that("parse_richey_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "richey_cscms_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.richey.k12.mt.us/currentopenings"

  result <- parse_richey_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "2026-27 Assistant Cook / Custodian")
  expect_equal(result$Location, "Richey")
  expect_equal(result$Link, url)
})

test_that("parse_richey_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_richey_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_richey_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "richey_cscms_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_richey_postings()

  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "2026-27 Assistant Cook / Custodian")
})

test_that("parse_judithgap_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "judithgap_cyberschool_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.judithgap.k12.mt.us/District/Portal/Employment"

  result <- parse_judithgap_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("Custodian / Maintenance / Boiler Operator", "School Cook"))
  expect_equal(unique(result$Location), "Judith Gap")
  expect_equal(unique(result$Link), url)
})

test_that("parse_judithgap_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_judithgap_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_whitewater_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "whitewater_finalsite_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://whitewater.k12.mt.us/employment"

  result <- parse_whitewater_postings(fixture, url)

  expect_equal(nrow(result), 3)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("Substitute Teachers", "Bus Drivers", "Custodians"))
  expect_equal(unique(result$Location), "Whitewater")
  expect_equal(unique(result$Link), url)
})

test_that("parse_whitewater_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_whitewater_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_victor_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "victor_gdoc_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.victor.k12.mt.us/page/employment"

  result <- parse_victor_postings(fixture, url)

  expect_equal(nrow(result), 4)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("HS/MS Special Education Teacher", "Paraprofessional", "Head High School Track Coach", "Substitute"))
  expect_equal(unique(result$Location), "Victor")
  expect_equal(unique(result$Link), url)
  expect_equal(unique(result$Posted_Date), "10/1/2026")
})

test_that("parse_victor_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_victor_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_superior_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "superior_gdoc_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.ssd3.us/page/employment"

  result <- parse_superior_postings(fixture, url)

  expect_equal(nrow(result), 3)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("Bus Drivers", "Substitute Teachers", "Paraprofessionals"))
  expect_equal(unique(result$Location), "Superior")
  expect_equal(unique(result$Link), url)
})

test_that("parse_superior_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_superior_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})


test_that("parse_rapelje_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "rapelje_parentsquare_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.rapelje.k12.mt.us/job-listings"

  result <- parse_rapelje_postings(fixture, url)

  expect_equal(nrow(result), 3)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("Bus Drivers—Route and/or Activity Drivers",
                                  "Preschool Teacher", "Cooks Helper"))
  expect_equal(unique(result$Location), "Rapelje")
  expect_equal(unique(result$Link), url)
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_rapelje_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_rapelje_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})


test_that("parse_eldergrove_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "eldergrove_finalsite_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.eldergrove.k12.mt.us/about-eg/employment/available-positions"

  result <- parse_eldergrove_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "Paraprofessionals")
  expect_equal(unique(result$Location), "Billings")
  expect_equal(unique(result$Link), url)
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_eldergrove_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_eldergrove_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_monforton_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "monforton_wordpress_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://monfortonschool.org/contact-us/job-openings/"

  result <- parse_monforton_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("Business Manager", "District Clerk"))
  expect_equal(unique(result$Location), "Bozeman")
  expect_equal(unique(result$Link), url)
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_monforton_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_monforton_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_grassrange_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "grassrange_custom_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://grps.k12.mt.us/staff/open-positions"

  result <- parse_grassrange_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("CDL Bus/Activity Driver", "Substitutes in all areas"))
  expect_equal(unique(result$Location), "Grass Range")
  expect_equal(unique(result$Link), url)
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_grassrange_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_grassrange_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_heartbutte_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "heartbutte_wordpress_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://heartbutte.k12.mt.us/employment/"

  result <- parse_heartbutte_postings(fixture, url)

  expect_equal(nrow(result), 8)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("Payroll Clerk", "K-12 Counselor",
                                  "Maintenance/Transportation Supervisor",
                                  "Substitute Teachers, Teacher’s Aides, Bus Drivers, Custodians",
                                  "Head Coach - Boy’s Basketball",
                                  "Head Coach - Junior High Basketball",
                                  "Head Coach - Wrestling",
                                  "Head Coach - Golf"))
  expect_equal(unique(result$Location), "Heart Butte")
  expect_equal(unique(result$Link), url)
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_heartbutte_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_heartbutte_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_noxon_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "noxon_apptegy_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.noxonschools.com/o/nps/page/certified-listings"

  result <- parse_noxon_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "7–12 Science Teacher")
  expect_equal(unique(result$Location), "Noxon")
  expect_equal(unique(result$Link), url)
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_noxon_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_noxon_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_seeleylake_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "seeleylake_apptegy_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.sleonline.org/page/join-our-team"

  result <- parse_seeleylake_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "Substitute (All Areas)")
  expect_equal(unique(result$Location), "Seeley Lake")
  expect_equal(unique(result$Link), url)
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_seeleylake_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_seeleylake_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_eastglacier_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "eastglacier_cyberschool_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://eastglacierschool.com/employment"

  result <- parse_eastglacier_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "Licensed Teachers")
  expect_equal(unique(result$Location), "East Glacier Park")
  expect_equal(unique(result$Link), url)
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_eastglacier_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_eastglacier_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_charlo_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "charlo_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://charlo.k12.mt.us/"

  result <- parse_charlo_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, c("Bus Drivers", "Paraprofessionals"))
  expect_equal(unique(result$Location), "Charlo")
  expect_equal(result$Link, c("https://charlo.k12.mt.us/announcements/hiring-bus-drivers/",
                              "https://charlo.k12.mt.us/announcements/hiring-paraprofessionals/"))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_charlo_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_charlo_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_canyoncreek_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "canyoncreek_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.canyoncreekschool.org/apps/jobs/"

  result <- parse_canyoncreek_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "Paraprofessional Pre-K (All Day Full-Time)")
  expect_equal(unique(result$Location), "Billings")
  expect_equal(result$Link, "https://www.canyoncreekschool.org/apps/jobs/show_job.jsp?REC_ID=23398")
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_canyoncreek_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_canyoncreek_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_hellgate_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "hellgate_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.hellgate.k12.mt.us/our-district/employment"

  result <- parse_hellgate_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, c("Substitute Teacher", "Custodial substitutes"))
  expect_equal(unique(result$Location), "Missoula")
  expect_equal(result$Link, c("https://www.hellgate.k12.mt.us/fs/pages/3391",
                              "https://www.hellgate.k12.mt.us/fs/pages/3392"))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_hellgate_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_hellgate_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_helenaflats_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "helenaflats_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.helenaflats.org/page/employment"

  result <- parse_helenaflats_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, c("Special Education Paraprofessional", "Substitutes Needed - all positions"))
  expect_equal(unique(result$Location), "Kalispell")
  expect_equal(unique(result$Link), url)
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_helenaflats_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_helenaflats_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})


test_that("parse_jordan_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "jordan_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.jordanpublicschools.org"

  result <- parse_jordan_postings(fixture, url)

  expect_equal(nrow(result), 5)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("Head of Maintenance", "K-12 Music Teacher",
                                 "Junior High Football Head Coach and Assistant Coach",
                                 "Junior High Boys Basketball Coach",
                                 "High School Boys Basketball Coach"))
  expect_true(all(result$Location == "Jordan"))
  expect_true(all(result$Link == url))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_jordan_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_jordan_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_pioneer_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "pioneer_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "http://pioneerschool.us/41034_2"

  result <- parse_pioneer_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "Substitute Teacher")
  expect_equal(result$Location, "Billings")
  expect_equal(result$Link, url)
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_pioneer_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_pioneer_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_opheim_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "opheim_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://sites.google.com/site/opheimschool/office"

  result <- parse_opheim_postings(fixture, url)

  expect_equal(nrow(result), 3)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("Substitute Teacher", "Substitute Bus Driver", "Music Teacher"))
  expect_true(all(result$Location == "Opheim"))
  expect_true(all(result$Link == url))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_opheim_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_opheim_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_pryor_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "pryor_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://pryorwarriors.org/human-resources/"

  result <- parse_pryor_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("Literacy Tutors", "Bus Drivers"))
  expect_true(all(result$Location == "Pryor"))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_pryor_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_pryor_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_westglacier_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "westglacier_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.westglacierelementary.org/opportunities/employment"

  result <- parse_westglacier_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("Substitute Teacher", "Part-Time Custodian / Maintenance Worker"))
  expect_true(all(result$Location == "West Glacier"))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_westglacier_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_westglacier_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_troutcreek_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "troutcreek_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.troutcreekeagles.org/apps/pages/index.jsp?uREC_ID=4449487&type=d&pREC_ID=2698685"

  result <- parse_troutcreek_postings(fixture, url)

  expect_equal(nrow(result), 4)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("Teachers", "Business Manager/Clerk", "Substitute Teachers", "Para-Professional"))
  expect_true(all(result$Location == "Trout Creek"))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_troutcreek_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_troutcreek_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_kila_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "kila_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://docs.google.com/document/d/10u_uwKptqVgvrhCL83skDHtK2lGzPCjRCl88em-58O0/export?format=html"

  result <- parse_kila_postings(fixture, url)

  expect_equal(nrow(result), 4)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("Custodian", "Substitute Custodian", "Substitute Para/Student Support", "Substitute Teachers"))
  expect_true(all(result$Location == "Kila"))
  expect_false(any(is.na(result$Posted_Date)))
})

test_that("parse_kila_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_kila_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_lavina_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "lavina_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.lavinapublicschools.com/District/2269-Untitled.html"

  result <- parse_lavina_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_setequal(result$Title, c("Junior High Assistant Volleyball Coach", "Junior High Assistant Football Coach"))
  expect_true(all(result$Location == "Lavina"))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_lavina_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_lavina_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_fromberg_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "fromberg_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.frombergpublicschools.com/district-info/employment"

  result <- parse_fromberg_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "Subs Music Teaching Position")
  expect_true(all(result$Location == "Fromberg"))
  expect_true(all(is.na(result$Posted_Date)))
  expect_equal(result$Link, "https://resources.finalsite.net/images/v1788191968/frombergpublicschoolscom/ubmikbqkr9khjuq2znyw/SubsMusicTeachingPosition.pdf")
})

test_that("parse_fromberg_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_fromberg_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_pleasantvalley_postings returns zero rows when no openings", {
  fixture <- paste(readLines(test_path("fixtures", "pleasantvalley_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.pvsmt.org/employment-opportunities.html"

  result <- parse_pleasantvalley_postings(fixture, url)

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_pleasantvalley_postings extracts positions when present", {
  sample_html <- '<div id="wsite-content"><h2 class="wsite-content-title">Employment Opportunities</h2><h2 class="wsite-content-title">Elementary Teacher (K-5)</h2></div>'
  url <- "https://www.pvsmt.org/employment-opportunities.html"

  result <- parse_pleasantvalley_postings(sample_html, url)
  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "Elementary Teacher (K-5)")
  expect_equal(result$Location, "Marion")
  expect_equal(result$Link, url)
})

test_that("parse_pleasantvalley_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_pleasantvalley_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_sunrivervalley_postings returns zero rows on fixture with only generic applications", {
  fixture <- paste(readLines(test_path("fixtures", "sunrivervalley_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://srvs.k12.mt.us/apps/jobs/"

  result <- parse_sunrivervalley_postings(fixture, url)

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_sunrivervalley_postings extracts real positions when present", {
  sample_html <- '<table width="100%"><tr><td class="light pale lightBorderBottom"><b><a href="/apps/jobs/show_job.jsp?REC_ID=19999">7-12 Science Teacher</a></b><br></td></tr></table>'
  url <- "https://srvs.k12.mt.us/apps/jobs/"

  result <- parse_sunrivervalley_postings(sample_html, url)
  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "7-12 Science Teacher")
  expect_equal(result$Location, "Simms")
  expect_equal(result$Link, "https://srvs.k12.mt.us/apps/jobs/show_job.jsp?REC_ID=19999")
})

test_that("parse_sunrivervalley_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_sunrivervalley_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_circle_postings returns zero rows on fixture with only generic applications", {
  fixture <- paste(readLines(test_path("fixtures", "circle_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.circleschools.org/employment-opportunities.html"

  result <- parse_circle_postings(fixture, url)

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_circle_postings extracts real positions when present", {
  sample_html <- '<div id="wsite-content"><h2 class="wsite-content-title">Employment Opportunities</h2><h2 class="wsite-content-title">High School English Teacher</h2></div>'
  url <- "https://www.circleschools.org/employment-opportunities.html"

  result <- parse_circle_postings(sample_html, url)
  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "High School English Teacher")
  expect_equal(result$Location, "Circle")
  expect_equal(result$Link, url)
})

test_that("parse_circle_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_circle_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_forsyth_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "forsyth_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://forsythpublicschools.org/bus-drivers-wanted/"

  result <- parse_forsyth_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, "Bus Drivers Wanted!")
  expect_true(all(result$Location == "Forsyth"))
  expect_true(all(is.na(result$Posted_Date)))
  expect_equal(result$Link, "https://www.forsythpublicschools.org/kL14New/uploads/2025/11/Bus-Driver-Education.pdf")
})

test_that("parse_forsyth_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_forsyth_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_desmet_postings returns zero rows on fixture with only generic applications", {
  fixture <- paste(readLines(test_path("fixtures", "desmet_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://desmetschool.org/available-employment-opportunities/"

  result <- parse_desmet_postings(fixture, url)

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_desmet_postings extracts real positions when present", {
  sample_html <- '<div class="entry-content"><h2>Special Education Teacher</h2></div>'
  url <- "https://desmetschool.org/available-employment-opportunities/"

  result <- parse_desmet_postings(sample_html, url)
  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "Special Education Teacher")
  expect_equal(result$Location, "Missoula")
  expect_equal(result$Link, url)
})

test_that("parse_desmet_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_desmet_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_fishtail_postings returns zero rows on fixture with no active openings", {
  fixture <- paste(readLines(test_path("fixtures", "fishtail_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://fishtailschool.org/job-openings/"

  result <- parse_fishtail_postings(fixture, url)

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_fishtail_postings extracts real positions when present", {
  test_html <- "<div id=\"av-primary-content\"><h2>Elementary Teacher</h2><a href=\"/app.pdf\">Apply</a></div>"
  url <- "https://fishtailschool.org/job-openings/"

  result <- parse_fishtail_postings(test_html, url)

  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "Elementary Teacher")
  expect_equal(result$Location, "Fishtail")
  expect_equal(result$Link, "https://fishtailschool.org/app.pdf")
})

test_that("parse_fishtail_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_fishtail_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_nye_postings returns zero rows on fixture with no active openings", {
  fixture <- paste(readLines(test_path("fixtures", "nye_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.nyeschooldistrict.org/job-openings/"

  result <- parse_nye_postings(fixture, url)

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_nye_postings extracts real positions when present", {
  test_html <- "<div class=\"entry-content\"><h2>K-8 Music Teacher</h2><a href=\"/app.pdf\">Apply</a></div>"
  url <- "https://www.nyeschooldistrict.org/job-openings/"

  result <- parse_nye_postings(test_html, url)

  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "K-8 Music Teacher")
  expect_equal(result$Location, "Nye")
  expect_equal(result$Link, "https://www.nyeschooldistrict.org/app.pdf")
})

test_that("parse_nye_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_nye_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_potomac_postings returns zero rows on fixture with only application prompt", {
  fixture <- paste(readLines(test_path("fixtures", "potomac_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.potomacschoolmontana.us/general-9"

  result <- parse_potomac_postings(fixture, url)

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_potomac_postings extracts real positions when present", {
  test_html <- "<main><h2>Special Education Paraprofessional</h2></main>"
  url <- "https://www.potomacschoolmontana.us/general-9"

  result <- parse_potomac_postings(test_html, url)

  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "Special Education Paraprofessional")
  expect_equal(result$Location, "Potomac")
  expect_equal(result$Link, url)
})

test_that("parse_potomac_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_potomac_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_frontier_postings extracts real positions or returns empty cleanly", {
  fixture <- paste(readLines(test_path("fixtures", "frontier_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.frontierk8.org/District/Jobs/"

  result <- parse_frontier_postings(fixture, url)

  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  if (nrow(result) > 0) {
    expect_true(all(result$Location == "Wolf Point"))
    expect_true(all(is.na(result$Posted_Date) | nzchar(result$Posted_Date)))
    expect_true(all(nzchar(result$Link)))
  }
})

test_that("parse_frontier_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_frontier_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_saco_postings extracts real positions or returns empty cleanly", {
  fixture <- paste(readLines(test_path("fixtures", "saco_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.sacoschools.k12.mt.us/District/Jobs/"

  result <- parse_saco_postings(fixture, url)

  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  if (nrow(result) > 0) {
    expect_true(all(result$Location == "Saco"))
    expect_true(all(is.na(result$Posted_Date) | nzchar(result$Posted_Date)))
    expect_true(all(nzchar(result$Link)))
  }
})

test_that("parse_saco_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_saco_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_ulm_postings extracts real positions or returns empty cleanly", {
  fixture <- paste(readLines(test_path("fixtures", "ulm_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.ulmschools.com/forms--files.html"

  result <- parse_ulm_postings(fixture, url)

  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  if (nrow(result) > 0) {
    expect_true(all(result$Location == "Ulm"))
    expect_true(all(is.na(result$Posted_Date) | nzchar(result$Posted_Date)))
    expect_true(all(nzchar(result$Link)))
  }
})

test_that("parse_ulm_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_ulm_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_montanacity_postings extracts real positions or returns empty cleanly", {
  fixture <- paste(readLines(test_path("fixtures", "montanacity_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.mtcityschool.net/District/Jobs/"

  result <- parse_montanacity_postings(fixture, url)

  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  if (nrow(result) > 0) {
    expect_true(all(result$Location == "Clancy"))
    expect_true(all(is.na(result$Posted_Date) | nzchar(result$Posted_Date)))
    expect_true(all(nzchar(result$Link)))
  }
})

test_that("parse_montanacity_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_montanacity_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_denton_postings extracts real positions or returns empty cleanly", {
  fixture <- paste(readLines(test_path("fixtures", "denton_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.denton.k12.mt.us/District/Jobs/"

  result <- parse_denton_postings(fixture, url)

  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  if (nrow(result) > 0) {
    expect_true(all(result$Location == "Denton"))
    expect_true(all(is.na(result$Posted_Date) | nzchar(result$Posted_Date)))
    expect_true(all(nzchar(result$Link)))
  }
})

test_that("parse_denton_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_denton_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_clancy_postings extracts real positions or returns empty cleanly", {
  fixture <- paste(readLines(test_path("fixtures", "clancy_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.clancyschool.org/District/Jobs/"

  result <- parse_clancy_postings(fixture, url)

  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  if (nrow(result) > 0) {
    expect_true(all(result$Location == "Clancy"))
    expect_true(all(is.na(result$Posted_Date) | nzchar(result$Posted_Date)))
    expect_true(all(nzchar(result$Link)))
  }
})

test_that("parse_clancy_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_clancy_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_bainville_postings extracts certified and classified vacancies from Google Docs HTML fixtures", {
  cert_fixture <- paste(readLines(test_path("fixtures", "bainville_certified.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  class_fixture <- paste(readLines(test_path("fixtures", "bainville_classified.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.bainvilleschool.com/page/employment"

  result <- parse_bainville_postings(cert_fixture, class_fixture, url)

  expect_equal(nrow(result), 7)
  expect_true(all(c("K-12 Art Teacher", "7-12 History", "Elementary Teacher",
                     "Paraprofessional- small intervention group", "Substitute Teachers",
                     "Custodian Subs", "Substitute Bus Drivers") %in% result$Title))
  expect_true(all(result$Location == "Bainville"))
  expect_true(all(result$Link == url))
})

test_that("parse_bainville_postings returns zero rows on empty input", {
  result <- parse_bainville_postings("", "", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_cji_postings extracts vacancies from PDF text fixture", {
  fixture <- paste(readLines(test_path("fixtures", "cji_positions_text.txt"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.cji.k12.mt.us/page/employmentcji"

  result <- parse_cji_postings(fixture, url)

  expect_equal(nrow(result), 5)
  expect_true(all(c("Assistant Activities Coordinator/ Concessions Manager",
                     "Administrative Assistant", "JH/HS MathTeacher",
                     "Custodial Subs", "Substitute Teachers") %in% result$Title))
  expect_true(all(result$Location == "Chester"))
  expect_true(all(result$Link == url))
})

test_that("the CJI openings PDF link is read from the rendered employment page", {
  # Anchors as the rendered page showed them on 2026-11-05.
  links <- data.frame(
    text = c("26-27 Student/Parent Handbook", "SIGN IN", "EMPLOYMENT OPPORTUNITIES", "Here"),
    href = c("https://aptg.co/bQp9pN", "https://cjihawks.id.thrillshare.com/",
             "https://www.cji.k12.mt.us/page/employmentcji", "https://aptg.co/YnhnDQ"),
    context = c("26-27 Student/Parent Handbook", "SIGN IN", "EMPLOYMENT OPPORTUNITIES",
                "Click Here to view current open positions at CJI!"),
    stringsAsFactors = FALSE)
  expect_equal(find_cji_positions_link(links), "https://aptg.co/YnhnDQ")
  expect_true(is.na(find_cji_positions_link(links[1:3, ])))
  # The live check runs it with a browser session.
  call <- resolve_scraper_call("Chester-Joplin-Inverness Public Schools")
  expect_equal(call$fn, "fetch_cji_postings")
  expect_true(call$session)
})

test_that("parse_cji_postings returns zero rows on empty text", {
  result <- parse_cji_postings("", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_marion_postings extracts vacancies from Google Sites HTML fixture", {
  fixture <- paste(readLines(test_path("fixtures", "marion_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://sites.google.com/a/marionschoolmt.com/new-marion-school/district-information/employment"

  result <- parse_marion_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(result$Title[1], "Guest Teacher / Pool of Substitutes")
  expect_equal(result$Location[1], "Marion")
  expect_equal(result$Link[1], url)
})

test_that("parse_marion_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_marion_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})


test_that("parse_lima_postings extracts all 3 positions from live feeds JSON fixture", {
  fixture <- paste(readLines(test_path("fixtures", "lima_live_feeds.json"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_lima_postings(fixture)

  expect_equal(nrow(result), 3)
  expect_equal(result$Title, c(
    "Lead Custodian",
    "Lead Maintenance Worker",
    "Transportation Director/Lead Bus Driver"
  ))
  expect_true(all(result$Location == "Lima"))
  expect_equal(result$Posted_Date, c("2026-10-26", "2026-10-24", "2026-10-20"))
})

test_that("parse_lima_postings returns zero rows on empty or non-matching JSON", {
  result <- parse_lima_postings("", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))

  result2 <- parse_lima_postings('{"live_feeds":[]}')
  expect_equal(nrow(result2), 0)
})


test_that("parse_joliet_postings extracts all 5 active positions from table fixture", {
  fixture <- paste(readLines(test_path("fixtures", "joliet_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.jolietschools.org/district-information/important-clicks/employment-information.html"

  result <- parse_joliet_postings(fixture, url)

  expect_equal(nrow(result), 5)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, c(
    "Bus Route & Bus Route Sub Drivers",
    "Substitute Teachers",
    "Head High School Boys Basketball Coach",
    "Asst High School Girls Basketball Coach",
    "Head High School Boys/Girls Golf Coach"
  ))
  expect_true(all(result$Location == "Joliet"))
  expect_equal(unique(result$Link), "https://www.gojhawks.com/applications/classified.php")
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_joliet_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_joliet_postings("", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))

  result2 <- parse_joliet_postings("<html><body><p>No employment table</p></body></html>", "url")
  expect_equal(nrow(result2), 0)
})

test_that("k12_district_coverage_tiers labels non-direct-API-platform districts Partial, leaves the rest for the caller's Full coalesce", {
  registry <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(
    District = c("AppliTrack District", "SchoolSpring District", "TedK12 District",
                 "TylerPortico District", "Apptegy District", "RedRover District", "Heuristic District"),
    Platform = c("AppliTrack", "SchoolSpring", "TedK12", "TylerPortico", "Apptegy", "RedRoverK12", "SomeHeuristic"),
    stringsAsFactors = FALSE
  ), registry, row.names = FALSE)

  tiers <- k12_district_coverage_tiers(registry)

  # Red Rover is read through its API since edjobs 0.14.0, so it is a direct-API platform too.
  expect_setequal(tiers$District, c("Apptegy District", "Heuristic District"))
  expect_true(all(tiers$Data_Coverage == "Partial"))
  # The 5 real-ATS-platform districts are absent -- callers coalesce a
  # missing match to "Full", the same convention Wyoming's own version uses.
  expect_false(any(c("AppliTrack District", "SchoolSpring District",
                      "TedK12 District", "TylerPortico District", "RedRover District") %in% tiers$District))
})

test_that("k12_district_coverage_tiers against the real registry only ever returns real registered districts", {
  tiers <- k12_district_coverage_tiers(here::here("k12_district_registry.csv"))
  registry <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)

  expect_true(all(tiers$District %in% registry$District))
  expect_true(nrow(tiers) > 0)
  expect_true(nrow(tiers) < nrow(registry))
})

# Real fixture captured 2026-11-02 from rollontigers.org's Current Openings
# page (Finalsite). Manhattan was registered as Tyler Portico, whose tenant
# is only a staff self-service portal with an empty Positions list.
manhattan_fixture <- function() {
  paste(readLines(test_path("fixtures", "manhattan_current-openings_2026-11-02.html"), warn = FALSE, encoding = "UTF-8"),
        collapse = "\n")
}

test_that("parse_manhattan_postings reads the 11 real postings, one PDF link each, without the application forms", {
  url <- "https://www.rollontigers.org/district/employment/current-openings"
  result <- parse_manhattan_postings(manhattan_fixture(), url)
  expect_equal(nrow(result), 11)
  expect_equal(result$Title, c(
    "Long-Term Substitute Teacher: Elementary", "Swing Shift Custodian", "Part-time Swing Shift Custodian",
    "Kitchen Aide-Cafeteria Assistant", "Part-Time Kitchen Aide", "SPED Paraprofessional MS- Part-Time",
    "ASL Intervener", "ASL Interpreter", "SPED Paraprofessional Elementary",
    "Weekend Events: Maintenance and Custodial", "HS Assistant Wrestling Coach"))
  expect_false(any(grepl("Application Form|Substitute Teachers", result$Title)))
  expect_true(all(grepl("^https://www\\.rollontigers\\.org/fs/resource-manager/view/[0-9a-f-]{36}$", result$Link)))
  expect_false(any(duplicated(result$Link)))
  expect_true(all(result$Location == "Manhattan"))
})

test_that("parse_manhattan_postings returns zero rows (not an error) on a page without the openings headings", {
  expect_equal(nrow(parse_manhattan_postings("<html><body><p>No openings</p></body></html>", "url")), 0)
})

test_that("fetch_manhattan_postings fetches and parses a live-shaped response", {
  fixture <- manhattan_fixture()
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )
  expect_equal(nrow(fetch_manhattan_postings()), 11)
})

# Real fixture: document.documentElement.outerHTML captured via a live
# chromote session 2026-11-09 from olneybissellschool.com's Employment page
# (Apptegy; the posting lives in the page-builder JSON embedded in the page).


