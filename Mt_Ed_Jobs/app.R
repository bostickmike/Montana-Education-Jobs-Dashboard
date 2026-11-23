library(shiny)
library(bslib)
library(shinyWidgets)
library(tidyverse)
library(DT)
library(data.table)
library(leaflet)
library(plotly)
library(scales)
library(stringr)
library(readxl)
library(shinycssloaders)
# Shared helpers (pay and date text, sparklines, trends, job search, first-seen fill): bostickmike/edjobs at the
# version in ../EDJOBS_VERSION (package phase 6, 2026-11-16). The deploy manifest records it as a GitHub package.
library(edjobs)
FEEDBACK_REPO_DEFAULT <- "bostickmike/Montana-Education-Jobs-Dashboard"

#--------------------------------------------------
# Schema guard -- ported from Wyoming's app.R verbatim (state-agnostic). Any
# dataset actually missing an expected column gets that column backfilled
# with NA so downstream mutate/select references don't hard-crash the whole
# app, and the problem is recorded in DATA_LOAD_ISSUES for a visible
# Home-tab banner instead of a silent blank field or an opaque stack trace.
#--------------------------------------------------
DATA_LOAD_ISSUES <- character(0)
# validate_and_pad_schema() (edjobs) reports a file's missing columns through this.
note_load_issue <- function(msg) DATA_LOAD_ISSUES <<- c(DATA_LOAD_ISSUES, msg)


first_seen_table <- tryCatch(read.csv("posting_first_seen.csv", colClasses = "character", fileEncoding = "UTF-8"),
                             error = function(e) NULL, warning = function(w) NULL)
POSTED_LISTED_NOTE <- paste0(
  "Posted / listed is the date the posting gives. Where the job board gives none, it shows the first week this ",
  "dashboard found the posting (\"First seen\"), or \"On the board since at least\" when the posting was already up ",
  "the first time this dashboard checked that board. ")

# OPI postings dated before the July 1 that began the school year of the run (Archive_Date), from September 1. OPI keeps "Open Until
# Filled" postings up after they're filled; the dashboard can't tell which, so it still counts them and labels them.
OPI_SOURCE <- "OPI Jobs for Teachers (statewide)"
OLD_OPI_LABEL <- " \u00b7 may be filled"
school_year_start <- function(run_date) {
  run_date <- as.Date(run_date)
  yr <- as.integer(format(run_date, "%Y")) - (as.integer(format(run_date, "%m")) < 7)
  as.Date(paste0(yr, "-07-01"))
}
# Only once the school year is under way (runs from September 1): in July and August, spring postings for the
# coming year are the ones most likely still open (about 70% of OPI rows in the 08-25 and 09-15 archives were dated
# before July 1).
is_old_opi_posting <- function(source, date_posted, run_date) {
  posted <- as.Date(as.character(date_posted), format = "%Y-%m-%d")
  run_date <- as.Date(as.character(run_date), format = "%Y-%m-%d")
  start <- school_year_start(run_date)
  under_way <- !is.na(run_date) & run_date >= start + 62  # July 1 + 62 days = September 1
  !is.na(source) & source == OPI_SOURCE & !is.na(posted) & under_way & posted < start
}
old_opi_note <- function(n) {
  if (n == 0) return("")
  paste0(n, " OPI posting", if (n == 1) " is" else "s are", " dated before July 1, before this school year began. ",
         "OPI still lists them, so they count, but OPI's \"Open Until Filled\" postings often stay up after the job ",
         "is filled, so their date is marked \"may be filled\".")
}


# Same for higher-ed staff postings: the institution's IPEDS average for the
# posting's staff category ("IPEDS average for full-time management staff,
# Montana State University").
format_ipeds_estimate <- function(est_pay, est_unit, category, institution, has_posted_pay) {
  format_pay_estimate(est_pay, est_unit, paste0("IPEDS average for full-time ", category, " staff, ", institution),
                      has_posted_pay)
}


# Map pay bands. Each posting is compared in its own unit -- an hourly wage
# is never turned into an annual one -- so day rates, stipends and per-credit
# pay appear only under "All".
PAY_BANDS <- list(
  hour_lt18  = list(unit = "hour", lo = 0,     hi = 18,    label = "under $18/hr"),
  hour_18_25 = list(unit = "hour", lo = 18,    hi = 25,    label = "$18\u201325/hr"),
  hour_25p   = list(unit = "hour", lo = 25,    hi = Inf,   label = "$25+/hr"),
  year_lt50  = list(unit = "year", lo = 0,     hi = 50000, label = "under $50k/yr"),
  year_50_60 = list(unit = "year", lo = 50000, hi = 60000, label = "$50\u201360k/yr"),
  year_60p   = list(unit = "year", lo = 60000, hi = Inf,   label = "$60k+/yr")
)


#--------------------------------------------------
# Load K-12 data
#--------------------------------------------------
combineddata <- read.csv("combinedclean.csv", fileEncoding = "UTF-8")
# An employer's map row can cover several posting names (opi_only_districts.csv
# Posting_Names: "Northern Cheyenne Trib HS / North Cheyenne Trib Elem" are the
# Northern Cheyenne Tribal School). Its postings carry the row's name, so the
# map dot, the Jobs table and "View matching jobs" agree. Display only: the
# data files keep OPI's names.
employer_names <- character(0)
if (file.exists("opi_only_districts.csv")) {
  .oo <- read.csv("opi_only_districts.csv", fileEncoding = "UTF-8", stringsAsFactors = FALSE)
  if ("Posting_Names" %in% names(.oo)) {
    .oo <- .oo[!is.na(.oo$Posting_Names) & nzchar(.oo$Posting_Names), , drop = FALSE]
    .parts <- strsplit(.oo$Posting_Names, " / ", fixed = TRUE)
    employer_names <- setNames(rep(.oo$District, lengths(.parts)), unlist(.parts))
  }
}
relabel_employer <- function(d) ifelse(d %in% names(employer_names), unname(employer_names[d]), d)
combineddata$District <- relabel_employer(combineddata$District)
# Posted-pay columns are optional (absent from files written before the
# pipeline captured pay) -- padded here rather than in validate_and_pad_schema(),
# which would flag their absence as a schema problem on the Home tab.
# The BLS estimate columns (Est_*) are optional the same way.
for (col in c("Feed_District", "Also_On_Feed", "Pay_Min", "Pay_Max", "Pay_Unit", "Pay_Text",
              "Est_Pay", "Est_Pay_Unit", "Est_Occupation", "Est_Area", "Est_Year", "Role_Hint")) {
  if (!col %in% names(combineddata)) combineddata[[col]] <- NA
}
oews_year <- na.omit(combineddata$Est_Year)[1]
combineddata <- combineddata %>%
  validate_and_pad_schema(c("District", "title", "position", "location", "date_posted", "url", "Archive_Date",
                            "Posting_Source", "Posting_Identity_Method", "Posting_ID"),
                          "combinedclean.csv", on_missing = note_load_issue) %>%
  mutate(`Posted Pay` = format_posted_pay(Pay_Min, Pay_Max, Pay_Unit),
         `Typical pay (BLS est.)` = format_bls_estimate(Est_Pay, Est_Pay_Unit, Est_Occupation, Est_Area, !is.na(Pay_Min)),
         # Home page job-type tables: TRUE unless edjobs classify_work_schedule() marks the posting as a substitute,
         # extra duty, part-time, student or temporary job (the same call as the pipeline's
         # k12_jobtype_weekly_totals.csv, so the counts agree).
         .Not_Marked = is.na(classify_work_schedule(title, k12_position = position, role_hint = Role_Hint))) %>%
  select(District, title, position, location, `Posted Pay`, `Typical pay (BLS est.)`, date_posted, url, Archive_Date,
         Posting_Source, Posting_Identity_Method, Posting_ID, Also_On_Feed, Pay_Min, Pay_Max, Pay_Unit, Est_Pay, Est_Pay_Unit,
         .Not_Marked) %>%
  # A direct posting OPI also lists (counted once, from our scrape).
  mutate(Posting_Source = ifelse(Also_On_Feed %in% c(TRUE, "TRUE"), paste0(Posting_Source, " \u00b7 also on OPI"), Posting_Source)) %>%
  distinct(Posting_ID, .keep_all = TRUE) %>%
  mutate(District = str_squish(as.character(District))) %>%
  mutate(.old_opi = is_old_opi_posting(Posting_Source, date_posted, Archive_Date)) %>%
  mutate(date_posted = format_posted_or_listed_date(date_posted)) %>%
  mutate(date_posted = fill_first_seen(date_posted, District, title, url, "K-12", lookup = first_seen_table)) %>%
  # An OPI posting from before this school year (posted before July 1; flagged above, before the date is
  # reformatted) still counts, since OPI still lists it, but many such postings are filled and left up
  # (claude-notes/2026-11-22_opi-spring): say so after its date, so the column sorts as before.
  mutate(date_posted = ifelse(.old_opi, paste0(date_posted, OLD_OPI_LABEL), date_posted)) %>%
  arrange(District, title) %>%
  mutate(url = paste0('<a href="', url, '" target="_blank">', url, '</a>')) %>%
  rename(Title = title, Position = position, Location = location,
         `Posted / listed` = date_posted, Link = url,
         Source = Posting_Source, `Identity method` = Posting_Identity_Method)

