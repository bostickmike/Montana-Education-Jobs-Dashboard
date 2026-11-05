# Tier-2 data-quality invariant sweep -- modelled on the LASSO project's
# tests/invariants.R. Runs against the *committed* pipeline-output CSVs (the
# same files app.R reads), and asserts properties that must hold no matter
# what the postings/salaries happen to be this week. Each block names the
# real failure it guards against.
#
# These are cheap (plain CSV reads) and belong in the weekly CI right after
# verify_schema.R, as a blocking gate before the data is committed: a broken
# classifier, a bad join, or a units error in a scraper shows up here as a
# hard failure instead of shipping to the live dashboard.
#
# Not duplicated here (already covered elsewhere):
#   - Total == sum of parts            -> test-data-integrity.R
#   - title encoding / mojibake        -> test-data-integrity.R
#   - schema / expected columns        -> test-schema-check.R
#   - reactive semantics, double-count -> test-app-reactives.R

suppressMessages({
  library(dplyr)
})

MT <- function(name) here::here("Mt_Ed_Jobs", name)
read_mt <- function(name, ...) {
  p <- MT(name)
  skip_if_not(file.exists(p), paste(name, "not found"))
  df <- utils::read.csv(p, stringsAsFactors = FALSE, ...)
  df[, setdiff(names(df), "X"), drop = FALSE]   # drop write.csv row-index col
}

# every numeric-looking column across a frame, as one vector
numeric_cells <- function(df) {
  num <- df[vapply(df, function(c) is.numeric(c), logical(1))]
  unlist(num, use.names = FALSE)
}

ALL_OUTPUT_CSVS <- c(
  "combinedclean.csv", "k12jobanalysis.csv", "allsum.csv", "allnow.csv",
  "allsum_he.csv", "allnow_he.csv", "k12_district_weekly_totals.csv",
  "he_institution_weekly_totals.csv", "salarymap2.csv", "salarymap.csv",
  "facultydata.csv", "job_duration_spells.csv", "he_job_duration_spells.csv",
  "data_dictionary.csv"
)


# ---------------------------------------------------------------------------
# 1. No NaN / Inf in any numeric cell of any shipped CSV.
#    (LASSO caught a real shipped bug this way -- CD_Report 47537c4, an
#    Inf/NaN leaking into a rendered table cell.)
# ---------------------------------------------------------------------------
test_that("no committed CSV has a NaN or Inf in a numeric cell", {
  for (f in ALL_OUTPUT_CSVS) {
    v <- numeric_cells(read_mt(f))
    bad <- v[is.nan(v) | is.infinite(v)]
    expect_equal(length(bad), 0,
                 info = sprintf("%s has %d NaN/Inf numeric cell(s)", f, length(bad)))
  }
})

test_that("no committed CSV has the literal string 'NaN' / 'Inf' / '-Inf' in a character cell", {
  for (f in ALL_OUTPUT_CSVS) {
    df <- read_mt(f)
    chr <- df[vapply(df, is.character, logical(1))]
    hits <- vapply(chr, function(col) any(trimws(col) %in% c("NaN", "Inf", "-Inf", "NA%")), logical(1))
    expect_false(any(hits), info = sprintf("%s: string NaN/Inf in column(s) %s",
                                           f, paste(names(hits)[hits], collapse = ", ")))
  }
})


# ---------------------------------------------------------------------------
# 2. Range and sign -- a value out of these bounds is a units error or a bad
#    join, not real data.
# ---------------------------------------------------------------------------
test_that("weekly posting counts are non-negative integers", {
  for (f in c("k12_district_weekly_totals.csv", "he_institution_weekly_totals.csv")) {
    n <- read_mt(f)$n
    expect_true(all(n >= 0 & n == as.integer(n)), info = f)
  }
  for (f in c("allsum.csv", "allsum_he.csv")) {
    s <- read_mt(f)$sum
    expect_true(all(s >= 0), info = f)
  }
  for (f in c("allnow.csv", "allnow_he.csv")) {
    s <- read_mt(f)$Sum
    expect_true(all(s >= 0), info = f)
  }
})

