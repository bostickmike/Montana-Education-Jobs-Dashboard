# Mock Sys.sleep to no-op so fake-chromote session tests do not sleep 4-5s per scraper:
testthat::local_mocked_bindings(Sys.sleep = function(...) invisible(NULL), .package = "base")

# Real fixture captured 2026-08-07 from
# https://www.livingston.k12.mt.us/apps/pages/index.jsp?uREC_ID=2055955&type=d&pREC_ID=2121638.

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

# Real fixture captured 2026-08-16 from scobeyschools.com/employment.html
# (a Weebly site, only reachable over plain http).

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

# Real fixture captured 2026-08-23 from roy.k12.mt.us (a plain Joomla site).

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

# Real fixture captured 2026-08-24 from tregoschool.org's Employment page
# (a publicly published Google Sites page, same platform as North Star
# above).

# Real fixture captured 2026-08-24 from baker.k12.mt.us's Employment
# page (Finalsite, same platform as Thompson Falls/Hobson/Shepherd
# above; found in the first pass against OPI's own full district list).

# Real fixture captured 2026-08-24 from sites.google.com/view/cutbankjobs
# (Google Sites -- a real candidate left unresolved in an earlier
# session, closed out here).

# Real fixture captured 2026-08-24 from valier.k12.mt.us's Employment
# page (Google Sites).

# Real fixture captured 2026-08-24 from robertsrockets.org's District
# Employment page (a Joomla-based CMS).

# Real fixture captured 2026-08-24 from winnettschool.org's Employment
# page (Squarespace, same platform as Terry above).

# Real fixture captured 2026-08-24 from sites.google.com/a/lincoln.k12.mt.us's
# Employment page (Google Sites, old "sites.google.com/a/domain/..."
# format, publicly reachable unlike Wyola's own sign-in-walled site).

# Real fixture captured 2026-08-24 from independent.k12.mt.us's Job
# Openings page (a real public county district, not private, despite
# the "INDEPENDENT SCHOOL - BILLINGS" OPI-feed label; Google Sites).

# Real fixture captured 2026-08-24 from shepherd.k12.mt.us's Jobs page
# (Finalsite, same platform as Thompson Falls/Hobson above).

# Real fixture captured 2026-08-24 from hyshamschools.com's Jobs page
# (an unbranded CMS, "Lightbox Page" marker-line technique).

# Real fixture captured 2026-08-24 from swanriverschool.org's Human
# Resources page (WordPress, Bigfork, category headers marked in the raw
# HTML rather than separated by real newlines in the rendered text).

# Real fixture captured 2026-08-24 from bigforkschools.org's Employment
# page (WordPress; a real candidate left unresolved in an earlier
# session, closed out here).

# Real fixture captured 2026-08-24 from reedpoint.k12.mt.us's Employment
# page (a publicly published Google Sites page, same platform as North
# Star/Trego above).

# Real fixture captured 2026-08-24 from hobson.k12.mt.us's Employment
# page (Finalsite, same platform as Thompson Falls above).

# Real fixture captured 2026-08-24 from turner.k12.mt.us's Employment
# page (WordPress, same platform as Ramsay above).

# Real fixture captured 2026-08-24 from terryschools.org's Employment
# page (Squarespace, a new platform for this project).

# Real fixture from gallatingatewayschool.com's Employment page (CatapultCMS),
# recaptured 2026-11-04 at its new address, About-Us/Employment/.

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

# Real fixture captured 2026-08-24 from mtbrocktonps.schoolinsites.com's
# Employment page (SCHOOLinSITES CMS, same platform as Miles City above).

# Real fixture captured 2026-08-24 from culbertsonschool.com's Employment
# page (Finalsite).

# Real fixture captured 2026-08-24 from cottonwood57.org's Job Openings
# page (a publicly published Google Sites page, same platform as
# Lincoln/Independent above). Genuinely empty right now.

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-25 from bonner.k12.mt.us's Employment page (Apptegy).

# Real fixture captured 2026-08-25 from Creston School's linked Google
# Doc (plain-text export) of job postings.

# Real fixture captured 2026-08-25 from clintoncougars.com's Employment
# page (an unbranded CMS).

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

# Real fixture captured 2026-08-25 from zurichelementary17.org's
# Employment page (a Wix site, same platform as Augusta above). Genuinely
# empty right now.

# Real fixture captured 2026-08-25 from daytonschool.net's Employment
# page (Upper West Shore School District #33).

