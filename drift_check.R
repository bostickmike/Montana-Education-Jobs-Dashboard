# Detects when a source that reliably has real postings suddenly reports
# none -- ported from Wyoming's drift_check.R. build_historical_counts(),
# flag_drift(), check_salary_coverage(), check_salary_value_bounds(),
# check_salary_yoy_plausibility(), and score_page_text_for_job_signal() are
# all state-agnostic (pure functions operating on whatever data/thresholds
# they're given) and kept as-is. Only build_source_url_lookup() at the
# bottom is Montana-specific, and it's actually simpler here: Montana's
# job-postings sources are already consolidated into two registry files
# (k12_district_registry.csv, he_institution_registry.csv) rather than
# Wyoming's several separate per-platform CSVs plus a misc-district
# registry.
#
# Two tiers, kept as separate functions so each is independently testable:
#   1. flag_drift() -- cheap, no network calls. Compares this week's
#      per-source counts against each source's own trailing historical
#      baseline. Pure function, easy to unit test with synthetic history.
#   2. score_page_text_for_job_signal() -- the scoring half of the chromote
#      corroboration step (see .github/scripts/corroborate_drift.R for the
#      live-fetch half).

# Only snapshots from this date forward are valid drift-detection baseline
# candidates -- the date Montana's full pipeline (every K-12/HE platform,
# salary/staffing/Census sources) was completed and first produced real
# data across the board.
BASELINE_VALID_FROM <- as.Date("2026-08-06")

# --------------------------------------------------------------------------
# Tier 1: per-source historical drift detection
# --------------------------------------------------------------------------

# OPI's "Jobs for Teachers" statewide feed publishes a raw free-text
# location per posting (e.g. "SCOBEY", "Miles City, MT", "Yaak, Montana"),
# never a canonical district identity -- see CLAUDE.md's "The Map/District
# Summary intentionally show a narrower slice" note. Tier-1 drift detection
# groups by the District column, so without this every distinct OPI location
# string looks like its own directly-scraped source: ordinary week-to-week
# posting churn in the statewide feed then produces dozens of bogus "dropped
# to zero" flags (23 of them on 2026-09-01 alone) that bury the real
# registry-backed signals. Collapse every OPI-sourced row to the single feed
# it actually is before counting, so OPI is drift-checked as one source
# (which still catches a real collapse of the whole feed).
OPI_STATEWIDE_SOURCE <- "OPI Jobs for Teachers (statewide)"
OPI_STATEWIDE_URL <- "https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx"

# Return `df`'s per-row source names with every statewide-feed row relabelled
# to a single bucket. Falls back to the raw name column when `source_col`
# isn't present; callers working with archive snapshots that predate the
# Posting_Source column should skip those snapshots rather than rely on this
# fallback (see check_drift.R's read_k12_archive()), since their raw OPI
# location strings can't be collapsed and would land in the baseline.
collapse_statewide_feed_names <- function(df, name_col = "District",
                                          source_col = "Posting_Source",
                                          feed_label = OPI_STATEWIDE_SOURCE) {
  names_out <- as.character(df[[name_col]])
  if (!source_col %in% names(df)) return(names_out)
  is_feed <- !is.na(df[[source_col]]) & df[[source_col]] == feed_label
  names_out[is_feed] <- feed_label
  names_out
}

# A source dropping to (near) zero is ambiguous on count alone: a genuinely
# quiet week looks identical to a scraper that started erroring. But
# safe_scrape() (scrape_helpers.R) already logs which one happened, to
# scrape_log.csv, in the very same pipeline run that produced this week's
# drift-flagged counts -- so check there first, before spending a live
# chromote render on a guess. A source whose most recent logged attempt
# this run was a real "error" (not "empty") is a much stronger and cheaper
# signal: the registered URL itself is broken (a dead ATS tenant, a DNS
# failure, a migrated platform -- see 2026-09's Butte/Belgrade/Hamilton
# AppliTrack migrations), not just "no visible postings right now".
# scrape_log's `source` strings aren't always an exact match for a flagged
# `name` (e.g. Apptegy districts log as "Apptegy/chromote: <District>"), so
# match by substring containment rather than requiring equality.
attach_scrape_log_errors <- function(flagged, scrape_log) {
  flagged$scrape_error <- rep(NA_character_, nrow(flagged))
  if (nrow(flagged) == 0 || nrow(scrape_log) == 0) return(flagged)

  # Keep only each source's single most recent logged attempt -- a source
  # that errored earlier in the run but succeeded on a later retry/re-run
  # must NOT be reported as currently broken, so status is checked on the
  # latest attempt, not on "was there ever an error this run".
  latest <- scrape_log[order(scrape_log$timestamp), ]
  latest <- latest[!duplicated(latest$source, fromLast = TRUE), ]
  errors <- latest[!is.na(latest$status) & latest$status == "error", ]
  if (nrow(errors) == 0) return(flagged)

  for (i in seq_len(nrow(flagged))) {
    hits <- which(vapply(errors$source, function(s) grepl(flagged$name[i], s, fixed = TRUE), logical(1)))
    if (length(hits) > 0) flagged$scrape_error[i] <- errors$error_message[hits[1]]
  }
  flagged
}

