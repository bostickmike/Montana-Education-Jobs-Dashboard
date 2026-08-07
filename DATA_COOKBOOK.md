# Data Cookbook

Every dataset the pipeline (`Mt_ED_Jobs.Rmd`) produces and ships to `Mt_Ed_Jobs/`, where `Mt_Ed_Jobs/app.R` reads it. Mirrors the Wyoming Education Jobs Dashboard's own `DATA_COOKBOOK.md` structure, but Montana's actual data sources differ from Wyoming's in several real, documented ways — see "Notes on the data model" at the end for the summary, and each dataset's own notes for specifics. All of these except `combinedclean.csv`, `hedata.xlsx`, `allnow.csv`, and `allnow_he.csv` are **accumulated, growing datasets** — each run appends that run's newly classified rows onto what's already there (see `history_accumulator.R`), rather than rebuilding from scratch. `schema_check.R`'s `REQUIRED_SCHEMAS` is the enforced, tested version of the column lists below — if this document and that list ever disagree, trust the code and open an issue.

---

## K-12

### `combinedclean.csv` — current K-12 postings (this run only)

One row per open K-12 posting, all position types (not just teachers). Rebuilt fresh every run — **not** an accumulated file.

| Column | Type | Notes |
|---|---|---|
| `title` | text | Job title as posted. Passed through `fix_title_encoding()` at ingestion. |
| `Archive_Date` | date | The date this snapshot was scraped. |
| `date_posted` | text | Original posted-date text, format varies by source platform. |
| `position` | text | Coarse bucket from `classify_k12_position()` (Teacher, Support Services, Administration, etc. — see `k12_he_classification.R` for the full list). |
| `location` | text | School/site name or district office, as scraped — format varies a lot by source platform. |
| `url` | text | The district's job-board URL (one per district, not a per-posting deep link) for direct-scraped rows. For OPI-statewide-fallback rows, this is the shared statewide listing URL instead — see that source's own note below. |
| `District` | text | Canonical district name for the 18 directly-scraped districts (`canonicalize_k12_district()` applied). For every other Montana district (surfaced only via the OPI statewide feed), this is that posting's raw City value instead — **not a canonical legal district name**, since the OPI feed exposes no district field at all. See "OPI statewide fallback feed" below. |

**Sources combined into this file**: AppliTrack, SchoolSpring, Tyler Portico, and TedK12 direct-district scrapes (`k12_district_registry.csv`'s 18 districts), plus the OPI "Jobs for Teachers" statewide feed **filtered to districts not already covered directly** (matched on `k12_district_registry.csv`'s `City` column, to avoid double-counting a district like Kalispell that appears in both a direct scrape and the statewide feed).

### `k12jobanalysis.csv` — full history, Teacher postings only

Row-level history of every Teacher-position posting ever scraped, one row per posting per run it appeared. **Accumulated**.

| Column | Type | Notes |
|---|---|---|
| `title` | text | |
| `Archive_Date` | date | |
| `position` | text | Always `"Teacher"` in this file (pre-filtered). |
| `location` | text | |
| `url` | text | |
| `District` | text | Canonical district name (or a raw OPI City value — see `combinedclean.csv` above). |
| `Category` | text | Fine-grained subject from `classify_k12_subject()`. |
| `Broad_Category` | text | Coarser grouping from `classify_k12_broad_category()`; this is what the app's category color palettes and pickers use. |

### `allsum.csv` — longitudinal category counts, by district and statewide

One row per (`Broad_Category`, `Archive_Date`, `District`) combination, **plus** a `District == "Total"` row per (`Broad_Category`, `Archive_Date`) that's the sum of that run's district rows — computed as an explicit sum of the parts (`check_total_matches_parts()` asserts this before every append). **Accumulated.**

| Column | Type | Notes |
|---|---|---|
| `Broad_Category` | text | |
| `Archive_Date` | date | |
| `District` | text | A real district name, an OPI City value, or `"Total"`. |
| `sum` | integer | Distinct (`title`, `location`) postings that run — deduplicated on the pair, not `title` alone, since two schools can legitimately post the same generic title. |

### `allnow.csv` — current-run category counts

Same shape as `allsum.csv` minus the `Archive_Date` column. Not accumulated.

| Column | Type | Notes |
|---|---|---|
| `Broad_Category` | text | |
| `Sum` | integer | Note the capital S — inconsistent with `allsum.csv`'s lowercase `sum`, kept as-is (same pre-existing quirk Wyoming's own file has). |
| `District` | text | |

### `k12_district_weekly_totals.csv` — all-category totals per district, per run

One row per (`District`, `Archive_Date`), counting **every** position type, not just Teacher. **Accumulated.**

