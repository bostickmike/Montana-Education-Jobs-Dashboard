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
# Posted-pay coverage
# --------------------------------------------------------------------------

# A pay source that breaks doesn't lose postings -- each one just comes
# back with Pay_* blank -- so flag_drift() above can't see it. This compares
# each source's share of postings with stated pay against its own history
# in the raw archives. Archives written before a source captured pay have
# no Pay_* column and are skipped, not counted as zero.

# One row per source: postings (n) and how many state pay (with_pay).
pay_coverage_counts <- function(names, has_pay) {
  if (length(names) == 0) {
    return(data.frame(name = character(0), n = integer(0), with_pay = integer(0),
                      stringsAsFactors = FALSE))
  }
  n <- tapply(rep(1L, length(names)), names, sum)
  with_pay <- tapply(as.integer(has_pay), names, sum)
  data.frame(name = names(n), n = as.integer(n), with_pay = as.integer(with_pay[names(n)]),
             stringsAsFactors = FALSE)
}

# current: pay_coverage_counts() for this run. history: a list of the same,
# one per archived week that had Pay_*. A source is flagged when it has at
# least min_weeks weeks with min_postings or more postings, its average
# share with pay over those weeks is at least min_share, and this run --
# with min_postings or more postings, so a source that lost its postings is
# left to flag_drift() -- has a share at or below drop_threshold times that
# average.
flag_pay_coverage_drop <- function(current, history, min_weeks = 2, min_postings = 3,
                                   min_share = 0.4, drop_threshold = 0.2) {
  empty <- data.frame(name = character(0), mean_share = numeric(0), n_weeks = integer(0),
                      n = integer(0), with_pay = integer(0), stringsAsFactors = FALSE)
  weeks <- do.call(rbind, history)
  if (is.null(weeks) || nrow(weeks) == 0 || nrow(current) == 0) return(empty)
  weeks <- weeks[weeks$n >= min_postings, , drop = FALSE]
  if (nrow(weeks) == 0) return(empty)
  weeks$share <- weeks$with_pay / weeks$n
  baseline <- data.frame(
    name = sort(unique(weeks$name)),
    stringsAsFactors = FALSE
  )
  baseline$n_weeks <- as.integer(table(weeks$name)[baseline$name])
  baseline$mean_share <- as.numeric(tapply(weeks$share, weeks$name, mean)[baseline$name])

  merged <- merge(baseline, current, by = "name")
  merged <- merged[merged$n >= min_postings & merged$n_weeks >= min_weeks &
                     merged$mean_share >= min_share, , drop = FALSE]
  flagged <- merged[merged$with_pay / merged$n <= merged$mean_share * drop_threshold, , drop = FALSE]
  if (nrow(flagged) == 0) return(empty)
  flagged[order(-flagged$mean_share), c("name", "mean_share", "n_weeks", "n", "with_pay")]
}

build_pay_coverage_report_markdown <- function(flagged, date = Sys.Date()) {
  if (nrow(flagged) == 0) return(character(0))
  c(
    paste0("### Posted pay went missing (", date, ")"),
    "",
    paste("These sources still return postings, but far fewer of them carry the pay the posting states",
          "than usual -- the pay field or detail request the scraper reads has likely changed.",
          "Postings and counts are unaffected; the Posted Pay column is blank for them."),
    "",
    sprintf("- **%s** (%s): usually %.0f%% of postings state pay, now %d of %d",
            flagged$name, flagged$type, 100 * flagged$mean_share, flagged$with_pay, flagged$n),
    ""
  )
}

