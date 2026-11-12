# The accumulated history files (combinedclean.csv, k12jobanalysis.csv, the
# weekly totals): the weekly pipeline classifies only this run's rows and
# appends them, instead of re-reading every archive. The archived raw
# snapshots are still written every run as the durable source of truth; the
# rebuild scripts reproduce the accumulated files from them.
#
# append_weekly_rows(), summarize_k12_posting_counts(),
# build_k12_combinedclean() and build_k12_teacher_rows() are in the edjobs
# package since 0.10.0 (phase 4, 2026-11-12), with one K-12 output schema
# for every state (edjobs::K12_POSTING_COLUMNS). check_total_matches_parts()
# and rebuild_parity_row() moved in phase 2. Attached here so every script
# that sources this file still has them.
suppressMessages(library(edjobs))

suppressMessages(library(dplyr))
# The OPI feed's label (state_config.R), which build_k12_combinedclean() reads
# to tell feed rows from direct ones; loaded here unless the caller already did.
if (is.null(current_state_config())) source("state_config.R")

# Montana's raw rows and archives name the feed columns after OPI; the
# accumulated files use the shared names.
MT_K12_COLUMNS <- c(Feed_District = "OPI_District", Also_On_Feed = "Also_On_OPI", Feed_Description = "OPI_Description")

# combinedclean.csv's rows from counted K-12 postings (direct rows plus the
# OPI rows the rule counts), for the weekly pipeline (Mt_ED_Jobs.Rmd) and the
# from-archive rebuild (scripts/rebuild_k12_history_from_archive.R) alike. An
# OPI row's county is its registry district's, else the county of the
# district its detail page names (opi_counties).
mt_k12_combinedclean <- function(counted, oews_wages, district_county, opi_counties) {
  build_k12_combinedclean(counted, oews_wages, district_county, "MT", columns = MT_K12_COLUMNS,
                          feed_counties = stats::setNames(opi_counties$County, opi_counties$OPI_District),
                          canonicalize_district = canonicalize_k12_district)
}
