
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

test_that("collapse_statewide_feed_names buckets OPI rows under the label state_config.R gives", {
  df <- data.frame(
    District = c("SCOBEY", "Miles City, MT", "Billings Public Schools", "Yaak, Montana"),
    Posting_Source = c(OPI_STATEWIDE_SOURCE, OPI_STATEWIDE_SOURCE,
                       "AppliTrack (direct district board)", OPI_STATEWIDE_SOURCE),
    stringsAsFactors = FALSE
  )
  expect_equal(collapse_statewide_feed_names(df), c(OPI_STATEWIDE_SOURCE, OPI_STATEWIDE_SOURCE,
                                                    "Billings Public Schools", OPI_STATEWIDE_SOURCE))
})

test_that("build_source_url_lookup covers every real registered district and institution, and OPI", {
  lookup <- build_source_url_lookup()
  k12 <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  he <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
  expect_equal(unname(lookup[k12$District]), k12$Job_Link)
  expect_equal(unname(lookup[he$Institution]), he$Job_Link)
  expect_equal(unname(lookup[OPI_STATEWIDE_SOURCE]), OPI_STATEWIDE_URL)
  # A name in both registries would resolve to the K-12 row only.
  expect_length(intersect(k12$District, he$Institution), 0)
})

# ---- Tier 3: per-source auto-fix issues -----------------------------------
# The dispatch logic is tested in edjobs (test-scraper-dispatch.R). These
# check Montana's data: state_config.R's specs against the real registries
# and scraper files -- the live check and repro script depend on them.

test_that("every scraper function MT_SCRAPER_SPECS names really exists", {
  fns <- vapply(MT_SCRAPER_SPECS, `[[`, character(1), "fn")
  expect_true(all(vapply(fns, exists, logical(1), mode = "function")),
              info = paste("missing:", paste(fns[!vapply(fns, exists, logical(1), mode = "function")], collapse = ", ")))
})

test_that("every real registered K-12 row resolves to a real scraper function, called as Mt_ED_Jobs.Rmd calls it", {
  k12 <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  for (i in seq_len(nrow(k12))) {
    call <- resolve_scraper_call(k12$District[i])
    expect_false(is.null(call), info = k12$Platform[i])
    expect_equal(call$where, "k12_district_registry.csv")
    if (call$map) {
      expect_equal(k12$Platform[i], "Apptegy", info = k12$District[i])
      expect_true(call$session)
      expect_true(k12$District[i] %in% names(APPTEGY_DISTRICT_SCRAPERS), info = k12$District[i])
    } else {
      expect_true(exists(call$fn, mode = "function"), info = paste(k12$Platform[i], "->", call$fn))
    }
  }
  hinsdale <- resolve_scraper_call("Hinsdale Public Schools")
  expect_equal(hinsdale[c("fn", "session")], list(fn = "fetch_hinsdale_postings", session = FALSE))
  expect_equal(hinsdale$args, list(k12$Job_Link[k12$District == "Hinsdale Public Schools"]))
  tyler <- k12[k12$Platform == "TylerPortico", ][1, ]
  expect_equal(resolve_scraper_call(tyler$District)$args, list(tyler$Slug, tyler$District))
  expect_equal(resolve_scraper_call(k12$District[k12$Platform == "BroadviewHeuristic"][1])$args, list())
  # Red Rover: the API's org ID (Slug) and the slug its links carry (Columbia Falls: 4161 / sd659912).
  cf <- resolve_scraper_call("Columbia Falls School District 6")
  expect_equal(cf[c("fn", "session")], list(fn = "fetch_redrover_postings", session = FALSE))
  expect_equal(cf$args, list("4161", "sd659912"))
})

