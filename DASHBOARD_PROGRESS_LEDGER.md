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
  * [x] Classification safeguards, items 12 and 13 (2026-11-04, both states; MT 42ecd88): rebuild parity and a
    reclassify script. The K-12 rebuild bound every archive before applying the OPI rule per week, so older weeks
    got an all-NA `OPI_Counted` column, read as "counted": their OPI rows skipped reconciliation (all counted, under
    the raw town as District). Now `read_counted_archive_week()` (`opi_reconcile.R`) applies the rule one file at a
    time, and `build_k12_combinedclean()` / `build_k12_teacher_rows()` (`history_accumulator.R`) are shared by
    `Mt_ED_Jobs.Rmd` and the rebuild, which therefore carries OPI_District, Also_On_OPI, Close_Date and Est_*. The
    rebuild reproduces all nine committed K-12/HE files exactly; `.github/scripts/check_rebuild_parity.R` checks
    that weekly (non-blocking, into the drift issue). `k12_posting_panel()` had the same OPI bug: its OPI rows are
    now 811 (was 1,019) under real districts; non-OPI spells and the durations unchanged. `scripts/reclassify_committed_data.R`
    (dry run; `--apply`) rebuilds with the working-tree classifier after a guard that the HEAD classifier reproduces
    the committed data, reports every bucket move, writes the changed files in their committed row order and
    formats, and refreshes the spells. Tested on a scratch copy with a planted rule change (one Sidney posting
    Teacher -> Paraprofessional): diff = that row, its 18 history rows and their counts; data-quality sweep green.
    Full weekly rehearsal passed, and parity held on its fresh output (the appended week matched the rebuild).
  * [x] Classification safeguards, items 5, 6 and 3 (2026-11-05, both states; MT b45d465): title monitoring and a golden
    labeled set. `.github/scripts/check_title_quality.R` (weekly, non-blocking, into the drift issue; functions in
    `drift_check.R`): (5) title-shape lint of this run's postings per source -- level and rank with no role, schedule
    or detail sentences, field labels, markup, file names, blank or "Other" titles, over 200 characters, and pay
    stated in the title while Posted Pay is blank (`extract_posted_pay()` on the title; hiring incentives ignored);
    (6) a source whose Other share jumped against its last 8 archived weeks (today's classifier on both sides).
    Rules and thresholds measured on every archived week in both states: the lint hits the 2026-11-01 audit's
    misreads and no real title (long real titles reach ~190 characters); the Other-share replay flags 2 MT
    (Florence-Carlton schedule lines) and 2 WY (Albany 2024-09 section headings) source-weeks, all real. First
    run: MT 9 postings at 5 sources (Huntley Project, Livingston, OPI "Other", Turner, Ulm), WY 1 (Fremont #21).
    (3) `tests/testthat/fixtures/classification_golden_set.csv` (identical in both repos): 528 real titles (285
    K-12, 243 HE, both states, sampled across every bucket) with checked buckets, 50 judgment calls left out;
    27 `known_miss` rows the classifier still gets wrong (e.g. Administrative Assistant -> Administration, GEAR UP
    success coaches -> Coaching or Athletics, Laborer -> Support Services). `test-classification-golden-set.R`
    fails on any other disagreement and when a known miss starts agreeing (clear its flag).
  * [x] `Pay_Min`/`Pay_Max`/`Pay_Unit`/`Pay_Text` required in `hedata.xlsx` (`REQUIRED_SCHEMAS_XLSX`, 2026-11-09):
    the weekly runs already write them; `app.R` pads a missing pay column with NA, so before this a dropped column
    would have shown no posted pay without failing the schema step.

  * [x] Confirmed closings from each posting's page (2026-11-06/07; 3d741ab, data 57989e8): `posting_status.R`
    checks the page of every posting that dropped off its board since the last run (AppliTrack, TalentEd, Red Rover,
    NEOGOV, JazzHR, Paycom; a browser only for Red Rover and Paycom) and records in `posting_status.csv` (committed
    weekly) whether the platform says it closed, when, and any closing date it states. A failed check is "unknown".
    Trial on 11-03 -> 11-05: 15 of 15 dropped postings confirmed closed. Posting spells use it: "closed (confirmed)"
    endings, "censored: still open on its page" for scraper misses, the stated closing date as the end date when it
    falls in the gap, and an advertised-window measure (`advertised_windows.csv`). Platform audit:
    `claude-notes/2026-11-05_closing-date-audit.md` (54% of MT K-12 rows outside OPI and 76% of HE can be confirmed;
    the Apptegy/district-site scrapers and OPI can't).
  * [x] Title-shape fixes (2026-11-05; 3d741ab): `split_title_detail()` / `move_title_detail()` cut requirements,
    pay, "Open Until Filled" and file names from titles at ingestion, before the archive and the ID; pay found there
    fills Posted Pay (Turner "Secretary" $14/hour, Huntley Project "Bus Drivers", Livingston "Dish Server Cashier").
  * [x] CJI (2026-11-05; 3d741ab): the hard-coded openings-PDF short link went 404 and every run logged "empty";
    the link is now read from the rendered page, and a missing link or failed download is an error.
  * [x] Red Rover opening links (2026-11-06; 3d741ab): Columbia Falls, Hamilton and St. Ignatius rows carry
    `/org/<org>/opening/<n>`, now a stable posting ID (about 41 postings got new IDs once).
  * [x] `repro_scraper.R` for wrapper dispatch entries (2026-11-06; 3d741ab): `scraper_fetch_fn()` reads a wrapper's
    body, so the Red Rover districts name `fetch_redrover_postings` (repro and auto-fix evidence had NA).
  * [x] Drift-issue OPI wording (2026-11-06; 3d741ab): "N postings at M districts, not on the district's own board"
    instead of "protected by Central Safety Net fallback ... vacancies preserved" (the numbers were right).
  * [x] OPI-primary districts (2026-11-06; 3d741ab): `opi_primary_districts.csv`, 15 districts checked and found to
    post only on OPI (13 from 2026-11-03, Eureka and Geraldine from the backlog), summed in one line of the OPI
    cross-check so the adoption list shows only unchecked districts.
  * [x] Weekly-totals downloads (2026-11-06; 3d741ab): both download buttons keep the latest snapshot in each ISO week.
  * [x] Golden-set fixes (2026-11-07; 3d741ab, data 57989e8): "Administrative Assistant/Secretary/Clerk" -> Staff;
    academic/success/retention/GEAR UP coaches -> Advising. Golden set 501 -> 508 of 528, 7 known misses cleared,
    none broken; committed data reclassified (4 combinedclean rows).
  * [x] Six more golden-set misroutes (2026-11-08; 1f261c8): Sub-Varsity coach, Bus Paraprofessional, cross-country
    coach aides, bare "Aide" matching inside "Little Raiders Daycare", Office/Records Assistant, Mower. 17 of 8,066
    archived titles move, all intended; golden set 517 of 531; committed data unchanged (titles only in 2024-25
    archives). Items 1 and 2 measured first (`claude-notes/2026-11-08_classifier-items-1-2-measured.md`).
  * [x] Classification safeguards 9 and 11 (2026-11-08; 40e4365): keyword-conflict report in the drift issue
    (`find_keyword_conflicts()`, title words naming another bucket; tuned on all archived titles since 2025-10-01,
    0 false alarms left) and a blocking 8% ceiling on this week's Other share (record week 3.4%). Two misroutes it
    found: "Support Clerk"/"Building Secretary Support" -> Staff, HE "Custodian - Dining Center" -> Maintenance &
    Service. `reclassify_committed_data.R` now refreshes the posting spells even when the history files don't
    change (they come from the raw archives; the morning's fixes had left MT's "Little Raiders" spell stale).

  * [x] Eleven HE golden-set known misses (2026-11-09; d862c49): laborers, stationary engineer, lab/husbandry/
    paleontology, "(Student)" titles, counselor/financial assistance, classroom support, night watch, enterprise
    architect. Archive diff: 21 HE titles move, all intended; golden set 548 of 551; HE posting spells refreshed.
    Review tools added 11-08 (archive diff, spells invariant, guard rows; toolkit footgun 16, `sibling_sync.R`).

  * [x] "Coord" abbreviation -> Administration (2026-11-09; 3389731): "COMMUNICATIONS COORD." relabeled Administration
    (Mike); 3 archived titles move; golden set 549 of 551 (2 known misses, both file-name titles).

  * [x] "Posted / listed" first-seen fallback (2026-11-09; 391800f): 546 of 1,380 K-12 and 149 of 379 college postings had no date; they now show "First seen <date>" or
    "On the board since at least <date>" (already up when we first scraped that board), from the posting spells
    (`posting_first_seen.csv` in the app folder, committed weekly). Mike: first-seen dates will match posted dates
    more closely the longer the dashboards run. Checked in the rendered app.
  * [x] Reposts (2026-11-09; not built, measured): a listing that ends and reappears next week under a new ID with
    the same title looks like an ending plus a new posting (MT 101 / WY 358 strict pairs). Not linked: of the 23 WY
    SchoolSpring pairs whose old record has a final status, 8 were "filled", i.e. a new vacancy, not the same job.
    Built instead (Mike, option 1): those endings are "outcome unknown" (censored) in the duration estimates
    (7b75e29): K-12 median 25.5 -> 28.5 days, college 21.5 -> 31.5 (MSU reissues posting numbers; 142 of 156 relistings). A platform-reported "filled" keeps its ending.

  * [x] OPI descriptions refine the position bucket (2026-11-09; 178fc31): OPI's title is only its subject field. A
    `Role_Hint` from the description's opening (long-term substitute, part-time / under 1.0 FTE, or the role named
    first) moves 21 of 215 counted OPI postings on 11-03 (9 part-time teachers and 4 long-term substitutes out of
    Teacher, 2 paras out of "Elementary Curriculum", 5 teachers and a counselor out of Administration/Other), each
    confirmed by reading it; on the live board 11-09, 38 moves, all read (one false positive found and fixed:
    "paraprofessional support in the classroom"). Never moves a posting to Administration. History before 11-03
    keeps title-only buckets (no OPI descriptions archived). Rehearsal: all steps passed, but OPI hit a DNS timeout
    (0 OPI rows), so the fresh-data path was checked separately on the live board.

  * [x] OPI dead application links (2026-11-09; measured, nothing to drop): the 2 postings whose links all failed both
    still give a way to apply (Colstrip: a working email beside a dead short link; Poplar: its site was briefly down,
    200 on recheck). A weekly link check would mostly flag outages and email links; not built. College side: MSU's
    90 applicant pools already land in Adjunct/Part-Time Faculty; 8 non-pool postings over 180 days, all still open.
  * [x] OPI adoption candidates checked (2026-11-09): Golden Ridge, Ross, Valley View and Wyola added to
    `opi_primary_districts.csv` (no website, or none that is public or confirmed; evidence in the file), so the
    drift issue counts them on the "only board is OPI" line. Olney-Bissell has its own posting: moved to an
    adoption item below.
  * [x] Olney-Bissell School District adopted (2026-11-09; registry 201 districts): Apptegy behind Fastly, read
    through the shared chromote session; `parse_olneybissell_postings()` takes the bold title of each page-builder
    text block (instructions and the "Certified Application" link are plain text). Live 11-09: 1 posting, "Long Term
    Substitute - Kindergarten" (start about 2027-05-01), not on OPI. Fixture
    `apptegy_olneybissell_pagedata_2026-11-09.html`; no DLI salary mapping yet.
  * [x] Copilot Internet access (repo Settings, Mike, 2026-11-09): rollontigers.org, schooljobs.com, olneybissellschool.com and bls.gov (in the allowlist file since 10-31 but never on
    this list); gojhawks.com, jolietschools.org and savagepublicschool.com (10-29 batch) confirmed. The setting now matches
    `.github/copilot-allowlist.txt`.
  * [x] Olney-Bissell context data (2026-11-09): DLI (`MT_DLI_DISTRICT_MAP`, NorthWest "Olney-Bissell Elementary": 6
    teachers, pay "ND" so the salary columns stay NA), CCD (`MT_CCD_LEA_MAP`, "Olney-Bissell Elem": live 2024 10 FTE,
    95 students), SAIPE (`MT_SAIPE_DISTRICT_MAP`, 2024 child poverty 11.2%) and OPI finance (`MT_OPI_FINANCE_LEA_MAP`,
    FY2025 General Fund $857,304). Each live fetch checked by hand; fixtures got its real rows (CCD 2022 row, FY2025
    finance rows). `salarymap2.csv` gets its row from the registry on the next run.
  * [x] Last golden-set known misses (2026-11-09): `classify_k12_position()` reads "_" as a space (an uploaded
    file's name: "Dish_Server_Cashier 26 - Copy", Livingston) and Food Services takes word-bounded "Dish" and
    "Cashier" (not bare "Server", which can be IT). Archive diff over both states (7,825 K-12 titles): only those 2
    titles move, Other -> Food Services; committed data unchanged, MT posting spells refreshed (Food Services 49 -> 50
    postings). Golden set 551 of 551.
  * [x] Map context for every district (2026-11-09): CCD staffing, SAIPE child poverty and OPI finance came only
    from the 33 hand maps, so 168 scraped districts had no vacancy rate or students per teacher. Each now takes its
    CCD districts from `mt_district_crosswalk.csv` (`crosswalk_lea_names()` / `crosswalk_leaids()` /
    `crosswalk_counties()`, `opi_reconcile.R`; hand maps still win): CCD and SAIPE by LEAID, finance by name with
    the county where a name is shared. Rehearsal (`claude-notes/2026-11-09_rehearsal-mt-mapping-2.log`): all steps
    passed, salarymap2 201 of 201 for FTE, poverty and finance; the 32 previously mapped districts unchanged; 167
    reach the 10-FTE vacancy-rate floor. Found on the way: Cottonwood #57 (Havre, Hill County) carried Gallatin's
    NCES id (3007500 -> 3014150) and DLI region (4Rivers -> HiLine, $32,200); two districts are both
    "Cottonwood Elem", and `build_mt_district_crosswalk()` claimed the registry's CCD row by name, so it now
    claims by LEAID (crosswalk diff: only Cottonwood's and Olney-Bissell's rows change).
  * [x] Free/reduced lunch share and every posting on the map (2026-11-09/10): `Free_Reduced_Lunch_Share` (+
    `FRL_Year`) from CCD's school directory beside SAIPE child poverty for every map entity (rehearsal: 192 of 201
    registry districts); 18 employers that aren't public districts get map rows from `other_employers.csv`
    (`build_other_employer_rows()`: co-ops and Shodair from CCD, the Northern Cheyenne Tribal School from CCD's BIE
    directory, 11 private schools from the 2023-24 Private School Universe Survey; private/tribal schools get their
    surrounding district's SAIPE rate via the Census geocoder; `Posting_Names` puts Northern Cheyenne's two OPI names on
    one dot, relabeled in `app.R` for the map, Jobs, trends, weekly totals and spells). New employers without a row are
    listed in the drift issue (`unmapped_employers.csv`). Seven registry dots moved to their CCD school sites (Circle,
    Zurich, Lustre, Pleasant Valley, Miami, Big Sky, Cottonwood). From the full review: a CCD outage now logs an error
    and keeps last run's lunch values (it had logged "ok" and blanked them); a geocoder failure keeps last run's rate
    and is logged; the app read CCD_Year as both number and text and would not have started after the next run;
    Olney-Bissell's parser skips bold notices; the District Summary's numeric columns sort as numbers (every one had
    sorted as text, server-side); one wording for "every student counted (likely free meals for all)". Rehearsal
    (`claude-notes/2026-11-09_rehearsal-mt-review-fixes.log`): all steps passed; app tests and boot smoke pass on its
    output; full suite 965.
  * [x] Apptegy adoption tooling (2026-11-10, cbbf0eb): `scripts/capture_fixture.R --apptegy` renders the page in headless Chrome
    (as the pipeline does), redacts `AIza...` keys, refuses a page without page-builder data, and saves
    `apptegy_<slug>_pagedata_<date>.html`; `scripts/scaffold_district.R` gets an apptegy mode (auto-picked from that
    fixture; `--node text|panel`): registry row with Platform `Apptegy`, parser + chromote fetch before the dispatcher,
    the `APPTEGY_DISTRICT_SCRAPERS` entry, the Rmd label, unit tests asserting the titles the parser returns on the
    fixture, and the dispatcher test's fixture/routing/counts (warns when an existing routing pattern already matches
    the URL). Also: an unknown `--cms` is an error (it fell through to the generic template), and the allowlist step
    inserts the host in place instead of re-sorting the file (it moved 3 hosts it didn't touch). Checked in a scratch
    worktree: a text-block district (Olney-Bissell fixture, 1 posting) and a panel district (Savage fixture, 8, as
    Savage's own parser) scaffolded together, then misc-district, salary, allowlist, drift-check and coverage-calendar
    tests: 0 failures; rerun changed nothing; a live capture of Olney-Bissell's page scaffolded to its 1 posting.
    Recipe in the jobs-dash-scraper skill (`adopt-new-source.md` § Apptegy), synced from the toolkit.
  * [x] Two spell artifacts from WY's 11-10 audit (2026-11-10, 6f52b4a; same code in both states, WY d0de23d):
    `normalize_posting_text()` decodes every numeric HTML entity (`decode_numeric_entities()`; the hex `&#x27;` was
    missed: 4 MT K-12 archive files carry one, none in current data), and `relisted_next_run()` ignores punctuation.
    MT committed data unchanged (reclassify dry run); classifier archive diff over both states: no bucket moves; full
    suite 4,099 pass. MT's spells pick up the new relist rule when the weekly run rebuilds them. Pushed before the
    2026-11-10 run by Mike's call, without a full MT rehearsal (WY's passed with the same change).
  * [x] 2026-11-10 weekly run checked (manual dispatch 42889397879, all steps green; the late scheduled run 42891770941
    then failed only at its push, conflicting with the manual run's same-day files, so nothing of it landed):
    salarymap2 201/201 staffing, SAIPE and finance, lunch share 192; 17 non-district employers with Posting_Names; the
    7 moved dots on the map; CCD lunch share (296) and Census geocoder (12) logged ok; Olney-Bissell 1 posting; CJI 3;
    AppliTrack job-ID links 342/342; Turner "Secretary" $14/hour; posting_status.csv 30 checked (all closed);
    keyword conflicts 0, Other 1.8% K-12 / 2.1% HE; rebuild parity exact. Roberts back (2 postings: custodian,
    substitutes), so that item is closed. `pending` in `test-data-dictionary.R` emptied; the dictionary's
    salarymap2 `Child_Poverty_Basis` row removed (a WY row: MT's salarymap2 holds only public districts, which always
    have their own SAIPE rate; `opi_only_districts.csv` keeps the column). Lone Rock's auto-fix issue #13 is a false
    positive (its 2 real openings came down; the LLM hint read the standing substitute list as 6 postings).
  * [x] Data-integrity batch (2026-11-10, 775ff7b; `claude-notes/2026-11-10_data-integrity-sweep.md`): (1) pay units, same code as
    WY df9bc07 (bare $7.25-$60 beside a pay word is hourly; NEOGOV card falls back to its description when the field's
    unit is rejected); (2) OPI postings with no detail-page district get the one employer their location names
    (`OPI_LEGACY_LOCATIONS`: Busby, Vida, "841 Bear Canyon Road", "10 miles North of Troy", Wilsall, Montana City;
    "Saint" = "St." in town matching; Box Elder, Eureka, Troy, Itinerant, Fairfield stay unresolved), so the trend
    lines before and after 11-03 join; history rebuilt from the archives (`rebuild_k12_history_from_archive.R`, parity
    exact): current week unchanged, older weeks renamed, about 10 OPI teacher postings over 16 weeks now matched to
    the district's board; (3) no advertised window for a posting listed more than a week past its stated date;
    (4) Deer Park (was on Columbia Falls's dot, 8.9 km off), Swan River and Bigfork (one shared dot) moved to their CCD
    schools; toolkit `reference_audit.R` check 2b (9a2ef47) flags two districts within 300 m. Also
    `scripts/reconcile_opi_history.R` runs again (Role_Hint); do not run it as is: with `recompute = TRUE` it re-decides
    11-03 and 11-10 without the live 60-day rule (+14-15 OPI rows) and would break parity; use the parity rebuild.
  * [x] Run expectations and the scheduled-run guard (2026-11-10, d1f3879; WY eade3b4; workflow plan
    `claude-notes/2026-11-10_workflow-review-and-plans.md` items 2.1-2.2, approved by Mike): `run_expectations.csv`
    (6 rows, from the 11-17 watch-list) is checked by the new non-blocking step `check_run_expectations.R`
    (`run_expectations.R`, same file in both repos): summary on the run page, failures in the drift issue. On the
    committed 11-10 data, as of 11-17: 5 pass, 1 fails (6 K-12 posted pays without a unit; 775ff7b should leave at
    most 1). A `guard` job skips a scheduled run when main already has that day's data commit; checked against
    history (skips 11-10, runs 11-17). Live run of the step, suite 4,113 (0 failed).
    Review fixes before push (jobs-dashboard reviewer): the committed-file test no longer requires a row's file to
    exist (WY's posting_status.csv rows would have stopped the 11-13 pre-run suite); the guard fetches main's live tip
    (a queued run's checkout is main as of its creation: MT 11-10 started at 6f52b4a, 9 s after c2dec92 landed);
    .xlsx columns are typed like .csv; rows that passed on zero matched rows now count what must be there (6 rows).
    Suite 4,119 (0 failed).
  * [x] OPI matcher on the 11-10 run, and two rule changes (2026-11-10, 0911e70; `claude-notes/2026-11-10_opi-matcher-11-10-check.md`):
    345 of the 11-10 run's 354 OPI postings were already judged on 11-03; of the 17 new decisions, 11 right, 1 doubtful
    (Anaconda), 5 whose board twin had gone. A sample of 12 drops: 10 right, 1 wrong (Manhattan's ASL intervener), 1
    unsure. Mike's rule (open = a candidate can apply): all 5 lost twins still on OPI, every apply route through the
    district, none on its board (read live), so closed. `close_opi_lost_twins()` stops counting an OPI posting whose
    earlier twin is gone from a board that returned postings (`OPI_Matched_Posting_ID` new in the raw archive; history
    not restated, from 11-17). Matcher: no level in the job phrase -> OPI's school field ("Manhattan Elem"); answer key
    unchanged, one decision per week changes (Manhattan). Full rehearsal (`claude-notes/2026-11-10_rehearsal-mt-opi-twins.log`):
    all steps passed, 228 sources ok, 0 errors, the 5 closed, rebuild parity all 9 files, post-run suite 4,139.

  * [x] Standing substitute lists in the drift check (2026-11-10; same change in WY; MT issue #13, Lone Rock): an
    LLM-read list of substitute pools no longer makes a source likely_broken unless the source's own titles over its
    last 8 archived runs include a substitute posting (127 of 183 direct sources here do). `drop_standing_pool_titles()`,
    `recent_source_titles()` (drift_check.R); `corroborate_drift.R` passes the history. Live run of `corroborate_drift.R` on the 11-10 flags: Lone Rock -> looks_genuinely_empty ("an LLM read only a
    standing substitute list (6 line(s))"), University of Providence unchanged. Suite 4,154 (0 failed).
  * [x] apt mirror fallback in CI (2026-11-11; same change in WY and in edjobs' package CI): from ~15:20 UTC 11-11
    hosted runners could not resolve *.ubuntu.com (probe on ubuntu-22.04/24.04/26.04; Microsoft and CRAN hosts
    resolved), so every `apt-get update` hung until the job timed out. New `.github/actions/apt-mirror-fallback`, run
    before R setup in `setup-r-env` (PR checks, Copilot, autofix) and in `weekly-scrape.yml`: apt timeouts always,
    and `mirrors.edge.kernel.org` when azure.archive.ubuntu.com does not resolve (probe: apt-get update 5.6 s).
  * [x] Claude as the auto-fix fallback (2026-11-11; same change in WY): both states assign new auto-fix issues to
    Copilot (`AUTOFIX_ENGINE=copilot`; `COPILOT_TOKEN` is one fine-grained PAT for both repos, expires 2027-02-09).
    An issue still flagged at a later weekly run, at least 5 days old, with no open Copilot PR carrying changes and no
    merged fix, goes to `claude-autofix.yml` once (`autofix_escalation_decision()`, `autofix_linked_prs()` in
    drift_check.R; marker comment records the hand-over). Only when a Claude credential is set
    (`AUTOFIX_CLAUDE_FALLBACK` in weekly-scrape.yml). `claude-autofix.yml` has `allowed_bots: "github-actions"`
    (every earlier run failed "Workflow initiated by non-human actor"). Checked with a fake `gh` (hand-over, no
    credential, already handed over, too new, PR awaiting review, unreadable comments). Suites (NOT_CRAN=true): MT 3,932,
    WY 2,047, 0 failed.
    First real Claude run (WY #7, run 43079089307, 2026-11-11): Claude signed in and finished (11 turns, $0.35), but
    the guard step's `git add -A -- . ':!.autofix'` exits 1 because `.autofix` is gitignored, so no run could ever
    reach its PR/report step. Now `git add -A` then `git reset -- .autofix`.
    Merged 11-11 (PR #18 -> 67d2caa). Re-test from main (WY run 43086225793): ran end to end, the guard passed and
    Claude posted a "needs a human" report on WY #7. But every Bash call failed ("Sandbox dependencies not available:
    socat not installed"), so the workflow now apt-installs `socat` and `bubblewrap` before Claude runs.
  * [x] Phase 4 close-out review and its fixes (2026-11-13; `claude-notes/2026-11-13_phase4-full-review.md`, outcome
    at its end). `/full-review` of edjobs v0.5.0..v0.11.0 and both states' phase 4: nothing blocking. edjobs 0.12.0
    (PR bostickmike/edjobs#10, branch `phase4-review-fixes`; 1,386 tests, check clean): two latent spells/history bugs,
    ISO-only date parsing, page caps, JSON-LD dates in Mountain time, per-page posting-status log lines, tests for six
    untested exports. Drift baselines (Mike): zero weeks count between a source's first and last weeks with rows;
    trailing zero weeks and calendar-failed weeks (`failed_source_weeks()`) are left out (replayed since 09-01: WY 9
    flags either way, MT 20 -> 19). Run logging in both states: every message/warning to the run log, render
    interrupted at 40 min with R's call stack (`.github/scripts/render_with_stack.R`), partial-outputs artifact on
    failure. EDJOBS_VERSION 0.12.0. Decided by Mike: keep the TedK12 board-URL rule (0 rows affected since 08-11).
    MT: `he_posting_panel()` parses posted dates with `parse_board_posted_date()` (same dates on all 5,353 HE archive
    rows); `test-he-shared-board.R` (UM board split); drift floor `min_mean_count = 2` (Mike; was 0: 5 of 24 flags
    since 09-01 came from sources averaging under 3, Lone Rock 4 false alarms); stale comments. Suite 3,704 passed;
    rehearsal on 0.12.0 passed every step (`claude-notes/2026-11-13_rehearsal-mt-edjobs-0.12.0.log`, post-run suite
    3,728); `check_drift.R` with the floor and calendar weeks run live on the rehearsal output. To land: edjobs #10
    merged and tagged v0.12.0, then this branch's PR.
  * [x] Upkeep workflow: keepalive and token expiry (2026-11-13; same change in WY; edjobs 0.12.1, bostickmike/edjobs#11): new
    `.github/workflows/upkeep.yml` (Wednesdays, a day with no weekly run now or on the planned twice-weekly days) calls
    edjobs' reusable `upkeep.yml`. It re-enables every active workflow through the API, so GitHub's 60-day inactivity
    rule can't silently stop the weekly schedule (a disabled schedule sends no failure email), and opens one issue per
    secret 30 days before its date in the new `.github/token-expiry.csv` (`COPILOT_TOKEN` 2027-02-09, read from
    GitHub itself on each run; `CLAUDE_CODE_OAUTH_TOKEN` 2027-11-11, approximate: set 11-11, about a year).
    Self-sustaining checks 1 and 2 of `claude-notes/2026-11-12_twice-weekly-and-daily-presence-scope.md`; check 5
    waits for the daily presence check. Tested from this branch on a temporary push trigger: dry run with a 400-day
    window, then a real run (all workflows still `active`, `dynamic/` Copilot workflows skipped).
  * [x] Daily presence check, phase 0 (2026-11-13; same change in WY; edjobs 0.13.0): new
    `.github/workflows/presence.yml` (daily, 13:17 UTC) calls edjobs' reusable `presence.yml`, which reads each
    AppliTrack, SchoolSpring, TedK12 and Tyler Portico board once (list pages only, each district's own
    `resolve_scraper_call()`) and commits `presence_checks.csv` (one row per board per day) and
    `presence_sightings.csv` (one row per unbroken stretch of sightings, keyed by `edjobs::k12_link_posting_id()`,
    which now reads Tyler Portico's GUID links) to the `presence` branch, never main. First live run from the Mac
    (11-13): 39 boards, all answered, 594 postings, all keyed, 64 s. Red Rover's 3 boards added the same day,
    through the API (entry below). OPI fingerprints measured for a later step
    (`claude-notes/2026-11-13_presence-redrover-opi-wsba.md`).
    Phase 0 (shadow, 2 weeks): nothing reads the files yet. Measured at the end, in a dated claude-notes audit:
    agreement with the weekly run on its run days, flapping (missing one day, back the next), errors per board,
    runtime and cron lateness. Then phase 1: the spells read the sightings for day-precision endings.
  * [x] Red Rover through its API (2026-11-13; edjobs 0.14.0, same change in WY; Mike: "can't you do MT red rover
    like WY"): St. Ignatius, Hamilton and Columbia Falls are read with `edjobs::fetch_redrover_postings()` (the
    GraphQL API Red Rover's own board calls; WY's fetcher), no longer rendered with Chrome in the Apptegy batch.
    Registry `Slug` is the org ID (2261, 2362, 4161; Columbia Falls's link slug stays `sd659912`). The Chrome scrape
    gave a per-posting link to only 8 of Columbia Falls's 23 postings on 11-10; the API gives every posting its
    `/opening/<n>` link, plus pay; postings matched the 11-10 weekly rows apart from 1-2 posted since. Rows are
    labelled "Red Rover (direct district board)"; the spells panel gives every redroverk12.com row that label,
    archived ones included, so postings spanning the switch aren't censored as having moved boards. The three
    districts' coverage tier becomes Full (`MT_DIRECT_API_PLATFORMS`). The Chrome parser, its three map entries and
    its fixtures are gone.
  * [x] OPI in the daily presence check (2026-11-13; edjobs 0.15.0; Mike: "look a bit harder at OPI and WSBA"):
    `presence_feeds.R` defines OPI as a statewide feed, keyed by `edjobs::opi_posting_key()` (the detail page's
    district and school, title, posted date and description excerpt; OPI links carry no posting ID). A detail page is
    read only for a posting not seen before (first day ~350 pages, ~340 s; later days a handful). Workflow pins
    v0.15.0 and sources `state_config.R direct_api_scrapers.R presence_feeds.R`. Tested on GitHub from a throwaway
    branch (run 43538158652): 43 boards, all ok; OPI 354 postings, all keyed. Not pipeline code: suite only.
  * [x] Drift check: the LLM reading counts only titles the scraper missed (2026-11-13; edjobs 0.16.0, same change in
    WY; Mike: "I do like the change"). `corroborate_drift.R` passes this run's titles for each flagged source to
    `combine_verdict_with_llm(current_titles =)`. WY's Sublette 1 had been filed as likely_broken on 11-11 and 11-13
    because the LLM read "Substitutes", the one item the scraper returned (WY issue 7, closed 11-13 as genuinely
    quiet). Replayed on all 8 past flags with an LLM reading: the 6 MT ones unchanged (scraper returned 0), the 2
    Sublette ones no longer filed.
  * [x] Auto-fix only from main; Claude when Copilot refuses (2026-11-13; same change in WY; Mike: "limit auto fix to
    main", "if copilot is refused then claude kicks in"). The weekly workflow's auto-fix filing step runs only on
    main (branch test dispatches had been handing issues to Copilot). A new issue Copilot can't be assigned, or
    opens no PR for within 5 minutes, is unassigned and dispatched to `claude-autofix.yml` at once. MT's ruleset no
    longer requests Copilot reviews on every push (15 "insufficient remaining quota" reviews on MT PRs since 11-12).
  * [x] CyberSchool family routine (2026-11-14; edjobs 0.17.0, WY pin bump only; Mike: grouping the district
    scrapers by site family "asap"): Highwood, Power and Vaughn get `Platform = "CyberSchool"` and one Rmd block
    calling `edjobs::fetch_cyberschool_postings(Job_Link, City)`; their three scrapers, three blocks and seven tests
    are deleted (`test-cyberschool-family.R` runs each registry row against its fixture). Vaughn moved to IES's newer
    platform this week (`/District/Jobs/` -> `/jobs`, job pages on `vaughn.l.iescentral.com`), where the old scraper
    read nothing; the routine reads both. Same titles, links and locations as the old parsers on their fixtures and
    the 11-14 live pages; Power and Vaughn gain posted dates. Each district keeps its old `Posting_Source` text.
    Posting_IDs: Highwood unchanged; Power's 3 (posted date NA -> 2023-03-01) and Vaughn's 1 (now a stable URL)
    change once; spells bridge them (one spell each in the rehearsal), New This Week will list them on 11-17.
    `iescentral.com` in the Copilot allowlist (also needed in repo Settings). Rehearsal passed every step
    (`claude-notes/2026-11-14_rehearsal-mt-edjobs-0.17.0.log`; suites 3,678 / 3,684, 0 failed); two
    `run_expectations.csv` rows for 11-17. Notes: `claude-notes/2026-11-14_cyberschool-family/README.md`.
  * [x] Listing Duration tabs: the yellow "Time-to-fill estimates are paused" banner replaced by one footnote at
    the bottom of each tab (K-12 and HE), no "we"; the "How days listed is counted" popover reworded the same way
    (2026-11-14, Mike: "either have it or not"; chose: keep the current table, footnote). KPI boxes and charts stay
    out. App tests passed (both states); screenshots checked: MT K-12 tab, WY higher-ed tab.
  * [x] Apptegy family routine (2026-11-14; edjobs 0.18.0, MT PR 34, waits on edjobs PR 17; Mike 11-13: the shared
    filter wins where it disagrees with an old parser, substitute lines kept, Shelby bespoke). 44 districts read
    through `edjobs::fetch_apptegy_postings()`: Platform `Apptegy` (rendered text, 38) / `ApptegyPageBuilder` (6),
    optional rules in the new `k12_list_rules.csv` (5 rows); Shelby and Geyser keep their scrapers as
    `ApptegyBespoke`. Same browser session, log names and Posting_Source. 88 fetch/parse functions + helpers deleted
    (2,238 lines), 130 old test blocks; `test-apptegy-family.R` per district. Exact-title parity found the measured
    filter merging real postings ("Music - Instrumental"/"- Vocal" -> "Music"; St Regis's head/assistant coaches):
    fixed before building. Remaining differences are the decided ones (Townsend's 3 coaching jobs the old parser
    missed, substitute lines, Sweet Grass, Dutton, West Yellowstone's non-jobs) plus cleaner titles at Huntley,
    Florence-Carlton, Drummond. Posted pay now read from Apptegy lines (Melstone, Wolf Point, Townsend, St Regis).
    Rehearsal passed every step (`claude-notes/2026-11-14_rehearsal-mt-edjobs-0.18.0.log`; suites 3,430 / 3,458,
    0 failed): 215 Apptegy rows, every district's count equal to its 11-14 live parity, 197 of 215 spells continue.
    Three `run_expectations.csv` rows for 11-17. Notes: `claude-notes/2026-11-14_apptegy-family/README.md`.
  * [x] Google Sites family routine (2026-11-14; edjobs 0.19.0, stacked on the Apptegy change; same rule as
    Apptegy). 20 districts read through `edjobs::fetch_googlesites_postings()` (Platform `GoogleSites`; rules for Cut
    Bank, Dixon, Swan River in `k12_list_rules.csv`); one Rmd block replaces 20 (each keeps its Posting_Source); 40
    fetch/parse functions + 11 helpers (823 lines) and 56 test blocks deleted; `test-googlesites-family.R`. Eight
    districts stay bespoke (Lodge Grass, Charlo, Creston, Kila, West Glacier, Smith Valley, Opheim, Marion: reasons in
    the notes). Differences: 4 retitles (Lincoln, Fair-Mont-Egan, Ashland, Woodman) and Fair-Mont-Egan's old "Job
    Description" non-title gone. Suite on 0.19.0: 3,399 passed, 0 failed. Rehearsed together with the Finalsite change
    on 0.20.0 (`claude-notes/2026-11-14_rehearsal-mt-edjobs-0.20.0.log`, all steps passed): 65 rows, 62 of 65 spells
    continue, the 3 new ones are the retitles. Notes: `claude-notes/2026-11-14_googlesites-family/README.md`.
  * [x] Finalsite family routine (2026-11-14; edjobs 0.20.0, stacked on Google Sites). 11 districts read through
    `edjobs::fetch_finalsite_postings()` (Platform `Finalsite`); one Rmd block replaces 11; 22 fetch/parse functions +
    5 helpers (494 lines) and 34 test blocks deleted; `test-finalsite-family.R`. A title that is a link on the page
    keeps it: Manhattan's 9 and Hellgate's 2 per-posting links as before, new ones at Shields Valley (5) and Thompson
    Falls (3), each the posting's own document. Whitewater and Fromberg stay bespoke. Differences: Baker's "(... open
    until filled)" asides off, Thompson Falls' "Paraprofessional-" fixed, Shepherd's and Manhattan's substitute-pool
    lines kept (Manhattan's as one run-together line), Shields Valley's co-op heading gone. Suite on 0.20.0: 3,374
    passed, 0 failed; full rehearsal passed every step (`claude-notes/2026-11-14_rehearsal-mt-edjobs-0.20.0.log`;
    suites 3,395 / 3,402): 46 rows, 41 of 46 spells continue. Notes: `claude-notes/2026-11-14_finalsite-family/README.md`.
  * [x] WordPress family routine (2026-11-14; edjobs 0.21.0, stacked on Finalsite). 7 districts read through
    `edjobs::fetch_wordpress_postings()` (Platform `WordPress`); one Rmd block replaces 7; 14 fetch/parse functions
    and their helpers (350 lines) and 21 test blocks deleted; `test-wordpress-family.R`. Differences: Turner's
    "Secretary – $14 per hour, ..." -> "Secretary" with Pay_Min 14/hour; Upper West Shore adds "Teachers" (a standing
    invitation). Bigfork and Pryor stay bespoke. Rehearsed together with Edlio and Joomla on 0.23.0 (see the Joomla
    entry): 12 rows vs 11 in the committed data, the one new row Upper West Shore's "Teachers". Notes:
    `claude-notes/2026-11-14_wordpress-family/README.md`.
  * [x] Edlio family routine (2026-11-14; edjobs 0.22.0, stacked on WordPress). 5 districts read through
    `edjobs::fetch_edlio_postings()` (Platform `Edlio`) on the new `district_page_text()`; one Rmd block replaces 5;
    10 fetch/parse functions (242 lines) and 14 test blocks deleted; `test-edlio-family.R`. Difference: Livingston's
    document file names read as words without the school year ("Baker_Cook 2026 27" -> "Baker Cook"). Broadview
    stays bespoke. 0.22.0 alone dropped Canyon Creek's one posting (a POSIX `[ \t]` also matched a literal "t";
    fixed in 0.23.0). Rehearsed on 0.23.0: 26 rows vs 27 in the committed data; the change is Whitehall's own page
    (adds Agricultural Education Teacher, no longer lists School Custodian). Notes:
    `claude-notes/2026-11-14_small-families/README.md`.
  * [x] Joomla family routine (2026-11-14; edjobs 0.23.0, stacked on Edlio). 5 districts (Roy, Roberts, Belfry,
    Luther, Joliet) read through `edjobs::fetch_joomla_postings()` (Platform `Joomla`); one Rmd block replaces 5;
    10 fetch/parse functions (217 lines) and 15 test blocks deleted; `test-joomla-family.R`. Roberts's
    maintenance-page error and longer retry budget now apply to the family. Difference: Roy "Bus Driver" ->
    "BUS DRIVER" (its heading's case). Grass Range stays bespoke (jobs named in a sentence). Suite on 0.23.0: 3,332
    passed, 0 failed; full rehearsal (WordPress + Edlio + Joomla) passed every step
    (`claude-notes/2026-11-14_rehearsal-mt-edjobs-0.23.0.log`; post-run suite 3,360 passed): 14 rows, all 14 with a
    district + title (any case) already in the committed data; no NA Posting_Source in the three families' rows.
    Notes: `claude-notes/2026-11-14_small-families/README.md`.
  * [x] Noxon, Seeley Lake and Helena Flats back on the board (2026-11-14; edjobs 0.24.0, waits on the stack). All three
    returned 0 rows every week since ~11-03: their scrapers fetched with a plain request, which Apptegy answers with its
    3 KB bot-challenge page. Moved to the Apptegy family (text mode, rendered with the shared chromote session); Noxon
    has a stop rule for its marketing headings. Old functions, Rmd blocks, tests and fixtures deleted; rendered 11-14
    pages are the family test's fixtures. Live run of the step: 5 postings (Noxon 1, Seeley Lake 1, Helena Flats 3).
    Suite 3,324 passed, 0 failed. Notes: `claude-notes/2026-11-14_mt-leftovers/README.md`.
  * [x] Nashua, Frazer, Lavina, Hinsdale on the CyberSchool routine, mode "text" (2026-11-14; edjobs 0.24.0, waits on
    the stack). Registry Platform `CyberSchoolText`; each keeps its Posting_Source; the CyberSchool block now carries
    posted pay. Same titles as the four old parsers on fixtures and live pages (live: 1, 5, 26, 2 postings); Hinsdale's
    older fixture gains 2 per-posting document links. Old functions, Rmd blocks and tests deleted; the drift tests'
    HTTP-scraper example is now Richey. Suite 3,320 passed, 0 failed. Notes: `claude-notes/2026-11-14_mt-leftovers/README.md`.
  * [x] Fromberg on the Finalsite family (2026-11-14; edjobs 0.24.0). Same title and link as its old parser on the
    fixture and the live page; Posting_Source unchanged. Old function, Rmd block and tests deleted.
  * [x] Victor, Superior, Bainville, Creston on the Google Doc routine (2026-11-14; edjobs 0.24.0
    `fetch_googledoc_postings()`). Registry Platform `GoogleDoc`, doc ids in `Slug`; Bainville has list rules. Live
    11-14: 4, 3, 7, 1 postings, the 11-10 counts; Victor keeps the doc's "updated" date. Title changes once: Victor
    "Substitute" -> "Substitutes", Bainville "Paraprofessional- small intervention group" -> "Paraprofessional". Old
    functions, the preview helper, Rmd blocks and tests deleted. Full suite 3,322 passed, 1 failed (the rules-file test
    allowed only Apptegy/Google Sites rows; widened, that file then 287 passed, 0 failed).
  * [x] Full rehearsal of the `apptegy-leftovers` branch on edjobs 0.24.0 (2026-11-14): every step passed, rebuild
    parity 9/9, post-run suite 3,355 passed, 0 failed (`claude-notes/2026-11-14_rehearsal-mt-apptegy-leftovers-0.24.0.log`).
    combinedclean 1,369 -> 1,399 rows. Own-page rows: Helena Flats 3, Seeley Lake 3, Noxon 1 (0 in the 11-10 data);
    the other 9 moved districts the same counts as 11-10 (Frazer 26, Bainville 7, Victor 6, Nashua 5, Superior 4,
    Lavina 2, Creston 1, Fromberg 1, Hinsdale 1). The other 9 districts with no own-page rows in 3 weeks are
    genuinely quiet (no openings, application forms only, or an empty page; `claude-notes/2026-11-14_mt-leftovers/README.md`).
  * [x] Package phase 5, slice 1: IPEDS faculty salaries, enrollment, Pell share and ACS county context from edjobs
    0.25.0 (2026-11-15; branch `phase5-ipeds-acs`, ef1a60d; edjobs branch `phase5-ipeds-acs`, 74b9c6f + c4695a4, not
    tagged). `ipeds_salary_scraper.R`, `ipeds_enrollment_scraper.R`, `fsa_pell_scraper.R`, `census_acs_scraper.R`, their
    tests and fixtures deleted (tests moved to the package); the map is in `ipeds_unitids.R`; FIPS from
    `state_config()`. Package output identical to the old functions on every fixture; live fetch identical to the
    committed files. Full rehearsal on 0.25.0: every step passed; federal steps ok (IPEDS salaries 22, trend 66, enrollment 22, trend 22, Pell 22, ACS 56 + 56); `salarymap.csv` (23 rows) and
    `salarymap2.csv` (201 rows) federal columns identical to the committed files; rebuild parity 9/9 (combinedclean
    1,394); post-run suite 3,274 passed, 0 failed (`claude-notes/2026-11-15_rehearsal-mt-phase5-0.25.0.log`). Notes:
    `claude-notes/2026-11-15_phase5-federal/README.md`.
  * [x] Package phase 5, slice 2: CCD staffing and SAIPE child poverty from edjobs 0.26.0, by NCES id; combined
    districts' poverty pooled (2026-11-15; branch `phase5-ccd-saipe`, 457e0f4 + 90f63d5 + 18f19c5, on slice 1; edjobs
    branch `phase5-ccd-saipe`). `ccd_staff_scraper.R`, `census_saipe_scraper.R`, their tests and fixtures deleted;
    `MT_CCD_LEA_MAP` kept in `ccd_lea_pairs.R` as the crosswalk's pair input; `MT_SAIPE_DISTRICT_MAP` gone. By id vs by
    name on 2024 data: identical for all 201 districts (`claude-notes/2026-11-15_phase5-federal/slice2_side_by_side.R`).
    **Mike's decision 11-15:** an elementary + high school district's child poverty = children in poverty / relevant
    children summed over both (was the equal average of the two rates); also for the OPI-only table (was the first
    rate) and the surrounding-district stand-ins. Data dictionary (one sentence) and cookbook (with the SAIPE source)
    say so. Rehearsal on 0.26.0: every step passed; `salarymap2.csv` 201 rows, Child_Poverty_Rate changed for exactly
    the 90 combined districts, each to the measured pooled rate (median 0.4, max 2.5 points; `weighting_effect.csv`),
    every other column identical; `opi_only_districts.csv` 11 of 35 rows' poverty moved (median 0.4, max 1.8 points);
    parity 9/9 (combinedclean 1,394); post-run suite 3,208 passed, 0 failed
    (`claude-notes/2026-11-15_rehearsal-mt-phase5-0.26.0.log`).
  * [x] Sources footer and required notices on every page (2026-11-15; branch `phase5-ccd-saipe`, after slice 2).
    Mike 11-15: add the Census API notice and Urban's ODC-By citation, and check every source. Audit of every
    outside source's terms: `claude-notes/2026-11-15_citations-audit.md`. `page_navbar(footer = data_sources_footer)`
    lists the sources and carries the Census Data API notice and the BLS API disclaimer, both verbatim from their
    terms; Urban cited in its short ODC-By form. Esri basemaps now show each service's own credit (the bundled
    leaflet-providers strings were out of date and left out OpenStreetMap contributors). The K-12 footnote's SAIPE line said "unweighted average"; now says pooled, as slice 2 computes it.
    Checked live in a headless browser (footer text and all three basemaps' credits read back); app boot smoke and
    app reactives tests pass; `sibling_sync.R` OK.
  * [x] Basemaps with open terms, no Esri (2026-11-15; branch `phase5-ccd-saipe`). Esri's ArcGIS Online FAQ: without
    Esri software "you must purchase an ArcGIS Online subscription"; the free Location Platform key would need
    new endpoints, "Powered by Esri", a visitor terms-of-use page and pay-as-you-go billing past 2M tiles.
    **Mike's choice 11-15:** OpenStreetMap (default; policy URL tile.openstreetmap.org), USGS National Map
    (USGSTopo; public domain, USGS's requested acknowledgment as the credit), Shaded Relief (USGS relief + hydro).
    Options and quotes: `claude-notes/2026-11-15_basemap-options.md`. Checked live in both apps: opens on OSM, all
    three layers draw with their credits; app boot smoke and reactives pass; `sibling_sync.R` OK.
  * [x] Child poverty relabeled (2026-11-15; branch `phase5-ccd-saipe`). Census: "A true poverty \"rate\" for children
    cannot be determined from these figures, because the numerator and denominator refer to slightly different
    universes" (SAIPE school district overview, revised 2026-01-12). **Mike's choice 11-15 (option A):** labels only,
    numbers and the `Child_Poverty_Rate` column unchanged. Table column "School-Age Children in Poverty (Census est.)"
    (+ "Poverty Estimate Basis"), map popup, comparator card, About text; the footnote and the data dictionary (md +
    csv) explain the two counts. Read back live in both apps; app boot smoke, reactives, data dictionary and schema
    tests pass. Notes: `claude-notes/2026-11-15_census-reporting-lit-review/README.md` (Q2).
  * [x] About-tab wording for the county mining share (2026-11-15; branch `phase5-ccd-saipe`): it said "civilian labor
    force" (MT also "agriculture/resource extraction"); ACS S2403's denominator is the civilian employed population
    16 and over and line 4 is mining, quarrying, and oil and gas extraction only (Census API labels, read 2026-11-15).
    Now matches the data dictionary. Text only.
  * [x] SAIPE child poverty: Census's approximate 90% range beside each estimate (2026-11-16; branch `saipe-range`,
    edjobs 0.27.0). **Mike's choice 11-15 (option A):** Census publishes no margin of error for one district, only
    median relative errors by district size ("Quantifying Relative Error in the School District Estimates", revised
    2025-12-17); range = rate x (1 -/+ 1.645 x CV), floored at 0, capped at 1. New columns SAIPE_Population,
    Child_Poverty_Low, Child_Poverty_High (data dictionary; `pending` until the first run writes them;
    run_expectations `saipe_range_*`). Table column "Approx. 90% Range", map popup, comparator card, footnote.
    Rehearsal (`claude-notes/2026-11-15_rehearsal-mt-saipe-range-0.27.0.log`): every step passed; salarymap2 201 rows,
    201 with a range; opi_only_districts 30 rates, all with a range; rates changed only for the 90 combined
    districts (slice 2's pooling, not yet in main's data); parity 9/9; suites pre 3,199 / post 3,209 passed, 0 failed.
    Read back live in the rehearsed app (Billings 7.9%, about 6%-10%).
  * [x] ACS county figures: Census's 90% margins of error (2026-11-16; branch `acs-moe`, edjobs 0.28.0). **Mike's
    choice 11-16 (option B; `claude-notes/2026-11-16_acs-moe-reliability-decision.md`):** show the MOE, no CV tiers.
    New columns Median_Household_Income_MOE, Median_Gross_Rent_MOE, Mining_Employment_Share_MOE (salarymap2,
    salarymap, opi_only_districts; data dictionary; `pending` until the first run writes them; run_expectations
    `acs_moe_salarymap2`). Map popup income/rent +/- (mining +/- where shown, >= 5%), comparator rent, HE table,
    K-12 column "County Figures: 90% Margin of Error", footnotes (population trend has no MOE: controlled totals). A
    share whose MOE is at least the share is marked "not distinguishable from 0" (Census's CV > 0.61 line).
    Rehearsal (`claude-notes/2026-11-16_rehearsal-mt-acs-moe-0.28.0.log`): every step passed; every county figure has
    its MOE (salarymap2 201 of 201, salarymap 23 of 23, opi_only_districts 35 of 35); not distinguishable from 0:
    38 K-12 rows, 3 HE, 6 OPI-only; data quality 125 passed; parity 9/9; suites pre 3,199 / post 3,213 passed,
    0 failed. Read back live in the rehearsed app (Billings: income +/-$2,657; rent +/-$37; mining +/-0.3 pts).
  * [x] Feedback without a GitHub login (2026-11-16; branch `feedback-form`). Mike: the public shouldn't need a login;
    filter spam in the app and open one issue per real report in this repo (no second repo, no weekly digest).
    `Mt_Ed_Jobs/feedback.R` (same file in both states): form in a modal (problem type, district, job/link, details; no
    email field, reports are public), checks in `feedback_check()` (hidden honeypot field, under 4 s from opening, spam
    words, exact repeats: dropped silently; missing/oversized fields, > 3 links, 3 per visit, 20 per hour: message),
    @mentions and #N neutralized, issue labeled data-quality + user-report (labels created in the repo). Posts with
    `GITHUB_FEEDBACK_TOKEN` (Connect Cloud secret: fine-grained, this repo, Issues read/write only); without it the
    button stays the GitHub issue-form link. manifest.json lists feedback.R; the manifest check now requires curl and
    jsonlite. `test-feedback.R` 28 passed; full suite 3,227 passed, 0 failed; checked in a headless browser (form opens,
    too-fast submit dropped, short text gets a message, a valid report reaches GitHub and a refused post says so).
  * [x] A retrieval date for every outside data source in the footer (2026-11-16; branch `source-dates`, edjobs
    0.29.0). Mike: BLS option A (`claude-notes/2026-11-15_citations-audit.md`, open item 2), and a date for the
    other sources too. The pipeline records a source in `source_retrieved_dates.csv` (app folder; REQUIRED_SCHEMAS
    entry; committed by the weekly run) only when its fetch succeeded and the data was kept (`retrieved_source` on
    safe_scrape() / write_reference_file(); OEWS only when a new year is downloaded). Each footer line shows
    "(retrieved YYYY-MM-DD)", or a range when one line's parts were fetched on different days. QCEW, which the app
    uses, is now named in the footer. Seeded from git: BLS OEWS 2026-10-31 (last download), NCES PSS 2026-11-10
    (records added); the weekly sources get their first dates from the next run (scrape_log.csv is not committed, and
    the local copy's context rows are months old). Rehearsal (`claude-notes/2026-11-16_rehearsal-mt-source-dates-0.29.0.log`):
    every step passed; data quality 125 passed; parity 9/9; suites pre 3,227 / post 3,238 passed, 0 failed; every
    source dated (OEWS kept 2026-10-31: BLS has no newer year).
  * [x] Feedback form live (2026-11-16): `GITHUB_FEEDBACK_TOKEN` (fine-grained PAT, this repo only, Issues
    read/write, expires 2027-11-16) set as a Connect Cloud secret and the app republished by Mike; his test report
    opened issue #48 with the data-quality and user-report labels (closed). Token added to `.github/token-expiry.csv`
    (the upkeep run opens an issue 30 days before; renewal steps in the file).
  * [x] Package phase 5 close-out (2026-11-16; branch `phase5-closeout`, edjobs 0.30.0). The last pipeline helpers
    both states defined moved to edjobs: `standardize_date()` (same code in both Rmds) and the K-12 salary history,
    `archive_k12_salary_snapshot(salarymap2, history_path, columns)` with this state's
    `MT_K12_SALARY_HISTORY_COLUMNS` (`salary_scrapers.R`; a test checks them against the committed history). The
    archive appends any district/year pair the file lacks (MT's rule; WY's appended only a new year: 0 rows differ on
    WY's committed files); `needs_k12_salary_archive_update()` retired. Rehearsal
    (`claude-notes/2026-11-16_rehearsal-mt-phase5-closeout-0.30.0.log`): every step passed; salary history
    unchanged; parity 9/9; suites pre 3,210 / post 3,221 passed, 0 failed.
  * [x] One registry schema for both states (2026-11-16; branch `registry-schema`, edjobs 0.31.0; Mike 11-16: the
    column set, `Slug` -> `Platform_Key`, list rules in the registry). `k12_district_registry.csv` columns: District,
    NCES_LEAID, City, County, Latitude, Longitude, Platform, Platform_Key, Job_Link, List_Start, List_Stop, List_Skip;
    `k12_list_rules.csv` folded in and removed (`Skip_Section` -> `List_Skip`). Every source resolves to the same call
    as before (224 of 224: fn, args, session, platform, url; `claude-notes/2026-11-16_registry-schema/`). Rehearsal
    (`claude-notes/2026-11-16_rehearsal-mt-registry-schema-0.31.0.log`): every step passed; parity 9/9; suites pre
    3,211 / post 3,222 passed, 0 failed; combinedclean 1,395 rows.
  * [x] College postings at branch campuses on the map (2026-11-16; branch `he-campus-places`, edjobs 0.32.0; Mike
    11-16: "we need the locations to be accurate on the map"). A posting whose Location names another Montana town
    gets its own dot (edjobs `place_he_postings()`); the HE registry gains `Town`, `places.csv` holds every Census
    place with its county; anything else stays at the main campus, counted in a note under the map;
    facultydata.csv leaves the new columns out (`HE_PLACE_COLUMNS`). Plan and measurement:
    `claude-notes/2026-11-16_college-campus-locations.md`. Rehearsal
    (`claude-notes/2026-11-16_rehearsal-mt-campus-0.32.0.log`): every step passed; parity 9/9; suites pre 3,222 /
    post 3,236 passed, 0 failed; hedata 375 postings: 75 main town, 4 other town (FVCC Libby), 296 no town (mostly
    MSU-system departments: campus rules are stage 2, not built).
  * [x] IPEDS faculty salary over 9- to 12-month contracts (2026-11-16; edjobs 0.33.0; Mike 11-16: headline "Avg.
    salary, full-time instructional staff (IPEDS, 9-12-month contracts)"). The contract_length 99 "Total" row counted
    staff on contracts under 9 months, whose salaries IPEDS doesn't collect; the map popup's "blends part-time/adjunct
    pay" note was wrong (IPEDS salaries are full-time only) and is gone. Live fetch on 0.33.0
    (`claude-notes/2026-11-16_ipeds-salary-live.txt`): MT Blackfeet $25,621 -> $54,317, University of Montana
    $93,938 -> $95,013, the other 19 MT and all 9 WY figures and every professor-rank figure unchanged; Faculty_Count
    unchanged. Findings: `claude-notes/2026-11-16_ipeds-faculty-salary.md`.
  * [x] College postings at outreach sites and field offices, campus stage 2 (2026-11-16; branch `he-campus-stage2`,
    edjobs 0.34.0; Mike 11-16: "yes, build it"). MSU-system boards give a department, not a town, so a posting is
    now also placed from a title marker ("*Havre, MT*"), `he_campus_departments.csv` (MSU's research centers ->
    town, each with its source: the center's own page on agresearch.montana.edu) or an explicit sentence on its
    PeopleAdmin page ("This position is located in Joliet, Montana"; "The Extension office is located in
    Plentywood"); never a bare town name, and a posting naming several towns stays at the main campus. Extension
    agents are not placed at the county seat (Carbon County's office is in Joliet). Measured on 360 live PeopleAdmin
    pages (18 placed away from the main town, all read and right) and MT's archives (33 MSU postings placed by title
    or department; the two agree on all 10 where both apply): `claude-notes/2026-11-16_college-campus-locations.md`,
    "Stage 2 measured". Rehearsal (`claude-notes/2026-11-16_rehearsal-mt-campus2-0.34.0.log`): every step passed;
    parity 9/9; suites pre 3,231 / post 3,246 passed, 0 failed; combinedclean 1,402 rows; hedata 374 postings: 79
    main town, 15 other town (MSU 11: Havre 3, Great Falls 2, Helena, Joliet, Lewistown, Miles City, Plentywood,
    Sidney; FVCC Libby 4), 280 no town.
  * [x] A link to each district's and college's page at its source (2026-11-16; branch `source-record-links`, edjobs
    0.35.0; Mike 11-16: "each row in each data set could have a url link to its source whenever possible"; option A,
    Mike: "yes"). salarymap2.csv gets `CCD_Link` (NCES CCD district page, from `NCES_LEAID`) and salarymap.csv
    `IPEDS_Link` (College Navigator, from `IPEDS_UNITID`), added by a last Rmd chunk after every chunk that rewrites
    them. Posting files already link every posting; DLI/OPI salary, OPI finance, SAIPE and ACS have no page per
    district, so they get none (measurement: `claude-notes/2026-11-16_source-links-per-row.md`). Both NCES pages show
    NCES's newest year; split elementary/high school districts link the elementary district's record (the file's
    existing `NCES_LEAID`); Missoula College carries UM's IPEDS id. Rehearsal
    (`claude-notes/2026-11-16_rehearsal-mt-source-links-0.35.0.log`): every step passed; parity 9/9; suites pre 3,231
    / post 3,246 passed, 0 failed; links on 201 / 201 districts and 23 / 23 colleges; 14 sampled links each opened the
    right record.
  * [x] Data dictionary source labels a reader can look up (2026-11-16; branch `dictionary-source-labels`; Mike 11-16:
    the `Primary_Authority` labels were internal, "Canonical Registry", "Project Pipeline"; option A, Mike: "A is
    fine"). Every row now names an outside source or "This dashboard: ..." with how the value was made: weekly
    snapshot, posting tracking, job title classification, district and college list, coverage summary; postings
    are "Job posting (district job board or OPI Jobs for Teachers)" or "Job posting (college job board)"; duplicate source names merged (NCES Common Core
    of Data (CCD), US Census ACS 5-year, US Dept of Education FSA, MT DLI Teacher Compensation Report). Names,
    coordinates and careers links say "district and college list", not IPEDS or Census geocoding: the cookbook has
    them hand-maintained. 161 of the CSV's rows and 154 rows of DATA_DICTIONARY.md changed; no other cell changed;
    the two agree on every label. Suite 3,210 passed, 0 failed. Plan: `claude-notes/2026-11-16_dictionary-source-labels.md`.
  * [x] Old test-failure files untracked (2026-11-16; branch `small-leftovers`). Main tracked testthat's local
    failure snapshots (`tests/testthat/_problems/`, 4 files, and `testthat-problems.rds`) from 9c9c640; removed from
    git and added to `.gitignore` so a local failing test no longer shows up as a change. No code or data change.
  * [x] Package phase 6, slice 1: app helpers from edjobs 0.36.0 (2026-11-16; branch `phase6-slice1`). 22 functions
    both states' app.R defined identically (pay/date/MOE text, sparklines, trends and movers, job search, first-seen
    fill) now come from edjobs; app.R attaches it (`library(edjobs)`) and its copies are gone, with the app's copy of
    `first_seen_key()`. `fill_first_seen()` now takes `lookup = first_seen_table`. Checks: package vs app copies on
    both states' data 64/64 identical; app.R from main vs branch: all 82 data objects identical, every tab's 36
    outputs and the rows shown (7 tables, 89 rows) identical (`claude-notes/2026-11-16_phase6/`). Suite 3,214 passed; the
    only failures are the new committed-manifest test, which passes once manifest.json is rewritten from edjobs
    v0.36.0 installed from GitHub (the PR carries that manifest; the weekly run's manifest check now also requires
    edjobs as a GitHub package at the pinned tag). New test `test-app-no-local-copies.R`: app.R/feedback.R define no
    edjobs export. The unit tests moved to edjobs.
  * [x] Package phase 6, slice 2: app helpers that read an app global, from edjobs 0.37.0 (2026-11-17; branch
    `phase6-slice2`). Six functions (`validate_and_pad_schema`, `in_pay_band`, `relabel_spell_status`,
    `map_marker_radius`, `dictionary_columns_help`, `footer_retrieved`) now come from edjobs, with what they read
    from app globals passed as arguments (36 calls); app.R's copies and three constants are gone, and
    `note_load_issue()` collects the schema-guard banner text. Checks: edjobs `equivalence_slice2.R` 148 checks, 0
    differences; app.R from main vs branch: every data object identical (79; only the 3 constants gone), every tab's
    36 outputs identical (shinytest2, `parity2-mt.log`, `claude-notes/2026-11-16_phase6/`). Suite 3,196
    passed; the one failure is the EDJOBS_VERSION pin test until the pin moves to 0.37.0.
  * [x] Pin edjobs 0.38.0 (the 2026-11-17 full review's fixes) and split posting spells at gaps (2026-11-17; branch
    `pin-0.38.0`). `scripts/build_posting_spells.R` runs `split_posting_gaps()` after `bridge_posting_ids()` for
    K-12 and before `use_earliest_posted_date()` for college (Mike's evidence rule, workspace
    `claude-notes/2026-11-17_spells-gaps/`): same posted date on both sides of a gap stays one spell; a later posted
    date splits it and the earlier piece ends; no date splits it and the earlier piece is censored ("censored: back
    after a gap"); stable IDs never split. On the committed archives: K-12 2,852 -> 2,856 postings, 470 -> 472
    endings in durations, median 28 -> 25.5 days, 4 pieces censored back after a gap; college 927 -> 929 postings,
    244 endings, median 31.5 -> 32.5, 2 censored. manifest.json: main's, with only the edjobs entry from v0.38.0
    installed from GitHub (464c49c). Full rehearsal (`claude-notes/2026-11-17_rehearsal-mt-pin-0.38.0.log`): every
    step passed, suites 3,218 / 3,233 passed, 0 failed; OPI statewide 333 rows, no source errors; K-12 rows 1,369 ->
    1,393, college 381 -> 375.
  * [x] Twice-weekly runs, state side (2026-11-17; branch `twice-weekly`, edjobs 0.39.0 pinned). History checks count
    weeks, not runs or files: `check_pay_coverage.R` reads each ISO week's last run, `check_title_quality.R` the last
    56 days. `weekly-scrape.yml` runs in Mountain time (`TZ: America/Denver`; the Mac rehearsals already did), and a
    new step puts the daily presence check's last-commit age on the run summary, with a drift-issue section only when
    it is over 3 days old (Mike 11-17). The app rolls weekly totals up to each ISO week's last run; on the committed
    data only the extra runs of a week drop (08-06, 09-07), everything else unchanged. Archive replay
    (`claude-notes/2026-11-17_twice-weekly-replay/`): spells identical; frozen boards 9 -> 6; the same 19 drift and
    pay flags. Full rehearsal (`claude-notes/2026-11-17_rehearsal-mt-twice-weekly.log`): every step passed, suites
    3,218 / 3,233 passed, 0 failed; OPI statewide 333 postings; K-12 rows 1,369 -> 1,388, college 381 -> 378. The
    second weekly cron is a separate change.
  * [x] Second weekly run (2026-11-17; branch `second-cron`): `weekly-scrape.yml` cron `0 13 * * 1,4`, Mondays and
    Thursdays (was Tuesdays); Wyoming moves to Tuesdays and Fridays, so the shared `CENSUS_API_KEY` is never used by
    both on one day (days set by Mike 11-13). CLAUDE.md, README and the scraper skill's run-day line updated.
  * [x] Pin edjobs 0.40.0, the classifier batch (2026-11-17; branch `pin-0.40.0`): posted pay with a benefit word
    after the amount, part-time FTE, subjects from school/place names, HE job types, Apptegy "open until filled".
    Committed data (the 11-17 run, d73b27d) reclassified (`scripts/reclassify_committed_data.R --apply --skip-guard`;
    the guard needs the old version installed, and the 11-17 run on 0.39.0 rebuilt all 9 files exactly):
    combinedclean 4 Teacher -> Part-Time Teacher (two ".5 FTE" titles, two OPI postings marked part-time),
    k12jobanalysis 8,097 -> 8,065, allsum 6,489 -> 6,470, allnow 309 -> 305, HE spells per bugs 9/11. The script's
    `write.csv` quoted every date in combinedclean.csv; the file was patched back to the committed text with only the
    6 changed fields (values identical). `run_expectations.csv`: `cyberschool_vaughn_read` filters on
    vaughnschool.com/jobs/ (its links were never on iescentral.com; the 11-17 run read the posting). Full rehearsal
    (`claude-notes/2026-11-17_rehearsal-mt-pin-0.40.0.log`): every step passed but the pre-run suite's app boot
    smoke test (1 failure, Chrome timing while the render ran; 21/21 alone after); post-run suite 3,229 passed, 0
    failed; OPI statewide 333 postings; K-12 rows 1,374 -> 1,372.
  * [x] "How postings are counted" note moved from the top of the K-12 Trends tab to just below the Multi-Year Trends
    chart (2026-11-17, Mike; branch `counting-note-placement`), text unchanged. Checked by screenshot
    (`claude-notes/2026-11-17_counting-note/`); app smoke 21 and reactives 718 passed, 0 failed.
  * [x] Home: top job types, pin edjobs 0.41.0 (2026-11-18; branch `home-job-types`; plan
    `claude-notes/2026-11-17_home-job-types-plan.md`, flag rules `claude-notes/2026-11-18_not-full-time/`). The
    vacancy-rate plots, the biggest-mover boxes and their footnote are gone from Home; "Top K-12 / Higher Ed Job
    Types This Week" cards take their place (open postings, share, 12-run sparkline; a click opens that type's
    jobs). The top tables and the KPI cards count postings edjobs `classify_work_schedule()` doesn't mark as
    substitute, extra duty, part-time, student job or temporary: K-12 855 of 1,374, college 256 of 380. A switch on
    Home (on by default; "Leave out substitutes, coaching, part-time, student and temporary jobs") sets which postings
    the four top tables count, their Share and their sparklines, and the Jobs table a Home link opens follows it (a
    map popup link never does); the KPI cards keep both numbers (plan `claude-notes/2026-11-18_sparkline-basis/PLAN.md`,
    Mike 11-18). For the district and college sparklines, `k12_district_weekly_totals.csv` /
    `he_institution_weekly_totals.csv` gain `n_not_marked` (edjobs `posting_run_totals()`, pipeline and both rebuild
    scripts), backfilled from the archives (K-12 3,224 rows, college 346; the rebuilt `n` equals the committed `n` on every
    row; script `claude-notes/2026-11-18_sparkline-basis/backfill_n_not_marked.R`); schema and data dictionary
    cover the column. Switch screenshots `claude-notes/2026-11-18_sparkline-basis/shots/`. Rehearsal
    (`claude-notes/2026-11-18_rehearsal-mt-sparkline-basis.log`): every pipeline step passed but the manifest
    (until v0.41.0 is tagged), rebuild parity 11/11, K-12 rows 1,374 -> 1,371; the history-accumulator test still
    counted this week's totals the old way (fixed after: `posting_run_totals()`). Suite on the final tree: 3,275
    passed, 2 failed (the manifest test). The pipeline and
    both rebuild scripts write `k12_jobtype_weekly_totals.csv` / `he_jobtype_weekly_totals.csv` (edjobs
    `jobtype_run_totals()`), backfilled from the archives: 236 and 306 rows, 18 runs 2026-08-06 to 2026-11-17;
    schema, data dictionary, rebuild parity and reclassify cover them. On a phone the Share column is hidden and
    type names break after "/". Full rehearsal (`claude-notes/2026-11-18_rehearsal-mt-jobtype-0.41.0.log`): every
    pipeline step passed, rebuild parity 11/11; the manifest step and its test fail until v0.41.0 is tagged on
    GitHub (edjobs installed from disk); post-run suite 3,236 passed, those 2 failed; OPI statewide 333 postings;
    K-12 rows 1,374 -> 1,377. App tests on the final tree: reactives 730/0, boot smoke 21/0. Screenshots
    `claude-notes/2026-11-18_home-job-types-shots/`.
  * [x] Pin edjobs 0.42.0 (2026-11-18; branch `home-job-types`, replaces the 0.41.0 pin). 0.41.0 is the job-type
    flags the Home switch uses; 0.42.0 adds a day rate for a full/half day written before the amount (Melstone's
    "Full day/$100 and 1/2 day/$50": unit NA -> day) and `write_csv_keep_quoting()`, which
    `scripts/reclassify_committed_data.R` now writes with (the file's own quoting kept; no more quoting every date in
    combinedclean.csv). manifest.json's edjobs entry is from a pak install of the `v0.42.0` tag (only version, refs,
    SHA and build dates change). Reclassify dry run (`claude-notes/2026-11-18_pin-0.42.0/reclassify-dryrun-mt.log`):
    guard passed on v0.42.0, nothing to write. Pay units are set at scrape time and the rebuild doesn't recompute
    them, so the committed Melstone row keeps NA until the next run re-scrapes it. Live Apptegy scrape of Melstone
    on 0.42.0 (`claude-notes/2026-11-18_pin-0.42.0/melstone-live-mt.log`): 8 rows, the substitute posting $100/day.
    Suite: 3,277 passed, 0 failed (manifest test passes).
  * [x] Pin edjobs 0.44.0 (2026-11-19; branch `pin-0.44.0`, replaces the 0.42.0 pin). 0.43.0: pay units after a
    `;` and wrapped ranges (Browning "Lane 3/Step 0; $21.16" -> hour, Townsend "$13.52 -" / "$13.82/hour" ->
    $13.52-$13.82/hour; replay of 1,044 archived Pay_Text: 1 changes); with Melstone (0.42.0) this should let `k12_pay_has_unit` pass once the next run re-scrapes them. 0.44.0, the hardening release: 170 exports
    made internal, no state names in package code, `state_config(timezone = )` (set here to America/Denver, the value
    the package used as its default), front matter. `scripts/reclassify_committed_data.R` reads the package namespace
    (`asNamespace`), since some helpers are no longer exported. manifest.json's edjobs entry is from a pak install of
    the `v0.44.0` tag (version, Title, Description, refs, SHA, build dates). Full rehearsal
    (`claude-notes/2026-11-19_rehearsal-mt-pin-0.44.0.log`): every step passed, pre-run and post-run suites 3,277 passed, 0 failed.
  * [x] Pin edjobs 0.46.0 (2026-11-19; branch `package-specs`, replaces the 0.44.0 pin).
    The scraper specs for the platforms edjobs scrapes now come from the package (`edjobs::default_scraper_specs()`,
    0.46.0; review step 4): `state_config.R` passes `scraper_specs(...)` with only this state's own scrapers (Tyler Portico, the heuristics, JazzHR, Paycom) and the HE Apptegy (Stone Child) spec, so a
    district on a known platform is one registry row. These specs drive the PR live check, `scripts/repro_scraper.R`
    and the auto-fix issue, not the weekly pipeline. Dispatch parity (every source's resolved call before vs after,
    `claude-notes/2026-11-19_package-specs/`): 224 of 224 sources identical. Also in the pin: 0.45.0's `state_config(oews_areas = )`
    (`oews_area_definitions()` identical to 0.44.0's for this state, 81 rows) and the toy state in package CI.
    manifest.json's edjobs entry is from a pak install of the `v0.46.0` tag. `mt_list_rule()` (which re-read the registry CSV for every argument) is gone. Suite on the tag: 3,277 passed, 0 failed.
  * [x] Scraper skill synced from the toolkit (2026-11-19): the specs for platforms edjobs scrapes come from
    `edjobs::default_scraper_specs()` (0.46.0; montana.md, wyoming.md), and an edjobs helper may be internal since
    0.44.0 (ci-automation.md: list the namespace with `ls(asNamespace("edjobs"))`, call one as `edjobs:::name`).
  * [x] Pin edjobs 0.47.0: pipeline stages, slice 1 (2026-11-19; branch `stage-context`, replaces the 0.46.0 pin).
    The Rmd's two Census ACS county-context blocks (salarymap2.csv, salarymap.csv) are now
    `refresh_county_context()` calls, and the source-record-links loop is `refresh_source_record_links()` (edjobs
    0.47.0; review step 5). `state_config.R` sets `county_suffix = ", Montana"` (what the Rmd passed by hand).
    manifest.json's edjobs entry is from a pak install of the `v0.47.0` tag. Full rehearsal
    (`claude-notes/2026-11-19_rehearsal-mt-stage-context-0.47.0.log`): every step passed (data quality 125/0). The
    rehearsed files' ACS columns equal the committed ones (same vintage) apart from the last digit of 13 floating
    values (`Mining_Employment_Share` and its MOE, Yellowstone and Daniels counties; largest difference 1e-17).
  * [x] OPI answer key: `week1110` set (2026-11-19). 18 hand-judged OPI postings from the 2026-11-10 run
    (`claude-notes/2026-11-10_opi-matcher-11-10-check.md`): the new postings (Hardin's two copies), the matches new that
    week, the 5 whose board twin was gone, and Manhattan's ASL intervener (no match; fixed 11-10 in 0911e70). Anaconda's
    SPED posting is labeled the same opening as the board's "Elementary Special Education Teacher" (Mike, 11-19: the
    board's SPED vacancy was reposted from 07-31 on). Fixtures `opi_match_{labels,boards}_2026-11-10.csv` (boards = that
    run's 1,170 direct rows; recomputing the run from them gives its decisions except Manhattan, which the 0911e70 fix
    changed). New test in `test-opi-matcher.R`: every label holds (passes). 8 postings the 11-10 note never judged
    (Monforton, Malta, Colstrip K-8, Three Forks, Helena, Big Timber, Poplar, Rocky Boy) are left out.
  * [x] Pin edjobs 0.49.0: pipeline stages, slices 2 and 3 (2026-11-19; branch `stage-columns`, replaces the 0.47.0 pin).
    Six fetch-then-swap-columns blocks are now `refresh_file_columns()` calls (edjobs 0.48.0/0.49.0; review step 5):
    the HE chunk's IPEDS enrollment, 5-year enrollment trend and FSA Pell share (the chunk now writes salarymap.csv
    after its salary part and each refresh reads, swaps and writes), and the K-12 chunk's SAIPE child poverty (with
    `add_saipe_range()` as its `then` step), OPI district finance (its `Finance_Source` label as `then`) and CCD
    free/reduced lunch (`relationship = "many-to-one"`; the fetched table stays in `frl_all` for the OPI-only
    districts chunk). `test-pipeline-defensiveness.R` counts `refresh_file_columns()` / `refresh_county_context()`
    as guards (they run their fetch through `safe_scrape()`). manifest.json's edjobs entry is from a pak install of
    the `v0.49.0` tag. Full rehearsal (`claude-notes/2026-11-19_rehearsal-mt-stage-columns-0.49.0.log`): every step
    passed (data quality 125/0); the rehearsed salarymap.csv (23 rows) and salarymap2.csv (201 rows) equal the
    committed files in every column.
  * [x] Scheduled runs moved to 07:17 UTC (2026-11-19; Mike: run very early, so a failure can be fixed and re-run the
    same day and is known by morning). Just after midnight Mountain (00:17 MST, 01:17 MDT): every step's date is
    Mountain (`TZ`), so a start before midnight would date the run the day before. GitHub started the 13:00 UTC cron
    4-8.5 h late (runs since 09-25: 17:08-21:27 UTC), and the daily presence check's 13:17 UTC cron 5.5-9.5 h late,
    so an off-the-hour minute doesn't avoid it. Days unchanged (MT Mon/Thu, WY Tue/Fri; shared Census key).
  * [x] Pin edjobs 0.52.0: weekly check scripts in the package (2026-11-19; branch `step6-scripts`, replaces the
    0.49.0 pin; review step 6, `claude-notes/2026-11-19_step6-scripts-measure.md`). Nine `.github/scripts` are now
    short calls into edjobs (0.50.0-0.52.0): sanity, schema, run expectations, render-with-stack, drift
    (`check_drift_step()`), pay coverage, title quality, the pre-flight canary (`canary_step()`) and rebuild parity
    (`report_rebuild_parity()`; the script still sources the state's rebuild files). What differed by state is in
    `state_config.R`: `k12_source_names` (OPI rows as one source; archives before `Posting_Source` left out),
    `drift_min_mean = 2`, and the feed's canary `signature` and `cainfo`. Workflow paths unchanged.
    `test-canary-api-check.R` moved to edjobs. Parity of old and new scripts on the committed data:
    `claude-notes/2026-11-19_step6-parity/`. manifest.json's edjobs entry is from a pak install of the `v0.52.0` tag.
    Full rehearsal (`claude-notes/2026-11-19_rehearsal-mt-step6-0.52.0.log`): every step passed (canary, data quality
    125/0, rebuild parity "all 11 files reproduced from the archives"); suite 3,269/0 before the run, 3,271/0 after,
    1 skip.
  * [x] Pin edjobs 0.53.0: the Census check and the auto-fix live check in the package (2026-11-19; branch
    `step6-census`, replaces the 0.52.0 pin; review step 6, slice 4). `check_census_drift.R` is
    `check_census_step()` and `live_check_autofix.R` is `live_check_autofix_step()` (the script sources the scraper
    files first). The Census check's expected counts now come from `salarymap2.csv` / `salarymap.csv`: the script's
    hard-coded ones had gone stale (19 counties and 32 districts against 56 and 201), so a source could lose most of its coverage before it fired. Every county
    should have ACS context and every district a SAIPE rate, except `state_config(saipe_gaps = )` (none in Montana).
    Parity (`claude-notes/2026-11-19_step6-parity/slice4/`): identical output on the committed data (healthy); on a
    copy with two SAIPE rates blanked, the new check flags both by name where the old script passed. Live check run with the state's real
    scrapers through a stubbed `gh` (Lone Rock: 0 postings, as committed; Red Lodge: 4). manifest.json's edjobs entry is from a pak install of the `v0.53.0` tag
    (Suggests gained chromote). Single-step change: each new script run on the committed data, plus the suite 3,269 passed, 0 failed, 1 skip, plus 2 app boot smoke failures from Chrome contention with the live checks; that file passes alone, 21/0.
  * [x] Salary source named only where that source gave a salary (2026-11-19; branch `dli-source-label`, found while
    measuring the salary drift check). The pipeline set `Salary_Source` on every row, so 52 registry districts DLI
    doesn't report and two colleges IPEDS reports under their parents (Highlands College, Missoula College) showed
    "Salary source: ..." in their map popup with no salary above it. The OPI-only rows already blanked it. Now the
    K-12 and HE blocks name the source only where `Teacher_Avg_Salary` / `Faculty_Avg_Salary` is present; the
    committed files' 52 + 2 cells were blanked (every other column unchanged, and the new expression on the old file
    gives the repaired one exactly). New data-quality test: a named source with no salary fails.
  * [x] Pin edjobs 0.54.0: the auto-fix issue step in the package (2026-11-19; branch `step6-autofix`, replaces the
    0.53.0 pin; review step 6, slice 5). `file_autofix_issues.R` is `file_autofix_issues_step()`; the script keeps its
    own sourcing (`drift_check.R`). Parity (`claude-notes/2026-11-19_step6-parity/slice5/`): a fake `gh` on PATH logs every call,
    its body file and token; five scenarios (Claude dispatch; Copilot assignment and its PR; an edjobs companion
    issue; escalation to Claude; Copilot refusing; recovery closes with the companion; a confirmed_broken comment; no
    results file; the cap) give identical calls and output from the old script, the package function and the new
    script. manifest.json's edjobs entry is from a pak install of the `v0.54.0` tag. Suite on the tag: 3,273 passed, 0 failed, 1 skip.
  * [x] Pin edjobs 0.55.0: the drift corroboration in the package (2026-11-19; branch `step6-corroborate`, replaces the
    0.54.0 pin; review step 6, slice 6). `corroborate_drift.R` is `corroborate_drift_step()`; the script keeps its
    own sourcing. Live parity, Gemini off (`claude-notes/2026-11-19_step6-parity/slice6/`): five flagged sources (a
    scrape error, no URL, live boards, a college) through the old script and the new one give the same verdicts,
    `drift_results.csv`, report and printed lines (the old script also printed `[1] TRUE` from closing the browser). manifest.json's edjobs entry is from a pak install of the
    `v0.55.0` tag. Suite on the tag: 3,273 passed, 0 failed, 1 skip.
  * [x] Pin edjobs 0.56.0: a drift corroboration with no LLM reading keeps its verdict (2026-11-19; branch
    `pin-0.56.0`, found during slice 6). With no reading (no key, a failed or quota-limited Gemini call, a rejected
    count) the corroboration had turned "inconclusive" pages into "looks_genuinely_empty" ("an LLM read no postings
    off the live page either"), which the drift report leaves out, so a Gemini outage would hide them. Now they stay
    inconclusive and are reported; a real empty reading still downgrades. A source the statewide feed lists postings
    for, with no reading, now stays inconclusive (a human look) instead of reaching likely_broken (an auto-fix issue)
    through that downgrade. Live run with the key off (`claude-notes/2026-11-19_llm-unavailable/live-0.56.0.log`):
    Lone Rock, Red Lodge and MSU now inconclusive, as expected. manifest.json's edjobs entry is from a pak install of the `v0.56.0` tag.
    Suite on the tag: 3,273 passed, 0 failed, 1 skip.
  * [x] Pin edjobs 0.57.0: the salary-source check in the package, coverage against last run's committed file
    (2026-11-20; branch `step6-salary-drift`, replaces the 0.56.0 pin; review step 6, slice 7; Mike chose B over
    per-source gap lists). `check_salary_drift.R` is `salary_drift_step()`; the sources, value bounds and
    year-over-year pairs are `state_config(salary_checks = )`. The typed-in counts had gone stale (CCD and OPI finance expected 32 against 201, DLI 25-27 against 149). A drop names the districts or colleges that lost a value; it is
    flagged once (after that run's commit it is the baseline). Replayed on every committed version of both states'
    salary maps (75 commits): no false flags. Parity (`claude-notes/2026-11-19_step6-parity/slice7/`): same output on the
    committed data apart from one reworded sentence; with 10 DLI districts blanked the old script passed and the new one names
    them. Rehearsals have no `.git`: `dryrun.sh` sets `EDJOBS_SALARY_BASELINE`. manifest.json's edjobs entry is from a pak
    install of the `v0.57.0` tag. Suite on the tag: 3,273 passed, 0 failed, 1 skip.
  * [x] Pin edjobs 0.58.0: MT's general-fund range is per enrolled student (2026-11-20; branch
    `salary-fund-per-student`; Mike chose per student). The $500k floor, set when the smallest of 32 districts spent
    $2.1M, flagged 13 real districts of 4-46 students every week since the 11-10 registry growth. Replayed on every
    committed salarymap2.csv (`claude-notes/2026-11-20_mt-general-fund-bound.md`): $3k-$60k a student flags 0 in each,
    and a misread digit gives ~$950 or ~$96k a student at any district size. The dollar range stays for rows with no
    CCD enrollment (`salary_checks(bounds = )` `per` / `unless`, edjobs 0.58.0). Live step on the committed data: the
    13 flags gone; Swan River's DLI 10th percentile ($16,900) still flags. Report amounts are whole dollars.
    manifest.json's edjobs entry is from a pak install of the `v0.58.0` tag. Suite on the tag: 3,273 passed, 0 failed, 1 skip.
  * [x] The weekly run is edjobs's reusable workflow (2026-11-20; branch `weekly-run`, edjobs #58, v0.59.0; review
    step 6, second half). `weekly-scrape.yml` is a short caller: cron, `concurrency`, `permissions`, secrets passed one
    by one, and Montana's data as inputs (`tibble`, Gemini on the pipeline step, `check_opi_crosscheck.R`, the OPI
    commit files, the LLM shadow file). The `uses:` tag equals `EDJOBS_VERSION` (`test-weekly-workflow-ref.R`).
    Test dispatch on a branch (run 44675428576, data discarded): success, the same 40 step outcomes as the 11-19 run
    44602197341 apart from three renamed steps and the auto-fix filing (skipped off main), a commit dated 2026-11-19
    in Mountain time, the OPI cross-check (127 QC rows, 19 adoption candidates) and the salary check's git baseline.
    Pin 0.59.0 (no R change). manifest.json's edjobs entry is from a pak install of the `v0.59.0` tag. Suite on the tag: 3,275 passed, 0 failed, 1 skip.
  * [x] Package review step 7, slice 1 (+ 2a): the app's shared server, UI helpers, Feedback form and Listing
    Duration tabs from edjobs 0.60.0 (2026-11-21; branch `app-server-shared`, edjobs #59; Mike's choice A, 11-20).
    `server` calls `dashboard_server_shared()` first (the 101 server blocks both states had identical or differing
    only by the state's name) and keeps this state's own 14 blocks, which read 7 of its reactives; `outputOptions()`
    on the map stays here because it must run after the state's map output exists (the first parity run failed on
    it). The six UI helpers, `feedback.R` and the two Listing Duration panels (`k12_spells_panel()`,
    `he_spells_panel()`) are gone from the app folder; app.R 3,772 -> 2,271 lines. Tests: `test-feedback.R` moved to
    edjobs; `test-app-reactives.R` reaches shared internals as `shared$name()`; the data-dictionary download test
    also reads the package's handlers (same download files as main). Checks vs main: every data object identical
    (87); every tab's outputs identical (shinytest2, 34/34). edjobs 0.60.0 also carries the Carbon
    posted-pay fix. manifest.json: the edjobs entry (with its new Suggests) from a pak install of the `v0.60.0` tag,
    feedback.R out of the file list, stale file checksums refreshed. Suite on the tag: 3,246 passed, 0 failed, 1 skip. Notes and scripts:
    `claude-notes/2026-11-21_step7-slice1/`.
  * [x] Package review step 7, slice 2b, Data tab: its UI from edjobs 0.61.0's `data_tab_panel()` (2026-11-21;
    branch `data-tab-panel`, edjobs #60; Mike 11-21: the package builds each tab, the state passes its text, one tab
    per PR). app.R keeps only Montana's own text: 10 `data_tile()`s (fields it leaves out take the shared default
    for that download), the provenance rows (`data_provenance_row()`; county, student need, CCD staffing and IPEDS
    pay rows shared), and the citation and repository. The tile counts are now computed from the downloads at app
    start (`download_rows()`, `rows_phrase()`); the hand-written ones were stale: 3,200+ K-12 history records and 3,700+ weekly observations for downloads of 8,401 and 2,891 rows; now 8,400+ and 2,800+. Checks vs main
    (`claude-notes/2026-11-21_step7-slice2b-data/`): page HTML identical before the counts commit, only the count
    lines after it (`ui_parity.R`); every tab's outputs identical (shinytest2, 34/34, 89 table rows shown);
    Data tab screenshots looked at. manifest.json edjobs entry from a pak install of the `v0.61.0` tag;
    EDJOBS_VERSION and the weekly workflow ref 0.61.0. Suite on the tag: 3,246 passed, 0 failed (with NOT_CRAN=true, so the app boot test runs).
    Live 11-21 01:05 UTC: new counts shown; Home, Map, Data, K-12 Jobs connected with 0 errors, 3 tries.
  * [x] Package review step 7, slice 2b, Map tab: its UI from edjobs 0.62.0's `map_tab_panel()` (2026-11-21;
    branch `map-tab-panel`, edjobs #61, this repo's #87). app.R keeps only Montana's own text: the "About this map"
    paragraphs, what the red "Partial" badge means here, and the note under the map; filters and map are the
    package's. Checks vs main (`claude-notes/2026-11-21_step7-slice2b-map/`): page HTML identical (239,767 chars,
    `ui_parity.R`); every tab's outputs identical (shinytest2, 34/34, 89 table rows shown). manifest.json: the edjobs
    entry (leaflet now in its Suggests) for the `v0.62.0` tag, and app.R's checksum; EDJOBS_VERSION and the weekly
    workflow ref 0.62.0. Suite on the tag: 3,246 passed, 0 failed, 1 skipped.
  * [x] Package review step 7, slice 2b, both Jobs tabs: K-12 Jobs and Higher Ed Jobs from edjobs 0.63.0's
    `jobs_tab_panel(level, pay_note)` (2026-11-21; branch `jobs-tab-panel`, edjobs #62, this repo's #88). The two tabs
    differ only in their ids, Higher Ed's Appointment filter and the pay note, so one function and one PR (Mike 11-21).
    app.R keeps only Montana's pay notes. Checks vs main (`claude-notes/2026-11-21_step7-slice2b-jobs/`): page HTML
    identical (239,767 chars, `ui_parity.R`); every tab's outputs identical (shinytest2, 34/34, 89 table rows shown).
    edjobs R CMD check OK (0/0/0). manifest.json: the edjobs entry for the `v0.63.0` tag, and app.R's checksum;
    EDJOBS_VERSION and the weekly workflow ref 0.63.0. Suite on the tag: 3,246 passed, 0 failed, 1 skipped.
  * [x] Package review step 7, slice 2b, Higher Ed Trends: its UI from edjobs 0.64.0's `he_trends_panel()`
    (2026-11-21; branch `he-trends-panel`, edjobs #63, this repo's #89). app.R passes Montana's timeline window
    (bounded to the archive, WINDOW_WEEKS). Checks vs main (`claude-notes/2026-11-21_step7-slice2b-he-trends/`): page
    HTML identical (239,767 chars, `ui_parity.R`); every tab's outputs identical (shinytest2, 34/34, 89 table rows
    shown). edjobs R CMD check OK (0/0/0). manifest.json: the edjobs entry for the `v0.64.0` tag, and app.R's
    checksum; EDJOBS_VERSION and the weekly workflow ref 0.64.0. Suite on the tag: 3,246 passed, 0 failed, 1 skipped.
  * [x] Package review step 7, slice 2b, Higher Ed Colleges: its UI from edjobs 0.65.0's `he_colleges_panel()`
    (2026-11-21; branch `he-colleges-panel`, edjobs #64, this repo's #90). app.R keeps Montana's two directory notes
    (Salaries: the IPEDS all-ranks average; County: income, rent, mining/energy share and population trend) and opens
    the comparator on MSU vs UM. Checks vs main (`claude-notes/2026-11-21_step7-slice2b-he-colleges/`): page HTML
    identical (239,767 chars, `ui_parity.R`); every tab's outputs identical (shinytest2, 34/34, 89 table rows shown).
    edjobs R CMD check OK (0/0/0). manifest.json: the edjobs entry for the `v0.65.0` tag, and app.R's checksum;
    EDJOBS_VERSION and the weekly workflow ref 0.65.0. Suite on the tag: 3,246 passed, 0 failed, 1 skipped.
  * [x] Package review step 7, slice 2b, K-12 Trends: its UI from edjobs 0.66.0's `k12_trends_panel()` (2026-11-21;
    branch `k12-trends-panel`, edjobs #65, this repo's #91). app.R keeps Montana's two pieces: the slider label
    (`slider_label = TRUE`) and the note under the multi-year chart on how OPI postings are counted against district
    boards (`counting_note`). Checks vs main (`claude-notes/2026-11-21_step7-slice2b-home-districts/`): page HTML
    identical (239,767 chars, `ui_parity.R`); every tab's outputs identical (shinytest2, 34/34, 89 table rows shown).
    edjobs R CMD check OK (0/0/0). manifest.json: the edjobs entry for the `v0.66.0` tag, and app.R's checksum;
    EDJOBS_VERSION and the weekly workflow ref 0.66.0. Suite on the tag: 3,246 passed, 0 failed, 1 skipped.
  * [x] Package review step 7, slice 2b, Home: its UI from edjobs 0.67.0's `home_tab_panel()` (2026-11-21; branch
    `home-tab-panel`, edjobs #66, this repo's #92). app.R passes Montana's name, where its K-12 postings come from,
    the refreshed date, the credit line and its K-12 coverage card (`extra`); the switch label and its two notes
    (HOME_SWITCH_LABEL, NOT_MARKED_NOTE, NOT_MARKED_NOTE_HE) now come from edjobs. Checks vs main
    (`claude-notes/2026-11-21_step7-slice2b-home-districts/`): page HTML identical (239,767 chars, `ui_parity.R`);
    every tab's outputs identical (shinytest2, 34/34, 89 table rows shown). edjobs R CMD check OK (0/0/0).
    manifest.json: the edjobs entry for the `v0.67.0` tag, and app.R's checksum; EDJOBS_VERSION and the weekly
    workflow ref 0.67.0. Suite on the tag: 3,246 passed, 0 failed, 1 skipped.
  * [x] Package review step 7, slice 2b, K-12 Districts (the last tab): its UI from edjobs 0.68.0's
    `k12_districts_panel()` (2026-11-21; branch `k12-districts-panel`, edjobs #67, this repo's #93). app.R keeps
    Montana's text (the Openings note, the directory's pay/finance/county paragraphs and source, the comparator
    blurb, the openings source), the comparator's opening pair (Billings vs Kalispell) and its salary chart's card
    (DLI teacher average and county income). Checks vs main (`claude-notes/2026-11-21_step7-slice2b-home-districts/`):
    page HTML identical (239,767 chars, `ui_parity.R`); every tab's outputs identical (shinytest2, 34/34, 89 table
    rows shown). edjobs R CMD check OK (0/0/0). manifest.json: the edjobs entry for the `v0.68.0` tag, and app.R's
    checksum; EDJOBS_VERSION and the weekly workflow ref 0.68.0. Suite on the tag: 3,246 passed, 0 failed, 1 skipped.
    With all 11 tabs from edjobs, app.R is 1,716 lines (2,107 before slice 2b).
  * [x] Package review step 7, slice 3, part 1: the server blocks that differed only by a setting come from edjobs
    0.69.0's `dashboard_server_shared()` (2026-11-21; branch `slice3-config`, edjobs #69, this repo's #95): the
    map's basemaps, legend and opening view (`map_view`, -111.5/46.8, zoom 7) and county zoom, the Institution
    Summary table (page length 6), the HE slider's opening range and the slider labels
    (`bounded_timeline_value()` / `timeline_history_note()` now edjobs's). Dead `k12_new_table` removed (no UI showed
    it). The Feedback form's report time takes `timezone = "America/Denver"` (edjobs had the zone hard-coded since
    0.60.0). Map marker popups stay here for part 3 (their pay lines differ by state). Checks vs main
    (`claude-notes/2026-11-21_step7-slice3a/`): every tab's outputs identical (shinytest2, main on 0.68.0 vs branch on
    0.69.0, 34/34, 89 table rows shown). manifest.json: the edjobs entry for the `v0.69.0` tag, and app.R's
    checksum; EDJOBS_VERSION and the weekly workflow ref 0.69.0. Suite on the tag: 3,244 passed, 0 failed,
    1 skipped. app.R is 1,508 lines (1,716 before).
**Open work (moved here from claude-notes handoff, 2026-11-03; this list is the source of truth):**
- [ ] **Later (Mike 11-16, parked): a way for someone sending feedback to get a reply.** An email can't go in the
  report: it becomes a public issue (edit history keeps it). Options: (A) a "want a reply? email ..." line with a
  separate address, recommended; (B) an optional field whose address the app emails to Mike privately via a mail
  service (new account and secret; the form then needs a note on how the address is used); (C) the address
  encrypted in the issue (ruled out: clumsy).
- [ ] **Citations audit follow-ups (2026-11-15; `claude-notes/2026-11-15_citations-audit.md`), decisions for Mike:**
  BLS asks for the access date (apps don't know it yet); WSBA/WDE pages say "All rights reserved" with no reuse
  terms. (Esri basemaps: done, replaced 11-15.)
- [ ] **R package migration (current focus, Mike 2026-11-10):** shared code moves to `bostickmike/edjobs`, pinned in
  `EDJOBS_VERSION` (plan and status: `claude-notes/2026-11-10_r-package-migration-plan.md`). Phase 0 merged 11-11
  (run expectations; edjobs 0.0.1). Phase 1 merged 11-11 (edjobs v0.2.0: scrape helpers, posting status, coverage
  calendar, BLS OEWS, BLS QCEW, LLM extraction; MT PR #16, WY PR #8; full rehearsal in both states, WY test dispatch
  on the branch passed). Phase 2 on branch `edjobs-phase2` (11-11, edjobs v0.4.0): the classifier and posted pay, IPEDS staff salaries,
  41 shared drift/data-quality/auto-fix definitions, `check_file_schema()`, `check_total_matches_parts()`,
  `rebuild_parity_row()`; this repo keeps its name corrections, posting identity, dispatch, baselines and schemas.
  Suites on 0.4.0: MT 3,555 passed, 0 failed; full rehearsal passed every step, rebuild parity 9/9
  (`claude-notes/2026-11-11_rehearsal-mt-edjobs-phase2.log`). Phase 2 merged 11-11 (MT PR #20 -> 5e1677c).
  Phase 3 on branch `edjobs-phase3` (11-11, edjobs v0.5.0): the shared platform scrapers (AppliTrack fetch/parse,
  SchoolSpring details and ending reasons, PeopleAdmin page pay and dates, NEOGOV card pay). Auto-fix for a scraper
  that lives in edjobs: Copilot first on a companion edjobs issue, then the Claude fallback, which checks edjobs out
  in `.edjobs/` and opens its PR there. Suite on 0.5.0: MT 3,450 passed, 0 failed; full rehearsal passed every
  step, rebuild parity 9/9 (`claude-notes/2026-11-11_rehearsal-mt-edjobs-phase3.log`). Design rule from 11-11: build
  for N states and one stackable schema (plan section 2a).
  Phase 4, first slice, on branch `edjobs-phase4-spells` (11-11, edjobs v0.6.0): the posting-spells engine
  (bridging, endings, starts, flags, durations, first-seen lookup) moved to edjobs; this repo keeps its panels
  and its rules (`MT_K12_SPELL_RULES / MT_HE_SPELL_RULES` in `posting_spells.R`, a `spell_rules()` object). Rebuilt from the archives, every
  pre-existing column of the committed spells is unchanged (2,852 K-12 + 927 HE postings); the files gain the shared
  36-column schema (`POSTING_SPELL_COLUMNS`, `Is_OPI` renamed `Is_Feed`). Suite on 0.6.0: MT 3,396 passed, 0 failed.
  MT's five remaining rule differences, measured: `claude-notes/2026-11-11_spells-convergence.md` (decision for Mike).
  Phase 4 slice 1 merged 11-11 (MT PR #22 -> 02c1e45). Slice 2 on branch `edjobs-phase4-state-config` (edjobs
  v0.7.0): `state_config.R` sets `edjobs::state_config()` (name, FIPS, app folder, this state's own reference
  tables, which left the package's `REFERENCE_TABLE_RULES`); OEWS areas are a FIPS-keyed CSV in the package.
  Suite on 0.7.0: MT 3,401 passed, 0 failed; full rehearsal passed every step, rebuild parity 9/9
  (`claude-notes/2026-11-11_rehearsal-mt-edjobs-phase4.log`).
  Slice 2 merged 11-11 (MT PR #23 -> b0405d6). Slice 3 (edjobs v0.8.0): the drift-check functions MT and WY held
  differently, except dispatch and the auto-fix issue body, come from the package (`flag_drift`,
  `build_historical_counts`, the drift report, the live-check summary); `state_config.R` gains the OPI feed's
  labels and the drift baseline date. `check_drift.R` output on committed data is identical. Suite on 0.8.0:
  MT 3,387 passed, 0 failed (3,390 after the rehearsal's run); full rehearsal passed every step, rebuild parity 9/9
  (`claude-notes/2026-11-12_rehearsal-mt-edjobs-0.8.0.log`).
  Slice 3 merged 11-12. Slice 4 (edjobs v0.9.0): scraper dispatch and the auto-fix issue body come from the
  package (`resolve_scraper_call(name)`, `run_scraper_call()`, `gather_autofix_evidence()`,
  `build_autofix_issue_body()`, `build_source_url_lookup()`); this state's sources and how each is scraped are
  data in `state_config.R` (`scraper_sources`, `autofix`). On all 225 registered sources the resolved call, its description and
  the evidence are identical to the local code's; the issue body changes only in wording. Six colleges with no single-source scraper no longer get a platform line in an issue.
  Suite on 0.9.0: MT 3,792 passed, 0 failed (3,796 after the rehearsal's run); full rehearsal passed every step,
  rebuild parity 9/9 (`claude-notes/2026-11-12_rehearsal-mt-edjobs-0.9.0.log`). Not exercised by a rehearsal:
  `file_autofix_issues.R` and `live_check_autofix.R` (GitHub-only steps); `scripts/repro_scraper.R` was run live.
  Slice 4 merged 11-12. Slice 5 (edjobs v0.10.0): the accumulated K-12 history comes from the package
  (`build_k12_combinedclean()`, `build_k12_teacher_rows()`, `append_weekly_rows()`,
  `summarize_k12_posting_counts()`), with one output schema for every state (`edjobs::K12_POSTING_COLUMNS`).
  `combinedclean.csv`'s `OPI_District` / `Also_On_OPI` are now `Feed_District` / `Also_On_Feed` (header line only; `app.R`, schema check, dictionary and cookbook follow).
  Raw rows and the weekly archives keep their column names; posting id values are untouched. Suite on 0.10.0:
  MT 3,780 passed, 0 failed (3,783 after the rehearsal's run); full rehearsal passed every step, rebuild parity 9/9
  (`claude-notes/2026-11-12_rehearsal-mt-edjobs-0.10.0.log`). Design and open items:
  `claude-notes/2026-11-12_phase4-k12-output-schema.md`.
  Slice 5 merged 11-12. Slice 6 (edjobs 0.11.0, PR #9 there; branch `edjobs-platform-fetchers`, 11-12): the
  platform fetchers come from the package (`fetch_neogov_postings()`, `fetch_peopleadmin_atom()`,
  `fetch_schoolspring_postings()`, `fetch_tedk12_postings()`, `parse_jobposting_jsonld()`,
  `assign_shared_board_institutions()`); local copies, tests and fixtures deleted. NEOGOV is one platform keyed by
  the agency slug, read from the classic careers page (Mike's decision after the 11-12 measurement,
  `claude-notes/2026-11-12_neogov-decision-research.md`). UM's board moves to it, and the Attract code and fixtures
  go. Helena College, Missoula College and UM Western get their postings by a `Location_Pattern` column in
  `he_institution_registry.csv` (SharesBoard rows). Each posting's page gives its exact posted date and closing
  date. **Closes the open item "UM NEOGOV board counts 11 expired postings as open" (found 11-12):** the Attract
  site still listed 11 Helena College / UM Western postings closed between 2024-12 and 2026-05; the classic page
  lists none of them. Five `run_expectations.csv` rows for the 11-17 run. Suite on 0.11.0: 3,717 passed, 0 failed
  (3,720 after the rehearsal's run); full rehearsal passed every step, rebuild parity 9/9
  (`claude-notes/2026-11-12_rehearsal-mt-edjobs-0.11.0.log`): 45 UM-board rows, 45 exact posted dates, 20
  closing dates, posted pay on 41; Helena College 5, UM Western 2, no Attract links left. Review fixes before
  release (edjobs 579d632, `claude-notes/2026-11-12_review-edjobs-0.11.0.md`): NEOGOV cards' Location and date
  read per card (one card without its meta block had blanked every Location on the page, filing Helena College and
  UM Western under UM), a warning when a board returns no Locations, and a JSON-LD reader that takes schema.org's
  text forms and catches errors per page. Re-rehearsed: every step passed, parity 9/9, suite 3,717/0
  (`claude-notes/2026-11-12_rehearsal-mt-edjobs-0.11.0-fixes.log`); UM 38, Helena College 5, UM Western 2.
  PR checks pass once edjobs v0.11.0 is tagged.
- [ ] Real posting dates, rest of step 5: WY (K-12 and HE, same design, once its coverage calendar
  has a few weeks). What, if anything, the Listing Duration tabs (paused 2026-11-02) show from
  `posting_durations_k12.csv` / `posting_durations_he.csv`, and when.
  Update (Mike, 2026-11-14): no "paused" banner: the tabs show the current table with one footnote at the
  bottom; the duration KPI boxes and charts stay out until the checks below. For when this resumes (Mike): a way to
  filter out standing postings that are nearly always listed (adjunct pools and the like).
  Decision (Mike, 2026-11-09): the tabs stay paused until we are sure the data is accurate. Proposed checks
  (not yet agreed): (a) about 4 weekly runs after the 11-09/10 pushes (relistings censored, first-seen fallback,
  page-confirmed closings) with no processing change that moves the medians by more than a few days (the OPI
  dedup alone moved MT K-12 from 63 to 28 days; censoring relistings moved MT HE from 21.5 to 31.5); (b) the spells
  trust audit (`claude-notes/2026-11-02_spells-trust-audit.md`) re-run on that data, with few endings left that a
  known data artifact explains (68% on 11-02); (c) the OPI matcher check against fresh OPI data done.
  Treat a board-wide default end date such as Bozeman's 2027-06-11 as no deadline. Step 3: daily presence check
  for day-precision ends (`claude-notes/2026-11-09_daily-presence-check-plan.md`): phase 0 built 2026-11-13 (42 districts, Red
  Rover included, plus OPI's statewide list keyed by a detail-page fingerprint, edjobs 0.15.0; runs daily once the
  PR merges); the audit after two weeks, then phase 1 (the spells read the sightings).
- [ ] Arrowhead Elementary #75: HTTP 403 from Cloudflare on every weekly CI run since 2026-09-07
  (`coverage_calendar.csv`); the page serves an ordinary request from home. Rechecked 2026-11-09: 3 postings, the same
  3 the last good CI run (09-01) captured -- Substitute Employment (standing pool, $120/day), Special Education
  Paraprofessional (full time), Certified Teachers ("various grades"); none on OPI now (OPI carried two of them
  04-07 to 08-25). Not worked around on purpose: user agents, proxies or other routes past the block circumvent the
  site's bot protection. Running it from the Mac: built and withdrawn the same day (Mike: no jobs on his computer).
  Left: ask the district / its web host to let the weekly request through, or retire the source and say so.
- [ ] Old OPI postings (`claude-notes/2026-11-09_opi-old-postings.md`). Standard (Mike, 11-09): open = a candidate can
  still apply. All 357 live OPI postings read in full: every one gives a way to apply (general link 188, mail/phone/email
  162, job-specific link 7); 133 of 141 links work, 2 postings have only dead links. So the 4 "2025-26" ones (reused ad
  text, up since May-June) still count as open. Open: whether to flag spring postings. (A weekly check of the 7
  job-specific links: measured 11-09 and not built; it would mostly flag outages and email links.)
- [ ] Classification safeguards (`claude-notes/2026-11-01_classification-safeguards-proposal.md`): 3, 5, 6, 7, 8,
  9, 10, 11, 12, 13 done; 2 measured, no effect, not built; 1 has a small ceiling (Other is 1.6% MT, 0.1% WY), suggest
  parking (`claude-notes/2026-11-08_classifier-items-1-2-measured.md`). Golden set 551 of 551, no known misses (2026-11-09:
  the 2 file-name titles fixed; "COMMUNICATIONS COORD." was already relabeled in 3389731). Left: 4.
- [ ] Optional: Gemini as a shadow second opinion on OPI matches (QC report only; Mac key is free tier).
- [ ] Using the twice-weekly runs and the daily presence check on the dashboard (Mike, 2026-11-18). Every run is
  stored (`Archive_Date`; two a week, Mon + Thu, first Thu 2026-11-19); the app rolls the history up to each ISO week's last
  run (`latest_snapshot_per_week()`), so the history charts stay weekly while the current counts read the newest run.
  The presence check writes `presence_sightings.csv` (one row per posting: `First_Day`, `Last_Day`, `Days_Seen`) on
  the `presence` branch; nothing on the dashboard reads it yet.
  **Check ~2026-01-15 (about 8 weeks of twice-weekly runs):** do the two runs in a week differ by more than noise (new
  postings, endings, totals, by day of week)? If not, the history charts could plot every run on a date axis (back to
  the first twice-weekly run; nothing is lost by waiting). If there is a day-of-week pattern, keep one point a week.
  Either way, re-measure the drift thresholds (tuned on weekly counts) before any run-level chart.
  Ideas, not decided (each measured on the archives before building):
  Twice-weekly runs: (1) listing durations to within 3-4 days instead of 7 (the spells already end per run);
  (2) short-lived postings: postings seen in one run only, which weekly scrapes missed, by job type (fast fills or
  quick withdrawals); (3) when districts post: new postings by day of week and by month (a hiring calendar);
  (4) the weekly roll-up takes the week's most complete run instead of its last, so one failed run doesn't cost the
  week; (5) a broken board noticed in 3-4 days instead of 7.
  Daily presence (after the phase-0 audit ~11-27 and phase 1): (6) day-precision listing durations (planned: the
  spells read the sightings); (7) a "Last seen on its board" date in the Jobs table, and postings gone between scrapes
  hidden, so "open" means a candidate can still apply today; (8) closed early: postings that left the board before
  their stated closing date, by job type; (9) days open so far for current postings, and the longest-open ones by job
  type and district (a hard-to-fill signal; relistings censored, not linked); (10) board health: a board the daily
  check can't read flagged within a day.

