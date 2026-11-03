#!/usr/bin/env Rscript
# scripts/reconcile_opi_history.R
#
# Applies the OPI-vs-direct rule (opi_reconcile.R) to the committed K-12
# history, in place, so past weeks are counted the way the pipeline counts
# from 2026-11-03 on: OPI postings at a district we scrape are not counted
# (unless that district's scrape returned nothing that week), and counted OPI
# postings carry their district label (registry district, OPI-only map
# entity, or OPI's employer name).
#
# Per week, the rule is decided from that week's raw archive
# (Archivek12_Data/combined_*.csv; by town for weeks before OPI_District),
# then applied to the accumulated files by (Archive_Date, Posting_ID):
#   k12jobanalysis.csv           rows dropped / District relabeled
#   k12_district_weekly_totals   counts moved: minus each OPI row's old label,
#                                plus its new label when it still counts
#   allsum.csv / allnow.csv      recomputed from k12jobanalysis.csv (the same
#                                summarize_k12_posting_counts() the pipeline
#                                uses; verified identical before this change)
#   combinedclean.csv            latest week: dropped / relabeled, plus
#                                Also_On_OPI on the direct rows OPI also lists
# Every other column is left as committed. Raw archives are not modified.
# Rerunnable: once k12jobanalysis.csv has nothing left to drop, history is
# taken as reconciled and the weekly totals (adjusted by difference, so not
# safe to apply twice) are left alone; Also_On_OPI is recomputed either way.
# Afterwards run scripts/generate_job_duration_spells.R.
#
# Usage (repo root): Rscript scripts/reconcile_opi_history.R [--dry-run]

suppressMessages(library(dplyr))
source("k12_he_classification.R")
source("opi_reconcile.R")

dry_run <- "--dry-run" %in% commandArgs(trailingOnly = TRUE)
app <- "Mt_Ed_Jobs"
crosswalk <- read.csv(file.path(app, "mt_district_crosswalk.csv"), stringsAsFactors = FALSE,
                      colClasses = c(LEAID = "character"))
registry <- read.csv("k12_district_registry.csv", stringsAsFactors = FALSE)

read_archive_week <- function(path) {
  read.csv(path, colClasses = c(Archive_Date = "character"), stringsAsFactors = FALSE) %>%
    select(-any_of("X")) %>%
    mutate(Archive_Date = as.character(as.Date(Archive_Date, tryFormats = c("%Y-%m-%d", "%m/%d/%Y")))) %>%
    mutate(across(any_of(c("title", "position", "location", "url", "District", "Posting_Source")),
                  normalize_posting_text)) %>%
    add_k12_posting_identity() %>%
    distinct(Posting_ID, .keep_all = TRUE)
}

# One row per OPI posting per archived week: old label (as combinedclean
# carried it), Counted, new label.
rules <- bind_rows(lapply(list.files("Archivek12_Data", pattern = "^combined_.*\\.csv$", full.names = TRUE), function(f) {
  week <- read_archive_week(f)
  r <- opi_rule_for_archive(week, crosswalk, registry)
  data.frame(Archive_Date = week$Archive_Date, Posting_ID = r$Posting_ID,
             Placeholder = is_placeholder_posting(week$title),
             Old_District = canonicalize_k12_district(week$District),
             Counted = r$Counted, New_District = canonicalize_k12_district(r$District),
             stringsAsFactors = FALSE)[r$Is_OPI, , drop = FALSE]
}))
key <- function(d, id) paste(d, id)
rules$key <- key(rules$Archive_Date, rules$Posting_ID)

cat("OPI postings per week (archive): counted / not counted\n")
print(rules %>% group_by(Archive_Date) %>% summarize(counted = sum(Counted), not_counted = sum(!Counted), .groups = "drop"),
      n = Inf)

# ---- k12jobanalysis.csv ----
k12 <- read.csv(file.path(app, "k12jobanalysis.csv"), stringsAsFactors = FALSE)
k12_key <- key(k12$Archive_Date, k12$Posting_ID)
hit <- match(k12_key, rules$key)
drop_k12 <- !is.na(hit) & !rules$Counted[hit]
relabel_k12 <- !is.na(hit) & rules$Counted[hit]
cat(sprintf("\nk12jobanalysis.csv: %d rows, %d dropped, %d OPI rows relabeled (%d label changes)\n",
            nrow(k12), sum(drop_k12), sum(relabel_k12),
            sum(relabel_k12 & k12$District != rules$New_District[hit], na.rm = TRUE)))
k12$District[relabel_k12] <- rules$New_District[hit[relabel_k12]]
k12 <- k12[!drop_k12, , drop = FALSE]

# ---- allsum.csv / allnow.csv ----
k12sumdistrict <- summarize_k12_posting_counts(k12)
k12sum <- k12sumdistrict %>%
  group_by(Broad_Category, Archive_Date) %>%
  summarize(sum = sum(sum), .groups = "drop") %>%
  mutate(District = "Total") %>%
  select(Broad_Category, Archive_Date, District, sum)
