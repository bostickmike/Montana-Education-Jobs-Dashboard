# Montana's state configuration for the edjobs package (state_config(), since
# edjobs 0.7.0, phase 4). What package code needs to know about this state, as
# data. Sourced by the pipeline's setup chunk, tests/testthat/helper-setup.R
# and .github/scripts/check_salary_drift.R; set before anything refreshes or
# checks one of MT's own reference tables.
library(edjobs)

# Which function scrapes each registry platform, with which registry columns
# as its arguments (the same call shape Mt_ED_Jobs.Rmd uses);
# edjobs::resolve_scraper_call() reads these for the PR live check,
# scripts/repro_scraper.R and the auto-fix issue. `session = TRUE`: the
# scraper's first argument is a chromote session. Platforms with no entry
# (SharesBoard, split-feed ADP/isolved) have no single-source live check.
# test-drift-check.R asserts every function named here exists and every
# registered row resolves.
MT_SCRAPER_SPECS <- list(
  AppliTrack   = scraper_spec("fetch_applitrack_postings",   "Slug"),
  SchoolSpring = scraper_spec("fetch_schoolspring_postings", "Slug"),
  TylerPortico = scraper_spec("fetch_tylerportico_postings", c("Slug", "District")),
  TedK12       = scraper_spec("fetch_tedk12_postings",       "Slug"),
  BroadviewHeuristic = scraper_spec("fetch_broadview_postings"),
  # Reads its openings-PDF link from the rendered page (2026-11-05).
  CJIHeuristic = scraper_spec("fetch_cji_postings", "Job_Link", session = TRUE),
  PeopleAdmin  = scraper_spec("fetch_peopleadmin_atom",      c("Feed_URL", "Institution")),
  JazzHR       = scraper_spec("fetch_jazzhr_postings",       c("Feed_URL", "Institution")),
  Paycom       = scraper_spec("fetch_paycom_postings",       c("Feed_URL", "Institution")),
  # The agency slug; NEOGOV redirects to the agency's own domain (edjobs 0.11.0).
  Neogov       = scraper_spec("fetch_neogov_postings",       "Feed_URL"),
  MilesCCHeuristic   = scraper_spec("fetch_miles_cc_postings",   "Feed_URL"),
  DawsonCCHeuristic  = scraper_spec("fetch_dawson_cc_postings",  "Feed_URL"),
  CarrollCollegeHeuristic = scraper_spec("fetch_carroll_college_postings", "Feed_URL"),
  RockyMountainCollegeHeuristic = scraper_spec("fetch_rocky_mountain_college_postings", "Feed_URL"),
  SKCHeuristic       = scraper_spec("fetch_skc_postings",        "Feed_URL"),
  LBHCHeuristic      = scraper_spec("fetch_lbhc_postings",       "Feed_URL"),
  FPCCHeuristic      = scraper_spec("fetch_fpcc_postings",       "Feed_URL"),
  AnCollegeHeuristic = scraper_spec("fetch_ancollege_postings",  "Feed_URL"),
  CDKCHeuristic      = scraper_spec("fetch_cdkc_postings",       "Feed_URL")
)
# Every K-12 Apptegy / Red Rover district is dispatched through
# misc_district_scrapers.R's APPTEGY_DISTRICT_SCRAPERS map, keyed by district.
APPTEGY_DISPATCH_FN <- "APPTEGY_DISTRICT_SCRAPERS"
MT_APPTEGY_MAP_SPEC <- scraper_spec(APPTEGY_DISPATCH_FN, "District", session = TRUE, map = TRUE,
                                    defined_in = "misc_district_scrapers.R")
# The registries sit at the repository root; tests run from tests/testthat.
mt_registry <- function(file) function() {
  utils::read.csv(if (file.exists(file)) file else here::here(file), stringsAsFactors = FALSE)
}

set_state_config(state_config(
  state = "Montana", fips = "30", app_dir = "Mt_Ed_Jobs",
  feed = list(short_name = "OPI", label = "OPI Jobs for Teachers (statewide)",
              url = "https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx",
              discrepancy_file = "mt_discrepancy_report.csv"),
  # The first archive that counts toward the drift check's per-source
  # baselines: earlier runs predate fixes that changed the counts.
  drift_baseline_from = "2026-08-06",
  scraper_sources = list(
    scraper_registry(mt_registry("k12_district_registry.csv"), "District", "k12_district_registry.csv",
      specs = c(MT_SCRAPER_SPECS, list(Apptegy = MT_APPTEGY_MAP_SPEC, RedRoverK12 = MT_APPTEGY_MAP_SPEC)),
      # Every other K-12 "<Name>Heuristic" platform is fetch_<lowercase name>_postings(Job_Link).
      fallback = function(platform, row) {
        if (grepl("Heuristic$", platform)) {
          scraper_spec(paste0("fetch_", tolower(sub("Heuristic$", "", platform)), "_postings"), "Job_Link")
        }
      }),
    scraper_registry(mt_registry("he_institution_registry.csv"), "Institution", "he_institution_registry.csv",
      # The one HE Apptegy site (Stone Child College).
      specs = c(MT_SCRAPER_SPECS, list(Apptegy = scraper_spec("fetch_stonechild_postings", "Feed_URL", session = TRUE))))
  ),
  # The auto-fix issue: scraper files read as text; fixture names here don't
  # carry the district, so a source's fixtures are found from its tests.
  autofix = list(scraper_files = c("direct_api_scrapers.R", "misc_district_scrapers.R", "misc_college_scrapers.R"),
                 fixtures_by = "tests"),
  # MT's own reference tables (the shared ones are edjobs::REFERENCE_TABLE_RULES).
  reference_tables = list(
    opi_district_counties = list(name = "OPI district counties", required = c("OPI_District", "County"),
                                 bounds = list(), year_col = NA, max_age = NA),
    # NCES CCD districts -> registry district / OPI-only map entity
    # (opi_reconcile.R). Coordinates must fall inside Montana.
    mt_district_crosswalk = list(name = "MT district crosswalk (CCD)",
                                 required = c("OPI_District", "Map_Entity", "Latitude", "Longitude"),
                                 bounds = list(Latitude = c(44.3, 49.1), Longitude = c(-116.1, -104.0)),
                                 year_col = "CCD_Year", max_age = 4)
  )
))