# salarymap2.csv covers only this project's directly-scraped districts
# (k12_district_registry.csv), not Montana's full ~398-district universe --
# combineddata above has many more distinct District values (every district
# the OPI statewide fallback feed surfaces), but only the registry's districts
# have a Latitude/Longitude to put on the map. See METHODS.md, "OPI postings:
# when they count".
# BLS QCEW average pay of public school employees by county, all roles (the
# pipeline's qcew_county_school_pay.csv); county context in the map popup.
# Optional: counties BLS withholds, or a missing file, show nothing.
qcew_school_pay <- if (file.exists("qcew_county_school_pay.csv")) {
  read.csv("qcew_county_school_pay.csv", stringsAsFactors = FALSE, colClasses = c(Year = "character"))
} else {
  data.frame(County = character(0), Avg_Annual_Pay = numeric(0), Year = character(0))
}

mapdata2_k12 <- read.csv("salarymap2.csv", fileEncoding = "UTF-8")
# Optional columns (absent before the first run that writes them, 2026-11-09):
# padded here rather than in validate_and_pad_schema(), which would flag their
# absence as a data problem on the Home tab.
# Child_Poverty_Low / _High: Census's approximate 90% range (edjobs 0.27.0, first written by the run after 2026-11-15).
for (col in c("Child_Poverty_Basis", "Free_Reduced_Lunch_Share", "FRL_Year", "Child_Poverty_Low", "Child_Poverty_High",
               "Median_Household_Income_MOE", "Median_Gross_Rent_MOE", "Mining_Employment_Share_MOE")) {
  if (!col %in% names(mapdata2_k12)) mapdata2_k12[[col]] <- NA
}
mapdata2_k12 <- mapdata2_k12 %>%
  validate_and_pad_schema(c("District", "County", "Latitude", "Longitude", "Job_Link",
                             "Teacher_Count", "Teacher_Salary_10th_Pctile", "Teacher_Avg_Salary",
                             "Teacher_Salary_90th_Pctile", "Salary_Year", "Salary_Source",
                             "Teachers_Total_FTE", "Enrollment",
                             "Median_Household_Income", "Median_Gross_Rent", "Mining_Employment_Share",
                             "Population_Change_Pct", "ACS_Year", "Child_Poverty_Rate", "SAIPE_Year",
                             "Total_General_Fund_Expenditure", "Finance_FY", "Finance_Source",
                             "Data_Coverage"),
                           "salarymap2.csv", on_missing = note_load_issue) %>%
  rename(Name = District) %>%
  # CCD_Year is text: other employers' private-school rows carry "2023-24".
  mutate(Finance_FY = as.character(Finance_FY), CCD_Year = as.character(CCD_Year))

# Districts we don't scrape whose postings come from OPI's statewide board
# this week (opi_only_districts.csv, opi_reconcile.R): same context columns
# where a statewide source covers them, Data_Coverage = OPI_ONLY_COVERAGE
# (shown as the popup badge). Optional: absent before the first run that
# writes it.
OPI_ONLY_COVERAGE <- "Postings via OPI's statewide board"
if (file.exists("opi_only_districts.csv")) {
  opi_only_k12 <- read.csv("opi_only_districts.csv", fileEncoding = "UTF-8", stringsAsFactors = FALSE)
  if (nrow(opi_only_k12) > 0) {
    mapdata2_k12 <- bind_rows(
      mapdata2_k12,
      opi_only_k12 %>%
        rename(Name = District) %>%
        mutate(Finance_FY = as.character(Finance_FY), CCD_Year = as.character(CCD_Year), Data_Coverage = OPI_ONLY_COVERAGE) %>%
        select(any_of(names(mapdata2_k12)))
    )
  }
}


# District salary lookup for the Jobs Table
k12_salary_lookup <- mapdata2_k12 %>%
  select(Name, Teacher_Avg_Salary, Teacher_Salary_10th_Pctile, Teacher_Salary_90th_Pctile) %>%
  mutate(
    `District Avg Salary` = ifelse(
      is.na(Teacher_Avg_Salary),
      "—",
      scales::dollar(Teacher_Avg_Salary, accuracy = 1)
    ),
    `Salary Band (10th-90th)` = ifelse(
      is.na(Teacher_Salary_10th_Pctile) | is.na(Teacher_Salary_90th_Pctile),
      "—",
      paste0(scales::dollar(Teacher_Salary_10th_Pctile, accuracy = 1), " – ", scales::dollar(Teacher_Salary_90th_Pctile, accuracy = 1))
    )
  )

combineddata <- combineddata %>%
  # District is the registry district, an OPI-only district (pipeline,
  # opi_reconcile.R) or a non-district employer (no salary row).
  left_join(k12_salary_lookup, by = c("District" = "Name")) %>%
  # MT DLI publishes teacher compensation only, so these columns describe
  # teaching postings and stay blank on paraprofessional, bus driver, coach,
  # etc. rows rather than implying those jobs pay the teacher average.
  mutate(
    .is_teacher_row = Position %in% c("Teacher", "Part-Time Teacher"),
    `Teacher Avg Salary` = ifelse(.is_teacher_row, `District Avg Salary`, "—"),
    `Teacher Salary Band (10th-90th)` = ifelse(.is_teacher_row, `Salary Band (10th-90th)`, "—"),
    # Figure for the map's pay bands: posted pay, else the district teacher
    # average on a teaching posting, else the BLS estimate.
    .fallback_value = ifelse(.is_teacher_row & !is.na(Teacher_Avg_Salary), Teacher_Avg_Salary, Est_Pay),
    .fallback_unit = ifelse(.is_teacher_row & !is.na(Teacher_Avg_Salary), "year", Est_Pay_Unit),
    .Pay_Value = posting_pay_value(Pay_Min, Pay_Max, Pay_Unit, .fallback_value, .fallback_unit)$value,
    .Pay_Unit = posting_pay_value(Pay_Min, Pay_Max, Pay_Unit, .fallback_value, .fallback_unit)$unit
  ) %>%
  select(District, Title, Position, Location, `Posted Pay`, `Typical pay (BLS est.)`, `Teacher Avg Salary`,
         `Teacher Salary Band (10th-90th)`, `Posted / listed`, Link, Source, `Identity method`, Posting_ID,
         .Pay_Value, .Pay_Unit, .Not_Marked)

