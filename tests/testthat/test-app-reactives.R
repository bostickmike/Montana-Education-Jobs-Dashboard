# Loads the real app.R (with the real committed CSVs) into an isolated
# environment and exercises its reactives directly via shiny::testServer,
# rather than mocking data. Ported from the Wyoming Education Jobs
# Dashboard's test-app-reactives.R, adapted to Montana's actual app.R:
# reactive/output/input IDs here were verified by reading Mt_Ed_Jobs/app.R in
# full rather than assumed to match Wyoming's (most of them do carry over
# unchanged, since app.R's server-side structure was ported near-verbatim,
# but the data shape underneath -- columns, and two whole features -- did
# not). See the skip notes below for what was deliberately left out.
#
# Deliberately NOT ported from Wyoming's version, because Montana's app.R has
# no equivalent (confirmed by reading app.R, not assumed):
#   - Sheridan/Gillette shared-vacancy-rate tests -- Montana's map_he has no
#     merged-entity/Vacancy_Rate_Shared case at all (see app.R's comment
#     above combined_map_data: "no merged-entity vacancy-rate case (each
#     Montana HE institution has its own independent IPEDS unitid)").
#   - Data_Coverage "Partial" tier tests -- Montana's combined_map_data has
#     no Data_Coverage column whatsoever (see the same comment: "there's no
#     Data_Coverage 'Partial' tier here"); grepping app.R for "Data_Coverage"
#     turns up only that comment, not a real column.
#   - Superintendent-salary tests -- Montana has no superintendent salary
#     source; its K-12 salary shape is DLI's Teacher_Avg_Salary plus a
#     10th/90th percentile band, not WSBA's base-salary-plus-prior-year pair.

skip_if_not_installed("shiny")

load_app <- function() {
  app_dir <- here::here("Mt_Ed_Jobs")
  skip_if_not(dir.exists(app_dir), "Mt_Ed_Jobs/ not found -- skipping app tests")
  old_wd <- setwd(app_dir)
  on.exit(setwd(old_wd), add = TRUE)

  env <- new.env()
  suppressMessages(sys.source("app.R", envir = env))
  env
}

# Copies the real Mt_Ed_Jobs/ app folder into a scratch tempdir, applies
# corrupt_fn to one file in the copy (not the real committed data), then
# loads app.R from there -- for testing the schema guard's behavior when a
# dataset is actually broken, without touching anything real.
load_app_with_corrupted_file <- function(file_name, corrupt_fn) {
  app_dir <- here::here("Mt_Ed_Jobs")
  skip_if_not(dir.exists(app_dir), "Mt_Ed_Jobs/ not found -- skipping app tests")

  scratch_dir <- withr::local_tempdir()
  file.copy(list.files(app_dir, full.names = TRUE), scratch_dir, recursive = TRUE)
  corrupt_fn(file.path(scratch_dir, file_name))

  old_wd <- setwd(scratch_dir)
  on.exit(setwd(old_wd), add = TRUE)

  env <- new.env()
  suppressMessages(sys.source("app.R", envir = env))
  env
}

test_that("HE longitudinal 'Total' view is not double-counted", {
  # Same shape of bug as Wyoming's original HE double-counting regression:
  # filtered_hesum() returns the entire hesum_he table (Total row + every
  # institution's row) whenever "Total" is selected, and he_windowed() must
  # drop the Total row before he_longitudinal_plot sums -- otherwise every
  # category is inflated exactly 2x.
  env <- load_app()

  shiny::testServer(env$server, {
    session$setInputs(
      inst_trend = "Total",
      he_category = sort(unique(env$hesum_he$Category)),
      he_scroll = c(min(env$hesum_he$Archive_Date), max(env$hesum_he$Archive_Date)),
      he_chart_type = "all",
      he_detail_level_trends = "detail"
    )

    windowed <- he_windowed()
    expect_true(all(windowed$Institution != "Total"))

    latest_date <- max(windowed$Archive_Date)
    observed <- windowed %>%
      dplyr::filter(Archive_Date == latest_date) %>%
      dplyr::group_by(Category) %>%
      dplyr::summarize(sum = sum(sum), .groups = "drop")

    # hesum_he carries a Job_Type column (Instructor/Teacher/Faculty vs.
    # Adjunct/Part-Time Faculty); "All Jobs" mode sums across it, so the
    # expected total does too.
    expected <- env$hesum_he %>%
      dplyr::filter(Archive_Date == latest_date, Institution == "Total") %>%
      dplyr::group_by(Category) %>%
      dplyr::summarize(sum = sum(sum), .groups = "drop")

    merged <- dplyr::inner_join(observed, expected, by = "Category", suffix = c("_observed", "_expected"))
    expect_gt(nrow(merged), 0)
    expect_equal(merged$sum_observed, merged$sum_expected)
  })
})

