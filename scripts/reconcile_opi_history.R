#!/usr/bin/env Rscript
# scripts/reconcile_opi_history.R
#
# Re-applies the current OPI rule (opi_reconcile.R: posting-level matching
# against each district's own board) to the committed K-12 history, so past
# weeks are counted the way the pipeline counts now. Rebuilds rather than
# adjusts, so it can be rerun safely after any change to the rule:
#
#   k12_district_weekly_totals.csv  recomputed from each raw archive: direct
#                                   rows + the OPI rows the rule counts. (Checked
#                                   2026-11-03: before any OPI change, the
#                                   committed totals equalled the archives for
#                                   all 3,739 district-weeks.)
#   k12jobanalysis.csv              committed direct-board rows kept as they are;
#                                   OPI teacher rows rebuilt from the archives
#                                   with the current classifier
#   allsum.csv / allnow.csv         recomputed from k12jobanalysis.csv
#   combinedclean.csv               latest week: OPI rows rebuilt as the pipeline
#                                   builds them; Also_On_OPI recomputed
#
# Archives before 2026-11-03 carry no OPI description, so their OPI postings are
# matched on the OPI subject title alone (rougher; user's choice 2026-11-03), and
# OPI's repeat listings of one job can't be recognized (a title+date proxy was
# right only about half the time), so past weeks run ~30 postings/week high.
# Archives written by the district-level rule (OPI_Counted, 2026-11-03 run) are
# re-decided too (recompute = TRUE). Raw archives are never modified.
# Afterwards run scripts/generate_job_duration_spells.R.
#
# Usage (repo root): Rscript scripts/reconcile_opi_history.R [--dry-run]

suppressMessages(library(dplyr))
source("k12_he_classification.R")
source("opi_reconcile.R")
library(edjobs)

dry_run <- "--dry-run" %in% commandArgs(trailingOnly = TRUE)
app <- "Mt_Ed_Jobs"
crosswalk <- read.csv(file.path(app, "mt_district_crosswalk.csv"), stringsAsFactors = FALSE, colClasses = c(LEAID = "character"))
registry <- read.csv("k12_district_registry.csv", stringsAsFactors = FALSE)

read_archive_week <- function(path) {
  read.csv(path, colClasses = c(Archive_Date = "character"), stringsAsFactors = FALSE) %>%
    select(-any_of("X")) %>%
    mutate(Archive_Date = as.character(as.Date(Archive_Date, tryFormats = c("%Y-%m-%d", "%m/%d/%Y")))) %>%
    mutate(across(any_of(c("title", "position", "location", "url", "District", "Posting_Source")), normalize_posting_text)) %>%
    add_k12_posting_identity() %>%
    distinct(Posting_ID, .keep_all = TRUE)
}
is_opi_row <- function(df) {
  src <- if ("Posting_Source" %in% names(df)) df$Posting_Source else rep(NA_character_, nrow(df))
  x <- grepl("^OPI ", src) | is_opi_statewide_posting(df$url)
  x[is.na(x)] <- FALSE
  x
}

# ---- each archived week under the current rule ----
files <- list.files("Archivek12_Data", pattern = "^combined_.*\\.csv$", full.names = TRUE)
# In date order, each week's rule result passed to the next: an OPI posting
# whose board twin closed since the previous week stops counting
# (close_opi_lost_twins(), as in the pipeline from 2026-11-17).
weeks <- vector("list", length(files)); previous <- NULL
for (i in seq_along(files)) {
  w <- read_archive_week(files[i])
  rule <- opi_rule_for_archive(w, crosswalk, registry, recompute = TRUE, previous = previous)
  previous <- rule
  w$Is_OPI <- rule$Is_OPI
  w$Counted <- rule$Counted
  w$District <- canonicalize_k12_district(rule$District)
  weeks[[i]] <- w[w$Counted & !is_placeholder_posting(w$title), , drop = FALSE]
}
names(weeks) <- vapply(weeks, function(w) w$Archive_Date[1], character(1))

totals <- bind_rows(lapply(weeks, function(w) w %>% group_by(District, Archive_Date) %>%
                             summarize(n = n_distinct(Posting_ID), .groups = "drop"))) %>%
  arrange(Archive_Date, District)
old_totals <- read.csv(file.path(app, "k12_district_weekly_totals.csv"), stringsAsFactors = FALSE)
cat("Weekly K-12 totals, committed -> rebuilt (direct + counted OPI):\n")
print(full_join(old_totals %>% group_by(Archive_Date) %>% summarize(committed = sum(n), .groups = "drop"),
                totals %>% group_by(Archive_Date) %>% summarize(rebuilt = sum(n), .groups = "drop"), by = "Archive_Date"), n = Inf)

