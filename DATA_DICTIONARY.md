# Montana Education Jobs Dashboard — Data Dictionary & Codebook

Comprehensive variable codebook, schema definitions, and methodological provenance for datasets compiled and published by the **Montana Education Jobs Dashboard**.

Each dataset is accessible via the **Data Sources & Open Research Downloads** tab in the interactive web dashboard or by downloading machine-readable CSVs directly from this repository.

---

## 1. Datasets Overview

| Dataset Layer | Primary File | Description | Granularity | Refresh Cadence |
| :--- | :--- | :--- | :--- | :--- |
| **Active K-12 Jobs** | `combinedclean.csv` | All active public school job vacancies currently open across Montana school districts. | Posting level | Weekly |
| **K-12 Job Duration Spells** | `job_duration_spells.csv` | Longitudinal panel tracking vacancy duration (time-to-fill) and shortage dummy flags. | Posting spell | Weekly |
| **District Profiles & Benchmarks** | `salarymap2.csv` | District-level staffing, compensation benchmarks (MT DLI Teacher Compensation), and Census context. | District level | Weekly / Annual |
| **K-12 Weekly Vacancy Time Series** | `k12_district_weekly_totals.csv` | Weekly aggregate open job vacancy counts by school district over time. | District × Week | Weekly |
| **Higher Ed Institutional Profiles** | `salarymap.csv` | College and university profiles: IPEDS instructional faculty salaries, enrollment, and Pell recipient shares. | Institution level | Weekly / Annual |
| **Higher Ed Historical Postings** | `facultydata.csv` | Multi-year longitudinal postings for instructional faculty, adjuncts, and staff. | Posting level | Weekly |
| **Higher Ed Job Duration Spells** | `he_job_duration_spells.csv` | Longitudinal spell panel tracking collegiate faculty search duration (time-to-fill) and discipline flags. | Posting spell | Weekly |
| **Data Dictionary & Codebook** | `data_dictionary.csv` | Machine-readable column definitions, types, and primary source authorities across all files. | Variable level | Static / Maintained |

---

## 2. Universal Identifiers & Structural Crosswalks

To support seamless merges with federal, state, and academic datasets, the following universal identifiers and architectural crosswalks are embedded:

- **`NCES_LEAID`**: Official 7-digit federal National Center for Education Statistics Local Education Agency identifier (e.g., `3003870` for Billings, `3018570` for Missoula, `3000655` for East Helena). Enables 1:1 joining with the **Stanford Educational Data Archive (SEDA)**, **Civil Rights Data Collection (CRDC)**, and **Census F-33 School District Finance Survey**.
- **`IPEDS_UNITID`**: Official 6-digit federal Integrated Postsecondary Education Data System identifier (e.g., `180489` for University of Montana, `180461` for Montana State University). Enables 1:1 linkage with IPEDS, College Scorecard, and federal research datasets.
- **Montana K-12 District Structure**: Montana operates with a dual-district structure where many municipalities maintain separate elementary and high school LEAs (e.g., Billings Elementary and Billings High School) governed under a single unified administration and job board. The dashboard benchmarks aggregate both elementary and secondary CCD and OPI finance records to align with real-world applicant tracking portals.

---

## 3. Data Dictionary: Detailed Variable Definitions

### A. Active K-12 Job Vacancies (`combinedclean.csv`)
*Current active openings, updated weekly.*

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `title` | String | District Job Board / OPI | Job vacancy title as published by the school district or OPI Jobs for Teachers feed. |
| `date_posted` | String / Date | District Job Board / OPI | Original posted date string as published on the district applicant tracking board. |
| `position` | Categorical | Classifier | Broad occupational classification (Teacher, Administration, Support Services, etc.). |
| `location` | String | District Job Board / OPI | Specific school building, school campus, facility, or employer city/location. |
| `url` | URL | District Job Board / OPI | Direct URL link to the official job vacancy listing or online application portal. |
| `posting_id` | String | Project Key | Durable posting fingerprint used to track unique openings longitudinally across weekly scrapers. |
| `District` | String | Canonical Registry | Canonical public school district name (or raw city label for OPI statewide rows). |
| `Category` | String | Classifier | Fine-grained subject specialization or departmental role assignment. |
| `Broad_Category` | Categorical | Classifier | High-level clustered role grouping (Elementary, STEM, Special Education, Humanities, etc.). |
| `Posting_Source` | String | Project Provenance | Original job feed source (e.g., direct district board or OPI Jobs for Teachers feed). |
| `Posting_Identity_Method` | String | Project Provenance | Identity fingerprint method used (Stable per-posting URL vs Source fallback). |

