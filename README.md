# Montana Education Jobs Dashboard

A live, weekly-updated dashboard of K-12 and higher education job openings from covered Montana sources, with salary, staffing, and Census context data for directly scraped districts and institutions. A port of the [Wyoming Education Jobs Dashboard](https://github.com/bostickmike/Wyoming-Education-Jobs-Dashboard), adapted rather than copied wholesale — see `RESEARCH_NOTES.md` for the real structural differences between the two states (district counts, salary-source availability, FIPS codes) that shaped the port.

## What it does

- **Map** — every K-12 district and higher-ed institution with a current opening, plotted with two dimensions at once: circle size for number of openings, circle color for vacancy rate (openings as a share of teaching/faculty staff).
- **Home** — headline KPIs (with week-over-week deltas), top-hiring tables with trend sparklines, "biggest mover" callouts, and leaderboards for highest vacancy rate.
- **Jobs Tables** — every open posting, filterable and exportable (copy/CSV/print), per district or institution; K-12 exports include source provenance.
- **District Summary / Institution Summary** — one row per district or college with current openings, vacancy rate, and salary figures, fully exportable.
- **Longitudinal Trends** — postings over time by subject/category, with a Simple or Detailed category toggle so the chart stays readable either way.
- **Current Trends** — a compact table per category: current count, a trend sparkline, and change vs. a month/quarter/year ago.
- **New This Week** — postings that appeared since the previous weekly snapshot.

## Data sources

K-12 covers 85 directly-scraped districts (not Montana's full ~398-district universe — see `RESEARCH_NOTES.md`); higher ed covers 23 institutions (19 independently scraped, plus Highlands College, Helena College, University of Montana Western, and Missoula College, which ride a parent institution's shared job board and are attributed per-posting to their own real institution rather than getting their own scrape target). Platform coverage (`k12_district_registry.csv`/`he_institution_registry.csv`) spans AppliTrack, SchoolSpring, TedK12, Tyler Portico, Paycom, JazzHR, NEOGOV Attract, ADP Workforce Now, isolved Hire, and Apptegy (the last needing a live browser render — see Automation below), plus several institutions with no structured ATS at all, heuristically scraped from their own site's real page structure (`misc_district_scrapers.R`/`misc_college_scrapers.R`).

| Data | Source |
|---|---|
| K-12 job postings | Each covered district's own job board, plus OPI's statewide "Jobs for Teachers" feed; direct-board duplicates are reconciled at the posting level |
| Higher ed job postings | Each institution's own job board (see platform list above) |
| K-12 teacher salary | Montana Dept. of Labor & Industry's annual "Teacher Compensation Report" (9 regional PDFs) — reports average salary and 10th/90th percentile bands, not a base-salary figure; no superintendent salary source exists publicly at all (a real, confirmed gap, unlike Wyoming's WSBA) |
| K-12 teacher staffing (for vacancy rate) | NCES Common Core of Data (CCD), via the [Urban Institute Education Data Portal](https://educationdata.urban.org) |
| K-12 per-district finance | OPI's own published financial data files — real General Fund (day-to-day operating budget) expenditure per district, a data category Montana has that Wyoming's dashboard doesn't |
| Higher ed faculty salary | IPEDS (federal Integrated Postsecondary Education Data System), via the Urban Institute Education Data Portal |
| Higher ed faculty staffing (for vacancy rate) | IPEDS, same source |
| Higher ed fall enrollment (FTE) | IPEDS via the Urban Institute Education Data Portal, a different survey component — powers a students-per-faculty figure and a 5-year enrollment trend |
| Higher ed Pell Grant recipient share | US Dept. of Education, Federal Student Aid, via the Urban Institute Education Data Portal |
| County-level context (median income, median rent, mining/energy employment share, 5-year population trend) | US Census Bureau, American Community Survey 5-Year Estimates, via the [Census Data API](https://www.census.gov/data/developers/data-sets/acs-5year.html) — joined onto each K-12 district's and HE institution's own county |
| District-level child poverty rate | US Census Bureau, [Small Area Income and Poverty Estimates (SAIPE)](https://www.census.gov/programs-surveys/saipe/data/datasets.html), via the same Census Data API |

MT DLI publishes only the current year's Teacher Compensation Report with no public archive, so multi-year K-12 salary history is captured and grown by this project's own weekly pipeline going forward (`k12_salary_history.csv`), one snapshot per new report edition. IPEDS is queryable by year directly, so higher-ed salary already shows multiple years back.

### K-12 coverage and scope

The K-12 Jobs Table combines 85 directly scraped district boards with OPI's statewide Jobs for Teachers feed. Its `Source` column/export explicitly labels OPI rows. OPI is a valuable statewide source, but this project has not independently established its publication rules or coverage as a complete census of Montana vacancies. An absent posting therefore does not establish that no vacancy exists.

The Map and District Summary deliberately show only directly scraped districts: those records can be matched to verified district identities, coordinates, staffing, salary, and OPI General Fund expenditure data. OPI-only rows remain in the Jobs Table, but OPI exposes a raw location field rather than a canonical district identifier, so they cannot be reliably joined to district context or mapped.

K-12 current counts, vacancy numerators, longitudinal totals, and New This Week use one posting-identity contract. Stable per-posting URLs/IDs are used when structured sources provide them; sites without one use an explicit fallback. OPI's fallback is necessarily title + raw location + posted date and retains equal observed rows rather than claiming OPI gives a stable identifier. See `DATA_COOKBOOK.md` for the exact method and limits.

## Automation

A GitHub Actions workflow runs weekly (Tuesdays — deliberately not Wyoming's Friday, since the two projects share one `CENSUS_API_KEY`), re-scrapes every source, regenerates every derived dataset, and commits + pushes if anything changed — which also triggers an automatic Posit Connect Cloud redeploy. Several non-blocking checks run alongside it:

- Full `testthat` suite must pass before any real data is touched.
- A sanity check compares the new pull against the previous run and refuses to commit if either side dropped more than half its postings.
- Drift detection flags any source whose posting count falls far below its own historical baseline, with a live `chromote` render of the page as corroboration before anything is filed as a GitHub Issue.
- Salary-source coverage checks watch each source against its own known-fixed (or, where a source has a real permanent gap like MT DLI's, known-partial) universe and flag if it starts returning noticeably less than expected.
- The same coverage + value-plausibility checks run for the Census ACS/SAIPE sources.
- Twenty-four K-12 districts and one HE institution (Wolf Point, Plentywood, Conrad, Westby, Choteau, Gardiner, Malta, Drummond, Deer Lodge, Townsend, Hays-Lodge Pole, Plevna, Sunburst, Belt, Big Sky, Melstone, Roundup, White Sulphur Springs, Shelby, Centerville, Arlee, Chinook, Darby, Dutton/Brady, and Stone Child College) run on Apptegy, a CMS that ships no real content to a plain HTTP request — a real headless Chrome instance (installed via `browser-actions/setup-chrome`) renders these during the pipeline run itself, the same technique 4 of Wyoming's own districts already needed. One more district, Geyser, runs a different CMS ("CyberSchool 2.0") with the same plain-HTTP-request limitation, sharing that same headless-Chrome render rather than needing a second browser instance.

## Repository layout

- `Mt_ED_Jobs.Rmd` — the single pipeline entry point: scrapes every source, classifies and cleans postings, and appends this week's newly derived rows onto the accumulated datasets in `Mt_Ed_Jobs/`.
- `Mt_Ed_Jobs/app.R` — the Shiny dashboard itself.
- `direct_api_scrapers.R` — the real platform-API scrapers (AppliTrack, SchoolSpring, TedK12, Tyler Portico, Paycom, JazzHR, NEOGOV, ADP Workforce Now, isolved Hire, OPI statewide feed).
- `misc_district_scrapers.R` / `misc_college_scrapers.R` — heuristic scrapers (including the chromote-driven Apptegy ones) for districts/institutions with no structured ATS, kept separate from the platform-API scrapers since they're a real but acknowledged-less-reliable source.
- `opi_finance_scraper.R` — OPI's per-district General Fund expenditure data, a Montana-only data category.
- `salary_scrapers.R`, `ccd_staff_scraper.R`, `ipeds_salary_scraper.R`, `ipeds_enrollment_scraper.R`, `fsa_pell_scraper.R`, `census_acs_scraper.R`, `census_saipe_scraper.R` — the salary/staffing/Census data pipeline.
- `k12_he_classification.R`, `drift_check.R`, `scrape_helpers.R`, `schema_check.R` — classification and monitoring logic every chunk sources, largely state-agnostic and ported near-verbatim from Wyoming.
- `history_accumulator.R` — appends each week's newly classified rows onto the existing accumulated datasets (idempotent, schema-checked) instead of reprocessing the full raw archive every run.
- `k12_district_registry.csv` / `he_institution_registry.csv` — the hand-maintained list of every directly-scraped district/institution, its platform, and its real feed/job-board URL.
- `RESEARCH_NOTES.md` — the original WY→MT scoping research (district counts, salary-source gap, FIPS codes) that shaped every structural decision in this port.
- `Archivek12_Data/`, `Archived_HE_Data/` — one dated raw snapshot per week, still written every run as the durable source of truth. `scripts/rebuild_*_history_from_archive.R` rebuild the accumulated datasets from these from scratch, for disaster recovery or to verify the incremental path hasn't drifted. Run `Rscript scripts/rebuild_k12_history_from_archive.R` to deterministically migrate K-12 derived data to the current identity/provenance schema from committed archives.
- `tests/testthat/` — the test suite, built almost entirely on real captured fixtures (real scraped HTML, real downloaded PDFs, real API responses) rather than synthetic data.
- `.github/workflows/weekly-scrape.yml` — the automation described above.

## Running locally

Requirements: R (>= 4.0).

```r
install.packages(c(
  # Pipeline (Mt_ED_Jobs.Rmd) dependencies
  "rmarkdown", "dplyr", "purrr", "readr", "readxl", "rvest",
  "stringr", "tidyverse", "writexl", "xml2", "jsonlite",
  "httr2", "lubridate", "chromote", "rsconnect", "testthat",
  "withr", "here", "pdftools", "tibble",
  # Dashboard (Mt_Ed_Jobs/app.R) dependencies
  "shiny", "shinydashboard", "shinyWidgets", "DT", "data.table",
  "leaflet", "plotly", "scales", "shinycssloaders"
))
```

To run the dashboard against the data already committed in the repo (no scraping needed):

```r
shiny::runApp("Mt_Ed_Jobs")
```

To re-run the full scrape/build pipeline (takes a while, hits every live source, and needs a real headless Chrome available for the Apptegy scrapers — see Automation above):

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