# ---- k12jobanalysis.csv: direct rows kept, OPI teacher rows rebuilt ----
k12 <- read.csv(file.path(app, "k12jobanalysis.csv"), stringsAsFactors = FALSE)
k12_direct <- k12[!is_opi_row(k12), , drop = FALSE]
opi_teach <- bind_rows(lapply(weeks, function(w) w[w$Is_OPI, , drop = FALSE])) %>%
  mutate(position = classify_k12_position(title, if ("OPI_Description" %in% names(.)) k12_role_hint(OPI_Description) else NULL)) %>%
  filter(position == "Teacher") %>%
  mutate(Category = classify_k12_subject(title), Broad_Category = classify_k12_broad_category(Category),
         Posting_Source = "OPI Jobs for Teachers (statewide)",
         # k12jobanalysis.csv gained Role_Hint on 2026-11-09; archives before
         # 2026-11-03 have no OPI_Description, so theirs is NA.
         Role_Hint = if ("OPI_Description" %in% names(.)) k12_role_hint(OPI_Description) else NA_character_) %>%
  select(all_of(names(k12)))
k12_new <- bind_rows(k12_direct, opi_teach) %>% arrange(Archive_Date)
cat(sprintf("\nk12jobanalysis.csv: %d direct rows kept, OPI rows %d -> %d\n", nrow(k12_direct), sum(is_opi_row(k12)), nrow(opi_teach)))

k12sumdistrict <- summarize_k12_posting_counts(k12_new)
k12sum <- k12sumdistrict %>% group_by(Broad_Category, Archive_Date) %>% summarize(sum = sum(sum), .groups = "drop") %>%
  mutate(District = "Total") %>% select(Broad_Category, Archive_Date, District, sum)
allsum <- bind_rows(k12sum, k12sumdistrict)
latest <- k12sumdistrict %>% filter(Archive_Date == max(Archive_Date))
allnow <- bind_rows(latest %>% group_by(Broad_Category) %>% summarize(Sum = sum(sum), .groups = "drop") %>% mutate(District = "Total"),
                    latest %>% ungroup() %>% transmute(Broad_Category, Sum = sum, District))

# ---- combinedclean.csv: latest week's OPI rows rebuilt ----
cc <- read.csv(file.path(app, "combinedclean.csv"), stringsAsFactors = FALSE)
wk <- max(cc$Archive_Date)
if (!wk %in% names(weeks)) stop("No archive for combinedclean's week ", wk, "; nothing written.")
latest_week <- read_archive_week(files[names(weeks) == wk])
opi_now <- weeks[[wk]][weeks[[wk]]$Is_OPI, , drop = FALSE]
# Also_On_OPI: the direct postings an OPI posting matched this week.
is_o <- is_opi_row(latest_week)
dir_now <- latest_week[!is_o, , drop = FALSE]
dir_now$District <- canonicalize_k12_district(dir_now$District)
r <- reconcile_opi_with_direct(latest_week[is_o, , drop = FALSE], dir_now, crosswalk, registry, today = as.Date(wk), stale_fallback = FALSE)
also <- r$direct_df$Posting_ID[r$direct_df$Also_On_OPI]

oews <- read.csv(file.path(app, "oews_role_wages.csv"), stringsAsFactors = FALSE, colClasses = c(Area_Code = "character"))
opi_counties <- read.csv(file.path(app, "opi_district_counties.csv"), stringsAsFactors = FALSE)
if (!"OPI_District" %in% names(opi_now)) opi_now$OPI_District <- NA_character_
opi_rows <- opi_now %>%
  mutate(position = classify_k12_position(title, if ("OPI_Description" %in% names(.)) k12_role_hint(OPI_Description) else NULL),
         Also_On_OPI = FALSE) %>%
  ensure_posted_pay_columns() %>%
  drop_implausible_pay()
opi_rows <- attach_oews_estimates(opi_rows, oews,
                                  dplyr::coalesce(registry$County[match(opi_rows$District, registry$District)],
                                                  opi_counties$County[match(opi_rows$OPI_District, opi_counties$OPI_District)]), "MT")
cc_direct <- cc[!is_opi_row(cc), , drop = FALSE]
cc_direct$Also_On_OPI <- cc_direct$Posting_ID %in% also
opi_rows <- opi_rows[, intersect(names(cc), names(opi_rows)), drop = FALSE]
for (col in names(opi_rows)) if (!identical(class(opi_rows[[col]]), class(cc_direct[[col]]))) {
  opi_rows[[col]] <- methods::as(opi_rows[[col]], class(cc_direct[[col]])[1])     # e.g. Est_Year integer vs character
}
cc_new <- bind_rows(cc_direct, opi_rows)[, names(cc)]
cat(sprintf("combinedclean.csv (%s): %d direct rows (%d Also_On_OPI), OPI rows %d -> %d; %d rows\n", wk, nrow(cc_direct),
            sum(cc_direct$Also_On_OPI), sum(is_opi_row(cc)), nrow(opi_rows), nrow(cc_new)))

if (dry_run) {
  cat("\n--dry-run: nothing written.\n")
} else {
  write.csv(k12_new, file.path(app, "k12jobanalysis.csv"), row.names = FALSE)
  write.csv(allsum, file.path(app, "allsum.csv"), row.names = FALSE)
  write.csv(allnow, file.path(app, "allnow.csv"), row.names = FALSE)
  write.csv(totals, file.path(app, "k12_district_weekly_totals.csv"), row.names = FALSE)
  write.csv(cc_new, file.path(app, "combinedclean.csv"), row.names = FALSE)
  cat("\nWritten. Next: Rscript scripts/generate_job_duration_spells.R\n")
}
