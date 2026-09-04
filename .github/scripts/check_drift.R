# Tier 1 of the drift-alert system (see drift_check.R for the pure logic
# and its tests). Non-blocking and informational only -- unlike
# sanity_check.R, this never aborts the workflow. Writes
# /tmp/drift_flagged.csv, empty (header-only) if nothing looks off.

source("drift_check.R")

read_k12_archive <- function(path) {
  df <- read.csv(path, stringsAsFactors = FALSE)
  # Snapshots written before Posting_Source was added (pre-2026-08-18) can't
  # be collapsed -- there's no column saying which rows came from the OPI
  # statewide feed -- so every raw OPI location string in them would enter
  # the baseline as its own source and get flagged the moment that exact
  # string stops appearing. Drop those weeks from the K-12 baseline entirely
  # rather than let them reintroduce the noise this collapse exists to remove.
  if (!"Posting_Source" %in% names(df)) return(character(0))
  collapse_statewide_feed_names(df)
}

read_he_archive <- function(path) {
  df <- readxl::read_xlsx(path)
  df$Institution
}

load_snapshots <- function(dir, pattern, date_regex, reader, exclude_date) {
  files <- list.files(dir, pattern = pattern, full.names = TRUE)
  dates <- regmatches(files, regexpr(date_regex, files))
  keep <- dates != exclude_date
  files <- files[keep]
  dates <- dates[keep]

  snapshots <- lapply(files, function(f) data.frame(name = reader(f)))
  names(snapshots) <- dates
  snapshots
}

today <- format(Sys.Date(), "%Y-%m-%d")
date_regex <- "[0-9]{4}-[0-9]{2}-[0-9]{2}"

k12_snapshots <- load_snapshots("Archivek12_Data", "^combined_.*\\.csv$", date_regex, read_k12_archive, today)
he_snapshots <- load_snapshots("Archived_HE_Data", "^hedata_.*\\.xlsx$", date_regex, read_he_archive, today)

k12_baseline <- build_historical_counts(k12_snapshots, "name")
he_baseline <- build_historical_counts(he_snapshots, "name")

current_k12 <- as.data.frame(table(collapse_statewide_feed_names(
  read.csv("Mt_Ed_Jobs/combinedclean.csv", stringsAsFactors = FALSE)
)))
names(current_k12) <- c("name", "count")
current_he <- as.data.frame(table(readxl::read_xlsx("Mt_Ed_Jobs/hedata.xlsx")$Institution))
names(current_he) <- c("name", "count")

tag_type <- function(df, label) {
  if (nrow(df) > 0) df$type <- label
  df
}

flagged_k12 <- tag_type(flag_drift(current_k12, k12_baseline), "K-12")
flagged_he <- tag_type(flag_drift(current_he, he_baseline), "Higher Ed")

flagged <- if (nrow(flagged_k12) == 0 && nrow(flagged_he) == 0) {
  data.frame(name = character(0), mean_count = numeric(0), n_weeks = integer(0), count = numeric(0), type = character(0))
} else {
  rbind(flagged_k12, flagged_he)
}

# scrape_log.csv is this same run's own record of what actually errored vs.
# came back genuinely empty (see attach_scrape_log_errors()'s comment in
# drift_check.R) -- read it if the pipeline step before this one produced
# one. Its absence (a fresh checkout with nothing scraped yet) just means no
# source gets a scrape_error attached, same as before this existed.
scrape_log <- if (file.exists("scrape_log.csv")) {
  read.csv("scrape_log.csv", stringsAsFactors = FALSE)
} else {
  data.frame(timestamp = character(0), source = character(0), status = character(0),
             n_rows = integer(0), error_message = character(0))
}
flagged <- attach_scrape_log_errors(flagged, scrape_log)

cat(sprintf(
  "Drift check: %d K-12 baseline sources, %d HE baseline sources, %d flagged (%d confirmed by scrape_log as errored).\n",
  nrow(k12_baseline), nrow(he_baseline), nrow(flagged), sum(!is.na(flagged$scrape_error))
))
if (nrow(flagged) > 0) print(flagged)

write.csv(flagged, "/tmp/drift_flagged.csv", row.names = FALSE)
