# Montana Education Jobs Dashboard — Project Progress Ledger

**Maintainers & Authors:** Mike Bostick  
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
| **Geographic Leaflet Map** | Implemented | Implemented | **Full Parity** | Interactive position/subject keyword search ("special ed", "mathematics"), suggestion chips, dynamic radius scaling, layer controls (Positron, OSM, Esri Topo), and cluster pins. |
| **Data Sources & Codebook Tab** | Implemented | Implemented | **Full Parity** | Direct CSV download buttons and interactive schemas. |
| **Federal NCES LEA IDs** | Embedded (48/48) | Embedded (200/200) | **Full Parity** | 7-digit `NCES_LEAID` in registry, `salarymap2.csv`, and `job_duration_spells.csv`. |
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
  * Standardized citations and footer attribution across `Mt_ED_Jobs.Rmd`, `Mt_Ed_Jobs/app.R`, and `DATA_DICTIONARY.md` (later changed to Mike Bostick as sole Montana author; see the 2026-10-29 terminology/attribution entry below).

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
  * Synchronized [`DATA_DICTIONARY.md`](file:///Users/mikebostick/repos/Jobs_Dash_repos/Montana-Education-Jobs-Dashboard/DATA_DICTIONARY.md) markdown codebook with complete markdown tables and universal identifier definitions (`NCES_LEAID`, `IPEDS_UNITID`).
* **Automated Codebook Invariant Test Harness:**
  * Created [`tests/testthat/test-data-dictionary.R`](file:///Users/mikebostick/repos/Jobs_Dash_repos/Montana-Education-Jobs-Dashboard/tests/testthat/test-data-dictionary.R) enforcing:
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

### Milestone 13: K-12 District Coverage Expansion — Batch 24 (Frenchtown, Lima, Townsend Recovery) (2026-10-28)
* **Direct Pipeline District Adoption & Silent Drift Recovery:**
  * Adopted 2 new Montana K-12 districts into `k12_district_registry.csv`, expanding direct coverage from 197 to 199 districts (approaching 100% full K-12 coverage):
    - **Frenchtown K-12 Schools** (`NCES_LEAID`: `3011520`, Missoula County, Frenchtown): Major Missoula-area K-12 district running Apptegy behind Fastly. Navigated seamlessly via headless Chromote in `fetch_apptegy_k12_postings()`. Extracted 6 active vacancies (`School Nurse Substitute`, `Classified Substitutes Kitchen, Parprofessionals, Office`, `Softball .5 Assistant Coach`, `Substitute Bus Drivers`, `Substitute Teachers`, `Counselor Grades 3-5`).
    - **Lima School District #12** (`NCES_LEAID`: `3016710`, Beaverhead County, Lima): Southern Beaverhead rural K-12 district running Apptegy with job announcements published via Thrillshare Live Feeds API (`/api/v2/s/107780/live_feeds`). Extracted 3 active vacancies (`Lead Custodian`, `Lead Maintenance Worker`, `Transportation Director/Lead Bus Driver`).
    - **Townsend School District** (`NCES_LEAID`: `3004980`, Broadwater County, Townsend): Modernized `parse_townsend_postings()` to accommodate CMS heading punctuation change (hyphen instead of colon) and retired `ATHLETIC DIRECTOR` stop marker while filtering multi-line description continuation fragments. Restored 4 active vacancies (`Head HS Girls Tennis Coach`, `Assistant HS Speech and Drama Coach`, `Elementary Special Education`, `Custodian/Light Maintenance`).
  * Total active vacancies adopted/recovered across Batch 24: **13 positions**.
* **Test Fixture & Firewall Invariant Suite:**
  * Added 3 fixtures to `tests/testthat/fixtures/`: `frenchtown_employment_rendered.txt`, `lima_live_feeds.json`, and `townsend_jobs_rendered.txt`.
  * Expanded shared Apptegy session test in `tests/testthat/test-misc-district-scrapers.R` to 47 districts (+6 rows for Frenchtown = 271 total rows).
  * Added dedicated unit tests for `parse_frenchtown_postings()` (6 rows extracted and empty response), `parse_lima_postings()` (3 rows extracted and empty response), and `parse_townsend_postings()` (modernized layout 4 rows extracted).
  * Added `ftsd.org`, `limaschoolmt.org`, and `thrillshare-cmsv2.services.thrillshare.com` to `.github/copilot-allowlist.txt`.
  * Added `Frenchtown K-12 Schools` and `Lima School District #12` to DLI district mapping invariant exclusions in `tests/testthat/test-salary-scrapers.R`.
  * Updated `DISTRICT_BACKLOG.md` marking Frenchtown and Lima as adopted and logging Townsend under Group 11 (Platform Drift Recoveries).
  * Wired Bainville, CJI, Marion, and Lima heuristic scrapers into `Mt_ED_Jobs.Rmd`.

### Milestone 14: Categorization Engine Overhaul & Modernized UX Navigation (2026-10-28)
* **Categorization Engine & Precedence Overhaul:**
  * Executed comprehensive audit and overhaul of `classify_k12_position()`, `classify_k12_subject()`, `classify_he_job_type()`, and `classify_he_faculty_category()` across both Montana and Wyoming:
    - **Precedence Audit:** Prioritized Clerical (`Secretary`, `Clerk`, `Registrar`) before `Teacher`, routed paraprofessionals (`Teacher Assistant`, `Teaching Assistant`, `Instructional Assistant`) to Paraprofessional instead of inflating Teacher counts, and prioritized Higher Ed Provost/administrative appointments (`Faculty Affairs`, `Faculty Development`, `Faculty Director`) before faculty classifications.
    - **Discipline Accuracy Fixes:** Fixed severe misclassification bugs where `Zoology` was erroneously routed to `Broad_Category == "Specialist"`, `Political Science` and `Social Sciences` were misrouted to `Science`, and `Health Science`/`CNA` were misrouted to general science.
    - **Broadened Subject Coverage:** Expanded rules for `Elementary Education` (`K-[1-6]`), `English Language Arts` (`Intervention Teacher`), `Language Education` (`Culture Teacher`), `Substitute Teaching` (`Guest Teacher`), `Health Science` (`CNA`, `Certified Nursing Assistant`), and Higher Ed faculty fields (`leadership fellows`, `financial planning`, `family financial`, `iv&v`, `verification & validation`).
  * Rebuilt historical and current datasets from durable archives, slashing uncategorized postings across both states:
    - **Montana Higher Ed:** Uncategorized postings dropped from 933 (38.7%) down to **83 (3.4%)** (96.6% categorized).
    - **Montana MSU (Bozeman):** Uncategorized dropped from 580+ (35%+) down to **30 (1.8%)** (98.2% categorized).
    - **Montana K-12:** Uncategorized dropped from 382 (11.0%) down to **86 (2.5%)** (97.5% categorized).
    - **Wyoming Higher Ed:** Uncategorized dropped from 3,522 (18.6%) down to **2,576 (13.6%)** (86.4% categorized).
    - **Wyoming K-12:** Uncategorized dropped from 1,068 (8.1%) down to **518 (3.9%)** (96.1% categorized).
    - **Combined Impact:** Recovered and accurately categorized **2,642 job postings** across MT and WY previously lost in generic or misclassified buckets.
* **Shiny Dashboard UI/UX Overhaul:**
  * **Simplified Information Architecture:** Restructured sidebar navigation to eliminate ambiguous labels like "Profiles & Compare" in favor of clear, intuitive domain entities: `Home`, `Map`, `All Postings`, `Districts` / `Colleges & Universities`, `New Postings`, `Current Trends`, `Longitudinal Trends`, `Data`, `Report Mistake`.
  * **1-Click Quick Filter Toolbar:** Added an instant filter button bar (`radioGroupButtons`: `[ 📋 All Active Postings ]` | `[ 🟢 New This Week ]`) directly above the primary DataTables on both K-12 and Higher Ed postings pages, matching modern job board patterns (LinkedIn, Indeed).
  * **Elimination of Nested Sub-tabs:** Removed inner `tabBox` views inside the Current Trends pages in favor of dedicated, flat navigation cards.
  * **Responsive Table Containment:** Implemented modern `.trends-table-container` CSS bounding table widths to `980px`, adding clean borders, auto margins, styled headers, and fixed-width sparkline columns, eliminating horizontal table sprawling and whitespace overflow.
  * **Dedicated New Postings Tabs:** Implemented dedicated `k12_new` and `he_new` sidebar views for users specifically auditing weekly incoming volume.
* **Test Suite Verification & Parity:**
  * 100% test pass rate in Montana (`3,051 PASS, 0 FAIL, 0 WARN`).
  * Regenerated Connect Cloud manifest (`rsconnect::writeManifest()`).

---

## 4. Key Architectural Contracts & Invariants

1. **Pipeline / Dashboard Decoupling:**
   * `Mt_ED_Jobs.Rmd` is the sole pipeline entry point; it scrapes, munges, and saves derived CSVs to `Mt_Ed_Jobs/`.
   * `Mt_Ed_Jobs/app.R` is the Shiny dashboard reading committed CSVs. It **never** scrapes live pages.
2. **Posting Identity Contract (`Posting_ID`):**
   * Assigned once prior to deduplication, longitudinal accumulation, or spell calculations.
   * Uses real per-posting URLs when available (AppliTrack via its job ID since 2026-11-03); falls back to `title + location + date_posted` with an occurrence suffix.
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
- [x] Expand Montana K-12 coverage backlog (Batch 24: Frenchtown, Lima adopted; Townsend drift recovered; 197 -> 199 districts).
- [x] Overhaul K-12 and Higher Ed categorization engine: eliminate misclassifications (Zoology, Pol Sci, Health Sci), audit precedence (clerical before teacher, paraprofessional before teacher, provost/admin before faculty), and expand subject coverage recovering 2,642 previously uncategorized jobs.
- [x] Modernize dashboard UX navigation: clear tab titles (`Districts`, `Colleges & Universities`), flat Current Trends layout without nested tabs, 1-click `🟢 New This Week` filter button, and responsive table container styling.
- [x] Comprehensive 8-dimension data quality audit & historical archive reprocessing across MT & WY:
  * Full reprocessing from raw historical archives back to first scrape date (`rebuild_k12_history_from_archive.R` and higher ed rebuilds) propagating classification fixes across all historical time-series datasets (`allsum.csv`, `k12jobanalysis.csv`, `facultydata.csv`, `job_duration_spells.csv`).
  * Repaired text encoding / HTML entity leakage (`&amp;`, `&quot;`, `&#39;`, `&lt;`, `&gt;`, `&nbsp;`) in job titles.
  * Resolved non-instructional role precedence leaks: bare `Clerk` (Attendance, Records, Library Clerk) routed to `Staff` ahead of `Teacher`; `Library/Media Assistant` to `Paraprofessional`.
  * Expanded discipline coverage: Arapaho/Arapahoe language, Drama/Theatre in Art, Choir/Chorus/Vocal in Music, Trade & Technical, Autism/ASD in SPED, Grade 1-7 primary grades.
  * Repaired state DLI OCR compensation artifact in `salarymap2.csv` (Philipsburg 10th percentile salary clamped `< 15000` to `NA`).
  * 100% test pass rate across both MT (3,051 tests) and WY (1,424 tests).
- [x] Streamline dashboard navigation architecture across K-12 and Higher Ed:
  * Promoted **Vacancy Spells** to a dedicated top-level sidebar tab for both K-12 (`k12_spells`) and Higher Education (`he_spells`) featuring 4 KPI ValueBoxes, duration distributions, and searchable spell listings.
  * Unified **Current Trends** and **Longitudinal Trends** into a single cohesive **Trends** tab (`k12_trends`, `he_trends`) using a clean top-level `tabBox` with two panels: Current Snapshot (12-week sparklines and discipline breakdown) and Longitudinal Trends (multi-year timeline slider and interactive Plotly time series).
  * Retired redundant standalone "New Postings" sidebar tab, relying on the 1-click `🟢 New This Week` quick-filter toggle in the main postings tables. Preserved reactive server endpoints (`output$k12_new_table`, `output$he_new_table`) for backwards compatibility.
  * Standardized sidebar navigation into exactly 4 symmetrical items per education tier:
    - K-12 CAREERS: `All Postings`, `Districts`, `Trends`, `Vacancy Spells`
    - HIGHER EDUCATION: `All Postings`, `Colleges & Universities`, `Trends`, `Vacancy Spells`
  * 100% test pass rate across both MT (3,051 tests) and WY (1,424 tests).
- [x] Refine public-facing terminology, attribution, and sidebar proportions:
  * Montana attribution: Confirmed Mike Bostick as sole creator/maintainer for Montana across UI footer, citation, and pipeline documentation.
  * Public-friendly language: Replaced technical jargon like "scraped" / "directly-scraped" with clean phrasing ("tracked", "monitored", "compiled", "weekly updates") across District/Institution directories, map descriptions, and Vacancy Spells modules.
  * Single-word navigation clarity: Renamed tabs to concise, intuitive terms (`Jobs` for postings, `Colleges` for institutions, `Time-to-Fill` for duration metrics, `Feedback` for bug reporting).
  * Narrowed sidebar container: Reduced sidebar width from default 230px to 180px (`width = "180px"`, `titleWidth = "180px"`), eliminating empty void space after tab labels and giving 50px more width to data tables and maps. Streamlined category headers to `K-12`, `HIGHER ED`, and `COMMUNITY`.
- [x] Expand Montana K-12 coverage backlog (Batch 25: Savage adopted; Joliet re-anchored to real Montana district; Bozeman & Polson recovered from platform drift; 199 -> 200 districts):
  * **Savage Public Schools** (Richland County): Adopted via Apptegy embedded-JSON architecture (`decode_apptegy_pagebuilder_nodes()`); 8 active positions (Elementary Teacher, 6-12 History, K-12 Music, K-12 Counselor, 2 Paras, 3 Coaches); hits 200 registered districts!
  * **Joliet Public School District 86** (Carbon County): Replaced stale Illinois SD86 TedK12 link with real Montana district board (`jolietschools.org`, `JolietHeuristic`); 5 active positions (Bus Driver, Subs, 3 Coaches).
  * **Bozeman Public Schools** (Gallatin County): Recovered from silent platform drift (AppliTrack HTTP 500 failure -> Tyler Portico `bozemanschooldistrict7mt`); restores 46 active job openings to direct pipeline.
  * **Polson School District** (Lake County): Recovered from silent platform drift (SchoolSpring returning 0 -> Tyler Portico `polsonschooldistrict23mt`); restores 3 active job openings to direct pipeline.
  * Captured live fixtures (`savage_jobs.html`, `joliet_jobs.html`) with unit tests in `test-misc-district-scrapers.R` and `test-tylerportico-scraper.R`.
  * Total suite: 3,080 tests PASS (0 failures, 0 warnings).
- [x] Full Montana K-12 and Higher Ed Statewide Saturation & Infrastructure Audit (Batch 26):
  * **Arrowhead Elementary School District #75** (Park County): Recovered from Cloudflare HTTP 520 server failure caused by obsolete hardcoded Windows Chrome User-Agent header; restored 3 active positions to the direct pipeline.
  * **Manhattan School District** (Gallatin County): Probed live Tyler Portico tenant migration to `manhattanpublicschoolsmt.employeeaccess.tylerapp.com/resident/api/Positions`; verified clean empty array `[]` handling (0 vacancies).
  * **Comprehensive Shared ATS Audit (100% Green across all 59 platforms)**:
    - 23 AppliTrack districts: 100% active, 313 live vacancies (Billings, MCPS, Great Falls, Helena, East Helena, etc.).
    - 9 SchoolSpring districts: 100% active, 112 live vacancies (Belgrade, Whitefish, Lewistown, Laurel, Ronan, Libby, Bridger, Red Lodge, Target Range).
    - 2 TedK12 districts: 100% active, 12 live vacancies (Hardin, Glasgow).
    - 6 TylerPortico districts: 100% active, 117 live vacancies (Bozeman, Butte, Polson, Kalispell, Cascade, Manhattan).
    - 23 Higher Education institutions: 100% active, ~340 live vacancies (MSU, UM, Montana Tech, FVCC, Miles CC, Dawson CC, tribal colleges).
  * **Heuristic District Scrapers Audit**: 112/112 heuristic district scrapers verified live (91 active returning postings, 21 cleanly returning 0 on empty boards, 0 errors).
  * **Statewide Candidate Universe Saturation Analysis**:
    - Deep-probed all 33 High School / K-12 candidate districts from the OPI master target list (< 4000): 14 covered in registry, 4 Google Drive blocked (Troy, Plains, Eureka, Harrison), 1 OCR deferred (Box Elder), 2 redirect to OPI (Rosebud, Dodson), 12 verified generic blank forms only or zero vacancies (Absarokee, Fairfield, Geraldine, Harlowton, Medicine Lake, Ryegate, Twin Bridges, Willow Creek, Winifred, etc.).
    - Triaged candidate districts: Fairfield (`fairfield.k12.mt.us/o/district/browse/51027`, only generic PDFs -> Group 8), Troy (`troyk12.org/documents/...`, Google Drive folder `1CdUiMRs63JU5xLbNkLaJ1r3HndXnnQpS` -> Group 6 BLOCKED), Absarokee (`absarokeesdmt.sites.thrillshare.com`, all document links to Google Drive -> Group 6 BLOCKED), Somers Lakeside #29 (HR folder contains only CBAs and generic application link -> Group 8), Blue Creek School (employment folders empty -> Group 8).
    - Confirmed full saturation: virtually all active K-12 teaching and staff vacancies statewide in Montana are now monitored by direct scrapers in the 200-district registry or captured via the OPI statewide redundancy feed.
  * Total suite: 3,080 tests PASS (0 failures, 0 warnings).
- [x] Interactive Leaflet Map Position & Keyword Search with Suggestion Chips and Multi-Basemap Controls:
  * **Interactive Keyword / Subject Search**: Added instant full-text query matching (`match_job_query`) supporting compound terms, educational abbreviations ("special ed", "sped", "math", "pe", "cte"), and multi-word token matching across both K-12 and Higher Education postings.
  * **Dynamic Employer Filtering & Marker Scaling**: Map marker locations automatically filter to only employers with active matching openings, dynamically scaling circle marker radius proportional to matching vacancy counts.
  * **Rich Contextual Tooltips & Popups**: Hover tooltips and click popups highlight matching position counts, listing sample matching job titles alongside total vacancy counts and median salaries.
  * **Dynamic Feedback Badging**: Added real-time count badge above the map displaying exact matching openings, matching locations, and active query terms (with red guidance badge when 0 matches found).
  * **Instant Suggestion Chips**: Integrated 1-click filter chips for popular subject areas (`Special Ed`, `Mathematics`, `Elementary`, `Science`, `Music / Art`, `Bus Driver`, and `Clear`).
  * **Multi-Basemap Layer Control**: Added interactive tile layer switcher offering CartoDB Positron (clean default), OpenStreetMap, and Esri World Topo Map.
  * Total suite: 3,127 tests PASS (0 failures, 0 warnings, 2 skips).
- [x] Post-review fixes (2026-10-29):
  * **Position classifier regressions from the precedence overhaul** (`classify_k12_position()`, identical in MT and WY): bare `Intern` matched inside "Internal Applicants Only" (teacher and bus-driver postings landed in Support Services); `Technician` was checked ahead of Custodial/Transportation/Food Services (cafeteria, maintenance, HVAC, facility technicians); `Director`/`Driver` ahead of Teacher sent "Band/Choir Director" to Administration and "Drivers Education Teacher" to Transportation. Fixed with a word-bounded `\bIntern\b`, a separate late Technician rule, and an early Teacher rule for ensemble directors and Drivers Ed; regression tests added in `test-k12-classification.R`. K-12 history and `job_duration_spells.csv` rebuilt from archive.
  * **OPI Central Safety Net narrowed to a real fallback**: `apply_opi_district_fallback()` previously relabeled every matchable OPI row (358 of 396 on the 2026-10-27 data, 311 of them onto districts whose direct scrape was working), feeding OPI rows into the registry-backed district counts, map and vacancy rates and double counting differently worded duplicates. It now relabels only for districts with no direct rows this run (39 of 396 on the same data), matches the longest district name first (East Helena no longer maps to Helena; "Independent School - Billings" no longer maps to Billings Public Schools), and no longer hands a shared-city posting to whichever same-city district happens to be empty (Missoula -> DeSmet).
- [x] Categorization & research-download data-quality audit (2026-10-30):
  * **One shared classifier for both states.** The Higher Ed job-type and faculty-category functions had drifted between MT and WY (different rule order, Legal checked before Criminal Justice in WY); they are now identical in both repos, with each state's extra rules folded in.
  * **K-12 position:** OPI Jobs for Teachers publishes its subject-area field as the title ("Elementary Curriculum", "Special Education", "Music"), so those teaching postings landed in Other. Titles that name only a subject or grade now classify as Teacher unless they name an assistant/advisor-type role. Also: `\bPara`/`\bSub` word boundaries, nurses and counseling after Teacher/Staff/Admin, and new keywords for guards, noon duty, grounds, superintendents, stipend sports, and kitchen staff. Other fell from 10.9% to 1.8% of archived K-12 rows; uncategorized teacher subjects are 1.5%.
  * **K-12 subject:** bare "CTE" moved to the last-checked CTE bucket so "CTE – Agricultural/Business/FCS" reach their subjects; "Physical Ed", "Health Enhancement", "Reading", "World Languages", "Industrial Technology" and the "Special Educaiton" typo now match.
  * **HE:** "latin" matched inside "Gal**latin** College" (every Gallatin pool landed in Language) and "ems" inside "Syst**ems**" (Information Systems faculty in Health Sciences); bare "Instructional" counted technologists, designers and campus child-center aides as faculty. HE job-type Other fell from 17.2% to 1.6% (MT) and 5.9% to ~0% (WY); WY uncategorized faculty fell from 13.6% to 3.7%.
  * **Placeholder postings dropped** via shared `is_placeholder_posting()` in the pipeline and rebuild scripts: "Sample/Future Certified/Classified Position", account-creation templates, "Student Teaching Opportunities", "No open positions", a scraped "Job Title" header (EWC). Standing applicant pools are kept. Raw archives are unchanged.
  * **Vacancy spells:** a same-title posting absent for more than 21 days now starts a new spell (WY had 244 merged re-postings with a median "duration" of 382 days); `Weeks_Observed` counts calendar weeks rather than scrape dates.
  * **MT `salarymap2.csv`:** the read-back + registry join emitted `NCES_LEAID.x`/`.y` (a third copy would follow next run); collapsed to one `NCES_LEAID` and fixed at the source.
  * **District name variants:** MT OPI location labels normalized ("BILLINGS" / "Billings, MT" → "Billings"); WY "#21" / "No.1" spellings canonicalized.
  * Regression tests added for every fix; histories and spells rebuilt from archive.
- [x] WY weekly run fix (2026-10-30): the weekly salary chunks now keep `IPEDS_UNITID` and no longer duplicate the CCD
  columns (`.x`/`.y`). Both had been introduced by Oct 27 hand-edits to the committed CSVs that the pipeline didn't
  reproduce. Verified with full local rehearsals of both weekly workflows.
- [ ] Posted pay from the job posting itself (in progress):
  * [x] Increment 1: shared `extract_posted_pay()` (amount/range, unit, source snippet; never converted between units).
    AppliTrack postings carry `Pay_Min`/`Pay_Max`/`Pay_Unit`/`Pay_Text` into `combinedclean.csv`, with a "Posted Pay"
    column in the Jobs table. About 91% of sampled live AppliTrack postings state an amount.
  * [x] Increment 2 (2026-10-30): RedRover boards carry Pay_* (the board's own `$` line, read by `extract_posted_pay()`).
  * [x] Increment 3 (2026-10-30): higher ed. isolved Hire (structured min/max), Paycom (each posting's `salaryRange`,
    one detail request per posting) and University of Montana's NEOGOV board (pay line from its schooljobs.com listing,
    joined by job ID) carry Pay_* into `hedata.xlsx` and the raw HE archive, with a "Posted Pay" column in the Higher Ed
    Jobs table. Live 2026-10-30: BFCC 5/6, UM 44/58, FVCC 16/31 (the gap is adjunct postings, which state no pay).
    `facultydata.csv` keeps its schema (no Pay_*). `extract_posted_pay()` now also skips a benefits package's stated
    value ("Worth ~$25K") and a `$0.00` blank pay field.
  * [x] Pay-coverage monitor (2026-10-31): `check_pay_coverage.R` (non-blocking weekly step, in the monitoring
    self-check) flags a source whose postings still arrive but whose share with stated pay fell to <=20% of its own
    average (needs 2+ archived weeks with pay, avg share >=40%, 3+ postings), into the weekly drift issue. Pure logic
    in `drift_check.R` (`flag_pay_coverage_drop()`), tested.
  * [x] Map pay filter rebuilt on posted pay (2026-10-31): "Pay" bands in each posting's own unit (hourly: under $18 /
    $18-25 / $25+; annual: MT under $50k / $50-60k / $60k+, WY under $60k / $60-70k / $70k+), nothing converted. A posting
    counts by its posted pay (range midpoint), else its district/institution role figure, else the estimate below; day
    rates and stipends only under "All". The band narrows each dot to its matching postings, and "View N matching jobs"
    carries it to the Jobs tab.
  * [x] BLS OEWS fallback (2026-10-31): `bls_oews_scraper.R` (shared) pulls May-2025 regional medians for 17 school roles
    via the BLS API (bls.gov downloads refuse scripts), refreshing `oews_role_wages.csv` only when BLS publishes a new
    year. Each K-12 posting gets `Est_*` from its district's county area (statewide where unknown or suppressed); coaches
    get none. Jobs table: "Typical pay (BLS est.)" with role/area on hover, shown only where no pay is posted.
  * [x] IPEDS staff fallback (2026-10-31): `ipeds_staff_salaries.R` (shared) -- each college's average pay for full-time
    non-faculty staff by IPEDS category; HE staff postings get `Est_*` by title -> category. HE Jobs table: "Typical pay
    (IPEDS est.)".
  * [x] QCEW county context (2026-10-31): `qcew_school_pay.R` (shared) -- average pay of public school employees by
    county (all roles), shown in the district map popup.
  * [x] Hourly-pool, work-study, student and intern postings no longer get an annual IPEDS figure (shared
    `is_salaried_staff_posting()`, 2026-10-31); "Executive Assistant" is office support, not management.
  * [ ] Declined: ACS county earnings (less specific than QCEW for the same question).
  * [x] OPI detail pages (2026-10-31): `fetch_opi_statewide_postings()` opens each posting's detail postback (~0.75 s each,
    ~5 min/week, capped at 15 min) and reads its description's pay; ~25% state one. District housing costs ("apartments
    starting at $350 per month") are now excluded by `extract_posted_pay()`. The detail view also names the posting's
    real district (`parse_opi_job_details()`), not yet used.
  * [x] Pay data-quality safeguards (2026-11-01, both states). Posted amounts out of range for their unit
    (`PAY_PLAUSIBLE_RANGE`) are blanked before they reach the dashboard (`drop_implausible_pay()`); the raw archives
    keep them, and the weekly drift issue lists them. Extractor no longer reads application costs, money paid into a
    benefits package, or loan-assistance lists as pay (real misreads from the 10-31 rehearsal). Reference tables behind
    the estimates (OEWS, QCEW, IPEDS staff pay, OPI district counties) refresh through `write_reference_file()`, which keeps
    the old file when a download is partial, mostly blank or out of range, and logs each refresh to `scrape_log.csv`;
    `check_salary_drift.R` reports failed, rejected, missing or stale refreshes. Schema check and the blocking
    data-quality sweep cover the new files and the Pay_*/Est_* columns.
  * [x] Pay extractor fixes (2026-11-01, both states): a unit run into the next label ("$145/dayBENEFITS",
    "$21.69/hrThe District") is read as day/hour, and an earlier amount's bonus wording no longer vetoes a salary
    after it ("Signing bonus $1,000, $42,000 annual salary").
  * [x] OPI district aliases (2026-11-01): `OPI_DISTRICT_ALIASES` gives five job-board names the finance file spells
    differently (Broadview K-12, Ophir K-12, St. Ignatius HS, Phillipsburg HS, Sanders County Ed Services Coop) their
    county, so their postings get a local OEWS area.
  * [x] Ennis scraper (2026-11-01): a "Summary:" line between the title and "Reports to:" was taken as the title.
    Checked and left alone: Swan Valley #3's long title is the district's own heading for its one posting; Swan River
    #4's $16,900 10th-percentile teacher pay is DLI's published figure (9 teachers, NorthWest report).
  * [x] Classification audit (2026-11-01, both states; shared classifier). Every archived title since Oct 2025 checked
    against its bucket. K-12: new "Activities/Extracurricular" bucket (FFA/FBLA/DECA/HOSA advisors, drama, the musical,
    speech & debate, robotics, color guard, student council; cheer stays Athletics); every substitute posting is
    Substitute (substitute paras were Paraprofessional); coach/kitchen/bus aides go to Athletics/Food Services/
    Transportation instead of Support Services; "Teacher Aide" is Paraprofessional; bare "Aid" no longer matches inside
    "Paid" and "Para" no longer matches "Paradise Valley"; janitors, LPNs, accountants, district IT staff and
    grade-band-only titles ("Junior High 7-8") leave Other; "None at this time" is a placeholder. HE: faculty
    applicant pools are Adjunct/Part-Time; postdocs and research scientists are Research & Science; custodians are
    Maintenance & Service; UW "Hourly Pooled - <job>" is classified by the job (student/intern jobs are Student
    Positions). Spells `is_support_staff` now includes Transportation and Food Services, as documented. Committed
    combinedclean (position, and Est_* on changed rows) and the teacher/faculty histories, aggregates and spells
    reclassified; raw archives unchanged. Tests: test-classification-misroutes.R (identical in both repos).
  * [x] Scrapers (2026-11-01): Florence-Carlton reads its new "Job Title:" line (it had emitted "FULL TIME. MON -
    FRI." and "YEAR-ROUND POSITION." as postings and missed the custodian job); Plevna's level-only coaching lines get
    the sport from their header ("Track Coach - High School - Head"). Real fixtures dated 2026-11-01.
  * [x] OPI vs. direct scrapes (2026-11-02, MT): the direct scrape wins and only one source counts a district in a
    week (`opi_reconcile.R`). `mt_district_crosswalk.csv` (NCES CCD, ~391 districts, refreshed each run) ties each
    public district to the registry district whose board covers it (NCES id, same-town elementary/HS pair, or a
    one-district town's high school) or to none. OPI postings at a district we scrape are dropped (a matching
    direct posting -- same district, position, subject -- gets `Also_On_OPI`; the rest go to
    `mt_discrepancy_report.csv`); OPI fills in for a registry district whose scrape returned nothing; postings at
    districts we don't scrape count under one name per town and get a map dot with CCD/DLI/SAIPE/finance/ACS
    context (`opi_only_districts.csv`). Raw archive keeps every OPI row (`OPI_Counted`). New weekly drift-issue
    section "OPI cross-check" (`check_opi_crosscheck.R`): possible scraper misses by district, empty scrapes,
    adoption candidates with OPI's website and DISTRICT_BACKLOG.md status. History recomputed in place
    (`scripts/reconcile_opi_history.R`): K-12 totals ~1,466 -> ~1,148 for 10-27, ~250-330 less per week since
    Aug 11. Replaces `remove_opi_direct_duplicates()` / `apply_opi_district_fallback()` and the app's town crosswalk
    (which had shown e.g. Harlem's teacher salary on North Harlem Colony postings). Tests: test-opi-reconcile.R.
  * [x] Manhattan School District (2026-11-02): registered as Tyler Portico (manhattanpublicschoolsmt), but that
    tenant is only the staff self-service portal; its Positions API returns an empty list, so every run since
    August returned 0 while OPI listed Manhattan openings (found by the new OPI cross-check). The district posts on
    its own Finalsite page (rollontigers.org/district/employment/current-openings): new `ManhattanHeuristic`
    scraper, one PDF link per posting, application forms dropped. 11 live postings. Fixture
    manhattan_current-openings_2026-11-02.html. Same check of the other empty-on-10-27 districts: Bozeman,
    Columbia Falls, Townsend were already recovered 10-28/29 (50, 26, 4 live); Seeley Lake has no current openings
    (OPI's three are May-June listings).
  * [x] OPI de-duplication moved to posting level (2026-11-03): the district-level rule dropped every OPI posting at
    a district we scrape, but 37 districts post their teaching jobs only on OPI (~75 postings) and about half of
    OPI's postings at districts whose board lists teaching jobs aren't on that board. Now an OPI posting is dropped
    only when `match_opi_postings()` (new `opi_matcher.R`) finds the same opening on the district's board; OPI's
    repeat listings (same district + description) count once. Matcher measured on 142 hand-labeled real postings
    (`test-opi-matcher.R`): untouched held-out set 17/18 duplicates found, 0 wrong-posting matches, 2/15 false
    matches; old matcher ~50% precision. Gemini scored 17/17, 0 false on the same set but was not adopted (user
    preferred deterministic; GitHub Models, the Copilot route, is retired). OPI fetch now keeps OPI_School and
    OPI_Description (archive only). History rebuilt from the raw archives (`scripts/reconcile_opi_history.R`, now
    a rerunnable rebuild): totals ~170-210 higher per week since mid-September than the district rule; past weeks
    match on OPI subject titles only and may include ~30/week OPI repeat listings. Trends tab notes the method.
  * [x] OPI matcher, full-sample round (2026-11-03): all 275 OPI postings at scraped districts judged by the
    matcher and Gemini; agreements spot-checked, disagreements hand-judged. Eight general fixes (role-less board
    titles, sport from description, "Title 1", business manager ~ clerk/administrative, school words, grade numbers,
    "recruiting/serve as" cues, SPED para ~ single generic para, director/coordinator, "Pre-School", board-named roles
    must be the OPI job's role). On the 13 confidently judged disagreements: 10 right (was 4; Gemini 9). Answer key
    148 cases: 77/78 found, 0 wrong-posting, 2/70 false. Exact key: Tyler Portico `code` now kept (`Job_Code`, raw
    archive only); an OPI description quoting it ("JP054494") matches that posting outright (Kalispell's long-term
    elementary sub). Follow-up noted: ~3/week stale OPI listings (Froid "start July 1, 2023") now count.
  * [x] Real posting dates, step 1 (2026-11-03, both states; ff92dc0): AppliTrack postings carry the board's own job
    ID (`parse_applitrack_output()` `job_id`); `url` is the posting's own page (`applitrack_posting_url()`), so
    AppliTrack rows use the stable per-posting URL identity instead of the title fallback and postings sharing a title
    stay apart. Parser fix: fields are read per `<li>`; a one-value "Position Type" used to swallow the next field and
    shift every later one (52 of 343 rows on 11-03 had no posted date and a "Date Available" text as location; earlier
    archives keep the shifted values). New `Close_Date` (combinedclean + raw archive, as written): AppliTrack
    "Closing Date"; Tyler `postingEndDate` only when real (Tyler fills open-ended postings with the fetch date plus a
    year; Bozeman sets its own school-year default, 2027-06-11, kept as written). The 11-03 week was moved onto the
    job-ID links and corrected from the live boards (342/343), so New This Week doesn't flag them. Fixture
    `applitrack_output_wy_teton_single_position_type.bin`. Full weekly rehearsal passed. Next: SchoolSpring
    posted/closing dates and filled/canceled status, OPI closing dates, PeopleAdmin open/close dates, then the
    coverage calendar and the spells rebuild (`claude-notes/2026-11-03_posting-dates-plan.md`).
  * [x] Real posting dates, rest of step 1 (2026-11-04, SchoolSpring + PeopleAdmin in both states, OPI MT only;
    e66ec72): SchoolSpring reads each posting's own record (`api.schoolspring.com/api/Jobs/<jobId>`, no
    login; `add_schoolspring_details()`): `Close_Date` is the deadline applicants see (the raw `closeDate` is UTC and
    "Posted until filled" is stored as 2050-01-01, so NA), `Job_Status` (posted/review/filled/canceled; raw archive
    only, always "posted" on the live board, for step 4) and posted pay from the board's own pay fields (none before;
    93 of 114 MT rows, 0 implausible; "Per Year" under $10k is a stipend, "Hourly and Certified Pay" read by amount,
    "Substitute" left without pay). `displayDate` stays the posted date (`postDate` is record creation). OPI: the
    grid's "Closing Date" (`opi_close_date()`; 362 of 366 "Open Until Filled" on 11-04). PeopleAdmin: the posting
    page's open date replaces the feed's `<published>` where filled in (it moves on re-publish; a Great Falls pool
    open since 2024-06-26 showed 2026-08-13), and new HE `Close_Date` in `hedata.xlsx` and the raw archive (not
    `facultydata.csv`; rebuild script and accumulator test drop it too). MSU Bozeman and Northern leave both date
    fields blank. Fixtures `schoolspring_job_*.json`; tests `test-peopleadmin-dates.R`. Full weekly rehearsal passed
    (first run caught the HE `Close_Date` reaching `facultydata.csv`). Next: SchoolSpring ending reasons for postings
    that left the board (step 4), coverage calendar, spells rebuild.
  * [x] Real posting dates, step 4 (2026-11-04, both states; 0c8b4c7): `refresh_schoolspring_endings()`
    (`direct_api_scrapers.R`) runs after the raw archive is written: every SchoolSpring job ID listed in the past
    year but not today is looked up (`fetch_schoolspring_details()`), and `schoolspring_endings.csv` (repo root,
    committed by the weekly workflow) keeps one row per ended posting: District, Title, board posted date,
    First_Seen/Last_Seen, `Job_Status`, Status_Since, Last_Checked. Filled/canceled are final, review is rechecked
    weekly, and a lookup still saying "posted" (our scrape missed a live posting) records nothing. First lookup:
    MT 99 postings that left Aug-Oct (62 filled, 17 canceled, 20 review), WY 504 (294 / 119 / 91). Districts use the statuses differently (MT Libby leaves all at review; WY Campbell County 1 closes 79 as
    canceled vs 8 filled), so a pooled filled share is not a calibration constant
    (`claude-notes/2026-11-03_posting-dates-plan.md`, "Step 4 findings"). Tests in
    `test-schoolspring-scraper.R`. Full weekly rehearsal passed.
  * [x] Real posting dates, step 2 (2026-11-04, both states; b9650e4): coverage calendar. `coverage_calendar.R` writes
    `coverage_calendar.csv` (repo root, committed by the weekly workflow) after the HE archive: one row per run per
    entity (registry districts/institutions, feeds, off-registry districts that log under their own name, anything
    tracked before) with ok / empty / error / not_logged, row count and error, so a posting that stops appearing
    counts as ended only when its source was healthy. Shared-board colleges take the parent board's row; postings
    that come only via a statewide feed take the feed's row; a run with no log leaves the calendar untouched. MT backfilled 2026-09-07 to 11-03 from the workflow's
    scrape-log artifacts (last run per date). It shows Arrowhead #75 at HTTP 403 on every CI run since 09-07.
    Bug fixed on the way: `log_scrape_result()` backslash-escaped quotes in error messages, which `read.csv` can't
    parse, so rows after such a message were lost (MT 11-03: all 23 HE sources), including in the drift checks; it
    now doubles quotes and `read_scrape_log()` repairs older logs. Tests `test-coverage-calendar.R`. Full weekly
    rehearsal passed (`claude-notes/2026-11-03_posting-dates-plan.md`, "Step 2 findings").
  * [x] Real posting dates, step 5, K-12 data layer (2026-11-04; 20d91b9): `posting_spells.R` +
    `scripts/build_posting_spells.R` (weekly, non-blocking) write `posting_spells_k12.csv` (one row per posting:
    start basis, first/last seen, how it ended, flags) and `posting_durations_k12.csv` (Kaplan-Meier, medians only
    with >= 20 endings) at the repo root. Built from the archives from 2026-08-18 on `Posting_ID`, with bridges for
    identity changes (AppliTrack's 11-03 job-ID move: false 10-27 endings 103 -> 56); start = board posted date when
    plausible; an ending counts only when the source was healthy the next run (`coverage_calendar.csv`), SchoolSpring
    endings from `schoolspring_endings.csv`, else censored; OPI subject rows, standing ads/pools, shared titles and
    left-censored starts are left out of durations. Delayed entry matters: plain KM 74.5 days, with entry at the age
    first seen 25.5 days (95% CI 23.5-30.5; 938 postings, 489 endings; Teacher 30.5). Read as "days listed", not
    time-to-fill. Full weekly rehearsal passed (`claude-notes/2026-11-03_posting-dates-plan.md`, "Step 5 findings").
  * [x] Real posting dates, step 5, HE data layer (2026-11-04; b0cd82e): `scripts/build_posting_spells.R` also writes
    `posting_spells_he.csv` and `posting_durations_he.csv` (all, all except MSU, by HE job type, by institution) from
    `Archived_HE_Data` from 2026-08-11 (the first run covering every institution). HE archives have no `Posting_ID`,
    so `add_he_posting_identity()` sets one: the per-posting link (PeopleAdmin, schooljobs, Paycom, isolved, ADP,
    applytojob, Rocky's opportunity pages, posting PDFs/DOCX), otherwise institution + title for the four colleges
    that link one employment page for every opening (Carroll, Miles, Salish Kootenai, Stone Child). Only posting
    documents and title IDs are bridged across runs (Aaniiih Nakoda re-uploads PDFs under new names); a new
    PeopleAdmin/schooljobs number is a new posting. Start = earliest plausible posted date (PeopleAdmin's feed date
    moves forward on re-publish); shared titles excluded only for title IDs; endings from the calendar's HE rows.
    Result: 879 postings, 605 in durations, 373 endings, median 21.5 days listed (95% CI 17.5-24.5); MSU is 360 of
    the 605 at 15.5 days, all others 30.5 (25.5-37.5); Faculty 31.5. The curve is flat across 50% (17.5-21.5 days),
    so quote the CI, not the point. Tests in `test-posting-spells.R`; full weekly rehearsal passed.
  * [x] Gallatin Gateway and Roberts (2026-11-04; 0314e56): Gallatin Gateway's page moved to `About-Us/Employment/`
    (old `/Employment/` 404 on the 11-03 run); registry and scraper default updated, fixture recaptured, live fetch
    returns its 3 postings. Roberts answers HTTP 200 with the bare text "site under maintenance", which `read_html()`
    took for a file path; `parse_roberts_postings()` now stops with that text, so the log says what happened (still
    an error: the source wasn't healthy, and its endings stay censored). Real body as fixture `roberts_maintenance.txt`. Full weekly rehearsal passed.
  * [x] Classification safeguards, items 7, 8, 10 (2026-11-04, both states; MT 410ac15): blocking checks in
    `test-weekly-data-quality.R`: every committed position / Category / Broad_Category (combinedclean,
    k12jobanalysis) and Job_Type / Category (facultydata) equals what today's classifier gives its title (so a
    classifier change must ship with reclassified data; 0 differences in MT or WY today); k12jobanalysis holds only
    Teacher rows, facultydata only the two faculty types (the old check allowed stale values); no placeholder title
    in combinedclean, k12jobanalysis, facultydata or hedata.xlsx; spell dummies agree with the position they encode.
    "Activities/Extracurricular" confirmed in the weekly data.
  * [ ] Add `Pay_*` to `hedata.xlsx` in `REQUIRED_SCHEMAS_XLSX` once the first weekly run writes it.

**Open work (moved here from claude-notes handoff, 2026-11-03; this list is the source of truth):**
- [ ] Real posting dates, rest of step 5: WY (K-12 and HE, same design, once its coverage calendar
  has a few weeks). Decide what, if anything, the Listing Duration tabs (paused 2026-11-02,
  `claude-notes/2026-11-02_spells-trust-audit.md`) show from `posting_durations_k12.csv` / `posting_durations_he.csv`,
  and when. Treat a
  board-wide default end date such as Bozeman's 2027-06-11 as no deadline. Optional step 3: daily presence check
  (42 structured-platform districts + OPI grid, ~50 requests/day) for day-precision ends.
- [ ] Roberts: site still "under maintenance" on 2026-11-04 (recheck after the 11-10 run; it now logs
  `Roberts returned a page with no HTML: "site under maintenance"`).
- [ ] Arrowhead Elementary #75 (decision needed): HTTP 403 on every weekly CI run since 2026-09-07
  (`coverage_calendar.csv`); the 2026-10-29 "recovered" entry only held from the Mac. The site is behind Cloudflare,
  which turns away GitHub's servers; the page itself is fine (at least 8 openings on 2026-11-04, none on OPI), so none of its
  postings reach the data. Not worked around on purpose: trying user agents or other endpoints to get past the
  block is circumventing the site's bot protection. Options: ask the district/web host to allow the scraper, run
  this one source from the Mac, or retire it from the registry and say so.
- [ ] OPI matcher against the 2026-11-10 run's fresh OPI data: sample matched/unmatched, extend the answer key
  (`tests/testthat/fixtures/opi_match_labels_2026-11-03.csv`; notes in `claude-notes/2026-11-03_posting-level-dedup.md`).
  Also: drift issue "Central Safety Net" (`summarize_central_safety_net()`) still calls counted OPI postings
  "fallback"; ~3/week stale OPI listings (descriptions naming only past school years, e.g. Froid 2023) count.
- [ ] Districts whose real board is OPI (19 checked 2026-11-03): mark "OPI is primary" so the adoption list only
  flags new ones.
- [ ] Classification safeguards (`claude-notes/2026-11-01_classification-safeguards-proposal.md`): 7, 8, 10 done;
  next 13 (reclassify script, now needed: item 8 fails the suite on any classifier change until the committed data
  is reclassified), then 5, 6, then 3.
- [ ] Title-shape bugs: Huntley Project "Bus Drivers- Must have a CDL...", Turner "Secretary - $14 per hour...",
  "Dish_Server_Cashiers 26".
- [ ] Rebuild scripts drift from the pipeline (they drop Est_*/OPI_District/Close_Date from combinedclean; don't run
  them straight into the repo; proposal item 12). Weekly-totals downloads: keep one snapshot per week (decided
  2026-11-02, latest snapshot wins; not built).
- [ ] `scripts/repro_scraper.R "Columbia Falls School District 6"` aborts in its fixture step (scraper itself works).
- [ ] Optional: Gemini as a shadow second opinion on OPI matches (QC report only; Mac key is free tier).
- [ ] Manual (repo Settings -> Copilot -> Internet access): rollontigers.org, schooljobs.com.

