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

# Higher ed (posting_spells.R, "Higher ed"): identity from the raw HE archive
# columns, shaped like the real MT cases of 2026-11-04.
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

test_that("a re-uploaded posting document is bridged; a new PeopleAdmin number is not", {
  p <- rbind(ps_row("2026-09-29", "url:old.pdf", "NACTEP Project Assistant", district = "Aaniiih Nakoda College",
                    posted = NA, method = "Stable per-posting URL"),
             ps_row("2026-10-06", "url:new.pdf", "NACTEP Project Assistant", district = "Aaniiih Nakoda College",
                    posted = NA, method = "Stable per-posting URL"),
             ps_row("2026-09-29", "url:postings/1", "Adjunct Instructor", district = "Montana State University",
                    posted = NA, method = "Stable per-posting URL"),
             ps_row("2026-10-06", "url:postings/2", "Adjunct Instructor", district = "Montana State University",
                    posted = NA, method = "Stable per-posting URL"))
  p$Bridgeable <- c(TRUE, TRUE, FALSE, FALSE)
  b <- bridge_posting_ids(p)
  expect_equal(unique(b$Posting_ID[b$District == "Aaniiih Nakoda College"]), "url:new.pdf")
  expect_equal(sort(unique(b$Posting_ID[b$District == "Montana State University"])), c("url:postings/1", "url:postings/2"))
})

test_that("HE start is the earliest posted date shown, and shared titles count only for title IDs", {
  # Great Falls: the feed date moved forward when the posting was re-published.
  p <- rbind(ps_row("2026-10-20", "url:gf/1", "Adjunct Instructor", district = "Great Falls College MSU",
                    posted = "2026-10-01", method = "Stable per-posting URL"),
             ps_row("2026-10-27", "url:gf/1", "Adjunct Instructor", district = "Great Falls College MSU",
                    posted = "2026-10-25", method = "Stable per-posting URL"),
             ps_row("2026-10-27", "url:gf/2", "Adjunct Instructor", district = "Great Falls College MSU",
                    posted = "2026-10-26", method = "Stable per-posting URL"),
             ps_row("2026-10-27", "fb-1", "Instructor", district = "Carroll College", posted = NA),
             ps_row("2026-10-27", "fb-2", "Instructor", district = "Carroll College", posted = NA))
  p <- use_earliest_posted_date(p)
  expect_equal(p$date_posted[p$Posting_ID == "url:gf/1"], c("2026-10-01", "2026-10-01"))
  sp <- build_posting_spells(p, shared_titles = "fallback only")
  expect_equal(sp$Shared_Title[order(sp$Posting_ID)], c(TRUE, TRUE, FALSE, FALSE))
})

test_that("a posting's own page confirms or overrules its ending, and dates it by a stated closing date", {
  source(here::here("posting_status.R"))
  at <- function(id) paste0("https://www.applitrack.com/billings/onlineapp/default.aspx?AppliTrackLayoutMode=detail&AppliTrackJobId=", id)
  p <- rbind(ps_row("2026-10-27", "url-1", "Cook", method = "Stable per-posting URL", url = at(1), posted = "2026-10-01"),
             ps_row("2026-10-27", "url-2", "Aide", method = "Stable per-posting URL", url = at(2), posted = "2026-10-01"),
             ps_row("2026-11-03", "url-4", "Nurse", method = "Stable per-posting URL", url = at(4)))
  p$Close_Date <- c("2026-10-30", NA, NA)
  cal <- rbind(ps_cal("2026-10-27", "Billings Public Schools", "ok"), ps_cal("2026-11-03", "Billings Public Schools", "ok"))
  st <- data.frame(Check_URL = posting_status_check_url(at(1:2)), Status = c("closed", "open"), Stated_Close_Date = NA,
                   Last_Checked = "2026-11-03", stringsAsFactors = FALSE)
  sp <- build_posting_spells(p, cal, statuses = st)
  r <- function(id, col) sp[[col]][sp$Posting_ID == id]
  expect_equal(r("url-1", "Ending"), "closed (confirmed)")
  expect_equal(r("url-1", "End_Date"), "2026-10-30"); expect_equal(r("url-1", "Advertised_Days"), 29)
  expect_equal(r("url-2", "Ending"), "censored: still open on its page")
})

test_that("a posting relisted under a new ID the next run is 'outcome unknown', not an ending", {
  # 2026-11-09: of 23 WY SchoolSpring relistings whose old record has a final
  # status, 8 were "filled" (a new vacancy with the same title), so relistings
  # are neither linked nor counted as endings.
  d <- c("Albany County School District 1", "Albany County School District 1", "Albany County School District 1",
         "Albany County School District 1", "Laramie County School District 1")
  src <- c("acsd1", "acsd1", "acsd1", "other board", "acsd1")
  title <- c("Mechanic", " mechanic ", "Elementary Teacher", "Mechanic", "Mechanic")
  first <- as.Date(c("2026-03-06", "2026-04-17", "2026-04-17", "2026-04-17", "2026-04-17"))
  nxt <- as.Date(c("2026-04-17", NA, NA, NA, NA))
  # Same district, source and title (case and spacing aside), first seen the old one's next run.
  expect_equal(relisted_next_run(d, src, title, first, nxt), c(TRUE, FALSE, FALSE, FALSE, FALSE))
  # A different title, source or district, or a later run, is not a relisting.
  expect_equal(relisted_next_run(d[c(1, 3)], src[c(1, 3)], c("Custodian", "Elementary Teacher"), first[c(1, 3)],
                                 as.Date(c("2026-04-17", NA))), c(FALSE, FALSE))
  expect_false(relisted_next_run(d[1], src[1], title[1], first[1], as.Date("2026-04-24")))
  expect_false(relisted_next_run(d[1], src[1], title[1], first[1], NA))
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
