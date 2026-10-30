# Montana Education Jobs Dashboard — Data Dictionary & Codebook

Comprehensive variable codebook, schema definitions, and methodological provenance for datasets compiled and published by the **Montana Education Jobs Dashboard**.

Each dataset is accessible via the **Data Sources & Open Research Downloads** tab in the interactive web dashboard or by downloading machine-readable CSVs directly from this repository.

---

## 1. Datasets Overview

| Dataset Layer | Primary File | Description | Granularity | Refresh Cadence |
| :--- | :--- | :--- | :--- | :--- |
| **Active K-12 Jobs** | `combinedclean.csv` | All active public school job vacancies currently open across school districts. | Posting level | Weekly |
| **K-12 Historical Archive** | `k12jobanalysis.csv` | Multi-year longitudinal archive of all weekly K-12 job postings with standardized categorizations. | Posting level | Weekly |
| **K-12 Job Duration Spells** | `job_duration_spells.csv` | Longitudinal panel tracking vacancy duration (time-to-fill) and shortage dummy flags. | Posting spell | Weekly |
| **District Profiles & Benchmarks** | `salarymap2.csv` | District-level staffing, compensation benchmarks, and Census context. | District level | Weekly / Annual |
| **Higher Ed Historical Postings** | `facultydata.csv` | Multi-year longitudinal postings for instructional faculty, adjuncts, and staff. | Posting level | Weekly |
| **Higher Ed Job Duration Spells** | `he_job_duration_spells.csv` | Longitudinal spell panel tracking collegiate faculty search duration (time-to-fill) and discipline flags. | Posting spell | Weekly |
| **Higher Ed Institutional Profiles** | `salarymap.csv` | College and university profiles: IPEDS instructional faculty salaries, enrollment, and Pell recipient shares. | Institution level | Weekly / Annual |
| **K-12 Weekly Vacancy Time Series** | `k12_district_weekly_totals.csv` | Weekly aggregate open job vacancy counts by school district over time. | District × Week | Weekly |
| **Higher Ed Weekly Vacancy Time Series** | `he_institution_weekly_totals.csv` | Weekly aggregate open job vacancy counts by higher education institution. | Institution × Week | Weekly |
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
| `title` | String | District ATS / OPI | Official job vacancy title as published by the school district or OPI Jobs for Teachers feed. |
| `Archive_Date` | Date (YYYY-MM-DD) | Project Scraper | Weekly snapshot observation date on which the vacancy was captured as actively open. |
| `date_posted` | String / Date | District ATS / OPI | Original posted date string as published on the district applicant tracking board. |
| `position` | Categorical | Classification Model | Broad staff position group (Teacher, Administrator, Support Services, etc.). |
| `location` | String | District ATS / OPI | Specific school building, facility, or employer city/location label. |
| `url` | URL | District ATS / OPI | Direct link to the job posting or district applicant tracking portal. |
| `District` | String | Canonical Registry | Canonical public school district name (or raw city label for OPI statewide rows). |
| `Posting_Source` | String | Project Pipeline | Original job feed source (direct district ATS board vs OPI Jobs for Teachers feed). |
| `Posting_Identity_Method` | String | Project Pipeline | Durable identity fingerprint method used (Stable per-posting URL vs Source fallback). |
| `Posting_ID` | String | Project Pipeline | Durable unique posting identifier used to track openings longitudinally across weekly snapshots. |
| `Pay_Min` | Numeric | Job posting | Lowest pay amount stated in the posting itself, in `Pay_Unit` (NA when no dollar figure is stated). Never converted between units. |
| `Pay_Max` | Numeric | Job posting | Highest stated amount (equals `Pay_Min` for a single figure). |
| `Pay_Unit` | String | Job posting | `hour`, `day`, `month`, `year`, `credit hour`, or `stipend` (season/activity amount); NA when undeterminable. |
| `Pay_Text` | String | Job posting | The posting text the pay was read from, for verification. |

---