test_that("salarymap2.csv (K-12): salary / staffing / finance columns are in a plausible band", {
  d <- read_mt("salarymap2.csv")
  in_band <- function(x, lo, hi) all(is.na(x) | (x >= lo & x <= hi))

  expect_true(in_band(d$Teacher_Avg_Salary, 20000, 150000), info = "Teacher_Avg_Salary")
  # Lower bound accommodates small rural districts reporting part-time/stipend
  # instructional staff at the 10th percentile (e.g. Philipsburg's real $2,900
  # row in DLI's Western region PDF).
  expect_true(in_band(d$Teacher_Salary_10th_Pctile, 2500, 150000), info = "10th pctile")
  expect_true(in_band(d$Teacher_Salary_90th_Pctile, 20000, 250000), info = "90th pctile")
  # 10th <= avg <= 90th wherever all three are present
  band <- d[!is.na(d$Teacher_Salary_10th_Pctile) & !is.na(d$Teacher_Avg_Salary) &
              !is.na(d$Teacher_Salary_90th_Pctile), ]
  expect_true(all(band$Teacher_Salary_10th_Pctile <= band$Teacher_Avg_Salary &
                    band$Teacher_Avg_Salary <= band$Teacher_Salary_90th_Pctile),
              info = "10th <= avg <= 90th")

  expect_true(in_band(d$Teacher_Count, 0, 5000), info = "Teacher_Count")
  expect_true(in_band(d$Teachers_Total_FTE, 0, 6000), info = "Teachers_Total_FTE")
  expect_true(in_band(d$Enrollment, 0, 60000), info = "Enrollment")
  expect_true(in_band(d$Total_General_Fund_Expenditure, 0, 5e8), info = "General Fund expenditure")
})

test_that("salarymap.csv (HE): faculty salary / count columns are in a plausible band", {
  d <- read_mt("salarymap.csv")
  in_band <- function(x, lo, hi) all(is.na(x) | (x >= lo & x <= hi))
  expect_true(in_band(d$Faculty_Avg_Salary, 15000, 250000), info = "Faculty_Avg_Salary")
  expect_true(in_band(d$Faculty_Avg_Salary_Professor, 20000, 300000), info = "Professor salary")
  expect_true(in_band(d$Faculty_Count, 0, 5000), info = "Faculty_Count")
  expect_true(in_band(d$Enrollment, 0, 60000), info = "Enrollment")
})

test_that("percentage / rate columns are stored as proportions in [0, 1] (not 0-100)", {
  # These reach app.R as proportions and get scales::percent()'d there --
  # a value > 1 means the pipeline already multiplied by 100, which would
  # render as e.g. "8500%".
  d2 <- read_mt("salarymap2.csv")
  for (col in c("Mining_Employment_Share", "Child_Poverty_Rate")) {
    x <- d2[[col]]
    expect_true(all(is.na(x) | (x >= 0 & x <= 1)), info = paste("salarymap2", col))
  }
  # 5-year population change: a district gaining/losing >50% in 5yr is a data error
  expect_true(all(is.na(d2$Population_Change_Pct) | abs(d2$Population_Change_Pct) <= 0.5),
              info = "salarymap2 Population_Change_Pct")

  dh <- read_mt("salarymap.csv")
  for (col in c("Mining_Employment_Share", "Pell_Recipient_Share")) {
    x <- dh[[col]]
    expect_true(all(is.na(x) | (x >= 0 & x <= 1)), info = paste("salarymap", col))
  }
  expect_true(all(is.na(dh$Enrollment_Change_Pct) | abs(dh$Enrollment_Change_Pct) <= 1),
              info = "salarymap Enrollment_Change_Pct")
})

test_that("Latitude / Longitude put every mapped entity inside Montana's bounding box", {
  for (f in c("salarymap2.csv", "salarymap.csv")) {
    d <- read_mt(f)
    lat <- d$Latitude; lon <- d$Longitude
    ok <- is.na(lat) | is.na(lon) | (lat >= 44.3 & lat <= 49.1 & lon >= -116.1 & lon <= -104.0)
    expect_true(all(ok), info = sprintf("%s: %d entity/entities outside the MT bbox",
                                        f, sum(!ok)))
  }
})


# ---------------------------------------------------------------------------
# 3. Referential integrity -- the joins app.R and the pipeline rely on.
# ---------------------------------------------------------------------------
test_that("Posting_ID is unique within combinedclean.csv and within each week of k12jobanalysis.csv", {
  cc <- read_mt("combinedclean.csv")
  expect_equal(anyDuplicated(cc$Posting_ID), 0,
               info = "duplicate Posting_ID in combinedclean.csv")

  k12 <- read_mt("k12jobanalysis.csv")
  dup_within_week <- k12 %>%
    group_by(Archive_Date) %>%
    summarize(dups = anyDuplicated(Posting_ID), .groups = "drop") %>%
    filter(dups != 0)
  expect_equal(nrow(dup_within_week), 0,
               info = "duplicate Posting_ID within a single Archive_Date in k12jobanalysis.csv")
})

