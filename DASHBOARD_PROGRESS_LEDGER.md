# Montana Education Jobs Dashboard — Project Progress Ledger

**Maintainers & Authors:** Mike Bostick & Mark Perkins  
**Target Environment:** Posit Connect Cloud (Shiny for R)  
**CI/CD Orchestration:** GitHub Actions (`.github/workflows/weekly-scrape.yml`)  
**Production Cadence:** Automated weekly scrape & build every Tuesday 05:00 UTC (and manual `workflow_dispatch`)  
**Repository Branch:** `main`

---

## 1. Executive Summary & Purpose

This ledger serves as the authoritative, version-controlled record of feature development, pipeline hardening, data schema evolution, and feature parity between the **Montana Education Jobs Dashboard** and its sister project, the **Wyoming Education Jobs Dashboard**.

Unlike ephemeral conversation logs or local scratch handoffs, this document lives within the repository root so any human contributor, collaborator, or autonomous coding agent can instantly understand the exact state of the system, what has been implemented, active guardrails, and what remains to be completed.

---

## 2. Feature & Architecture Parity Matrix (WY vs. MT)

| Capability / Module | Wyoming (`Wy_Ed_Jobs`) | Montana (`Mt_Ed_Jobs`) | Parity Status | Implementation Notes |
| :--- | :--- | :--- | :--- | :--- |
| **K-12 Active Jobs Table** | Implemented | Implemented | **Full Parity** | Filterable by district, position, subject, broad category; exportable. |
| **K-12 District Summary** | Implemented | Implemented | **Full Parity** | District profiles, student-teacher ratios, salary benchmarks. |
| **K-12 Longitudinal Trends** | Implemented | Implemented | **Full Parity** | Multi-year vacancy volume time series with rolling averages. |
| **K-12 Current Trends** | Implemented | Implemented | **Full Parity** | In-season bar/donut distributions by category & subject. |
| **K-12 New This Week** | Implemented | Implemented | **Full Parity** | Delta detection vs. prior week's scrape snapshot. |
| **K-12 Vacancy Spells & Time-to-Fill** | Implemented | Implemented | **Full Parity** | Interactive Shiny tab (`k12_spells`) with KPIs, histograms, and spell tables. |
| **Higher Ed Vacancy Spells & Time-to-Fill** | Implemented | Implemented | **Full Parity** | Interactive Shiny tab (`he_spells`) with KPIs, duration histograms, discipline breakdown, and spell table. |
| **Higher Ed Jobs Table** | Implemented | Implemented | **Full Parity** | Faculty, adjunct, and institutional staff postings. |
| **Higher Ed Summary & Trends** | Implemented | Implemented | **Full Parity** | IPEDS instructional salary benchmarks & enrollment. |
| **Geographic Leaflet Map** | Implemented | Implemented | **Full Parity** | Cluster-mapped district & college vacancy pins. |
| **Data Sources & Codebook Tab** | Implemented | Implemented | **Full Parity** | Direct CSV download buttons and interactive schemas. |
| **Federal NCES LEA IDs** | Embedded (48/48) | Embedded (191/191) | **Full Parity** | 7-digit `NCES_LEAID` in registry, `salarymap2.csv`, and `job_duration_spells.csv`. |
| **Federal IPEDS UNITIDs** | Embedded (8/8) | Embedded (23/23) | **Full Parity** | 6-digit `IPEDS_UNITID` in higher ed institutional registry and `salarymap.csv`. |
| **Pipeline Dry-Run Test Harness** | Implemented | Implemented | **Full Parity** | Evaluates scrape combination chunks against mock data frames in CI. |
| **Pipeline AST Defensive Linting**| Implemented | Implemented | **Full Parity** | Blocks syntax typos (`%%`) and enforces date coercions. |
| **Connect Cloud Manifest Engine** | Implemented | Implemented | **Full Parity** | Enforces literal `null` metadata and users blocks for Connect Cloud. |

---

## 3. Implementation Chronology & Milestones

