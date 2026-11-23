# Montana Education Jobs Dashboard

A live dashboard of K-12 and higher education job openings from covered Montana sources, with salary, staffing, and Census context data for directly scraped districts and institutions. Updated twice a week.

**Live dashboard:** https://bostickmike-montana-education-jobs-dashboard.share.connect.posit.cloud

A port of the [Wyoming Education Jobs Dashboard](https://github.com/bostickmike/Wyoming-Education-Jobs-Dashboard), adapted rather than copied wholesale — see `RESEARCH_NOTES.md` for the differences between the two states (district counts, salary-source availability, FIPS codes) that shaped the port.

## What it does

- **Home**: open K-12 and college postings, each with a 12-week trend line and the change since the last update; the five districts, colleges, K-12 job types and college job types with the most postings, each with its own 12-week line; a switch that leaves out substitute, coaching and part-time jobs; and a card on how the K-12 numbers are put together.
- **Map**: every directly tracked district and college, plus districts the dashboard doesn't read directly that have a posting on OPI's statewide board (marked in their popup). Circle size is current openings; color is the vacancy rate (openings as a share of teaching or faculty staff).
- **K-12 and Higher Ed menus**, each with:
  - **Jobs**: every open posting, filterable and exportable, with posted pay where the posting states it. A "New this week" filter shows postings that appeared since the previous update.
  - **Districts** / **Colleges**: a directory with openings, vacancy rate, pay, budget and community context per district or college, and a head-to-head comparison of up to four.
  - **Trends**: current counts by category with sparklines and change over a month, quarter or year, and multi-year charts.
  - **Listing Duration**: how long postings stay listed, by job type.
- **Data**: every dataset as a download, with the data dictionary and where each source comes from.

## Data sources

K-12 reads 196 district job boards directly, plus OPI's statewide feed. The registry lists 200 districts: 4 of them have no board of their own, so their postings come from OPI. Montana has about 398 legally separate districts, many of them elementary and high-school districts that share one board (see `RESEARCH_NOTES.md`). Higher ed covers 23 institutions (19 independently scraped, plus Highlands College, Helena College, University of Montana Western, and Missoula College, which ride a parent institution's shared job board and are attributed per-posting to their own real institution rather than getting their own scrape target). The job-board platforms (`k12_district_registry.csv` / `he_institution_registry.csv`) are AppliTrack, SchoolSpring, Red Rover, TedK12, Tyler Portico, Paycom, JazzHR, NEOGOV, PeopleAdmin, Interfolio (University of Montana's faculty jobs), ADP Workforce Now and isolved Hire. Districts and colleges with no job-board platform are read from their own websites (`misc_district_scrapers.R` / `misc_college_scrapers.R`).

Many small districts run their websites on a school website system. Of the registry's 200 districts, 49 are on Apptegy (41 `Apptegy`, 6 `ApptegyPageBuilder`, 2 `ApptegyBespoke` with readers of their own), as is one college (Stone Child College); 20 are on Google Sites, 12 on CyberSchool (`CyberSchool`, `CyberSchoolText`), 12 on Finalsite, 7 on WordPress, 5 on Edlio and 5 on Joomla. Apptegy pages show no postings to a plain web request, so a headless Chrome opens them during each update. Each website family has one reader in edjobs (for example `fetch_apptegy_postings()`), and each district's list rules are in the registry's `List_Start` / `List_Stop` / `List_Skip` columns.

| Data | Source |
|---|---|
| K-12 job postings | Each covered district's own job board, plus OPI's statewide "Jobs for Teachers" feed; direct-board duplicates are reconciled at the posting level |
| Higher ed job postings | Each institution's own job board (see platform list above) |
| K-12 teacher salary | Montana Dept. of Labor & Industry's annual "Teacher Compensation Report" (9 regional PDFs) — reports average salary and 10th/90th percentile bands, not a base-salary figure; Montana has no public source for superintendent salaries (Wyoming's WSBA publishes them) |
| K-12 teacher staffing (for vacancy rate) | NCES Common Core of Data (CCD), via the [Urban Institute Education Data Portal](https://educationdata.urban.org) |
| K-12 per-district finance | OPI's own published financial data files — real General Fund (day-to-day operating budget) expenditure per district, a data category Montana has that Wyoming's dashboard doesn't |
| Higher ed faculty salary | IPEDS (federal Integrated Postsecondary Education Data System), via the Urban Institute Education Data Portal |
| Higher ed faculty staffing (for vacancy rate) | IPEDS, same source |
| Higher ed fall enrollment (FTE) | IPEDS via the Urban Institute Education Data Portal, a different survey component — powers a students-per-faculty figure and a 5-year enrollment trend |
| Higher ed Pell Grant recipient share | US Dept. of Education, Federal Student Aid, via the Urban Institute Education Data Portal |
| County-level context (median income, median rent, mining/energy employment share, 5-year population trend) | US Census Bureau, American Community Survey 5-Year Estimates, via the [Census Data API](https://www.census.gov/data/developers/data-sets/acs-5year.html) — joined onto each K-12 district's and HE institution's own county |
| District-level child poverty rate | US Census Bureau, [Small Area Income and Poverty Estimates (SAIPE)](https://www.census.gov/programs-surveys/saipe/data/datasets.html), via the same Census Data API |

MT DLI publishes only the current year's Teacher Compensation Report with no public archive, so this project keeps its own multi-year K-12 salary history (`k12_salary_history.csv`): one snapshot each time a new edition of the report appears. IPEDS is queryable by year directly, so higher-ed salary already shows multiple years back.

### K-12 coverage and scope

The K-12 Jobs Table combines 196 district job boards read directly with OPI's statewide Jobs for Teachers feed. Its `Source` column/export explicitly labels OPI rows. OPI is a valuable statewide source, but this project has not independently established its publication rules or coverage as a complete census of Montana vacancies. An absent posting therefore does not establish that no vacancy exists.

Each OPI posting's own page names its district, so OPI postings at districts this dashboard doesn't scrape directly also appear on the Map and in the Districts directory, badged "Postings via OPI's statewide board", with the same CCD, salary, finance and Census context where those sources cover them. Private and tribal schools, co-ops and other employers outside the public district list appear in the Jobs table only.

K-12 current counts, vacancy numerators, longitudinal totals, and New This Week use one posting-identity contract. Stable per-posting URLs/IDs are used when structured sources provide them; sites without one use an explicit fallback. OPI's fallback is necessarily title + raw location + posted date and retains equal observed rows rather than claiming OPI gives a stable identifier. See [METHODS.md](METHODS.md) for the exact method and limits.

## Automation

A GitHub Actions workflow runs twice a week (Mondays and Thursdays since 2026-11-17; never on Wyoming's Tuesdays and Fridays, since the two projects share one `CENSUS_API_KEY`), re-scrapes every source, regenerates every derived dataset, and commits and pushes if anything changed, which also redeploys the dashboard on Posit Connect Cloud. The workflow is a short caller of edjobs's reusable `weekly-run.yml`.

These steps stop the run before anything is committed:

- The full `testthat` suite, before any real data is touched.
- A sanity check against the previous run: refuses to commit if either K-12 or higher ed lost more than half its postings.
- A schema check (every column the dashboard reads is still there) and a data-quality sweep over the new files.

These only report (in a rolling "Scraper drift check" GitHub issue), so one finding never blocks the data:

- Drift: a source whose posting count falls far below its own history, corroborated by a live browser render of the page; a source that looks broken gets its own auto-fix issue.
- Salary and Census sources: coverage against the last run's files, and values outside plausible bounds.
- Posted pay that stopped arriving from a source, titles that aren't job titles, and sources with no rows in recent runs.
- OPI cross-check: OPI postings the district scrapes missed, empty scrapes, and districts worth adopting.
- A rebuild from the raw archives must reproduce the committed files; the run is checked against `run_expectations.csv`; and a meta-check reports any of these steps that crashed.

Two smaller workflows: `presence.yml` records once a day which postings the platform boards and OPI's list carry (list pages only; nothing uses it yet: the plan is to date postings' endings to the day), and `upkeep.yml` keeps the schedule from being switched off by GitHub's 60-day inactivity rule and warns before a token expires.

## Repository layout

- `Mt_ED_Jobs.Rmd` — the single pipeline entry point: scrapes every source, classifies and cleans postings, and adds each update's new rows to the accumulated datasets in `Mt_Ed_Jobs/`.
- `Mt_Ed_Jobs/app.R` — the Shiny dashboard itself. Its tabs and most of its server come from edjobs (one function per tab, such as `home_tab_panel()`, and `dashboard_server_shared()`); app.R loads the data and passes Montana's text and settings (such as `DISTRICT_SPEC`, the Districts tab's pay and budget columns).
- `direct_api_scrapers.R` — the real platform-API scrapers (AppliTrack, SchoolSpring, TedK12, Tyler Portico, Paycom, JazzHR, NEOGOV, Interfolio, ADP Workforce Now, isolved Hire, OPI statewide feed).
- `misc_district_scrapers.R` / `misc_college_scrapers.R` — readers for districts and colleges with no job-board platform, which read the postings from the school's own website. Most districts here go through edjobs's website-family readers (Apptegy, CyberSchool, Finalsite and others). These are kept apart from the platform scrapers because a website changes without notice and is less reliable than a platform's feed.
- `opi_finance_scraper.R` — OPI's per-district General Fund expenditure data, a Montana-only data category.
- `salary_scrapers.R`, `ccd_lea_pairs.R`, `ipeds_unitids.R` — the salary/staffing/Census data pipeline (the CCD, IPEDS, Pell, ACS and SAIPE fetchers are in edjobs).
- `k12_he_classification.R`, `drift_check.R`, `scrape_helpers.R`, `schema_check.R` — Montana's own parts of classification and monitoring (name corrections, posting identity, its schemas); each attaches edjobs, which holds the shared classifier and checks.
- `EDJOBS_VERSION` — the [edjobs](https://github.com/bostickmike/edjobs) version this repo pins: the R package with the code Montana and Wyoming share (platform scrapers, classifier, posting spells, the weekly run's checks, the dashboard's tabs).
- `history_accumulator.R` — adds each update's newly classified rows to the accumulated datasets (a same-day re-run replaces that day's rows; a column mismatch stops the run) instead of reprocessing the whole raw archive each time.
- `k12_district_registry.csv` / `he_institution_registry.csv` — the hand-maintained list of every directly-scraped district/institution, its platform, and its real feed/job-board URL.
- `METHODS.md` — how the numbers are made: what counts as a posting, OPI de-duplication, categories, pay, vacancy rate, listing duration, context data.
- `DATA_DICTIONARY.md` (and `Mt_Ed_Jobs/data_dictionary.csv`, shown on the dashboard's Data tab) — every published file and column.
- `RESEARCH_NOTES.md` — the original WY→MT scoping research (district counts, salary-source gap, FIPS codes) that shaped every structural decision in this port.
- `Archivek12_Data/`, `Archived_HE_Data/` — one dated raw snapshot per update, the durable source of truth. `scripts/rebuild_*_history_from_archive.R` rebuild the accumulated datasets from these from scratch, for disaster recovery or to check that the incremental path matches a full rebuild (each update checks this too).
- `tests/testthat/` — the test suite, built almost entirely on fixtures captured from the live sources (scraped HTML, downloaded PDFs, API responses) rather than made-up data.
- `.github/workflows/weekly-scrape.yml` — the automation described above: a short caller of edjobs's reusable `weekly-run.yml` at the pinned tag, holding Montana's cron, secrets and state check.

## Running locally

Requirements: R (>= 4.5.0), the version edjobs requires.

```r
install.packages(c(
  # Pipeline (Mt_ED_Jobs.Rmd) dependencies
  "rmarkdown", "dplyr", "purrr", "readr", "readxl", "rvest",
  "stringr", "tidyverse", "writexl", "xml2", "jsonlite",
  "httr2", "lubridate", "chromote", "rsconnect", "testthat",
  "withr", "here", "pdftools", "tibble",
  # Dashboard (Mt_Ed_Jobs/app.R) dependencies
  "shiny", "bslib", "shinyWidgets", "DT", "data.table",
  "leaflet", "plotly", "scales", "shinycssloaders"
))
```

Install the pinned edjobs (the app and the pipeline both load it):

```r
pak::pak(paste0("bostickmike/edjobs@v", readLines("EDJOBS_VERSION")))
```

To run the dashboard against the data already committed in the repo (no scraping needed):

```r
shiny::runApp("Mt_Ed_Jobs")
```

To re-run the full scrape/build pipeline (takes a while, hits every live source, and needs Chrome or Chromium for the Apptegy pages; set `CHROMOTE_CHROME` to its path if it isn't found):

```r
rmarkdown::render("Mt_ED_Jobs.Rmd")
```

The Census county-context chunk needs a free `CENSUS_API_KEY` environment variable (get one at https://api.census.gov/data/key_signup.html and set it in `.Renviron` locally, or as a GitHub Actions secret for the weekly workflow) — every other chunk runs fine without it, but that one step will fail loudly and leave `salarymap2.csv`'s county-context columns untouched if it's missing.

## Testing

```r
testthat::test_dir("tests/testthat")
```

## Licensing

- Source code is licensed under the MIT License — see `LICENSE`.
- Processed datasets and archived CSV files are licensed under Creative Commons Attribution 4.0 International (CC BY 4.0) — see `DATA_LICENSE.md`.

## Contact

Created by Michael Bostick, adapted from the [Wyoming Education Jobs Dashboard](https://github.com/bostickmike/Wyoming-Education-Jobs-Dashboard) — originally built by Mark Perkins, substantially rewritten and extended since.