### B. K-12 Historical Archive (`k12jobanalysis.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `title` | String | District ATS / OPI | Standardized job vacancy title as published by the school district or OPI feed. |
| `Archive_Date` | Date (YYYY-MM-DD) | Project Scraper | Weekly snapshot observation date on which the vacancy was captured as open. |
| `position` | Categorical | Classification Model | Broad staff position group (Teacher, Administrator, Support Services, etc.). |
| `location` | String | District ATS / OPI | Specific school building, facility, or employer city/location label. |
| `url` | URL | District ATS / OPI | Direct URL link to the official job vacancy listing or district portal. |
| `District` | String | Canonical Registry | Canonical public school district name. |
| `Posting_Source` | String | Project Pipeline | Original job feed source (direct district ATS board vs OPI statewide feed). |
| `Posting_Identity_Method` | String | Project Pipeline | Durable identity fingerprint method used (Stable per-posting URL vs Source fallback). |
| `Posting_ID` | String | Project Pipeline | Durable unique posting identifier tracking vacancies across multi-year weekly snapshots. |
| `Category` | String | Classification Model | Fine-grained subject specialization or departmental role assignment. |
| `Broad_Category` | Categorical | Classification Model | Clustered high-level category grouping (Elementary, STEM, Special Education, Humanities, etc.). |

---

### C. K-12 Job Duration Spells (`job_duration_spells.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `District` | String | Canonical Registry | Canonical public school district or employer location name. |
| `NCES_LEAID` | String (7-digit) | NCES CCD | Federal NCES 7-digit Local Education Agency identifier. |
| `Title` | String | District Job Board / OPI | Standardized job vacancy title. |
| `Category` | String | Classification Model | Fine-grained subject area or functional assignment. |
| `Broad_Category` | Categorical | Classification Model | High-level clustered subject or role category. |
| `Position` | Categorical | Classification Model | Broad staff position group (Teacher, Administrator, Support Services). |
| `First_Seen_Date` | Date (YYYY-MM-DD) | Project Scraper | Earliest weekly scraper run in which this job posting was observed active. |
| `Last_Seen_Date` | Date (YYYY-MM-DD) | Project Scraper | Latest weekly scraper run in which this job posting was observed active. |
| `Weeks_Observed` | Integer | Project Derived | Number of distinct calendar weeks (ISO weeks) in which this posting was observed during the spell. A posting absent for more than 21 days that reappears under the same title starts a new spell. |
| `Estimated_Days_Open` | Integer | Project Derived | Estimated calendar duration of the vacancy (proxy for labor shortage / time-to-fill). |
| `Status` | Categorical | Project Derived | State of posting: Closed / Filled or Still Active as of the latest pipeline run. |
| `is_stem` | Binary (0/1) | Shortage Taxonomy | Dummy indicator: 1 if position is Science, Technology, Engineering, or Math; 0 otherwise. |
| `is_sped` | Binary (0/1) | Shortage Taxonomy | Dummy indicator: 1 if position is Special Education; 0 otherwise. |
| `is_elementary` | Binary (0/1) | Shortage Taxonomy | Dummy indicator: 1 if position is Elementary Education; 0 otherwise. |
| `is_secondary` | Binary (0/1) | Shortage Taxonomy | Dummy indicator: 1 if position is Middle or High School; 0 otherwise. |
| `is_admin` | Binary (0/1) | Shortage Taxonomy | Dummy indicator: 1 if position is Administration, Principal, or Superintendent; 0 otherwise. |
| `is_support_staff` | Binary (0/1) | Shortage Taxonomy | Dummy indicator: 1 if position is Classified Support, Paraprofessional, Custodial, Bus, or Food Service; 0 otherwise. |

---

