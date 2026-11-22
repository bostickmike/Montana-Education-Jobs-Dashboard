# opi_matcher.R against hand-labeled real postings (2026-11-03): 148 OPI
# postings at districts whose own board was scraped, each labeled with the
# board posting that is the same opening, or none. Labels were made by reading
# the OPI description against the district's full board; four sets (dev, then
# three held-out sets labeled before the matcher saw them, then "fullsample":
# the cases where the matcher and an LLM disagreed when both judged all 275 OPI
# postings at scraped districts that week). The board fixture
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
  expect_lte(sum(missed), 1)       # of 78 true duplicates (each miss double counts a job)
  expect_lte(sum(false_match), 2)  # of 70 OPI-only postings (each hides a real opening)
  expect_gte(sum(nzchar(e) & got == e), 77)
})

# week1110: the 2026-11-10 run's new decisions, judged by hand
# (claude-notes/2026-11-10_opi-matcher-11-10-check.md): the new OPI postings, the
# 3 matches new that week, the 5 whose board twin was gone, and Manhattan's ASL
# intervener (a wrong match on 11-10, fixed the same day by reading the level from
# the school field). Anaconda's SPED posting is labeled the same opening as the
# board's (Mike, 2026-11-19: the board's SPED vacancy was reposted from July on).
# Run against that week's whole-state boards; every label must hold.
test_that("week1110: every hand-judged 2026-11-10 decision holds", {
  labels10 <- read.csv(test_path("fixtures", "opi_match_labels_2026-11-10.csv"), stringsAsFactors = FALSE)
  boards10 <- read.csv(test_path("fixtures", "opi_match_boards_2026-11-10.csv"), stringsAsFactors = FALSE)
  labels10[is.na(labels10)] <- ""
  m <- match_opi_postings(transform(labels10, title = OPI_Title), labels10$District, boards10)
  got <- ifelse(is.na(m), "", boards10$title[m])
  bad <- got != labels10$Expected_Match
  expect_equal(sum(bad), 0, info = paste(labels10$District[bad], labels10$OPI_Title[bad], "->", got[bad],
                                         "expected", labels10$Expected_Match[bad], collapse = "; "))
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

test_that("a district job code quoted on OPI matches the Tyler posting that carries it", {
  # Real Kalispell Tyler feed and OPI description, both 2026-11-03.
  tyler <- parse_tylerportico_positions(
    paste(readLines(test_path("fixtures", "tylerportico_kalispell_2026-11-03.json"), warn = FALSE), collapse = "\n"),
    "Kalispell Public Schools", "https://kalispellpublicschoolsmt.tylerportico.com/tess/citizen")
  expect_true(all(grepl("^JP[0-9]+", tyler$Job_Code)))
  board <- data.frame(District = "Kalispell Public Schools", title = tyler$Title, location = tyler$Location,
                      Job_Code = tyler$Job_Code, stringsAsFactors = FALSE)
  opi <- data.frame(title = "Elementary Curriculum", OPI_School = "District Wide",
                    OPI_Description = readLines(test_path("fixtures", "opi_description_kalispell_JP054494_2026-11-03.txt"), warn = FALSE))
  m <- match_opi_postings(opi, "Kalispell Public Schools", board)
  expect_equal(board$title[m], "LONG TERM SUBSTITUTE - ELEMENTARY")
  expect_match(board$Job_Code[m], "^JP054494")
})

test_that("a phrase with no grade level takes it from OPI's school field (Manhattan, 2026-11-10)", {
  desc <- "MANHATTAN PUBLIC SCHOOLS VACANCY ANNOUNCEMENT JOB TITLE: Specialized Paraprofessional - ASL Fluent Intervener COMPENSATION: $26.85 hourly. Will work with special education students."
  s <- function(board, school) opi_match_score("Paraprofessional - Special Education", opi_job_phrase(desc, "Paraprofessional - Special Education"),
                                               desc, school, board, "Manhattan")
  expect_equal(s("SPED Paraprofessional MS- Part-Time", "Manhattan Elem"), -Inf)        # elementary job, middle-school posting
  expect_gt(s("SPED Paraprofessional", "Manhattan Elem"), -Inf)                         # a posting naming no level still matches
  expect_gt(s("SPED Paraprofessional MS- Part-Time", "District Wide"), -Inf)            # no level anywhere: unchanged
})

# 2026-11-22 drift triage (claude-notes/2026-11-22_drift-triage/): two real OPI postings that were each counted
# a second time next to their own board posting. Descriptions are the 11-19 archive's, opening words.
test_that("a long-term sub with words between 'long term' and 'substitute' is still a long-term sub (Bozeman)", {
  expect_equal(opi_tokens("LONG TERM ENGLISH TEACHER SUBSTITUTE AT GHS", OPI_ROLE_LEXICON), c("ENG", "LTS"))
  expect_equal(opi_tokens("Substitute Teacher", OPI_ROLE_LEXICON), "SUB")
  desc <- "English Teacher at GHS - long term substitute (24 hours/week) Salary Range: $178.00/day for the first 34 consecutive days, then $268.67/day starting with the 35th day."
  board <- data.frame(District = "Bozeman Public Schools", location = "",
                      title = c("LONG TERM ENGLISH TEACHER SUBSTITUTE AT GHS", "LONG TERM SUBSTITUTE - ELEMENTARY MUSIC TEACHER", "Substitute Teacher"))
  m <- match_opi_postings(data.frame(title = "English", OPI_School = "Gallatin High School", OPI_Description = desc), "Bozeman Public Schools", board)
  expect_equal(board$title[m], "LONG TERM ENGLISH TEACHER SUBSTITUTE AT GHS")
})

test_that("a K-12 endorsement meets an elementary board title only when the subject agrees (Great Falls, Savage)", {
  desc <- "QUALIFICATIONS: =Class 1 or 2 MT Teaching License required; =Music K-12 endorsement required; =String experience preferred EMPLOYMENT: 2026/2027 SALARY: $48,300-$73,957"
  s <- function(board) opi_match_score("Music", opi_job_phrase(desc, "Music"), desc, "District Wide", board, "District-wide")
  expect_gt(s("Elementary Instrumental Music Teacher -oyo"), -Inf)
  expect_equal(s("Elementary Teacher"), -Inf)                    # K-12 alone isn't the subject-less elementary opening
  expect_equal(s("Elementary Special Education Teacher"), -Inf)  # nor another subject's
})
