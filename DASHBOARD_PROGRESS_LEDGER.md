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
