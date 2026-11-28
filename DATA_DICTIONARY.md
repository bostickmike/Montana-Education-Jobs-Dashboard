# Montana Education Jobs Dashboard — Data Dictionary & Codebook

Comprehensive variable codebook, schema definitions, and methodological provenance for datasets compiled and published by the **Montana Education Jobs Dashboard**.

Each dataset is accessible via the **Data** tab in the interactive web dashboard or by downloading machine-readable CSVs directly from this repository.

---

## 1. Datasets Overview

| Dataset Layer | Primary File | Description | Granularity | Refresh Cadence |
| :--- | :--- | :--- | :--- | :--- |
| **Active K-12 Jobs** | `combinedclean.csv` | Every K-12 posting listed in the latest update: district boards plus OPI's statewide board. | Posting level | Twice weekly |
| **K-12 Historical Archive** | `k12jobanalysis.csv` | Every teaching posting in every update since August 2026 (teaching jobs only), with standardized categories. | Posting level | Twice weekly |
| **K-12 Job Duration Spells** | `job_duration_spells.csv` | One row per posting: first and last update it was seen, days listed, and job-type flags (STEM, special education, ...). | Posting spell | Twice weekly |
| **District Profiles & Benchmarks** | `salarymap2.csv` | District-level staffing, compensation benchmarks, and Census context. | District level | Twice weekly / Annual |
| **Higher Ed Historical Postings** | `facultydata.csv` | Every faculty and adjunct posting in every update since August 2026 (no staff postings). | Posting level | Twice weekly |
| **Higher Ed Job Duration Spells** | `he_job_duration_spells.csv` | One row per college posting: first and last update it was seen, days listed, and discipline flags. | Posting spell | Twice weekly |
| **Higher Ed Institutional Profiles** | `salarymap.csv` | College and university profiles: IPEDS instructional faculty salaries, enrollment, and Pell recipient shares. | Institution level | Twice weekly / Annual |
| **K-12 Weekly Vacancy Time Series** | `k12_district_weekly_totals.csv` | Open posting counts per district in each update. | District × Update | Twice weekly |
| **K-12 Job Type Time Series** | `k12_jobtype_weekly_totals.csv` | Open job postings per update by K-12 position type, all and those not marked part-time, substitute or extra duty. | Job type × Update | Twice weekly |
| **Higher Ed Weekly Vacancy Time Series** | `he_institution_weekly_totals.csv` | Open posting counts per college in each update. | Institution × Update | Twice weekly |
| **Higher Ed Job Type Time Series** | `he_jobtype_weekly_totals.csv` | Open college job postings per update by job type, all and those not marked part-time, student or temporary. | Job type × Update | Twice weekly |
| **K-12 Current Category Counts** | `allnow.csv` | Teaching postings in the latest update by subject group and district, with statewide totals. | District × Category | Twice weekly |
| **K-12 Category Time Series** | `allsum.csv` | Teaching postings by subject group and district in every update, with statewide totals. | District × Category × Update | Twice weekly |
| **Higher Ed Current Category Counts** | `allnow_he.csv` | Faculty and adjunct postings in the latest update by discipline, type and college, with statewide totals. | College × Discipline × Type | Twice weekly |
| **Higher Ed Category Time Series** | `allsum_he.csv` | Faculty and adjunct postings by discipline, type and college in every update, with statewide totals. | College × Discipline × Type × Update | Twice weekly |
| **Active Higher Ed Jobs** | `hedata.xlsx` | Every college posting listed in the latest update, all job types, with posted pay, campus placement and pay estimates. | Posting level | Twice weekly |
| **IPEDS Staff Salaries** | `ipeds_staff_salaries.csv` | Average pay of full-time non-instructional staff by college and occupational category (categories with at least 3 staff). | College × Category | Annual |
| **K-12 Teacher Salary History** | `k12_salary_history.csv` | Teacher pay by district for each Teacher Compensation Report edition this project has captured (DLI keeps no public archive). | District × Year | Annual |
| **BLS Regional Pay by Role** | `oews_role_wages.csv` | Median pay for the occupations K-12 postings are matched to, by Montana OEWS area; the source of the K-12 Typical pay (BLS est.) column. | Area × Occupation | Annual |
| **OPI District Counties** | `opi_district_counties.csv` | The county of each district as OPI names it, used to give OPI postings a county. | District level | Twice weekly |
| **Posting First Seen** | `posting_first_seen.csv` | When the dashboard first found each currently listed posting; shown where the board gives no posted date. | Posting level | Twice weekly |
| **County Public School Pay** | `qcew_county_school_pay.csv` | Average annual pay and employment of public school (local government, NAICS 6111) employees by county, all roles together. | County level | Annual |
| **Source Retrieval Dates** | `source_retrieved_dates.csv` | When each outside data source was last fetched successfully. | Source level | Twice weekly |
| **Data Dictionary & Codebook** | `data_dictionary.csv` | Machine-readable column definitions, types, and primary source authorities across all files. | Variable level | Static / Maintained |

---

## 2. Universal Identifiers

To support seamless merges with federal, state, and academic datasets, the following universal identifiers are embedded:

- **`NCES_LEAID`**: Official 7-digit federal National Center for Education Statistics Local Education Agency identifier. Enables 1:1 joining with the **Stanford Educational Data Archive (SEDA)**, **Civil Rights Data Collection (CRDC)**, and **Census F-33 School District Finance Survey**.
- **`IPEDS_UNITID`**: Official 6-digit federal Integrated Postsecondary Education Data System identifier.

---

## 3. Data Dictionary: Detailed Variable Definitions