build_historical_counts <- function(archive_snapshots, name_col) {
  # archive_snapshots: named list of data.frames, names are "YYYY-MM-DD"
  # dates, each data.frame has a `name_col` column of source names (one row
  # per posting, same shape as combinedclean.csv/hedata.xlsx).
  valid_dates <- names(archive_snapshots)[as.Date(names(archive_snapshots)) >= BASELINE_VALID_FROM]

  if (length(valid_dates) == 0) {
    return(data.frame(name = character(0), n_weeks = integer(0), mean_count = numeric(0)))
  }

  counts_by_week <- lapply(valid_dates, function(d) {
    df <- archive_snapshots[[d]]
    as.data.frame(table(df[[name_col]]), stringsAsFactors = FALSE)
  })

  all_counts <- do.call(rbind, counts_by_week)
  names(all_counts) <- c("name", "count")
  all_counts$count <- as.numeric(all_counts$count)

  aggregate(count ~ name, data = all_counts, FUN = function(x) c(n = length(x), mean = mean(x))) -> agg
  data.frame(
    name = agg$name,
    n_weeks = agg$count[, "n"],
    mean_count = agg$count[, "mean"],
    stringsAsFactors = FALSE
  )
}

# current_counts: data.frame(name, count) for this week's just-rendered data.
# baseline: output of build_historical_counts().
# min_weeks: a source needs at least this many valid historical weeks before
#   it's eligible to be flagged at all -- with 0 or 1 data points there's no
#   real baseline yet, just noise.
# drop_threshold: flag if current count <= mean_count * drop_threshold.
flag_drift <- function(current_counts, baseline, min_weeks = 2, drop_threshold = 0.2) {
  merged <- merge(baseline, current_counts, by = "name", all.x = TRUE)
  merged$count[is.na(merged$count)] <- 0

  eligible <- merged[merged$n_weeks >= min_weeks & merged$mean_count > 0, ]
  flagged <- eligible[eligible$count <= eligible$mean_count * drop_threshold, ]
  flagged[order(-flagged$mean_count), c("name", "mean_count", "n_weeks", "count")]
}

# --------------------------------------------------------------------------
# Tier 0: salary-source structural/coverage checks
# --------------------------------------------------------------------------

# Salary/staffing/Census data has a small, essentially fixed universe (18 MT
# districts, 6 MT public HE institutions, 56 MT counties) and changes far
# less often than job postings, so a trailing statistical baseline like
# flag_drift() doesn't fit. Instead this is a hard assertion against that
# known universe size.
check_salary_coverage <- function(name, actual, expected, min_ok = expected) {
  if (actual >= min_ok) return(NULL)
  data.frame(name = name, expected = expected, actual = actual, stringsAsFactors = FALSE)
}

# --------------------------------------------------------------------------
# Tier 0b: salary VALUE plausibility (as opposed to coverage/row-count)
# --------------------------------------------------------------------------

# actual: named numeric vector (name = district/institution, value = salary).
check_salary_value_bounds <- function(name, actual, min_ok, max_ok) {
  bad <- actual < min_ok | actual > max_ok
  bad[is.na(bad)] <- FALSE
  if (!any(bad)) return(NULL)
  data.frame(
    name = name, entity = names(actual)[bad], value = unname(actual[bad]),
    min_ok = min_ok, max_ok = max_ok, stringsAsFactors = FALSE
  )
}