### Milestone 1: Cross-State Feature Porting (October 2026)
* **Federal Universal Identifiers:**
  * Embedded official 7-digit `NCES_LEAID` Local Education Agency identifiers from the NCES Common Core of Data (CCD) and Census SAIPE across 100% of Montana districts (188/188) in `k12_district_registry.csv`.
  * Joined `NCES_LEAID` into `Mt_Ed_Jobs/salarymap2.csv` (128/128 districts) and `Mt_Ed_Jobs/job_duration_spells.csv` (362/367 rows).
  * Updated `Mt_ED_Jobs.Rmd` join pipeline, `DATA_DICTIONARY.md`, and `Mt_Ed_Jobs/data_dictionary.csv`.
* **Vacancy Spells & Time-to-Fill Tab:**
  * Ported interactive `k12_spells` module to `Mt_Ed_Jobs/app.R` matching the Wyoming implementation:
    - 4 reactive summary KPIs: Median Vacancy Duration (Days), Long-Duration Vacancies (>45d), Active Openings, Closed/Filled Spells.
    - 4 reactive user filters: Position Type, Subject Category, District Picker, Spell Status (All / Closed / Still Open).
    - 2 Plotly interactive visualizations: Duration Histogram & Density curve, and Category-Level Box Plots.
    - Searchable DT data table with CSV and Excel export buttons.
  * Added `job_duration_spells.csv` to `REQUIRED_SCHEMAS` in `schema_check.R` to satisfy the strict schema verification suite.
* **Citation & Attribution Harmonization:**
  * Standardized citations and footer attribution across `Mt_ED_Jobs.Rmd`, `Mt_Ed_Jobs/app.R`, and `DATA_DICTIONARY.md` to:  
    *"Developed by Mike Bostick and Mark Perkins"*.

### Milestone 2: Scraper Pipeline Hardening & Error Eradication
* **Date Parsing Homogenization:**
  * Resolved fatal CI pipeline crashes caused by `bind_rows()` encountering conflicting types (`date` vs `character` in `date_posted`).
  * Created `standardize_df_date()` and `standardize_he_df_date()` functions in `Mt_ED_Jobs.Rmd` mapped via `lapply()` before combining direct K-12 and HE data frames.
  * Hardened `safe_scrape()` in `scrape_helpers.R` to coerce `date_posted` and `Posted_Date` to `character` upon return, preventing type collisions with `empty_df()` (`character(0)`).
* **AST Typo Guardrails:**
  * Corrected modulo operator typo `%%` at lines 2140, 2164, 2188 of `Mt_ED_Jobs.Rmd` to `%>%`.
  * Added AST analysis tests in `tests/testthat/test-pipeline-defensiveness.R` to ensure syntax typos never pass CI again.

### Milestone 3: Advanced Pipeline Test Harness
* **Mock Pipeline Dry-Run Harness (`test-pipeline-orchestration-dryrun.R`):**
  * Created unit test suites evaluating all scraping combination and munge chunks against heterogeneous mock inputs (mixed character/Date formats, empty scrapers, missing columns) in ~1.2s without making live network calls.
  * Enforces that all combiners correctly handle empty scrape results gracefully.
* **Manifest Deploy Guardrails:**
  * Validated that `manifest.json` generation preserves explicit `null` JSON literals for `primary_rmd`, `primary_html`, `content_category`, and `users`, preventing deployment rejections on Posit Connect Cloud.