test_that("every district in salarymap2.csv is a real row in k12_district_registry.csv", {
  reg <- utils::read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  sm  <- read_mt("salarymap2.csv")
  orphans <- setdiff(unique(sm$District), unique(reg$District))
  expect_equal(length(orphans), 0,
               info = paste("salarymap2 districts not in the registry:",
                            paste(orphans, collapse = "; ")))
})

test_that("every this-week district total ties out to a distinct Posting_ID count in combinedclean.csv", {
  cc  <- read_mt("combinedclean.csv")
  wt  <- read_mt("k12_district_weekly_totals.csv")
  latest <- max(as.Date(wt$Archive_Date))
  this_week <- wt %>% filter(as.Date(Archive_Date) == latest)

  from_cc <- cc %>%
    filter(District %in% this_week$District) %>%
    group_by(District) %>%
    summarize(n_cc = n_distinct(Posting_ID), .groups = "drop")

  merged <- this_week %>%
    select(District, n_wt = n) %>%
    full_join(from_cc, by = "District")
  # combinedclean.csv is "this week only", so every district present in one
  # should be present in the other with the same count.
  mismatch <- merged %>% filter(is.na(n_wt) | is.na(n_cc) | n_wt != n_cc)
  expect_equal(nrow(mismatch), 0,
               info = paste(utils::capture.output(print(mismatch)), collapse = "\n"))
})


# ---------------------------------------------------------------------------
# 4. Enum coverage -- a value app.R's switch/recode/ifelse logic doesn't
#    know about renders blank or falls through a case.
# ---------------------------------------------------------------------------
test_that("Data_Coverage is one of the three documented values", {
  dc <- read_mt("salarymap2.csv")$Data_Coverage
  expect_true(all(is.na(dc) | dc %in% c("Full", "Partial")),
              info = paste("unexpected Data_Coverage:", paste(setdiff(unique(dc), c(NA, "Full", "Partial")), collapse = ", ")))
})

test_that("Posting_Identity_Method values all describe a known method", {
  m <- unique(c(read_mt("combinedclean.csv")$Posting_Identity_Method,
                read_mt("k12jobanalysis.csv")$Posting_Identity_Method))
  m <- m[!is.na(m) & nzchar(m)]
  # every method string should mention a URL, an OPI fallback, or a
  # source/title fallback -- not be some new un-audited scheme
  known <- grepl("URL|url|OPI fallback|Source fallback|title \\+", m)
  expect_true(all(known), info = paste("un-audited Posting_Identity_Method:",
                                       paste(m[!known], collapse = " | ")))
})

test_that("facultydata.csv holds only the two faculty Job_Types the pipeline keeps", {
  # Classification safeguards, item 10: the pipeline filters facultydata to
  # these two; any other value means a row came from somewhere else.
  jt <- unique(read_mt("facultydata.csv")$Job_Type)
  expect_true(all(!is.na(jt) & jt %in% c("Instructor/Teacher/Faculty", "Adjunct/Part-Time Faculty")),
              info = paste("unexpected Job_Type:", paste(jt, collapse = ", ")))
})

test_that("k12jobanalysis.csv holds only Teacher rows", {
  pos <- unique(read_mt("k12jobanalysis.csv")$position)
  expect_identical(pos, "Teacher", info = paste("unexpected position:", paste(pos, collapse = ", ")))
})

# Classification safeguards (claude-notes 2026-11-01 proposal), items 7 and 8:
# every committed bucket equals what today's classifier gives its title. A
# classifier change must ship with its reclassified data; otherwise history
# silently mixes old and new buckets (the 2026-11-01 audit found ~400 misrouted
# titles that no check caught). Also catches a K-12 position value the
# classifier can't produce (item 7). Fix by reclassifying the committed files.
classification_mismatches <- function(got, want, title) {
  same <- (is.na(got) & is.na(want)) | (!is.na(got) & !is.na(want) & got == want)
  bad <- !same
  if (!any(bad)) return("")
  x <- unique(data.frame(title = title[bad], committed = got[bad], classifier = want[bad]))
  paste(sum(bad), "rows differ, e.g.:", paste(utils::head(sprintf("'%s': %s -> %s", x$title, x$committed, x$classifier), 8),
                                         collapse = " | "))
}

