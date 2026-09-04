# Ported from Wyoming's test-drift-check.R. All the pure-function tests
# carry over unchanged (the functions themselves are state-agnostic) --
# only build_source_url_lookup()'s test is rewritten for Montana's simpler
# two-registry setup, and score_page_text_for_job_signal()'s tests use
# synthetic (not real-captured) text, since that function is pure text-
# pattern matching with no Montana-specific behavior to verify against real
# fixtures.

test_that("attach_scrape_log_errors attaches the latest error message for a matching source", {
  flagged <- data.frame(name = c("Butte School District 1", "Stable District"),
                        mean_count = c(10, 5), n_weeks = c(3, 3), count = c(0, 4),
                        stringsAsFactors = FALSE)
  scrape_log <- data.frame(
    timestamp = c("2026-09-01 10:00:00", "2026-09-01 10:05:00"),
    source = c("Butte School District 1", "Stable District"),
    status = c("error", "ok"),
    n_rows = c(0, 4),
    error_message = c("HTTP 500 Internal Server Error.", NA_character_),
    stringsAsFactors = FALSE
  )

  result <- attach_scrape_log_errors(flagged, scrape_log)

  expect_equal(result$scrape_error[result$name == "Butte School District 1"], "HTTP 500 Internal Server Error.")
  expect_true(is.na(result$scrape_error[result$name == "Stable District"]))
})

test_that("attach_scrape_log_errors matches by substring for prefixed scrape_log source names (Apptegy)", {
  flagged <- data.frame(name = "Wolf Point Public Schools", mean_count = 19, n_weeks = 3, count = 0,
                        stringsAsFactors = FALSE)
  scrape_log <- data.frame(
    timestamp = "2026-09-01 10:00:00",
    source = "Apptegy/chromote: Wolf Point Public Schools",
    status = "error", n_rows = 0, error_message = "Page structure changed",
    stringsAsFactors = FALSE
  )

  result <- attach_scrape_log_errors(flagged, scrape_log)

  expect_equal(result$scrape_error, "Page structure changed")
})

test_that("attach_scrape_log_errors keeps only the most recent attempt when a source logged twice", {
  flagged <- data.frame(name = "Rocky Mountain College", mean_count = 4.7, n_weeks = 3, count = 0,
                        stringsAsFactors = FALSE)
  scrape_log <- data.frame(
    timestamp = c("2026-09-01 09:00:00", "2026-09-01 09:05:00"),
    source = c("Rocky Mountain College", "Rocky Mountain College"),
    status = c("error", "ok"),
    n_rows = c(0, 12),
    error_message = c("HTTP 429 Too Many Requests.", NA_character_),
    stringsAsFactors = FALSE
  )

  result <- attach_scrape_log_errors(flagged, scrape_log)

  # The later attempt succeeded -- no error should be attached.
  expect_true(is.na(result$scrape_error))
})

test_that("attach_scrape_log_errors leaves scrape_error NA when there's no scrape_log or no flagged rows", {
  flagged <- data.frame(name = "Some District", mean_count = 5, n_weeks = 3, count = 0, stringsAsFactors = FALSE)
  empty_log <- data.frame(timestamp = character(0), source = character(0), status = character(0),
                          n_rows = integer(0), error_message = character(0))

  result <- attach_scrape_log_errors(flagged, empty_log)
  expect_true(is.na(result$scrape_error))

  empty_flagged <- data.frame(name = character(0), mean_count = numeric(0), n_weeks = integer(0), count = numeric(0))
  result2 <- attach_scrape_log_errors(empty_flagged, empty_log)
  expect_equal(nrow(result2), 0)
  expect_true("scrape_error" %in% names(result2))
})

test_that("build_historical_counts excludes pre-pipeline snapshots and computes correct means", {
  snapshots <- list(
    "2026-08-06" = data.frame(District = c("A", "A", "A", "B")),
    "2026-08-13" = data.frame(District = c("A", "A", "B", "B")),
    "2026-08-20" = data.frame(District = c("A", "A", "A")),
    # Predates BASELINE_VALID_FROM -- must be excluded.
    "2026-01-01" = data.frame(District = c("A", "A", "A", "A", "A", "A", "A", "A", "A", "A"))
  )

  baseline <- build_historical_counts(snapshots, "District")

  expect_equal(baseline$n_weeks[baseline$name == "A"], 3)
  expect_equal(baseline$mean_count[baseline$name == "A"], (3 + 2 + 3) / 3)
  expect_equal(baseline$n_weeks[baseline$name == "B"], 2)
})

test_that("build_historical_counts returns an empty frame when no snapshots are post-baseline", {
  snapshots <- list("2026-01-01" = data.frame(District = c("A", "A")))
  baseline <- build_historical_counts(snapshots, "District")
  expect_equal(nrow(baseline), 0)
})

