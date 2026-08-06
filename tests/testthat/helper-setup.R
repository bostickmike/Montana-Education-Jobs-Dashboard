# Auto-sourced by testthat before any test-*.R file runs (test_dir/test_file/
# devtools::test() all pick up helper-*.R automatically). Loads the shared
# classification/canonicalization functions and scrapers under test. Grows
# as more source files are added, mirroring the Wyoming project's own
# helper-setup.R.
suppressMessages(library(here))
suppressMessages(library(dplyr))
source(here::here("k12_he_classification.R"))
source(here::here("scrape_helpers.R"))
source(here::here("direct_api_scrapers.R"))