allsum <- bind_rows(k12sum, k12sumdistrict)
latest <- k12sumdistrict %>% filter(Archive_Date == max(Archive_Date))
allnow <- bind_rows(
  latest %>% group_by(Broad_Category) %>% summarize(Sum = sum(sum), .groups = "drop") %>% mutate(District = "Total"),
  latest %>% ungroup() %>% transmute(Broad_Category, Sum = sum, District)
)

# ---- k12_district_weekly_totals.csv ----
totals <- read.csv(file.path(app, "k12_district_weekly_totals.csv"), stringsAsFactors = FALSE)
already_reconciled <- sum(drop_k12) == 0
if (already_reconciled) cat("History already reconciled (nothing to drop): weekly totals left as they are.\n")
moves <- if (already_reconciled) rules[0, ] else rules %>% filter(!Placeholder, !(Counted & Old_District == New_District))
minus <- moves %>% count(District = Old_District, Archive_Date, name = "minus")
plus <- moves %>% filter(Counted) %>% count(District = New_District, Archive_Date, name = "plus")
totals_new <- totals %>%
  full_join(minus, by = c("District", "Archive_Date")) %>%
  full_join(plus, by = c("District", "Archive_Date")) %>%
  mutate(n = coalesce(n, 0L) - coalesce(minus, 0L) + coalesce(plus, 0L))
if (any(totals_new$n < 0)) {
  print(totals_new[totals_new$n < 0, ])
  stop("A weekly total would go negative: the archive and k12_district_weekly_totals.csv disagree. Nothing written.")
}
totals_new <- totals_new %>% filter(n > 0) %>% select(District, Archive_Date, n) %>% arrange(Archive_Date, District)
cat(sprintf("k12_district_weekly_totals.csv: total postings by week, before -> after\n"))
print(full_join(totals %>% group_by(Archive_Date) %>% summarize(before = sum(n)),
                totals_new %>% group_by(Archive_Date) %>% summarize(after = sum(n)), by = "Archive_Date"), n = Inf)

# ---- combinedclean.csv (latest week) ----
cc <- read.csv(file.path(app, "combinedclean.csv"), stringsAsFactors = FALSE)
cc_hit <- match(key(cc$Archive_Date, cc$Posting_ID), rules$key)
drop_cc <- !is.na(cc_hit) & !rules$Counted[cc_hit]
relabel_cc <- !is.na(cc_hit) & rules$Counted[cc_hit]
cc$District[relabel_cc] <- rules$New_District[cc_hit[relabel_cc]]
# Also_On_OPI: rerun the week's match on its direct rows.
latest_file <- file.path("Archivek12_Data", paste0("combined_", max(cc$Archive_Date), ".csv"))
if (!"Also_On_OPI" %in% names(cc)) cc$Also_On_OPI <- FALSE
if (file.exists(latest_file)) {
  week <- read_archive_week(latest_file)
  is_opi <- is_opi_statewide_posting(week$url) | grepl("^OPI ", week$Posting_Source)
  direct <- week[!is_opi, , drop = FALSE]
  direct$District <- canonicalize_k12_district(direct$District)
  r <- reconcile_opi_with_direct(week[is_opi, , drop = FALSE], direct, crosswalk, registry,
                                 today = as.Date(max(cc$Archive_Date)), stale_fallback = FALSE)
  also <- r$direct_df$Posting_ID[r$direct_df$Also_On_OPI]
  cc$Also_On_OPI <- cc$Posting_ID %in% also
}
cc <- cc[!drop_cc, , drop = FALSE]
cols <- names(cc)
cols <- append(setdiff(cols, "Also_On_OPI"), "Also_On_OPI", after = match("OPI_District", setdiff(cols, "Also_On_OPI")))
cc <- cc[, cols]
cat(sprintf("combinedclean.csv: %d OPI rows dropped, %d relabeled, %d direct rows flagged Also_On_OPI; %d rows remain\n",
            sum(drop_cc), sum(relabel_cc), sum(cc$Also_On_OPI), nrow(cc)))

if (dry_run) {
  cat("\n--dry-run: nothing written.\n")
} else {
  write.csv(k12, file.path(app, "k12jobanalysis.csv"), row.names = FALSE)
  write.csv(allsum, file.path(app, "allsum.csv"), row.names = FALSE)
  write.csv(allnow, file.path(app, "allnow.csv"), row.names = FALSE)
  write.csv(totals_new, file.path(app, "k12_district_weekly_totals.csv"), row.names = FALSE)
  write.csv(cc, file.path(app, "combinedclean.csv"), row.names = FALSE)
  cat("\nWritten. Next: Rscript scripts/generate_job_duration_spells.R\n")
}