test_that("collapse_statewide_feed_names buckets every OPI row and leaves direct rows alone", {
  df <- data.frame(
    District = c("SCOBEY", "Miles City, MT", "Billings Public Schools", "Yaak, Montana"),
    Posting_Source = c(OPI_STATEWIDE_SOURCE, OPI_STATEWIDE_SOURCE,
                       "AppliTrack (direct district board)", OPI_STATEWIDE_SOURCE),
    stringsAsFactors = FALSE
  )

  names_out <- collapse_statewide_feed_names(df)

  expect_equal(names_out, c(OPI_STATEWIDE_SOURCE, OPI_STATEWIDE_SOURCE,
                            "Billings Public Schools", OPI_STATEWIDE_SOURCE))
})

test_that("collapse_statewide_feed_names falls back to the raw name column with no Posting_Source", {
  df <- data.frame(District = c("SCOBEY", "Billings Public Schools"), stringsAsFactors = FALSE)
  expect_equal(collapse_statewide_feed_names(df), c("SCOBEY", "Billings Public Schools"))
})

test_that("collapsing the statewide feed keeps a per-location OPI drop from being flagged", {
  # Two weeks of OPI history where the specific locations churn completely,
  # but the feed's total volume is steady -- the pre-collapse behavior would
  # flag every vanished location string; the collapsed behavior flags nothing.
  raw_snapshots <- list(
    "2026-08-13" = data.frame(
      District = c("SCOBEY", "SCOBEY", "RICHEY", "Billings Public Schools"),
      Posting_Source = c(OPI_STATEWIDE_SOURCE, OPI_STATEWIDE_SOURCE,
                         OPI_STATEWIDE_SOURCE, "AppliTrack (direct district board)"),
      stringsAsFactors = FALSE
    ),
    "2026-08-20" = data.frame(
      District = c("JOLIET", "HALL", "POWER", "Billings Public Schools"),
      Posting_Source = c(OPI_STATEWIDE_SOURCE, OPI_STATEWIDE_SOURCE,
                         OPI_STATEWIDE_SOURCE, "AppliTrack (direct district board)"),
      stringsAsFactors = FALSE
    )
  )
  collapsed <- lapply(raw_snapshots, function(df) data.frame(name = collapse_statewide_feed_names(df)))
  baseline <- build_historical_counts(collapsed, "name")
  current <- data.frame(name = c(OPI_STATEWIDE_SOURCE, "Billings Public Schools"), count = c(3, 1))

  flagged <- flag_drift(current, baseline)

  expect_equal(nrow(flagged), 0)
})

test_that("flag_drift flags a real drop and leaves a stable source alone", {
  baseline <- data.frame(
    name = c("BigDistrict", "StableDistrict"),
    n_weeks = c(5, 5),
    mean_count = c(50, 10)
  )
  current <- data.frame(name = c("BigDistrict", "StableDistrict"), count = c(0, 9))

  flagged <- flag_drift(current, baseline)

  expect_equal(flagged$name, "BigDistrict")
})

test_that("flag_drift requires a minimum number of historical weeks before flagging", {
  baseline <- data.frame(name = "BrandNewDistrict", n_weeks = 1, mean_count = 10)
  current <- data.frame(name = "BrandNewDistrict", count = 0)

  flagged <- flag_drift(current, baseline, min_weeks = 2)

  expect_equal(nrow(flagged), 0)
})

test_that("flag_drift treats a source missing from current data as a count of zero", {
  baseline <- data.frame(name = "VanishedDistrict", n_weeks = 3, mean_count = 20)
  current <- data.frame(name = character(0), count = numeric(0))

  flagged <- flag_drift(current, baseline)

  expect_equal(flagged$name, "VanishedDistrict")
  expect_equal(flagged$count, 0)
})

test_that("check_salary_coverage flags a source that fell below its expected count", {
  flagged <- check_salary_coverage("K-12 teacher salary (MT DLI)", actual = 5, expected = 18)
  expect_equal(flagged$name, "K-12 teacher salary (MT DLI)")
  expect_equal(flagged$expected, 18)
  expect_equal(flagged$actual, 5)
})

test_that("check_salary_coverage returns NULL when a source meets its expected count", {
  expect_null(check_salary_coverage("K-12 teacher salary (MT DLI)", actual = 18, expected = 18))
})

test_that("check_salary_coverage supports a tolerance below the ideal expected count", {
  expect_null(check_salary_coverage("HE avg faculty salary (IPEDS)", actual = 5, expected = 6, min_ok = 5))
  flagged <- check_salary_coverage("HE avg faculty salary (IPEDS)", actual = 3, expected = 6, min_ok = 5)
  expect_equal(flagged$actual, 3)
})

test_that("check_salary_value_bounds flags a value outside the sane dollar range", {
  actual <- c(A = 51000, B = 52500, C = 5)  # C is obvious garbage (a parser misread)
  flagged <- check_salary_value_bounds("K-12 teacher salary (MT DLI)", actual, min_ok = 25000, max_ok = 150000)
  expect_equal(flagged$entity, "C")
  expect_equal(flagged$value, 5)
})