# current/prior: named numeric vectors (name = district/institution),
# compared pairwise by name. Flags an entity whose |% change| both (a)
# exceeds hard_ceiling outright and (b) is a real statistical outlier
# against every OTHER entity's change this same run (median absolute
# deviation).
check_salary_yoy_plausibility <- function(current, prior, hard_ceiling = 0.25, mad_multiplier = 5) {
  common <- intersect(names(current), names(prior))
  cur <- current[common]
  pri <- prior[common]
  valid <- !is.na(cur) & !is.na(pri) & pri != 0
  if (sum(valid) < 3) return(NULL)  # too few points for a cross-sectional outlier check to mean anything

  pct_change <- (cur[valid] - pri[valid]) / pri[valid]
  center <- stats::median(pct_change)
  spread <- stats::mad(pct_change)

  is_outlier <- if (spread > 0) {
    abs(pct_change - center) > mad_multiplier * spread & abs(pct_change) > hard_ceiling
  } else {
    abs(pct_change) > hard_ceiling
  }
  if (!any(is_outlier)) return(NULL)

  data.frame(
    name = names(pct_change)[is_outlier],
    prior = unname(pri[valid][is_outlier]),
    current = unname(cur[valid][is_outlier]),
    pct_change = unname(pct_change[is_outlier]),
    stringsAsFactors = FALSE
  )
}

# --------------------------------------------------------------------------
# Source name -> public URL lookup, for the chromote corroboration step
# --------------------------------------------------------------------------

# Montana's own registries already carry a real, human-facing Job_Link per
# source -- unlike Wyoming's several separate per-platform CSVs plus a
# misc-district registry, there's nothing else to combine here.
build_source_url_lookup <- function(
    k12_registry_csv = "k12_district_registry.csv",
    he_registry_csv = "he_institution_registry.csv") {
  k12 <- read.csv(k12_registry_csv, stringsAsFactors = FALSE)
  he <- read.csv(he_registry_csv, stringsAsFactors = FALSE)

  c(
    setNames(k12$Job_Link, k12$District),
    setNames(he$Job_Link, he$Institution),
    # So the collapsed statewide-feed bucket (see collapse_statewide_feed_names())
    # can still be corroborated against its real public page rather than
    # landing in the "no URL on file" bucket.
    setNames(OPI_STATEWIDE_URL, OPI_STATEWIDE_SOURCE)
  )
}

# --------------------------------------------------------------------------
# Tier 2: chromote corroboration scoring (pure function half)
# --------------------------------------------------------------------------

# page_text: visible rendered text of a live page (document.body.innerText
# via chromote). Returns one of "likely_broken", "looks_genuinely_empty", or
# "inconclusive".
score_page_text_for_job_signal <- function(page_text) {
  if (is.na(page_text) || nchar(trimws(page_text)) == 0) {
    return("inconclusive")
  }

  negative_signal <- grepl(
    "no (open |current )?(job|position|vacan)|no openings|not currently (hiring|accepting)|there are (currently )?no",
    page_text, ignore.case = TRUE
  )

  positive_hits <- lengths(regmatches(
    page_text,
    gregexpr("apply now|view details|job title|posted:|closing date|date posted|JobID", page_text, ignore.case = TRUE)
  ))

  if (negative_signal && positive_hits < 3) {
    "looks_genuinely_empty"
  } else if (positive_hits >= 3) {
    "likely_broken"
  } else {
    "inconclusive"
  }
}

# --------------------------------------------------------------------------
# Tier 2b: fold an LLM read of the page into the text-signal verdict
# --------------------------------------------------------------------------