| Column | Type | Notes |
|---|---|---|
| `District` | text | |
| `Archive_Date` | date | |
| `n` | integer | All postings that district had that run, any position type. |

### `salarymap2.csv` — one row per registered district, static reference + refreshed figures

One current row per this project's **18 directly-scraped K-12 districts** (`k12_district_registry.csv`) — not Montana's full ~398-district universe, matching this project's job-postings scraping scope. `District`/`County`/`Latitude`/`Longitude`/`Job_Link` come from the registry; everything else is refreshed from its live source every run (and left untouched if that run's fetch fails, rather than being blanked out).

| Column | Type | Source | Notes |
|---|---|---|---|
| `District` | text | registry | Canonical name; the join key. |
| `County` | text | registry | |
| `Latitude` / `Longitude` | numeric | registry | |
| `Job_Link` | text | registry | District's job-board URL. |
| `Teacher_Count` | numeric | MT DLI Teacher Compensation Report | Full-time general-education teacher count that report's underlying data covers for this district. |
| `Teacher_Salary_10th_Pctile` / `Teacher_Avg_Salary` / `Teacher_Salary_90th_Pctile` | numeric | MT DLI | **Not the same metric as Wyoming's `Teacher_Base_Salary`** — Montana has no clean WSBA equivalent (no BA-step-1 contract base salary source exists publicly). The best available source, the MT Dept. of Labor & Industry's "Teacher Compensation Report," reports average salary and 10th/90th percentile bands instead, so these columns are named to make that difference explicit rather than implying equivalence. |
| `Salary_Year` | text | MT DLI | e.g. `"2022-23"` (a school year, extracted from the report's own "Source: OPI GEMS `<year>`" footer) — the real freshness signal, since this report has only ever had one published edition found so far (cadence unconfirmed). |
| `Salary_Source` | text | MT DLI | Literal string naming the report. |
| `Teachers_Total_FTE` | numeric | NCES CCD via Urban Institute | Vacancy-rate denominator. Montana's elementary/HS district split means this is a SUM across 1–2 real CCD LEA records per district (`MT_CCD_LEA_MAP` in `ccd_staff_scraper.R`), not a single CCD record the way Wyoming's districts are. |
| `Enrollment` | numeric | NCES CCD via Urban Institute | Same elementary/HS-sum treatment as `Teachers_Total_FTE`. Powers `Students_Per_Teacher` (`Enrollment ÷ Teachers_Total_FTE`), computed in `app.R`, not stored here. |
| `CCD_Year` / `CCD_Source` | text | NCES CCD | |
| `Median_Household_Income` / `Median_Gross_Rent` | numeric | Census ACS 5-Year | County-level, not district-level — joined on `County`, so sibling districts in the same county share identical values. |
| `Mining_Employment_Share` | numeric | Census ACS 5-Year Subject Tables | County's civilian workforce share (0–1) employed in mining/oil & gas — the same explanatory-variable choice Wyoming's dashboard uses, kept for consistency; Montana's own energy-producing counties show real, meaningful spread too (confirmed live, not assumed). |
| `Population_Change_Pct` | numeric | Census ACS 5-Year | County population change vs. the same ACS product 5 years earlier. |
| `ACS_Year` | integer | Census ACS 5-Year | The ACS 5-Year vintage's end year — the real freshness signal for the four columns above. |
| `Child_Poverty_Rate` | numeric | Census SAIPE | **District-level.** Montana's districts aren't uniformly "unified" the way Wyoming's 48 are — SAIPE reports a separate elementary-district rate and high-school-district rate for 15 of this project's 18 districts (the other 3 are already-unified K-12 districts). A split district's `Child_Poverty_Rate` here is a **plain, unweighted average** of its elementary and secondary rates (`MT_SAIPE_DISTRICT_MAP` in `census_saipe_scraper.R`) — a documented simplification, not an enrollment-weighted or otherwise authoritative single figure. |
| `SAIPE_Year` | integer | Census SAIPE | The real freshness signal for `Child_Poverty_Rate`. |

**No superintendent salary or contract-days column exists in this file at all** — unlike Wyoming's `Superintendent_Salary`/`Superintendent_Contract_Days` (from WSBA), no public Montana source for this figure was found anywhere (checked directly; those numbers are public record but scattered across ~393 individual district board minutes/contracts with no statewide clearinghouse). This is a confirmed real gap, not an oversight.

### OPI statewide fallback feed — a note, not a dataset of its own

Montana's analog of Wyoming's WSBA vacancies page is the MT OPI "Jobs for Teachers" feed (`apps.opi.mt.gov/mtjobsforteachers/`), folded directly into `combinedclean.csv`/`k12jobanalysis.csv`/`allsum.csv` above (filtered to districts not already scraped directly) rather than kept as a separate file — Wyoming's WSBA data gets the same "combined in, not separate" treatment. Two real limitations worth knowing before trusting a District value from this source: (1) `District` for these rows is a raw City string, not a canonical legal district name (the feed exposes no district field), and (2) the feed is an ASP.NET WebForms page with no stable per-posting URL — `url` for these rows is the shared statewide listing page, not a deep link, so it can't be used to jump straight to one specific posting.

---

## Higher Ed

### `hedata.xlsx` — current HE postings (this run only)

One row per open posting across this project's 6 directly-scraped HE institutions, every job type (not just faculty). Rebuilt fresh every run — **not** accumulated (the accumulated raw history lives in `Archived_HE_Data/*.xlsx`, one file per run).

| Column | Type | Notes |
|---|---|---|
| `Title` | text | |
| `Location` | text | Format varies by platform — a city string (PeopleAdmin/Paycom) or a department name (JazzHR, PeopleAdmin's own multi-department institutions). |
| `Posted_Date` | text | Original posted-date text; genuinely absent (`NA`) for JazzHR postings — that platform's listing page carries no date field at all. |
| `Institution` | text | Canonical institution name (`canonicalize_he_institution()` applied). |
| `Link` | text | Direct link to the posting. |
| `Archive_Date` | date | |

**Sources combined into this file**: PeopleAdmin (4 institutions), JazzHR (Montana Tech, which also covers Highlands College's postings under its own board), Paycom (Flathead Valley Community College), NEOGOV Attract (University of Montana, which also covers Missoula College, Helena College, and University of Montana Western under its own board), ADP Workforce Now (University of Providence), isolved Hire (Blackfeet Community College), and heuristic free-text/DOM scrapers (Miles Community College, Dawson Community College, Carroll College, Rocky Mountain College) — `he_institution_registry.csv`'s 12 institutions.

### `facultydata.csv` — full history, faculty + adjunct postings only

Row-level history of every `"Instructor/Teacher/Faculty"` and `"Adjunct/Part-Time Faculty"` posting ever scraped. **Accumulated.**

| Column | Type | Notes |
|---|---|---|
| `Title` | text | |
| `Location` | text | |
| `Posted_Date` | text | |
| `Institution` | text | Canonical institution name. |
| `Link` | text | |
| `Archive_Date` | date | |
| `Job_Type` | text | `"Instructor/Teacher/Faculty"` or `"Adjunct/Part-Time Faculty"` from `classify_he_job_type()`. |
| `Category` | text | Subject area from `classify_he_faculty_category()`. |

### `allsum_he.csv` — longitudinal category counts, by institution and statewide

Same shape/logic as K-12's `allsum.csv`, plus a `Job_Type` dimension. **Accumulated.**

| Column | Type | Notes |
|---|---|---|
| `Category` | text | |
| `Archive_Date` | date | |
| `Institution` | text | A real institution name, or `"Total"`. |
| `Job_Type` | text | |
| `sum` | integer | |

### `allnow_he.csv` — current-run category counts

Same shape as `allsum_he.csv` minus `Archive_Date`. Not accumulated.

| Column | Type | Notes |
|---|---|---|
| `Category` | text | |
| `Job_Type` | text | |
| `Sum` | integer | Capital S, same pre-existing inconsistency as K-12's `allnow.csv`. |
| `Institution` | text | |

### `he_institution_weekly_totals.csv` — all-category totals per institution, per run

One row per (`Institution`, `Archive_Date`), all job types. **Accumulated.**

| Column | Type | Notes |
|---|---|---|
| `Institution` | text | |
| `Archive_Date` | date | |
| `n` | integer | |

### `salarymap.csv` — one row per registered institution, static reference + refreshed figures

One current row per this project's **6 directly-scraped HE institutions** — matching Wyoming's own `salarymap.csv` scope (its 9 rows are exactly its 9 job-scraped institutions, not a broader MUS-wide reference set), not the full ~16-institution MUS-plus-tribal-college universe `RESEARCH_NOTES.md` originally scoped for job-postings coverage. `Name`/`County`/`Longitude`/`Latitude`/`Link` come from `he_institution_registry.csv`; everything else refreshes from IPEDS/FSA each run.

| Column | Type | Source | Notes |
|---|---|---|---|
| `Name` | text | registry | Canonical name; the join key. |
| `County` | text | registry | |
| `Longitude` / `Latitude` | numeric | registry | |
| `Link` | text | registry | Careers page. |
| `Faculty_Avg_Salary` / `Faculty_Avg_Salary_Professor` | numeric | IPEDS via Urban Institute | "All ranks combined" and Professor-rank average salary. |
| `Faculty_Count` | numeric | IPEDS | Vacancy-rate denominator. |
| `Salary_Year` | text | IPEDS | Calendar year IPEDS surveyed as of (Nov 1), not an academic year. |
| `Salary_Source` | text | IPEDS | |
| `Faculty_Avg_Salary_Y1Ago` / `Faculty_Avg_Salary_Y2Ago` | numeric | IPEDS via Urban Institute | Real multi-year trend — unlike the K-12 side's DLI data (only one published edition found so far), IPEDS is queryable by year indefinitely, so this goes back 2 years beyond `Salary_Year` on every run. |
| `Enrollment` / `Enrollment_Year` | numeric / text | IPEDS via Urban Institute | Fall enrollment (FTE), summed across every `level_of_study` an institution reports. `Students_Per_Teacher` is computed on the fly in `app.R` (`Enrollment / Faculty_Count`), not stored here. |
| `Enrollment_Change_Pct` | numeric | IPEDS via Urban Institute | Institution-level 5-year enrollment trend. Confirmed with real data: only Montana State University grew (+1.7%) over the 5-year window checked; the other 5 institutions all shrank. |
| `Pell_Recipient_Share` / `Pell_Year` | numeric / text | US Dept. of Education FSA via Urban Institute | Real, unduplicated Pell Grant recipient count divided by `Enrollment` from the SAME year (FSA lags IPEDS by roughly 2 years) — an honest headcount-over-FTE-enrollment ratio, not two directly comparable counts. |
| `Median_Household_Income` / `Median_Gross_Rent` / `Mining_Employment_Share` / `Population_Change_Pct` / `ACS_Year` | numeric | Census ACS 5-Year | Same `fetch_census_county_context()` pipeline `salarymap2.csv` uses, fetched independently and joined on `County`. No two of these 6 institutions share a county, so there's no sibling-sharing case here. |

**No unitid-sharing/merged-entity case exists among these 6 institutions** — unlike Wyoming's Sheridan/Gillette (one shared IPEDS unitid for two colleges), each of Montana's 6 institutions (including Highlands College of Montana Tech, which reports separately from Montana Tech itself in IPEDS despite sharing its job board) has its own independent unitid, confirmed live. No `Salary_Note` column exists here for that reason.

---

## Notes on the data model

- **Accumulation, not rebuilding.** Every "full history" file above is appended to each run, not regenerated from the raw archive from scratch — see `history_accumulator.R`. The raw snapshots (`Archivek12_Data/*.csv`, `Archived_HE_Data/*.xlsx`) are still written every run as the durable source of truth.
- **Missingness is real, not a data quality bug.** `NA` in a salary/staffing/Census column means that source's fetch failed, or the underlying figure is genuinely suppressed/non-disclosable at the source (MT DLI's own `ND` marker for small districts) — not that this pipeline failed to look. Every salary/staffing/Census chunk leaves the relevant file untouched on a failed run rather than blanking out last run's good values.
- **Montana's job-postings scraping scope (18 K-12 districts, 6 HE institutions) is intentionally narrower than Montana's full universe** (~398 nominal K-12 districts, ~16 MUS+tribal HE institutions per `RESEARCH_NOTES.md`) — every registry-keyed dataset above (`salarymap2.csv`, `salarymap.csv`) matches that same narrower scope, not the full state. The OPI statewide feed is the one exception that surfaces postings (not salary/staffing data) from districts outside the 18, with the caveats noted above.
- **Classification lives in one place.** `classify_k12_position()`, `classify_k12_subject()`, `classify_k12_broad_category()`, `classify_he_job_type()`, `classify_he_faculty_category()`, and the `canonicalize_*` functions all live in `k12_he_classification.R`, sourced everywhere they're needed.
- **Schema is enforced, not just documented.** `schema_check.R`'s `REQUIRED_SCHEMAS` is checked against real committed data via `tests/testthat/test-schema-check.R`.
- **One source needs its own credential.** Everything else in this pipeline is a public, keyless API or a plain public web page. `census_acs_scraper.R`/`census_saipe_scraper.R` are the exception — the Census Data API requires a free `CENSUS_API_KEY` (`.Renviron` locally; would need to become a GitHub Actions secret once a CI workflow exists) — missing or invalid, the affected chunk fails loudly and leaves that file's county/district-context columns untouched.
- **Elementary/HS district splits recur across three independent sources.** `MT_CCD_LEA_MAP` (`ccd_staff_scraper.R`), `MT_DLI_DISTRICT_MAP` (`salary_scrapers.R`), and `MT_SAIPE_DISTRICT_MAP` (`census_saipe_scraper.R`) each hand-map this project's 18 combined districts to that source's own elementary/HS/unified naming — three separate maps, not shared, because each source's real-world naming convention differs slightly from the other two (confirmed live for each).
