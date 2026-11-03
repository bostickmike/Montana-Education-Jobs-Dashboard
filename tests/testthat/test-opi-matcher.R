# opi_matcher.R against hand-labeled real postings (2026-11-03): 142 OPI
# postings at districts whose own board was scraped, each labeled with the
# board posting that is the same opening, or none. Labels were made by reading
# the OPI description against the district's full board; four sets (dev, then
# three held-out sets labeled before the matcher saw them). The board fixture
# is the whole state's direct postings that week, since word weights
# (opi_title_idf) come from all of them, as in the pipeline.
#
# A wrong-posting match is never acceptable; misses (double counts) and false
# matches (a real opening hidden) may not grow past what the matcher achieved
# when it shipped. Raise the bar when the matcher improves.

labels <- read.csv(test_path("fixtures", "opi_match_labels_2026-11-03.csv"), stringsAsFactors = FALSE)
boards <- read.csv(test_path("fixtures", "opi_match_boards_2026-11-03.csv"), stringsAsFactors = FALSE)
labels[is.na(labels)] <- ""

run_matcher <- function() {
  m <- match_opi_postings(transform(labels, title = OPI_Title), labels$District, boards)
  ifelse(is.na(m), "", boards$title[m])
}

test_that("the matcher never pairs an OPI posting with the wrong board posting", {
  got <- run_matcher(); e <- labels$Expected_Match
  wrong <- nzchar(e) & nzchar(got) & got != e
  expect_equal(sum(wrong), 0, info = paste(labels$District[wrong], labels$OPI_Title[wrong], "->", got[wrong], collapse = "; "))
})

test_that("missed duplicates and false matches stay at or below the shipped level", {
  got <- run_matcher(); e <- labels$Expected_Match
  missed <- nzchar(e) & !nzchar(got)
  false_match <- !nzchar(e) & nzchar(got)
  expect_lte(sum(missed), 2)       # of 76 true duplicates (each miss double counts a job)
  expect_lte(sum(false_match), 3)  # of 66 OPI-only postings (each hides a real opening)
  expect_gte(sum(nzchar(e) & got == e), 74)
})

test_that("the job phrase skips boilerplate and names the job", {
  libby <- opi_job_phrase("Coaching Opportunities Available NATURE OF POSITION The Special Education Teacher shall be responsible")
  expect_false(grepl("(?i)coach", libby, perl = TRUE))
  expect_match(libby, "Special Education Teacher")
  expect_match(opi_job_phrase("Glendive Public Schools is looking for a School Psychologist for the 2026-2027 school year. Video from Superintendent"),
               "^School Psychologist")
  expect_match(opi_job_phrase("Stevensville Elementary School is accepting applications for a 1.0 FTE Special Education Paraprofessional."),
               "1.0 FTE Special Education Paraprofessional")
})

test_that("grade level, special education and coaching sport must agree", {
  s <- function(opi_title, desc, board_title, school = "") opi_match_score(opi_title, opi_job_phrase(desc, opi_title), desc, school, board_title, "")
  # A 7th-8th grade job isn't the K-6 opening (Lodge Grass).
  expect_equal(s("Elementary Curriculum", "We are seeking a dedicated and engaging 7th-8th Grade Teacher to join", "Elementary Teacher k-6"), -Inf)
  # Elementary SPED isn't a grades 6-12 Life Skills SPED job (Big Sandy).
  expect_equal(s("Special Education", "Big Sandy Schools is seeking applications for an Elementary Special Education Teacher", "Special Education Teacher (Life Skills Grades 6-12)"), -Inf)
  # Soccer coaches aren't the softball coach (Lockwood).
  expect_equal(opi_match_conflict("Coach", "Head Boys Soccer Coach and Head Girls Soccer Coach", "", "Head Softball Coach | Lockwood High School", ""), TRUE)
  # A related-service role under a SPED department prefix is still the same job (Kalispell).
  expect_gt(s("Physical Therapist", "Starting 2026-2027 FTE .60", "SE - PHYSICAL THERAPIST"), -Inf)
})
