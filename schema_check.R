# Schema-drift guard for every dataset app.R reads by name.
#
# Ported from the Wyoming Education Jobs Dashboard's schema_check.R --
# check_file_schema() itself is state-agnostic and kept as-is.
# REQUIRED_SCHEMAS below reflects what Montana's pipeline actually produces
# so far -- extended as each new data source gets built, the same way
# Wyoming's own list grew over that project's history.
REQUIRED_SCHEMAS <- list(
  "combinedclean.csv" = c("title", "date_posted", "position", "location", "url", "District"),
  "k12jobanalysis.csv" = c("title", "Archive_Date", "location", "District"),
  "allsum.csv" = c("Broad_Category", "Archive_Date", "District", "sum"),
  "allnow.csv" = c("Broad_Category", "Sum", "District"),
  "k12_district_weekly_totals.csv" = c("District", "Archive_Date", "n"),
  "salarymap2.csv" = c("District", "County", "Latitude", "Longitude", "Job_Link",
                        "Teacher_Count", "Teacher_Salary_10th_Pctile", "Teacher_Avg_Salary",
                        "Teacher_Salary_90th_Pctile", "Salary_Year", "Salary_Source",
                        "Teachers_Total_FTE", "Enrollment", "CCD_Year", "CCD_Source",
                        "Median_Household_Income", "Median_Gross_Rent", "Mining_Employment_Share",
                        "Population_Change_Pct", "ACS_Year", "Child_Poverty_Rate", "SAIPE_Year",
                        "Total_General_Fund_Expenditure", "Finance_FY", "Finance_Source"),
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
                       "Population_Change_Pct", "ACS_Year")
)

REQUIRED_SCHEMAS_XLSX <- list(
  "hedata.xlsx" = c("Title", "Location", "Posted_Date", "Institution", "Link", "Archive_Date")
)

# Pure function: given one file's actual column names, which of the
# required ones (if any) are missing? NULL if the schema is fine, so
# callers can filter with Filter(Negate(is.null), ...) the same way other
# check_*() functions in this repo do.
check_file_schema <- function(file_name, actual_cols, required_cols) {
  missing <- setdiff(required_cols, actual_cols)
  if (length(missing) == 0) return(NULL)
  data.frame(file = file_name, missing_column = missing, stringsAsFactors = FALSE)
}
