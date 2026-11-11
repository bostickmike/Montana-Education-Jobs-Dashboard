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

# --- LLM corroboration (Tier 2b) ----------------------------------------

test_that("combine_verdict_with_llm promotes inconclusive to likely_broken when the LLM read real titles", {
  out <- combine_verdict_with_llm("inconclusive", c("Bus Driver", "3rd Grade Teacher"))
  expect_equal(out$verdict, "likely_broken")
  expect_match(out$note, "2 posting\\(s\\)")
  expect_match(out$note, "Bus Driver; 3rd Grade Teacher")
})

test_that("combine_verdict_with_llm truncates a long LLM title list in the note", {
  out <- combine_verdict_with_llm("inconclusive", paste("Role", 1:12))
  expect_equal(out$verdict, "likely_broken")
  expect_match(out$note, "Role 8, \\.\\.\\.$")
})

test_that("combine_verdict_with_llm downgrades inconclusive to genuinely_empty only when the LLM also found nothing", {
  out <- combine_verdict_with_llm("inconclusive", character(0))
  expect_equal(out$verdict, "looks_genuinely_empty")
  expect_match(out$note, "no postings")
})

test_that("combine_verdict_with_llm does not touch looks_genuinely_empty or a confirmed_broken verdict", {
  expect_equal(combine_verdict_with_llm("looks_genuinely_empty", character(0))$verdict, "looks_genuinely_empty")
  expect_true(is.na(combine_verdict_with_llm("looks_genuinely_empty", character(0))$note))
  # confirmed_broken stays put even if the LLM happens to read something
  expect_equal(combine_verdict_with_llm("confirmed_broken", c("Bus Driver"))$verdict, "confirmed_broken")
})

test_that("combine_verdict_with_llm keeps an already-likely_broken verdict and still lists what the LLM found", {
  out <- combine_verdict_with_llm("likely_broken", c("Custodian"))
  expect_equal(out$verdict, "likely_broken")
  expect_match(out$note, "Custodian")
})

test_that("llm_titles_from_page_text returns character(0) with no key or a blank page (never throws)", {
  withr::with_envvar(c(GEMINI_API_KEY = "", LLM_EXTRACT_KEY_ENV = ""), {
    expect_identical(llm_titles_from_page_text("Food Service Worker\nBus Driver"), character(0))
  })
  withr::with_envvar(c(GEMINI_API_KEY = "fake-key"), {
    expect_identical(llm_titles_from_page_text(NA_character_), character(0))
    expect_identical(llm_titles_from_page_text("   "), character(0))
  })
})

# ---- Tier 3: per-source auto-fix issues -----------------------------------

test_that("every scraper function SCRAPER_CALL_SPECS names really exists", {
  fns <- vapply(SCRAPER_CALL_SPECS, `[[`, character(1), "fn")
  expect_true(all(vapply(fns, exists, logical(1), mode = "function")),
              info = paste("missing:", paste(fns[!vapply(fns, exists, logical(1), mode = "function")], collapse = ", ")))
})

test_that("every real registered K-12 heuristic platform resolves to a real scraper function", {
  k12 <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  heur <- k12[grepl("Heuristic$", k12$Platform), ]
  for (i in seq_len(nrow(heur))) {
    call <- resolve_scraper_call(heur[i, ])
    expect_false(is.null(call), info = heur$Platform[i])
    expect_true(exists(call$fn, mode = "function"), info = paste(heur$Platform[i], "->", call$fn))
  }
})

test_that("resolve_scraper_call passes the same registry columns Mt_ED_Jobs.Rmd does", {
  hinsdale <- data.frame(District = "Hinsdale Public Schools", Platform = "HinsdaleHeuristic",
                         Slug = "", Job_Link = "https://hinsdale.example/jobs", stringsAsFactors = FALSE)
  expect_equal(resolve_scraper_call(hinsdale),
               list(fn = "fetch_hinsdale_postings", args = list("https://hinsdale.example/jobs"), session = FALSE))

  tyler <- data.frame(District = "Some District", Platform = "TylerPortico", Slug = "abc",
                      Job_Link = "x", stringsAsFactors = FALSE)
  expect_equal(resolve_scraper_call(tyler)$args, list("abc", "Some District"))

  broadview <- data.frame(District = "Broadview", Platform = "BroadviewHeuristic", Slug = "",
                          Job_Link = "x", stringsAsFactors = FALSE)
  expect_equal(resolve_scraper_call(broadview)$args, list())
})

test_that("resolve_scraper_call routes every registered Apptegy/RedRover district through APPTEGY_DISTRICT_SCRAPERS", {
  k12 <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  chrome <- k12[k12$Platform %in% c("Apptegy", "RedRoverK12"), ]
  for (i in seq_len(nrow(chrome))) {
    call <- resolve_scraper_call(chrome[i, ])
    expect_true(call$session)
    expect_true(chrome$District[i] %in% names(APPTEGY_DISTRICT_SCRAPERS), info = chrome$District[i])
  }
})