# verdict: from score_page_text_for_job_signal() ("likely_broken" /
#   "looks_genuinely_empty" / "inconclusive"), or "confirmed_broken" /
#   "no_url_available" set upstream in corroborate_drift.R.
# llm_titles: from llm_titles_from_page_text() -- character(0) when the LLM
#   step was skipped (no key) or found nothing.
#
# Returns list(verdict, note):
#   - LLM found real postings and we weren't already at confirmed_broken ->
#     promote to "likely_broken" and say what it found (the scraper returned
#     ~0 but these are demonstrably on the page).
#   - LLM found nothing AND the text signal was only "inconclusive" ->
#     downgrade to "looks_genuinely_empty" (conservative: both weak signals
#     now agree there's nothing there).
#   - otherwise: unchanged.
combine_verdict_with_llm <- function(verdict, llm_titles) {
  n <- length(llm_titles)

  if (n > 0 && !identical(verdict, "confirmed_broken")) {
    shown <- paste(utils::head(llm_titles, 8L), collapse = "; ")
    return(list(
      verdict = "likely_broken",
      note = paste0("an LLM read ", n, " posting(s) off the live page: ",
                    shown, if (n > 8L) ", ..." else "")
    ))
  }

  if (n == 0 && identical(verdict, "inconclusive")) {
    return(list(verdict = "looks_genuinely_empty",
                note = "an LLM read no postings off the live page either"))
  }

  list(verdict = verdict, note = NA_character_)
}

# --------------------------------------------------------------------------
# Tier 3: per-source auto-fix issues (Copilot coding agent hand-off)
# --------------------------------------------------------------------------
#
# The rolling "Scraper drift check" issue stays the human-facing summary.
# On top of it, each "likely_broken" source -- the live page demonstrably
# has postings the scraper missed (Thompson Falls 2026-09-07, Hinsdale
# 2026-09-22: page markup changed, parser didn't) -- gets its own issue
# that .github/scripts/file_autofix_issues.R can assign to the Copilot
# coding agent. confirmed_broken (HTTP 429/520 etc.) and genuinely-empty
# verdicts are deliberately NOT eligible: those are site-side, and a code
# change "fixing" them is exactly the wrong move.
#
# The issue body carries an HTML-comment marker naming the source, so
# .github/scripts/live_check_autofix.R can find which scraper a PR claims
# to fix (via the PR's linked issue) and re-run just that scraper live.

AUTOFIX_LABEL <- "scraper-autofix"
AUTOFIX_ELIGIBLE_VERDICTS <- "likely_broken"
AUTOFIX_MARKER_RE <- "<!--\\s*autofix-source:\\s*(.+?)\\s*-->"

autofix_issue_title <- function(name) paste0("Scraper auto-fix: ", name)

parse_autofix_marker <- function(body) {
  if (length(body) == 0 || is.na(body)) return(NA_character_)
  m <- regmatches(body, regexec(AUTOFIX_MARKER_RE, body, perl = TRUE))[[1]]
  if (length(m) < 2) NA_character_ else m[2]
}

# Explicit platform -> scraper spec. `fn` is the fetch_* function; `args`
# names the registry columns passed positionally (the same call shape
# Mt_ED_Jobs.Rmd uses); `session` means the scraper's first argument is a
# chromote session. Every K-12 "<Name>Heuristic" platform not listed here
# follows fetch_<lowercase name>_postings(Job_Link), and every K-12
# Apptegy/RedRoverK12 district is dispatched through
# misc_district_scrapers.R's own APPTEGY_DISTRICT_SCRAPERS map -- see
# resolve_scraper_call(). HE heuristics don't follow one convention, so
# they're listed. Platforms absent from all three (SharesBoard, split-feed
# ADP/isolved) have no single-source live check; resolve_scraper_call()
# returns NULL and the PR says so. test-drift-check.R asserts every fn
# named here really exists.
SCRAPER_CALL_SPECS <- list(
  AppliTrack   = list(fn = "fetch_applitrack_postings",   args = "Slug"),
  SchoolSpring = list(fn = "fetch_schoolspring_postings", args = "Slug"),
  TylerPortico = list(fn = "fetch_tylerportico_postings", args = c("Slug", "District")),
  TedK12       = list(fn = "fetch_tedk12_postings",       args = "Slug"),
  BroadviewHeuristic = list(fn = "fetch_broadview_postings", args = character(0)),
  PeopleAdmin  = list(fn = "fetch_peopleadmin_atom",      args = c("Feed_URL", "Institution")),
  JazzHR       = list(fn = "fetch_jazzhr_postings",       args = c("Feed_URL", "Institution")),
  Paycom       = list(fn = "fetch_paycom_postings",       args = c("Feed_URL", "Institution")),
  Neogov       = list(fn = "fetch_neogov_postings",       args = c("Feed_URL", "Institution")),
  MilesCCHeuristic   = list(fn = "fetch_miles_cc_postings",   args = "Feed_URL"),
  DawsonCCHeuristic  = list(fn = "fetch_dawson_cc_postings",  args = "Feed_URL"),
  CarrollCollegeHeuristic = list(fn = "fetch_carroll_college_postings", args = "Feed_URL"),
  RockyMountainCollegeHeuristic = list(fn = "fetch_rocky_mountain_college_postings", args = "Feed_URL"),
  SKCHeuristic       = list(fn = "fetch_skc_postings",        args = "Feed_URL"),
  LBHCHeuristic      = list(fn = "fetch_lbhc_postings",       args = "Feed_URL"),
  FPCCHeuristic      = list(fn = "fetch_fpcc_postings",       args = "Feed_URL"),
  AnCollegeHeuristic = list(fn = "fetch_ancollege_postings",  args = "Feed_URL"),
  CDKCHeuristic      = list(fn = "fetch_cdkc_postings",       args = "Feed_URL")
)
APPTEGY_DISPATCH_FN <- "APPTEGY_DISTRICT_SCRAPERS"

