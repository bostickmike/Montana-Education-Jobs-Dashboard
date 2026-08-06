# Proves the Higher Ed PeopleAdmin pipeline end-to-end: reads the HE
# institution registry, scrapes every PeopleAdmin institution's Atom feed
# live via safe_scrape(), classifies the results, and prints a summary.
# Standalone check (not the final pipeline entry point), mirroring
# scripts/run_k12_applitrack_scrape.R for the K-12 side.

suppressMessages({
  library(dplyr)
  library(here)
})

source(here::here("scrape_helpers.R"))
source(here::here("direct_api_scrapers.R"))
source(here::here("k12_he_classification.R"))

registry <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
peopleadmin_institutions <- registry[registry$Platform == "PeopleAdmin", ]

expected_cols <- c("Title", "Location", "Posted_Date", "Link")

results <- lapply(seq_len(nrow(peopleadmin_institutions)), function(i) {
  row <- peopleadmin_institutions[i, ]
  message("Scraping ", row$Institution, " (", row$Feed_URL, ")...")
  df <- safe_scrape(
    source_name = row$Institution,
    scrape_fn = function() fetch_peopleadmin_atom(row$Feed_URL, location_fallback = row$Institution),
    expected_cols = expected_cols
  )
  if (nrow(df) > 0) {
    df$Institution <- row$Institution
    df$Archive_Date <- as.character(Sys.Date())
  }
  df
})

combined <- do.call(rbind, results)

cat("\n=== Summary ===\n")
cat("Institutions scraped:", nrow(peopleadmin_institutions), "\n")
cat("Total postings found:", nrow(combined), "\n\n")

if (nrow(combined) > 0) {
  print(combined %>% count(Institution, name = "n_postings") %>% arrange(desc(n_postings)))

  combined$Job_Type <- classify_he_job_type(combined$Title)
  cat("\n=== Job type buckets ===\n")
  print(combined %>% count(Job_Type, sort = TRUE))

  cat("\n=== Sample Locations (proves author-based extraction worked) ===\n")
  print(head(unique(combined$Location), 10))
}

cat("\nSee scrape_log.csv for per-institution ok/empty/error status.\n")