test_that("every real registered HE platform except the known gaps resolves to a real scraper function", {
  he <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
  for (i in seq_len(nrow(he))) {
    call <- resolve_scraper_call(he[i, ])
    if (he$Platform[i] %in% c("SharesBoard", "AdpWorkforceNow", "IsolvedHire")) {
      expect_null(call, info = he$Platform[i])
    } else {
      expect_false(is.null(call), info = he$Platform[i])
      expect_true(exists(call$fn, mode = "function"), info = paste(he$Platform[i], "->", call$fn))
    }
  }
})

test_that("run_scraper_call hands a chromote-backed scraper a session and the Apptegy map its district", {
  fake_session <- structure(list(close = function() NULL), class = "fake")
  stub_map <- list("Test District" = function(session) {
    data.frame(Title = if (identical(session, fake_session)) "got session" else "no session")
  })
  call <- list(fn = APPTEGY_DISPATCH_FN, args = list("Test District"), session = TRUE)
  expect_equal(run_scraper_call(call, function() fake_session, apptegy_map = stub_map)$Title, "got session")
})

test_that("resolve_scraper_call returns NULL for platforms with no single-source live check", {
  shares <- data.frame(Institution = "MSU", Platform = "SharesBoard", Feed_URL = "x", stringsAsFactors = FALSE)
  expect_null(resolve_scraper_call(shares))
})

test_that("build_autofix_issue_body round-trips its source marker and lists the LLM titles", {
  row <- data.frame(name = "Hinsdale Public Schools", type = "K-12", mean_count = 3, count = 0,
                    url = "https://hinsdale.k12.mt.us/District/1557-Untitled.html",
                    llm_titles = "Route Bus Drivers | Daycare Manager", stringsAsFactors = FALSE)
  reg <- data.frame(District = "Hinsdale Public Schools", Platform = "HinsdaleHeuristic", Slug = "",
                    Job_Link = row$url, stringsAsFactors = FALSE)
  body <- paste(build_autofix_issue_body(row, reg, "https://run"), collapse = "\n")

  expect_equal(parse_autofix_marker(body), "Hinsdale Public Schools")
  expect_match(body, "- Route Bus Drivers", fixed = TRUE)
  expect_match(body, "- Daycare Manager", fixed = TRUE)
  expect_match(body, "`fetch_hinsdale_postings()`", fixed = TRUE)
  expect_match(body, "https://run", fixed = TRUE)
  expect_match(body, "deliberately leaves out", fixed = TRUE)
  # Hinsdale is a plain HTTP scraper -- no sandbox-render hint.
  expect_no_match(body, "rendered this page in CI", fixed = TRUE)
})

test_that("build_autofix_issue_body warns chromote-scraper fixes that the page renders fine in CI", {
  # Issue #7: the agent's firewall blocked Apptegy's CDNs, it saw no postings
  # in its own render, and rewrote the fetch to parse embedded JSON instead.
  row <- data.frame(name = "Lone Rock School District", type = "K-12", mean_count = 1, count = 0,
                    url = "https://www.lonerockschool.org/page/employment",
                    llm_titles = "Special Education Paraprofessional", stringsAsFactors = FALSE)
  reg <- data.frame(District = row$name, Platform = "Apptegy", Slug = "", Job_Link = row$url,
                    stringsAsFactors = FALSE)
  body <- paste(build_autofix_issue_body(row, reg), collapse = "\n")
  expect_match(body, "rendered this page in CI", fixed = TRUE)
  expect_equal(parse_autofix_expected_titles(body), "Special Education Paraprofessional")
})

test_that("build_autofix_issue_body tolerates no LLM titles and no registry row", {
  row <- data.frame(name = "Mystery", type = "K-12", mean_count = 2, count = 0, url = NA_character_,
                    llm_titles = NA_character_, stringsAsFactors = FALSE)
  body <- paste(build_autofix_issue_body(row), collapse = "\n")
  expect_equal(parse_autofix_marker(body), "Mystery")
  expect_no_match(body, "An LLM read")
})

test_that("autofix_engine defaults to claude and rejects typos", {
  expect_equal(autofix_engine(""), "claude")
  expect_equal(autofix_engine(NA_character_), "claude")
  expect_equal(autofix_engine(" Copilot "), "copilot")
  expect_equal(autofix_engine("none"), "none")
  expect_error(autofix_engine("claud"), "AUTOFIX_ENGINE must be one of")
})

test_that("parse_autofix_marker returns NA for bodies without a marker", {
  expect_true(is.na(parse_autofix_marker("just a normal issue")))
  expect_true(is.na(parse_autofix_marker(NA_character_)))
  expect_true(is.na(parse_autofix_marker(character(0))))
})

test_that("parse_autofix_expected_titles recovers the titles build_autofix_issue_body wrote", {
  row <- data.frame(name = "X", type = "K-12", mean_count = 3, count = 0, url = "u",
                    llm_titles = "Route Bus Drivers | Daycare Manager", stringsAsFactors = FALSE)
  body <- paste(build_autofix_issue_body(row), collapse = "\n")
  expect_equal(parse_autofix_expected_titles(body), c("Route Bus Drivers", "Daycare Manager"))
  expect_equal(parse_autofix_expected_titles("no titles here"), character(0))
})

