# The job pages read by CSS selectors (registry Platform "CSSBoard", edjobs parse_css_board(), package review step 8,
# 2026-11-24): each source's rule in css_board_rules.csv, on its real fixture. Colleges (captured 2026-08-07) are
# keyed by Institution, districts (Swan Valley, Richey, Rapelje, captured 2026-10-21) by District. The old one-off
# parsers gave these same rows on every fixture (claude-notes/2026-11-24_css-board/parity.R and
# claude-notes/2026-11-24_css-board-k12/parity.R).

css_rules <- mt_css_board_rules()
css_registry <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
# The auto-fix issue lists a source's fixtures from these blocks (edjobs fixtures_used_by_tests()): a block counts
# when its description has the entry point `fetch_css_board_postings` and the source's registry name, and its
# fixtures are the literal test_path("fixtures", "...") calls inside it. So each source's blocks start
# "fetch_css_board_postings: <registry name>" and name their fixture in the block (test-drift-check.R checks it).
read_css_page <- function(path) paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
parse_css_source <- function(institution, html) {
  row <- css_registry[css_registry$Institution == institution, ]
  parse_css_board(html, row$Feed_URL, row$Town, css_board_rule(css_rules, institution))
}

css_k12_registry <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
parse_css_district <- function(district, html) {
  row <- css_k12_registry[css_k12_registry$District == district, ]
  parse_css_board(html, row$Job_Link, row$City, css_board_rule(css_rules, district))
}

test_that("every CSSBoard registry row has a rule, and every rule a CSSBoard registry row", {
  board_rows <- c(css_registry$Institution[css_registry$Platform == "CSSBoard"],
                  css_k12_registry$District[css_k12_registry$Platform == "CSSBoard"])
  expect_setequal(css_rules$Source, board_rows)
  expect_false(anyDuplicated(board_rows) > 0)
})

