#!/usr/bin/env Rscript
# scripts/build_posting_spells.R
#
# Rebuilds the posting-level spells (posting_spells.R) from the raw archives,
# coverage_calendar.csv and schoolspring_endings.csv, and writes
#   posting_spells_k12.csv     one row per K-12 posting: start, end, how it ended
#   posting_durations_k12.csv  Kaplan-Meier median days listed, all and by
#                              position (only with >= 20 endings)
#   posting_spells_he.csv      the same for higher ed (Archived_HE_Data)
#   posting_durations_he.csv   all, by HE job type and by institution (MSU is
#                              over half the HE postings)
# at the repo root. Research tables only: the dashboard's Listing Duration tabs
# stay paused (2026-11-02 spells trust audit) until enough clean history exists.
# Rerunnable from scratch any time; the weekly workflow runs it after the
# pipeline (non-blocking).

suppressPackageStartupMessages({ library(dplyr); library(readxl) })
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

# Higher ed: each institution is its own source in the calendar's HE rows.
he_calendar <- if (is.null(calendar)) NULL else calendar[calendar$Segment == "HE", , drop = FALSE]
he_panel <- use_earliest_posted_date(bridge_posting_ids(he_posting_panel("Archived_HE_Data")))
he_spells <- build_posting_spells(he_panel, he_calendar, shared_titles = "fallback only")
he_durations <- bind_rows(summarize_posting_durations(he_spells),
                          summarize_posting_durations(he_spells[he_spells$District != "Montana State University", ]) %>%
                            mutate(Group = "All except Montana State University"),
                          summarize_posting_durations(he_spells, "Position"),
                          summarize_posting_durations(he_spells, "District") %>% mutate(Group = paste("Institution:", Group))) %>%
  mutate(As_Of = max(he_spells$Last_Seen))
write.csv(he_spells, "posting_spells_he.csv", row.names = FALSE)
write.csv(he_durations, "posting_durations_he.csv", row.names = FALSE)
cat("posting_spells_he.csv:", nrow(he_spells), "postings,", sum(he_spells$In_Durations), "in durations,",
    sum(he_spells$Event & he_spells$In_Durations), "endings. Median days listed (all):",
    he_durations$Median_Days[he_durations$Group == "All"], "\n")