---

### B. K-12 Job Duration & Shortage Spells Panel (`job_duration_spells.csv`)
*Longitudinal spell panel tracking vacancy duration and subject-area shortages. Essential for labor economists and empirical policy analysts.*

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `District` | String | Canonical Registry | Canonical public school district or employer location name. |
| `NCES_LEAID` | String (7-digit) | NCES CCD | Federal NCES 7-digit Local Education Agency identifier. |
| `Title` | String | District Job Board / OPI | Standardized job vacancy title. |
| `Position` | Categorical | Classifier | Broad staff position group (Teacher, Administrator, Support Services). |
| `Category` | String | Classifier | Fine-grained subject area or functional assignment. |
| `Broad_Category` | Categorical | Classifier | High-level clustered subject or role category. |
| `First_Seen_Date` | Date (YYYY-MM-DD) | Project Scraper | Earliest weekly scraper run in which this job posting was observed active. |
| `Last_Seen_Date` | Date (YYYY-MM-DD) | Project Scraper | Latest weekly scraper run in which this job posting was observed active. |
| `Weeks_Observed` | Integer | Project Scraper | Total count of weekly snapshots where this posting was present. |
| `Estimated_Days_Open` | Integer | Derived Metric | Estimated calendar duration of the vacancy (proxy for labor shortage / time-to-fill). |
| `Status` | Categorical | Derived Metric | State of posting: `Closed / Filled` or `Still Active` as of the latest pipeline run. |
| `is_stem` | Binary (0/1) | Taxonomy Indicator | Dummy indicator: 1 if position is Science, Technology, Engineering, or Math; 0 otherwise. |
| `is_sped` | Binary (0/1) | Taxonomy Indicator | Dummy indicator: 1 if position is Special Education; 0 otherwise. |
| `is_elementary` | Binary (0/1) | Taxonomy Indicator | Dummy indicator: 1 if position is Elementary Education; 0 otherwise. |
| `is_secondary` | Binary (0/1) | Taxonomy Indicator | Dummy indicator: 1 if position is Middle or High School; 0 otherwise. |
| `is_admin` | Binary (0/1) | Taxonomy Indicator | Dummy indicator: 1 if position is Administration, Principal, or Superintendent; 0 otherwise. |
| `is_support_staff` | Binary (0/1) | Taxonomy Indicator | Dummy indicator: 1 if position is Classified Support, Paraprofessional, Custodial, Bus, or Food Service; 0 otherwise. |

---

