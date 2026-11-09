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

# Consistency check for the incremental-append mechanism itself -- verifies
# this week's freshly computed "Total" rows actually equal the sum of this
# week's own per-district/per-institution "parts" rows, run proactively
# BEFORE anything is written to the growing accumulated history. A mismatch
# means a bug in this week's summary computation -- stop() rather than
# silently appending a corrupted week onto otherwise-good history.
check_total_matches_parts <- function(total_rows, part_rows, group_cols, value_col = "sum") {
  parts_agg <- part_rows %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(group_cols))) %>%
    dplyr::summarize(parts_sum = sum(.data[[value_col]]), .groups = "drop")

  merged <- total_rows %>%
    dplyr::select(dplyr::all_of(group_cols), total_value = dplyr::all_of(value_col)) %>%
    dplyr::full_join(parts_agg, by = group_cols)

  mismatches <- merged %>%
    dplyr::filter(is.na(total_value) | is.na(parts_sum) | total_value != parts_sum)

  if (nrow(mismatches) > 0) {
    stop(
      "check_total_matches_parts(): this week's Total row(s) don't equal the sum of their ",
      "own parts -- a bug in this week's summary computation, not a data-source problem. ",
      "Refusing to append a corrupted week onto the accumulated history.\n",
      paste(utils::capture.output(print(mismatches)), collapse = "\n")
    )
  }
  invisible(TRUE)
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

# Rebuild parity (classification safeguards, item 12): how one rebuilt file
# differs from the committed one, ignoring row order, NA vs "" and \r\n vs \n (CSV
# round-trips blur them). Both sides compared as text. Returns one row:
# File, Committed_Rows, Rebuilt_Rows, Missing_Cols (in committed, not rebuilt),
# Extra_Cols, Only_Committed / Only_Rebuilt (row counts on the shared columns)
# and Example (one differing row from each side).
rebuild_parity_row <- function(file, committed, rebuilt) {
  as_text <- function(d) {
    d <- as.data.frame(d, stringsAsFactors = FALSE)
    d[] <- lapply(d, function(x) {
      x <- gsub("\r\n", "\n", as.character(x), fixed = TRUE)   # read.csv() turns a quoted \r\n into \n
      x[is.na(x) | x == ""] <- "<NA>"
      x
    })
    d
  }
  committed <- as_text(committed); rebuilt <- as_text(rebuilt)
  common <- intersect(names(committed), names(rebuilt))
  key <- function(d) if (length(common)) do.call(paste, c(unname(d[common]), sep = " | ")) else character(nrow(d))
  a <- key(committed); b <- key(rebuilt)
  # Multiset difference: a row twice in one file and once in the other differs.
  tab <- function(x) table(factor(x, levels = unique(c(a, b))))
  diff_count <- tab(a) - tab(b)
  only_c <- names(diff_count)[diff_count > 0]; only_r <- names(diff_count)[diff_count < 0]
  data.frame(File = file, Committed_Rows = nrow(committed), Rebuilt_Rows = nrow(rebuilt),
             Missing_Cols = paste(setdiff(names(committed), names(rebuilt)), collapse = ", "),
             Extra_Cols = paste(setdiff(names(rebuilt), names(committed)), collapse = ", "),
             Only_Committed = sum(diff_count[diff_count > 0]), Only_Rebuilt = -sum(diff_count[diff_count < 0]),
             Example = paste(c(if (length(only_c)) paste("committed:", only_c[1]), if (length(only_r)) paste("rebuilt:", only_r[1])),
                             collapse = " // "),
             stringsAsFactors = FALSE)
}