test_that("check_salary_value_bounds returns NULL when every value is in range", {
  actual <- c(A = 51000, B = 52500, C = 48000)
  expect_null(check_salary_value_bounds("K-12 teacher salary (MT DLI)", actual, min_ok = 25000, max_ok = 150000))
})

test_that("check_salary_value_bounds ignores NA rather than flagging it", {
  actual <- c(A = 51000, B = NA_real_)
  expect_null(check_salary_value_bounds("K-12 teacher salary (MT DLI)", actual, min_ok = 25000, max_ok = 150000))
})

test_that("check_salary_yoy_plausibility flags an entity whose change is a real outlier against its peers", {
  prior <- c(A = 50000, B = 48000, C = 52000, D = 49000, E = 51000, Z = 50000)
  current <- c(A = 51500, B = 49500, C = 53500, D = 50500, E = 53500, Z = 73500)
  flagged <- check_salary_yoy_plausibility(current, prior)
  expect_equal(flagged$name, "Z")
  expect_equal(round(flagged$pct_change, 2), 0.47)
})

test_that("check_salary_yoy_plausibility does not flag a statewide event where every entity moves a lot", {
  prior <- c(A = 50000, B = 48000, C = 52000, D = 49000, E = 51000)
  current <- prior * 1.15
  expect_null(check_salary_yoy_plausibility(current, prior))
})

test_that("check_salary_yoy_plausibility does not flag normal small variation", {
  prior <- c(A = 50000, B = 48000, C = 52000, D = 49000, E = 51000)
  current <- c(A = 51000, B = 49200, C = 53000, D = 50100, E = 51800)
  expect_null(check_salary_yoy_plausibility(current, prior))
})

test_that("check_salary_yoy_plausibility returns NULL with too few comparable entities", {
  prior <- c(A = 50000, B = 48000)
  current <- c(A = 70000, B = 48500)
  expect_null(check_salary_yoy_plausibility(current, prior))
})

test_that("check_salary_yoy_plausibility still flags an outlier when every peer moved by exactly zero (MAD == 0)", {
  prior <- c(A = 50000, B = 48000, C = 52000, D = 49000, E = 51000, Z = 50000)
  current <- c(A = 50000, B = 48000, C = 52000, D = 49000, E = 51000, Z = 73500)
  flagged <- check_salary_yoy_plausibility(current, prior)
  expect_equal(flagged$name, "Z")
})

test_that("check_salary_yoy_plausibility does not flag a uniform statewide move even with zero peer spread", {
  prior <- c(A = 50000, B = 48000, C = 52000, D = 49000, E = 51000)
  current <- prior * 1.15
  expect_null(check_salary_yoy_plausibility(current, prior))
})

test_that("score_page_text_for_job_signal identifies real job-board content as likely_broken", {
  text <- "Current Openings\nMath Teacher - Posted: 08/01/2026 - Closing Date: 08/15/2026 - Apply Now\nBus Driver - JobID 4821 - View Details"
  expect_equal(score_page_text_for_job_signal(text), "likely_broken")
})

test_that("score_page_text_for_job_signal identifies a genuinely empty page", {
  text <- "Employment Opportunities\nThere are currently no open positions. Please check back later."
  expect_equal(score_page_text_for_job_signal(text), "looks_genuinely_empty")
})

test_that("score_page_text_for_job_signal is honestly inconclusive on ambiguous content", {
  text <- "Now Hiring\nBus Drivers\nCoaching Positions Available\nContact HR for details."
  expect_equal(score_page_text_for_job_signal(text), "inconclusive")
})

test_that("score_page_text_for_job_signal returns inconclusive for NA or empty input", {
  expect_equal(score_page_text_for_job_signal(NA_character_), "inconclusive")
  expect_equal(score_page_text_for_job_signal(""), "inconclusive")
  expect_equal(score_page_text_for_job_signal("   "), "inconclusive")
})

test_that("build_source_url_lookup combines both Montana registries", {
  k12 <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(District = "Test District", Job_Link = "https://k12.example",
                        stringsAsFactors = FALSE), k12, row.names = FALSE)

  he <- withr::local_tempfile(fileext = ".csv")
  write.csv(data.frame(Institution = "Test Institution", Job_Link = "https://he.example",
                        stringsAsFactors = FALSE), he, row.names = FALSE)

  lookup <- build_source_url_lookup(k12, he)

  expect_equal(unname(lookup["Test District"]), "https://k12.example")
  expect_equal(unname(lookup["Test Institution"]), "https://he.example")
})

test_that("build_source_url_lookup defaults cover every real registered district and institution", {
  lookup <- build_source_url_lookup(
    here::here("k12_district_registry.csv"),
    here::here("he_institution_registry.csv")
  )
  k12 <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  he <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
  expect_true(all(k12$District %in% names(lookup)))
  expect_true(all(he$Institution %in% names(lookup)))
})