test_that("every real registered HE platform except the known gaps resolves to a real scraper function", {
  he <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
  for (i in seq_len(nrow(he))) {
    call <- resolve_scraper_call(he$Institution[i])
    if (he$Platform[i] %in% c("SharesBoard", "AdpWorkforceNow", "IsolvedHire")) {
      expect_null(call, info = he$Platform[i])
    } else {
      expect_false(is.null(call), info = he$Platform[i])
      expect_true(exists(call$fn, mode = "function"), info = paste(he$Platform[i], "->", call$fn))
    }
  }
  expect_null(resolve_scraper_call("No Such District"))
})

test_that("scraper_fetch_fn follows the Apptegy map to the real fetch_* function", {
  lines <- scraper_source_lines()
  expect_equal(scraper_fetch_fn(resolve_scraper_call("Lone Rock School District"), lines), "fetch_lonerock_postings")
  expect_true(scraper_reads_inner_text("fetch_lonerock_postings", lines))
  expect_false(scraper_reads_inner_text("fetch_applitrack_postings", lines))
  # Every map district's entry names a fetch_ function the evidence step can read.
  k12 <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  for (d in k12$District[k12$Platform == "Apptegy"]) {
    expect_false(is.na(scraper_fetch_fn(resolve_scraper_call(d), lines)), info = d)
  }
})

test_that("an innerText scraper's issue hands the agent the CI capture as its fixture", {
  call <- resolve_scraper_call("Lone Rock School District")
  ev <- gather_autofix_evidence(call, "Lone Rock School District", lonerock_capture(), repo_root = here::here())
  expect_true(ev$inner_text)
  expect_equal(ev$fixtures[1], "apptegy_lonerock_content_2026-09-30.txt")
  expect_true("apptegy_lonerock_rendered.txt" %in% ev$fixtures)
  expect_equal(ev$diff_against, "apptegy_lonerock_content_2026-09-30.txt")

  body <- paste(build_autofix_issue_body(lonerock_row(), call, evidence = ev, captured_on = "2026-09-30"), collapse = "\n")
  expect_match(body, "### What CI saw", fixed = TRUE)
  expect_match(body, "Full page text captured in CI", fixed = TRUE)
  expect_match(body, "Classified Employee Application", fixed = TRUE)
  expect_match(body, "1. Save the **Full page text captured in CI**", fixed = TRUE)
  expect_match(body, "the `APPTEGY_DISTRICT_SCRAPERS[[\"Lone Rock School District\"]]` entry in misc_district_scrapers.R", fixed = TRUE)
  expect_match(body, "rendered this page in CI", fixed = TRUE)
  expect_match(body, "scripts/repro_scraper.R \"Lone Rock School District\"", fixed = TRUE)
  expect_match(body, "Do **not** edit the registries (k12_district_registry.csv, he_institution_registry.csv), the accumulated data under `Mt_Ed_Jobs/`, or archives.", fixed = TRUE)
  expect_equal(parse_autofix_marker(body), "Lone Rock School District")
  expect_equal(parse_autofix_expected_titles(body),
               c("Special Education Paraprofessional", "Bus Driver and Maintenance Director"))
})

test_that("an HTTP scraper's issue keeps the capture as context and asks for a raw fixture", {
  row <- data.frame(name = "Hinsdale Public Schools", type = "K-12", mean_count = 3, count = 0,
                    url = "https://hinsdale.k12.mt.us/District/1557-Untitled.html",
                    llm_titles = NA_character_, stringsAsFactors = FALSE)
  call <- resolve_scraper_call(row$name)
  ev <- gather_autofix_evidence(call, row$name, "Route Bus Drivers\nDaycare Manager", repo_root = here::here())
  expect_false(ev$inner_text)
  expect_equal(ev$diff, character(0))
  expect_true(length(ev$fixtures) > 0)
  body <- paste(build_autofix_issue_body(row, call, evidence = ev), collapse = "\n")
  expect_match(body, "`fetch_hinsdale_postings()`", fixed = TRUE)
  expect_match(body, "1. Fetch the live page", fixed = TRUE)
  expect_no_match(body, "Diff: newest text fixture", fixed = TRUE)
  expect_no_match(body, "rendered this page in CI", fixed = TRUE)
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
