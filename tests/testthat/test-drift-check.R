
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

test_that("parse_autofix_expected_titles recovers the titles build_autofix_issue_body wrote", {
  row <- data.frame(name = "X", type = "K-12", mean_count = 3, count = 0, url = "u",
                    llm_titles = "Route Bus Drivers | Daycare Manager", stringsAsFactors = FALSE)
  body <- paste(build_autofix_issue_body(row), collapse = "\n")
  expect_equal(parse_autofix_expected_titles(body), c("Route Bus Drivers", "Daycare Manager"))
  expect_equal(parse_autofix_expected_titles("no titles here"), character(0))
})

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

test_that("the drift report's feed (state_config.R) is the OPI feed the rest of the pipeline labels", {
  feed <- edjobs::current_state_config()$feed
  expect_equal(feed$label, OPI_STATEWIDE_SOURCE)
  expect_equal(feed$url, OPI_STATEWIDE_URL)
  expect_equal(edjobs::current_state_config()$drift_baseline_from, as.Date("2026-08-06"))
})