### D. District Profiles & Benchmarks (`salarymap2.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `District` | String | Canonical Registry | Canonical public school district name. |
| `County` | String | US Census Bureau | Primary county in which the district central administrative office is located. |
| `Latitude` | Decimal Degrees | US Census / Geocoding | Geographic latitude coordinate of district central headquarters. |
| `Longitude` | Decimal Degrees | US Census / Geocoding | Geographic longitude coordinate of district central headquarters. |
| `Job_Link` | URL | District Registry | Official employment or applicant tracking portal link for the district. |
| `NCES_LEAID` | String (7-digit) | NCES CCD | Federal NCES 7-digit Local Education Agency identifier. |
| `Teacher_Count` | Integer | MT DLI Compensation Report | Total certified classroom teachers reported in the regional DLI compensation dataset. |
| `Teacher_Salary_10th_Pctile` | Currency ($) | MT DLI Compensation Report | 10th percentile teacher salary published in the Montana DLI Regional Wage Report. |
| `Teacher_Avg_Salary` | Currency ($) | MT DLI Compensation Report | Average annual compensation paid across all employed certified classroom teachers. |
| `Teacher_Salary_90th_Pctile` | Currency ($) | MT DLI Compensation Report | 90th percentile teacher salary published in the Montana DLI Regional Wage Report. |
| `Salary_Year` | String | MT DLI Compensation Report | Data collection school year corresponding to the published DLI wage report. |
| `Salary_Source` | String | State Agency | Publishing authority (Montana Department of Labor & Industry via OPI GEMS). |
| `Teachers_Total_FTE` | Numeric | NCES CCD | Total full-time-equivalent certified classroom teachers employed by the district. |
| `Enrollment` | Integer | NCES CCD | Total pre-K through grade 12 student enrollment count. |
| `CCD_Year` | Integer | NCES CCD | Data collection school year for federal CCD staffing and enrollment counts. |
| `CCD_Source` | String | NCES CCD | Federal source citation for NCES CCD public school district universe data. |
| `Data_Coverage` | Categorical | Project Methodology | Scraper coverage fidelity tier: Full (direct ATS integration) vs Partial (heuristic site scrape). |
| `Median_Household_Income` | Currency ($) | US Census ACS 5-Year | County median annual household income in inflation-adjusted dollars. |
| `Median_Gross_Rent` | Currency ($) | US Census ACS 5-Year | County median monthly gross rent including estimated utilities. |
| `Population` | Integer | US Census ACS 5-Year | Total estimated resident population of the county. |
| `ACS_Year` | Integer | US Census ACS 5-Year | Data release year for US Census American Community Survey 5-year estimates. |
| `Mining_Employment_Share` | Proportion (0-1) | US Census ACS 5-Year | Proportion of county civilian employed labor force in agriculture, forestry, mining, and energy extraction. |
| `Population_Change_Pct` | Proportion | US Census ACS 5-Year | County 5-year percentage change in total resident population. |
| `Child_Poverty_Rate` | Proportion (0-1) | US Census SAIPE | Estimated proportion of school-age children (ages 5-17) living in families below the federal poverty line. |
| `SAIPE_Year` | Integer | US Census SAIPE | Release year of federal Small Area Income and Poverty Estimates data. |
| `Total_General_Fund_Expenditure` | Currency ($) | OPI School Finance Files | Total district General Fund operating expenditures. |
| `Finance_FY` | String / Integer | OPI School Finance Files | State fiscal year for OPI financial expenditure reporting. |
| `Finance_Source` | String | OPI School Finance Files | Publishing state agency authority for Montana Office of Public Instruction annual finance files. |

---

### E. Higher Ed Historical Archive (`facultydata.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Title` | String | Institutional Board | Published higher education job vacancy title as advertised on the college careers portal. |
| `Location` | String | Institutional Board | Campus location, city, or remote work designation. |
| `Posted_Date` | String / Date | Institutional Board | Original date of vacancy posting as published by the college or university. |
| `Institution` | String | IPEDS Directory | Collegiate institution canonical name. |
| `Link` | URL | Institutional Board | Direct web URL to the employment vacancy listing. |
| `Archive_Date` | Date (YYYY-MM-DD) | Project Scraper | Weekly snapshot observation date when the posting was captured open. |
| `Job_Type` | Categorical | Classification Model | Position appointment category (Instructor/Teacher/Faculty, Adjunct/Part-Time Faculty, Other/Staff). |
| `Category` | String | Classification Model | Academic discipline or administrative functional area. |

---

### F. Higher Ed Job Duration Spells (`he_job_duration_spells.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Institution` | String | IPEDS Directory | Collegiate institution canonical name. |
| `IPEDS_UNITID` | String (6-digit) | NCES IPEDS | Official 6-digit federal NCES Integrated Postsecondary Education Data System Unit ID. |
| `Title` | String | Institutional Board | Standardized collegiate job vacancy title. |
| `Category` | String | Classification Model | Academic discipline or functional assignment area. |
| `Job_Type` | Categorical | Classification Model | Collegiate appointment type (Instructor/Teacher/Faculty or Adjunct/Part-Time Faculty). |
| `First_Seen_Date` | Date (YYYY-MM-DD) | Project Scraper | Earliest weekly scraper run in which this job posting was observed active. |
| `Last_Seen_Date` | Date (YYYY-MM-DD) | Project Scraper | Latest weekly scraper run in which this job posting was observed active. |
| `Weeks_Observed` | Integer | Project Derived | Number of distinct calendar weeks (ISO weeks) in which this posting was observed during the spell. A posting absent for more than 21 days that reappears under the same title starts a new spell. |
| `Estimated_Days_Open` | Integer | Project Derived | Estimated calendar duration of the vacancy (proxy for search length and time-to-fill). |
| `Status` | Categorical | Project Derived | State of posting: Closed / Filled or Still Active as of the latest pipeline run. |
| `is_stem` | Binary (0/1) | Shortage Taxonomy | Dummy indicator: 1 if position is Science, Technology, Engineering, or Math; 0 otherwise. |
| `is_health` | Binary (0/1) | Shortage Taxonomy | Dummy indicator: 1 if position is Health Sciences, Nursing, or Medical; 0 otherwise. |
| `is_cte` | Binary (0/1) | Shortage Taxonomy | Dummy indicator: 1 if position is Career & Technical Education or Trades; 0 otherwise. |
| `is_adjunct` | Binary (0/1) | Shortage Taxonomy | Dummy indicator: 1 if position is Part-Time or Adjunct Faculty; 0 otherwise. |
| `is_faculty` | Binary (0/1) | Shortage Taxonomy | Dummy indicator: 1 if position is Full-Time Instructional Faculty; 0 otherwise. |

