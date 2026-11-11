# Turns the weekly pipeline's derived-dataset writes from "reprocess every
# archived raw snapshot from scratch" into "append this week's newly
# computed rows onto what's already on disk."
#
# Ported verbatim from the Wyoming Education Jobs Dashboard's
# history_accumulator.R -- fully state-agnostic (no Wyoming-specific
# columns or logic), so Montana's pipeline gets the same O(this week) --
# not O(all history) -- behavior from the start rather than needing this
# fix retrofitted after the archive has already grown large. See Wyoming's
# own version for the full "why" (100+ archive files and growing, O(all
# history) work on every run against a hard CI timeout).
#
# append_weekly_rows() instead takes only this week's freshly classified
# rows and appends them onto the existing accumulated CSV. The archived raw
# snapshots are still written every run as the durable source of truth /
# disaster-recovery path -- they're just not read back every run.

# check_total_matches_parts() and rebuild_parity_row() moved to the edjobs package in phase 2 (2026-11-11); attached here so
# every script that sources this file still has them.
suppressMessages(library(edjobs))

suppressMessages(library(dplyr))

# Appends new_rows (expected to be exactly one Archive_Date's worth of
# freshly computed rows) onto whatever's already at existing_path.
#
# Idempotent: if new_rows' date is already present in the existing file
# (a same-day re-run), that date's old rows are replaced rather than
# duplicated, so running the pipeline twice in one day can't double-count
# that day.
#
# Fails loudly on a column mismatch between the existing file and new_rows
# rather than silently writing a jagged file via bind_rows()'s NA-padding --
# a classifier renaming/adding a column is a real schema change that needs
# a human decision, not something that should get baked into the growing
# history without anyone noticing.
#
# read_fn is injectable so this is testable against synthetic existing data
# without real files on disk.
append_weekly_rows <- function(existing_path, new_rows, date_col = "Archive_Date",
                                read_fn = utils::read.csv) {
  if (nrow(new_rows) == 0) {
    if (!file.exists(existing_path)) return(new_rows)
    existing <- read_fn(existing_path, stringsAsFactors = FALSE)
    existing[[date_col]] <- as.character(existing[[date_col]])
    return(existing)
  }

  new_rows[[date_col]] <- as.character(new_rows[[date_col]])
  new_dates <- unique(new_rows[[date_col]])
  if (length(new_dates) != 1) {
    stop("append_weekly_rows(): new_rows must contain exactly one ", date_col,
         ", got ", length(new_dates), ": ", paste(new_dates, collapse = ", "))
  }

  if (!file.exists(existing_path)) {
    return(new_rows)
  }

  existing <- read_fn(existing_path, stringsAsFactors = FALSE)
  existing[[date_col]] <- as.character(existing[[date_col]])

  if (!setequal(names(existing), names(new_rows))) {
    stop(
      "append_weekly_rows(): column mismatch between existing ", existing_path,
      " (", paste(sort(names(existing)), collapse = ", "), ") and this week's new rows (",
      paste(sort(names(new_rows)), collapse = ", "), "). A classifier or schema likely ",
      "changed -- fix the mismatch, or rebuild the file from the raw archive, rather than ",
      "letting bind_rows() silently pad the difference with NA."
    )
  }

  # Same-day re-run guard -- drop this date's rows from the existing file
  # before appending, so a re-run replaces rather than duplicates.
  existing <- existing[existing[[date_col]] != new_dates, , drop = FALSE]

  dplyr::bind_rows(existing, new_rows[names(existing)])
}


# ---------------------------------------------------------------------------
# The K-12 derived rows, built one way for the weekly pipeline
# (Mt_ED_Jobs.Rmd) and for the from-archive rebuild
# (scripts/rebuild_k12_history_from_archive.R), so the two can't drift apart
# (classification safeguards proposal, item 12: the rebuild had dropped
# OPI_District, Also_On_OPI, Close_Date and Est_*).
# ---------------------------------------------------------------------------

# combinedclean.csv's rows from counted K-12 postings (direct rows plus the OPI
# rows the rule counts): placeholders out, current classifier, posted pay
# guarded (drop_implausible_pay()), and the OEWS pay estimate for the
# posting's role in its district's county -- the registry's, else (OPI rows)
# the county of the district its detail page names; statewide where neither
# is known. Needs bls_oews_scraper.R sourced.
build_k12_combinedclean <- function(counted, oews_wages, district_county, opi_counties, state = "MT") {
  for (col in c("OPI_District", "Close_Date", "OPI_Description")) {
    if (!col %in% names(counted)) counted[[col]] <- NA_character_
  }
  if (!"Also_On_OPI" %in% names(counted)) counted$Also_On_OPI <- NA
  counted$Close_Date <- as.character(counted$Close_Date)
  out <- counted %>%
    filter(!is_placeholder_posting(title)) %>%
    # OPI's title is its subject field; the description's opening refines the
    # bucket (k12_role_hint(); OPI descriptions are archived from 2026-11-03).
    mutate(Role_Hint = ifelse(grepl("OPI", Posting_Source) & !is.na(OPI_Description) & nzchar(OPI_Description),
                              k12_role_hint(OPI_Description), NA_character_),
           position = classify_k12_position(title, Role_Hint),
           District = canonicalize_k12_district(District)) %>%
    ensure_posted_pay_columns() %>%
    drop_implausible_pay()
  out <- attach_oews_estimates(out, oews_wages,
                               dplyr::coalesce(district_county$County[match(out$District, district_county$District)],
                                               opi_counties$County[match(out$OPI_District, opi_counties$OPI_District)]),
                               state)
  out %>%
    select(title, Archive_Date, date_posted, position, location, url, District,
           Posting_Source, Posting_Identity_Method, Posting_ID, OPI_District, Also_On_OPI,
           Close_Date, all_of(POSTED_PAY_COLUMNS), all_of(OEWS_ESTIMATE_COLUMNS), Role_Hint)
}

# k12jobanalysis.csv's rows: the Teacher postings, with subject and broad
# category.
build_k12_teacher_rows <- function(combinedclean) {
  combinedclean %>%
    filter(position == "Teacher") %>%
    mutate(Category = classify_k12_subject(title),
           Broad_Category = classify_k12_broad_category(Category)) %>%
    select(title, Archive_Date, position, location, url, District,
           Posting_Source, Posting_Identity_Method, Posting_ID, Category, Broad_Category,
           any_of("Role_Hint"))
}

