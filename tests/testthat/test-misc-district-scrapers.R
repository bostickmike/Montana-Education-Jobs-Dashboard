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

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-23 from beltschool.com's Employment Opportunities page.

test_that("parse_belt_postings extracts the 3 real Classified postings, excluding the trailing prose paragraph and the empty Certified category", {
  text <- paste(readLines(test_path("fixtures", "apptegy_belt_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_belt_postings(text, "url")

  expect_equal(nrow(result), 3)
  expect_true(all(result$Location == "Classified Openings"))
  expect_true(all(c("Facility Maintenance- Full-time or Part-time", "Night Custodian- Full-time or Part Time",
                     "Day Custodian- Full-time or Part-Time") %in% result$Title))
  expect_false(any(grepl("also has classified openings", result$Title)))
})

test_that("parse_belt_postings returns zero rows (not an error) when there's no Certified Openings header", {
  result <- parse_belt_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

# Real fixture captured 2026-08-23 from bssd72.org's Employment Opportunities page.

test_that("parse_bigsky_postings extracts the 4 real postings across 2 real bare (no-colon) category headers", {
  text <- paste(readLines(test_path("fixtures", "apptegy_bigsky_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_bigsky_postings(text, "url")

  expect_equal(nrow(result), 4)
  expect_equal(sum(result$Location == "Teaching"), 2)
  expect_equal(sum(result$Location == "District Staff"), 2)
  expect_true(all(c("High School Science Teacher", "Elementary Curriculum", "Bus Drivers", "Guest Teachers") %in% result$Title))
})

test_that("parse_bigsky_postings returns zero rows (not an error) when there's no Current Openings header", {
  result <- parse_bigsky_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

# Real fixture captured 2026-08-23 from melstonepublicschools.org's
# Employment Opportunities page (a repeated "Title:"/"Description:"/
# "Benefits:" field-label card layout).

test_that("parse_melstone_postings extracts all 4 real postings via the Title: field marker", {
  text <- paste(readLines(test_path("fixtures", "apptegy_melstone_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_melstone_postings(text, "url")

  expect_equal(nrow(result), 4)
  expect_true(all(c("Head Cook", "Head Maintenance/Custodian", "Substitute Route Bus Drivers/Activity Drivers",
                     "Substitute Teachers, Kitchen Staff, Custodian") %in% result$Title))
  expect_true(all(result$Location == "Melstone"))
})

test_that("parse_melstone_postings returns zero rows (not an error) when there's no Title: field marker", {
  result <- parse_melstone_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

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

test_that("fetch_belt_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_belt_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_belt_postings(session)

  expect_equal(nrow(result), 3)
})

test_that("fetch_bigsky_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_bigsky_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_bigsky_postings(session)

  expect_equal(nrow(result), 4)
})

test_that("fetch_melstone_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_melstone_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_melstone_postings(session)

  expect_equal(nrow(result), 4)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-23 from roundup.k12.mt.us's Employment page.

test_that("parse_roundup_postings extracts all 13 real postings across 3 real bare category headers", {
  text <- paste(readLines(test_path("fixtures", "apptegy_roundup_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_roundup_postings(text, "url")

  expect_equal(nrow(result), 13)
  expect_equal(sum(result$Location == "Certified Positions"), 1)
  expect_equal(sum(result$Location == "Extracurricular Positions"), 5)
  expect_equal(sum(result$Location == "Classified Positions and Substitutes"), 7)
  expect_false(any(grepl("Required Application Materials|Resume|Transcripts", result$Title)))
})

test_that("parse_roundup_postings returns zero rows (not an error) when there's no Open Positions header", {
  result <- parse_roundup_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_roundup_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_roundup_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_roundup_postings(session)

  expect_equal(nrow(result), 13)
})

# Real fixture captured 2026-08-23 from whitesulphur.k12.mt.us's Employment page.

test_that("parse_wss_postings extracts the 5 real flat-list postings", {
  text <- paste(readLines(test_path("fixtures", "apptegy_wss_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_wss_postings(text, "url")

  expect_equal(nrow(result), 5)
  expect_true(all(c("Counselor", "Secretary", "Bus Driver", "Music") %in% result$Title))
  expect_true(all(result$Location == "White Sulphur Springs"))
})

test_that("parse_wss_postings returns zero rows (not an error) when there's no Current Openings header", {
  result <- parse_wss_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_wss_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_wss_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_wss_postings(session)

  expect_equal(nrow(result), 5)
})

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

test_that("parse_centerville_postings extracts the 4 real flat-list postings", {
  text <- paste(readLines(test_path("fixtures", "apptegy_centerville_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_centerville_postings(text, "url")

  expect_equal(nrow(result), 4)
  expect_true(all(c("Shop/Vo-Ag Teacher", "Colony Aide", "Assistant HS Football Coach",
                     "Assistant HS Girls Flag Football Coach") %in% result$Title))
  expect_true(all(result$Location == "Sand Coulee"))
})

test_that("parse_centerville_postings returns zero rows (not an error) when there's no Employment Opportunities header", {
  result <- parse_centerville_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_centerville_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_centerville_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_centerville_postings(session)

  expect_equal(nrow(result), 4)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-23 from arleeschools.org's Employment Opportunities page.

test_that("parse_arlee_postings extracts all 8 real postings from the 3-column Job Description/Application/Closing Date table", {
  text <- paste(readLines(test_path("fixtures", "apptegy_arlee_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_arlee_postings(text, "url")

  expect_equal(nrow(result), 8)
  expect_true(all(c(".5 FTE Custodian (School year/10 months)", "Elementary Teacher (6th grade)",
                     "Paraprofessionals", "HS Math Teacher (1 FTE)", "Substitute Bus Driver") %in% result$Title))
  expect_true(all(result$Location == "Arlee"))
  expect_false(any(grepl("^Classified Application$|^Certified Application$|^Until Filled$", result$Title)))
})

test_that("parse_arlee_postings returns zero rows (not an error) when there's no Job Description table header", {
  result <- parse_arlee_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_arlee_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_arlee_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_arlee_postings(session)

  expect_equal(nrow(result), 8)
})

# Real fixture captured 2026-08-23 from chinookschools.org's Employment page.

test_that("parse_chinook_postings extracts all 7 real postings across 3 real category headers, excluding embedded pay-range prose", {
  text <- paste(readLines(test_path("fixtures", "apptegy_chinook_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_chinook_postings(text, "url")

  expect_equal(nrow(result), 7)
  expect_equal(sum(result$Location == "CURRENT TEACHING AND AIDE OPENINGS"), 1)
  expect_equal(sum(result$Location == "ADDITIONAL/EXTRA CURRICULAR OPENINGS"), 1)
  expect_equal(sum(result$Location == "CUSTODIAL, KITCHEN, AND OTHER OPENINGS"), 5)
  expect_false(any(grepl("Pay Range|Experience|\\$", result$Title)))
})

test_that("parse_chinook_postings returns zero rows (not an error) when there's no real category header", {
  result <- parse_chinook_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_chinook_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_chinook_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_chinook_postings(session)

  expect_equal(nrow(result), 7)
})

# Real fixture captured 2026-08-23 from darby.k12.mt.us's Employment page.

test_that("parse_darby_postings extracts the 6 real flat-list postings", {
  text <- paste(readLines(test_path("fixtures", "apptegy_darby_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_darby_postings(text, "url")

  expect_equal(nrow(result), 6)
  expect_true(all(c("Substitute Bus Driver", "Substitute Teacher", "Part-Time Spanish Teacher",
                     "JH Volleyball Coaches(1)", "Transportation Supervisor or Technician", "Nigh Custodian") %in% result$Title))
  expect_true(all(result$Location == "Darby"))
})

test_that("parse_darby_postings returns zero rows (not an error) when there's no Open Positions header", {
  result <- parse_darby_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_darby_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_darby_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_darby_postings(session)

  expect_equal(nrow(result), 6)
})

# Real fixture captured 2026-08-23 from dbps.k12.mt.us's Careers page.

test_that("parse_dutton_postings extracts the 2 real postings, excluding their prose descriptions", {
  text <- paste(readLines(test_path("fixtures", "apptegy_dutton_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_dutton_postings(text, "url")

  expect_equal(nrow(result), 2)
  expect_equal(result$Title, c("Route and Relief School Bus Drivers", "Substitute Teachers"))
  expect_true(all(result$Location == "Dutton"))
})

test_that("parse_dutton_postings returns zero rows (not an error) when there's no Employment Opportunities: header", {
  result <- parse_dutton_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_dutton_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_dutton_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_dutton_postings(session)

  expect_equal(nrow(result), 2)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from jobs.redroverk12.com/org/2261 (St. Ignatius
# School District's Red Rover Hiring board).

test_that("parse_stignatius_postings extracts the 6 real postings, excluding the 2 evergreen application-form placeholders", {
  text <- paste(readLines(test_path("fixtures", "stignatius_jobs_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_stignatius_postings(text, "url")

  expect_equal(nrow(result), 6)
  expect_true(all(c("Paraprofessional - Elem, Middle & High Positions Available!", "Title I", "Salish Teacher",
                     "Elementary Education 2026-2027", "Special Ed K-12", "Substitute Teacher") %in% result$Title))
  expect_equal(result$Location[result$Title == "Salish Teacher"], "St. Ignatius High School")
  expect_true(is.na(result$Location[result$Title == "Special Ed K-12"]))
  expect_false(any(result$Title %in% c("Classified Application", "Certified Application", "Volunteer Application")))
})

test_that("parse_stignatius_postings returns zero rows (not an error) when there's no 'Found N job openings' header", {
  result <- parse_stignatius_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_stignatius_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "stignatius_jobs_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_stignatius_postings(session)

  expect_equal(nrow(result), 6)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from stanfordmtschool.com's Job Openings page.

test_that("parse_stanford_postings extracts the 6 real postings, excluding the 2 evergreen application-form placeholders", {
  text <- paste(readLines(test_path("fixtures", "apptegy_stanford_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_stanford_postings(text, "url")

  expect_equal(nrow(result), 6)
  expect_true(all(c("Business Manager/District Clerk", "School Secretary", "CTE – Agricultural Education",
                     "K-8 Elementary Teacher", "Bus Drivers- Non CDL & CDL", "Substitute Teachers") %in% result$Title))
  expect_true(all(result$Location == "Stanford"))
  expect_false(any(result$Title %in% c("Certified Application", "Classified Application")))
})

test_that("parse_stanford_postings returns zero rows (not an error) when there's no Job Openings header", {
  result <- parse_stanford_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_stanford_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_stanford_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_stanford_postings(session)

  expect_equal(nrow(result), 6)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from loloschools.org's Employment page.

test_that("parse_lolo_postings extracts the 4 real prose postings, handling both colon- and period-delimited titles", {
  text <- paste(readLines(test_path("fixtures", "apptegy_lolo_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_lolo_postings(text, "url")

  expect_equal(nrow(result), 4)
  expect_true(all(c("General Music & Band Long Term Substitute", "Foreign Language Teacher (.33)",
                     "Paraprofessional position(s)", "Midday Aide position") %in% result$Title))
  expect_true(all(result$Location == "Lolo"))
})

test_that("parse_lolo_postings returns zero rows (not an error) when there's no CURRENT OPENING/S: header", {
  result <- parse_lolo_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_lolo_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_lolo_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_lolo_postings(session)

  expect_equal(nrow(result), 4)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from froidschool.com's Open Positions/Applications
# page.

test_that("parse_froid_postings extracts the 3 real postings, excluding the stray bare-year artifact line", {
  text <- paste(readLines(test_path("fixtures", "apptegy_froid_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_froid_postings(text, "url")

  expect_equal(nrow(result), 3)
  expect_true(all(c("Counselor", "Substitute Teachers", "Substitute Bus Driver") %in% result$Title))
  expect_true(all(result$Location == "Froid"))
  expect_false(any(grepl("^[0-9]{4}-[0-9]{4}$", result$Title)))
})

test_that("parse_froid_postings returns zero rows (not an error) when there's no year-suffixed Open Positions header", {
  result <- parse_froid_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_froid_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_froid_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_froid_postings(session)

  expect_equal(nrow(result), 3)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from huntley.k12.mt.us's Employment Opportunities
# page (Worden).

test_that("parse_huntley_postings extracts the 5 real postings, excluding the long marketing-copy paragraph", {
  text <- paste(readLines(test_path("fixtures", "apptegy_huntley_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_huntley_postings(text, "url")

  expect_equal(nrow(result), 5)
  expect_true(all(c("K-6 Music Teacher", "Full Time Custodian", "Substitutes",
                     "Junior High Wrestling Coach") %in% result$Title))
  expect_true(all(result$Location == "Huntley Project"))
})

test_that("parse_huntley_postings returns zero rows (not an error) when there's no Open Positions header", {
  result <- parse_huntley_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_huntley_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_huntley_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_huntley_postings(session)

  expect_equal(nrow(result), 5)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from parkcityschools.org's Employment information
# page, found via its own clientWorkStateTemp menu tree (no plain nav
# link).

test_that("parse_parkcity_postings extracts the 2 real postings from the 3-column Job Title/Type/Description table", {
  text <- paste(readLines(test_path("fixtures", "apptegy_parkcity_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_parkcity_postings(text, "url")

  expect_equal(nrow(result), 2)
  expect_true(all(c("Substitute Teachers", "Various Substitutes") %in% result$Title))
  expect_true(all(result$Location == "Park City"))
})

test_that("parse_parkcity_postings returns zero rows (not an error) when there's no EMPLOYMENT OPPORTUNITIES header", {
  result <- parse_parkcity_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_parkcity_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_parkcity_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_parkcity_postings(session)

  expect_equal(nrow(result), 2)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from alberton.k12.mt.us's Employment Opportunities
# page (first pass against OPI's own full district list).

test_that("parse_alberton_postings extracts all 6 real postings across the 3 hybrid shapes on this page", {
  text <- paste(readLines(test_path("fixtures", "apptegy_alberton_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_alberton_postings(text, "url")

  expect_equal(nrow(result), 6)
  expect_true(all(c("Assistant Cook", "Assistant Varsity Boys' Basketball", "Assistant Varsity Volleyball",
                     "JH Volleyball", "JH Girls' Basketball", "Substitute Teachers") %in% result$Title))
  expect_true(all(result$Location == "Alberton"))
})

test_that("parse_alberton_postings returns zero rows (not an error) when there's no real marker", {
  result <- parse_alberton_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_alberton_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_alberton_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_alberton_postings(session)

  expect_equal(nrow(result), 6)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from dillonschools.org's Employment Opportunities
# page.

test_that("parse_dillon_postings extracts the 3 real flat-list postings", {
  text <- paste(readLines(test_path("fixtures", "apptegy_dillon_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_dillon_postings(text, "url")

  expect_equal(nrow(result), 3)
  expect_true(all(c("Para Professional Vacancy Announcement", "Food Service- Baker",
                     "Substitute/Guest Teachers Needed") %in% result$Title))
  expect_true(all(result$Location == "Dillon"))
})

test_that("parse_dillon_postings returns zero rows (not an error) when there's no Employment Opportunities header", {
  result <- parse_dillon_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_dillon_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_dillon_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_dillon_postings(session)

  expect_equal(nrow(result), 3)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from ennisschools.org's Job Opportunities page.

test_that("parse_ennis_postings extracts all 5 real postings via the 'Reports to:' marker line and the Coaching flat list", {
  text <- paste(readLines(test_path("fixtures", "apptegy_ennis_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_ennis_postings(text, "url")

  expect_equal(nrow(result), 5)
  expect_true(all(c("Assistant Cook", "Custodian", "High School Wrestling Head Coach",
                     "Seventh Grade Volleyball", "Sixth Grade Volleyball") %in% result$Title))
  expect_true(all(result$Location == "Ennis"))
})

test_that("parse_ennis_postings returns zero rows (not an error) when there's no real marker", {
  result <- parse_ennis_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_ennis_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_ennis_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_ennis_postings(session)

  expect_equal(nrow(result), 5)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from columbuscougars.com's District Employment
# page, found via its own clientWorkStateTemp menu tree.

test_that("parse_columbus_postings extracts the 2 real postings from the 2-column Opportunity/Description table", {
  text <- paste(readLines(test_path("fixtures", "apptegy_columbus_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_columbus_postings(text, "url")

  expect_equal(nrow(result), 2)
  expect_true(all(c("Facilities Technician", "Substitute") %in% result$Title))
  expect_true(all(result$Location == "Columbus"))
})

test_that("parse_columbus_postings returns zero rows (not an error) when there's no Employment Opportunities header", {
  result <- parse_columbus_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_columbus_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_columbus_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_columbus_postings(session)

  expect_equal(nrow(result), 2)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from stregisschool.org's Employment page.

test_that("parse_stregis_postings extracts all 14 real postings across 4 sections, splitting 2 'Title - description' combined lines", {
  text <- paste(readLines(test_path("fixtures", "apptegy_stregis_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_stregis_postings(text, "url")

  expect_equal(nrow(result), 14)
  expect_true(all(c("JH Football: Head Coach", "FFA Advisor", "Bus Route Driver", "Groundskeeper",
                     "Substitute Bus Driver") %in% result$Title))
  expect_true(all(result$Location == "St Regis"))
})

test_that("parse_stregis_postings returns zero rows (not an error) when there's no OPEN POSITIONS header", {
  result <- parse_stregis_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_stregis_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_stregis_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_stregis_postings(session)

  expect_equal(nrow(result), 14)
})

# Real fixture: document.body.innerText captured via a live chromote
# session 2026-08-24 from florencecarlton.org's Available Positions
# page, found via its own "CLICK HERE TO VIEW AVAILABLE POSITIONS" link.

test_that("parse_florencecarlton_postings extracts all 9 real postings via the ALL-CAPS title-shape heuristic, merging the 2-line custodian posting", {
  text <- paste(readLines(test_path("fixtures", "apptegy_florencecarlton_rendered.txt"), warn = FALSE), collapse = "\n")

  result <- parse_florencecarlton_postings(text, "url")

  expect_equal(nrow(result), 9)
  expect_true("HIGH SCHOOL COUNSELOR" %in% result$Title)
  expect_true("SEEKING TWO (2) EVENING SHIFT SCHOOL CUSTODIANS AND ONE (1) MID SHIFT SCHOOL CUSTODIAN" %in% result$Title)
  expect_true(all(c("Substitute Teachers", "Substitute Custodians") %in% result$Title))
  expect_true(all(result$Location == "Florence-Carlton"))
  expect_false(any(grepl("^PLEASE COMPLETE", result$Title)))
})

test_that("parse_florencecarlton_postings returns zero rows (not an error) when there's no real start marker", {
  result <- parse_florencecarlton_postings("Just some regular page text with no postings.", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_florencecarlton_postings drives a chromote session and parses its real rendered text", {
  text <- paste(readLines(test_path("fixtures", "apptegy_florencecarlton_rendered.txt"), warn = FALSE), collapse = "\n")
  session <- fake_chromote_session(text)

  result <- fetch_florencecarlton_postings(session)

  expect_equal(nrow(result), 9)
})

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

test_that("parse_trego_postings extracts the 2 real postings under the flat 'Jobs Available' header", {
  html <- paste(readLines(test_path("fixtures", "trego_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_trego_postings(html, "url")

  expect_equal(nrow(result), 2)
  expect_true(all(c("Snow Removal", "K-1 Teacher") %in% result$Title))
  expect_true(all(result$Location == "Trego"))
})

test_that("parse_trego_postings returns zero rows (not an error) when there's no 'Jobs Available' header", {
  result <- parse_trego_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_trego_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "trego_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_trego_postings()

  expect_equal(nrow(result), 2)
})

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

test_that("parse_cutbank_postings extracts the 5 real postings under the date-suffixed 'Open Positions' header", {
  html <- paste(readLines(test_path("fixtures", "cutbank_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_cutbank_postings(html, "url")

  expect_equal(nrow(result), 5)
  expect_true(all(c("Health & Wellness Advisor", "Middle School Boys Basketball Coach",
                     "Route Bus Driver", "School Lunch Worker") %in% result$Title))
  expect_true(all(result$Location == "Cut Bank"))
})

test_that("parse_cutbank_postings returns zero rows (not an error) when there's no date-suffixed Open Positions header", {
  result <- parse_cutbank_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_cutbank_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "cutbank_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_cutbank_postings()

  expect_equal(nrow(result), 5)
})

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

test_that("parse_valier_postings extracts the 1 real posting, excluding the 2 empty 'None at this time' categories", {
  html <- paste(readLines(test_path("fixtures", "valier_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_valier_postings(html, "url")

  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "Part-Time Cook")
  expect_equal(result$Location, "Valier")
})

test_that("parse_valier_postings returns zero rows (not an error) when there's no real marker sentence", {
  result <- parse_valier_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_valier_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "valier_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_valier_postings()

  expect_equal(nrow(result), 1)
})

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

test_that("parse_lincoln_postings extracts the 1 real posting between the application link and the closing sentence", {
  html <- paste(readLines(test_path("fixtures", "lincoln_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_lincoln_postings(html, "url")

  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "Para Professional Job Opening")
  expect_equal(result$Location, "Lincoln")
})

test_that("parse_lincoln_postings returns zero rows (not an error) when there's no CLICK HERE FOR APPLICATION line", {
  result <- parse_lincoln_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_lincoln_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "lincoln_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_lincoln_postings()

  expect_equal(nrow(result), 1)
})

# Real fixture captured 2026-08-24 from independent.k12.mt.us's Job
# Openings page (a real public county district, not private, despite
# the "INDEPENDENT SCHOOL - BILLINGS" OPI-feed label; Google Sites).

test_that("parse_independent_postings extracts the 3 real ALL-CAPS-title postings", {
  html <- paste(readLines(test_path("fixtures", "independent_job-openings.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_independent_postings(html, "url")

  expect_equal(nrow(result), 3)
  expect_true(all(c("SPECIAL EDUCATION TEACHER", "SCHOOL COUNSELOR",
                     "SUBSTITUTES WANTED - POSITIONS AVAILABLE") %in% result$Title))
  expect_true(all(result$Location == "Independent"))
})

test_that("parse_independent_postings returns zero rows (not an error) when there's no JOB OPENINGS header", {
  result <- parse_independent_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_independent_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "independent_job-openings.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_independent_postings()

  expect_equal(nrow(result), 3)
})

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

test_that("parse_swanriver_postings extracts the 5 real postings across 3 non-empty categories, excluding the 3 empty ones", {
  html <- paste(readLines(test_path("fixtures", "swanriver_human-resources.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_swanriver_postings(html, "url")

  expect_equal(nrow(result), 5)
  expect_equal(sum(result$Location == "Substitute Positions"), 3)
  expect_equal(sum(result$Location == "Aide Positions"), 1)
  expect_equal(sum(result$Location == "Classified Positions"), 1)
  expect_true(all(c("Teachers", "Paraeducators", "Hot lunch helpers") %in% result$Title[result$Location == "Substitute Positions"]))
  expect_true("Paraprofessional (Full Time)" %in% result$Title)
  expect_true("Custodian (Full Time)" %in% result$Title)
  expect_false(any(result$Location %in% c("Certified Positions", "Coaching Positions", "Administrative Positions")))
})

test_that("parse_swanriver_postings returns zero rows (not an error) when there's no Certified Positions header", {
  result <- parse_swanriver_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_swanriver_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "swanriver_human-resources.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_swanriver_postings()

  expect_equal(nrow(result), 5)
})

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

test_that("parse_reedpoint_postings extracts the 2 real postings under the 'Job Openings-' header", {
  html <- paste(readLines(test_path("fixtures", "reedpoint_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_reedpoint_postings(html, "url")

  expect_equal(nrow(result), 2)
  expect_true(all(c("Kitchen Substitute", "Substitute Teachers") %in% result$Title))
  expect_true(all(result$Location == "Reed Point"))
})

test_that("parse_reedpoint_postings returns zero rows (not an error) when there's no 'Job Openings-' header", {
  result <- parse_reedpoint_postings("<html><body><p>Nothing here.</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_reedpoint_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "reedpoint_employment.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_reedpoint_postings()

  expect_equal(nrow(result), 2)
})

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

# Real fixture captured 2026-08-24 from gallatingatewayschool.com's
# Employment page (CatapultCMS, a new platform for this project).

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
  result <- fetch_apptegy_k12_postings(chromote_session_factory = NULL)
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link", "District"))
})

test_that("fetch_apptegy_k12_postings shares one session across all 37 districts and tags each row with its real District", {
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
  belt_text <- paste(readLines(test_path("fixtures", "apptegy_belt_rendered.txt"), warn = FALSE), collapse = "\n")
  bigsky_text <- paste(readLines(test_path("fixtures", "apptegy_bigsky_rendered.txt"), warn = FALSE), collapse = "\n")
  melstone_text <- paste(readLines(test_path("fixtures", "apptegy_melstone_rendered.txt"), warn = FALSE), collapse = "\n")
  roundup_text <- paste(readLines(test_path("fixtures", "apptegy_roundup_rendered.txt"), warn = FALSE), collapse = "\n")
  wss_text <- paste(readLines(test_path("fixtures", "apptegy_wss_rendered.txt"), warn = FALSE), collapse = "\n")
  shelbymt_text <- paste(readLines(test_path("fixtures", "apptegy_shelbymt_rendered.txt"), warn = FALSE), collapse = "\n")
  geyser_text <- paste(readLines(test_path("fixtures", "geyser_jobs_rendered.txt"), warn = FALSE), collapse = "\n")
  centerville_text <- paste(readLines(test_path("fixtures", "apptegy_centerville_rendered.txt"), warn = FALSE), collapse = "\n")
  arlee_text <- paste(readLines(test_path("fixtures", "apptegy_arlee_rendered.txt"), warn = FALSE), collapse = "\n")
  chinook_text <- paste(readLines(test_path("fixtures", "apptegy_chinook_rendered.txt"), warn = FALSE), collapse = "\n")
  darby_text <- paste(readLines(test_path("fixtures", "apptegy_darby_rendered.txt"), warn = FALSE), collapse = "\n")
  dutton_text <- paste(readLines(test_path("fixtures", "apptegy_dutton_rendered.txt"), warn = FALSE), collapse = "\n")
  stignatius_text <- paste(readLines(test_path("fixtures", "stignatius_jobs_rendered.txt"), warn = FALSE), collapse = "\n")
  stanford_text <- paste(readLines(test_path("fixtures", "apptegy_stanford_rendered.txt"), warn = FALSE), collapse = "\n")
  lolo_text <- paste(readLines(test_path("fixtures", "apptegy_lolo_rendered.txt"), warn = FALSE), collapse = "\n")
  froid_text <- paste(readLines(test_path("fixtures", "apptegy_froid_rendered.txt"), warn = FALSE), collapse = "\n")
  huntley_text <- paste(readLines(test_path("fixtures", "apptegy_huntley_rendered.txt"), warn = FALSE), collapse = "\n")
  parkcity_text <- paste(readLines(test_path("fixtures", "apptegy_parkcity_rendered.txt"), warn = FALSE), collapse = "\n")
  alberton_text <- paste(readLines(test_path("fixtures", "apptegy_alberton_rendered.txt"), warn = FALSE), collapse = "\n")
  dillon_text <- paste(readLines(test_path("fixtures", "apptegy_dillon_rendered.txt"), warn = FALSE), collapse = "\n")
  ennis_text <- paste(readLines(test_path("fixtures", "apptegy_ennis_rendered.txt"), warn = FALSE), collapse = "\n")
  columbus_text <- paste(readLines(test_path("fixtures", "apptegy_columbus_rendered.txt"), warn = FALSE), collapse = "\n")
  stregis_text <- paste(readLines(test_path("fixtures", "apptegy_stregis_rendered.txt"), warn = FALSE), collapse = "\n")
  florencecarlton_text <- paste(readLines(test_path("fixtures", "apptegy_florencecarlton_rendered.txt"), warn = FALSE), collapse = "\n")

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
          else if (grepl("beltschool", navigated_url)) belt_text
          else if (grepl("bssd72", navigated_url)) bigsky_text
          else if (grepl("melstone", navigated_url)) melstone_text
          else if (grepl("roundup", navigated_url)) roundup_text
          else if (grepl("whitesulphur", navigated_url)) wss_text
          else if (grepl("shelbypublicschools", navigated_url)) shelbymt_text
          else if (grepl("geyser", navigated_url)) geyser_text
          else if (grepl("centerville", navigated_url)) centerville_text
          else if (grepl("arleeschools", navigated_url)) arlee_text
          else if (grepl("chinookschools", navigated_url)) chinook_text
          else if (grepl("darby", navigated_url)) darby_text
          else if (grepl("dbps", navigated_url)) dutton_text
          else if (grepl("redroverk12", navigated_url)) stignatius_text
          else if (grepl("stanfordmtschool", navigated_url)) stanford_text
          else if (grepl("loloschools", navigated_url)) lolo_text
          else if (grepl("froidschool", navigated_url)) froid_text
          else if (grepl("huntley", navigated_url)) huntley_text
          else if (grepl("parkcityschools", navigated_url)) parkcity_text
          else if (grepl("alberton", navigated_url)) alberton_text
          else if (grepl("dillonschools", navigated_url)) dillon_text
          else if (grepl("ennisschools", navigated_url)) ennis_text
          else if (grepl("columbuscougars", navigated_url)) columbus_text
          else if (grepl("stregisschool", navigated_url)) stregis_text
          else if (grepl("florencecarlton", navigated_url)) florencecarlton_text
          else ""
          list(result = list(value = value))
        }
      ),
      close = function() invisible(NULL)
    )
  }

  result <- fetch_apptegy_k12_postings(chromote_session_factory = session_factory)

  expect_equal(nrow(result), 19 + 4 + 12 + 2 + 5 + 5 + 11 + 8 + 4 + 5 + 5 + 10 + 4 + 3 + 4 + 4 + 13 + 5 + 6 + 5 + 4 + 8 + 7 + 6 + 2 + 6 + 6 + 4 + 3 + 5 + 2 + 6 + 3 + 5 + 2 + 14 + 9)
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
  expect_equal(sum(result$District == "Belt Public Schools"), 3)
  expect_equal(sum(result$District == "Big Sky School District 72"), 4)
  expect_equal(sum(result$District == "Melstone Public Schools"), 4)
  expect_equal(sum(result$District == "Roundup School District"), 13)
  expect_equal(sum(result$District == "White Sulphur Springs Schools"), 5)
  expect_equal(sum(result$District == "Shelby School District"), 6)
  expect_equal(sum(result$District == "Geyser Public Schools"), 5)
  expect_equal(sum(result$District == "Centerville Public Schools"), 4)
  expect_equal(sum(result$District == "Arlee Joint School District"), 8)
  expect_equal(sum(result$District == "Chinook Public Schools"), 7)
  expect_equal(sum(result$District == "Darby School District 9"), 6)
  expect_equal(sum(result$District == "Dutton/Brady Public School District"), 2)
  expect_equal(sum(result$District == "St. Ignatius School District"), 6)
  expect_equal(sum(result$District == "Stanford Public Schools"), 6)
  expect_equal(sum(result$District == "Lolo School District 7"), 4)
  expect_equal(sum(result$District == "Froid Public Schools"), 3)
  expect_equal(sum(result$District == "Huntley Project School District"), 5)
  expect_equal(sum(result$District == "Park City Schools"), 2)
  expect_equal(sum(result$District == "Alberton School District"), 6)
  expect_equal(sum(result$District == "Dillon School District 10"), 3)
  expect_equal(sum(result$District == "Ennis Schools"), 5)
  expect_equal(sum(result$District == "Columbus Public Schools"), 2)
  expect_equal(sum(result$District == "St Regis School District"), 14)
  expect_equal(sum(result$District == "Florence-Carlton School District 15-6"), 9)
})