test_that("committed K-12 position / Category / Broad_Category equal the current classifier", {
  cc <- read_mt("combinedclean.csv")
  k <- read_mt("k12jobanalysis.csv")
  expect_identical(classification_mismatches(cc$position, classify_k12_position(cc$title), cc$title), "",
                   label = "combinedclean.csv position")
  expect_identical(classification_mismatches(k$position, classify_k12_position(k$title), k$title), "",
                   label = "k12jobanalysis.csv position")
  expect_identical(classification_mismatches(k$Category, classify_k12_subject(k$title), k$title), "",
                   label = "k12jobanalysis.csv Category")
  expect_identical(classification_mismatches(k$Broad_Category, classify_k12_broad_category(k$Category), k$title), "",
                   label = "k12jobanalysis.csv Broad_Category")
})

test_that("committed HE Job_Type / Category equal the current classifier", {
  fd <- read_mt("facultydata.csv")
  expect_identical(classification_mismatches(fd$Job_Type, classify_he_job_type(fd$Title), fd$Title), "",
                   label = "facultydata.csv Job_Type")
  expect_identical(classification_mismatches(fd$Category, classify_he_faculty_category(fd$Title), fd$Title), "",
                   label = "facultydata.csv Category")
})

test_that("no placeholder board entry ships in any posting-level output (item 10)", {
  titles <- list(combinedclean = read_mt("combinedclean.csv")$title,
                 k12jobanalysis = read_mt("k12jobanalysis.csv")$title,
                 facultydata = read_mt("facultydata.csv")$Title)
  if (file.exists(MT("hedata.xlsx"))) titles$hedata <- readxl::read_excel(MT("hedata.xlsx"))$Title
  for (n in names(titles)) {
    hit <- unique(titles[[n]][is_placeholder_posting(titles[[n]])])
    expect(length(hit) == 0, paste(n, "ships placeholder titles:", paste(head(hit, 5), collapse = " | ")))
  }
})

test_that("duration-spell dummies agree with the position / job type they encode (item 10)", {
  # The 2026-11-01 audit found is_support_staff never set for Transportation
  # and Food Services.
  s <- read_mt("job_duration_spells.csv")
  support <- c("Support Services", "Paraprofessional", "Custodial/Maintenance", "Transportation", "Food Services")
  expect_equal(s$is_support_staff, as.integer(s$Position %in% support))
  expect_equal(s$is_admin, as.integer(s$Position == "Administration"))
  h <- read_mt("he_job_duration_spells.csv")
  expect_equal(h$is_faculty, as.integer(h$Job_Type == "Instructor/Teacher/Faculty"))
  expect_equal(h$is_adjunct, as.integer(h$Job_Type == "Adjunct/Part-Time Faculty"))
})

test_that("every Broad_Category / Category in the summary data has a color AND a collapse-map entry in app.R", {
  skip_if_not_installed("shiny")
  app_dir <- here::here("Mt_Ed_Jobs")
  skip_if_not(dir.exists(app_dir))
  old <- setwd(app_dir); on.exit(setwd(old), add = TRUE)
  env <- new.env()
  suppressMessages(sys.source("app.R", envir = env))

  # detail-mode categories must each have a detail color
  k12_detail <- setdiff(unique(env$k12sum$Broad_Category), NA)
  expect_true(all(k12_detail %in% names(env$K12_CATEGORY_COLORS_DETAIL)),
              info = paste("K-12 detail category with no color:",
                           paste(setdiff(k12_detail, names(env$K12_CATEGORY_COLORS_DETAIL)), collapse = ", ")))
  # collapsed-mode categories must each have an agg color
  k12_agg <- setdiff(unique(env$k12sum_agg$Broad_Category), NA)
  expect_true(all(k12_agg %in% names(env$K12_CATEGORY_COLORS_AGG)),
              info = paste("K-12 agg category with no color:",
                           paste(setdiff(k12_agg, names(env$K12_CATEGORY_COLORS_AGG)), collapse = ", ")))

  he_detail <- setdiff(as.character(unique(env$hesum_he$Category)), NA)
  expect_true(all(he_detail %in% names(env$HE_CATEGORY_COLORS_DETAIL)),
              info = paste("HE detail category with no color:",
                           paste(setdiff(he_detail, names(env$HE_CATEGORY_COLORS_DETAIL)), collapse = ", ")))
  he_agg <- setdiff(as.character(unique(env$hesum_he_agg$Category)), NA)
  expect_true(all(he_agg %in% names(env$HE_CATEGORY_COLORS_AGG)),
              info = paste("HE agg category with no color:",
                           paste(setdiff(he_agg, names(env$HE_CATEGORY_COLORS_AGG)), collapse = ", ")))
})


