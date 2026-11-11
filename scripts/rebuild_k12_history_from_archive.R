# Disaster-recovery / verification tool: rebuilds the K-12 accumulated
# datasets (combinedclean.csv, k12jobanalysis.csv, allsum.csv, allnow.csv,
# k12_district_weekly_totals.csv)
# from scratch by reprocessing every raw snapshot in Archivek12_Data/, the
# same way the weekly pipeline used to do on every single run before
# history_accumulator.R's incremental-append path replaced that. Ported
# from the Wyoming Education Jobs Dashboard's own
# scripts/rebuild_k12_history_from_archive.R.
#
# Two real uses:
#   1. Disaster recovery -- if a shipped accumulated CSV is ever lost or
#      believed corrupted, this rebuilds it from the durable raw archive
#      (which the weekly pipeline still writes every run, unchanged).
#   2. Ground truth for tests/testthat/test-history-accumulator.R, which
#      checks that incrementally appending one new week onto an existing
#      accumulated file reproduces exactly what a full from-scratch
#      rebuild through that same week would produce.
#
# Run directly (Rscript scripts/rebuild_k12_history_from_archive.R) to
# actually rebuild and overwrite the files on disk. It derives current
# Posting_ID/provenance fields deterministically from each archived row (OPI
# is recognized by its known shared listing URL); source() it from
# elsewhere (as the tests do) to get rebuild_k12_history_from_archive()
# without triggering that.

suppressMessages(library(dplyr))

rebuild_k12_history_from_archive <- function(archive_dir = "Archivek12_Data",
                                             crosswalk_path = here::here("Mt_Ed_Jobs", "mt_district_crosswalk.csv"),
                                             registry_path = here::here("k12_district_registry.csv"),
                                             reference_dir = here::here("Mt_Ed_Jobs")) {
  csv_files <- list.files(archive_dir, pattern = "^combined_.*\\.csv$", full.names = TRUE)
  if (length(csv_files) == 0) {
    stop("rebuild_k12_history_from_archive(): no archive files found in ", archive_dir)
  }
  crosswalk <- read.csv(crosswalk_path, stringsAsFactors = FALSE, colClasses = c(LEAID = "character"))
  registry <- read.csv(registry_path, stringsAsFactors = FALSE)

  # Each week under the OPI rule on its own (read_counted_archive_week(),
  # opi_reconcile.R): bind_rows() first gave old weeks an all-NA OPI_Counted
  # column, which skipped their reconciliation (old OPI rows kept their raw
  # town as District and were all counted). Columns are bound as character,
  # since a column can be all-NA logical in one week and text in another.
  counted <- csv_files %>%
    lapply(function(f) {
      w <- read_counted_archive_week(f, crosswalk, registry)
      w[] <- lapply(w, function(x) if (is.logical(x) && all(is.na(x))) as.character(x) else x)
      w
    }) %>%
    bind_rows() %>%
    mutate(Archive_Date = as.Date(Archive_Date))

  # Pay columns and Also_On_OPI back to the types the pipeline writes.
  for (col in intersect(c("Pay_Min", "Pay_Max"), names(counted))) counted[[col]] <- suppressWarnings(as.numeric(counted[[col]]))
  if ("Also_On_OPI" %in% names(counted)) counted$Also_On_OPI <- as.logical(counted$Also_On_OPI)

  oews_wages <- read.csv(file.path(reference_dir, "oews_role_wages.csv"), stringsAsFactors = FALSE,
                         colClasses = c(Area_Code = "character", SOC = "character", Year = "character"))
  district_county <- registry[, c("District", "County")]
  opi_counties <- read.csv(file.path(reference_dir, "opi_district_counties.csv"), stringsAsFactors = FALSE)
  combinedclean <- build_k12_combinedclean(counted, oews_wages, district_county, opi_counties, "MT")
  k12jobs <- build_k12_teacher_rows(combinedclean)

  k12_district_weekly_totals <- combinedclean %>%
    group_by(District, Archive_Date) %>%
    summarize(n = n_distinct(Posting_ID), .groups = "drop")

  k12sumdistrict <- summarize_k12_posting_counts(k12jobs)

  k12sum <- k12sumdistrict %>%
    group_by(Broad_Category, Archive_Date) %>%
    summarize(sum = sum(sum), .groups = "drop") %>%
    mutate(District = "Total") %>%
    select(Broad_Category, Archive_Date, District, sum)

  allsum <- bind_rows(k12sum, k12sumdistrict)
  latest_k12sumdistrict <- k12sumdistrict %>%
    filter(Archive_Date == max(Archive_Date))
  allnow <- bind_rows(
    latest_k12sumdistrict %>%
      group_by(Broad_Category) %>%
      summarize(Sum = sum(sum), .groups = "drop") %>%
      mutate(District = "Total"),
    latest_k12sumdistrict %>%
      transmute(Broad_Category, Sum = sum, District)
  )

  list(
    combinedclean = combinedclean %>% filter(Archive_Date == max(Archive_Date)),
    k12jobs = k12jobs,
    k12_district_weekly_totals = k12_district_weekly_totals,
    allsum = allsum,
    allnow = allnow
  )
}

# Only runs when this file is executed directly (Rscript ...), not when
# source()'d -- source() adds a stack frame, so sys.nframe() > 0 while its
# top-level statements evaluate, whereas a directly Rscript'd file's
# top-level statements run at sys.nframe() == 0.
if (sys.nframe() == 0) {
  source("k12_he_classification.R")
  source("opi_reconcile.R")
  library(edjobs)
  source("history_accumulator.R")
  result <- rebuild_k12_history_from_archive()

  write.csv(result$combinedclean, file.path("Mt_Ed_Jobs", "combinedclean.csv"), row.names = FALSE)
  write.csv(result$k12jobs, file.path("Mt_Ed_Jobs", "k12jobanalysis.csv"), row.names = FALSE)
  write.csv(result$allsum, file.path("Mt_Ed_Jobs", "allsum.csv"), row.names = FALSE)
  write.csv(result$allnow, file.path("Mt_Ed_Jobs", "allnow.csv"), row.names = FALSE)
  write.csv(result$k12_district_weekly_totals, file.path("Mt_Ed_Jobs", "k12_district_weekly_totals.csv"), row.names = FALSE)

  cat("Rebuilt combinedclean.csv (", nrow(result$combinedclean), " rows), k12jobanalysis.csv (",
      nrow(result$k12jobs), " rows), allsum.csv/allnow.csv (",
      nrow(result$allsum), "/", nrow(result$allnow), " rows), k12_district_weekly_totals.csv (",
      nrow(result$k12_district_weekly_totals), " rows) from ",
      length(list.files("Archivek12_Data", pattern = "\\.csv$")), " archive snapshots.\n", sep = "")
}