test_that("K-12 longitudinal 'Total' view is not double-counted", {
  # Same shape of bug is structurally possible here too (filtered_k12sum()
  # also returns everything unfiltered for "Total") -- df_windowed() already
  # guards against it; this pins that guard in place.
  env <- load_app()

  shiny::testServer(env$server, {
    session$setInputs(
      district_trend = "Total",
      broad_category = sort(unique(env$k12sum$Broad_Category)),
      k12_scroll = c(min(env$k12sum$Archive_Date), max(env$k12sum$Archive_Date)),
      k12_detail_level_trends = "detail"
    )

    windowed <- df_windowed()
    expect_true(all(windowed$Broad_Category %in% unique(env$k12sum$Broad_Category)))

    latest_date <- max(windowed$Archive_Date)
    observed <- windowed %>%
      dplyr::filter(Archive_Date == latest_date) %>%
      dplyr::group_by(Broad_Category) %>%
      dplyr::summarize(sum = sum(sum), .groups = "drop")

    expected <- env$k12sum %>%
      dplyr::filter(Archive_Date == latest_date, District == "Total") %>%
      dplyr::group_by(Broad_Category) %>%
      dplyr::summarize(sum = sum(sum), .groups = "drop")

    merged <- dplyr::inner_join(observed, expected, by = "Broad_Category", suffix = c("_observed", "_expected"))
    expect_gt(nrow(merged), 0)
    expect_equal(merged$sum_observed, merged$sum_expected)
  })
})

test_that("HE and K-12 reactives don't error across every institution/district", {
  env <- load_app()

  shiny::testServer(env$server, {
    for (inst in sort(unique(env$hesum_he$Institution))) {
      session$setInputs(inst_trend = inst, he_category = sort(unique(env$hesum_he$Category)),
                         he_scroll = c(min(env$hesum_he$Archive_Date), max(env$hesum_he$Archive_Date)),
                         he_chart_type = "all", he_detail_level_trends = "detail")
      expect_no_error(he_windowed())
      expect_no_error(output$he_longitudinal_plot)
    }
    for (inst in sort(unique(env$henowsum_he$Institution))) {
      session$setInputs(
        inst_current = inst,
        he_detail_level_current = "detail",
        he_current_appointment = "all"
      )
      expect_no_error(output$he_current_trends_table)
    }

    for (d in sort(unique(env$k12sum$District))) {
      session$setInputs(district_trend = d, broad_category = sort(unique(env$k12sum$Broad_Category)),
                         k12_scroll = c(min(env$k12sum$Archive_Date), max(env$k12sum$Archive_Date)),
                         k12_detail_level_trends = "detail")
      expect_no_error(df_windowed())
      expect_no_error(output$k12_longitudinal_plot)
    }
    for (d in sort(unique(env$k12nowsum$District))) {
      session$setInputs(district_current = d, k12_detail_level_current = "detail")
      expect_no_error(output$k12_current_trends_table)
    }
  })
})

test_that("higher-ed appointment classifier separates adjunct, faculty, and other roles", {
  env <- load_app()

  expect_identical(
    env$classify_he_appointment(c(
      "Adjunct Mathematics Instructor",
      "Biology Professor",
      "Admissions Specialist"
    )),
    c(
      "Adjunct/part-time faculty",
      "Faculty/instructor (non-adjunct)",
      "Other / not faculty"
    )
  )
})

test_that("make_sparkline_svg draws a rising trend with a green endpoint and a falling trend with a red one", {
  env <- load_app()

  rising <- env$make_sparkline_svg(c(10, 15, 20))
  expect_match(rising, "^<svg")
  expect_match(rising, "#1baf7a", fixed = TRUE)

  falling <- env$make_sparkline_svg(c(20, 15, 10))
  expect_match(falling, "#e34948", fixed = TRUE)

  flat <- env$make_sparkline_svg(c(10, 10, 10))
  expect_match(flat, "#999999", fixed = TRUE)
})

