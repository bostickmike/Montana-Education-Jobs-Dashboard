# Schema-drift guard for every dataset app.R reads by name.
#
# Ported from the Wyoming Education Jobs Dashboard's schema_check.R --
# check_file_schema() itself is state-agnostic and kept as-is.
# REQUIRED_SCHEMAS below reflects what Montana's pipeline actually produces
# so far -- extended as each new data source gets built, the same way
# Wyoming's own list grew over that project's history. REQUIRED_SCHEMAS
# reflects the columns app.R actually reads by name from each file --
# k12_salary_history.csv is deliberately absent since nothing in app.R
# reads it yet (same as Wyoming's own equivalent file).
# check_file_schema() moved to the edjobs package in phase 2 (2026-11-11); attached here so
# every script that sources this file still has them.
suppressMessages(library(edjobs))

REQUIRED_SCHEMAS <- list(
  # "Posted / listed" fallback (scripts/build_posting_spells.R); optional in
  # app.R, which shows the column as before without it.
  "posting_first_seen.csv" = c("Segment", "Key", "First_Seen", "Left_Censored"),
  "combinedclean.csv" = c("title", "date_posted", "position", "location", "url", "District",
                          "Posting_Source", "Posting_Identity_Method", "Posting_ID", "Also_On_OPI", "Close_Date",
                          "Pay_Min", "Pay_Max", "Pay_Unit", "Pay_Text",
                          "Est_Pay", "Est_Pay_Unit", "Est_Occupation", "Est_Area", "Est_Year"),
  "k12jobanalysis.csv" = c("title", "Archive_Date", "location", "District",
                            "Posting_Source", "Posting_Identity_Method", "Posting_ID"),
  "allsum.csv" = c("Broad_Category", "Archive_Date", "District", "sum"),
  "allnow.csv" = c("Broad_Category", "Sum", "District"),
  "k12_district_weekly_totals.csv" = c("District", "Archive_Date", "n"),
  "salarymap2.csv" = c("District", "County", "Latitude", "Longitude", "Job_Link",
                        "Teacher_Count", "Teacher_Salary_10th_Pctile", "Teacher_Avg_Salary",
                        "Teacher_Salary_90th_Pctile", "Salary_Year", "Salary_Source",
                        "Teachers_Total_FTE", "Enrollment", "CCD_Year", "CCD_Source",
                        "Median_Household_Income", "Median_Gross_Rent", "Mining_Employment_Share",
                        "Population_Change_Pct", "ACS_Year", "Child_Poverty_Rate", "SAIPE_Year",
                        "Total_General_Fund_Expenditure", "Finance_FY", "Finance_Source",
                        "Data_Coverage"),
  "facultydata.csv" = c("Title", "Location", "Institution", "Link", "Archive_Date", "Job_Type", "Category"),
  "allsum_he.csv" = c("Category", "Archive_Date", "Institution", "Job_Type", "sum"),
  "allnow_he.csv" = c("Category", "Job_Type", "Sum", "Institution"),
  "he_institution_weekly_totals.csv" = c("Institution", "Archive_Date", "n"),
  "salarymap.csv" = c("Name", "County", "Longitude", "Latitude", "Link",
                       "Faculty_Avg_Salary", "Faculty_Avg_Salary_Professor", "Faculty_Count",
                       "Salary_Year", "Salary_Source", "Faculty_Avg_Salary_Y1Ago", "Faculty_Avg_Salary_Y2Ago",
                       "Enrollment", "Enrollment_Year",
                       "Enrollment_Change_Pct", "Pell_Recipient_Share", "Pell_Year",
                       "Median_Household_Income", "Median_Gross_Rent", "Mining_Employment_Share",
                       "Population_Change_Pct", "ACS_Year"),
  "data_dictionary.csv" = c("Dataset", "File_Name", "Column_Name", "Data_Type", "Primary_Authority", "Definition"),
  "job_duration_spells.csv" = c("District", "Title", "Category", "Broad_Category", "Position", "First_Seen_Date", "Last_Seen_Date", "Weeks_Observed", "Estimated_Days_Open", "Status"),
  "he_job_duration_spells.csv" = c("Institution", "Title", "Category", "Job_Type", "First_Seen_Date", "Last_Seen_Date", "Weeks_Observed", "Estimated_Days_Open", "Status"),
  "qcew_county_school_pay.csv" = c("County", "Avg_Annual_Pay", "Year"),
  # Reference tables the pipeline reads to build the Est_* columns (kept
  # between runs, refreshed through write_reference_file()).
  "oews_role_wages.csv" = c("Area_Code", "Area_Name", "SOC", "Occupation", "Annual_Median", "Hourly_Median", "Year"),
  "ipeds_staff_salaries.csv" = c("IPEDS_UNITID", "Staff_Category", "Category_Label", "Avg_Salary", "Year"),
  "opi_district_counties.csv" = c("OPI_District", "County"),
  # opi_reconcile.R: every public district -> registry district / OPI-only
  # map entity, and the OPI-only entities' map rows.
  "mt_district_crosswalk.csv" = c("LEAID", "OPI_District", "City", "County", "Latitude", "Longitude",
                                  "Registry_District", "Match_Rule", "Map_Entity", "CCD_Year"),
  "opi_only_districts.csv" = c("District", "County", "Latitude", "Longitude", "Job_Link",
                               "Teachers_Total_FTE", "Enrollment", "Data_Coverage")
)

REQUIRED_SCHEMAS_XLSX <- list(
  "hedata.xlsx" = c("Title", "Location", "Posted_Date", "Institution", "Link", "Archive_Date",
                  "Pay_Min", "Pay_Max", "Pay_Unit", "Pay_Text",
                  "Est_Pay", "Est_Pay_Unit", "Est_Occupation", "Est_Area", "Est_Year")
)

