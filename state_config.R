# Montana's state configuration for the edjobs package (state_config(), since
# edjobs 0.7.0, phase 4). What package code needs to know about this state, as
# data. Sourced by the pipeline's setup chunk, tests/testthat/helper-setup.R
# and .github/scripts/check_salary_drift.R; set before anything refreshes or
# checks one of MT's own reference tables.
library(edjobs)

set_state_config(state_config(
  state = "Montana", fips = "30", app_dir = "Mt_Ed_Jobs",
  feed = list(short_name = "OPI", label = "OPI Jobs for Teachers (statewide)",
              url = "https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx",
              discrepancy_file = "mt_discrepancy_report.csv"),
  # The first archive that counts toward the drift check's per-source
  # baselines: earlier runs predate fixes that changed the counts.
  drift_baseline_from = "2026-08-06",
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