test_that("make_sparkline_svg handles too little data without erroring", {
  env <- load_app()

  expect_equal(env$make_sparkline_svg(numeric(0)), "")
  expect_equal(env$make_sparkline_svg(c(5)), "")
  expect_equal(env$make_sparkline_svg(c(NA, NA)), "")
  # One real value plus NAs still isn't enough to draw a line between two points.
  expect_equal(env$make_sparkline_svg(c(5, NA, NA)), "")
})

test_that("compute_wow_delta skips an extra same-week snapshot instead of comparing against it", {
  env <- load_app()

  # A real week-old snapshot, plus an extra same-week re-run 1 day before
  # "latest" (the exact failure mode min_days_back guards against).
  weekly <- data.frame(
    Archive_Date = as.Date(c("2026-07-30", "2026-08-05", "2026-08-06")),
    n = c(100, 108, 111)
  )
  # Without the gap guard this would return 111 - 108 = 3 (comparing
  # against yesterday's extra run); with it, it should skip the too-recent
  # 2026-08-05 snapshot and compare against the real week-old one.
  expect_equal(env$compute_wow_delta(weekly), 111 - 100)
})

test_that("compute_wow_delta returns NA when no snapshot is old enough to count as 'last week'", {
  env <- load_app()

  weekly <- data.frame(
    Archive_Date = as.Date(c("2026-08-05", "2026-08-06")),
    n = c(50, 55)
  )
  expect_true(is.na(env$compute_wow_delta(weekly)))
})

test_that("compute_vacancy_rate_domain falls back to a placeholder range instead of Inf/-Inf when every rate is NA", {
  env <- load_app()

  expect_equal(env$compute_vacancy_rate_domain(c(NA_real_, NA_real_, NA_real_)), c(0, 1))
  expect_equal(env$compute_vacancy_rate_domain(c(0.05, NA_real_, 0.20)), c(0.05, 0.20))
})

test_that("clean committed data produces no schema-guard issues", {
  env <- load_app()
  expect_equal(env$DATA_LOAD_ISSUES, character(0))
})

test_that("a dataset missing an expected column degrades instead of crashing app.R, and names the source", {
  # Regression for the "if something breaks, the dashboard should alert you
  # which data source is broken" pattern (ported from Wyoming) --
  # validate_and_pad_schema() is what turns a missing column into a padded
  # NA field plus a recorded issue, instead of app.R crashing at load time
  # with a bare "object 'Teachers_Total_FTE' not found" that names nothing.
  env <- load_app_with_corrupted_file("salarymap2.csv", function(path) {
    df <- read.csv(path)
    df$Teachers_Total_FTE <- NULL
    write.csv(df, path, row.names = FALSE)
  })

  expect_length(env$DATA_LOAD_ISSUES, 1)
  expect_match(env$DATA_LOAD_ISSUES, "salarymap2\\.csv is missing expected column\\(s\\): Teachers_Total_FTE")
  # The rest of the app still built successfully -- the missing column was
  # padded with NA rather than left absent, so downstream code that
  # references it by name (Vacancy_Rate's calculation) didn't hard-error.
  expect_true(is.data.frame(env$combined_map_data))
  expect_true(nrow(env$combined_map_data) > 0)
})

test_that("the Home-tab data-issue banner renders when there are load issues, and stays hidden when there aren't", {
  env <- load_app()
  shiny::testServer(env$server, {
    # req(FALSE) inside renderUI surfaces as a shiny.silent.error when the
    # output is accessed directly in testServer (rather than just quietly
    # returning NULL, as it would when rendered normally in a browser) --
    # that's the correct "nothing to show" signal here.
    expect_error(output$data_load_issues_banner, class = "shiny.silent.error")
  })

  broken_env <- load_app_with_corrupted_file("salarymap2.csv", function(path) {
    df <- read.csv(path)
    df$Teachers_Total_FTE <- NULL
    write.csv(df, path, row.names = FALSE)
  })
  shiny::testServer(broken_env$server, {
    expect_no_error(output$data_load_issues_banner)
    expect_false(is.null(output$data_load_issues_banner))
  })
})