test_that("fetch_css_board_postings: Carroll College, all 16 accordion titles, the positions page, Helena", {
  result <- parse_css_source("Carroll College", read_css_page(test_path("fixtures", "carroll_college_positions.html")))
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

test_that("fetch_css_board_postings: Rocky Mountain College, 7 postings with their own pages and departments; the template item is skipped", {
  result <- parse_css_source("Rocky Mountain College", read_css_page(test_path("fixtures", "rocky_mountain_college_employment.html")))
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

test_that("fetch_css_board_postings: Salish Kootenai College, all 17 accordion titles, the employment page, Pablo", {
  result <- parse_css_source("Salish Kootenai College", read_css_page(test_path("fixtures", "skc_employment.html")))
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

test_that("fetch_css_board_postings: Little Big Horn College, the 4 PDF-linked titles, relative links made absolute, Crow Agency", {
  result <- parse_css_source("Little Big Horn College", read_css_page(test_path("fixtures", "lbhc_job_opportunities.html")))
  expect_equal(result$Title, c("Chief Finance Officer", "Math Instructor", "Ag Instructor", "Web IT specialist"))
  expect_equal(result$Link, paste0("http://lbhc.edu/sites/default/files/lbhc/humanresources/", c(
    "2026_CFO_LBHC_final.pdf", "2026_Math_Instructor_Final.pdf", "Ag_Instructor.pdf", "Web_IT_Specialist.pdf")))
  expect_equal(unique(result$Location), "Crow Agency")
})

test_that("fetch_css_board_postings: Little Big Horn College, 2026-11-24 page: links with spaces keep the page's own text", {
  result <- parse_css_source("Little Big Horn College", read_css_page(test_path("fixtures", "lbhc_job_opportunities_2026-11-24.html")))
  expect_equal(result$Title, c("Dean of Student Services", "Human Resources Director", "Computer Science Instructor",
                               "Ag Instructor"))
  expect_equal(result$Link, paste0("http://lbhc.edu/sites/default/files/lbhc/humanresources/", c(
    "Dean of Student Services App Packet.pdf", "Human Resources App Packet.pdf",
    "Computer_Science_Instructor_Position.pdf", "Ag_Instructor.pdf")))
})

test_that("fetch_css_board_postings: Fort Peck Community College, the 1 posting, its location field (2nd of 4) and its PDF", {
  result <- parse_css_source("Fort Peck Community College", read_css_page(test_path("fixtures", "fpcc_employment.html")))
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

test_that("fetch_css_board_postings: Little Big Horn College, a live-shaped response", {
  httr2::local_mocked_responses(list(httr2::response(
    200, headers = list("Content-Type" = "text/html; charset=utf-8"),
    body = charToRaw(read_css_page(test_path("fixtures", "lbhc_job_opportunities.html"))))))
  row <- css_registry[css_registry$Institution == "Little Big Horn College", ]
  result <- fetch_css_board_postings(row$Feed_URL, row$Town, css_board_rule(css_rules, row$Institution))
  expect_equal(nrow(result), 4)
})

# K-12: the same naming, so the auto-fix issue finds each district's own fixtures.
test_that("fetch_css_board_postings: Swan Valley School District #3, the 1 Weebly heading (a sentence), Condon", {
  html <- paste(readLines(test_path("fixtures", "swanvalley_careers_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"),
                collapse = "\n")
  result <- parse_css_district("Swan Valley School District #3", html)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(result$Title, paste("Instructional paraprofessional, or a candidate interested in a part-time",
                                   "teaching/part-time paraprofessional role"))
  expect_equal(result$Location, "Condon")
  expect_equal(result$Link, "https://www.swanvalleyelementary.org/careers.html")
  expect_equal(result$Posted_Date, NA_character_)
})

test_that("fetch_css_board_postings: Richey Public Schools, the 1 bold title; headings and the notice are dropped", {
  html <- paste(readLines(test_path("fixtures", "richey_cscms_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"),
                collapse = "\n")
  result <- parse_css_district("Richey Public Schools", html)
  expect_equal(result$Title, "2026-27 Assistant Cook / Custodian")
  expect_equal(result$Location, "Richey")
  expect_equal(result$Link, "https://www.richey.k12.mt.us/currentopenings")
  expect_equal(result$Posted_Date, NA_character_)
  # What the exclude and length rules hold back on this page: the page's own headings, the equal-opportunity line.
  all_text <- parse_css_board(html, "u", "Richey", modifyList(css_board_rule(css_rules, "Richey Public Schools"),
                                                               list(Exclude_Regex = "", Max_Title_Chars = "")))
  expect_true(nrow(all_text) > nrow(result))
})

test_that("fetch_css_board_postings: Rapelje School District, the 3 18px headings in the editor block, Rapelje", {
  html <- paste(readLines(test_path("fixtures", "rapelje_parentsquare_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"),
                collapse = "\n")
  result <- parse_css_district("Rapelje School District", html)
  expect_equal(result$Title, c("Bus Drivers\u2014Route and/or Activity Drivers", "Preschool Teacher", "Cooks Helper"))
  expect_equal(result$Location, rep("Rapelje", 3))
  expect_equal(result$Link, rep("https://www.rapelje.k12.mt.us/job-listings", 3))
  expect_equal(result$Posted_Date, rep(NA_character_, 3))
})

test_that("fetch_css_board_postings: Rapelje School District, 2026-11-23 page: only the bus drivers are left", {
  # A real change on the page (Preschool Teacher and Cooks Helper taken down), not a reader fault.
  html <- paste(readLines(test_path("fixtures", "rapelje_parentsquare_2026-11-23.html"), warn = FALSE, encoding = "UTF-8"),
                collapse = "\n")
  result <- parse_css_district("Rapelje School District", html)
  expect_equal(result$Title, "Bus Drivers\u2014Route and/or Activity Drivers")
  expect_equal(result$Location, "Rapelje")
  expect_equal(result$Link, "https://www.rapelje.k12.mt.us/job-listings")
})

test_that("parse_css_board: Swan Valley, Richey and Rapelje stop on a page without their board's container", {
  # Board_CSS (Mike's 2026-11-22 call for one-off parsers): a moved or redesigned page is a scrape error, not
  # "0 postings". The old parsers returned 0 rows here. Each district's rule on another district's real page:
  pages <- c("Swan Valley School District #3" = "richey_cscms_2026-10-21.html",
             "Richey Public Schools" = "rapelje_parentsquare_2026-10-21.html",
             "Rapelje School District" = "swanvalley_careers_2026-10-21.html")
  for (d in names(pages)) {
    html <- paste(readLines(test_path("fixtures", pages[[d]]), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    expect_error(parse_css_district(d, html), "the board's marker", info = d)
  }
})

test_that("a K-12 CSSBoard district resolves to fetch_css_board_postings() with its Job_Link, City and rule", {
  call <- resolve_scraper_call("Rapelje School District")
  expect_equal(call$fn, "fetch_css_board_postings")
  expect_equal(call$where, "k12_district_registry.csv")
  expect_equal(call$args[[1]], "https://www.rapelje.k12.mt.us/job-listings")
  expect_equal(call$args[[2]], "Rapelje")
  expect_equal(call$args[[3]]$Title_CSS, ".ss-editor-content span[style*='18px']")
})

test_that("fetch_css_board_postings: Richey Public Schools, a live-shaped response", {
  html <- paste(readLines(test_path("fixtures", "richey_cscms_2026-10-21.html"), warn = FALSE, encoding = "UTF-8"),
                collapse = "\n")
  httr2::local_mocked_responses(list(httr2::response(
    200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(html))))
  row <- css_k12_registry[css_k12_registry$District == "Richey Public Schools", ]
  result <- fetch_css_board_postings(row$Job_Link, row$City, css_board_rule(css_rules, row$District))
  expect_equal(result$Title, "2026-27 Assistant Cook / Custodian")
})