# registry_row: one row of k12_district_registry.csv or
# he_institution_registry.csv. Returns list(fn, args, session) with args as
# a list of actual values, or NULL when the platform has no single-source
# live check. Pure lookup -- run it with run_scraper_call().
resolve_scraper_call <- function(registry_row) {
  platform <- registry_row$Platform
  is_k12 <- "District" %in% names(registry_row)
  spec <- SCRAPER_CALL_SPECS[[platform]]
  if (is.null(spec) && is_k12 && platform %in% c("Apptegy", "RedRoverK12")) {
    spec <- list(fn = APPTEGY_DISPATCH_FN, args = "District", session = TRUE)
  }
  if (is.null(spec) && !is_k12 && platform == "Apptegy") {
    spec <- list(fn = "fetch_stonechild_postings", args = "Feed_URL", session = TRUE)
  }
  if (is.null(spec) && is_k12 && grepl("Heuristic$", platform)) {
    spec <- list(fn = paste0("fetch_", tolower(sub("Heuristic$", "", platform)), "_postings"),
                 args = "Job_Link")
  }
  if (is.null(spec)) return(NULL)
  list(fn = spec$fn, args = lapply(spec$args, function(col) registry_row[[col]]),
       session = isTRUE(spec$session))
}

# Human-readable pointer to the code a resolved call runs.
describe_scraper_call <- function(call) {
  if (identical(call$fn, APPTEGY_DISPATCH_FN)) {
    sprintf("the `%s[[\"%s\"]]` entry in misc_district_scrapers.R", APPTEGY_DISPATCH_FN, call$args[[1]])
  } else {
    sprintf("`%s()`", call$fn)
  }
}

# Executes a resolve_scraper_call() result against the live source.
# session_factory is only called for chromote-backed scrapers; apptegy_map
# is a parameter only so tests can swap in a stub.
run_scraper_call <- function(call, session_factory = NULL,
                             apptegy_map = get0(APPTEGY_DISPATCH_FN)) {
  if (!call$session) return(do.call(get(call$fn, mode = "function"), call$args))
  session <- session_factory()
  on.exit(tryCatch(session$close(), error = function(e) NULL), add = TRUE)
  if (identical(call$fn, APPTEGY_DISPATCH_FN)) {
    apptegy_map[[call$args[[1]]]](session)
  } else {
    do.call(get(call$fn, mode = "function"), c(list(session), call$args))
  }
}