test_that("parse_westvalley_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "westvalley_submittable_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://westvalleyschool.submittable.com/submit"

  result <- parse_westvalley_postings(fixture, url)

  expect_equal(nrow(result), 1)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link", "Pay_Min", "Pay_Max", "Pay_Unit", "Pay_Text"))
  expect_equal(result$Title, "Paraprofessional Position")
  expect_equal(result$Location, "Kalispell")
  expect_true(grepl("paraprofessional-position$", result$Link))
  expect_equal(result[, c("Pay_Min", "Pay_Max", "Pay_Unit")], data.frame(Pay_Min = 16.27, Pay_Max = 16.27, Pay_Unit = "hour"))
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

test_that("parse_smithvalley_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "smithvalley_googlesites_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  url <- "https://www.smithvalleyschool.org/employment-opportunities"

  result <- parse_smithvalley_postings(fixture, url)

  expect_equal(nrow(result), 2)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link", "Pay_Min", "Pay_Max", "Pay_Unit", "Pay_Text"))
  expect_equal(result$Title, c("7/8 Grade Girls Basketball Coach", "Substitute Teacher"))
  expect_true(all(result$Location == "Kalispell"))
  expect_true(all(result$Link == url))
  expect_equal(result$Pay_Min, c(NA, 15))          # "All substitutes are paid $15/hour."
  expect_equal(result$Pay_Unit, c(NA, "hour"))
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
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link", "Pay_Min", "Pay_Max", "Pay_Unit", "Pay_Text"))
  expect_true("Girls Basketball Coach" %in% result$Title)
  expect_true("After School Program Teachers/Subs" %in% result$Title)
  expect_equal(unique(result$Location), "Boulder")
  expect_equal(unique(result$Link), url)
  expect_equal(result$Pay_Min[match(c("After School Program Teachers/Subs", "Girls Basketball Coach"), result$Title)], c(18, NA))
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

test_that("parse_judithgap_postings: a panel with a heading is one posting (11-21 capture)", {
  # The body repeats the role ("Immediate Bus Driver Position") and lists requirements; neither is a posting.
  fixture <- paste(readLines(test_path("fixtures", "judithgap_cyberschool_2026-11-21.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  result <- parse_judithgap_postings(fixture)
  expect_equal(result$Title, "Bus Driver")
  expect_equal(result$Posted_Date, "November 16 , 2026")
  expect_equal(result$Location, "Judith Gap")
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

test_that("parse_pleasantvalley_postings errors (not 0 rows) on an empty or different page (2026-11-22)", {
  expect_error(parse_pleasantvalley_postings("<html><body><p>No jobs</p></body></html>", "url"), "no #wsite-content")
  expect_error(parse_pleasantvalley_postings("", "url"), "empty")
  expect_error(parse_pleasantvalley_postings('<div id="wsite-content"><p>x</p></div>', "url"), "no .wsite-content-title")
  zurich <- paste(readLines(test_path("fixtures", "zurich_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_error(parse_pleasantvalley_postings(zurich, "url"), "no #wsite-content")   # a real Wix page
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

test_that("parse_circle_postings errors (not 0 rows) on an empty or different page (2026-11-22)", {
  expect_error(parse_circle_postings("<html><body><p>No jobs</p></body></html>", "url"), "no #wsite-content")
  expect_error(parse_circle_postings("", "url"), "empty")
  zurich <- paste(readLines(test_path("fixtures", "zurich_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  expect_error(parse_circle_postings(zurich, "url"), "no #wsite-content")
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

test_that("k12_district_coverage_tiers gives an OPIOnly district (no board of its own) the OPI-only label", {
  registry <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(District = c("No Board District", "Heuristic District", "AppliTrack District"),
                       Platform = c("OPIOnly", "SomeHeuristic", "AppliTrack"), stringsAsFactors = FALSE),
            registry, row.names = FALSE)
  tiers <- k12_district_coverage_tiers(registry)
  expect_equal(tiers$Data_Coverage[tiers$District == "No Board District"], "Postings via OPI's statewide board")
  expect_equal(tiers$Data_Coverage[tiers$District == "Heuristic District"], "Partial")
  # The real registry: Ulm (its site has no jobs page; retired 2026-11-21).
  real <- k12_district_coverage_tiers(here::here("k12_district_registry.csv"))
  expect_equal(real$Data_Coverage[real$District == "Ulm Public Schools"], "Postings via OPI's statewide board")
})

test_that("k12_district_coverage_tiers against the real registry only ever returns real registered districts", {
  tiers <- k12_district_coverage_tiers(here::here("k12_district_registry.csv"))
  registry <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)

  expect_true(all(tiers$District %in% registry$District))
  expect_true(nrow(tiers) > 0)
  expect_true(nrow(tiers) < nrow(registry))
})

# Real fixture: document.documentElement.outerHTML captured via a live
# chromote session 2026-11-09 from olneybissellschool.com's Employment page
# (Apptegy; the posting lives in the page-builder JSON embedded in the page).