# ---------------------------------------------------------------------------
# 5. Temporal sanity.
# ---------------------------------------------------------------------------
test_that("every Archive_Date parses and none is in the future", {
  for (f in c("combinedclean.csv", "k12jobanalysis.csv", "allsum.csv", "allsum_he.csv",
              "k12_district_weekly_totals.csv", "he_institution_weekly_totals.csv",
              "facultydata.csv")) {
    d <- read_mt(f)
    ad <- suppressWarnings(as.Date(d$Archive_Date))
    expect_false(any(is.na(ad)), info = paste(f, "has an unparseable Archive_Date"))
    expect_false(any(ad > Sys.Date() + 1), info = paste(f, "has a future Archive_Date"))
  }
})

test_that("the accumulated history only ever grows -- the newest week is not smaller than half the prior week", {
  # A soft version of .github/scripts/sanity_check.R, kept in the test suite
  # so a local run flags a systemic scrape failure too.
  wt <- read_mt("k12_district_weekly_totals.csv") %>%
    group_by(Archive_Date) %>% summarize(total = sum(n), .groups = "drop") %>%
    arrange(Archive_Date)
  skip_if(nrow(wt) < 2, "need >= 2 weeks of history")
  newest <- tail(wt$total, 1); prior <- tail(wt$total, 2)[1]
  expect_gt(newest, prior * 0.5)
})


# ---------------------------------------------------------------------------
# 6. Posted pay and pay estimates. Posted pay is read out of free text, so a
#    fee, a benefit's value or a units slip can look like a wage; the
#    estimates come from re-downloaded reference tables (BLS, IPEDS).
# ---------------------------------------------------------------------------
read_hedata_mt <- function() {
  p <- here::here("Mt_Ed_Jobs", "hedata.xlsx")
  skip_if_not(file.exists(p), "hedata.xlsx not found")
  as.data.frame(readxl::read_xlsx(p))
}

test_that("no posted pay outside PAY_PLAUSIBLE_RANGE for its unit ships (drop_implausible_pay ran)", {
  for (d in list(K12 = read_mt("combinedclean.csv"), HE = read_hedata_mt())) {
    if (!"Pay_Min" %in% names(d)) next   # HE files before the first run with pay
    bad <- is_implausible_pay(d$Pay_Min, d$Pay_Max, d$Pay_Unit)
    expect_equal(sum(bad), 0, info = paste("implausible pay:", paste(head(d$Pay_Text[bad], 3), collapse = " | ")))
  }
})

test_that("every posted amount keeps the snippet it came from, and a unit never stands alone", {
  for (d in list(K12 = read_mt("combinedclean.csv"), HE = read_hedata_mt())) {
    if (!"Pay_Min" %in% names(d)) next
    has_pay <- !is.na(d$Pay_Min)
    expect_true(all(!is.na(d$Pay_Text[has_pay]) & nzchar(d$Pay_Text[has_pay])))
    expect_true(all(is.na(d$Pay_Unit[!has_pay])))
    expect_true(all(is.na(d$Pay_Max) == is.na(d$Pay_Min)))
  }
})

test_that("pay estimates are hourly or annual, in range, and say what they estimate", {
  for (d in list(K12 = read_mt("combinedclean.csv"), HE = read_hedata_mt())) {
    if (!"Est_Pay" %in% names(d)) next
    has <- !is.na(d$Est_Pay)
    expect_true(all(d$Est_Pay_Unit[has] %in% c("hour", "year")))
    expect_true(all(!is.na(d$Est_Occupation[has])))
    hourly <- has & d$Est_Pay_Unit %in% "hour"; annual <- has & d$Est_Pay_Unit %in% "year"
    # An hourly median in the annual column (or the reverse) is the units
    # slip these bounds catch; the top end allows UW's salary-book medians.
    expect_true(all(d$Est_Pay[hourly] >= 7 & d$Est_Pay[hourly] <= 150))
    expect_true(all(d$Est_Pay[annual] >= 15000 & d$Est_Pay[annual] <= 1500000))
  }
})

test_that("every reference table the estimates come from passes its own rules", {
  for (name in names(REFERENCE_TABLE_RULES)) {
    p <- here::here("Mt_Ed_Jobs", paste0(name, ".csv"))
    if (!file.exists(p)) next
    expect_null(reference_table_problem(read.csv(p, stringsAsFactors = FALSE), REFERENCE_TABLE_RULES[[name]]),
                info = name)
  }
})