### C. District Profiles & Socioeconomic Context (`salarymap2.csv`)
*District-level profiles combining compensation surveys, federal CCD staffing, and Census economic indicators.*

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `District` | String | Canonical Registry | Canonical public school district name. |
| `NCES_LEAID` | String (7-digit) | NCES CCD | Federal NCES 7-digit Local Education Agency identifier. |
| `County` | String | US Census Bureau | Primary county in which the district central administrative office is located. |
| `Latitude` / `Longitude` | Decimal Degrees | US Census / Geocoding | Geographic coordinates of district central headquarters. |
| `Job_Link` | URL | District Registry | Official employment or applicant tracking portal link for the district. |
| `Teacher_Count` | Integer | MT DLI Compensation Report | Total certified classroom teachers reported in the regional DLI compensation dataset. |
| `Teacher_Salary_10th_Pctile` | Currency ($) | MT DLI Compensation Report | 10th percentile teacher salary published in the Montana DLI Regional Wage Report. |
| `Teacher_Avg_Salary` | Currency ($) | MT DLI Compensation Report | Average annual compensation paid across all employed certified classroom teachers. |
| `Teacher_Salary_90th_Pctile` | Currency ($) | MT DLI Compensation Report | 90th percentile teacher salary published in the Montana DLI Regional Wage Report. |
| `Salary_Year` | String | MT DLI Compensation Report | Data collection school year corresponding to the published DLI wage report. |
| `Salary_Source` | String | State Agency | Publishing authority (Montana Department of Labor & Industry via OPI GEMS). |
| `Teachers_Total_FTE` | Numeric | NCES CCD via Urban Inst | Total full-time-equivalent certified classroom teachers employed by the district. |
| `Enrollment` | Integer | NCES CCD via Urban Inst | Total pre-K through grade 12 student enrollment count. |
| `CCD_Year` | Integer | NCES CCD | Data collection school year for federal CCD staffing and enrollment counts. |
| `Median_Household_Income` | Currency ($) | US Census ACS 5-Year | County median annual household income in inflation-adjusted dollars. |
| `Median_Gross_Rent` | Currency ($) | US Census ACS 5-Year | County median monthly gross rent including estimated utilities. |
| `Population` | Integer | US Census ACS 5-Year | Total estimated resident population of the county. |
| `Mining_Employment_Share` | Proportion (0-1) | US Census ACS 5-Year | Proportion of county civilian employed labor force in agriculture, forestry, mining, and energy extraction. |
| `Population_Change_Pct` | Proportion | US Census ACS 5-Year | County 5-year percentage change in total resident population. |
| `Child_Poverty_Rate` | Proportion (0-1) | US Census SAIPE | Estimated proportion of school-age children (ages 5-17) living in families below the federal poverty line. |
| `SAIPE_Year` | Integer | US Census SAIPE | Release year of federal Small Area Income and Poverty Estimates data. |
| `Total_General_Fund_Expenditure` | Currency ($) | OPI School Finance Files | Total district General Fund operating expenditures. |
| `Finance_FY` | String / Integer | OPI School Finance Files | State fiscal year for OPI financial expenditure reporting. |
| `Data_Coverage` | Categorical | Project Methodology | Scraper coverage fidelity: Full (direct ATS integration) vs Partial (heuristic site scrape). |

---

### D. K-12 Weekly Vacancy Time Series (`k12_district_weekly_totals.csv`)
*Longitudinal weekly vacancy counts by district.*

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `District` | String | Canonical Registry | Canonical public school district or employer location name. |
| `Archive_Date` | Date (YYYY-MM-DD) | Project Scraper | Snapshot observation date for that weekly pipeline sweep. |
| `n` | Integer | Project Scraper | Total count of active job postings observed open for that district in that week. |

---

### E. Higher Education Institutional Profiles (`salarymap.csv`)
*Institutional profiles and compensation benchmarks for Montana colleges and universities.*

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Name` | String | IPEDS Directory | Official legal institution name of the public college or university. |
| `IPEDS_UNITID` | String / Integer | NCES IPEDS | Official 6-digit federal NCES Integrated Postsecondary Education Data System Unit ID. |
| `County` | String | US Census Bureau | County in which the collegiate campus is located. |
| `Latitude` / `Longitude` | Decimal Degrees | IPEDS Directory | Geographic coordinates of campus centroid. |
| `Faculty_Avg_Salary` | Currency ($) | NCES IPEDS via Urban Inst | Average full-time instructional faculty salary on 9/10-month contract equivalent across all academic ranks combined. |
| `Faculty_Avg_Salary_Professor` | Currency ($) | NCES IPEDS via Urban Inst | Average full-time instructional faculty salary for the Full Professor rank. |
| `Faculty_Count` | Integer | NCES IPEDS via Urban Inst | Total count of full-time instructional faculty employed by the institution. |
| `Salary_Year` | String / Integer | NCES IPEDS | Academic reporting year for IPEDS faculty compensation data. |
| `Enrollment` | Integer | NCES IPEDS | Total unduplicated fall student enrollment count. |
| `Pell_Recipient_Share` | Proportion (0-1) | US Dept of Ed FSA | Proportion of enrolled undergraduate students receiving federal need-based Pell Grants. |

---

### F. Higher Education Historical Postings (`facultydata.csv`)
*Longitudinal academic and administrative vacancies across higher education institutions.*

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Title` | String | Institutional Board | Published higher education job vacancy title. |
| `Institution` | String | IPEDS Directory | Collegiate institution name. |
| `Location` | String | Institutional Board | Campus location or city. |
| `Appointment` | Categorical | Classifier | Position appointment category (Faculty/Instructor non-adjunct, Adjunct/Part-Time, Other/Staff). |
| `Category` | String | Classifier | Academic discipline or administrative functional area. |
| `Archive_Date` | Date (YYYY-MM-DD) | Project Scraper | Snapshot observation date when the posting was captured open. |
| `Link` | URL | Institutional Board | Direct web URL to the employment vacancy listing. |