test_that("summarize_live_check fails on an error or zero rows and passes otherwise", {
  expect_false(summarize_live_check("X", simpleError("HTTP 520."))$pass)
  expect_false(summarize_live_check("X", data.frame(Title = character(0)))$pass)

  ok <- summarize_live_check("X", data.frame(Title = c("Route Bus Drivers", "Cook")),
                             expected_titles = c("route bus drivers", "Daycare Manager"))
  expect_true(ok$pass)
  md <- paste(ok$markdown, collapse = "\n")
  expect_match(md, "Matched 1 of 2", fixed = TRUE)
  expect_match(md, "- Daycare Manager", fixed = TRUE)
})

# ---- auto-fix evidence (the CI capture handed to the agent) ----------------
# Issue #7: the agent's sandbox rendered Lone Rock's Apptegy page empty and
# it misdiagnosed the break. The real cause -- a renamed stop line plus one
# new posting -- is plain in a diff of the old fixture against the text the
# drift check rendered in CI. drift_autofix_lonerock_innertext_2026-09-30.txt
# is that text, captured live with scripts/repro_scraper.R.

lonerock_capture <- function() {
  paste(readLines(test_path("fixtures", "drift_autofix_lonerock_innertext_2026-09-30.txt"),
                  warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}
scraper_source_lines <- function() {
  unlist(lapply(here::here(SCRAPER_FILES), readLines, warn = FALSE))
}
lonerock_row <- function() {
  data.frame(name = "Lone Rock School District", type = "K-12", mean_count = 1, count = 0,
             url = "https://www.lonerockschool.org/page/employment",
             llm_titles = "Special Education Paraprofessional | Bus Driver and Maintenance Director",
             stringsAsFactors = FALSE)
}
lonerock_registry <- function() {
  data.frame(District = "Lone Rock School District", Platform = "Apptegy", Slug = "",
             Job_Link = "https://www.lonerockschool.org/page/employment", stringsAsFactors = FALSE)
}

test_that("scraper_fetch_fn follows the Apptegy map to the real fetch_* function", {
  lines <- scraper_source_lines()
  expect_equal(scraper_fetch_fn(resolve_scraper_call(lonerock_registry()), lines), "fetch_lonerock_postings")
  expect_equal(scraper_fetch_fn(list(fn = "fetch_applitrack_postings", args = list("x"), session = FALSE), lines),
               "fetch_applitrack_postings")
  expect_true(is.na(scraper_fetch_fn(NULL, lines)))
  expect_true(is.na(scraper_fetch_fn(list(fn = APPTEGY_DISPATCH_FN, args = list("No Such District"), session = TRUE), lines)))
})

test_that("scraper_reads_inner_text tells innerText chromote scrapers from HTTP ones", {
  lines <- scraper_source_lines()
  expect_true(scraper_reads_inner_text("fetch_lonerock_postings", lines))
  expect_false(scraper_reads_inner_text("fetch_applitrack_postings", lines))
  expect_false(scraper_reads_inner_text(NA_character_, lines))
})

test_that("source_fixtures finds a scraper's fixtures from its tests, dated newest first", {
  test_paths <- list.files(test_path(), pattern = "^test-.*[.]R$", full.names = TRUE)
  test_files <- setNames(lapply(test_paths, readLines, warn = FALSE), basename(test_paths))
  fx <- source_fixtures("fetch_lonerock_postings", test_files)
  expect_equal(fx[1], "apptegy_lonerock_content_2026-09-30.txt")
  expect_true("apptegy_lonerock_rendered.txt" %in% fx)
  expect_equal(source_fixtures(NA_character_, test_files), character(0))
})

test_that("text_diff of the pre-fix Lone Rock fixture vs the CI capture shows the real break", {
  skip_if(!nzchar(Sys.which("diff")), "no system diff")
  old <- paste(readLines(test_path("fixtures", "apptegy_lonerock_rendered.txt"), warn = FALSE), collapse = "\n")
  d <- text_diff(old, lonerock_capture(), "old.txt", "ci")
  expect_true("-District Employment Applications." %in% d)
  expect_true("+Classified Employee Application" %in% d)
  expect_true("+Bus Driver and Maintenance Director" %in% d)
  expect_lt(length(d), 40)
  expect_equal(text_diff("a\n\nb ", "a\nb"), character(0))
})

test_that("an innerText scraper's issue hands the agent the CI capture as its fixture", {
  call <- resolve_scraper_call(lonerock_registry())
  ev <- gather_autofix_evidence(call, lonerock_capture(), repo_root = here::here())
  expect_true(ev$inner_text)
  expect_equal(ev$diff_against, "apptegy_lonerock_content_2026-09-30.txt")

  body <- paste(build_autofix_issue_body(lonerock_row(), lonerock_registry(), evidence = ev,
                                         captured_on = "2026-09-30"), collapse = "\n")
  expect_match(body, "### What CI saw", fixed = TRUE)
  expect_match(body, "Full page text captured in CI", fixed = TRUE)
  expect_match(body, "Classified Employee Application", fixed = TRUE)
  expect_match(body, "1. Save the **Full page text captured in CI**", fixed = TRUE)
  expect_match(body, "scripts/repro_scraper.R \"Lone Rock School District\"", fixed = TRUE)
  expect_equal(parse_autofix_marker(body), "Lone Rock School District")
})

test_that("diff and page-text lines never leak into the live check's expected titles", {
  ev <- list(fetch_fn = "fetch_x_postings", fixtures = "x.txt", inner_text = TRUE,
             page_text = "- Not A Title\nreal text", diff_against = "x.txt",
             diff = c("--- x.txt", "+++ ci", "- Also Not A Title", "+new"))
  body <- paste(build_autofix_issue_body(lonerock_row(), lonerock_registry(), evidence = ev), collapse = "\n")
  expect_equal(parse_autofix_expected_titles(body),
               c("Special Education Paraprofessional", "Bus Driver and Maintenance Director"))
})

test_that("an HTTP scraper's issue keeps the capture as context and asks for a raw fixture", {
  row <- data.frame(name = "Hinsdale Public Schools", type = "K-12", mean_count = 3, count = 0,
                    url = "https://hinsdale.k12.mt.us/District/1557-Untitled.html",
                    llm_titles = NA_character_, stringsAsFactors = FALSE)
  reg <- data.frame(District = row$name, Platform = "HinsdaleHeuristic", Slug = "",
                    Job_Link = row$url, stringsAsFactors = FALSE)
  ev <- gather_autofix_evidence(resolve_scraper_call(reg), "Route Bus Drivers\nDaycare Manager",
                                repo_root = here::here())
  expect_false(ev$inner_text)
  expect_equal(ev$diff, character(0))
  expect_true(length(ev$fixtures) > 0)
  body <- paste(build_autofix_issue_body(row, reg, evidence = ev), collapse = "\n")
  expect_match(body, "1. Fetch the live page", fixed = TRUE)
  expect_no_match(body, "Diff: newest text fixture", fixed = TRUE)
})

test_that("a long capture is truncated to fit an issue body", {
  ev <- list(fetch_fn = "fetch_x_postings", fixtures = character(0), inner_text = TRUE,
             page_text = strrep("x", AUTOFIX_PAGE_TEXT_MAX_CHARS * 3), diff_against = NA_character_,
             diff = paste0("+", seq_len(AUTOFIX_DIFF_MAX_LINES * 2)))
  md <- autofix_evidence_markdown(ev, "2026-09-30")
  expect_lt(sum(nchar(md)), 60000)  # GitHub caps issue bodies at 65,536 chars
  expect_true(any(grepl("page text truncated", md, fixed = TRUE)))
  expect_true(any(grepl("diff truncated", md, fixed = TRUE)))
})

test_that("summarize_central_safety_net handles empty or NULL inputs gracefully", {
  summary <- summarize_central_safety_net()
  expect_equal(summary$total_feed_vacancies, 0L)
  expect_equal(summary$total_fallback_vacancies, 0L)
  expect_equal(length(summary$fallback_districts), 0)
  expect_equal(nrow(summary$discrepancies), 0)
  expect_true(any(grepl("Counted from OPI at directly scraped districts**: none", summary$markdown, fixed = TRUE)))
})

test_that("summarize_central_safety_net identifies active fallback districts and counts", {
  registry <- data.frame(
    District = c("Bozeman Public Schools", "Polson School District", "Billings Public Schools"),
    stringsAsFactors = FALSE
  )
  combined <- data.frame(
    District = c("Bozeman Public Schools", "Bozeman Public Schools", "Polson School District", "Unregistered Town", "Billings Public Schools"),
    Posting_Source = c(
      OPI_STATEWIDE_SOURCE,
      OPI_STATEWIDE_SOURCE,
      OPI_STATEWIDE_SOURCE,
      OPI_STATEWIDE_SOURCE,
      "AppliTrack (direct district board)"
    ),
    stringsAsFactors = FALSE
  )

  summary <- summarize_central_safety_net(
    combined_df = combined,
    registry = registry,
    feed_label = OPI_STATEWIDE_SOURCE,
    feed_short_name = "OPI"
  )

  expect_equal(summary$total_feed_vacancies, 4L)
  expect_equal(summary$total_fallback_vacancies, 3L)
  expect_equal(summary$fallback_districts[["Bozeman Public Schools"]], 2L)
  expect_equal(summary$fallback_districts[["Polson School District"]], 1L)
  expect_null(summary$fallback_districts[["Billings Public Schools"]])

  md <- paste(summary$markdown, collapse = "\n")
  expect_match(md, "3 posting(s) at 2 district(s), not on the district's own board", fixed = TRUE)
  expect_match(md, "Bozeman Public Schools**: 2", fixed = TRUE)
  expect_match(md, "Polson School District**: 1", fixed = TRUE)
})

test_that("summarize_central_safety_net reads discrepancy report for unmatched postings", {
  disc <- data.frame(
    District = c("Billings Public Schools", "Helena Public Schools"),
    Source = c("OPI", "OPI"),
    Title = c("Math Teacher", "Custodian (stale)"),
    Date_Posted = c("2026-10-25", "2026-05-01"),
    Discrepancy_Type = c("Unmatched on direct scraper (investigate ATS drift)", "Potential ghost posting on OPI"),
    stringsAsFactors = FALSE
  )

  summary <- summarize_central_safety_net(
    discrepancy_report = disc,
    feed_short_name = "OPI"
  )

  expect_equal(nrow(summary$discrepancies), 1)
  expect_equal(summary$discrepancies$District, "Billings Public Schools")
  md <- paste(summary$markdown, collapse = "\n")
  expect_match(md, "1 unmatched vacancy/vacancies detected on central feed", fixed = TRUE)
  expect_match(md, "Billings Public Schools**: \"Math Teacher\" (posted 2026-10-25)", fixed = TRUE)
})

test_that("build_drift_report_markdown includes Central Safety Net status annotations and summary", {
  actionable <- data.frame(
    name = c("Bozeman Public Schools", "Havre Public Schools", "Montana State University"),
    type = c("K-12", "K-12", "Higher Ed"),
    mean_count = c(45.0, 10.0, 30.0),
    count = c(0, 0, 2),
    url = c("https://bozeman.k12.mt.us", "https://havre.k12.mt.us", "https://msu.edu"),
    verdict = c("confirmed_broken", "likely_broken", "likely_broken"),
    error_message = c("500 Server Error", NA, NA),
    llm_note = c(NA, "an LLM read 4 postings", NA),
    safety_net_vacancies = c(5L, 0L, NA_integer_),
    stringsAsFactors = FALSE
  )

  safety_net_summary <- list(
    total_feed_vacancies = 350L,
    fallback_districts = list("Bozeman Public Schools" = 5L),
    total_fallback_vacancies = 5L,
    markdown = c(
      "### OPI postings at districts we scrape directly",
      "",
      "- **Statewide Feed (OPI)**: 350 active vacancies captured.",
      "- **Counted from OPI at directly scraped districts**: 5 posting(s) at 1 district(s), not on the district's own board:",
      "  - **Bozeman Public Schools**: 5",
      "- **Central Feed Discrepancies**: 0 unmatched vacancies detected for active direct scrapers.",
      ""
    )
  )

  lines <- build_drift_report_markdown(
    actionable = actionable,
    safety_net_summary = safety_net_summary,
    date = as.Date("2026-10-29"),
    feed_short_name = "OPI"
  )

  report <- paste(lines, collapse = "\n")
  # Bozeman: active fallback
  expect_match(report, "Bozeman Public Schools", fixed = TRUE)
  expect_match(report, "On OPI**: 5 postings for this district that its own board doesn't list (counted from OPI)", fixed = TRUE)
  # Havre: inactive fallback
  expect_match(report, "Havre Public Schools", fixed = TRUE)
  expect_match(report, "On OPI**: nothing for this district beyond what its own board lists", fixed = TRUE)
  # Higher Ed: no Central Safety Net bullet under its entry
  expect_match(report, "Montana State University", fixed = TRUE)
  expect_false(grepl("Montana State University.*\\n\\s+- \\*\\*On OPI", report))
  # Bottom summary block included
  expect_match(report, "### OPI postings at districts we scrape directly", fixed = TRUE)
  expect_match(report, "Statewide Feed (OPI)**: 350 active vacancies captured", fixed = TRUE)
})

# --- Posted-pay coverage -----------------------------------------------------

test_that("pay_coverage_counts tallies postings and postings with pay per source", {
  out <- pay_coverage_counts(c("A", "A", "B", "A"), c(TRUE, FALSE, FALSE, TRUE))
  expect_equal(out$name, c("A", "B"))
  expect_equal(out$n, c(3L, 1L))
  expect_equal(out$with_pay, c(2L, 0L))
  expect_equal(nrow(pay_coverage_counts(character(0), logical(0))), 0)
})

test_that("flag_pay_coverage_drop flags a source whose postings arrive but lost their pay", {
  week <- function(n, with_pay) data.frame(name = c("Paycom College", "Free Text District"),
                                           n = n, with_pay = with_pay)
  history <- list(week(c(30, 10), c(16, 1)), week(c(31, 12), c(15, 2)))
  current <- data.frame(name = c("Paycom College", "Free Text District"), n = c(31, 11), with_pay = c(0, 0))
  out <- flag_pay_coverage_drop(current, history)
  # The free-text district never carried much pay, so its 0 is not a drop.
  expect_equal(out$name, "Paycom College")
  expect_equal(out$with_pay, 0)
  expect_equal(out$n_weeks, 2L)
  expect_equal(round(out$mean_share, 3), round(mean(c(16 / 30, 15 / 31)), 3))
})

test_that("flag_pay_coverage_drop stays quiet without enough history or postings", {
  hist1 <- list(data.frame(name = "A", n = 10, with_pay = 9))
  hist2 <- c(hist1, hist1)
  expect_equal(nrow(flag_pay_coverage_drop(data.frame(name = "A", n = 10, with_pay = 0), hist1)), 0)
  # Too few postings this run to judge (and a lost-postings source is flag_drift()'s job).
  expect_equal(nrow(flag_pay_coverage_drop(data.frame(name = "A", n = 2, with_pay = 0), hist2)), 0)
  # A normal week-to-week dip is not flagged.
  expect_equal(nrow(flag_pay_coverage_drop(data.frame(name = "A", n = 10, with_pay = 6), hist2)), 0)
  expect_equal(nrow(flag_pay_coverage_drop(data.frame(name = "A", n = 10, with_pay = 0), list())), 0)
  expect_equal(nrow(flag_pay_coverage_drop(data.frame(name = "A", n = 10, with_pay = 0), hist2)), 1)
})

test_that("build_pay_coverage_report_markdown names each flagged source and its numbers", {
  expect_equal(build_pay_coverage_report_markdown(data.frame()), character(0))
  flagged <- data.frame(name = "Paycom College", mean_share = 0.51, n_weeks = 2L, n = 31L,
                        with_pay = 0L, type = "Higher Ed")
  md <- build_pay_coverage_report_markdown(flagged, date = as.Date("2026-11-07"))
  expect_true(any(grepl("Posted pay went missing (2026-11-07)", md, fixed = TRUE)))
  expect_true(any(grepl("**Paycom College** (Higher Ed): usually 51% of postings state pay, now 0 of 31", md, fixed = TRUE)))
})

# ---- Title quality (classification safeguards items 5 and 6) ----
# Titles below are real, copied from the MT and WY raw archives.

test_that("lint_title_shape flags the misread titles found in the archives", {
  bad <- c(
    "High School - Head" = "level and rank only, no role",                      # Plevna
    "Jr. High - Asst." = "level and rank only, no role",                        # Plevna
    "FULL TIME. MON - FRI." = "schedule or detail sentence",                    # Florence-Carlton
    "YEAR-ROUND POSITION." = "schedule or detail sentence",                     # Florence-Carlton
    "Bus Drivers- Must have a CDL with a school bus passenger endorsement." = "schedule or detail sentence",
    "Food Service is hiring for a cook position." = "schedule or detail sentence",  # Uinta 6
    "Special Education Teachers - Open Until Filled." = "schedule or detail sentence",  # Fremont 21
    "Dish_Server_Cashiers 26" = "file name",                                    # Livingston
    "Dish_Server_Cashier 26 - Copy" = "file name",
    "Other" = "no job named"                                                    # OPI subject field
  )
  expect_equal(lint_title_shape(names(bad)), unname(bad))
  ennis <- paste("Summary: Ennis Schools is seeking a Virtual Programs Paraprofessional to join our team for the",
                 "remainder of the 2026-2027 school year. The ideal candidate will work closely with the building",
                 "principal to ensure proper supervision of students, work with staff to help provide appropriate",
                 "virtual classes, and help to develop virtual programs at the secondary level.")
  expect_equal(lint_title_shape(ennis), "schedule or detail sentence; field label; too long")
  expect_equal(lint_title_shape("CustodianEndFragment (NEW)$18.90–$20.00/hour"), "markup left in")  # Cheyenne Classical
  expect_equal(lint_title_shape(c(NA_character_, "", "  ")), rep("blank title", 3))
  expect_equal(lint_title_shape(character(0)), character(0))
})

test_that("lint_title_shape leaves real titles alone, abbreviations and start dates included", {
  good <- c(
    "Junior High 7-8", "Track Coach - Jr. High - Asst.", "COMMUNICATIONS COORD.",
    "Instructional Asst./Technology Asst.", "Director of Budget and Finance.", "Seasonal Grounds Keeper.",
    "Assistant High School Girls Basketball Coach.",
    "Journey Administrative Specialist beginning for the 2026-2027 school year.",
    "Project Coordinator, Senior - Fed. Relations/Employee Success Coord.", "Elementary",
    "Substitute Certified Teachers $150/day",
    "Special Education Maternity Leave (2) - PMS - (8/26/26-12/14/26)/TCH00532 - (11/2/26-3/15/27)/TCH00073",
    paste("Monthly Pooled - WCC AmeriCorps Individual Placement - Habitat Biologist Technician with Wyoming",
          "Game and Fish Department and Bighorn National Forest")
  )
  expect_equal(lint_title_shape(good), rep(NA_character_, length(good)))
})

test_that("title_pay_unrecorded flags pay stated in the title only when Posted Pay is blank", {
  t <- c("Secretary – $14 per hour, up to 32 hours per week",                       # Turner
         "Substitute Certified Teachers $150/day",                                      # Platte 2
         "Science Teacher - Torrington Middle School - Eligible for $10,000 Hiring Incentive Based on Certification",
         "Custodian", NA)
  expect_equal(title_pay_unrecorded(t, c(NA, 150, NA, NA, NA)), c(TRUE, FALSE, FALSE, FALSE, FALSE))
  expect_equal(title_pay_unrecorded(character(0), numeric(0)), logical(0))
})

test_that("build_title_lint_report_markdown counts postings and caps the titles shown per source", {
  hits <- data.frame(source = c(rep("OPI", 7), "Turner"), type = "K-12",
                     title = c("Other", "Other", paste("T", 1:5), "Secretary $14"),
                     reason = "x", stringsAsFactors = FALSE)
  md <- build_title_lint_report_markdown(hits, date = "2026-11-05", max_per_source = 3)
  expect_true(any(grepl("**OPI** (K-12), 7 posting(s):", md, fixed = TRUE)))
  expect_true(any(grepl("...and 3 more", md, fixed = TRUE)))    # 6 distinct titles, 3 shown
  expect_equal(sum(grepl("\"Other\"", md, fixed = TRUE)), 1)
  expect_length(build_title_lint_report_markdown(hits[0, ]), 0)
})

test_that("flag_other_share_jump flags a source whose Other share jumped against its recent weeks", {
  # Florence-Carlton, MT 2026-09-08: 2 of 10 postings were schedule lines, none before.
  history <- list(data.frame(name = c("Florence", "Steady"), n = c(8, 10), other = c(0, 1)),
                  data.frame(name = c("Florence", "Steady"), n = c(9, 10), other = c(0, 1)))
  current <- data.frame(name = c("Florence", "Steady"), n = c(10, 10), other = c(2, 2))
  out <- flag_other_share_jump(current, history)
  expect_equal(out$name, "Florence")
  expect_equal(out$mean_share, 0)
  expect_equal(out$other, 2)
})

test_that("flag_other_share_jump stays quiet without enough history, postings or Other rows", {
  hist1 <- list(data.frame(name = "A", n = 10, other = 0))
  expect_equal(nrow(flag_other_share_jump(data.frame(name = "A", n = 10, other = 5), hist1)), 0)
  hist2 <- c(hist1, hist1)
  expect_equal(nrow(flag_other_share_jump(data.frame(name = "A", n = 2, other = 2), hist2)), 0)
  expect_equal(nrow(flag_other_share_jump(data.frame(name = "A", n = 10, other = 1), hist2)), 0)
  # already mostly Other: a rise from 50% to 60% isn't a jump
  hist3 <- list(data.frame(name = "A", n = 10, other = 5), data.frame(name = "A", n = 10, other = 5))
  expect_equal(nrow(flag_other_share_jump(data.frame(name = "A", n = 10, other = 6), hist3)), 0)
  expect_equal(nrow(flag_other_share_jump(data.frame(name = "A", n = 10, other = 5), list())), 0)
})

test_that("other_share_counts and build_other_share_report_markdown", {
  counts <- other_share_counts(c("A", "A", "B"), c(TRUE, FALSE, FALSE))
  expect_equal(counts$other, c(1L, 0L))
  flagged <- data.frame(name = "Florence", mean_share = 0, n_weeks = 8L, n = 10L, other = 2L,
                        type = "K-12", examples = "\"YEAR-ROUND POSITION.\"", stringsAsFactors = FALSE)
  md <- build_other_share_report_markdown(flagged, date = "2026-11-05")
  expect_true(any(grepl("**Florence** (K-12): usually 0% Other, now 2 of 10", md, fixed = TRUE)))
  expect_length(build_other_share_report_markdown(flagged[0, ]), 0)
})

test_that("a wrapper dispatch entry still names its fetch_ function (Red Rover districts)", {
  lines <- c('  "Columbia Falls School District 6" = function(session) {',
             '    fetch_redrover_postings(session, "https://jobs.redroverk12.com/org/sd659912",',
             '                            default_location = "Columbia Falls")',
             '  },',
             '  "Huntley Project School District" = fetch_huntley_postings,')
  call <- function(d) list(fn = APPTEGY_DISPATCH_FN, args = list(d))
  expect_equal(scraper_fetch_fn(call("Columbia Falls School District 6"), lines), "fetch_redrover_postings")
  expect_equal(scraper_fetch_fn(call("Huntley Project School District"), lines), "fetch_huntley_postings")
  expect_true(is.na(scraper_fetch_fn(call("Nowhere School District"), lines)))
})

test_that("find_keyword_conflicts flags titles whose words name another bucket, and spares real exceptions", {
  # Real archived titles (2026-11-08 tuning run). Flagged: what the classifier
  # got wrong before its fixes that day, given the bucket it had.
  flagged <- find_keyword_conflicts(
    c("Temporary Business Office Support Clerk", "CCA Cross Country Aide", "Bus Paraprofessional - Transportation",
      "Kitchen Aide"),
    c("Support Services", "Support Services", "Paraprofessional", "Support Services"),
    k12_keyword_conflict_rules)
  expect_equal(flagged, c("secretary or clerk outside Staff", "coach aide outside Athletics",
                          "bus aide or monitor outside Transportation", "food-service word outside Food Services"))
  expect_equal(find_keyword_conflicts("Custodian - Washakie Dining Center", "Culinary", he_keyword_conflict_rules),
               "custodian outside Maintenance & Service")
  # Spared: the word is secondary, or the title is a dual role.
  spared <- find_keyword_conflicts(
    c("Nutrition Services Secretary", "Summer Nutrition Services Van Driver", "Secretary/Paraprofessional",
      "Alternative High School Principal / Counselor", "Bus Driver/Classroom Paraprofessional", "Para Teacher Assistant"),
    c("Staff", "Transportation", "Paraprofessional", "Support Services", "Paraprofessional", "Paraprofessional"),
    k12_keyword_conflict_rules)
  expect_true(all(is.na(spared)))
  expect_true(is.na(find_keyword_conflicts("Hourly Pooled - Custodian/Dish Room Attendant - Bakery", "Culinary",
                                           he_keyword_conflict_rules)))
  # The bucket the classifier gives today raises nothing for any of these.
  t <- c("Temporary Business Office Support Clerk", "CCA Cross Country Aide", "Bus Paraprofessional - Transportation")
  expect_true(all(is.na(find_keyword_conflicts(t, classify_k12_position(t), k12_keyword_conflict_rules))))
})

test_that("build_keyword_conflict_report_markdown lists each title once, and nothing when there are none", {
  expect_identical(build_keyword_conflict_report_markdown(
    data.frame(source = character(), type = character(), title = character(), bucket = character(), rule = character())),
    character(0))
  hits <- data.frame(source = c("Laramie #1", "Laramie #1"), type = "K-12", title = "Kitchen Aide",
                     bucket = "Support Services", rule = "food-service word outside Food Services")
  md <- build_keyword_conflict_report_markdown(hits, date = "2026-11-08")
  expect_equal(sum(grepl("Kitchen Aide", md)), 1)
  expect_match(md[1], "different bucket \\(2026-11-08\\)")
})

# Standing substitute lists (MT issue #13, Lone Rock, 2026-11-10): an LLM-read
# list of substitute pools doesn't make a source "likely_broken" unless the
# source posts substitute jobs itself.
test_that("substitute lines are set aside only for a source whose own titles have none", {
  pool <- c("bus driver substitutes", "classroom teacher substitutes", "kitchen substitutes", "para professionals substitutes")
  expect_length(drop_standing_pool_titles(pool, c("Special Education Paraprofessional", "Bus Driver and Maintenance Director")), 0)
  # a board that posts substitute jobs: the same lines are real misses
  expect_equal(drop_standing_pool_titles(pool, c("Substitute Teacher", "3rd Grade Teacher")), pool)
  # no history to judge by: keep everything
  expect_equal(drop_standing_pool_titles(pool, NULL), pool)
  # real titles survive next to pool lines; "Subject"-like words aren't substitutes
  expect_equal(drop_standing_pool_titles(c("kitchen substitutes", "Subject Area Specialist", "Bus subs"), "Math Teacher"),
               "Subject Area Specialist")
})

test_that("an LLM read of only a standing substitute list no longer promotes to likely_broken", {
  pool <- c("bus driver substitutes", "classroom teacher substitutes", "custodial substitutes",
            "kitchen substitutes", "office staff substitutes", "para professionals substitutes")
  out <- combine_verdict_with_llm("inconclusive", pool, c("Special Education Paraprofessional"))
  expect_equal(out$verdict, "looks_genuinely_empty")
  expect_match(out$note, "standing substitute list \\(6")
  # the old behaviour stands where the source does post substitutes, or without history
  expect_equal(combine_verdict_with_llm("inconclusive", pool, "Substitute Teacher")$verdict, "likely_broken")
  expect_equal(combine_verdict_with_llm("inconclusive", pool)$verdict, "likely_broken")
  # a real title among the pool lines still promotes
  expect_equal(combine_verdict_with_llm("inconclusive", c(pool, "Head Cook"), "Bus Driver")$verdict, "likely_broken")
})

test_that("recent_source_titles reads one source's titles from the K-12 and HE archives", {
  dir <- withr::local_tempdir(); k <- file.path(dir, "k"); h <- file.path(dir, "h"); dir.create(k); dir.create(h)
  write.csv(data.frame(District = c("A", "B"), title = c("Math Teacher", "Substitute Teacher")), file.path(k, "combined_2026-11-03.csv"), row.names = FALSE)
  write.csv(data.frame(District = "A", title = "Bus Driver"), file.path(k, "combined_2026-11-10.csv"), row.names = FALSE)
  writexl::write_xlsx(data.frame(Institution = "U", Title = "Adjunct"), file.path(h, "hedata_2026-11-10.xlsx"))
  expect_setequal(recent_source_titles("A", "K-12", k12_dir = k, he_dir = h), c("Math Teacher", "Bus Driver"))
  expect_equal(recent_source_titles("A", "K-12", weeks = 1, k12_dir = k, he_dir = h), "Bus Driver")
  expect_equal(recent_source_titles("U", "Higher Ed", k12_dir = k, he_dir = h), "Adjunct")
  expect_null(recent_source_titles("A", "K-12", k12_dir = file.path(dir, "none"), he_dir = h))
})

test_that("Lone Rock's real page and history: inconclusive text, a substitute-only LLM read, no auto-fix", {
  # Page text rendered 2026-11-10 (scripts/repro_scraper.R); the two real
  # openings were gone, the standing substitute list stayed.
  text <- paste(readLines(test_path("fixtures", "drift_lonerock_substitute_list_2026-11-10.txt"), warn = FALSE), collapse = "\n")
  expect_equal(score_page_text_for_job_signal(text), "inconclusive")
  # What the LLM read off it in CI (issue #13).
  llm <- c("bus driver substitutes", "classroom teacher substitutes", "custodial substitutes",
           "kitchen substitutes", "office staff substitutes", "para professionals substitutes")
  history <- recent_source_titles("Lone Rock School District", "K-12", k12_dir = here::here("Archivek12_Data"))
  expect_gt(length(history), 0)
  expect_false(any(grepl(STANDING_POOL_PATTERN, history, perl = TRUE)))
  expect_equal(combine_verdict_with_llm(score_page_text_for_job_signal(text), llm, history)$verdict, "looks_genuinely_empty")
  # Billings posts substitute jobs on its own board, so the same lines would count there.
  expect_true(any(grepl(STANDING_POOL_PATTERN, recent_source_titles("Billings Public Schools", "K-12", k12_dir = here::here("Archivek12_Data")), perl = TRUE)))
})
