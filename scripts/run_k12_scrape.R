# Proves the K-12 pipeline end-to-end across every platform built so far
# (AppliTrack, SchoolSpring, Tyler Portico): reads the district registry,
# scrapes each district live via safe_scrape(), classifies the results, and
# prints a summary. Not the final pipeline entry point (that will be
# Mt_ED_Jobs.Rmd, mirroring Wyoming's Wy_ED_Jobs.Rmd) -- this is a standalone
# check that every ported scraper actually works against real Montana job
# boards before the full pipeline gets built on top of them.
#
# AppliTrack returns different column name casing (title/position/location)
# than SchoolSpring/Tyler Portico (Title/Location/Link) -- the same
# inconsistency Wyoming's own per-platform parsers have, reconciled only at
# the real pipeline entry point when combinedclean.csv gets built. Kept
# separate here rather than force-merged, since reconciling column schemas
# is pipeline-entry-point work, not this script's job.

suppressMessages({
  library(dplyr)
  library(here)
})

source(here::here("scrape_helpers.R"))
source(here::here("direct_api_scrapers.R"))
source(here::here("k12_he_classification.R"))

registry <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)

# --- AppliTrack -------------------------------------------------------------

applitrack_districts <- registry[registry$Platform == "AppliTrack", ]
applitrack_expected_cols <- c("title", "position", "position2", "date_posted", "location", "closing_date")

applitrack_results <- lapply(seq_len(nrow(applitrack_districts)), function(i) {
  row <- applitrack_districts[i, ]
  message("Scraping ", row$District, " (AppliTrack: ", row$Slug, ")...")
  df <- safe_scrape(
    source_name = row$District,
    scrape_fn = function() fetch_applitrack_postings(row$Slug),
    expected_cols = applitrack_expected_cols
  )
  if (nrow(df) > 0) {
    df$District <- row$District
    df$title <- fix_title_encoding(df$title)
  }
  df
})
applitrack_combined <- do.call(rbind, applitrack_results)

# --- SchoolSpring -------------------------------------------------------------

schoolspring_districts <- registry[registry$Platform == "SchoolSpring", ]
schoolspring_expected_cols <- c("Title", "Location", "Posted_Date", "Link")

schoolspring_results <- lapply(seq_len(nrow(schoolspring_districts)), function(i) {
  row <- schoolspring_districts[i, ]
  message("Scraping ", row$District, " (SchoolSpring: ", row$Slug, ")...")
  df <- safe_scrape(
    source_name = row$District,
    scrape_fn = function() fetch_schoolspring_postings(row$Slug),
    expected_cols = schoolspring_expected_cols
  )
  if (nrow(df) > 0) df$District <- row$District
  df
})
schoolspring_combined <- do.call(rbind, schoolspring_results)

# --- Tyler Portico -----------------------------------------------------------

tylerportico_districts <- registry[registry$Platform == "TylerPortico", ]
tylerportico_expected_cols <- c("Title", "Location", "Posted_Date", "Link")

tylerportico_results <- lapply(seq_len(nrow(tylerportico_districts)), function(i) {
  row <- tylerportico_districts[i, ]
  message("Scraping ", row$District, " (Tyler Portico: ", row$Slug, ")...")
  df <- safe_scrape(
    source_name = row$District,
    scrape_fn = function() fetch_tylerportico_postings(row$Slug, row$District),
    expected_cols = tylerportico_expected_cols
  )
  if (nrow(df) > 0) df$District <- row$District
  df
})
tylerportico_combined <- do.call(rbind, tylerportico_results)

# --- Summary -------------------------------------------------------------

cat("\n=== Summary ===\n")
cat("AppliTrack districts scraped:", nrow(applitrack_districts),
    "| postings found:", nrow(applitrack_combined), "\n")
cat("SchoolSpring districts scraped:", nrow(schoolspring_districts),
    "| postings found:", nrow(schoolspring_combined), "\n")
cat("Tyler Portico districts scraped:", nrow(tylerportico_districts),
    "| postings found:", nrow(tylerportico_combined), "\n")
cat("Total K-12 postings found:",
    nrow(applitrack_combined) + nrow(schoolspring_combined) + nrow(tylerportico_combined), "\n\n")

if (nrow(applitrack_combined) > 0) {
  cat("--- AppliTrack by district ---\n")
  print(applitrack_combined %>% count(District, name = "n_postings") %>% arrange(desc(n_postings)))
}
if (nrow(schoolspring_combined) > 0) {
  cat("\n--- SchoolSpring by district ---\n")
  print(schoolspring_combined %>% count(District, name = "n_postings") %>% arrange(desc(n_postings)))
}
if (nrow(tylerportico_combined) > 0) {
  cat("\n--- Tyler Portico by district ---\n")
  print(tylerportico_combined %>% count(District, name = "n_postings") %>% arrange(desc(n_postings)))
}

if (nrow(applitrack_combined) > 0) {
  applitrack_combined$position_bucket <- classify_k12_position(applitrack_combined$title)
  cat("\n=== AppliTrack position buckets ===\n")
  print(applitrack_combined %>% count(position_bucket, sort = TRUE))
}
if (nrow(schoolspring_combined) > 0) {
  schoolspring_combined$position_bucket <- classify_k12_position(schoolspring_combined$Title)
  cat("\n=== SchoolSpring position buckets ===\n")
  print(schoolspring_combined %>% count(position_bucket, sort = TRUE))
}
if (nrow(tylerportico_combined) > 0) {
  tylerportico_combined$position_bucket <- classify_k12_position(tylerportico_combined$Title)
  cat("\n=== Tyler Portico position buckets ===\n")
  print(tylerportico_combined %>% count(position_bucket, sort = TRUE))
}

cat("\nSee scrape_log.csv for per-district ok/empty/error status.\n")