---

### G. Higher Ed Institutional Profiles (`salarymap.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Name` | String | IPEDS Directory | Official legal institution name of the public college or university. |
| `County` | String | US Census Bureau | County in which the collegiate campus is located. |
| `Longitude` | Decimal Degrees | IPEDS Directory | Geographic longitude coordinate of main campus centroid. |
| `Latitude` | Decimal Degrees | IPEDS Directory | Geographic latitude coordinate of main campus centroid. |
| `Link` | URL | Institutional Directory | Official careers or employment opportunities portal URL for the institution. |
| `IPEDS_UNITID` | String (6-digit) | NCES IPEDS | Official 6-digit federal NCES Integrated Postsecondary Education Data System Unit ID. |
| `Faculty_Avg_Salary` | Currency ($) | NCES IPEDS | Average full-time instructional faculty salary across all academic ranks combined. |
| `Faculty_Avg_Salary_Professor` | Currency ($) | NCES IPEDS | Average full-time instructional faculty salary for the Full Professor rank. |
| `Faculty_Count` | Integer | NCES IPEDS | Total count of full-time instructional faculty employed by the institution. |
| `Salary_Year` | Integer | NCES IPEDS | Academic reporting year for IPEDS faculty compensation data. |
| `Salary_Source` | String | NCES IPEDS | Primary source citation for instructional faculty pay. |
| `Faculty_Avg_Salary_Y1Ago` | Currency ($) | NCES IPEDS | Average full-time instructional faculty salary in the prior academic year (t-1). |
| `Faculty_Avg_Salary_Y2Ago` | Currency ($) | NCES IPEDS | Average full-time instructional faculty salary two academic years prior (t-2). |
| `Enrollment` | Integer | NCES IPEDS | Total unduplicated fall student enrollment count. |
| `Enrollment_Year` | Integer | NCES IPEDS | Academic reporting year for IPEDS fall enrollment figures. |
| `Enrollment_Change_Pct` | Proportion | NCES IPEDS | 5-year percentage change in total fall student enrollment. |
| `Pell_Recipient_Share` | Proportion (0-1) | US Dept of Ed FSA | Share of undergraduate degree-seeking students awarded federal need-based Pell Grants. |
| `Pell_Year` | Integer | US Dept of Ed FSA | Award year for Federal Student Aid (FSA) Pell Grant recipient figures. |
| `Median_Household_Income` | Currency ($) | US Census ACS 5-Year | County median annual household income in inflation-adjusted dollars. |
| `Median_Gross_Rent` | Currency ($) | US Census ACS 5-Year | County median monthly gross rent including estimated utilities. |
| `Population` | Integer | US Census ACS 5-Year | Total estimated resident population of the county. |
| `ACS_Year` | Integer | US Census ACS 5-Year | Data release year for US Census American Community Survey 5-year estimates. |
| `Mining_Employment_Share` | Proportion (0-1) | US Census ACS 5-Year | Proportion of county civilian employed labor force in agriculture, forestry, mining, and energy extraction. |
| `Population_Change_Pct` | Proportion | US Census ACS 5-Year | County 5-year percentage change in total resident population. |

---

### H. K-12 Weekly Vacancy Time Series (`k12_district_weekly_totals.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `District` | String | Canonical Registry | Canonical public school district or employer location name. |
| `Archive_Date` | Date (YYYY-MM-DD) | Project Scraper | Snapshot observation date for that weekly pipeline sweep. |
| `n` | Integer | Project Scraper | Total count of active job postings observed open for that district in that week. |

---

### I. Higher Ed Weekly Vacancy Time Series (`he_institution_weekly_totals.csv`)

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Institution` | String | IPEDS Directory | Canonical public college or university name. |
| `Archive_Date` | Date (YYYY-MM-DD) | Project Scraper | Snapshot observation date for that weekly pipeline sweep. |
| `n` | Integer | Project Scraper | Total count of active job postings observed open for that higher education institution in that week. |

---