# row: one likely_broken row of corroborate_drift.R's results (name, type,
# mean_count, count, url, llm_titles). registry_row: that source's registry
# row, or NULL. Returns the markdown body of the per-source auto-fix issue
# -- written as the task prompt the Copilot coding agent will work from.
build_autofix_issue_body <- function(row, registry_row = NULL, run_url = NULL) {
  titles <- if (is.na(row$llm_titles) || !nzchar(row$llm_titles)) character(0)
            else strsplit(row$llm_titles, " | ", fixed = TRUE)[[1]]
  call <- if (is.null(registry_row)) NULL else resolve_scraper_call(registry_row)

  c(
    sprintf("<!-- autofix-source: %s -->", row$name),
    "",
    sprintf("The weekly drift check found that **%s** (%s) averaged %.1f postings/week but the scraper returned **%d** this run, while the live page still lists real postings. The page markup most likely changed and the parser no longer matches it.",
            row$name, row$type, row$mean_count, as.integer(row$count)),
    "",
    sprintf("- **Live page:** %s", if (is.na(row$url)) "(none on file)" else row$url),
    if (!is.null(registry_row)) sprintf("- **Registry platform:** `%s`", registry_row$Platform),
    if (!is.null(call)) sprintf("- **Scraper entry point:** %s (and the `parse_*` function it calls, if any)", describe_scraper_call(call)),
    if (!is.null(run_url)) sprintf("- **Drift-check run:** %s", run_url),
    "",
    if (length(titles) > 0) c(
      "An LLM read these postings off the live page (a hint, not ground truth -- verify against the page itself):",
      "",
      paste0("- ", titles),
      ""
    ),
    "### Task",
    "",
    "1. Fetch the live page and save it as a **new, dated real fixture** in `tests/testthat/fixtures/` (keep the existing fixture -- the old layout must keep parsing).",
    "2. Fix the parser so it extracts the real postings from the new fixture. Keep the change minimal and in the existing style.",
    "3. Add a regression test against the new fixture asserting the exact titles found.",
    "4. Run `testthat::test_dir(\"tests/testthat\")` and make sure everything passes.",
    "",
    "Do **not** edit the registries, accumulated CSVs under `Mt_Ed_Jobs/`, or archives. If the source has moved to a different platform or URL, or the page genuinely has no postings, don't force a parser change -- say so in the PR description and stop.",
    "",
    sprintf("The PR must reference this issue (`Fixes #<n>`) so the live check can find the source. Label: `%s`.", AUTOFIX_LABEL)
  )
}

# The LLM-read titles build_autofix_issue_body() listed -- the live check's
# (hint-quality) expectation for what the fixed scraper should now return.
parse_autofix_expected_titles <- function(body) {
  lines <- strsplit(body, "\n", fixed = TRUE)[[1]]
  start <- grep("^An LLM read these postings", lines)
  end <- grep("^### Task", lines)
  if (length(start) == 0 || length(end) == 0 || end[1] <= start[1]) return(character(0))
  block <- lines[(start[1] + 1):(end[1] - 1)]
  sub("^- ", "", block[startsWith(block, "- ")])
}

# result: the scraper's data.frame, or a condition object if it errored.
# Returns list(pass, markdown). Fails only on the unambiguous cases -- an
# error or zero rows (the exact symptom the issue was filed for). Fewer
# rows than the LLM read, or titles it didn't match, are reported for the
# human reviewer but don't fail: the LLM list is a hint, not ground truth.
summarize_live_check <- function(source_name, result, expected_titles = character(0)) {
  header <- sprintf("### Live scraper check: %s", source_name)
  if (inherits(result, "condition")) {
    return(list(pass = FALSE, markdown = c(header, "", sprintf(":x: The scraper **errored** against the live site: `%s`", conditionMessage(result)))))
  }
  titles <- if ("Title" %in% names(result)) as.character(result$Title) else character(0)
  if (length(titles) == 0) {
    return(list(pass = FALSE, markdown = c(header, "", ":x: The scraper still returns **0 postings** from the live site.")))
  }

  norm <- function(x) tolower(trimws(x))
  matched <- vapply(expected_titles, function(t) any(grepl(norm(t), norm(titles), fixed = TRUE) |
                                                     vapply(norm(titles), grepl, logical(1), x = norm(t), fixed = TRUE)),
                    logical(1))
  out <- c(header, "",
           sprintf(":white_check_mark: The scraper returned **%d posting(s)** from the live site:", length(titles)),
           "", paste0("- ", utils::head(titles, 25)),
           if (length(titles) > 25) sprintf("- ... and %d more", length(titles) - 25), "")
  if (length(expected_titles) > 0) {
    out <- c(out, sprintf("Matched %d of %d title(s) the drift check's LLM read off the page.", sum(matched), length(expected_titles)))
    if (any(!matched)) out <- c(out, "", "Not matched (check by hand -- the LLM list is a hint, not ground truth):", "",
                                paste0("- ", expected_titles[!matched]))
  }
  list(pass = TRUE, markdown = out)
}
