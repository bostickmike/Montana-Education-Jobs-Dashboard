# Posting-level spells (posting_spells.R; posting-dates plan step 5). Small
# panels shaped like the real cases found in the MT archives on 2026-11-04.
source(here::here("posting_spells.R"))

ps_row <- function(run, id, title, district = "Billings Public Schools", posted = "2026-09-01",
                   method = "Source fallback: title + location + posted date (no stable posting URL)",
                   source = "AppliTrack (direct district board)", url = "https://www.applitrack.com/billings/onlineapp/default.aspx",
                   opi = FALSE, position = "Custodial/Maintenance") {
  data.frame(Run_Date = as.Date(run), Posting_ID = id, Posting_Identity_Method = method, District = district,
             title = title, date_posted = posted, url = url, Posting_Source = source, Is_OPI = opi,
             position = position, stringsAsFactors = FALSE)
}
ps_cal <- function(run, entity, status) data.frame(Run_Date = run, Segment = "K-12", Entity = entity, Source = entity,
                                                   Status = status, N_Rows = 1L, Error = NA_character_)

test_that("earlier title-identified rows join the job ID the same posting carries later", {
  p <- rbind(ps_row("2026-10-20", "fb-1", "Custodian III"), ps_row("2026-10-27", "fb-1", "Custodian III"),
             ps_row("2026-11-03", "url-9", "Custodian III", method = "Stable per-posting URL",
                    url = "https://www.applitrack.com/billings/onlineapp/default.aspx?AppliTrackJobId=9"))
  b <- bridge_posting_ids(p)
  expect_equal(unique(b$Posting_ID), "url-9")
  expect_equal(b$Bridged_From[1], "fb-1")
})

test_that("an ID change between consecutive runs is bridged only when the posted date allows it", {
  # Sidney, 11-03: the parser fix filled a posted date that was blank before.
  p <- rbind(ps_row("2026-10-27", "fb-a", "Library Media Specialist", district = "Sidney Public Schools", posted = NA),
             ps_row("2026-11-03", "url-a", "Library Media Specialist", district = "Sidney Public Schools",
                    posted = "2026-05-01", method = "Stable per-posting URL"),
             # Billings "Custodian III": posted 08-04, a new one posted 08-18 is a real repost.
             ps_row("2026-08-18", "fb-b", "Custodian III", posted = "2026-08-04"),
             ps_row("2026-08-25", "fb-c", "Custodian III", posted = "2026-08-18"))
  b <- bridge_posting_ids(p)
  expect_equal(b$Posting_ID[b$title == "Library Media Specialist"], c("url-a", "url-a"))
  expect_equal(sort(unique(b$Posting_ID[b$title == "Custodian III"])), c("fb-b", "fb-c"))
})

test_that("an ending counts only when the source was healthy the next run", {
  p <- rbind(ps_row("2026-10-20", "a", "Custodian"), ps_row("2026-10-20", "b", "Cook", district = "Laurel Public Schools"),
             ps_row("2026-10-20", "c", "Bus Driver", district = "Belgrade School District 44", source = "SchoolSpring (direct district board)",
                    url = "https://belgrade.schoolspring.com/jobs/5785656"),
             ps_row("2026-10-27", "d", "Secretary"), ps_row("2026-10-27", "e", "Cook II", district = "Laurel Public Schools"),
             ps_row("2026-10-27", "f", "Aide", district = "Belgrade School District 44", source = "SchoolSpring (direct district board)",
                    url = "https://belgrade.schoolspring.com/jobs/1"))
  cal <- rbind(ps_cal("2026-10-20", "Billings Public Schools", "ok"), ps_cal("2026-10-27", "Billings Public Schools", "ok"),
               ps_cal("2026-10-27", "Laurel Public Schools", "error"), ps_cal("2026-10-27", "Belgrade School District 44", "error"))
  end <- data.frame(job_id = "5785656", Job_Status = "filled")
  sp <- build_posting_spells(p, cal, end)
  e <- setNames(sp$Ending, sp$Posting_ID)
  expect_equal(unname(e[c("a", "b", "c", "d")]),
               c("no longer listed", "censored: source error", "filled", "still listed"))
  expect_equal(sp$Event[sp$Posting_ID %in% c("a", "b", "c", "d")][order(sp$Posting_ID[sp$Posting_ID %in% c("a", "b", "c", "d")])],
               c(TRUE, FALSE, TRUE, FALSE))
  # Ending dated at the midpoint between last sighting and the next run.
  expect_equal(sp$End_Date[sp$Posting_ID == "a"], "2026-10-23")
})

test_that("start date, left-censoring, standing ads and shared titles are flagged", {
  p <- rbind(ps_row("2026-08-18", "a", "Custodian", posted = "2026-08-10"),
             ps_row("2026-08-18", "b", "Cook", posted = NA),                               # first week, no date
             ps_row("2026-08-25", "c", "Bus Driver", posted = NA),                         # later week, no date
             ps_row("2026-08-25", "d", "Paraprofessional", posted = "2022-07-14"),         # a 2022 standing ad
             ps_row("2026-08-25", "e", "Substitute Teacher", posted = "2026-08-20"),
             ps_row("2026-08-25", "f", "Special Education Teacher", posted = "2026-08-01"),
             ps_row("2026-08-25", "g", "Special Education Teacher", posted = "2026-08-02"))
  sp <- build_posting_spells(p)
  r <- function(id, col) sp[[col]][sp$Posting_ID == id]
  expect_equal(r("a", "Start_Basis"), "board posted date"); expect_equal(r("a", "Start_Date"), "2026-08-10")
  expect_true(r("b", "Left_Censored")); expect_false(r("c", "Left_Censored"))
  expect_true(r("d", "Evergreen")); expect_true(r("e", "Evergreen")); expect_false(r("a", "Evergreen"))
  expect_true(r("f", "Shared_Title") && r("g", "Shared_Title"))
  expect_equal(sp$Posting_ID[sp$In_Durations], c("a", "c"))
})

test_that("Kaplan-Meier medians use delayed entry and need enough endings", {
  mk <- function(n, before, days, event) data.frame(In_Durations = TRUE, Days_Before_First_Seen = before,
                                                    Days_Listed = days, Event = event, Position = "Teacher")
  # 30 postings watched from day 0 that all end at day 10, plus 30 first seen
  # at day 200 that end at day 210: delayed entry keeps the old ones from
  # dragging the median past their own entry age.
  s <- rbind(mk(30, rep(0, 30), rep(10, 30), rep(TRUE, 30)), mk(30, rep(200, 30), rep(210, 30), rep(TRUE, 30)))
  d <- summarize_posting_durations(s)
  expect_equal(d$Median_Days, 10)
  expect_true(is.na(summarize_posting_durations(s[1:5, ])$Median_Days))
})