# Weekly ALL-category posting totals per district/institution -- powers the
# sparkline trend next to each entity's raw count on the Top Hiring tables.
# Twice-weekly runs (2026-11-17): every history file the charts read is rolled up to each ISO week's last run
# (latest_snapshot_per_week()), so a chart has one point a week and "new this week" compares with a week ago.
k12_district_weekly_totals <- read.csv("k12_district_weekly_totals.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("District", "Archive_Date", "n", "n_not_marked"), "k12_district_weekly_totals.csv", on_missing = note_load_issue) %>%
  # An employer whose map row covers several posting names counts once.
  mutate(Archive_Date = as.Date(Archive_Date), District = relabel_employer(District)) %>%
  group_by(District, Archive_Date) %>%
  summarise(n = sum(n), n_not_marked = sum(n_not_marked), .groups = "drop") %>%
  latest_snapshot_per_week()
he_institution_weekly_totals <- read.csv("he_institution_weekly_totals.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("Institution", "Archive_Date", "n", "n_not_marked"), "he_institution_weekly_totals.csv", on_missing = note_load_issue) %>%
  mutate(Archive_Date = as.Date(Archive_Date)) %>%
  latest_snapshot_per_week()
# Per-run totals by job type (edjobs jobtype_run_totals()), for the Home page's job-type sparklines.
read_jobtype_totals <- function(f) {
  read.csv(f, fileEncoding = "UTF-8", stringsAsFactors = FALSE) %>%
    validate_and_pad_schema(c("Job_Type", "Archive_Date", "n", "n_not_marked"), f, on_missing = note_load_issue) %>%
    mutate(Archive_Date = as.Date(Archive_Date)) %>%
    latest_snapshot_per_week()
}
k12_jobtype_weekly_totals <- read_jobtype_totals("k12_jobtype_weekly_totals.csv")
he_jobtype_weekly_totals <- read_jobtype_totals("he_jobtype_weekly_totals.csv")
# Columns the app uses but never shows or exports.
HIDDEN_COLS <- c(".Pay_Value", ".Pay_Unit", ".Map_Name", ".Job_Type", ".Not_Marked")
# The Jobs tables' "Showing:" line when a Home click carried the switch with it.
NOT_MARKED_SHOWING <- "excluding substitutes, coaching and postings marked part-time, student or temporary"
NOT_MARKED_SHOWING_HE <- "excluding adjunct, part-time, student and temporary postings"

data_dictionary <- if (file.exists("data_dictionary.csv")) {
  read.csv("data_dictionary.csv", stringsAsFactors = FALSE)
} else {
  data.frame(Dataset = character(0), File_Name = character(0), Column_Name = character(0),
             Data_Type = character(0), Primary_Authority = character(0), Definition = character(0))
}


job_duration_spells <- if (file.exists("job_duration_spells.csv")) {
  relabel_spell_status(read.csv("job_duration_spells.csv", fileEncoding = "UTF-8", stringsAsFactors = FALSE)) %>%
    mutate(District = relabel_employer(District))
} else {
  data.frame()
}

he_job_duration_spells <- if (file.exists("he_job_duration_spells.csv")) {
  relabel_spell_status(read.csv("he_job_duration_spells.csv", fileEncoding = "UTF-8", stringsAsFactors = FALSE))
} else {
  data.frame()
}


k12sum <- read.csv("allsum.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("Broad_Category", "Archive_Date", "District", "sum"), "allsum.csv", on_missing = note_load_issue) %>%
  mutate(District = relabel_employer(str_squish(as.character(District)))) %>%
  group_by(Broad_Category, Archive_Date, District) %>%
  summarise(sum = sum(sum), .groups = "drop") %>%
  mutate(
         Broad_Category = dplyr::recode(Broad_Category,
                                        "English Language Arts Secondary" = "Engl. LA",
                                        "Secondary Social Studies" = "Soc. St.",
                                        "Special Education - General" = "SpEd - General",
                                        "Special Education - Resource/Life Skills" = "SpEd - Resource/LS",
                                        "CTE - Trades, Ag & Technical" = "CTE - Trades/Ag",
                                        "CTE - Business & Family Sciences" = "CTE - Biz/Family")) %>%
  filter(Broad_Category != "Other")

k12sum$Archive_Date <- as.Date(k12sum$Archive_Date)
k12sum <- latest_snapshot_per_week(k12sum)

# A week with zero postings for a category is simply absent from the source
# aggregation, not an explicit 0 -- geom_line() would silently connect
# through the gap. tidyr::complete() fills every combination with a real 0.
k12sum <- k12sum %>%
  tidyr::complete(Broad_Category, Archive_Date, District, fill = list(sum = 0))


k12nowsum <- read.csv("allnow.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("Broad_Category", "Sum", "District"), "allnow.csv", on_missing = note_load_issue) %>%
  mutate(District = relabel_employer(District)) %>%
  group_by(Broad_Category, District) %>%
  summarise(Sum = sum(Sum), .groups = "drop") %>%
  mutate(Broad_Category = dplyr::recode(Broad_Category,
                                        "English Language Arts Secondary" = "Engl. LA",
                                        "Secondary Social Studies" = "Soc. St.",
                                        "Special Education - General" = "SpEd - General",
                                        "Special Education - Resource/Life Skills" = "SpEd - Resource/LS",
                                        "CTE - Trades, Ag & Technical" = "CTE - Trades/Ag",
                                        "CTE - Business & Family Sciences" = "CTE - Biz/Family"),
         District = str_squish(as.character(District))) %>%
  filter(Broad_Category != "Other")

#--------------------------------------------------
# Load Higher Ed data
#--------------------------------------------------
ccdata <- read_xlsx("hedata.xlsx")
# Optional posted-pay columns, padded the same way as combinedclean.csv's.
for (col in c("Pay_Min", "Pay_Max", "Pay_Unit", "Pay_Text",
              "Est_Pay", "Est_Pay_Unit", "Est_Occupation", "Est_Area", "Est_Year",
              "Campus_Town", "Campus_County", "Campus_Latitude", "Campus_Longitude", "Place_Basis")) {
  if (!col %in% names(ccdata)) ccdata[[col]] <- NA
}
# Typed, so a file written before the placement columns existed still joins.
for (col in c("Campus_Town", "Campus_County", "Place_Basis")) ccdata[[col]] <- as.character(ccdata[[col]])
for (col in c("Campus_Latitude", "Campus_Longitude")) ccdata[[col]] <- as.numeric(ccdata[[col]])
ccdata <- ccdata %>%
  validate_and_pad_schema(c("Institution", "Title", "Location", "Posted_Date", "Link"), "hedata.xlsx", on_missing = note_load_issue) %>%
  mutate(`Posted Pay` = format_posted_pay(Pay_Min, Pay_Max, Pay_Unit),
         `Typical pay (IPEDS est.)` = format_ipeds_estimate(Est_Pay, Est_Pay_Unit, Est_Occupation, Est_Area, !is.na(Pay_Min))) %>%
  select(Institution, Title, Location, `Posted Pay`, `Typical pay (IPEDS est.)`, Posted_Date, Link,
         Pay_Min, Pay_Max, Pay_Unit, Est_Pay, Est_Pay_Unit,
         Campus_Town, Campus_County, Campus_Latitude, Campus_Longitude, Place_Basis) %>%
  arrange(Institution, Title) %>%
  mutate(
    Appointment = classify_he_appointment(Title),
    # Home page job-type tables (as the K-12 .Not_Marked above; he_jobtype_weekly_totals.csv makes the same calls).
    .Job_Type = classify_he_job_type(Title),
    .Not_Marked = is.na(classify_work_schedule(Title, he_job_type = .Job_Type)),
    Posted_Date = format_posted_or_listed_date(Posted_Date),
    Posted_Date = fill_first_seen(Posted_Date, Institution, Title, Link, "HE", lookup = first_seen_table)
  ) %>%
  rename(`Posted / listed` = Posted_Date)
ccdata$Link <- paste0('<a href="', ccdata$Link, '" target="_blank">', ccdata$Link, '</a>')
he_faculty_counts <- summarize_he_faculty_postings(ccdata$Title)

mapdata2_he <- read.csv("salarymap.csv")
# ACS margins of error (edjobs 0.28.0): optional until the first run writes them.
for (col in c("Median_Household_Income_MOE", "Median_Gross_Rent_MOE", "Mining_Employment_Share_MOE")) if (!col %in% names(mapdata2_he)) mapdata2_he[[col]] <- NA_real_
mapdata2_he <- mapdata2_he %>%
  validate_and_pad_schema(c("Name", "Longitude", "Latitude", "Link", "Faculty_Avg_Salary",
                             "Faculty_Avg_Salary_Professor", "Faculty_Count", "Salary_Year",
                             "Salary_Source", "Faculty_Avg_Salary_Y1Ago", "Faculty_Avg_Salary_Y2Ago",
                             "County", "Median_Household_Income", "Median_Gross_Rent",
                             "Mining_Employment_Share", "Population_Change_Pct", "ACS_Year",
                             "Enrollment", "Enrollment_Change_Pct", "Pell_Recipient_Share", "Pell_Year"),
                           "salarymap.csv", on_missing = note_load_issue) %>%
  mutate(Salary_Year = as.character(Salary_Year), Pell_Year = as.character(Pell_Year))

# Institution faculty salary lookup for the Higher Ed Jobs Table
he_salary_lookup <- mapdata2_he %>%
  select(Name, Faculty_Avg_Salary) %>%
  mutate(
    `Avg. Salary, Full-Time Instructional Staff (IPEDS)` = ifelse(
      is.na(Faculty_Avg_Salary),
      "—",
      scales::dollar(Faculty_Avg_Salary, accuracy = 1)
    )
  )

ccdata$.Map_Name <- he_map_name(ccdata$Institution, ccdata$Campus_Town)
he_campus_points <- ccdata %>%
  filter(!is.na(Campus_Town), !is.na(Campus_Latitude), !is.na(Campus_Longitude)) %>%
  distinct(.Map_Name, Institution, Campus_Town, Campus_County, Campus_Latitude, Campus_Longitude)
ccdata$.Map_Name <- ifelse(ccdata$.Map_Name %in% he_campus_points$.Map_Name, ccdata$.Map_Name, ccdata$Institution)
# Postings shown at the main campus because they name no town in the state
# (a department or building, several sites, "United States", another state).
he_unplaced_n <- sum(ccdata$Place_Basis %in% c("no_town", "out_of_state"))
he_place_note <- if (any(!is.na(ccdata$Place_Basis))) paste0(
  "College postings are shown at the town the posting names (a branch campus, outreach center or field office). ",
  format(he_unplaced_n, big.mark = ","), " of ", format(nrow(ccdata), big.mark = ","),
  " current college postings don't name one Montana town (the job board gives a department, a building or no place, ",
  "or the job covers several sites or is out of state) and are shown at the institution's main campus.") else ""

ccdata <- ccdata %>%
  left_join(he_salary_lookup, by = c("Institution" = "Name")) %>%
  # Figure for the map's pay bands: posted pay, else the institution's IPEDS
  # faculty average on a full-time faculty posting, else its IPEDS average
  # for the posting's staff category.
  mutate(
    .faculty_avg = Appointment == "Faculty/instructor (non-adjunct)" & !is.na(Faculty_Avg_Salary),
    .fallback_value = ifelse(.faculty_avg, Faculty_Avg_Salary, Est_Pay),
    .fallback_unit = ifelse(.faculty_avg, "year", Est_Pay_Unit),
    .Pay_Value = posting_pay_value(Pay_Min, Pay_Max, Pay_Unit, .fallback_value, .fallback_unit)$value,
    .Pay_Unit = posting_pay_value(Pay_Min, Pay_Max, Pay_Unit, .fallback_value, .fallback_unit)$unit
  ) %>%
  select(Institution, Title, Location, Appointment, `Posted Pay`, `Typical pay (IPEDS est.)`, `Avg. Salary, Full-Time Instructional Staff (IPEDS)`,
         `Posted / listed`, Link, .Pay_Value, .Pay_Unit, .Map_Name, .Job_Type, .Not_Marked)

hesum_he <- read.csv("allsum_he.csv") %>%
  validate_and_pad_schema(c("Category", "Archive_Date", "Institution", "Job_Type", "sum"), "allsum_he.csv", on_missing = note_load_issue) %>%
  filter(Category != "Uncategorized")

hesum_he$Archive_Date <- as.Date(hesum_he$Archive_Date)
hesum_he <- latest_snapshot_per_week(hesum_he)

hesum_he <- hesum_he %>%
  tidyr::complete(Category, Archive_Date, Institution, Job_Type, fill = list(sum = 0))
he_dates <- sort(unique(hesum_he$Archive_Date))
WINDOW_WEEKS <- 52
hesum_he$Category <- as.factor(hesum_he$Category)

henowsum_he <- read.csv("allnow_he.csv") %>%
  validate_and_pad_schema(c("Category", "Job_Type", "Sum", "Institution"), "allnow_he.csv", on_missing = note_load_issue) %>%
  filter(Category != "Uncategorized")

last_refreshed_date <- format(max(k12sum$Archive_Date, hesum_he$Archive_Date, na.rm = TRUE), "%B %d, %Y")

k12_timeline_value <- bounded_timeline_value(k12sum$Archive_Date)
he_timeline_value <- bounded_timeline_value(hesum_he$Archive_Date, days = WINDOW_WEEKS * 7)

#--------------------------------------------------
# Category collapse maps -- keyed on classify_k12_broad_category()/
# classify_he_faculty_category()'s own output values, the SAME
# state-agnostic classification functions Wyoming's pipeline uses (ported
# unchanged into k12_he_classification.R), so these groupings (and the
# color palettes below) carry over directly rather than needing Montana-
# specific re-derivation.
#--------------------------------------------------
k12_collapse_map <- c(
  "Elementary" = "Elementary & Early Childhood",
  "Early Childhood" = "Elementary & Early Childhood",
  "SpEd - General" = "Special Education",
  "SpEd - Resource/LS" = "Special Education",
  "Math" = "Core Academic",
  "Science" = "Core Academic",
  "Engl. LA" = "Core Academic",
  "Soc. St." = "Core Academic",
  "Language" = "Core Academic",
  "CTE - Trades/Ag" = "CTE",
  "CTE - Biz/Family" = "CTE",
  "Music" = "Arts & Enrichment",
  "Art" = "Arts & Enrichment",
  "Physical Education" = "Arts & Enrichment",
  "Library Media" = "Arts & Enrichment",
  "Gifted and Talented" = "Arts & Enrichment"
)

k12sum_agg <- k12sum %>%
  mutate(Broad_Category = dplyr::recode(Broad_Category, !!!k12_collapse_map)) %>%
  group_by(Broad_Category, Archive_Date, District) %>%
  summarize(sum = sum(sum), .groups = "drop")

k12nowsum_agg <- k12nowsum %>%
  mutate(Broad_Category = dplyr::recode(Broad_Category, !!!k12_collapse_map)) %>%
  group_by(Broad_Category, District) %>%
  summarize(Sum = sum(Sum), .groups = "drop")

he_collapse_map <- c(
  "CTE - Trades & Engineering" = "CTE / Career-Technical",
  "CTE - Health Sciences" = "CTE / Career-Technical",
  "CTE - Business & Computing" = "CTE / Career-Technical",
  "Culinary/Hospitality" = "CTE / Career-Technical",
  "Science" = "STEM",
  "Math" = "STEM",
  "Humanities" = "Humanities & Social Sciences",
  "Social Science" = "Humanities & Social Sciences",
  "History" = "Humanities & Social Sciences",
  "Language" = "Humanities & Social Sciences",
  "Criminal Justice" = "Humanities & Social Sciences",
  "Legal" = "Humanities & Social Sciences",
  "Human Services" = "Humanities & Social Sciences",
  "Education" = "Humanities & Social Sciences",
  "The Arts" = "Arts & Physical Education",
  "Physical Education" = "Arts & Physical Education",
  "Extension/Outreach" = "Extension/Outreach & Library",
  "Library" = "Extension/Outreach & Library"
)

hesum_he_agg <- hesum_he %>%
  mutate(Category = dplyr::recode(as.character(Category), !!!he_collapse_map)) %>%
  group_by(Category, Archive_Date, Institution, Job_Type) %>%
  summarize(sum = sum(sum), .groups = "drop")

henowsum_he_agg <- henowsum_he %>%
  mutate(Category = dplyr::recode(Category, !!!he_collapse_map)) %>%
  group_by(Category, Institution, Job_Type) %>%
  summarize(Sum = sum(Sum), .groups = "drop")

#--------------------------------------------------
# Category colors -- ported verbatim (see collapse-map note above for why
# these apply directly to Montana's data too).
#--------------------------------------------------
EXT_HUES <- c("#8B5E34", "#5C7A99", "#7A7A3D", "#767671", "#2E8B87",
              "#C77DA8", "#B8860B", "#6B5B95", "#4A6670", "#D97757")
BASE8 <- c("#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948")

K12_CATEGORY_COLORS_AGG <- setNames(BASE8[1:5], c(
  "Special Education", "Core Academic", "Elementary & Early Childhood",
  "Arts & Enrichment", "CTE"
))

K12_CATEGORY_COLORS_DETAIL <- setNames(c(BASE8, EXT_HUES[1:8]), c(
  "Elementary", "SpEd - General", "SpEd - Resource/LS", "Music", "Math",
  "Engl. LA", "Science", "CTE - Trades/Ag", "Language", "CTE - Biz/Family",
  "Soc. St.", "Physical Education", "Early Childhood", "Art", "Library Media",
  "Gifted and Talented"
))

HE_CATEGORY_COLORS_AGG <- setNames(BASE8[1:5], c(
  "CTE / Career-Technical", "Humanities & Social Sciences", "STEM",
  "Arts & Physical Education", "Extension/Outreach & Library"
))

HE_CATEGORY_COLORS_DETAIL <- setNames(c(BASE8, EXT_HUES), c(
  "CTE - Trades & Engineering", "Science", "CTE - Health Sciences", "CTE - Business & Computing",
  "The Arts", "Humanities", "Social Science", "Extension/Outreach", "Math",
  "History", "Education", "Culinary/Hospitality", "Physical Education",
  "Library", "Language", "Criminal Justice", "Legal", "Human Services"
))

HE_JOB_TYPE_COLORS <- c(
  "Faculty/instructor (non-adjunct)" = "#2a78d6",
  "Adjunct/Part-Time"  = "#eb6834"
)

#--------------------------------------------------
# "New this week" -- row-level history, diffed against the previous
# archived run.
#--------------------------------------------------
k12_history <- read.csv("k12jobanalysis.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("title", "Archive_Date", "location", "District", "Posting_ID"),
                          "k12jobanalysis.csv", on_missing = note_load_issue) %>%
  mutate(Archive_Date = as.Date(Archive_Date), District = relabel_employer(District)) %>%
  latest_snapshot_per_week()

k12_new_this_week <- find_k12_new_postings(k12_history)

he_history <- read.csv("facultydata.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("Title", "Location", "Institution", "Link", "Archive_Date", "Job_Type", "Category"), "facultydata.csv", on_missing = note_load_issue) %>%
  mutate(Archive_Date = as.Date(Archive_Date)) %>%
  latest_snapshot_per_week() %>%
  filter(Job_Type %in% c("Instructor/Teacher/Faculty", "Adjunct/Part-Time Faculty")) %>%
  mutate(Appointment = dplyr::recode(
    Job_Type,
    "Instructor/Teacher/Faculty" = "Faculty/instructor (non-adjunct)",
    "Adjunct/Part-Time Faculty" = "Adjunct/part-time faculty"
  ))

he_new_this_week <- {
  dates <- sort(unique(he_history$Archive_Date))
  if (length(dates) >= 2) {
    latest <- dates[length(dates)]
    previous <- dates[length(dates) - 1]
    he_history %>%
      filter(Archive_Date == latest) %>%
      anti_join(he_history %>% filter(Archive_Date == previous), by = c("Title", "Location", "Institution"))
  } else {
    he_history[0, ]
  }
}

#--------------------------------------------------
# Combined map dataset -- one row per K-12 district or HE institution
# registered in this project's registries, merging each entity's
# location/salary reference data with a live current-openings count.
# Unlike Wyoming, there's no Data_Coverage "Partial" tier here (every
# registered entity is scraped from a real structured platform) and no
# merged-entity vacancy-rate case (each Montana HE institution has its own
# independent IPEDS unitid) -- both of those pieces of Wyoming's app.R are
# simply absent below rather than adapted.
#--------------------------------------------------
k12_current_counts <- combineddata %>% count(District, name = "CurrentCount")
k12_sample_titles <- combineddata %>%
  group_by(District) %>%
  summarize(SampleTitles = paste(head(Title, 3), collapse = "; "), .groups = "drop")
k12_weekly_new <- k12_new_this_week %>% count(District, name = "WeeklyNew")

# Vacancy rate needs a minimum FTE to be a meaningful comparison. Since
# staffing comes from the crosswalk for every district (2026-11-09), 34 small
# districts (under 10 FTE) show no rate, and a district with 10-20 FTE can show
# a high one from a handful of postings (Frazer: 10 of 15).
VACANCY_RATE_MIN_FTE <- 10

DLI_SALARY_SOURCE_URL <- "https://lmi.mt.gov/Publications/index"
IPEDS_SALARY_SOURCE_URL <- "https://educationdata.urban.org"

# The Districts tab's pay and budget columns, their map popup lines, the compare plot's bars and the footnote's
# state paragraphs (edjobs district_spec(), step 7 slice 3 part 3, 2026-11-21).
# Teacher_Avg_Salary and its 10th/90th percentile band (MT DLI Teacher Compensation Report), not a base salary plus
# prior year: see METHODS.md, "Pay", for why this is a different metric.
DISTRICT_SPEC <- district_spec(
  columns = list(
    district_column("Teacher Avg Salary (%s)", value = "Teacher_Avg_Salary", year_col = "Salary_Year",
                    year_fallback = "current year", card = "Teacher Avg Salary:"),
    district_column("Teacher Salary Range (10th-90th %ile)", range = c("Teacher_Salary_10th_Pctile", "Teacher_Salary_90th_Pctile"),
                    card = "Salary Band (10th-90th):"),
    district_column("Annual General Fund Budget (FY%s)", value = "Total_General_Fund_Expenditure", year_col = "Finance_FY",
                    year_fallback = "current fiscal year", card = "General Fund Budget:", card_section = "budget")
  ),
  popup_lines = list(
    district_popup_line("Teacher avg salary", "Teacher_Avg_Salary",
                        range = c("Teacher_Salary_10th_Pctile", "Teacher_Salary_90th_Pctile"), year_col = "Salary_Year")
  ),
  compare_bars = c("Teacher Avg Salary (MT DLI)" = "Teacher_Avg_Salary",
                   "County Median Household Income" = "Median_Household_Income"),
  compare_y_title = "Annual Compensation ($)",
  source_notes = list(
    district_source_note("Salary data:", "Salary_Source", year_col = "Salary_Year", url = DLI_SALARY_SOURCE_URL,
                         url_text = "lmi.mt.gov",
                         after = ". Average salary and 10th/90th percentile pay range (reflecting starting to senior teacher pay) — not a contract base salary."),
    district_source_note("General Fund expenditure:", "Finance_Source", year_col = "Finance_FY", year_format = "(FY%s).",
                         after = "This is total day-to-day operating spending, not per-pupil or per-teacher spending.")
  ),
  saipe_scope_note = ". District-level. For districts split between an elementary and a high-school district, this pools the two: children 5-17 in poverty summed over both districts, divided by their children 5-17 summed.",
  saipe_standin_note = "A private or tribal school has no Census poverty estimate of its own; it shows its surrounding district's estimate (marked \"Surrounding district\").",
  other_employers_note = helpText(
    "Employers that aren't public school districts are on the map too: special-education cooperatives and a",
    "hospital school (NCES Common Core of Data), the Northern Cheyenne Tribal School (CCD's Bureau of Indian",
    "Education schools) and private schools, whose teacher and student counts come from the NCES Private School",
    "Universe Survey, 2023-24 -- the newest edition, older than the public-district figures. No public source",
    "reports their teacher pay or budgets, so those stay blank.",
    tags$a(href = "https://nces.ed.gov/surveys/pss/", target = "_blank", "nces.ed.gov/surveys/pss")
  ),
  page_length = 18
)

k12_teacher_current_counts <- k12_history %>%
  filter(Archive_Date == max(Archive_Date)) %>%
  group_by(District) %>%
  summarize(TeacherCurrentCount = n_distinct(Posting_ID), .groups = "drop")

map_k12 <- mapdata2_k12 %>%
  left_join(k12_current_counts, by = c("Name" = "District")) %>%
  left_join(k12_sample_titles, by = c("Name" = "District")) %>%
  left_join(k12_weekly_new, by = c("Name" = "District")) %>%
  left_join(k12_teacher_current_counts, by = c("Name" = "District")) %>%
  mutate(
    CurrentCount = coalesce(CurrentCount, 0L),
    WeeklyNew = coalesce(WeeklyNew, 0L),
    SampleTitles = coalesce(SampleTitles, ""),
    Type = "K-12 District",
    FRL_Year = as.character(FRL_Year),  # read back as a number; HE rows carry text NA
    TeacherCurrentCount = coalesce(TeacherCurrentCount, 0L),
    Vacancy_Rate = ifelse(!is.na(Teachers_Total_FTE) & Teachers_Total_FTE >= VACANCY_RATE_MIN_FTE,
                           TeacherCurrentCount / Teachers_Total_FTE, NA_real_),
    Vacancy_Numerator = TeacherCurrentCount, Vacancy_Denominator = Teachers_Total_FTE,
    Faculty_Avg_Salary = NA_real_, Faculty_Avg_Salary_Professor = NA_real_, Faculty_Count = NA_real_,
    Faculty_Avg_Salary_Y1Ago = NA_real_, Faculty_Avg_Salary_Y2Ago = NA_real_,
    Students_Per_Teacher = ifelse(!is.na(Teachers_Total_FTE) & Teachers_Total_FTE > 0,
                                   Enrollment / Teachers_Total_FTE, NA_real_),
    Enrollment_Change_Pct = NA_real_,
    Pell_Recipient_Share = NA_real_, Pell_Year = NA_character_
  ) %>%
  select(Name, Longitude, Latitude, Type, CurrentCount, WeeklyNew, SampleTitles,
         Link = Job_Link, Teacher_Count, Teacher_Salary_10th_Pctile, Teacher_Avg_Salary,
         Teacher_Salary_90th_Pctile, Salary_Year,
         Faculty_Avg_Salary, Faculty_Avg_Salary_Professor, Faculty_Count,
         Faculty_Avg_Salary_Y1Ago, Faculty_Avg_Salary_Y2Ago,
         Vacancy_Rate, Vacancy_Numerator, Vacancy_Denominator, Salary_Source, County,
         Enrollment, Students_Per_Teacher, Enrollment_Change_Pct, Pell_Recipient_Share, Pell_Year,
         Median_Household_Income, Median_Gross_Rent, Mining_Employment_Share, Population_Change_Pct, ACS_Year,
         Median_Household_Income_MOE, Median_Gross_Rent_MOE, Mining_Employment_Share_MOE,
         Child_Poverty_Rate, Child_Poverty_Low, Child_Poverty_High, SAIPE_Year, Child_Poverty_Basis, Free_Reduced_Lunch_Share, FRL_Year, Total_General_Fund_Expenditure, Finance_FY, Finance_Source,
         Data_Coverage)

he_current_counts <- ccdata %>% count(Institution = .Map_Name, name = "CurrentCount")
he_sample_titles <- ccdata %>%
  group_by(Institution = .Map_Name) %>%
  summarize(SampleTitles = paste(head(Title, 3), collapse = "; "), .groups = "drop")
# New-this-week postings counted on the dot their current posting is on.
he_weekly_new <- he_new_this_week %>%
  left_join(ccdata %>% distinct(Institution, Title, Location, .Map_Name) %>%
              distinct(Institution, Title, Location, .keep_all = TRUE),
            by = c("Institution", "Title", "Location")) %>%
  count(Institution = coalesce(.Map_Name, Institution), name = "WeeklyNew")

# Scoped to full-time faculty only, matching Faculty_Count's own scope --
# IPEDS's salaries-instructional-staff survey (the source of Faculty_Count)
# only covers full-time instructional staff, so mixing Adjunct/Part-Time
# postings into this numerator would overstate the rate by comparing "all
# open faculty postings" against a full-time-only denominator. he_history
# itself now includes both Job_Types (added for the FT/PT appointment
# toggles elsewhere), so this consumer filters back down explicitly rather
# than assuming the shared object's scope.
he_faculty_current_counts <- he_history %>%
  filter(Archive_Date == max(Archive_Date), Job_Type == "Instructor/Teacher/Faculty") %>%
  count(Institution, name = "FacultyCurrentCount")

map_he <- mapdata2_he %>%
  left_join(he_current_counts, by = c("Name" = "Institution")) %>%
  left_join(he_sample_titles, by = c("Name" = "Institution")) %>%
  left_join(he_weekly_new, by = c("Name" = "Institution")) %>%
  left_join(he_faculty_current_counts, by = c("Name" = "Institution")) %>%
  mutate(
    CurrentCount = coalesce(CurrentCount, 0L),
    WeeklyNew = coalesce(WeeklyNew, 0L),
    SampleTitles = coalesce(SampleTitles, ""),
    Type = "Higher Ed Institution",
    FacultyCurrentCount = coalesce(FacultyCurrentCount, 0L),
    Vacancy_Numerator = FacultyCurrentCount,
    Vacancy_Rate = ifelse(!is.na(Faculty_Count) & Faculty_Count >= VACANCY_RATE_MIN_FTE,
                           Vacancy_Numerator / Faculty_Count, NA_real_),
    Vacancy_Denominator = Faculty_Count,
    Teacher_Count = NA_real_, Teacher_Salary_10th_Pctile = NA_real_,
    Teacher_Avg_Salary = NA_real_, Teacher_Salary_90th_Pctile = NA_real_,
    Students_Per_Teacher = ifelse(!is.na(Faculty_Count) & Faculty_Count > 0,
                                   Enrollment / Faculty_Count, NA_real_),
    Child_Poverty_Rate = NA_real_, Child_Poverty_Low = NA_real_, Child_Poverty_High = NA_real_, SAIPE_Year = NA_integer_,
    Child_Poverty_Basis = NA_character_, Free_Reduced_Lunch_Share = NA_real_, FRL_Year = NA_character_,
    Total_General_Fund_Expenditure = NA_real_, Finance_FY = NA_character_,
    Finance_Source = NA_character_,
    # Unlike Wyoming (where every HE institution is on a genuine structured
    # platform, so it hardcodes Data_Coverage = "Full" for HE), Montana has
    # real heuristic HE scrapers too (misc_college_scrapers.R -- Miles CC,
    # Dawson CC, Carroll, Rocky Mountain, SKC, LBHC, FPCC, Aaniiih Nakoda
    # College, Chief Dull Knife, plus Stone Child via Apptegy) -- hardcoding
    # "Full" here would misrepresent about 10 of 23 institutions.
    # Left NA rather than guessing a tier for HE that hasn't actually been
    # designed yet; the map-popup badge below only renders for a real
    # non-NA, non-"Full" value, so an NA institution just shows no badge
    # (same as "nothing to say" everywhere else in this app), not a bug.
    Data_Coverage = NA_character_
  ) %>%
  select(Name, Longitude, Latitude, Type, CurrentCount, WeeklyNew, SampleTitles,
         Link, Teacher_Count, Teacher_Salary_10th_Pctile, Teacher_Avg_Salary,
         Teacher_Salary_90th_Pctile, Salary_Year,
         Faculty_Avg_Salary, Faculty_Avg_Salary_Professor, Faculty_Count,
         Faculty_Avg_Salary_Y1Ago, Faculty_Avg_Salary_Y2Ago,
         Vacancy_Rate, Vacancy_Numerator, Vacancy_Denominator, Salary_Source, County,
         Enrollment, Students_Per_Teacher, Enrollment_Change_Pct, Pell_Recipient_Share, Pell_Year,
         Median_Household_Income, Median_Gross_Rent, Mining_Employment_Share, Population_Change_Pct, ACS_Year,
         Median_Household_Income_MOE, Median_Gross_Rent_MOE, Mining_Employment_Share_MOE,
         Child_Poverty_Rate, Child_Poverty_Low, Child_Poverty_High, SAIPE_Year, Child_Poverty_Basis, Free_Reduced_Lunch_Share, FRL_Year, Total_General_Fund_Expenditure, Finance_FY, Finance_Source)

# One dot per branch campus or site with current postings: its own count,
# new-this-week and sample titles, its town's county context (the ACS figures
# a district in that county shows), and no institution-wide figures (salary,
# vacancy rate, enrollment), which stay on the main campus dot.
he_county_context <- bind_rows(map_k12, map_he) %>%
  filter(!is.na(County), !is.na(Median_Household_Income)) %>%
  distinct(County, .keep_all = TRUE) %>%
  select(County, Median_Household_Income, Median_Gross_Rent, Mining_Employment_Share, Population_Change_Pct, ACS_Year,
         Median_Household_Income_MOE, Median_Gross_Rent_MOE, Mining_Employment_Share_MOE)
map_he_campus <- he_campus_points %>%
  transmute(Name = .Map_Name, Campus_Of = Institution, Longitude = Campus_Longitude, Latitude = Campus_Latitude,
            County = Campus_County, Link = mapdata2_he$Link[match(Institution, mapdata2_he$Name)]) %>%
  left_join(he_current_counts, by = c("Name" = "Institution")) %>%
  left_join(he_sample_titles, by = c("Name" = "Institution")) %>%
  left_join(he_weekly_new, by = c("Name" = "Institution")) %>%
  left_join(he_county_context, by = "County") %>%
  mutate(CurrentCount = coalesce(CurrentCount, 0L), WeeklyNew = coalesce(WeeklyNew, 0L),
         SampleTitles = coalesce(SampleTitles, ""), Type = "Higher Ed Institution", Data_Coverage = NA_character_,
         Campus_Note = paste0("A campus or site of ", Campus_Of, ". Its salary, vacancy and enrollment figures are on the ",
                              Campus_Of, " dot."))
he_other_site_counts <- map_he_campus %>% group_by(Campus_Of) %>% summarize(n = sum(CurrentCount), .groups = "drop")
map_he <- map_he %>%
  mutate(Campus_Of = NA_character_,
         Campus_Note = {
           n <- he_other_site_counts$n[match(Name, he_other_site_counts$Campus_Of)]
           ifelse(!is.na(n) & n > 0, paste0("Plus ", n, " opening", ifelse(n == 1, "", "s"),
                                            " at other campuses or sites (their own dots)."), NA_character_)
         }) %>%
  bind_rows(map_he_campus)

combined_map_data <- bind_rows(map_k12, map_he)

map_county_choices <- c("All Counties" = "all", setNames(
  sort(unique(na.omit(combined_map_data$County))),
  sub(", Montana$", "", sort(unique(na.omit(combined_map_data$County))))
))


vacancy_rate_domain <- compute_vacancy_rate_domain(combined_map_data$Vacancy_Rate)
vacancy_rate_palette <- colorNumeric(palette = "YlOrRd", domain = vacancy_rate_domain, na.color = "#9e9e9e")

#--------------------------------------------------
# UI (bslib / Bootstrap 5)
#--------------------------------------------------
# The navbar's id stays "sidebar_tabs" and each page's value is the old
# shinydashboard tabName, so the map's "View N matching jobs" link
# (nav_select) and the boot smoke test's set_inputs(sidebar_tabs = ...) keep
# working unchanged.
app_theme <- bs_theme(
  version = 5,
  preset = "shiny",
  primary = "#2a78d6",
  base_font = font_collection(font_google("Inter", local = FALSE), "system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"),
  "font-size-base" = "0.925rem"
)


# Sources and required notices, shown at the foot of every page. The Census
# Data API terms require their notice "prominently within the application"
# (census.gov/data/developers/about/terms-of-service.html, revised
# 2026-04-14); the BLS API terms require theirs ("Users must clearly state",
# bls.gov/developers/termsOfService.htm, modified 2023-08-30); Urban's
# Education Data Portal data are under ODC-By, cited in its short form for
# visualizations (educationdata.urban.org/documentation/). Audit:
# claude-notes/2026-11-15_citations-audit.md.
# When each outside source was last retrieved (source_retrieved_dates.csv, written by the pipeline only when a fetch
# succeeds and its data is kept; hand-kept files carry the date they were added). BLS asks for the access date
# (Mike, 2026-11-16: give one for every source). Missing file or source: the line shows no date.
source_dates <- tryCatch(read.csv("source_retrieved_dates.csv", stringsAsFactors = FALSE, colClasses = "character"),
                         error = function(e) data.frame(Source = character(0), Retrieved = character(0)))

data_sources_footer <- tags$footer(
  class = "data-sources-footer",
  tags$p(tags$strong("Data sources."), "Job postings: each employer's own job board (every posting links to it) and the Office of Public Instruction's Montana job board."),
  tags$p(
    paste0("U.S. Census Bureau: American Community Survey 5-Year Estimates", footer_retrieved("Census ACS", source_dates),
           "; Small Area Income and Poverty Estimates", footer_retrieved("Census SAIPE", source_dates),
           "; Census Geocoder", footer_retrieved("Census Geocoder", source_dates), "."),
    paste0("U.S. Bureau of Labor Statistics, Occupational Employment and Wage Statistics", footer_retrieved("BLS OEWS", source_dates),
           " and Quarterly Census of Employment and Wages", footer_retrieved("BLS QCEW", source_dates), "."),
    HTML(paste0("NCES Common Core of Data", footer_retrieved("Urban CCD", source_dates), ", IPEDS", footer_retrieved("Urban IPEDS", source_dates),
                " and Federal Student Aid Title IV data", footer_retrieved("Urban FSA", source_dates), ", via Education Data Portal, Urban Institute, ",
                "under <a href=\"https://opendatacommons.org/licenses/by/1-0/\" target=\"_blank\" rel=\"noopener\">ODC Attribution License</a>."))
  ),
  tags$p(paste0("NCES Private School Universe Survey, 2023-24", footer_retrieved("NCES PSS", source_dates), ".")),
  tags$p(paste0("Montana Department of Labor & Industry, Labor Market Information, teacher pay from OPI's GEMS data", footer_retrieved("MT DLI", source_dates),
                "; Office of Public Instruction, school finance data files", footer_retrieved("OPI finance", source_dates), ".")),
  tags$p(
    "This product uses the Census Bureau Data API but is not endorsed or certified by the Census Bureau.",
    "BLS.gov cannot vouch for the data or analyses derived from these data after the data have been retrieved from BLS.gov."
  )
)

ui <- page_navbar(
  id = "sidebar_tabs",
  title = tags$span(icon("graduation-cap"), " Montana Education Jobs"),
  window_title = "Montana Education Jobs",
  theme = app_theme,
  fillable = FALSE,
  footer = data_sources_footer,
  navbar_options = navbar_options(theme = "dark", bg = "#1e293b"),
  header = tags$head(
    tags$style(HTML("
    .bslib-page-navbar > .navbar .navbar-brand { font-weight: 600; font-size: 1.1rem; }
    .navbar .dropdown-header { font-size: 11px; letter-spacing: 0.08em; text-transform: uppercase; }
    h1.page-title { font-size: 1.6rem; font-weight: 600; margin: 4px 0 14px; }
    h3.page-title { font-size: 1.3rem; font-weight: 600; margin: 4px 0 8px; }
    .card { margin-bottom: 1rem; }
    .data-sources-footer { border-top: 1px solid var(--bs-border-color); margin: 24px 0 0; padding: 12px 16px 16px; font-size: 0.78rem; color: var(--bs-secondary-color); }
    .data-sources-footer p { margin: 0 0 4px; }
    .bslib-value-box .value-box-title { font-size: 0.85rem; }
    .bslib-value-box .value-box-showcase svg { max-width: 100%; height: auto; }
    .download-tile { border: 1px solid var(--bs-border-color); border-radius: 8px; padding: 14px;
                     height: 100%; display: flex; flex-direction: column; background: var(--bs-tertiary-bg); }
    .download-tile h4 { font-size: 15px; font-weight: 600; margin-top: 0; }
    .download-tile p { font-size: 12px; color: var(--bs-secondary-color); flex-grow: 1; }
    .leaflet-tooltip {
      max-width: min(800px, 92vw) !important;
      min-width: min(320px, 85vw) !important;
      white-space: normal !important;
      background-color: rgba(255,255,255,0.95);
      padding: 6px 10px;
      border-radius: 6px;
      border: 1px solid gray;
      font-size: 14px;
      display: inline-block;
      box-sizing: border-box;
    }
    @media (max-width: 767px) {
      .leaflet-container { height: 480px !important; }
    }
    /* Table toolbar styling */
    .table-toolbar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 10px;
      margin-bottom: 12px;
      background: #f8fafc;
      padding: 10px 14px;
      border-radius: 6px;
      border: 1px solid #e2e8f0;
    }
    .table-toolbar .form-group { margin-bottom: 0; }
    /* Clean table styling so tables do not overfill space */
    .trends-table-container {
      width: 100%;
      overflow-x: auto;
      margin-top: 10px;
    }
    .trends-table-container table {
      width: 100% !important;
      max-width: 980px !important;
      margin: 0 auto;
      border-collapse: separate;
      border-spacing: 0;
      border-radius: 6px;
      overflow: hidden;
      border: 1px solid #e2e8f0;
      background: #ffffff;
      font-size: 13.5px;
    }
    .trends-table-container th {
      background-color: #f8fafc !important;
      color: #334155;
      font-weight: 600;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      padding: 10px 14px !important;
      border-bottom: 2px solid #e2e8f0 !important;
    }
    .trends-table-container td {
      padding: 8px 14px !important;
      border-bottom: 1px solid #f1f5f9;
      color: #1e293b;
      vertical-align: middle !important;
    }
    .trends-table-container tr:last-child td { border-bottom: none; }
    .trends-table-container tr:hover td { background-color: #f8fafc; }
    /* Light DT export buttons instead of BS5 btn-secondary blocks */
    .dt-buttons .btn {
      background: transparent !important; color: var(--bs-body-color) !important;
      border: 1px solid var(--bs-border-color) !important;
      padding: 0.2rem 0.75rem !important; font-size: 0.8rem !important;
    }
    .dt-buttons .btn:hover { background: var(--bs-tertiary-bg) !important; }
    #map_filter_count .badge { white-space: normal; text-align: left; line-height: 1.4; }
    .info-pop { font-size: 0.85rem; font-weight: 500; text-decoration: none; white-space: nowrap; }
    .info-popover { --bs-popover-max-width: 420px; font-size: 0.85rem; }
    .help-popover .popover-body { max-height: 60vh; overflow-y: auto; }
    .help-pop { color: var(--bs-secondary-color); font-size: 0.95rem; text-decoration: none; }
    .help-pop:hover, .help-pop:focus { color: var(--bs-primary); }
    .help-columns dt { font-weight: 600; margin-top: 4px; }
    .help-columns dd { margin: 0 0 2px; }
    .map-chips { margin-top: -8px; font-size: 12px; color: #64748b; line-height: 1.9; }
    .map-chips a { margin-right: 8px; font-weight: 500; }
    .bslib-sidebar-layout > .sidebar .form-group { margin-bottom: 0.75rem; }
    .page-sidebar { border: none; --_sidebar-bg: transparent; }
    /* On a phone the collapsed sidebar is just a chevron; name it. */
    @media (max-width: 575.98px) {
      .bslib-sidebar-layout.sidebar-collapsed > .collapse-toggle { width: auto; padding: 4px 10px; border: 1px solid var(--bs-border-color); border-radius: 6px; }
      .bslib-sidebar-layout.sidebar-collapsed > .collapse-toggle::after { content: 'Filters'; margin-left: 6px; font-size: 0.9rem; }
      /* Home job-type tables: drop Share on a phone so the 12-week sparkline fits without scrolling. */
      #top_k12_job_types th:nth-child(3), #top_k12_job_types td:nth-child(3),
      #top_he_job_types th:nth-child(3), #top_he_job_types td:nth-child(3) { display: none; }
    }
  ")),
    # A DT table rendered while its page or tab was hidden measures its columns
    # at zero width; re-measure whenever a page or tab is shown.
    tags$script(HTML("
    $(document).on('shown.bs.tab', function() {
      if ($.fn.dataTable) $.fn.dataTable.tables({ visible: true, api: true }).columns.adjust();
      // On a phone, close the collapsed navbar menu once a page is picked.
      var menu = document.querySelector('.navbar-collapse.show');
      if (menu && window.bootstrap) bootstrap.Collapse.getOrCreateInstance(menu).hide();
    });
  "))
  ),

  # ------------------ Global Introduction ------------------
  # Home tab: edjobs's home_tab_panel() (step 7 slice 2b), with Montana's K-12 coverage card.
  home_tab_panel("Montana", "each district's own job board, read twice a week, and the Office of Public Instruction's Montana job board.",
    last_refreshed_date, "Created by Mike Bostick",
    extra = dash_card(
      "Montana K-12 coverage", class = "border-warning",
      tags$p(
        "The K-12 Jobs Table combines postings from ", sum(map_k12$Data_Coverage != OPI_ONLY_COVERAGE, na.rm = TRUE),
        " directly tracked district boards with Montana OPI's statewide Jobs for Teachers feed. ",
        "A job on both counts once: an OPI posting is checked, posting by posting, against the district's own board, and one that is the same opening ",
        "isn't counted again (the district's posting is marked \u201calso on OPI\u201d). OPI postings the district's board doesn't list count from OPI \u2014 ",
        "many districts post their teaching jobs only there \u2014 as do OPI postings for districts this dashboard doesn't scrape directly."
      ),
      tags$p(
        "OPI is a valuable statewide source, but its publication rules and coverage have not been independently verified as a complete census of Montana vacancies. ",
        "A job absent from this dashboard is not evidence that no vacancy exists."
      ),
      tags$p(
        class = "mb-0",
        "Districts this dashboard doesn't scrape directly appear on the Map and District Summary when they post on OPI, marked \u201c", OPI_ONLY_COVERAGE, "\u201d, with NCES location and staffing and the same salary, finance and Census context where those sources cover them. ",
        "Private and tribal schools, co-ops and other employers outside the public district list stay in the Jobs Table only."
      ),
      tags$p(
        class = "small text-muted mt-2 mb-0",
        "Not included: Arrowhead Elementary School District #75 (Pray), whose website blocks automated requests; its openings are on ",
        tags$a(href = "https://arrowheadk8.com/careers/", target = "_blank", "its own careers page", .noWS = "after"), "."
      )
    )),

  # Map tab: the layout, filters and shared text are edjobs's map_tab_panel(); this is Montana's own text.
  map_tab_panel(
    "Montana",
    about = list(
      p("Only this project's ", n_distinct(map_k12$Name), " directly tracked K-12 districts and ",
        n_distinct(map_he$Name), " directly tracked Higher Ed institutions are shown here (with current openings)."),
      p("The K-12 Jobs Table also includes OPI's statewide \"Jobs for Teachers\" feed, but OPI coverage is not independently verified as a complete census of Montana vacancies. OPI postings are matched to districts through the district each posting's OPI page names; districts this dashboard doesn't scrape directly are mapped from those postings."),
      p("Circle size reflects current openings; color reflects teacher/faculty vacancy rate where available. Click a marker to jump to its filtered Jobs Table.")
    ),
    partial_note = "A red \"Partial\" badge means that district's postings come from an automated monitor of the district's own site rather than a structured job-board platform (AppliTrack/SchoolSpring/TedK12/Tyler Portico) -- its current-openings count may be less complete or slower to reflect changes than a platform-monitored district's count.",
    map_note = "Shows the directly tracked districts and colleges, plus districts this dashboard doesn't scrape directly that post on OPI this week (marked in their popup). Circle size = current openings; color = vacancy rate. ",
    county_choices = map_county_choices, pay_bands = PAY_BANDS, he_place_note = he_place_note
  ),

  # ------------------ K-12 ------------------
  nav_menu(
    "K-12", icon = icon("school"),
    # K-12 Jobs tab: the layout and filters are edjobs's jobs_tab_panel(); this is Montana's pay note.
    jobs_tab_panel("k12", pay_note = list(POSTED_LISTED_NOTE,
      old_opi_note(sum(endsWith(combineddata$`Posted / listed`, OLD_OPI_LABEL), na.rm = TRUE)), " ", paste0("Posted Pay is the pay the job posting itself states (hourly, daily, annual, or a season stipend, as written); blank where the posting gives no figure. ",
        "Typical pay (BLS est.) fills in where the posting states none: the Bureau of Labor Statistics' ",
        if (!is.na(oews_year)) paste0("May ", oews_year, " ") else "",
        "median pay for that role in the posting's region (hover for the role and area; OEWS, all employers, not just schools), so treat it as a regional estimate, not this job's offer. "),
        "Teacher salary columns reflect MT DLI Teacher Compensation data (Source: OPI GEMS) and are shown on teaching postings only; Montana publishes no district-level pay data for paraprofessional, bus driver, or other classified roles. OPI Jobs for Teachers rows show the district named on the posting's OPI page; Location keeps OPI's raw city.")),
    # K-12 Districts tab: edjobs's k12_districts_panel() (step 7 slice 2b); this state's text and salary card.
    k12_districts_panel(sort(unique(mapdata2_k12$Name)), c("Billings Public Schools", "Kalispell Public Schools"),
      openings_note = "postings in this week's scrape (all job types) and those new since last week. Posting Data says where they come from: the district's own board, a monitor of its own site (Partial), or only OPI's statewide board.",
      directory_notes = tagList(
        p(tags$strong("Teacher pay: "), "average salary and the 10th-90th percentile range (Montana Department of Labor & Industry, from OPI's GEMS data). ", tags$strong("General Fund Budget: "), "the district's General Fund expenditure (OPI school finance data files)."),
        p(tags$strong("County, poverty and lunch: "), "county median household income, median rent, mining/energy share of jobs and 5-year population change (Census American Community Survey 5-year estimates, with 90% margins of error); school-age children in poverty (Census SAIPE), with its approximate 90% range; share of students eligible for free or reduced-price lunch (NCES Common Core of Data).")),
      directory_source = "see each group above; full definitions in the District Profiles download's (?) on the Data tab.",
      compare_blurb = "Select up to four school districts to evaluate staffing demand, DLI compensation benchmarks, and community demographics side-by-side.",
      salary_card = dash_card("Teacher Avg Salary & County Median Income", info = help_popover("Teacher pay and county income",
          p(tags$strong("Teacher Avg Salary: "), "the average salary of the district's teachers, for the school system the Montana Department of Labor & Industry reports it under (blank where it suppresses the figure or no system matches)."),
          p(tags$strong("County Median Income: "), "median household income in the district's county."),
          source = "Montana Department of Labor & Industry, Labor Market Information, teacher pay from OPI's GEMS data; Census American Community Survey 5-year estimates."),
        withSpinner(plotlyOutput("k12_compare_salary_plot", height = "360px"))),
      openings_source = "each district's own job board, and the Office of Public Instruction's Montana job board."),
    # K-12 Trends tab: edjobs's k12_trends_panel() (step 7 slice 2b). Montana adds its slider label and, under the multi-year chart (Mike 11-17: it explains the chart's earlier weeks), how OPI postings are de-duplicated against district boards (opi_reconcile.R, scripts/reconcile_opi_history.R; 2026-11-03).
    k12_trends_panel(k12nowsum, k12sum, k12_timeline_value, slider_label = TRUE,
      counting_note = tagList(
        tags$strong("How postings are counted: "),
        "a job listed on both a district's own board and Montana OPI's statewide board counts once. ",
        "Since November 3, 2026 each OPI posting is checked against the district's board using its description; ",
        "earlier weeks were recomputed the same way but from OPI's subject titles alone, so they may include roughly 30 ",
        "postings a week that OPI listed twice.")),
    k12_spells_panel()
  ),

  # ------------------ Higher Ed ------------------
  nav_menu(
    "Higher Ed", icon = icon("building-columns"),
    # Higher Ed Jobs tab: the layout and filters are edjobs's jobs_tab_panel(); this is Montana's pay note.
    jobs_tab_panel("he", pay_note = list(POSTED_LISTED_NOTE, "Posted Pay is the pay the job posting itself states (hourly, annual, or per credit hour, as written); blank where the posting gives no figure. Typical pay (IPEDS est.) fills in for staff postings that state none: the college's average pay for its full-time staff in that job category (IPEDS; hover for the category), not this job's offer. Avg. Salary, Full-Time Instructional Staff is the college's IPEDS average for full-time instructional staff on 9- to 12-month contracts, all ranks (via the Urban Institute), not this job's offer.")),
    # Higher Ed Colleges tab: edjobs's he_colleges_panel() (step 7 slice 2b); Montana's Salaries and County notes.
    he_colleges_panel(sort(unique(mapdata2_he$Name)), c("Montana State University", "University of Montana"),
      salaries_note = "IPEDS average salary of full-time instructional staff on 9- to 12-month contracts, all ranks.",
      county_note = "the college's county's median income, rent, mining/energy share of jobs and population trend (Census American Community Survey 5-year estimates)."),
    # Higher Ed Trends tab: edjobs's he_trends_panel() (step 7 slice 2b).
    he_trends_panel(henowsum_he, hesum_he, he_timeline_value),
    he_spells_panel()
  ),

  # ------------------ Data & community ------------------
  # Data tab: the layout and the text both states share are edjobs's data_tab_panel(); this is Montana's own text.
  data_tab_panel(
    tiles = list(
      data_tile("download_active_k12",
                "All current public school job openings in Montana with standardized titles, positions, locations, links, and district salary benchmarks.",
                sources = "each district's own job board and the Office of Public Instruction's Montana job board; Typical pay: BLS Occupational Employment and Wage Statistics; teacher salary columns: Montana Department of Labor & Industry."),
      data_tile("download_history_k12",
                paste0("Historical record of weekly K-12 job postings across Montana", rows_phrase(download_rows("k12jobanalysis.csv")),
                       " for hiring seasonality and longitudinal teacher demand studies.")),
      data_tile("download_spells",
                "Each posting's first and last week on the boards this dashboard tracks, days listed, and subject flags (STEM, SPED, etc.). Not a time-to-fill measure: see the note on the Listing Duration tab."),
      data_tile("download_district_benchmarks",
                "District-level profiles: MT DLI salaries (10th/avg/90th), NCES teacher FTE & enrollment, student-to-teacher ratios, and Census poverty/rent.",
                heading = "District Profiles",
                sources = "Montana Department of Labor & Industry (teacher pay); OPI school finance data files; NCES Common Core of Data (via the Urban Institute); Census American Community Survey 5-year estimates and SAIPE."),
      data_tile("download_weekly_totals",
                paste0("Weekly longitudinal vacancy totals across Montana school districts",
                       rows_phrase(download_rows("k12_district_weekly_totals.csv", latest_week = TRUE), "observations"),
                       ". Ideal for seasonal hiring cycles and supply/demand modeling."),
                label = "Weekly Totals (CSV)"),
      data_tile("download_history_he",
                "Longitudinal postings for instructional faculty, adjuncts, and staff across the Montana University System, tribal colleges, and community colleges."),
      data_tile("download_he_spells"),
      data_tile("download_he_benchmarks"),
      data_tile("download_he_weekly_totals",
                "Weekly longitudinal vacancy totals across Montana colleges, universities, and tribal colleges. Ideal for tracking higher ed hiring seasonality."),
      data_tile("download_dictionary")
    ),
    dictionary = data_dictionary,
    provenance_rows = list(
      data_provenance_row(layer = "K-12 Active Vacancies",
                          source = "District Hiring Portals (Frontline/AppliTrack, SchoolSpring, TalentEd, Tyler Portico) + Montana OPI Jobs for Teachers",
                          cadence = "Weekly", badge = "success",
                          description = "Standardized active postings across 180+ Montana school districts and regional education cooperatives, cleaned to remove duplicate listings and enriched with standardized job roles, categories, and direct application links."),
      data_provenance_row(layer = "K-12 Historical Archive", source = "Historical Project Archive (2023-Present)", cadence = "Weekly Append",
                          description = "Multi-year archive of education postings used to model seasonal hiring waves, subject-area shortages (STEM, Special Education, CTE), and geographic vacancy patterns."),
      data_provenance_row(layer = "K-12 Teacher Compensation",
                          source = "Montana Dept of Labor & Industry (DLI) / OPI GEMS Certified Staff Collection", cadence = "Annual / Periodic",
                          description = "Published teacher compensation distributions (10th percentile, average, and 90th percentile) across 105+ Montana school districts. Sourced directly from official state regional wage reports."),
      data_provenance_row("ccd_staffing", layer = "District Staffing & Enrollment"),
      data_provenance_row("ipeds_pay",
                          description = "Average salaries of full-time instructional staff on 9- to 12-month contracts (all ranks and full professor rank) for Montana University System campuses, tribal colleges, and community colleges."),
      data_provenance_row("county"),
      data_provenance_row("student_need")
    ),
    citation = "Bostick, M. (2026). Montana Education Jobs Dashboard: Longitudinal Staffing Demand, Compensation, and Socioeconomic Context. ",
    repo_url = "https://github.com/bostickmike/Montana-Education-Jobs-Dashboard"
  ),

  nav_spacer(),
  feedback_nav_item(FEEDBACK_REPO_DEFAULT)
)


#--------------------------------------------------
# Server
#--------------------------------------------------
server <- function(input, output, session) {
  # Outputs and observers both states share (edjobs dashboard_server_shared(), step 7 slice 1, 2026-11-21). This
  # state's own blocks follow and read the reactives it returns.
  shared <- dashboard_server_shared(input, output, session,
                                    data = mget(dashboard_server_data_names(), inherits = TRUE),
                                    state_name = "Montana", feedback_repo = FEEDBACK_REPO_DEFAULT,
                                    timezone = "America/Denver",
                                    map_view = list(lng = -111.5, lat = 46.8, zoom = 7), he_page_length = 6,
                                    district_spec = DISTRICT_SPEC)
  k12_not_marked_only <- shared$k12_not_marked_only
  selected_district <- shared$selected_district
  selected_k12_query <- shared$selected_k12_query
  selected_k12_type <- shared$selected_k12_type
  selected_pay_band <- shared$selected_pay_band
  map_filtered <- shared$map_filtered
  filtered_hesum <- shared$filtered_hesum

}

shinyApp(ui = ui, server = server)