### A. Active K-12 Jobs (`combinedclean.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `title` | String | Job posting (district job board or OPI Jobs for Teachers) | Official job vacancy title as published by the school district or OPI Jobs for Teachers feed. |
| `Archive_Date` | Date (YYYY-MM-DD) | This dashboard: snapshot at each update | Date of the update that saw the posting listed (the dashboard updates twice a week since 2026-11-17, weekly before). |
| `date_posted` | String / Date | Job posting (district job board or OPI Jobs for Teachers) | Original posted date string as published on the district applicant tracking board. |
| `position` | Categorical | This dashboard: job title classification | Broad staff position group (Teacher, Administrator, Support Services, etc.). |
| `location` | String | Job posting (district job board or OPI Jobs for Teachers) | Specific school building, facility, or employer city/location label. |
| `url` | URL | Job posting (district job board or OPI Jobs for Teachers) | Direct link to the job posting or district applicant tracking portal. |
| `District` | String | This dashboard: district and college list | Canonical public school district name. OPI statewide rows: the name of the district whose board this dashboard reads, when that board came back empty that week, else the district not read directly (one name per town, e.g. "Box Elder Elem / Box Elder H S"), else OPI's employer name (private and tribal schools, co-ops); raw city only where the posting's district couldn't be identified. See `opi_reconcile.R`. |
| `Posting_Source` | String | This dashboard: posting tracking | Original job feed source (direct district ATS board vs OPI Jobs for Teachers feed). |
| `Posting_Identity_Method` | String | This dashboard: posting tracking | Durable identity fingerprint method used (Stable per-posting URL vs Source fallback). |
| `Posting_ID` | String | This dashboard: posting tracking | Durable unique posting identifier used to track openings across updates. |
| `Feed_District` | String | OPI Jobs for Teachers | For OPI statewide rows, the employer's district as the posting's detail page names it, in OPI's naming ("Lockwood K-12", "Richey Elem"), which is NCES CCD's district name; NA for direct-board rows and where the detail page could not be read. Used to decide whether the posting counts (`opi_reconcile.R`). |
| `Also_On_Feed` | Logical | This dashboard: posting tracking | TRUE for a direct-board posting that OPI Jobs for Teachers also lists as the same opening (`opi_matcher.R`). Counted once, from the direct board; OPI postings a district's board doesn't list are counted from OPI. |
| `Close_Date` | String | Job posting (district job board or OPI Jobs for Teachers) | The posting's closing date as its board states it, unparsed (a date, or "Open Until Filled", "TBD" and similar). AppliTrack (from 2026-11-03), Tyler Portico rows with a real end date (Tyler fills open-ended postings with the fetch date plus a year, which is left NA), SchoolSpring (from 2026-11-04: the deadline applicants see, as YYYY-MM-DD; "Posted until filled" is NA), and OPI (from 2026-11-04: the grid's "Closing Date", a date as YYYY-MM-DD, otherwise as written, nearly always "Open Until Filled"); NA where the board gives none and for other sources. |
| `Role_Hint` | Categorical | This dashboard: job title classification | What the posting's own description says about the role, used to refine its position bucket: Substitute (a long-term substitute), Paraprofessional, Part-Time (a part-time or under-1.0-FTE teacher), Teacher, Counselor or Administration (the role the description names first). OPI postings only, from 2026-11-03 (when OPI descriptions began to be archived): OPI's title is its subject-area field, which misfiles some postings (e.g. a long-term substitute, a paraeducator under "Elementary Curriculum", a teacher under "Administrative - Other"). NA when the description gives no clear signal, and for every other source. |
| `Pay_Min` | Numeric | Job posting (district job board or OPI Jobs for Teachers) | Lowest pay amount stated in the posting itself, in `Pay_Unit` (NA when no dollar figure is stated). Never converted between units. |
| `Pay_Max` | Numeric | Job posting (district job board or OPI Jobs for Teachers) | Highest stated amount (equals `Pay_Min` for a single figure). |
| `Pay_Unit` | String | Job posting (district job board or OPI Jobs for Teachers) | `hour`, `day`, `month`, `year`, `credit hour`, or `stipend` (season/activity amount); NA when undeterminable. |
| `Pay_Text` | String | Job posting (district job board or OPI Jobs for Teachers) | The posting text the pay was read from, for verification (for RedRover, the board's own pay line, e.g. "$13.50 - $14.65 per hour"; "per unit" there means a stipend). |
| `Est_Pay` | Numeric | BLS OEWS | Where the posting states no pay of its own: the Bureau of Labor Statistics' median pay for the posting's role in its region (see `Est_Occupation`, `Est_Area`), in `Est_Pay_Unit`. A regional estimate across all employers of that occupation, not this job's offer. NA for roles with no fair match (coaches, unclassified postings). |
| `Est_Pay_Unit` | String | BLS OEWS | `hour` for roles usually paid hourly where BLS publishes an hourly median; otherwise `year`. |
| `Est_Occupation` | String | BLS OEWS | The OEWS occupation the posting was matched to from its position and title (e.g. "Teaching assistants", "School bus drivers"). |
| `Est_Area` | String | BLS OEWS | The OEWS area the figure is for: the metro or nonmetro area holding the district's county, or the state where the county is unknown or BLS suppresses the local figure. |
| `Est_Year` | String | BLS OEWS | OEWS reference year (May of that year). |

**Not in this file: old board ads.** Board postings dated (posted, or with a stated closing date) before the July 1 that began the previous school year aren't counted, except standing pools and jobs advertised all year (METHODS.md, "Old board ads"). They are left out of this file and every count. The raw postings (`Archivek12_Data/combined_<date>.csv`) keep them, with `Stale_Reason`: `posted before the previous school year`, `closing date before the previous school year`; NA on every counted row. Raw postings saved before the rule (November 26, 2026) have no `Stale_Reason` column; the history files judge their board postings by the same rule, with each update's own date (recomputed November 26, 2026).

---

### B. K-12 Historical Archive (`k12jobanalysis.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `title` | String | Job posting (district job board or OPI Jobs for Teachers) | Standardized job vacancy title as published by the school district or OPI feed. |
| `Archive_Date` | Date (YYYY-MM-DD) | This dashboard: snapshot at each update | Date of the update that saw the posting listed (the dashboard updates twice a week since 2026-11-17, weekly before). |
| `position` | Categorical | This dashboard: job title classification | Broad staff position group (Teacher, Administrator, Support Services, etc.). |
| `location` | String | Job posting (district job board or OPI Jobs for Teachers) | Specific school building, facility, or employer city/location label. |
| `url` | URL | Job posting (district job board or OPI Jobs for Teachers) | Direct URL link to the official job vacancy listing or district portal. |
| `District` | String | This dashboard: district and college list | Canonical public school district name. |
| `Posting_Source` | String | This dashboard: posting tracking | Original job feed source (direct district ATS board vs OPI statewide feed). |
| `Posting_Identity_Method` | String | This dashboard: posting tracking | Durable identity fingerprint method used (Stable per-posting URL vs Source fallback). |
| `Posting_ID` | String | This dashboard: posting tracking | Durable unique posting identifier, the same for a posting in every update it appears in. |
| `Category` | String | This dashboard: job title classification | Fine-grained subject specialization or departmental role assignment. |
| `Broad_Category` | Categorical | This dashboard: job title classification | Clustered high-level category grouping (Elementary, STEM, Special Education, Humanities, etc.). |
| `Role_Hint` | Categorical | This dashboard: job title classification | What the posting's own description says about the role, used to refine its position bucket: Substitute (a long-term substitute), Paraprofessional, Part-Time (a part-time or under-1.0-FTE teacher), Teacher, Counselor or Administration (the role the description names first). OPI postings only, from 2026-11-03 (when OPI descriptions began to be archived): OPI's title is its subject-area field, which misfiles some postings (e.g. a long-term substitute, a paraeducator under "Elementary Curriculum", a teacher under "Administrative - Other"). NA when the description gives no clear signal, and for every other source. |

---

### C. K-12 Job Duration Spells (`job_duration_spells.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `District` | String | This dashboard: district and college list | Canonical public school district or employer location name. |
| `NCES_LEAID` | String (7-digit) | NCES Common Core of Data (CCD) | Federal NCES 7-digit Local Education Agency identifier. |
| `Title` | String | Job posting (district job board or OPI Jobs for Teachers) | Standardized job vacancy title. |
| `Category` | String | This dashboard: job title classification | Fine-grained subject area or functional assignment. |
| `Broad_Category` | Categorical | This dashboard: job title classification | High-level clustered subject or role category. |
| `Position` | Categorical | This dashboard: job title classification | Broad staff position group (Teacher, Administrator, Support Services). |
| `First_Seen_Date` | Date (YYYY-MM-DD) | This dashboard: posting tracking | Earliest update in which this job posting was observed active. |
| `Last_Seen_Date` | Date (YYYY-MM-DD) | This dashboard: posting tracking | Latest update in which this job posting was observed active. |
| `Weeks_Observed` | Integer | This dashboard: posting tracking | Number of distinct calendar weeks (ISO weeks) in which this posting was observed during the spell. A posting absent for more than 21 days that reappears under the same title starts a new spell. |
| `Estimated_Days_Open` | Integer | This dashboard: posting tracking | Estimated days the posting was listed: first to last sighting, plus half the time to the next update once it is gone. How long a listing stays up, not time to fill: filled jobs can stay posted and open jobs get reposted. |
| `Status` | Categorical | This dashboard: posting tracking | Still Active (listed in the latest update) or Closed / Filled (no longer listed; whether it was filled isn't known). |
| `is_stem` | Binary (0/1) | This dashboard: job title classification | Dummy indicator: 1 if position is Science, Technology, Engineering, or Math; 0 otherwise. |
| `is_sped` | Binary (0/1) | This dashboard: job title classification | Dummy indicator: 1 if position is Special Education; 0 otherwise. |
| `is_elementary` | Binary (0/1) | This dashboard: job title classification | Dummy indicator: 1 if position is Elementary Education; 0 otherwise. |
| `is_secondary` | Binary (0/1) | This dashboard: job title classification | Dummy indicator: 1 if position is Middle or High School; 0 otherwise. |
| `is_admin` | Binary (0/1) | This dashboard: job title classification | Dummy indicator: 1 if position is Administration, Principal, or Superintendent; 0 otherwise. |
| `is_support_staff` | Binary (0/1) | This dashboard: job title classification | Dummy indicator: 1 if position is Classified Support, Paraprofessional, Custodial, Bus, or Food Service; 0 otherwise. |

---

### D. District Profiles & Benchmarks (`salarymap2.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `District` | String | This dashboard: district and college list | Canonical public school district name. |
| `County` | String | US Census Bureau | Primary county in which the district central administrative office is located. |
| `Latitude` | Decimal Degrees | This dashboard: district and college list | Geographic latitude coordinate of district central headquarters. |
| `Longitude` | Decimal Degrees | This dashboard: district and college list | Geographic longitude coordinate of district central headquarters. |
| `Job_Link` | URL | This dashboard: district and college list | Official employment or applicant tracking portal link for the district. |
| `NCES_LEAID` | String (7-digit) | NCES Common Core of Data (CCD) | Federal NCES 7-digit Local Education Agency identifier. |
| `CCD_Link` | URL | NCES Common Core of Data (CCD) | Link to this district's page in the NCES Common Core of Data district search, built from NCES_LEAID (edjobs nces_district_url()). The page shows NCES's newest school year, which can be newer than CCD_Year. Blank when the district has no NCES id. |
| `Teacher_Count` | Integer | MT DLI Teacher Compensation Report | Total certified classroom teachers reported in the regional DLI compensation dataset. |
| `Teacher_Salary_10th_Pctile` | Currency ($) | MT DLI Teacher Compensation Report | 10th percentile teacher salary published in the Montana DLI Regional Wage Report. |
| `Teacher_Avg_Salary` | Currency ($) | MT DLI Teacher Compensation Report | Average annual compensation paid across all employed certified classroom teachers. |
| `Teacher_Salary_90th_Pctile` | Currency ($) | MT DLI Teacher Compensation Report | 90th percentile teacher salary published in the Montana DLI Regional Wage Report. |
| `Salary_Year` | String | MT DLI Teacher Compensation Report | Data collection school year corresponding to the published DLI wage report. |
| `Salary_Source` | String | MT DLI Teacher Compensation Report | Publishing authority (Montana Department of Labor & Industry via OPI GEMS). |
| `Teachers_Total_FTE` | Numeric | NCES Common Core of Data (CCD) | Total full-time-equivalent certified classroom teachers employed by the district. |
| `Enrollment` | Integer | NCES Common Core of Data (CCD) | Total pre-K through grade 12 student enrollment count. |
| `CCD_Year` | Integer | NCES Common Core of Data (CCD) | Data collection school year for federal CCD staffing and enrollment counts. |
| `CCD_Source` | String | NCES Common Core of Data (CCD) | Federal source citation for NCES CCD public school district universe data. |
| `Data_Coverage` | Categorical | This dashboard: coverage summary | Scraper coverage fidelity tier: Full (direct ATS integration) vs Partial (read from the district's own website); "Postings via OPI's statewide board" for a district with no board of its own (registry Platform OPIOnly). |
| `Median_Household_Income` | Currency ($) | US Census ACS 5-year | County median annual household income in inflation-adjusted dollars. |
| `Median_Household_Income_MOE` | Currency ($) | US Census ACS 5-year | Census's 90% margin of error for Median_Household_Income (B19013_001M). Shown as ± on the dashboard. |
| `Median_Gross_Rent` | Currency ($) | US Census ACS 5-year | County median monthly gross rent including estimated utilities. |
| `Median_Gross_Rent_MOE` | Currency ($) | US Census ACS 5-year | Census's 90% margin of error for Median_Gross_Rent (B25064_001M). |
| `Population` | Integer | US Census ACS 5-year | Total estimated resident population of the county. |
| `ACS_Year` | Integer | US Census ACS 5-year | Data release year for US Census American Community Survey 5-year estimates. |
| `Mining_Employment_Share` | Proportion (0-1) | US Census ACS 5-year | Share of the county's employed civilians (16 and over) who work in mining, quarrying, and oil and gas extraction (ACS table S2403). |
| `Mining_Employment_Share_MOE` | Proportion (0-1) | US Census ACS 5-year (derived) | 90% margin of error for Mining_Employment_Share, from Census's formula for a derived proportion (ACS handbook 2020, ch. 8, formula 6) using the S2403 MOEs. When it is at least the share itself, the share is not distinguishable from zero (Census's CV > 0.61 line) and the dashboard says so. Census's CV-based reliability rules are unstable for shares under 5% (National Research Council 2007, p. 67), so no reliability tier is given. |
| `Population_Change_Pct` | Proportion | US Census ACS 5-year | County 5-year percentage change in total resident population. |
| `Child_Poverty_Rate` | Proportion (0-1) | US Census SAIPE | Share of children 5-17 in families below the poverty line. Separate elementary and high school districts (e.g. Billings) are combined by their numbers of children. Not a true poverty rate (Census): the first count includes only children related to the householder, in families in poverty; the second, all children 5-17 (foster children, other unrelated children and children in group quarters are in the second only). The dashboards label it "School-age children in poverty (Census est.)". |
| `SAIPE_Population` | Number | US Census SAIPE | Total population of the SAIPE district behind the child poverty estimate (SAEPOVALL_PT); for a combined elementary + high school district, the larger one's (the high school district covers both). It sets the estimate's error band. |
| `Child_Poverty_Low` | Proportion (0-1) | US Census SAIPE (derived) | Low end of Census's approximate 90% range for Child_Poverty_Rate: rate x (1 - 1.645 x CV), floored at 0. CV is Census's median relative error for districts of that size (0.67 under 2,500 people down to 0.15 at 65,000+; "Quantifying Relative Error in the School District Estimates", revised 2025-12-17), which Census calls an approximate upper bound. Census publishes no margin of error for one district. |
| `Child_Poverty_High` | Proportion (0-1) | US Census SAIPE (derived) | High end of the same range: rate x (1 + 1.645 x CV), capped at 1. See Child_Poverty_Low. |
| `SAIPE_Year` | Integer | US Census SAIPE | Release year of federal Small Area Income and Poverty Estimates data. |
| `Total_General_Fund_Expenditure` | Currency ($) | OPI School Finance Files | Total district General Fund operating expenditures. |
| `Finance_FY` | String / Integer | OPI School Finance Files | State fiscal year for OPI financial expenditure reporting. |
| `Finance_Source` | String | OPI School Finance Files | Publishing state agency authority for Montana Office of Public Instruction annual finance files. |

---

### E. Higher Ed Historical Archive (`facultydata.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Title` | String | Job posting (college job board) | Published higher education job vacancy title as advertised on the college careers portal. |
| `Location` | String | Job posting (college job board) | Campus location, city, or remote work designation. |
| `Posted_Date` | String / Date | Job posting (college job board) | Original date of vacancy posting as published by the college or university. |
| `Institution` | String | This dashboard: district and college list | Collegiate institution canonical name. |
| `Link` | URL | Job posting (college job board) | Direct web URL to the employment vacancy listing. |
| `Archive_Date` | Date (YYYY-MM-DD) | This dashboard: snapshot at each update | Date of the update that saw the posting listed (the dashboard updates twice a week since 2026-11-17, weekly before). |
| `Job_Type` | Categorical | This dashboard: job title classification | Instructor/Teacher/Faculty or Adjunct/Part-Time Faculty (this file holds faculty postings only). |
| `Category` | String | This dashboard: job title classification | Academic discipline or administrative functional area. |

---

### F. Higher Ed Job Duration Spells (`he_job_duration_spells.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Institution` | String | This dashboard: district and college list | Collegiate institution canonical name. |
| `IPEDS_UNITID` | String (6-digit) | NCES IPEDS | Official 6-digit federal NCES Integrated Postsecondary Education Data System Unit ID. |
| `Title` | String | Job posting (college job board) | Standardized collegiate job vacancy title. |
| `Category` | String | This dashboard: job title classification | Academic discipline or functional assignment area. |
| `Job_Type` | Categorical | This dashboard: job title classification | Collegiate appointment type (Instructor/Teacher/Faculty or Adjunct/Part-Time Faculty). |
| `First_Seen_Date` | Date (YYYY-MM-DD) | This dashboard: posting tracking | Earliest update in which this job posting was observed active. |
| `Last_Seen_Date` | Date (YYYY-MM-DD) | This dashboard: posting tracking | Latest update in which this job posting was observed active. |
| `Weeks_Observed` | Integer | This dashboard: posting tracking | Number of distinct calendar weeks (ISO weeks) in which this posting was observed during the spell. A posting absent for more than 21 days that reappears under the same title starts a new spell. |
| `Estimated_Days_Open` | Integer | This dashboard: posting tracking | Estimated days the posting was listed: first to last sighting, plus half the time to the next update once it is gone. How long a listing stays up, not time to fill: filled jobs can stay posted and open jobs get reposted. |
| `Status` | Categorical | This dashboard: posting tracking | Still Active (listed in the latest update) or Closed / Filled (no longer listed; whether it was filled isn't known). |
| `is_stem` | Binary (0/1) | This dashboard: job title classification | Dummy indicator: 1 if position is Science, Technology, Engineering, or Math; 0 otherwise. |
| `is_health` | Binary (0/1) | This dashboard: job title classification | Dummy indicator: 1 if position is Health Sciences, Nursing, or Medical; 0 otherwise. |
| `is_cte` | Binary (0/1) | This dashboard: job title classification | Dummy indicator: 1 if position is Career & Technical Education or Trades; 0 otherwise. |
| `is_adjunct` | Binary (0/1) | This dashboard: job title classification | Dummy indicator: 1 if position is Part-Time or Adjunct Faculty; 0 otherwise. |
| `is_faculty` | Binary (0/1) | This dashboard: job title classification | Dummy indicator: 1 if position is Full-Time Instructional Faculty; 0 otherwise. |

---

### G. Higher Ed Institutional Profiles (`salarymap.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Name` | String | This dashboard: district and college list | College or university name. |
| `County` | String | US Census Bureau | County in which the collegiate campus is located. |
| `Longitude` | Decimal Degrees | This dashboard: district and college list | Geographic longitude coordinate of main campus centroid. |
| `Latitude` | Decimal Degrees | This dashboard: district and college list | Geographic latitude coordinate of main campus centroid. |
| `Link` | URL | This dashboard: district and college list | Official careers or employment opportunities portal URL for the institution. |
| `IPEDS_UNITID` | String (6-digit) | NCES IPEDS | Official 6-digit federal NCES Integrated Postsecondary Education Data System Unit ID. |
| `IPEDS_Link` | URL | NCES IPEDS | Link to this institution's page in NCES College Navigator, built from IPEDS_UNITID (edjobs college_navigator_url()). The page shows NCES's newest year, which can be newer than this file's year columns. Blank when the institution has no IPEDS id. |
| `Faculty_Avg_Salary` | Currency ($) | NCES IPEDS | Average salary of full-time instructional staff on 9- to 12-month contracts (IPEDS collects none for part-time staff or for contracts under 9 months) across all academic ranks combined. |
| `Faculty_Avg_Salary_Professor` | Currency ($) | NCES IPEDS | Average salary of full-time instructional staff on 9- to 12-month contracts (IPEDS collects none for part-time staff or for contracts under 9 months) for the Full Professor rank. |
| `Faculty_Count` | Integer | NCES IPEDS | Total count of full-time instructional faculty employed by the institution. |
| `Salary_Year` | Integer | NCES IPEDS | Academic reporting year for IPEDS faculty compensation data. |
| `Salary_Source` | String | NCES IPEDS | Primary source citation for instructional faculty pay. |
| `Faculty_Avg_Salary_Y1Ago` | Currency ($) | NCES IPEDS | Average salary of full-time instructional staff on 9- to 12-month contracts (IPEDS collects none for part-time staff or for contracts under 9 months) in the prior academic year (t-1). |
| `Faculty_Avg_Salary_Y2Ago` | Currency ($) | NCES IPEDS | Average salary of full-time instructional staff on 9- to 12-month contracts (IPEDS collects none for part-time staff or for contracts under 9 months) two academic years prior (t-2). |
| `Enrollment` | Integer | NCES IPEDS | Total unduplicated fall student enrollment count. |
| `Enrollment_Year` | Integer | NCES IPEDS | Academic reporting year for IPEDS fall enrollment figures. |
| `Enrollment_Change_Pct` | Proportion | NCES IPEDS | 5-year percentage change in total fall student enrollment. |
| `Pell_Recipient_Share` | Proportion (0-1) | US Dept of Education FSA | Share of undergraduate degree-seeking students awarded federal need-based Pell Grants. |
| `Pell_Year` | Integer | US Dept of Education FSA | Award year for Federal Student Aid (FSA) Pell Grant recipient figures. |
| `Median_Household_Income` | Currency ($) | US Census ACS 5-year | County median annual household income in inflation-adjusted dollars. |
| `Median_Household_Income_MOE` | Currency ($) | US Census ACS 5-year | Census's 90% margin of error for Median_Household_Income (B19013_001M). Shown as ± on the dashboard. |
| `Median_Gross_Rent` | Currency ($) | US Census ACS 5-year | County median monthly gross rent including estimated utilities. |
| `Median_Gross_Rent_MOE` | Currency ($) | US Census ACS 5-year | Census's 90% margin of error for Median_Gross_Rent (B25064_001M). |
| `Population` | Integer | US Census ACS 5-year | Total estimated resident population of the county. |
| `ACS_Year` | Integer | US Census ACS 5-year | Data release year for US Census American Community Survey 5-year estimates. |
| `Mining_Employment_Share` | Proportion (0-1) | US Census ACS 5-year | Share of the county's employed civilians (16 and over) who work in mining, quarrying, and oil and gas extraction (ACS table S2403). |
| `Mining_Employment_Share_MOE` | Proportion (0-1) | US Census ACS 5-year (derived) | 90% margin of error for Mining_Employment_Share, from Census's formula for a derived proportion (ACS handbook 2020, ch. 8, formula 6) using the S2403 MOEs. When it is at least the share itself, the share is not distinguishable from zero (Census's CV > 0.61 line) and the dashboard says so. Census's CV-based reliability rules are unstable for shares under 5% (National Research Council 2007, p. 67), so no reliability tier is given. |
| `Population_Change_Pct` | Proportion | US Census ACS 5-year | County 5-year percentage change in total resident population. |

---

### H. K-12 Weekly Vacancy Time Series (`k12_district_weekly_totals.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `District` | String | This dashboard: district and college list | Canonical public school district or employer location name. |
| `Archive_Date` | Date (YYYY-MM-DD) | This dashboard: snapshot at each update | Date of the update. |
| `n` | Integer | This dashboard: snapshot at each update | Total count of active job postings observed open for that district in that week. |
| `n_not_marked` | Integer | This dashboard: job classification | Of those, postings classify_work_schedule() (edjobs) does not mark as a substitute, extra-duty (coaching, activities, stipend), part-time, student or temporary/seasonal job. Sources never confirm full-time, so this is "not marked", not "full-time". The Home page's top districts table and its sparklines count these when its switch is on (the default). |

---

### H2. K-12 Job Type Time Series (`k12_jobtype_weekly_totals.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Job_Type` | String | This dashboard: job classification | K-12 position bucket (position in combinedclean.csv). |
| `Archive_Date` | Date (YYYY-MM-DD) | This dashboard: snapshot at each update | Date of the update. |
| `n` | Integer | This dashboard: snapshot at each update | Count of active job postings of that type observed open on that update. |
| `n_not_marked` | Integer | This dashboard: job classification | Of those, postings classify_work_schedule() (edjobs) does not mark as a substitute, extra-duty (coaching, activities, stipend), part-time, student or temporary/seasonal job. Sources never confirm full-time, so this is "not marked", not "full-time". The Home page's job-type tables count these. |

---

### I. Higher Ed Weekly Vacancy Time Series (`he_institution_weekly_totals.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Institution` | String | This dashboard: district and college list | College or university name. |
| `Archive_Date` | Date (YYYY-MM-DD) | This dashboard: snapshot at each update | Date of the update. |
| `n` | Integer | This dashboard: snapshot at each update | Total count of active job postings observed open for that higher education institution in that week. |
| `n_not_marked` | Integer | This dashboard: job classification | Of those, postings classify_work_schedule() (edjobs) does not mark as a substitute, extra-duty (coaching, activities, stipend), part-time, student or temporary/seasonal job. Sources never confirm full-time, so this is "not marked", not "full-time". The Home page's top colleges table and its sparklines count these when its switch is on (the default). |

---

### I2. Higher Ed Job Type Time Series (`he_jobtype_weekly_totals.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Job_Type` | String | This dashboard: job classification | College job type (classify_he_job_type(), every posting, not only faculty). |
| `Archive_Date` | Date (YYYY-MM-DD) | This dashboard: snapshot at each update | Date of the update. |
| `n` | Integer | This dashboard: snapshot at each update | Count of active college job postings of that type observed open on that update. |
| `n_not_marked` | Integer | This dashboard: job classification | Of those, postings classify_work_schedule() (edjobs) does not mark as a substitute, extra-duty (coaching, activities, stipend), part-time, student or temporary/seasonal job. Sources never confirm full-time, so this is "not marked", not "full-time". The Home page's job-type tables count these. |

---

### J. District Crosswalk (`mt_district_crosswalk.csv`)

Every Montana public district in NCES CCD, tied to the registry district whose job board covers it (or none). Refreshed each update; drives which OPI postings count.

| Column | Type | Authority | Definition |
|---|---|---|---|
| `LEAID` | String | NCES Common Core of Data (CCD) | NCES district ID. |
| `OPI_District` | String | NCES Common Core of Data (CCD) | CCD district name, which is also the name OPI Jobs for Teachers detail pages use. |
| `City` | String | NCES Common Core of Data (CCD) | District's city (CCD location address). |
| `County` | String | NCES Common Core of Data (CCD) | District's county. |
| `Latitude` | Numeric | NCES Common Core of Data (CCD) | District latitude (CCD). |
| `Longitude` | Numeric | NCES Common Core of Data (CCD) | District longitude (CCD). |
| `Teachers_Total_FTE` | Numeric | NCES Common Core of Data (CCD) | Teacher FTE for this district. |
| `Enrollment` | Integer | NCES Common Core of Data (CCD) | Student enrollment for this district. |
| `Registry_District` | String | This dashboard: district and college list | The directly scraped registry district whose job board covers this district; NA if it isn't scraped directly. |
| `Match_Rule` | String | This dashboard: district and college list | How Registry_District was assigned: registry NCES id, same town and name (elementary/high school pair), or high school in a scraped town. |
| `Map_Entity` | String | This dashboard: district and college list | Name used on the map and in District: the registry district, or for districts not scraped directly one name per town (e.g. 'Box Elder Elem / Box Elder H S'). |
| `CCD_Year` | Integer | NCES Common Core of Data (CCD) | CCD directory year. |

### K. OPI-only Districts (`opi_only_districts.csv`)

Districts not scraped directly that posted on OPI Jobs for Teachers this week: their map rows, with the same context as `salarymap2.csv` where a statewide source covers them.

| Column | Type | Authority | Definition |
|---|---|---|---|
| `District` | String | This dashboard: district and college list | Map entity: a district (or town pair) not scraped directly that posted on OPI Jobs for Teachers this week. |
| `County` | String | NCES Common Core of Data (CCD) | County. |
| `City` | String | NCES Common Core of Data (CCD) | City. |
| `Latitude` | Numeric | NCES Common Core of Data (CCD) | Latitude (mean over the entity's districts). |
| `Longitude` | Numeric | NCES Common Core of Data (CCD) | Longitude (mean over the entity's districts). |
| `Teachers_Total_FTE` | Numeric | NCES Common Core of Data (CCD) | Teacher FTE, summed over the entity's districts. |
| `Enrollment` | Integer | NCES Common Core of Data (CCD) | Enrollment, summed over the entity's districts. |
| `OPI_Districts` | String | NCES Common Core of Data (CCD) | The entity's district names, ' / '-separated. |
| `LEAIDs` | String | NCES Common Core of Data (CCD) | The entity's NCES district IDs, ';'-separated. |
| `Data_Coverage` | String | This dashboard: coverage summary | Always "Postings via OPI's statewide board": openings come from OPI, not a direct scrape. |
| `Job_Link` | String | OPI Jobs for Teachers | OPI Jobs for Teachers board. |
| `Teacher_Count` | Integer | MT DLI Teacher Compensation Report | Teachers in the matched DLI school system. |
| `Teacher_Salary_10th_Pctile` | Currency ($) | MT DLI Teacher Compensation Report | 10th percentile teacher salary of the matched DLI school system. |
| `Teacher_Avg_Salary` | Currency ($) | MT DLI Teacher Compensation Report | Average teacher salary of the matched DLI school system; NA where DLI suppresses it or no system matches by name. |
| `Teacher_Salary_90th_Pctile` | Currency ($) | MT DLI Teacher Compensation Report | 90th percentile teacher salary of the matched DLI school system. |
| `DLI_Name` | String | MT DLI Teacher Compensation Report | DLI school system matched by name (one match only); may cover an elementary and high school district together. |
| `Salary_Year` | String | MT DLI Teacher Compensation Report | School year of the DLI figures. |
| `Salary_Source` | String | MT DLI Teacher Compensation Report | Source of the salary figures. |
| `Child_Poverty_Rate` | Proportion (0-1) | US Census SAIPE | Estimated share of children 5-17 in poverty (SAIPE, by NCES id). An entity with an elementary and a high school district adds their children in poverty and divides by all their children. Not a true poverty rate (Census): the first count includes only children related to the householder, in families in poverty; the second, all children 5-17 (foster children, other unrelated children and children in group quarters are in the second only). The dashboards label it "School-age children in poverty (Census est.)". |
| `SAIPE_Population` | Number | US Census SAIPE | Total population of the SAIPE district behind the child poverty estimate (SAEPOVALL_PT); for a combined elementary + high school district, the larger one's (the high school district covers both). It sets the estimate's error band. |
| `Child_Poverty_Low` | Proportion (0-1) | US Census SAIPE (derived) | Low end of Census's approximate 90% range for Child_Poverty_Rate: rate x (1 - 1.645 x CV), floored at 0. CV is Census's median relative error for districts of that size (0.67 under 2,500 people down to 0.15 at 65,000+; "Quantifying Relative Error in the School District Estimates", revised 2025-12-17), which Census calls an approximate upper bound. Census publishes no margin of error for one district. |
| `Child_Poverty_High` | Proportion (0-1) | US Census SAIPE (derived) | High end of the same range: rate x (1 + 1.645 x CV), capped at 1. See Child_Poverty_Low. |
| `SAIPE_Year` | Integer | US Census SAIPE | SAIPE year. |
| `Total_General_Fund_Expenditure` | Currency ($) | OPI School Finance Files | General Fund expenditure, summed over the entity's districts. |
| `Finance_FY` | String / Integer | OPI School Finance Files | State fiscal year of the finance figures. |
| `Finance_Source` | String | OPI School Finance Files | Source of the finance figures. |
| `Median_Household_Income` | Currency ($) | US Census ACS 5-year | County median household income. |
| `Median_Household_Income_MOE` | Currency ($) | US Census ACS 5-year | Census's 90% margin of error for Median_Household_Income (B19013_001M). Shown as ± on the dashboard. |
| `Median_Gross_Rent` | Currency ($) | US Census ACS 5-year | County median gross rent. |
| `Median_Gross_Rent_MOE` | Currency ($) | US Census ACS 5-year | Census's 90% margin of error for Median_Gross_Rent (B25064_001M). |
| `Population` | Integer | US Census ACS 5-year | County population. |
| `ACS_Year` | Integer | US Census ACS 5-year | ACS release year. |
| `Mining_Employment_Share` | Proportion (0-1) | US Census ACS 5-year | Share of the county's employed civilians (16 and over) who work in mining, quarrying, and oil and gas extraction (ACS table S2403). |
| `Mining_Employment_Share_MOE` | Proportion (0-1) | US Census ACS 5-year (derived) | 90% margin of error for Mining_Employment_Share, from Census's formula for a derived proportion (ACS handbook 2020, ch. 8, formula 6) using the S2403 MOEs. When it is at least the share itself, the share is not distinguishable from zero (Census's CV > 0.61 line) and the dashboard says so. Census's CV-based reliability rules are unstable for shares under 5% (National Research Council 2007, p. 67), so no reliability tier is given. |
| `Population_Change_Pct` | Proportion | US Census ACS 5-year | County 5-year population change. |
| `CCD_Year` | Integer | NCES Common Core of Data (CCD) | CCD directory year. |

## 4. More Datasets

Summary counts, current college postings, and the reference tables behind the pay estimates and dates.

### L. K-12 Current Category Counts (`allnow.csv`)

Teaching postings in the latest update by subject group and district, with statewide totals.

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Broad_Category` | Categorical | This dashboard: teaching postings | Teaching subject group (Elementary, STEM, Special Education, Humanities, ...). Teaching postings only. |
| `Sum` | Integer | This dashboard: teaching postings | Teaching postings in that subject group at that district in the latest update. |
| `District` | String | This dashboard: teaching postings | District name, or "Total" for the statewide sum of the district rows. |

### M. K-12 Category Time Series (`allsum.csv`)

Teaching postings by subject group and district in every update, with statewide totals.

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Broad_Category` | Categorical | This dashboard: teaching postings | Teaching subject group (Elementary, STEM, Special Education, Humanities, ...). Teaching postings only. |
| `Archive_Date` | Date (YYYY-MM-DD) | This dashboard: teaching postings | Date of the update. |
| `District` | String | This dashboard: teaching postings | District name, or "Total" for the statewide sum of that update's district rows. |
| `sum` | Integer | This dashboard: teaching postings | Teaching postings in that subject group at that district in that update (distinct postings). |

### N. Higher Ed Current Category Counts (`allnow_he.csv`)

Faculty and adjunct postings in the latest update by discipline, type and college, with statewide totals.

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Category` | String | This dashboard: faculty postings | Faculty discipline (Science, Humanities, Health, ...). |
| `Job_Type` | Categorical | This dashboard: faculty postings | Instructor/Teacher/Faculty or Adjunct/Part-Time Faculty (faculty postings only). |
| `Sum` | Integer | This dashboard: faculty postings | Faculty postings of that discipline and type at that college in the latest update. |
| `Institution` | String | This dashboard: faculty postings | College name, or "Total" for the statewide sum of the college rows. |

### O. Higher Ed Category Time Series (`allsum_he.csv`)

Faculty and adjunct postings by discipline, type and college in every update, with statewide totals.

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Category` | String | This dashboard: faculty postings | Faculty discipline (Science, Humanities, Health, ...). |
| `Archive_Date` | Date (YYYY-MM-DD) | This dashboard: faculty postings | Date of the update. |
| `Institution` | String | This dashboard: faculty postings | College name, or "Total" for the statewide sum of that update's college rows. |
| `Job_Type` | Categorical | This dashboard: faculty postings | Instructor/Teacher/Faculty or Adjunct/Part-Time Faculty (faculty postings only). |
| `sum` | Integer | This dashboard: faculty postings | Faculty postings of that discipline and type at that college in that update. |

### P. Active Higher Ed Jobs (`hedata.xlsx`)

Every college posting listed in the latest update, all job types, with posted pay, campus placement and pay estimates.

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Title` | String | Job posting (college job board) | Job title as the college's board gives it. |
| `Location` | String | Job posting (college job board) | Location as the board gives it: a town on some platforms, a department on others. |
| `Posted_Date` | String | Job posting (college job board) | Posted date as the board gives it; blank where the board shows none. |
| `Institution` | String | Job posting (college job board) | College name. |
| `Link` | String | Job posting (college job board) | Link to the posting. |
| `Close_Date` | String | Job posting (college job board) | Closing date the posting page states (YYYY-MM-DD), where it gives one; PeopleAdmin boards only. |
| `Pay_Min` | Numeric | Job posting (college job board) | Lowest pay amount stated in the posting itself, in Pay_Unit (blank when the posting states no dollar figure). Never converted between units. |
| `Pay_Max` | Numeric | Job posting (college job board) | Highest pay amount stated in the posting (equals Pay_Min for a single figure). |
| `Pay_Unit` | String | Job posting (college job board) | Unit of Pay_Min and Pay_Max: hour, day, month, year, credit hour or stipend. Blank when no pay is stated, or when the stated unit is implausible for the amount. |
| `Pay_Text` | String | Job posting (college job board) | The posting text the pay was read from, kept so every figure can be checked against its source. |
| `Archive_Date` | Date (YYYY-MM-DD) | Job posting (college job board) | Date of the update that saw the posting listed (the dashboard updates twice a week since 2026-11-17, weekly before). |
| `Campus_Town` | String | Job posting (college job board) | The town the posting is mapped to when it is at a campus or site other than the college's main campus (Place_Basis other_town); blank otherwise. |
| `Campus_County` | String | Job posting (college job board) | County of Campus_Town. |
| `Campus_Latitude` | Numeric | Job posting (college job board) | Latitude of Campus_Town (Census place internal point). |
| `Campus_Longitude` | Numeric | Job posting (college job board) | Longitude of Campus_Town (Census place internal point). |
| `Place_Basis` | Categorical | Job posting (college job board) | Why the posting is mapped where it is: main (the main campus town), other_town (one other town in the state, named in its location, title or page), out_of_state, or no_town (nothing placeable, or several towns at once; shown at the main campus). |
| `Est_Pay` | Numeric | IPEDS via Urban Institute Education Data Portal | For a salaried staff posting: the college's average salary for full-time staff in the posting's IPEDS occupational category (Est_Occupation), per year. A college-wide average for the category, not this job's offer; given whether or not the posting states pay. |
| `Est_Pay_Unit` | String | IPEDS via Urban Institute Education Data Portal | year. |
| `Est_Occupation` | String | IPEDS via Urban Institute Education Data Portal | The IPEDS staff category the posting was matched to from its title. |
| `Est_Area` | String | IPEDS via Urban Institute Education Data Portal | The college whose IPEDS figure is used. |
| `Est_Year` | String | IPEDS via Urban Institute Education Data Portal | IPEDS year of the figure. |

### Q. IPEDS Staff Salaries (`ipeds_staff_salaries.csv`)

Average pay of full-time non-instructional staff by college and occupational category (categories with at least 3 staff).

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `IPEDS_UNITID` | Integer | IPEDS via Urban Institute Education Data Portal | IPEDS institution id; joins to salarymap.csv. |
| `Staff_Category` | Integer | IPEDS via Urban Institute Education Data Portal | IPEDS occupational category code for full-time non-instructional staff (2 research ... 14 production and transportation). |
| `Category_Label` | String | IPEDS via Urban Institute Education Data Portal | Short name of the category. |
| `Staff_Count` | Numeric | IPEDS via Urban Institute Education Data Portal | Full-time non-instructional staff in the category. |
| `Avg_Salary` | Numeric | IPEDS via Urban Institute Education Data Portal | Average salary: total salary outlays divided by staff count, rounded. |
| `Year` | String | IPEDS via Urban Institute Education Data Portal | IPEDS year. |

### R. K-12 Teacher Salary History (`k12_salary_history.csv`)

Teacher pay by district for each Teacher Compensation Report edition this project has captured (DLI keeps no public archive).

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `District` | String | Montana Department of Labor & Industry | District name. |
| `Salary_Year` | String | Montana Department of Labor & Industry | Data collection school year corresponding to the published DLI wage report. |
| `Teacher_Count` | Integer | Montana Department of Labor & Industry | Total certified classroom teachers reported in the regional DLI compensation dataset. |
| `Teacher_Salary_10th_Pctile` | Currency ($) | Montana Department of Labor & Industry | 10th percentile teacher salary published in the Montana DLI Regional Wage Report. |
| `Teacher_Avg_Salary` | Currency ($) | Montana Department of Labor & Industry | Average annual compensation paid across all employed certified classroom teachers. |
| `Teacher_Salary_90th_Pctile` | Currency ($) | Montana Department of Labor & Industry | 90th percentile teacher salary published in the Montana DLI Regional Wage Report. |

### S. BLS Regional Pay by Role (`oews_role_wages.csv`)

Median pay for the occupations K-12 postings are matched to, by Montana OEWS area; the source of the K-12 Typical pay (BLS est.) column.

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Area_Code` | String | BLS Occupational Employment and Wage Statistics (OEWS) | OEWS area code (keep as text: metro codes have leading zeros, e.g. `0013740`). |
| `Area_Name` | String | BLS Occupational Employment and Wage Statistics (OEWS) | OEWS area name: the state, a metro area, or a nonmetropolitan area. |
| `SOC` | String | BLS Occupational Employment and Wage Statistics (OEWS) | 2018 SOC code without the dash, e.g. `259045`. |
| `Occupation` | String | BLS Occupational Employment and Wage Statistics (OEWS) | OEWS occupation title. |
| `Annual_Median` | Numeric | BLS Occupational Employment and Wage Statistics (OEWS) | Annual median wage. `NA` where BLS suppresses the figure for that area. |
| `Hourly_Median` | Numeric | BLS Occupational Employment and Wage Statistics (OEWS) | Hourly median, fetched only for roles usually paid hourly; `NA` where BLS publishes none (school-year roles such as teaching assistants). |
| `Year` | String | BLS Occupational Employment and Wage Statistics (OEWS) | Reference year (May). |

### T. OPI District Counties (`opi_district_counties.csv`)

The county of each district as OPI names it, used to give OPI postings a county.

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `OPI_District` | String | OPI school finance data files | As OPI writes it ("Absarokee Elem", "Absarokee H S"). |
| `County` | String | OPI school finance data files | "Stillwater County", the registry's form. |

### U. Posting First Seen (`posting_first_seen.csv`)

When the dashboard first found each currently listed posting; shown where the board gives no posted date.

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Segment` | Categorical | This dashboard: posting tracking | K-12 or HE. |
| `Key` | String | This dashboard: posting tracking | District or college, title and link, lowercased and joined with " / ": the key the dashboard uses to look up a posting it shows. |
| `First_Seen` | Date (YYYY-MM-DD) | This dashboard: posting tracking | First update that found the posting. The dashboard shows it where the board gives no posted date. |
| `Left_Censored` | Logical | This dashboard: posting tracking | TRUE when the posting was already listed the first time this project read that board, so it may have been up longer (shown as "on the board since at least"). |

### V. County Public School Pay (`qcew_county_school_pay.csv`)

Average annual pay and employment of public school (local government, NAICS 6111) employees by county, all roles together.

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `County` | String | BLS Quarterly Census of Employment and Wages (QCEW) | "Yellowstone County" (joined to `salarymap2.csv`'s `County` with any ", State" suffix dropped). |
| `County_FIPS` | String | BLS Quarterly Census of Employment and Wages (QCEW) | Five-digit county FIPS. |
| `School_Employment` | Numeric | BLS Quarterly Census of Employment and Wages (QCEW) | Annual average employment. |
| `Avg_Annual_Pay` | Numeric | BLS Quarterly Census of Employment and Wages (QCEW) | Annual average pay per employee. |
| `Year` | String | BLS Quarterly Census of Employment and Wages (QCEW) | QCEW reference year. |

### W. Source Retrieval Dates (`source_retrieved_dates.csv`)

When each outside data source was last fetched successfully.

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Source` | String | This dashboard: update log | An outside data source the dashboard uses (BLS OEWS, Census ACS, Urban IPEDS, ...). |
| `Retrieved` | Date (YYYY-MM-DD) | This dashboard: update log | Last date that source was fetched successfully; shown on the Data tab. |