### Milestone 4: Higher Education Vacancy Duration Spells & Pipeline Synchronization
* **Collegiate Vacancy Spells & Time-to-Fill (`he_job_duration_spells.csv` & `he_spells`):**
  * Derived longitudinal collegiate duration spell panels from `facultydata.csv` tracking time-to-fill, right-censored vacancies, and academic discipline indicators across all institutions (227 spells MT, 711 spells WY).
  * Implemented interactive `he_spells` module in `Mt_Ed_Jobs/app.R`:
    - 4 reactive summary KPIs: Median Vacancy Duration (Days), Currently Open Searches, Persistent Searches (≥90d), Longest Duration Discipline.
    - 4 reactive user filters: Vacancy Status, Appointment Type (Regular vs Adjunct), Academic Focus (STEM, Health Sciences, CTE), Institution Picker.
    - 2 Plotly interactive visualizations: Median Days Open by Discipline horizontal bar chart and binned duration distribution histogram.
    - Searchable DT data table with CSV and Excel export buttons.
    - Direct CSV download button in the *Data Sources & Open Research Downloads* tab (`he_job_duration_spells.csv`).
  * Automated spell generators in `scripts/generate_he_job_duration_spells.R`.
  * Added `he_job_duration_spells.csv` to `REQUIRED_SCHEMAS` in `schema_check.R`, verified with `test-schema-check.R`.
  * Documented all schema variables in `DATA_DICTIONARY.md`, `data_dictionary.csv`, and `DATA_COOKBOOK.md`.
  * Integrated automated spell generation step into `.github/workflows/weekly-scrape.yml`.

### Milestone 5: Montana K-12 Coverage Expansion (Batch 21) & Scraper Drift Recovery
* **Scraper Drift Recovery:**
  * Fixed drifted `Brockton School District` scraper: updated endpoint from deprecated SchoolInSites URL to live district site (`https://www.brockton.k12.mt.us/employment`), extracting 3 active positions (`Elementary Teacher`, `Secondary STEM`, `Secondary Humanities`) while maintaining backward-compatible parser tests.
* **Batch 21 District Adoption:**
  * Adopted 3 new Montana K-12 districts with verified 7-digit `NCES_LEAID` universal identifiers from NCES CCD, coordinates, and automated test coverage:
    - **Frontier Elementary School** (`NCES_LEAID`: `3011670`, Roosevelt County / Wolf Point, CyberSchool 2.0).
    - **Saco Public Schools** (`NCES_LEAID`: `3023370`, Phillips County, CyberSchool 2.0).
    - **Ulm Public Schools** (`NCES_LEAID`: `3026880`, Cascade County, Weebly CMS).
  * Expanded Montana district registry coverage from 188 to 191 directly-tracked districts.
  * Resolved Group 3 & Group 10 backlog items: triaged Avon, Bynum, Elliston, Garrison, and Dupuyer to Group 8 (county-managed or no standalone job boards).
  * Enhanced `scripts/scaffold_district.R` to support 9-column registry schema with `--leaid` and CyberSchool CMS scaffolding.

### Milestone 6: Interactive Spells Hardening, Research Downloads Parity & UX Polish
* **Interactive Vacancy Spells Resiliency:**
  * Added zero-row / empty filter state handling across both K-12 and Higher Ed vacancy spells modules (`k12_spells`, `he_spells`):
    - Reactive KPIs return clean zero counts (`0 Days`, `0 Open Spells`, `0 Persistent Spells`, `None`) instead of NaN or errors.
    - Plotly duration and distribution charts render clean, informative placeholder notifications (`"No vacancy spells match the selected filter criteria"`) instead of leaving an empty white canvas.
    - Duration distribution histograms regularized with `tidyr::complete()` across all 5 standard duration bins (`1–14 Days`, `15–30 Days`, `31–60 Days`, `61–90 Days`, `90+ Days` for K-12; `1–30 Days`, `31–60 Days`, `61–90 Days`, `91–180 Days`, `180+ Days` for Higher Ed), guaranteeing consistent axes and comparable geometries under dynamic filtering.
    - Searchable DT spell tables render clean empty states without `req()` blocking.
* **Homepage Interactive Drill-Down:**
  * Enhanced "Top K-12 Hiring Districts This Week" and "Top Higher Ed Hiring Institutions This Week" tables with clickable employer action links.
  * Clicking any top employer automatically selects that employer, switches to the filtered `k12_table` or `he_table`, and displays all active positions.
  * Hardened `observeEvent(input$popup_view_jobs)` to seamlessly handle mapped institutions, direct scrape LEAs, and OPI statewide locations.
* **Open Research Downloads Completeness:**
  * Added direct CSV download for **Higher Ed Weekly Vacancies** (`download_he_weekly_totals`, serving `he_institution_weekly_totals.csv`).
  * Documented `he_institution_weekly_totals.csv` in `Mt_Ed_Jobs/data_dictionary.csv` and `DATA_DICTIONARY.md`.