---

### G. Higher Education Job Duration Spells Panel (`he_job_duration_spells.csv`)
*Longitudinal spell panel tracking vacancy duration, search persistence, and academic disciplines across colleges and universities.*

| Column Name | Data Type | Source Authority | Description |
| :--- | :--- | :--- | :--- |
| `Institution` | String | IPEDS Directory | Collegiate institution name. |
| `IPEDS_UNITID` | String (6-digit) | NCES IPEDS | Official 6-digit federal NCES Integrated Postsecondary Education Data System Unit ID. |
| `Title` | String | Institutional Board | Standardized collegiate job vacancy title. |
| `Category` | String | Classifier | Academic discipline or functional assignment area. |
| `Job_Type` | Categorical | Classifier | Collegiate appointment type (Instructor/Teacher/Faculty or Adjunct/Part-Time Faculty). |
| `First_Seen_Date` | Date (YYYY-MM-DD) | Project Scraper | Earliest weekly scraper run in which this job posting was observed active. |
| `Last_Seen_Date` | Date (YYYY-MM-DD) | Project Scraper | Latest weekly scraper run in which this job posting was observed active. |
| `Weeks_Observed` | Integer | Project Scraper | Total count of weekly snapshots where this posting was present. |
| `Estimated_Days_Open` | Integer | Derived Metric | Estimated calendar duration of the vacancy (proxy for search length and time-to-fill). |
| `Status` | Categorical | Derived Metric | State of posting: `Closed / Filled` or `Still Active` as of the latest pipeline run. |
| `is_stem` | Binary (0/1) | Taxonomy Indicator | Dummy indicator: 1 if position is Science, Technology, Engineering, or Math; 0 otherwise. |
| `is_health` | Binary (0/1) | Taxonomy Indicator | Dummy indicator: 1 if position is Health Sciences, Nursing, or Medical; 0 otherwise. |
| `is_cte` | Binary (0/1) | Taxonomy Indicator | Dummy indicator: 1 if position is Career & Technical Education; 0 otherwise. |
| `is_adjunct` | Binary (0/1) | Taxonomy Indicator | Dummy indicator: 1 if appointment is Adjunct or Part-Time Faculty; 0 otherwise. |
| `is_faculty` | Binary (0/1) | Taxonomy Indicator | Dummy indicator: 1 if appointment is Full-Time or Regular Instructional Faculty; 0 otherwise. |

---

## 4. Citation and Attribution

Researchers utilizing these datasets should cite the project as follows:

```bibtex
@misc{bostick_perkins_2026_montana,
  author = {Bostick, Mike and Perkins, Mark},
  title = {Montana Education Jobs Dashboard: Longitudinal Staffing Demand, Compensation, and Socioeconomic Context},
  year = {2026},
  publisher = {GitHub},
  howpublished = {\url{https://github.com/bostickmike/Montana-Education-Jobs-Dashboard}}
}
```
