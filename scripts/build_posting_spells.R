#!/usr/bin/env Rscript
# scripts/build_posting_spells.R
#
# Rebuilds the posting-level K-12 spells (posting_spells.R) from the raw
# archives, coverage_calendar.csv and schoolspring_endings.csv, and writes
#   posting_spells_k12.csv     one row per posting: start, end, how it ended
#   posting_durations_k12.csv  Kaplan-Meier median days listed, all and by
#                              position (only with >= 20 endings)
# at the repo root. Research tables only: the dashboard's Listing Duration tabs
# stay paused (2026-11-02 spells trust audit) until enough clean history exists.
# Rerunnable from scratch any time; the weekly workflow runs it after the
# pipeline (non-blocking).

suppressPackageStartupMessages(library(dplyr))
source("k12_he_classification.R")
source("opi_reconcile.R")
source("posting_spells.R")

crosswalk <- read.csv(file.path("Mt_Ed_Jobs", "mt_district_crosswalk.csv"), stringsAsFactors = FALSE,
                      colClasses = c(LEAID = "character"))
registry <- read.csv("k12_district_registry.csv", stringsAsFactors = FALSE)
calendar <- if (file.exists("coverage_calendar.csv")) read.csv("coverage_calendar.csv", colClasses = "character") else NULL
endings <- if (file.exists("schoolspring_endings.csv")) read.csv("schoolspring_endings.csv", colClasses = "character") else NULL

panel <- bridge_posting_ids(k12_posting_panel("Archivek12_Data", crosswalk, registry))
spells <- build_posting_spells(panel, calendar, endings)
durations <- bind_rows(summarize_posting_durations(spells),
                       summarize_posting_durations(spells, "Position")) %>%
  mutate(As_Of = max(spells$Last_Seen))

write.csv(spells, "posting_spells_k12.csv", row.names = FALSE)
write.csv(durations, "posting_durations_k12.csv", row.names = FALSE)
cat("posting_spells_k12.csv:", nrow(spells), "postings,", sum(spells$In_Durations), "in durations,",
    sum(spells$Event & spells$In_Durations), "endings. Median days listed (all):",
    durations$Median_Days[durations$Group == "All"], "\n")