* **Data Quality Test Suite Expansion:**
  * Registered `job_duration_spells.csv` and `he_job_duration_spells.csv` into `ALL_OUTPUT_CSVS` in `test-weekly-data-quality.R`, enforcing automated verification against NaN, Inf, and literal string leakage across 2,839 passing tests.
* **Coverage Backlog Triage:**
  * Triaged Golden Ridge (Teton County #45) and Grant (Beaverhead County #7) to Group 8 in `DISTRICT_BACKLOG.md` (1-room rural schools with no standalone job boards).

### Milestone 7: Tab Navigation Consolidation & Head-to-Head Comparator Modules
* **Sidebar Navigation Consolidation:**
  * Streamlined sidebar navigation from 16 tabs down to 10 tabs, removing sidebar clutter while preserving 100% of underlying analytical modules.
  * Replaced flat tab list with organized `tabBox` subtab navigation:
    - **Profiles & Compare** (`k12_summary` / `he_summary`): Subtab 1: Directory Table, Subtab 2: Head-to-Head Comparator.
    - **Current Trends & New** (`k12_current` / `he_current`): Subtab 1: Category & Discipline Breakdown, Subtab 2: New This Week Postings.
    - **Trends & Duration Spells** (`k12_trends` / `he_trends`): Subtab 1: Longitudinal Hiring Trends, Subtab 2: Vacancy Spells & Time-to-Fill.
* **Side-by-Side District & College Comparator:**
  * Built interactive Head-to-Head Comparators allowing users to select and benchmark up to 4 districts or colleges simultaneously.
  * Dynamic comparative cards display active openings, vacancy rates, compensation (MT DLI teacher average salary, 10th-90th percentile bands, IPEDS faculty compensation), general fund operating expenditures, student enrollment, student-to-staff ratios, and community socioeconomic context.
  * Comparative Plotly visualizations for compensation benchmarks, staffing scale, and collegiate appointment distributions.
  * Real-time filtered openings table showing active postings across the selected employers.
  * One-touch quick presets for "Top Hiring" and "Largest Enrollment" employers.
* **Test Suite Expansion & Zero-Warning Cleanliness:**
  * Added automated reactive tests in `test-app-reactives.R` verifying comparator card rendering, Plotly graphics, tabular filters, and preset button event handlers.
  * Updated `LEAF_TABS` contract in `test-app-boot-smoke.R` to reflect the 10 consolidated destination tabs.
  * Verified 2,855 passing tests (0 fails, 0 warnings, 2 skips).

### Milestone 8: Map Multi-Dimensional Filtering & Responsive Navigation (2026-10-28)
* **Multi-Dimensional Map Filter Panel:**
  * Built an integrated responsive control panel directly above the interactive Leaflet map featuring:
    - **Employer Type:** Toggle K-12 Districts, Higher Ed Institutions, or both.
    - **County Filter:** Dropdown populated from all 56 Montana counties with clean user-facing labels.
    - **Salary Benchmark Tier:** Filter by average educator compensation ($60,000+ Average Pay, $50,000 - $60,000, Under $50,000) harmonizing MT DLI teacher average salary (with 10th percentile fallback) and IPEDS faculty average pay.
    - **Posting Volume & Urgency:** Filter by employer hiring intensity (All Active Locations, High Volume 5+ openings, Multiple Openings 2+, New Postings This Week).
    - **1-Click Reset:** Single-click "Reset Filters" action button restoring all controls to default statewide view.
* **Dynamic Filter Result Badge:**
  * Real-time indicator displaying matching location counts and cumulative active openings across the filtered locations (`Showing X of Y active locations (Z current openings across filtered locations)`).
  * Informative warning state with guidance to broaden filters when zero locations match the selected criteria.
* **Responsive Geo-Spatial Viewport Centering:**
  * Automatically pans and bounds-zooms the Leaflet map viewport to the selected county when a user chooses a county filter, and smoothly returns to the statewide Montana view when reset.
* **Defensive Marker Lifecycle & Zero-Row Guarding:**
  * Ensured `leafletProxy` reliably clears markers without generating orphaned popups or JavaScript errors on 0-row filter states.
* **Automated Reactive Test Coverage:**
  * Added comprehensive tests in `test-app-reactives.R` verifying default filtering, single and combined filter attributes, county zoom coordinates, empty state handling, and reset triggers (20 new tests, 2,875 total tests passing with 0 fails and 0 warnings).

### Milestone 9: Research Data Dictionary Completeness & Automated Codebook Invariants (2026-10-28)
* **100% Data Dictionary & Codebook Column Coverage:**
  * Expanded `Mt_Ed_Jobs/data_dictionary.csv` to 120 variables across all 9 public research download CSVs on the Data Sources tab.
  * Resolved documentation drift for `k12jobanalysis.csv` (3,200+ historical records), Census ACS variables (`Median_Household_Income`, `Median_Gross_Rent`, `Population`, `Mining_Employment_Share`), OPI school finance metrics, and IPEDS historical faculty compensation.
  * Synchronized [`DATA_DICTIONARY.md`](file:///Users/mikebostick/Jobs_Dash_repos/Montana-Education-Jobs-Dashboard/DATA_DICTIONARY.md) markdown codebook with complete markdown tables and universal identifier definitions (`NCES_LEAID`, `IPEDS_UNITID`).
* **Automated Codebook Invariant Test Harness:**
  * Created [`tests/testthat/test-data-dictionary.R`](file:///Users/mikebostick/Jobs_Dash_repos/Montana-Education-Jobs-Dashboard/tests/testthat/test-data-dictionary.R) enforcing:
    - 100% column documentation: every column in every public download CSV must exist in `data_dictionary.csv`.
    - Zero phantom columns: every documented column must exist in the target dataset.
    - Non-empty descriptions and valid data types.
    - Synchronized dataset inventories between Shiny UI download handlers and `data_dictionary.csv`.
* **Data Quality Test Suite Registration:**
  * Added `data_dictionary.csv` to `ALL_OUTPUT_CSVS` in `tests/testthat/test-weekly-data-quality.R`.
  * Verified 2,929 passing tests across the entire test suite (0 fails, 0 warnings, 2 skips).

### Milestone 10: K-12 District Coverage Expansion — Batch 22 & Group 3 Triage (2026-10-28)
* **Adopted Districts into Direct Pipeline (191 -> 194 districts):**
  * **Montana City Elementary School District #27** (Jefferson County, NCES `3018780`): Scaffolded CyberSchool scraper targeting `https://www.mtcityschool.net/District/Jobs/`.
  * **Denton Public Schools** (Fergus County, NCES `3008850`): Scaffolded CyberSchool scraper targeting `https://www.denton.k12.mt.us/District/Jobs/`.
  * **Clancy Elementary School District #1** (Jefferson County, NCES `3006840`): Scaffolded CyberSchool scraper targeting `https://www.clancyschool.org/District/Jobs/`.
* **Group 3 & Group 8 Backlog Triage:**
  * Investigated and resolved geographic/website status for Pine Grove (Garfield County District 19, Brusett MT; 1-teacher 7-student rural school) and Hawks Home (Carter County District 78, Hammond MT; ~5-12 students). Both lack standalone web portals and were triaged to Group 8 (declined / covered via OPI).
  * Verified Basin School status (reopened 2026, site/DNS pending; triaged to Group 8).
* **Test Suite Expansion:**
  * Added HTML test fixtures for Montana City, Denton, and Clancy in `tests/testthat/fixtures/`.
  * Added unit test suites in `tests/testthat/test-misc-district-scrapers.R`.
  * Added unmapped DLI coverage tests in `tests/testthat/test-salary-scrapers.R`.
  * Verified full test suite: **2,944 PASS, 0 FAIL, 0 WARN** (2 skips).

### Milestone 11: Columbia Falls RedRover Platform Recovery & Modernized Parser (2026-10-28)
* **Silent Platform Drift Discovery & Recovery:**
  * Identified that **Columbia Falls School District 6** (Flathead County, NCES LEAID `3007110`) had migrated away from its deprecated SchoolSpring portal (`sd6.schoolspring.com` returning 0 postings) to RedRover (`https://jobs.redroverk12.com/org/sd659912`), silently dropping 25 active vacancies.
  * Migrated Columbia Falls from `SchoolSpring` to `RedRoverK12` in `k12_district_registry.csv` and added its scraper dispatch function to `APPTEGY_DISTRICT_SCRAPERS` in `misc_district_scrapers.R`.
* **RedRover Parsing Engine Modernization:**
  * Modernized `parse_redrover_postings()` in `misc_district_scrapers.R` to support modern Next.js DOM structures where the "Apply Now" button and relative timestamp are concatenated within the same line (`Apply Now3 days ago`, `Apply Nowabout 1 month ago`) in addition to standalone "APPLY NOW" button stamps followed by next-line relative timestamps (e.g. St. Ignatius) or no relative timestamps (e.g. Hamilton).
  * Maintained 100% backward compatibility with all existing RedRover districts.
* **Test Fixture & Cross-Check Suite:**
  * Added clean fixture `columbiafalls_jobs_rendered.txt` to `tests/testthat/fixtures/`.
  * Expanded shared-session testing in `tests/testthat/test-misc-district-scrapers.R` from 45 to 46 districts, verifying exact district-tagging and row-count totals (45-district count + 25 = 265 total postings across fixtures).
  * Added dedicated unit test for Columbia Falls in `test-misc-district-scrapers.R`.
  * Verified 2-way set equality cross-check between `k12_district_registry.csv` and `APPTEGY_DISTRICT_SCRAPERS`.
  * Verified full test suite: **2,952 PASS, 0 FAIL, 0 WARN** (2 skips).
* **Backlog Triage Refinement:**
  * Triaged **Anderson School District #41** (Gallatin County): confirmed ParentSquare CMS at `andersonmt.org/careers` contains only recruiting prose without active vacancies (`RECHECK`).
  * Triaged **Kester School District #29** (Garfield County): confirmed `kesterschool23.org/employment` banner states it is no longer accepting applications (1-room rural school, `Group 8 DECLINED`).
  * Created **Group 11 — Platform Drift Recoveries** in `DISTRICT_BACKLOG.md` documenting Brockton and Columbia Falls.

### Milestone 12: K-12 District Coverage Expansion — Batch 23 (Bainville, CJI, Marion) (2026-10-28)
* **Direct Pipeline District Adoption:**
  * Adopted 3 new Montana K-12 districts into `k12_district_registry.csv`, expanding total coverage from 194 to 197 directly-tracked districts:
    - **Bainville K-12 Schools** (`NCES_LEAID`: `3002640`, Roosevelt County, Bainville): Extracts both Certified and Classified job listings from embedded Google Docs (`1n0ed1N5YGWsSs948BfXk1CYqK9BvzrGXIz4DRklS3mw` and `1nQVTrVJJususbBn9EvdT7xD1gDHFYeW3RQhdR10RTbQ`) via `/export?format=html` without requiring headless Chrome. Extracted 7 active vacancies.
    - **Chester-Joplin-Inverness Public Schools (CJI)** (`NCES_LEAID`: `3000098`, Liberty County, Chester): Apptegy site linking via `aptg.co` to live Thrillshare PDF vacancy notice (`pdftools::pdf_text()`). Extracted 5 active vacancies.
    - **Marion School District #54** (`NCES_LEAID`: `3017700`, Flathead County, Marion): Google Sites parser extracting structured vacancies under `VACANCIES` header. Extracted 1 active vacancy.
  * Recovered/adopted **13 active teacher and staff vacancies** into the direct pipeline.
* **Test Fixture & Firewall Invariant Suite:**
  * Added 4 fixtures to `tests/testthat/fixtures/`: `bainville_certified.html`, `bainville_classified.html`, `cji_positions_text.txt`, and `marion_employment.html`.
  * Added 6 unit test blocks to `tests/testthat/test-misc-district-scrapers.R` validating fixture parsing and empty response handling.
  * Added `bainvilleschool.com` and `cji.k12.mt.us` to `.github/copilot-allowlist.txt` ensuring complete firewall allowlist compliance in `test-copilot-allowlist.R`.
  * Added all 3 districts to DLI district mapping invariant exclusions in `tests/testthat/test-salary-scrapers.R`.
  * Updated `DISTRICT_BACKLOG.md` marking Bainville, CJI, and Marion as adopted.

---

## 4. Key Architectural Contracts & Invariants

1. **Pipeline / Dashboard Decoupling:**
   * `Mt_ED_Jobs.Rmd` is the sole pipeline entry point; it scrapes, munges, and saves derived CSVs to `Mt_Ed_Jobs/`.
   * `Mt_Ed_Jobs/app.R` is the Shiny dashboard reading committed CSVs. It **never** scrapes live pages.
2. **Posting Identity Contract (`Posting_ID`):**
   * Assigned once prior to deduplication, longitudinal accumulation, or spell calculations.
   * Uses real per-posting URLs when available; falls back to `title + location + date_posted` with an occurrence suffix.
3. **Schema Integrity:**
   * Every CSV consumed by `app.R` must be registered in `REQUIRED_SCHEMAS` inside `schema_check.R` and tested in `test-schema-check.R`.
4. **Posit Connect Cloud Manifest Safety:**
   * Empty lists in R become `{}` in JSON via `jsonlite::toJSON()`, which Connect Cloud rejects. Post-processing in `regenerate_manifest.R` forces `metadata` and `users` to `null`.

---

## 5. Active & Upcoming Workstreams

- [x] Port `NCES_LEAID` universal identifiers to Montana registry and data layers.
- [x] Port Vacancy Spells & Time-to-Fill interactive tab to `Mt_Ed_Jobs/app.R`.
- [x] Harmonize attribution to Mike Bostick & Mark Perkins.
- [x] Eradicate `bind_rows` date collision errors across all heuristic scrapers.
- [x] Add pipeline dry-run and AST linting tests to CI test suite.
- [x] Incorporate October 27 weekly scrape output into refreshed `job_duration_spells.csv` (390 total spells; 217 active, 173 closed).
- [x] Mock `Sys.sleep()` during unit tests in `test-misc-district-scrapers.R` reducing test run time from 416s down to 6.7s.
- [x] Create reproducible generator script `scripts/generate_job_duration_spells.R`.
- [x] Create Higher Ed vacancy duration spells panel (`he_job_duration_spells.csv`) and `he_spells` dashboard tab.
- [x] Expand Montana K-12 coverage backlog (Batch 21: Frontier, Saco, Ulm adopted; Brockton drift recovered; Group 3/10 triaged).
- [x] Harden interactive Vacancy Spells modules against empty filter states and regularize duration distribution bins.
- [x] Enable 1-click drill-down navigation from Homepage top hiring employers tables to filtered jobs tables.
- [x] Add Higher Ed weekly vacancy series downloads and codebook definitions.
- [x] Add spell panels to automated data-quality invariant suite.
- [x] Triage Golden Ridge and Grant in district coverage backlog.
- [x] Streamline sidebar navigation into consolidated tabBoxes (10 main tabs).
- [x] Implement Head-to-Head District and College Comparator modules.
- [x] Multi-dimensional map filtering (salary tiers, county cluster, posting volume/urgency) with dynamic count badge and auto-zoom.
- [x] 100% data dictionary column coverage and automated codebook invariant test suite.
- [x] Expand Montana K-12 coverage backlog (Batch 22: Montana City, Denton, Clancy adopted; Group 3 triaged to Group 8).
- [x] Recover Columbia Falls School District 6 from silent coverage failure (RedRover migration) and modernize RedRover parser.
- [x] Expand Montana K-12 coverage backlog (Batch 23: Bainville, CJI, Marion adopted; 194 -> 197 districts).
- [ ] Expand Montana K-12 coverage backlog (Batch 24: next active vacancy districts).
