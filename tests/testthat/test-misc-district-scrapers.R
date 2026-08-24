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

# Real fixtures captured 2026-08-16: trimmed page-builder JSON payloads
# (Conrad, Gardiner, Drummond) or full rendered pages (Westby, Choteau,
# Malta) from each district's own real Employment page.

test_that("parse_conrad_postings extracts all 12 real postings across 3 accordion panels, excluding the stale standalone posting", {
  html <- paste(readLines(test_path("fixtures", "conrad_apptegy_pagedata.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_conrad_postings(html, "url")

  expect_equal(nrow(result), 12)
  expect_equal(sum(result$Location == "Certified Staff Vacancies"), 3)
  expect_equal(sum(result$Location == "Classified & Support Staff Vacancies"), 4)
  expect_equal(sum(result$Location == "Coaching Positions"), 5)
  # Regression: "Substitute Bus Driver" is a real posting but sits outside
  # any accordion panel with a "Revised Posting Date: March 14, 2019" --
  # a years-stale evergreen posting, deliberately excluded.
  expect_false("Substitute Bus Driver" %in% result$Title)
})

test_that("parse_conrad_postings returns zero rows (not an error) when there's no embedded page data", {
  result <- parse_conrad_postings("<html><body>no data here</body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_gardiner_postings extracts 5 real postings correctly split by column position into Certified/Classified", {
  html <- paste(readLines(test_path("fixtures", "gardiner_apptegy_pagedata.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_gardiner_postings(html, "url")

  expect_equal(nrow(result), 5)
  expect_equal(sum(result$Location == "Certified Positions"), 3)
  expect_equal(sum(result$Location == "Classified Positions"), 2)
  expect_true("K-8 Elementary Teacher" %in% result$Title)
  # Regression: the boilerplate application-link buttons in a 3rd,
  # visually-identical two-column node must not be swept in as postings.
  expect_false(any(result$Title %in% c("Certified Application", "Classified Application")))
})

test_that("parse_drummond_postings extracts 8 real postings, using each posting's own <a> link text as Title where present", {
  html <- paste(readLines(test_path("fixtures", "drummond_apptegy_pagedata.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_drummond_postings(html, "url")

  expect_equal(nrow(result), 8)
  expect_equal(sum(result$Location == "Certified"), 3)
  expect_equal(sum(result$Location == "Classified"), 5)
  # Regression: the real title is just the <a> text -- the "/Other Teaching
  # Duties" annotation sitting outside that <a> tag must not be appended.
  expect_true("Half-Time K-12 Librarian" %in% result$Title)
  expect_false(any(grepl("Other Teaching Duties", result$Title)))
  # Regression: application-instruction content after "Contact
  # Superintendent..." must not be swept in as postings.
  expect_false(any(grepl("Letter of Interest|Resume|Transcripts", result$Title)))
})

test_that("parse_westby_postings extracts both real postings via the title-then-compensation-line pattern", {
  html <- paste(readLines(test_path("fixtures", "westby_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  text <- rvest::html_text2(rvest::read_html(html))

  result <- parse_westby_postings(text, "url")

  expect_equal(nrow(result), 2)
  expect_setequal(result$Title, c("Maintenance/Custodian", "Activity Bus Driver / Afternoon Route Bus Driver"))
  expect_true(all(result$Location == "Westby"))
})

test_that("parse_choteau_postings extracts 5 real postings correctly split into Certified/Classified", {
  html <- paste(readLines(test_path("fixtures", "choteau_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  text <- rvest::html_text2(rvest::read_html(html))

  result <- parse_choteau_postings(text, "url")

  expect_equal(nrow(result), 5)
  expect_equal(sum(result$Location == "Certified"), 1)
  expect_equal(sum(result$Location == "Classified"), 4)
})

test_that("parse_malta_postings extracts 11 real postings, skipping genuinely empty categories", {
  html <- paste(readLines(test_path("fixtures", "malta_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  text <- rvest::html_text2(rvest::read_html(html))

  result <- parse_malta_postings(text, "url")

  expect_equal(nrow(result), 11)
  expect_setequal(unique(result$Location), c("Certified", "Classified", "Coaching"))
  # Regression: "Administrative"/"Other Employment" are real, currently
  # empty categories -- must not appear at all, not appear with 0 rows.
  expect_false(any(result$Location %in% c("Administrative", "Other Employment")))
})

# Real fixture captured 2026-08-16 (trimmed page-builder JSON payload) from
# deerlodgeschools.org/page/employment.

test_that("parse_deerlodge_postings extracts all 4 real postings from 2 different real page shapes", {
  html <- paste(readLines(test_path("fixtures", "deerlodge_apptegy_pagedata.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_deerlodge_postings(html, "url")

  expect_equal(nrow(result), 4)
  expect_setequal(result$Title, c(
    "HS Special Ed Aide", "Elementary PE Teacher with a period of Intervention",
    "Special Education Teacher 5th/6th grades", "Bus Driver"
  ))
  # Regression: "Substitutes Wanted" is a standing recruiting card, not a
  # specific posting -- must not appear as a Title.
  expect_false("Substitutes Wanted" %in% result$Title)
  # Regression: "Certified Teacher" is the card's generic heading, not the
  # real title -- the real title sits inside the card's own body text.
  expect_false("Certified Teacher" %in% result$Title)
})

test_that("parse_deerlodge_postings returns zero rows (not an error) when there's no embedded page data", {
  result <- parse_deerlodge_postings("<html><body>no data here</body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

# Real fixture captured 2026-08-16 from townsend.k12.mt.us/page/employment.

test_that("parse_townsend_postings extracts all 5 real postings, split into Internal/External", {
  html <- paste(readLines(test_path("fixtures", "townsend_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  text <- rvest::html_text2(rvest::read_html(html))

  result <- parse_townsend_postings(text, "url")

  expect_equal(nrow(result), 5)
  expect_equal(sum(result$Location == "Internal"), 1)
  expect_equal(sum(result$Location == "External"), 4)
  expect_true("HS Student Council" %in% result$Title)
  # Regression: the full "ATHLETIC DIRECTOR" job-description document that
  # follows is reference material for the "HS/MS Activities Director"
  # posting already captured, not a second real posting.
  expect_false(any(grepl("ATHLETIC DIRECTOR|REPORTS TO|FLSA", result$Title)))
})

test_that("parse_townsend_postings returns zero rows (not an error) when there's no Job Vacancies header", {
  result <- parse_townsend_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-23 from hlpschools.k12.mt.us/page/jobs.

test_that("parse_hayslodgepole_postings extracts the 5 real postings, excluding interleaved benefits/application prose", {
  text <- paste(readLines(test_path("fixtures", "apptegy_hayslodgepole_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_hayslodgepole_postings(text, "url")

  expect_equal(nrow(result), 5)
  expect_equal(sum(result$Location == "Certified"), 2)
  expect_equal(sum(result$Location == "Classified"), 3)
  expect_true(all(c("JH/HS Art Teacher", "Paraprofessional X2", "Substitute Teachers",
                     "Substitute Bus Drivers", "High School Boys Head Basketball Coach") %in% result$Title))
  # Regression: "$5000.00 Sign-On Bonus" is short and unpunctuated enough
  # to otherwise pass Wolf Point's own title-shape filter unchanged.
  expect_false(any(grepl("\\$", result$Title)))
})

test_that("parse_hayslodgepole_postings returns zero rows (not an error) when there's no Certified Positions header", {
  result <- parse_hayslodgepole_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

# Real fixture captured 2026-08-23 from plevnacougars.com's Employment page.

test_that("parse_plevna_postings extracts all 10 real postings across 4 real category headers", {
  text <- paste(readLines(test_path("fixtures", "apptegy_plevna_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_plevna_postings(text, "url")

  expect_equal(nrow(result), 10)
  expect_equal(sum(result$Location == "Certified Teaching Positions"), 2)
  expect_equal(sum(result$Location == "Basketball Coaching Position"), 2)
  expect_equal(sum(result$Location == "Track Coaching Positions"), 4)
  expect_equal(sum(result$Location == "Substitutes"), 2)
  # Regression: the benefits copy that immediately follows the last
  # posting must not be swept in as a positions.
  expect_false(any(grepl("Health Insurance|HSA|Life Insurance", result$Title)))
})

test_that("parse_plevna_postings returns zero rows (not an error) when there's no Positions Open header", {
  result <- parse_plevna_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

# Real fixture captured 2026-08-23 from sunburst.k12.mt.us/page/employment-opportunities.

test_that("parse_sunburst_postings extracts the 4 real flat-list postings", {
  text <- paste(readLines(test_path("fixtures", "apptegy_sunburst_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_sunburst_postings(text, "url")

  expect_equal(nrow(result), 4)
  expect_true(all(c("Cook", "Guidance Counselor", "Substitute Teachers", "Bus Drivers") %in% result$Title))
  expect_true(all(result$Location == "Sunburst"))
})

test_that("parse_sunburst_postings returns zero rows (not an error) when there's no jobs-open header", {
  result <- parse_sunburst_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

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

test_that("parse_northstar_postings extracts the 2 real postings under colon-headers, excluding the 2 genuinely-empty non-colon categories", {
  html <- paste(readLines(test_path("fixtures", "northstar_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_northstar_postings(html, "url")

  expect_equal(nrow(result), 2)
  expect_equal(result$Title[result$Location == "Substitutes"], "Substitute Teachers")
  expect_equal(result$Title[result$Location == "Transportation"], "Bus Drivers")
  # Regression: "Elementary Positions"/"MS/HS Positions" have no colon and
  # only a broken job-board-widget placeholder line beneath them.
  expect_false(any(grepl("Search North Star", result$Title)))
})

test_that("parse_northstar_postings returns zero rows (not an error) when there's no positions-open header", {
  result <- parse_northstar_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_northstar_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "northstar_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_northstar_postings()

  expect_equal(nrow(result), 2)
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

test_that("fetch_conrad_postings drives a chromote session, reads outerHTML, and parses the embedded page data", {
  html <- paste(readLines(test_path("fixtures", "conrad_apptegy_pagedata.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  session <- fake_chromote_session(html)

  result <- fetch_conrad_postings(session)

  expect_equal(nrow(result), 12)
})

test_that("fetch_gardiner_postings drives a chromote session, reads outerHTML, and parses the embedded page data", {
  html <- paste(readLines(test_path("fixtures", "gardiner_apptegy_pagedata.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  session <- fake_chromote_session(html)

  result <- fetch_gardiner_postings(session)

  expect_equal(nrow(result), 5)
})

test_that("fetch_drummond_postings drives a chromote session, reads outerHTML, and parses the embedded page data", {
  html <- paste(readLines(test_path("fixtures", "drummond_apptegy_pagedata.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  session <- fake_chromote_session(html)

  result <- fetch_drummond_postings(session)

  expect_equal(nrow(result), 8)
})

test_that("fetch_westby_postings drives a chromote session and parses its real rendered text", {
  html <- paste(readLines(test_path("fixtures", "westby_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  text <- rvest::html_text2(rvest::read_html(html))
  session <- fake_chromote_session(text)

  result <- fetch_westby_postings(session)

  expect_equal(nrow(result), 2)
})

test_that("fetch_choteau_postings drives a chromote session and parses its real rendered text", {
  html <- paste(readLines(test_path("fixtures", "choteau_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  text <- rvest::html_text2(rvest::read_html(html))
  session <- fake_chromote_session(text)

  result <- fetch_choteau_postings(session)

  expect_equal(nrow(result), 5)
})

test_that("fetch_malta_postings drives a chromote session and parses its real rendered text", {
  html <- paste(readLines(test_path("fixtures", "malta_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  text <- rvest::html_text2(rvest::read_html(html))
  session <- fake_chromote_session(text)

  result <- fetch_malta_postings(session)

  expect_equal(nrow(result), 11)
})

test_that("fetch_deerlodge_postings drives a chromote session, reads outerHTML, and parses the embedded page data", {
  html <- paste(readLines(test_path("fixtures", "deerlodge_apptegy_pagedata.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  session <- fake_chromote_session(html)

  result <- fetch_deerlodge_postings(session)

  expect_equal(nrow(result), 4)
})

test_that("fetch_townsend_postings drives a chromote session and parses its real rendered text", {
  html <- paste(readLines(test_path("fixtures", "townsend_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  text <- rvest::html_text2(rvest::read_html(html))
  session <- fake_chromote_session(text)

  result <- fetch_townsend_postings(session)

  expect_equal(nrow(result), 5)
})

test_that("fetch_hayslodgepole_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_hayslodgepole_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_hayslodgepole_postings(session)

  expect_equal(nrow(result), 5)
})

test_that("fetch_plevna_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_plevna_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_plevna_postings(session)

  expect_equal(nrow(result), 10)
})

test_that("fetch_sunburst_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_sunburst_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_sunburst_postings(session)

  expect_equal(nrow(result), 4)
})

test_that("fetch_apptegy_k12_postings returns an empty frame (not an error) when no session factory is available", {
  result <- fetch_apptegy_k12_postings(chromote_session_factory = NULL)
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link", "District"))
})

test_that("fetch_apptegy_k12_postings shares one session across all 13 districts and tags each row with its real District", {
  wp_text <- paste(readLines(test_path("fixtures", "apptegy_wolfpoint_rendered.txt"), warn = FALSE), collapse = "\n")
  pw_text <- paste(readLines(test_path("fixtures", "apptegy_plentywood_rendered.txt"), warn = FALSE), collapse = "\n")
  conrad_html <- paste(readLines(test_path("fixtures", "conrad_apptegy_pagedata.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  gardiner_html <- paste(readLines(test_path("fixtures", "gardiner_apptegy_pagedata.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  drummond_html <- paste(readLines(test_path("fixtures", "drummond_apptegy_pagedata.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  deerlodge_html <- paste(readLines(test_path("fixtures", "deerlodge_apptegy_pagedata.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  westby_text <- rvest::html_text2(rvest::read_html(paste(readLines(test_path("fixtures", "westby_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")))
  choteau_text <- rvest::html_text2(rvest::read_html(paste(readLines(test_path("fixtures", "choteau_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")))
  malta_text <- rvest::html_text2(rvest::read_html(paste(readLines(test_path("fixtures", "malta_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")))
  townsend_text <- rvest::html_text2(rvest::read_html(paste(readLines(test_path("fixtures", "townsend_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")))
  hlp_text <- paste(readLines(test_path("fixtures", "apptegy_hayslodgepole_rendered.txt"), warn = FALSE), collapse = "\n")
  plevna_text <- paste(readLines(test_path("fixtures", "apptegy_plevna_rendered.txt"), warn = FALSE), collapse = "\n")
  sunburst_text <- paste(readLines(test_path("fixtures", "apptegy_sunburst_rendered.txt"), warn = FALSE), collapse = "\n")

  # Same fake session serves every district's fetch, real URL routing comes
  # from each fetch_*_postings()'s own default url= argument -- this fake
  # returns each district's real fixture content by checking the navigated
  # URL, the same pattern the original Wolf Point/Plentywood-only version
  # of this test already used.
  navigated_url <- NULL
  session_factory <- function() {
    list(
      Page = list(
        navigate = function(url) navigated_url <<- url,
        loadEventFired = function(wait_ = TRUE, timeout_ = 30) invisible(NULL)
      ),
      Runtime = list(
        evaluate = function(expr) {
          value <- if (grepl("wolfpoint", navigated_url)) wp_text
          else if (grepl("plentywood", navigated_url)) pw_text
          else if (grepl("conradschools", navigated_url)) conrad_html
          else if (grepl("gardiner", navigated_url)) gardiner_html
          else if (grepl("drummondschool", navigated_url)) drummond_html
          else if (grepl("deerlodgeschools", navigated_url)) deerlodge_html
          else if (grepl("westbyschool", navigated_url)) westby_text
          else if (grepl("choteauschools", navigated_url)) choteau_text
          else if (grepl("maltaschools", navigated_url)) malta_text
          else if (grepl("townsend", navigated_url)) townsend_text
          else if (grepl("hlpschools", navigated_url)) hlp_text
          else if (grepl("plevnacougars", navigated_url)) plevna_text
          else if (grepl("sunburst", navigated_url)) sunburst_text
          else ""
          list(result = list(value = value))
        }
      ),
      close = function() invisible(NULL)
    )
  }

  result <- fetch_apptegy_k12_postings(chromote_session_factory = session_factory)

  expect_equal(nrow(result), 19 + 4 + 12 + 2 + 5 + 5 + 11 + 8 + 4 + 5 + 5 + 10 + 4)
  expect_equal(sum(result$District == "Wolf Point Public Schools"), 19)
  expect_equal(sum(result$District == "Plentywood Public Schools"), 4)
  expect_equal(sum(result$District == "Conrad Public Schools"), 12)
  expect_equal(sum(result$District == "Westby School District 3"), 2)
  expect_equal(sum(result$District == "Choteau School District"), 5)
  expect_equal(sum(result$District == "Gardiner Public Schools"), 5)
  expect_equal(sum(result$District == "Malta Public Schools"), 11)
  expect_equal(sum(result$District == "Drummond Public Schools"), 8)
  expect_equal(sum(result$District == "Deer Lodge School District #1"), 4)
  expect_equal(sum(result$District == "Townsend School District"), 5)
  expect_equal(sum(result$District == "Hays-Lodge Pole School District"), 5)
  expect_equal(sum(result$District == "Plevna School District #55"), 10)
  expect_equal(sum(result$District == "Sunburst Schools"), 4)
})
