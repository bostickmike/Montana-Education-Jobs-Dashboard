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
