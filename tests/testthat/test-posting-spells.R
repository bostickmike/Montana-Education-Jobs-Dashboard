# MT's HE posting identity (posting_spells.R) and the committed spells; the
# spell rules themselves are tested in edjobs (tests/testthat/test-posting-spells.R).
source(here::here("posting_spells.R"))

# Raw HE archive rows, shaped like the real MT cases of 2026-11-04.
he_raw <- function(run, title, inst, link, posted = NA_character_) {
  data.frame(Title = title, Location = NA_character_, Posted_Date = posted, Institution = inst, Link = link,
             Archive_Date = run, stringsAsFactors = FALSE)
}

test_that("HE per-posting links are IDs; one employment page for every posting is not", {
  d <- rbind(he_raw("2026-10-27", "Program Coordinator", "Montana State University", "https://jobs.montana.edu/postings/53556"),
             he_raw("2026-10-27", "Admissions Counselor", "Rocky Mountain College",
                    "https://rocky.edu/employment/opportunities/admissions-counselor/"),
             he_raw("2026-10-27", "Director", "Montana Tech", "https://montanatechuniversity.applytojob.com/apply/6BpCaPKxsi/Director"),
             # Carroll: every opening links the same page.
             he_raw("2026-10-27", "Chemistry Faculty", "Carroll College", "https://www.carroll.edu/faculty-staff-positions"),
             he_raw("2026-10-27", "Head Coach", "Carroll College", "https://www.carroll.edu/faculty-staff-positions"),
             # Miles: one opening this week, but the page also held two titles in another run.
             he_raw("2026-10-20", "Nursing Instructor", "Miles Community College", "https://www.milescc.edu/employment/"),
             he_raw("2026-10-20", "Custodian", "Miles Community College", "https://www.milescc.edu/employment/"),
             he_raw("2026-10-27", "Custodian", "Miles Community College", "https://www.milescc.edu/employment/"))
  x <- add_he_posting_identity(d)
  m <- setNames(x$Posting_Identity_Method == "Stable per-posting URL", paste(x$Institution, x$Archive_Date, x$Title))
  expect_true(all(m[1:3]))
  expect_false(any(m[4:8]))
  expect_equal(x$Posting_ID[7], x$Posting_ID[8])   # same title, same fallback ID across runs
  expect_equal(x$Bridgeable, c(FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE))
})

test_that("the committed spells mark relistings unknown but keep platform-reported fills", {
  p <- here::here("posting_spells_k12.csv")
  skip_if_not(file.exists(p), "posting_spells_k12.csv not built")
  s <- utils::read.csv(p, colClasses = "character")
  r <- s$Ending == "censored: relisted next run"
  expect_true(all(s$Event[r] == "FALSE"))
  expect_true(all(s$End_Basis[r] == "censored"))
  # Every relisting is either marked unknown or kept as the platform's "filled";
  # no relisting is still counted as a plain ending.
  rel <- relisted_next_run(s$District, s$Posting_Source, s$Title, as.Date(s$First_Seen), as.Date(s$Next_Run))
  expect_false(any(rel & s$Ending %in% setdiff(POSTING_SPELL_EVENTS, "filled")))
  expect_true(all(r <= rel))
})

test_that("the committed spells give no advertised window to a posting that outlived its stated date", {
  for (p in here::here(c("posting_spells_k12.csv", "posting_spells_he.csv"))) {
    skip_if_not(file.exists(p), "posting spells not built")
    s <- utils::read.csv(p, stringsAsFactors = FALSE)
    w <- !is.na(s$Advertised_Days)
    expect_true(all(as.Date(s$Last_Seen[w]) <= as.Date(s$Stated_Close_Date[w]) + 7), info = basename(p))
  }
})
