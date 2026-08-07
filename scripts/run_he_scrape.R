# Proves the Higher Ed pipeline end-to-end across every platform built so
# far (PeopleAdmin, JazzHR): reads the HE institution registry, scrapes
# every institution live via safe_scrape(), classifies the results, and
# prints a summary. Standalone check (not the final pipeline entry point),
# mirroring scripts/run_k12_scrape.R for the K-12 side. Was
# run_he_peopleadmin_scrape.R until JazzHR needed the same treatment K-12's
# runner already got -- renamed rather than adding a second single-platform
# script per platform.

suppressMessages({
  library(dplyr)
  library(here)
})

source(here::here("scrape_helpers.R"))
source(here::here("direct_api_scrapers.R"))
source(here::here("k12_he_classification.R"))

registry <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
expected_cols <- c("Title", "Location", "Posted_Date", "Link")

# --- PeopleAdmin -------------------------------------------------------------

peopleadmin_institutions <- registry[registry$Platform == "PeopleAdmin", ]

peopleadmin_results <- lapply(seq_len(nrow(peopleadmin_institutions)), function(i) {
  row <- peopleadmin_institutions[i, ]
  message("Scraping ", row$Institution, " (PeopleAdmin: ", row$Feed_URL, ")...")
  df <- safe_scrape(
    source_name = row$Institution,
    scrape_fn = function() fetch_peopleadmin_atom(row$Feed_URL, location_fallback = row$Institution),
    expected_cols = expected_cols
  )
  if (nrow(df) > 0) df$Institution <- row$Institution
  df
})
peopleadmin_combined <- do.call(rbind, peopleadmin_results)

# --- JazzHR --------------------------------------------------------------

# Feed_URL holds the applytojob.com subdomain here (fetch_jazzhr_postings()
# builds the full URL itself), unlike PeopleAdmin's row above where it's
# already a complete feed URL -- the same per-platform meaning difference
# k12_district_registry.csv's Slug column already has (tenant path vs.
# domain name vs. full URL depending on platform).
jazzhr_institutions <- registry[registry$Platform == "JazzHR", ]

jazzhr_results <- lapply(seq_len(nrow(jazzhr_institutions)), function(i) {
  row <- jazzhr_institutions[i, ]
  message("Scraping ", row$Institution, " (JazzHR: ", row$Feed_URL, ")...")
  df <- safe_scrape(
    source_name = row$Institution,
    scrape_fn = function() fetch_jazzhr_postings(row$Feed_URL, row$Institution),
    expected_cols = expected_cols
  )
  if (nrow(df) > 0) df$Institution <- row$Institution
  df
})
jazzhr_combined <- do.call(rbind, jazzhr_results)

# --- Summary -------------------------------------------------------------

combined <- dplyr::bind_rows(peopleadmin_combined, jazzhr_combined)

cat("\n=== Summary ===\n")
cat("PeopleAdmin institutions scraped:", nrow(peopleadmin_institutions),
    "| postings found:", nrow(peopleadmin_combined), "\n")
cat("JazzHR institutions scraped:", nrow(jazzhr_institutions),
    "| postings found:", nrow(jazzhr_combined), "\n")
cat("Total HE postings found:", nrow(combined), "\n\n")

if (nrow(combined) > 0) {
  print(combined %>% count(Institution, name = "n_postings") %>% arrange(desc(n_postings)))

  combined$Job_Type <- classify_he_job_type(combined$Title)
  cat("\n=== Job type buckets ===\n")
  print(combined %>% count(Job_Type, sort = TRUE))

  cat("\n=== Sample Locations (proves department-based extraction worked) ===\n")
  print(head(unique(combined$Location), 10))
}

cat("\nSee scrape_log.csv for per-institution ok/empty/error status.\n")
