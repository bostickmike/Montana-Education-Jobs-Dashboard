# The job pages read by rules on their lines of text (registry Platform "TextBoard", edjobs parse_text_board() 0.99.0,
# package review step 8, 2026-11-25): each district's rows of text_board_rules.csv on its real fixtures. The old one-off
# parsers gave the same Title / Location / Link on every fixture and on 2026-11-25's live pages, except where a test says
# so (claude-notes/2026-11-25_step8-tail/parity.R).

text_rules <- mt_text_board_rules()
text_registry <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
# Blocks are titled "fetch_text_board_postings: <registry name>" and name their fixtures with test_path(), so the auto-fix
# issue lists each source's own (test-drift-check.R checks it), as in test-css-boards.R.
read_text_page <- function(path) paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
parse_text_district <- function(district, html) {
  row <- text_registry[text_registry$District == district, ]
  result <- parse_text_board(html, row$Job_Link, row$City, text_board_rule(text_rules, district))
  expect_true(all(result$Location == row$City))
  expect_true(all(result$Link == row$Job_Link))
  expect_true(all(is.na(result$Posted_Date)))
  result
}

test_that("every TextBoard registry row has a rule, and every rule a TextBoard registry row", {
  expect_setequal(text_rules$Source, text_registry$District[text_registry$Platform == "TextBoard"])
})

test_that("fetch_text_board_postings: Zurich Elementary School District #17, an empty board", {
  html <- read_text_page(test_path("fixtures", "zurich_employment.html"))
  expect_equal(nrow(parse_text_district("Zurich Elementary School District #17", html)), 0)
  # Reworded "nothing open" lines are still no postings; a real title is one.
  with_line <- function(x) sub("There are no current jobs open.", x, html, fixed = TRUE)
  expect_false(identical(with_line("x"), html))
  for (x in c("No positions available at this time.", "We are not currently hiring.", "None at this time"))
    expect_equal(nrow(parse_text_district("Zurich Elementary School District #17", with_line(x))), 0, info = x)
  expect_equal(parse_text_district("Zurich Elementary School District #17", with_line("K-8 Teacher"))$Title, "K-8 Teacher")
})

test_that("fetch_text_board_postings: Winnett Public Schools, the insurance stipend is not pay", {
  result <- parse_text_district("Winnett Public Schools", read_text_page(test_path("fixtures", "winnett_employment.html")))
  expect_equal(result$Title, c("Bus Driver/Substitute Bus Drivers", "Practice Bus Driver", "Activity Bus Driver",
                               "High School Track Coach"))
  expect_true(all(is.na(result$Pay_Min)))
})

test_that("fetch_text_board_postings: Gallatin Gateway School", {
  result <- parse_text_district("Gallatin Gateway School", read_text_page(test_path("fixtures", "gallatingateway_employment.html")))
  expect_equal(result$Title, c("Substitute Teacher", "Athletic Director", "Business Manager"))
})

test_that("fetch_text_board_postings: Jefferson High School", {
  result <- parse_text_district("Jefferson High School",
                                read_text_page(test_path("fixtures", "jeffersonhigh_eschoolview_2026-10-21.html")))
  expect_equal(result$Title, c("Teachers", "Substitute Teachers", "Paraprofessional Teacher Aides",
                               "Head and Assistant Cheer", "Assistant Football", "Assistant Volleyball"))
})

test_that("fetch_text_board_postings: Brockton School District, both of its page layouts", {
  result <- parse_text_district("Brockton School District", read_text_page(test_path("fixtures", "brockton_jobs.html")))
  expect_equal(result$Title, c("Elementary Teacher (Multiple Openings)", "Secondary Teacher – STEM (Multiple Openings)",
                               "Secondary Teacher – Humanities (Multiple Openings)"))
  older <- parse_text_district("Brockton School District", read_text_page(test_path("fixtures", "brockton_employment.html")))
  expect_equal(older$Title, c("Maintenance", "Bus Driver"))
})

test_that("fetch_text_board_postings: Hysham Public Schools", {
  result <- parse_text_district("Hysham Public Schools", read_text_page(test_path("fixtures", "hysham_jobs.html")))
  expect_equal(result$Title, c("Head of Maintenance", "Vo-Ag Teacher"))
})

test_that("fetch_text_board_postings: Bigfork School District 38, pay from each notice", {
  result <- parse_text_district("Bigfork School District 38", read_text_page(test_path("fixtures", "bigfork_employment_2026-11-25.html")))
  expect_equal(result$Title, c(
    "Full-Time Temporary Custodian", "Food Service Associate 6 hours/day", "Full Time Instructional Paraprofessional",
    "Full Time High School Special Education Paraprofessional", "Substitute Bus Driver", "Substitute Food Service Worker",
    "Temporary Substitute Custodian", "Head Boys HS Baseball Coach",
    "2026-2027 High School Girls Basketball JV/Assistant Varsity Coach",
    "2026-2027 Middle School Girls Basketball Coaches (1 volunteer position and one paid position)"))
  expect_equal(result$Pay_Min, c(16.97, NA, NA, NA, 20, NA, NA, NA, NA, NA))
  expect_equal(result$Pay_Max, c(20.04, NA, NA, NA, 20, NA, NA, NA, NA, NA))
  older <- parse_text_district("Bigfork School District 38", read_text_page(test_path("fixtures", "bigfork_employment.html")))
  expect_equal(older$Title, c(
    "Food Service Associate 6 hours/day", "Full Time Instructional Paraprofessional",
    "Full Time Food Service Associate/Custodian", "Full Time Life Skills Special Education Paraprofessional",
    "Full Time High School Special Education Paraprofessional", "Substitute Bus Driver", "Substitute Food Service Worker",
    "Temporary Substitute Custodian", "2026-2027 High School Boys Assistant Soccer Coach",
    "2026-2027 Middle School Boys 7th and 8th Grade Basketball Coach (2 positions)"))
})