test_that("Students_Per_Teacher is computed for both K-12 districts (vs. Teachers_Total_FTE) and HE institutions (vs. Faculty_Count)", {
  env <- load_app()
  expect_true(all(c("Enrollment", "Students_Per_Teacher") %in% names(env$combined_map_data)))

  he <- env$combined_map_data[env$combined_map_data$Type == "Higher Ed Institution", ]
  skip_if(nrow(he) == 0, "no HE rows in committed data -- skipping")
  expect_true(any(!is.na(he$Students_Per_Teacher)))
  he_values <- he$Students_Per_Teacher[!is.na(he$Students_Per_Teacher)]
  # Loose sanity range, not a tight real-world one -- just catching a
  # units/sign error, not asserting what a plausible ratio looks like.
  expect_true(all(he_values > 0 & he_values < 100))

  k12_with_fte <- env$combined_map_data[env$combined_map_data$Type == "K-12 District" &
                                           !is.na(env$combined_map_data$Vacancy_Denominator) &
                                           env$combined_map_data$Vacancy_Denominator > 0, ]
  skip_if(nrow(k12_with_fte) == 0, "no K-12 rows with teacher FTE in committed data -- skipping")
  expect_true(any(!is.na(k12_with_fte$Students_Per_Teacher)))
  # Loose sanity range -- real Montana districts in the committed data run
  # roughly 9-18 students per teacher; this bound exists to catch a
  # units/column mixup, not to assert what a plausible ratio looks like.
  real_values <- k12_with_fte$Students_Per_Teacher[!is.na(k12_with_fte$Students_Per_Teacher)]
  expect_true(all(real_values > 0 & real_values < 100))
})

test_that("Enrollment_Change_Pct is a real institution-level 5-year trend for HE, and NA (not missing) for K-12", {
  # Montana has real IPEDS enrollment-trend data for HE
  # (ipeds_enrollment_scraper.R) but no district-level enrollment-trend pull
  # for K-12 -- map_k12's mutate() hardcodes Enrollment_Change_Pct to
  # NA_real_ rather than leaving the column absent, distinct from
  # Population_Change_Pct (county-level, real for K-12 via the Census join).
  env <- load_app()
  expect_true("Enrollment_Change_Pct" %in% names(env$combined_map_data))

  he <- env$combined_map_data[env$combined_map_data$Type == "Higher Ed Institution", ]
  skip_if(nrow(he) == 0, "no HE rows in committed data -- skipping")
  expect_true(any(!is.na(he$Enrollment_Change_Pct)))
  # Loose sanity range -- a real 5-year FTE swing of more than 90% at any
  # Montana public HE institution would be implausible and more likely a
  # units error than genuine enrollment collapse/boom.
  he_values <- he$Enrollment_Change_Pct[!is.na(he$Enrollment_Change_Pct)]
  expect_true(all(he_values > -0.9 & he_values < 0.9))
  # Not every institution moved the same direction (real data, not a
  # hardcoded sign).
  expect_true(any(he_values > 0) && any(he_values < 0))

  k12 <- env$combined_map_data[env$combined_map_data$Type == "K-12 District", ]
  skip_if(nrow(k12) == 0, "no K-12 rows in committed data -- skipping")
  expect_true(all(is.na(k12$Enrollment_Change_Pct)))
})

test_that("Pell_Recipient_Share is real for HE (FSA) and NA (not missing) for K-12 (no SAIPE equivalent)", {
  # HE analogue of Child_Poverty_Rate (SAIPE, K-12-only) -- a different
  # federal program since SAIPE has no HE equivalent. map_he's salarymap.csv
  # join supplies real values; map_k12's mutate() hardcodes NA_real_.
  env <- load_app()
  expect_true(all(c("Pell_Recipient_Share", "Pell_Year") %in% names(env$combined_map_data)))

  he <- env$combined_map_data[env$combined_map_data$Type == "Higher Ed Institution", ]
  skip_if(nrow(he) == 0, "no HE rows in committed data -- skipping")
  expect_true(any(!is.na(he$Pell_Recipient_Share)))
  he_values <- he$Pell_Recipient_Share[!is.na(he$Pell_Recipient_Share)]
  expect_true(all(he_values > 0 & he_values < 1))

  k12 <- env$combined_map_data[env$combined_map_data$Type == "K-12 District", ]
  skip_if(nrow(k12) == 0, "no K-12 rows in committed data -- skipping")
  expect_true(all(is.na(k12$Pell_Recipient_Share)))
})