# Report section for this week's posted amounts that drop_implausible_pay()
# blanked (rows of `bad`: source, title, Pay_Min, Pay_Max, Pay_Unit,
# Pay_Text). A misread -- a fee, a benefit's value -- usually means the
# extractor needs a new skip rule; a real but unusual figure means
# PAY_PLAUSIBLE_RANGE needs widening.
build_implausible_pay_report_markdown <- function(bad, date = Sys.Date(), max_rows = 25) {
  if (nrow(bad) == 0) return(character(0))
  shown <- utils::head(bad, max_rows)
  amount <- ifelse(shown$Pay_Min == shown$Pay_Max | is.na(shown$Pay_Max),
                   sprintf("$%s", format(shown$Pay_Min, big.mark = ",")),
                   sprintf("$%s-$%s", format(shown$Pay_Min, big.mark = ","), format(shown$Pay_Max, big.mark = ",")))
  c(
    paste0("### Posted pay blanked as implausible (", date, ")"),
    "",
    paste("These amounts were read from the postings but fall outside PAY_PLAUSIBLE_RANGE",
          "(k12_he_classification.R) for their unit, so the dashboard shows no posted pay for them.",
          "The raw archive keeps them. A misread needs an extractor fix; a real figure needs the range widened."),
    "",
    sprintf("- **%s** (%s) \"%s\": %s per %s -- \"%s\"",
            shown$source, shown$type, shown$title, amount, ifelse(is.na(shown$Pay_Unit), "unknown unit", shown$Pay_Unit),
            substr(gsub("[\r\n]+", " ", shown$Pay_Text), 1, 120)),
    if (nrow(bad) > max_rows) sprintf("- ...and %d more", nrow(bad) - max_rows),
    ""
  )
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
# Tier 2c: Central Safety Net status summary & report formatting
# --------------------------------------------------------------------------

# Summarizes the status of the Central Safety Net statewide vacancy fallback
# (OPI in Montana, WSBA in Wyoming).
#
# Returns a list with:
#   - total_feed_vacancies: total vacancies from the statewide feed
#   - feed_name: display name of the statewide feed
#   - fallback_districts: named list of {district -> count} for registered districts
#                         with active fallback postings
#   - total_fallback_vacancies: sum of fallback vacancies across registered districts
#   - discrepancies: data.frame of unmatched discrepancies for direct districts
#   - markdown: character vector of markdown lines for the alert report
summarize_central_safety_net <- function(
  combined_df = NULL,
  registry = NULL,
  discrepancy_report = NULL,
  scrape_log = NULL,
  feed_label = OPI_STATEWIDE_SOURCE,
  feed_short_name = "OPI",
  discrepancy_path = "mt_discrepancy_report.csv"
) {
  # 1. Total vacancies on the statewide feed
  feed_total <- 0L
  if (!is.null(scrape_log) && nrow(scrape_log) > 0 && "source" %in% names(scrape_log)) {
    feed_log <- scrape_log[grepl(feed_short_name, scrape_log$source, ignore.case = TRUE) |
                           grepl(feed_label, scrape_log$source, fixed = TRUE), , drop = FALSE]
    if (nrow(feed_log) > 0 && "n_rows" %in% names(feed_log)) {
      latest_rows <- feed_log$n_rows[nrow(feed_log)]
      if (!is.na(latest_rows) && is.numeric(latest_rows)) {
        feed_total <- as.integer(latest_rows)
      }
    }
  }

  if (feed_total == 0L && !is.null(combined_df) && nrow(combined_df) > 0) {
    if ("Posting_Source" %in% names(combined_df)) {
      feed_total <- sum(!is.na(combined_df$Posting_Source) & combined_df$Posting_Source == feed_label)
    } else {
      is_feed <- (!is.na(combined_df$url) & grepl(feed_short_name, combined_df$url, ignore.case = TRUE)) |
                 (!is.na(combined_df$posting_id) & grepl(feed_short_name, combined_df$posting_id, ignore.case = TRUE))
      feed_total <- sum(is_feed)
    }
  }

  # 2. Registered districts receiving fallback postings
  registered_districts <- if (!is.null(registry) && "District" %in% names(registry)) {
    unique(registry$District[!is.na(registry$District) & nzchar(registry$District)])
  } else {
    character(0)
  }

  fallback_districts <- list()
  if (!is.null(combined_df) && nrow(combined_df) > 0 && length(registered_districts) > 0) {
    is_feed_row <- if ("Posting_Source" %in% names(combined_df)) {
      !is.na(combined_df$Posting_Source) & combined_df$Posting_Source == feed_label
    } else {
      (!is.na(combined_df$url) & grepl(feed_short_name, combined_df$url, ignore.case = TRUE)) |
      (!is.na(combined_df$posting_id) & grepl(feed_short_name, combined_df$posting_id, ignore.case = TRUE))
    }
    feed_reg_rows <- combined_df[is_feed_row & combined_df$District %in% registered_districts, , drop = FALSE]
    if (nrow(feed_reg_rows) > 0) {
      tbl <- table(feed_reg_rows$District)
      fallback_districts <- as.list(as.integer(tbl))
      names(fallback_districts) <- names(tbl)
    }
  }

  # 3. Discrepancy report
  if (is.null(discrepancy_report) && !is.null(discrepancy_path) && file.exists(discrepancy_path)) {
    discrepancy_report <- tryCatch(
      read.csv(discrepancy_path, stringsAsFactors = FALSE),
      error = function(e) NULL
    )
  }

  disc_unmatched <- if (!is.null(discrepancy_report) && nrow(discrepancy_report) > 0 && "Discrepancy_Type" %in% names(discrepancy_report)) {
    discrepancy_report[!grepl("ghost", discrepancy_report$Discrepancy_Type, ignore.case = TRUE), , drop = FALSE]
  } else {
    data.frame()
  }

  # If fallback_districts is empty but discrepancy_report had matching fallback districts
  if (length(fallback_districts) == 0 && nrow(disc_unmatched) > 0 && "District" %in% names(disc_unmatched)) {
    reg_disc <- disc_unmatched[disc_unmatched$District %in% registered_districts, , drop = FALSE]
    if (nrow(reg_disc) > 0) {
      tbl <- table(reg_disc$District)
      fallback_districts <- as.list(as.integer(tbl))
      names(fallback_districts) <- names(tbl)
    }
  }

  total_fallback_vacancies <- sum(unlist(fallback_districts), 0L)

  # 4. Generate Markdown
  md <- c(
    sprintf("### %s postings at districts we scrape directly", feed_short_name),
    "",
    paste("Openings the statewide feed lists for a district we scrape directly, counted because the district's own",
          "board doesn't list them: the district posts some jobs only on the feed, or our scrape misses them.",
          "A district with many is worth a look."),
    "",
    sprintf("- **Statewide Feed (%s)**: %d active vacancies captured.", feed_short_name, feed_total)
  )

  if (length(fallback_districts) == 0) {
    md <- c(md, sprintf("- **Counted from %s at directly scraped districts**: none (every %s opening at those districts is also on the district's own board).", feed_short_name, feed_short_name))
  } else {
    md <- c(
      md,
      sprintf("- **Counted from %s at directly scraped districts**: %d posting(s) at %d district(s), not on the district's own board:",
              feed_short_name, total_fallback_vacancies, length(fallback_districts))
    )
    for (d_name in names(fallback_districts)) {
      md <- c(md, sprintf("  - **%s**: %d", d_name, fallback_districts[[d_name]]))
    }
  }

  if (nrow(disc_unmatched) == 0) {
    md <- c(md, "- **Central Feed Discrepancies**: 0 unmatched vacancies detected for active direct scrapers.")
  } else {
    md <- c(
      md,
      sprintf("- **Central Feed Discrepancies**: %d unmatched vacancy/vacancies detected on central feed for direct-scraped districts (investigate potential ATS drift):", nrow(disc_unmatched))
    )
    shown_n <- min(nrow(disc_unmatched), 5L)
    for (i in seq_len(shown_n)) {
      r <- disc_unmatched[i, ]
      dp <- if ("Date_Posted" %in% names(r) && !is.na(r$Date_Posted) && nzchar(r$Date_Posted)) sprintf(" (posted %s)", r$Date_Posted) else ""
      t_title <- if ("Title" %in% names(r)) r$Title else ""
      d_dist <- if ("District" %in% names(r)) r$District else ""
      md <- c(md, sprintf("  - **%s**: \"%s\"%s", d_dist, t_title, dp))
    }
    if (nrow(disc_unmatched) > shown_n) {
      md <- c(md, sprintf("  - ... and %d more discrepancies", nrow(disc_unmatched) - shown_n))
    }
  }
  md <- c(md, "")

  list(
    total_feed_vacancies = feed_total,
    feed_name = feed_label,
    fallback_districts = fallback_districts,
    total_fallback_vacancies = total_fallback_vacancies,
    discrepancies = disc_unmatched,
    markdown = md
  )
}

build_drift_report_markdown <- function(
  actionable,
  safety_net_summary = NULL,
  date = Sys.Date(),
  feed_short_name = "OPI",
  intro_explanation = NULL
) {
  if (nrow(actionable) == 0) return(character(0))

  default_intro <- if (is.null(intro_explanation)) {
    "A source is flagged when it has at least 2 weeks of history averaging real postings, and this week's count dropped to 20% or less of that average. These entries are corroborated against the actual live page but still need a human look."
  } else {
    intro_explanation
  }

  lines <- c(
    paste0("Automated drift check flagged ", nrow(actionable), " source(s) as of ", date, "."),
    "",
    default_intro,
    ""
  )

  for (verdict_group in c("confirmed_broken", "likely_broken", "inconclusive", "no_url_available")) {
    subset_rows <- actionable[actionable$verdict == verdict_group, ]
    if (nrow(subset_rows) == 0) next

    label <- switch(verdict_group,
      confirmed_broken = "### Confirmed broken -- the scraper itself errored this run (not just a low count)",
      likely_broken = "### Likely broken -- live page has real job-posting content, scraper reported little/none",
      inconclusive = "### Inconclusive -- drift detected, live page didn't clearly confirm either way",
      no_url_available = "### No URL on file -- couldn't corroborate automatically"
    )
    lines <- c(lines, label, "")
    for (i in seq_len(nrow(subset_rows))) {
      r <- subset_rows[i, ]
      url_part <- if (is.na(r$url)) "" else sprintf(" -- %s", r$url)
      error_part <- if (verdict_group == "confirmed_broken" && !is.na(r$error_message) && nzchar(r$error_message)) sprintf(" (%s)", r$error_message) else ""
      lines <- c(lines, sprintf("- **%s** (%s): averaged %.1f/week, now %d%s%s", r$name, r$type, r$mean_count, r$count, url_part, error_part))
      if ("llm_note" %in% names(r) && !is.na(r$llm_note) && nzchar(r$llm_note)) lines <- c(lines, sprintf("  - %s", r$llm_note))

      if (r$type == "K-12" && !is.null(safety_net_summary)) {
        sn_count <- if ("safety_net_vacancies" %in% names(r) && !is.na(r$safety_net_vacancies)) {
          as.integer(r$safety_net_vacancies)
        } else if (!is.null(safety_net_summary$fallback_districts[[r$name]])) {
          as.integer(safety_net_summary$fallback_districts[[r$name]])
        } else {
          0L
        }

        if (sn_count > 0) {
          lines <- c(lines, sprintf("  - **On %s**: %d posting%s for this district that its own board doesn't list (counted from %s)",
                                    feed_short_name, sn_count, if (sn_count == 1) "" else "s", feed_short_name))
        } else {
          lines <- c(lines, sprintf("  - **On %s**: nothing for this district beyond what its own board lists", feed_short_name))
        }
      }
    }
    lines <- c(lines, "")
  }

  if (!is.null(safety_net_summary) && !is.null(safety_net_summary$markdown)) {
    lines <- c(lines, safety_net_summary$markdown)
  }

  lines
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

# Who works a new auto-fix issue, from the AUTOFIX_ENGINE repo variable:
# "claude" (default) dispatches .github/workflows/claude-autofix.yml,
# "copilot" assigns the issue to the Copilot coding agent via COPILOT_TOKEN,
# "none" just files it. Both agents on one issue would race to open
# competing PRs, so it's one or the other. A typo fails the step loudly
# rather than quietly filing issues nobody works.
AUTOFIX_ENGINES <- c("claude", "copilot", "none")
AUTOFIX_CLAUDE_WORKFLOW <- "claude-autofix.yml"

autofix_engine <- function(value) {
  v <- tolower(trimws(if (length(value) == 0 || is.na(value)) "" else value))
  if (!nzchar(v)) return("claude")
  if (!v %in% AUTOFIX_ENGINES) {
    stop("AUTOFIX_ENGINE must be one of ", paste(AUTOFIX_ENGINES, collapse = ", "), ", not '", value, "'")
  }
  v
}

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
  # Reads its openings-PDF link from the rendered page (2026-11-05).
  CJIHeuristic = list(fn = "fetch_cji_postings", args = "Job_Link", session = TRUE),
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

# ---- Evidence for the agent ------------------------------------------------
# The drift check renders each flagged page in CI, outside the agent's
# firewall. The agent's own render can't be trusted: on issue #7 its
# firewall blocked Apptegy's CDNs, the page came up empty, and it rewrote
# the fetch instead of fixing a renamed stop line. So the issue carries the
# text CI captured, the source's existing fixtures, and a diff between the
# newest text fixture and that capture. These helpers read the scraper and
# test files as text, since file_autofix_issues.R doesn't source the
# scrapers.

AUTOFIX_PAGE_TEXT_MAX_CHARS <- 20000
AUTOFIX_DIFF_MAX_LINES <- 200
SCRAPER_FILES <- c("direct_api_scrapers.R", "misc_district_scrapers.R", "misc_college_scrapers.R")

# The fetch_* function a resolved call ends up in. Apptegy districts are
# looked up in the APPTEGY_DISTRICT_SCRAPERS map's source lines.
scraper_fetch_fn <- function(call, scraper_lines) {
  if (is.null(call)) return(NA_character_)
  if (!identical(call$fn, APPTEGY_DISPATCH_FN)) return(call$fn)
  hit <- grep(sprintf('"%s" = fetch_', call$args[[1]]), scraper_lines, fixed = TRUE, value = TRUE)
  if (length(hit) > 0) return(sub('.*= (fetch_[A-Za-z0-9_]+).*', "\\1", hit[1]))
  # A wrapper entry ("<district>" = function(session) { fetch_redrover_postings(session, ...) },
  # every Red Rover district): the first fetch_ call in its body.
  start <- grep(sprintf('"%s" = function(', call$args[[1]]), scraper_lines, fixed = TRUE)
  if (length(start) == 0) return(NA_character_)
  body <- scraper_lines[start[1]:min(length(scraper_lines), start[1] + 5)]
  call_line <- grep("fetch_[A-Za-z0-9_]+\\(", body, value = TRUE)
  if (length(call_line) == 0) NA_character_ else sub('.*?(fetch_[A-Za-z0-9_]+)\\(.*', "\\1", call_line[1], perl = TRUE)
}

# Whether fetch_fn's parser consumes document.body.innerText -- the form the
# drift check captured, so the capture can be the new fixture verbatim.
scraper_reads_inner_text <- function(fetch_fn, scraper_lines) {
  if (is.na(fetch_fn)) return(FALSE)
  start <- grep(sprintf("^%s <- function", fetch_fn), scraper_lines)
  if (length(start) == 0) return(FALSE)
  later <- grep("^[A-Za-z_.][A-Za-z0-9_.]* <- ", scraper_lines)
  end <- c(later[later > start[1]], length(scraper_lines) + 1)[1] - 1
  any(grepl("document.body.innerText", scraper_lines[start[1]:end], fixed = TRUE))
}

# Fixture files used by the tests of fetch_fn or its parse_* twin, newest
# first: dated names by date, then undated ones in file order.
# test_files: named list of test-file lines (name = file name).
source_fixtures <- function(fetch_fn, test_files) {
  if (is.na(fetch_fn)) return(character(0))
  fns <- c(fetch_fn, sub("^fetch_", "parse_", fetch_fn))
  found <- character(0)
  for (lines in test_files) {
    starts <- grep("^\\s*test_that\\(", lines)
    ends <- c(starts[-1] - 1, length(lines))
    for (i in seq_along(starts)) {
      if (!any(vapply(fns, grepl, logical(1), x = lines[starts[i]], fixed = TRUE))) next
      block <- lines[starts[i]:ends[i]]
      refs <- unlist(regmatches(block, gregexpr('test_path\\("fixtures", "[^"]+"\\)', block)))
      found <- c(found, sub('.*"([^"]+)"\\)$', "\\1", refs))
    }
  }
  found <- unique(found)
  dates <- ifelse(grepl("[0-9]{4}-[0-9]{2}-[0-9]{2}", found),
                  sub(".*([0-9]{4}-[0-9]{2}-[0-9]{2}).*", "\\1", found), "")
  found[order(dates, seq_along(found), decreasing = c(TRUE, FALSE), method = "radix")]
}

# Unified diff of two texts after trimming lines and dropping blanks
# (innerText and html_text2() disagree on blank lines, which is noise).
# Uses the system `diff`; returns character(0) when identical or absent.
text_diff <- function(old_text, new_text, old_label = "old", new_label = "new") {
  norm <- function(x) { x <- trimws(unlist(strsplit(x, "\n", fixed = TRUE))); x[nzchar(x)] }
  if (!nzchar(Sys.which("diff"))) return(character(0))
  f_old <- tempfile(); f_new <- tempfile()
  on.exit(unlink(c(f_old, f_new)))
  writeLines(norm(old_text), f_old, useBytes = TRUE)
  writeLines(norm(new_text), f_new, useBytes = TRUE)
  out <- suppressWarnings(system2("diff", c("-u", "--label", shQuote(old_label), "--label", shQuote(new_label),
                                            shQuote(f_old), shQuote(f_new)), stdout = TRUE, stderr = FALSE))
  as.character(out)
}

# Everything build_autofix_issue_body() shows the agent beyond the drift
# numbers. repo_root is a parameter only so tests can point it elsewhere.
gather_autofix_evidence <- function(call, page_text, repo_root = ".") {
  scraper_lines <- unlist(lapply(file.path(repo_root, SCRAPER_FILES), readLines, warn = FALSE))
  test_paths <- list.files(file.path(repo_root, "tests", "testthat"), pattern = "^test-.*[.]R$", full.names = TRUE)
  test_files <- stats::setNames(lapply(test_paths, readLines, warn = FALSE), basename(test_paths))

  fetch_fn <- scraper_fetch_fn(call, scraper_lines)
  fixtures <- source_fixtures(fetch_fn, test_files)
  inner_text <- scraper_reads_inner_text(fetch_fn, scraper_lines)
  has_text <- length(page_text) == 1 && !is.na(page_text) && nzchar(trimws(page_text))

  diff_against <- if (inner_text && has_text) utils::head(fixtures[grepl("[.]txt$", fixtures)], 1) else character(0)
  diff <- if (length(diff_against) == 1) {
    old <- paste(readLines(file.path(repo_root, "tests", "testthat", "fixtures", diff_against),
                           warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    text_diff(old, page_text, diff_against, "page text captured in CI")
  } else character(0)

  list(fetch_fn = fetch_fn, fixtures = fixtures, inner_text = inner_text,
       page_text = if (has_text) page_text else NA_character_,
       diff_against = if (length(diff_against) == 1) diff_against else NA_character_,
       diff = diff)
}

# The "What CI saw" section of the issue body, from gather_autofix_evidence().
autofix_evidence_markdown <- function(evidence, captured_on) {
  if (is.null(evidence)) return(character(0))
  out <- c("### What CI saw", "")
  if (length(evidence$fixtures) > 0) {
    out <- c(out, sprintf("Existing fixtures for `%s()` in `tests/testthat/fixtures/`, newest first: %s",
                          evidence$fetch_fn, paste0("`", evidence$fixtures, "`", collapse = ", ")), "")
  }
  if (length(evidence$diff) > 0) {
    d <- evidence$diff
    cut <- length(d) > AUTOFIX_DIFF_MAX_LINES
    out <- c(out,
             sprintf("<details><summary>Diff: newest text fixture (<code>%s</code>) &rarr; page text captured in CI</summary>", evidence$diff_against),
             "", "````diff", utils::head(d, AUTOFIX_DIFF_MAX_LINES),
             if (cut) sprintf("... diff truncated (%d more lines)", length(d) - AUTOFIX_DIFF_MAX_LINES),
             "````", "", "</details>", "")
  }
  if (!is.na(evidence$page_text)) {
    txt <- evidence$page_text
    cut <- nchar(txt) > AUTOFIX_PAGE_TEXT_MAX_CHARS
    if (cut) txt <- substr(txt, 1, AUTOFIX_PAGE_TEXT_MAX_CHARS)
    out <- c(out,
             sprintf("<details><summary>Full page text captured in CI (<code>document.body.innerText</code>, %s)</summary>", captured_on),
             "", "````text", txt, if (cut) "... page text truncated", "````", "", "</details>", "")
  }
  if (length(out) == 2) character(0) else out
}

# row: one likely_broken row of corroborate_drift.R's results (name, type,
# mean_count, count, url, llm_titles). registry_row: that source's registry
# row, or NULL. evidence: gather_autofix_evidence()'s result, or NULL.
# Returns the markdown body of the per-source auto-fix issue -- written as
# the task prompt the Copilot coding agent will work from.
build_autofix_issue_body <- function(row, registry_row = NULL, run_url = NULL,
                                     evidence = NULL, captured_on = as.character(Sys.Date())) {
  titles <- if (is.na(row$llm_titles) || !nzchar(row$llm_titles)) character(0)
            else strsplit(row$llm_titles, " | ", fixed = TRUE)[[1]]
  call <- if (is.null(registry_row)) NULL else resolve_scraper_call(registry_row)
  # The CI capture is the new fixture verbatim only when the parser reads
  # innerText; otherwise it's context and the agent captures raw HTML.
  use_capture <- !is.null(evidence) && isTRUE(evidence$inner_text) && !is.na(evidence$page_text)
  repro <- sprintf("`Rscript scripts/repro_scraper.R \"%s\"`", row$name)

  c(
    sprintf("<!-- autofix-source: %s -->", row$name),
    "",
    sprintf("The weekly drift check found that **%s** (%s) averaged %.1f postings/week but the scraper returned **%d** this run, while the live page still lists real postings. The page markup most likely changed and the parser no longer matches it.",
            row$name, row$type, row$mean_count, as.integer(row$count)),
    "",
    sprintf("- **Live page:** %s", if (is.na(row$url)) "(none on file)" else row$url),
    if (!is.null(registry_row)) sprintf("- **Registry platform:** `%s`", registry_row$Platform),
    if (!is.null(call)) sprintf("- **Scraper entry point:** %s (and the `parse_*` function it calls, if any)", describe_scraper_call(call)),
    if (!is.null(call)) sprintf("- **Reproduce:** %s runs this scraper against its fixtures and the live site", repro),
    if (!is.null(run_url)) sprintf("- **Drift-check run:** %s", run_url),
    "",
    if (length(titles) > 0) c(
      "An LLM read these postings off the live page (a hint, not ground truth -- verify against the page itself):",
      "",
      paste0("- ", titles),
      "",
      "The list covers the whole page, so it can include things this source's parser deliberately leaves out (e.g. a standing substitute-recruiting list). Restore what the parser used to find; see the comment above its `parse_*` function.",
      ""
    ),
    if (isTRUE(call$session)) c(
      "The drift check rendered this page in CI with chromote (`document.body.innerText`), so it renders normally outside your sandbox. If your render shows no postings, check the firewall's blocked hosts before changing how the scraper fetches the page -- see `.github/copilot-instructions.md`.",
      ""
    ),
    autofix_evidence_markdown(evidence, captured_on),
    "### Task",
    "",
    if (use_capture) {
      sprintf("1. Save the **Full page text captured in CI** above, verbatim, as a **new, dated fixture** in `tests/testthat/fixtures/` (e.g. `<source>_rendered_%s.txt`). It is real captured data -- the exact text this scraper parses -- so prefer it over your own render. Keep the existing fixtures; the old layout must keep parsing.", captured_on)
    } else {
      "1. Fetch the live page and save it as a **new, dated real fixture** in `tests/testthat/fixtures/` (keep the existing fixture -- the old layout must keep parsing)."
    },
    if (length(evidence$diff) > 0) {
      "2. Start from the diff above: it shows what changed since the newest fixture. Fix the parser so it extracts the real postings from the new fixture. Keep the change minimal and in the existing style."
    } else {
      "2. Fix the parser so it extracts the real postings from the new fixture. Keep the change minimal and in the existing style."
    },
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
  # First heading after the list -- "### What CI saw" (whose diff and page
  # text can hold "- " lines) or "### Task".
  end <- grep("^### ", lines)
  end <- end[end > start[1]]
  if (length(start) == 0 || length(end) == 0) return(character(0))
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

# --------------------------------------------------------------------------
# Title quality (classification safeguards items 5 and 6; run weekly by
# .github/scripts/check_title_quality.R, non-blocking)
# --------------------------------------------------------------------------

# A scraper that starts reading the wrong element still returns rows, and
# the row count looks fine to flag_drift(): what changes is what the "title"
# holds -- a schedule sentence, a summary paragraph, a level without its role.
# lint_title_shape() names the problem per title (NA when the title looks
# like a job title). Each rule was measured against every archived week in
# both states (2026-11-05): it flags the misreads found by hand in the
# 2026-11-01 classification audit and nothing that is merely an unusual but
# real title. Long real titles run to ~190 characters (UW, Goshen), so
# max_chars is 200. A start date a district writes into its own title
# ("beginning the 2026-27 school year.") isn't flagged; "- Open Until
# Filled." is (WY ledger: Fremont #21).

# Abbreviations whose trailing period isn't the end of a sentence.
TITLE_ABBREVIATION_PATTERN <- paste0(
  "(?i)\\b(Jr|Sr|Asst|Assist|Assoc|Coord|Dept|Ed|Sp|St|Supt|Admin|Tech|Spec|Mgr|Dir|Fed|Govt|",
  "Mr|Mrs|Ms|Dr|No|Vo|Ag|Phys|Res|Prof|Approx|Hrs|P\\.E|Ft)\\."
)

lint_title_shape <- function(title, max_chars = 200) {
  t <- as.character(title)
  t[is.na(t)] <- ""
  t <- trimws(t)
  no_abbrev <- gsub(TITLE_ABBREVIATION_PATTERN, "", t, perl = TRUE)
  level_words <- "(?i)\\b(high school|middle school|junior high|jr\\.? high|elementary|hs|ms|head|assistant|asst\\.?|varsity|junior varsity|jv)\\b"
  rules <- list(
    "blank title" = !nzchar(t),
    "no job named" = grepl("^(other|none|n/?a|tbd|tba|positions?|jobs?|vacanc(y|ies)|openings?|see (job )?description|untitled)$",
                           t, ignore.case = TRUE),
    "level and rank only, no role" = nzchar(t) &
      grepl("(?i)\\b(head|assistant|asst)\\b", t, perl = TRUE) &
      !grepl("[A-Za-z0-9]", gsub(level_words, "", t, perl = TRUE)),
    "schedule or detail sentence" = grepl("\\.\\s*$", no_abbrev) &
      (grepl("[A-Za-z]\\.\\s+[A-Za-z]", no_abbrev) |
         grepl("\\b(must|required|requires|hiring|open until|hours?|hrs|per (day|hour|week)|full[- ]time|part[- ]time|year[- ]round|apply|mon|fri)\\b",
               no_abbrev, ignore.case = TRUE)),
    "field label" = grepl("^(summary|description|job description|job summary|position summary|position|job title|title|location|department|salary|pay|wage|posted|closing date|status|requirements|qualifications)\\s*:",
                          t, ignore.case = TRUE),
    "markup left in" = grepl("StartFragment|EndFragment|&[a-z]+;|&#[0-9]+;|<[a-z/][^>]*>|​", t, ignore.case = TRUE, perl = TRUE),
    "file name" = grepl("[A-Za-z]{2,}_[A-Za-z]{2,}|\\s-\\sCopy$", t),
    "too long" = nchar(t) > max_chars
  )
  reasons <- do.call(cbind, lapply(names(rules), function(r) ifelse(rules[[r]], r, NA_character_)))
  if (length(t) == 0) return(character(0))
  out <- apply(matrix(reasons, nrow = length(t)), 1, function(r) paste(r[!is.na(r)], collapse = "; "))
  out[!nzchar(out)] <- NA_character_
  out
}

# Titles that state pay ("Secretary - $14 per hour", "Substitute Teachers
# $150/day") on postings whose Posted Pay is blank: no scraper reads pay from
# the title, so the posting's own pay isn't shown. Uses extract_posted_pay()
# (k12_he_classification.R), which ignores amounts that aren't pay ("$10,000
# Hiring Incentive").
title_pay_unrecorded <- function(title, pay_min) {
  t <- as.character(title)
  has_dollar <- !is.na(t) & grepl("\\$\\s*[0-9]", t)
  out <- rep(FALSE, length(t))
  if (!any(has_dollar & is.na(pay_min))) return(out)
  idx <- which(has_dollar & is.na(pay_min))
  out[idx] <- !is.na(extract_posted_pay(t[idx])$Pay_Min)
  out
}

# hits: data.frame(source, type, title, reason). At most max_per_source
# titles are listed per source.
build_title_lint_report_markdown <- function(hits, date = Sys.Date(), max_per_source = 5) {
  if (nrow(hits) == 0) return(character(0))
  key <- paste(hits$type, hits$source, sep = "\r")
  lines <- unlist(lapply(unique(key), function(k) {
    h <- hits[key == k, , drop = FALSE]
    n_postings <- nrow(h)
    h <- h[!duplicated(h$title), , drop = FALSE]
    shown <- utils::head(h, max_per_source)
    c(sprintf("- **%s** (%s), %d posting(s):", h$source[1], h$type[1], n_postings),
      sprintf("  - \"%s\" -- %s", substr(gsub("[\r\n]+", " ", shown$title), 1, 120), shown$reason),
      if (nrow(h) > max_per_source) sprintf("  - ...and %d more", nrow(h) - max_per_source))
  }))
  c(
    paste0("### Titles that don't look like job titles (", date, ")"),
    "",
    paste("This week's postings whose title looks like something other than a job title: page text, a",
          "summary, a heading, or pay the Posted Pay column doesn't carry. Usually the scraper is reading",
          "the wrong element. These titles are classified as they are, so they can land in the wrong bucket."),
    "",
    lines,
    ""
  )
}

# One row per source: postings (n) and how many the classifier puts in Other
# (other).
other_share_counts <- function(names, is_other) {
  out <- pay_coverage_counts(names, is_other)
  names(out)[names(out) == "with_pay"] <- "other"
  out
}

# current: other_share_counts() for this run. history: a list of the same,
# one per recent archived week (the caller picks the window). A source is
# flagged when it has at least min_weeks weeks with min_postings or more
# postings, and this run has min_postings or more postings, at least
# min_other of them in Other, and an Other share at least `jump` above its
# average and at least `ratio` times it. Replayed over every archived week
# (8-week window, 2026-11-05) these defaults flag 2 MT and 2 WY source-weeks,
# all real scraper problems (Florence-Carlton schedule lines, Albany section
# headings); stricter settings flag none of them.
flag_other_share_jump <- function(current, history, min_weeks = 2, min_postings = 3, min_other = 2,
                                  jump = 0.15, ratio = 1.5) {
  empty <- data.frame(name = character(0), mean_share = numeric(0), n_weeks = integer(0),
                      n = integer(0), other = integer(0), stringsAsFactors = FALSE)
  weeks <- do.call(rbind, history)
  if (is.null(weeks) || nrow(weeks) == 0 || nrow(current) == 0) return(empty)
  weeks <- weeks[weeks$n >= min_postings, , drop = FALSE]
  if (nrow(weeks) == 0) return(empty)
  weeks$share <- weeks$other / weeks$n
  baseline <- data.frame(name = sort(unique(weeks$name)), stringsAsFactors = FALSE)
  baseline$n_weeks <- as.integer(table(weeks$name)[baseline$name])
  baseline$mean_share <- as.numeric(tapply(weeks$share, weeks$name, mean)[baseline$name])
  merged <- merge(baseline, current, by = "name")
  share <- merged$other / merged$n
  flagged <- merged[merged$n_weeks >= min_weeks & merged$n >= min_postings & merged$other >= min_other &
                      share >= merged$mean_share + jump & share >= ratio * merged$mean_share, , drop = FALSE]
  if (nrow(flagged) == 0) return(empty)
  flagged[order(-(flagged$other / flagged$n)), c("name", "mean_share", "n_weeks", "n", "other")]
}

# flagged: flag_other_share_jump() rows plus type and examples (a few of the
# source's Other titles this run).
build_other_share_report_markdown <- function(flagged, date = Sys.Date()) {
  if (nrow(flagged) == 0) return(character(0))
  c(
    paste0("### More postings than usual land in Other (", date, ")"),
    "",
    paste("These sources' share of postings the classifier can't place jumped against their own recent",
          "weeks. Usually the scraper started picking up page text instead of titles; otherwise the",
          "classifier needs a rule for a new kind of title."),
    "",
    sprintf("- **%s** (%s): usually %.0f%% Other, now %d of %d -- e.g. %s",
            flagged$name, flagged$type, 100 * flagged$mean_share, flagged$other, flagged$n, flagged$examples),
    ""
  )
}
