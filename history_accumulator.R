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