test_that("county-level Census context is present for both K-12 and HE, and sibling entities in the same county share values", {
  # Real per-county figures on both K-12 and HE rows (HE joined via
  # salarymap.csv's County column). Two entities that sit in the same county
  # must show the EXACT same county-level figures, not two different ones --
  # this is a county-level join, not an entity-level one.
  #
  # Unlike Wyoming (whose 9 public HE institutions each sit in a different
  # county, so WY's version of this test instead asserts no two HE rows
  # share a county), Montana genuinely has multiple HE institutions sharing
  # a county -- e.g. Great Falls College MSU and University of Providence
  # both sit in Cascade County; Montana Tech and Highlands College both sit
  # in Silver Bow County. So the HE check here mirrors the K-12 sibling
  # check (same-county rows must agree), not a uniqueness assertion.
  env <- load_app()
  census_cols <- c("Median_Household_Income", "Median_Gross_Rent", "Mining_Employment_Share", "Population_Change_Pct")
  expect_true(all(census_cols %in% names(env$combined_map_data)))

  he <- env$combined_map_data[env$combined_map_data$Type == "Higher Ed Institution", ]
  skip_if(nrow(he) == 0, "no HE rows in committed data -- skipping")
  expect_true(any(!is.na(he$Median_Household_Income)))

  he_with_income <- he[!is.na(he$Median_Household_Income), ]
  he_county_counts <- table(he_with_income$County)
  he_shared_counties <- names(he_county_counts[he_county_counts >= 2])
  skip_if(length(he_shared_counties) == 0, "no county with 2+ mapped HE institutions in committed data -- skipping")
  for (cty in he_shared_counties) {
    siblings <- he_with_income[he_with_income$County == cty, ]
    expect_equal(length(unique(siblings$Median_Household_Income)), 1)
  }

  k12 <- env$combined_map_data[env$combined_map_data$Type == "K-12 District", ]
  skip_if(nrow(k12) == 0, "no K-12 rows in committed data -- skipping")
  expect_true(any(!is.na(k12$Median_Household_Income)))

  siblings <- k12[k12$County == k12$County[which(!is.na(k12$Median_Household_Income))[1]] &
                    !is.na(k12$Median_Household_Income), ]
  skip_if(nrow(siblings) < 2, "no county with 2+ mapped K-12 districts in committed data -- skipping")
  expect_equal(length(unique(siblings$Median_Household_Income)), 1)
  expect_equal(length(unique(siblings$Mining_Employment_Share)), 1)
})

test_that("Child_Poverty_Rate is district-level (unlike the county-level Census columns), so sibling districts can genuinely differ", {
  # Unlike Median_Household_Income etc. (real county-level joins, correctly
  # identical for sibling districts), Child_Poverty_Rate is a real
  # DISTRICT-level SAIPE figure and two districts in the same county are NOT
  # expected to share it -- confirmed with real committed data (Bozeman
  # Public Schools and Belgrade School District 44 are both Gallatin County
  # but report different real child poverty rates: ~4.6% vs ~5.4%). Also
  # present (NA) on HE rows -- no HE analogue of SAIPE.
  env <- load_app()
  expect_true("Child_Poverty_Rate" %in% names(env$combined_map_data))

  he <- env$combined_map_data[env$combined_map_data$Type == "Higher Ed Institution", ]
  skip_if(nrow(he) == 0, "no HE rows in committed data -- skipping")
  expect_true(all(is.na(he$Child_Poverty_Rate)))

  k12 <- env$combined_map_data[env$combined_map_data$Type == "K-12 District", ]
  k12_with_rate <- k12[!is.na(k12$Child_Poverty_Rate), ]
  skip_if(nrow(k12_with_rate) == 0, "no K-12 rows with a child poverty rate in committed data -- skipping")
  expect_true(all(k12_with_rate$Child_Poverty_Rate >= 0 & k12_with_rate$Child_Poverty_Rate <= 1))

  gallatin <- k12_with_rate[k12_with_rate$County == "Gallatin County", ]
  skip_if(nrow(gallatin) < 2, "fewer than 2 mapped Gallatin County districts with a rate in committed data -- skipping")
  expect_true(length(unique(gallatin$Child_Poverty_Rate)) > 1)
})