test_that("fetch_text_board_postings: Clinton School District #32, the job each notice names", {
  # The old parser took the line above the notice, a heading: "Classified Positions" (11-23), where the job is paras.
  result <- parse_text_district("Clinton School District #32", read_text_page(test_path("fixtures", "clinton_employment_2026-11-25.html")))
  expect_equal(result$Title, c("Substitute Teachers", "Paraprofessionals"))
  expect_equal(result$Pay_Min, c(95, NA))
  expect_equal(result$Pay_Unit, c("day", NA))
  older <- parse_text_district("Clinton School District #32", read_text_page(test_path("fixtures", "clinton_employment.html")))
  expect_equal(older$Title, c("Substitute Teachers", "Paraprofessional"))
})

test_that("fetch_text_board_postings: Miami Elementary School District #31, in Conrad, with its day rate", {
  # The old parser's place was "Miami"; the school is at New Miami Colony, Conrad (the registry's City).
  result <- parse_text_district("Miami Elementary School District #31", read_text_page(test_path("fixtures", "miami_employment.html")))
  expect_equal(result$Title, "Substitute Teachers")
  expect_equal(result$Location, "Conrad")
  expect_equal(result[, c("Pay_Min", "Pay_Max", "Pay_Unit")], data.frame(Pay_Min = 200, Pay_Max = 200, Pay_Unit = "day"))
})

test_that("fetch_text_board_postings: Marion School District #54, the notice's own words", {
  # The old parser wrote "Guest Teacher / Pool of Substitutes" for this line.
  result <- parse_text_district("Marion School District #54", read_text_page(test_path("fixtures", "marion_employment.html")))
  expect_equal(result$Title, "Guest teachers in our pool of substitutes")
})

test_that("fetch_text_board_postings: Scobey Schools, 13 starred lines, all in Scobey", {
  # The old parser's place was the section heading ("TEACHING STAFF"). The site answers on plain http only (08-16).
  result <- parse_text_district("Scobey Schools", read_text_page(test_path("fixtures", "scobey_employment.html")))
  expect_equal(result$Title, c(
    "ELEMENTARY TEACHER", "K-12 LIBRARIAN", "K-12 ART TEACHER", "K-12 MUSIC TEACHER", "7-12 MATH TEACHER",
    "7-12 FAMILY & CONSUMER SCIENCE TEACHER", "K-6 SPECIAL EDUCATION TEACHER", "K-12 PARAPROFESSIONALS",
    "SUBSTITUTE TEACHERS", "SUBSTITUTE ROUTE BUS DRIVERS", "ACTIVITY DRIVERS", "JH HEAD FOOTBALL COACH",
    "HEAD GIRLS HIGH SCHOOL BASKETBALL COACH"))
})

test_that("fetch_text_board_postings: Terry Public Schools, every list on the page", {
  # The old parser's place was the list's name ("Certified"), and it stopped before "The following positions are
  # currently available", so a posting there was missed.
  html <- read_text_page(test_path("fixtures", "terry_employment_2026-11-25.html"))
  now <- c("Clerk/Business Manager", "Special Education Paraprofessional", "Expedition Route Driver", "Kitchen sub",
           "Sub Teacher/Aide", "Bus Driver", "Sub Bus Driver", "Sub custodian")
  expect_equal(parse_text_district("Terry Public Schools", html)$Title, now)   # "No open positions at this time" is none
  more <- sub("(The following positions are currently available[^<]*</[a-z0-9]+>)", "\\1<p>Head Cook</p>", html)
  expect_false(identical(more, html))
  expect_equal(parse_text_district("Terry Public Schools", more)$Title, c(now, "Head Cook"))
  older <- parse_text_district("Terry Public Schools", read_text_page(test_path("fixtures", "terry_employment.html")))
  expect_equal(older$Title, c(
    "3 Elementary Teachers", "Part time Music Teacher for K – 12", "Part time Art Teacher for K – 12",
    "Physical Education Teacher", "Part time Family – Consumer Science Teacher for grades 7 – 12",
    "Part time Business Teacher for grades 7 – 12", "Title 1 Elementary Teacher", "Special Education Paraprofessional",
    "Expedition Route Driver", "Kitchen sub", "Sub Teacher/Aide", "Bus Driver", "Sub Bus Driver", "Sub custodian"))
})

test_that("a page that isn't the board is an error wherever the rule has a section, not an empty board", {
  # Clinton and Miami name their postings in a sentence and have no fixed heading: no posting sentence is no posting.
  other <- read_text_page(test_path("fixtures", "charlo_jobs.html"))
  for (d in unique(text_rules$Source[nzchar(text_rules$Start_Regex)]))
    expect_error(parse_text_district(d, other), "text board: the page has no line matching", info = d)
})
