# Montana's state configuration for the edjobs package (state_config(), since
# edjobs 0.7.0, phase 4). What package code needs to know about this state, as
# data. Sourced by the pipeline's setup chunk, tests/testthat/helper-setup.R
# and .github/scripts/check_salary_drift.R; set before anything refreshes or
# checks one of MT's own reference tables.
library(edjobs)

# Which function scrapes each registry platform, with which registry columns
# as its arguments (the same call shape Mt_ED_Jobs.Rmd uses);
# edjobs::resolve_scraper_call() reads these for the PR live check,
# scripts/repro_scraper.R and the auto-fix issue. The platforms edjobs scrapes
# (AppliTrack, SchoolSpring, TedK12, Red Rover, the CMS families, Google Doc,
# CyberSchool, Apptegy, PeopleAdmin, NEOGOV) come from
# edjobs::default_scraper_specs() (edjobs 0.46.0); MT_SCRAPER_SPECS adds only
# Montana's own scrapers. `session = TRUE`: the scraper's first argument is a
# chromote session. Platforms with no entry (SharesBoard) have no
# single-source live check. test-drift-check.R asserts
# every function named here exists and every registered row resolves.
MT_SCRAPER_SPECS <- scraper_specs(
  TylerPortico = scraper_spec("fetch_tylerportico_postings", c("Platform_Key", "District")),
  BroadviewHeuristic = scraper_spec("fetch_broadview_postings"),
  # Lima's scraper reads the Thrillshare feed its default names; Job_Link is the district's home page, which the
  # Heuristic fallback below would pass (wrong page for the live check and repro until 2026-11-24).
  LimaHeuristic = scraper_spec("fetch_lima_postings"),
  # Reads its openings-PDF link from the rendered page (2026-11-05).
  CJIHeuristic = scraper_spec("fetch_cji_postings", "Job_Link", session = TRUE),
  JazzHR       = scraper_spec("fetch_jazzhr_postings",       c("Feed_URL", "Institution")),
  # "a:b" in Feed_URL: the two parts (IsolvedHire subdomain:domain_id, ADP cid:ccId); with the institution.
  IsolvedHire  = scraper_spec("fetch_isolvedhire_postings", list(function(row) strsplit(row$Feed_URL, ":")[[1]][1],
                                                                 function(row) strsplit(row$Feed_URL, ":")[[1]][2], "Institution")),
  AdpWorkforceNow = scraper_spec("fetch_adp_workforcenow_postings", list(function(row) strsplit(row$Feed_URL, ":")[[1]][1],
                                                                        function(row) strsplit(row$Feed_URL, ":")[[1]][2], "Institution")),
  Paycom       = scraper_spec("fetch_paycom_postings",       c("Feed_URL", "Institution")),
  MilesCCHeuristic   = scraper_spec("fetch_miles_cc_postings",   "Feed_URL"),
  DawsonCCHeuristic  = scraper_spec("fetch_dawson_cc_postings",  "Feed_URL"),
  # Job pages read by CSS selectors (edjobs 0.87.0): each one's selectors are its row of
  # css_board_rules.csv, keyed by Institution here; the K-12 registry's own spec below reads District.
  CSSBoard           = css_board_spec(function() mt_css_board_rules(), "Feed_URL", "Town", "Institution"),
  AnCollegeHeuristic = scraper_spec("fetch_ancollege_postings",  "Feed_URL"),
  CDKCHeuristic      = scraper_spec("fetch_cdkc_postings",       "Feed_URL")
)
# The direct boards Mt_ED_Jobs.Rmd reads with edjobs::scrape_registry_platforms() (edjobs 0.92.0, 2026-11-24): one
# group per platform, in the order the per-platform blocks it replaced were combined (direct_dfs), so the combined
# rows come out in the same order. A new platform goes here (test-direct-board-platforms.R checks every registry
# platform is either here or read by its own block: the ATS boards, the Apptegy batch, OPI only).
MT_DIRECT_BOARD_PLATFORMS <- list(
  broadview = "BroadviewHeuristic", scobey = "ScobeyHeuristic", smartsites = "SmartSites",
  hysham = "HyshamHeuristic", winnett = "WinnettHeuristic", milescity = "MilesCityHeuristic",
  brockton = "BrocktonHeuristic", googledoc = "GoogleDoc", clinton = "ClintonHeuristic", miami = "MiamiHeuristic",
  zurich = "ZurichHeuristic", wibaux = "WibauxHeuristic", westvalley = "WestValleyHeuristic",
  cssboard_k12 = "CSSBoard", cyberschool = c("CyberSchool", "CyberSchoolText"), googlesites = "GoogleSites",
  finalsite = "Finalsite", wordpress = "WordPress", edlio = "Edlio", joomla = "Joomla",
  smithvalley = "SmithValleyHeuristic", moore = "MooreHeuristic", boulder = "BoulderHeuristic",
  jeffersonhigh = "JeffersonHighHeuristic", judithgap = "JudithGapHeuristic", whitewater = "WhitewaterHeuristic",
  monforton = "MonfortonHeuristic", grassrange = "GrassRangeHeuristic", heartbutte = "HeartButteHeuristic",
  eastglacier = "EastGlacierHeuristic", charlo = "CharloHeuristic", jordan = "JordanHeuristic",
  pioneer = "PioneerHeuristic", opheim = "OpheimHeuristic", pryor = "PryorHeuristic",
  westglacier = "WestGlacierHeuristic", kila = "KilaHeuristic", pleasantvalley = "PleasantValleyHeuristic",
  circle = "CircleHeuristic", bigfork = "BigforkHeuristic", terry = "TerryHeuristic", cji = "CJIHeuristic",
  marion = "MarionHeuristic", lima = "LimaHeuristic", gallatingateway = "GallatinGatewayHeuristic"
)
# The college boards Mt_ED_Jobs.Rmd reads with edjobs::scrape_registry_platforms() (0.94.0, 2026-11-24), in the
# order the per-platform blocks they replaced were combined (he_dfs; Interfolio, UM's faculty board, isn't a
# registry loop and is read in the Rmd after NEOGOV). Miles/Dawson CC, AnCollege and CDKC are heuristic
# scrapers (misc_college_scrapers.R; CDKC's is expected to return nothing most weeks). Stone Child runs Apptegy.
# University of Providence runs ADP Workforce Now and packs "cid:ccId" in Feed_URL; isolved Hire boards pack
# "subdomain:domain_id" there (domain_id is per-institution and not derivable from the subdomain).
MT_HE_PLATFORMS <- list(
  peopleadmin = "PeopleAdmin", jazzhr = "JazzHR", paycom = "Paycom", milescc = "MilesCCHeuristic",
  dawsoncc = "DawsonCCHeuristic", isolvedhire = "IsolvedHire", neogov = "Neogov", cssboard = "CSSBoard",
  adp = "AdpWorkforceNow", stonechild = "Apptegy", ancollege = "AnCollegeHeuristic", cdkc = "CDKCHeuristic"
)
# The bespoke Apptegy-session districts (Shelby, Geyser: registry Platform
# "ApptegyBespoke") are dispatched through misc_district_scrapers.R's
# APPTEGY_DISTRICT_SCRAPERS map, keyed by district.
APPTEGY_DISPATCH_FN <- "APPTEGY_DISTRICT_SCRAPERS"
MT_APPTEGY_MAP_SPEC <- scraper_spec(APPTEGY_DISPATCH_FN, "District", session = TRUE, map = TRUE,
                                    defined_in = "misc_district_scrapers.R")
