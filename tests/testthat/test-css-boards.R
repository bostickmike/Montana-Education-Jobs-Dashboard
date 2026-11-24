# The college job pages read by CSS selectors (registry Platform "CSSBoard", edjobs parse_css_board(), package
# review step 8, 2026-11-24): each source's rule in css_board_rules.csv, on its real fixture (captured 2026-08-07).
# The old one-off parsers gave these same rows on every fixture (claude-notes/2026-11-24_css-board/parity.R).

css_rules <- mt_css_board_rules()
css_registry <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
read_css_fixture <- function(name) {
  paste(readLines(test_path("fixtures", name), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}
parse_css_source <- function(institution, fixture) {
  row <- css_registry[css_registry$Institution == institution, ]
  parse_css_board(read_css_fixture(fixture), row$Feed_URL, row$Town, css_board_rule(css_rules, institution))
}

test_that("every CSSBoard registry row has a rule, and every rule a CSSBoard registry row", {
  board_rows <- css_registry$Institution[css_registry$Platform == "CSSBoard"]
  expect_setequal(css_rules$Source, board_rows)
})

test_that("Carroll College: all 16 accordion titles, the positions page, Helena", {
  result <- parse_css_source("Carroll College", "carroll_college_positions.html")
  expect_equal(result$Title, c(
    "Founding Director, Master of Educational Leadership Program", "Part-time Clinical Nursing Faculty",
    "Principal Faculty for Physician Assistant Program", "Alumni & Community Engagement Coordinator",
    "Area Coordinator", "Custodian", "Didactic Program Coordinator for PA Program",
    "Director of Alumni & Community Engagement", "Educational Technology Specialist",
    "Facilities Services Supervisor - Grounds", "IT Support Specialist", "Library Director",
    "Mail Services Coordinator", "Major Gift Officer – Part-time", "Head Dance Coach",
    "Special Event Team Members- Part-time"))
  expect_equal(unique(result$Location), "Helena")
  expect_equal(unique(result$Link), "https://www.carroll.edu/faculty-staff-positions")
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("Rocky Mountain College: 7 postings with their own pages and departments; the template item is skipped", {
  result <- parse_css_source("Rocky Mountain College", "rocky_mountain_college_employment.html")
  expect_equal(result$Title, c(
    "Admissions Counselor", "Director of Flight Operations", "Adjunct Faculty Position in Theater",
    "Head Bears Cheer Coach", "Airframe & Powerplant Certified Mechanic with (I/ A) Inspection Authorization",
    "Adjunct Instructor-Accounting", "Chief Flight Instructor"))
  expect_equal(result$Location, c("Admissions", "Aviation", "Academics", "Athletics", "Aviation", "Faculty", "Aviation"))
  expect_equal(result$Link, paste0("https://rocky.edu/employment/opportunities/", c(
    "admissions-counselor/", "director-of-flight-operations/", "adjunct-faculty-position-in-theater/",
    "head-bears-cheer-coach/", "airframe-powerplant-certified-mechanic-with-i-a-inspection-authorization/",
    "adjunct-instructor-accounting/", "chief-flight-instructor/")))
  # rocky.edu has rate-limited single requests (429s 2026-09-01, 09-15): six tries.
  expect_equal(css_board_rule(css_rules, "Rocky Mountain College")$Max_Tries, "6")
})

test_that("Salish Kootenai College: all 17 accordion titles, the employment page, Pablo", {
  result <- parse_css_source("Salish Kootenai College", "skc_employment.html")
  expect_equal(result$Title, c(
    "Soils & Groundwater Hydrology Instructor 9month", "Lab Instructor-Nursing Department 10 months",
    "College & Career Readiness Coach", "Grants and Contracts Manager MODIFIED TO REFLECT REVISED SALARY",
    "Tribal Governance & Admin Instructor FT 9-months", "Nursing Faculty Part-time", "Accounting Assistant",
    "Pre-Engineering/Physics Faculty and Digital Manufacturing Lab Director",
    "Tribal Research & Education in Ecosystem Sciences (TREES) Center Director",
    "Chemical Dependency Instructor-9months", "Elementary Education Instructor/Education Grants Specialist",
    "HR Director & Title IX Coordinator", "HEO Instructor/Mechanic Helper-HCT Department 10months",
    "Academic Transfer Specialist", "Truck Driving Instructor Full-time 9months",
    "Loan Officer-Financial Aid Department", "Assistant Fitness Center Manager"))
  expect_equal(unique(result$Location), "Pablo")
  expect_equal(unique(result$Link), "https://www.skc.edu/employment/")
})

test_that("Little Big Horn College: the 4 PDF-linked titles, relative links made absolute, Crow Agency", {
  result <- parse_css_source("Little Big Horn College", "lbhc_job_opportunities.html")
  expect_equal(result$Title, c("Chief Finance Officer", "Math Instructor", "Ag Instructor", "Web IT specialist"))
  expect_equal(result$Link, paste0("http://lbhc.edu/sites/default/files/lbhc/humanresources/", c(
    "2026_CFO_LBHC_final.pdf", "2026_Math_Instructor_Final.pdf", "Ag_Instructor.pdf", "Web_IT_Specialist.pdf")))
  expect_equal(unique(result$Location), "Crow Agency")
})

test_that("Little Big Horn College, 2026-11-24 page: links with spaces keep the page's own text", {
  result <- parse_css_source("Little Big Horn College", "lbhc_job_opportunities_2026-11-24.html")
  expect_equal(result$Title, c("Dean of Student Services", "Human Resources Director", "Computer Science Instructor",
                               "Ag Instructor"))
  expect_equal(result$Link, paste0("http://lbhc.edu/sites/default/files/lbhc/humanresources/", c(
    "Dean of Student Services App Packet.pdf", "Human Resources App Packet.pdf",
    "Computer_Science_Instructor_Position.pdf", "Ag_Instructor.pdf")))
})

test_that("Fort Peck Community College: the 1 posting, its location field (2nd of 4) and its PDF", {
  result <- parse_css_source("Fort Peck Community College", "fpcc_employment.html")
  expect_equal(result$Title, "Agriculture Assistant")
  expect_equal(result$Location, "Poplar")
  expect_equal(result$Link, paste0("https://cdn.prod.website-files.com/68de85d9627927ed05698b64/",
                                   "69160b4cf0be390b6b317f44_Ag-Assistant-Job-Description.pdf"))
})

test_that("a CSSBoard source resolves to fetch_css_board_postings() with its page, town and rule", {
  call <- resolve_scraper_call("Salish Kootenai College")
  expect_equal(call$fn, "fetch_css_board_postings")
  expect_equal(call$args[[1]], "https://www.skc.edu/employment/")
  expect_equal(call$args[[2]], "Pablo")
  expect_equal(call$args[[3]]$Title_CSS, ".uabb-adv-accordion-button-label")
})

test_that("fetch_css_board_postings() reads a live-shaped response for a registry source", {
  httr2::local_mocked_responses(list(httr2::response(
    200, headers = list("Content-Type" = "text/html; charset=utf-8"),
    body = charToRaw(read_css_fixture("lbhc_job_opportunities.html")))))
  row <- css_registry[css_registry$Institution == "Little Big Horn College", ]
  result <- fetch_css_board_postings(row$Feed_URL, row$Town, css_board_rule(css_rules, row$Institution))
  expect_equal(nrow(result), 4)
})