# The registries sit at the repository root; tests run from tests/testthat.
mt_registry <- function(file) function() {
  utils::read.csv(if (file.exists(file)) file else here::here(file), stringsAsFactors = FALSE)
}
# The CSS-board rules (css_board_rules.csv, edjobs css_board_rules()), read when a source is looked up.
mt_css_board_rules <- function() {
  file <- "css_board_rules.csv"
  css_board_rules(if (file.exists(file)) file else here::here(file))
}

set_state_config(state_config(
  state = "Montana", fips = "30", app_dir = "Mt_Ed_Jobs",
  feed = list(short_name = "OPI", label = "OPI Jobs for Teachers (statewide)",
              url = "https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx",
              discrepancy_file = "mt_discrepancy_report.csv",
              # The pre-flight canary (edjobs 0.52.0): words the page must show; apps.opi.mt.gov needs the GoDaddy R1
              # bundle (opi_ca_bundle(), direct_api_scrapers.R).
              signature = c("TeacherSearch", "Montana"), cainfo = "certs/opi_godaddy_r1.pem"),
  # How the weekly checks name a K-12 row's source (edjobs 0.51.0): OPI's rows are one source; archives from
  # before Posting_Source (2026-08-18) can't be split that way and are left out. Floor 2 (Mike, 2026-11-13).
  k12_source_names = function(df) if (!"Posting_Source" %in% names(df)) NULL else collapse_statewide_feed_names(df),
  drift_min_mean = 2,
  # The first archive that counts toward the drift check's per-source
  # baselines: earlier runs predate fixes that changed the counts.
  drift_baseline_from = "2026-08-06",
  # The boards' own time zone: the day a presence check counts for, a JSON-LD date's local day (edjobs 0.44.0).
  timezone = "America/Denver",
  # Census names counties "Gallatin County, Montana"; Montana's files say "Gallatin County" (edjobs 0.47.0,
  # refresh_county_context()).
  county_suffix = ", Montana",
  # The weekly salary check (edjobs 0.57.0): each source's coverage against last run's committed file. Value bounds are
  # generous (DLI 2022-23 teacher averages $52k-$67k; IPEDS faculty $25.6k at Blackfeet CC to $99k; OPI general fund
  # $2.1M Big Sandy to $134.2M Billings): they catch a misread digit, not real variation. DLI has published one
  # edition only, so there's no K-12 year-over-year pair.
  salary_checks = salary_checks(
    coverage = data.frame(
      name = c("K-12 teacher avg salary (MT DLI)", "K-12 teacher FTE (CCD)", "K-12 General Fund expenditure (OPI Finance)",
               "HE avg faculty salary (IPEDS)", "HE fall enrollment FTE (IPEDS)", "HE 5-year enrollment trend (IPEDS)",
               "HE Pell Grant recipient share (FSA)"),
      file = rep(c("salarymap2.csv", "salarymap.csv"), c(3, 4)),
      column = c("Teacher_Avg_Salary", "Teachers_Total_FTE", "Total_General_Fund_Expenditure", "Faculty_Avg_Salary",
                 "Enrollment", "Enrollment_Change_Pct", "Pell_Recipient_Share")),
    # The general fund is checked per enrolled student (edjobs 0.58.0, Mike 2026-11-20): since the 11-10 registry growth
    # the $500k floor flagged 13 real districts of 4-46 students every week ($7k-$27k a student; statewide $6.3k-$30.4k
    # on 11-19), while a misread digit gives ~$950 or ~$96k a student at any size. The dollar range is kept only for
    # rows with no CCD enrollment. claude-notes/2026-11-20_mt-general-fund-bound.md.
    bounds = data.frame(
      name = c("K-12 teacher avg salary (MT DLI)", "K-12 teacher 10th pctile salary (MT DLI)",
               "K-12 teacher 90th pctile salary (MT DLI)", "K-12 General Fund expenditure per student (OPI Finance / CCD)",
               "K-12 General Fund expenditure (OPI Finance; no CCD enrollment)", "HE avg faculty salary (IPEDS)"),
      file = rep(c("salarymap2.csv", "salarymap.csv"), c(5, 1)),
      column = c("Teacher_Avg_Salary", "Teacher_Salary_10th_Pctile", "Teacher_Salary_90th_Pctile",
                 "Total_General_Fund_Expenditure", "Total_General_Fund_Expenditure", "Faculty_Avg_Salary"),
      per = c(NA, NA, NA, "Enrollment", NA, NA), unless = c(NA, NA, NA, NA, "Enrollment", NA),
      min_ok = c(25000, 20000, 25000, 3000, 500000, 15000), max_ok = c(150000, 150000, 175000, 60000, 250000000, 150000)),
    yoy = data.frame(file = "salarymap.csv", current = "Faculty_Avg_Salary", prior = "Faculty_Avg_Salary_Y1Ago")),
  scraper_sources = list(
    scraper_registry(mt_registry("k12_district_registry.csv"), "District", "k12_district_registry.csv",
      # CSSBoard districts (Swan Valley, Richey, Rapelje since 2026-11-24): the page, City and rule keyed by District.
      specs = scraper_specs(ApptegyBespoke = MT_APPTEGY_MAP_SPEC,
                            CSSBoard = css_board_spec(function() mt_css_board_rules(), "Job_Link", "City", "District"),
                            defaults = MT_SCRAPER_SPECS),
      # Every other K-12 "<Name>Heuristic" platform is fetch_<lowercase name>_postings(Job_Link).
      fallback = function(platform, row) {
        if (grepl("Heuristic$", platform)) {
          scraper_spec(paste0("fetch_", tolower(sub("Heuristic$", "", platform)), "_postings"), "Job_Link")
        }
      }),
    scraper_registry(mt_registry("he_institution_registry.csv"), "Institution", "he_institution_registry.csv",
      # The one HE Apptegy site (Stone Child College), in place of the K-12 family routine.
      specs = scraper_specs(Apptegy = scraper_spec("fetch_stonechild_postings", "Feed_URL", session = TRUE),
                            defaults = MT_SCRAPER_SPECS)),
    # Private schools whose own board is read but which have no registry row (no NCES LEAID): one board, three
    # schools (fetch_st_labre_postings(), direct_api_scrapers.R).
    scraper_calls(stats::setNames(rep(list(list(fn = "fetch_st_labre_postings", args = list(),
                                                platform = "trakstar", url = "https://stlabre.hire.trakstar.com/")), 3),
                                  c("St Labre Indian H S", "St Charles Mission School", "Pretty Eagle Catholic Academy")),
                  "fetch_st_labre_postings() in direct_api_scrapers.R (St. Labre's Trakstar board)")
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
