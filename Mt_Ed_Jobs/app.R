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


# Keep the deployed app aligned with the pipeline's posting-identity
# comparison without requiring the app bundle to source files above it.
find_k12_new_postings <- function(k12_history) {
  dates <- sort(unique(as.Date(k12_history$Archive_Date)))
  if (length(dates) < 2) return(k12_history[0, , drop = FALSE])

  latest <- dates[length(dates)]
  previous <- dates[length(dates) - 1]
  k12_history %>%
    filter(as.Date(Archive_Date) == latest) %>%
    anti_join(
      k12_history %>% filter(as.Date(Archive_Date) == previous) %>% select(Posting_ID),
      by = "Posting_ID"
    )
}


first_seen_table <- tryCatch(read.csv("posting_first_seen.csv", colClasses = "character", fileEncoding = "UTF-8"),
                             error = function(e) NULL, warning = function(w) NULL)
POSTED_LISTED_NOTE <- paste0(
  "Posted / listed is the date the posting gives. Where the job board gives none, it shows the first week this ",
  "dashboard found the posting (\"First seen\"), or \"On the board since at least\" when the posting was already up ",
  "the first time this dashboard checked that board. ")


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
  validate_and_pad_schema(c("District", "title", "position", "location", "date_posted", "url",
                            "Posting_Source", "Posting_Identity_Method", "Posting_ID"),
                          "combinedclean.csv", on_missing = note_load_issue) %>%
  mutate(`Posted Pay` = format_posted_pay(Pay_Min, Pay_Max, Pay_Unit),
         `Typical pay (BLS est.)` = format_bls_estimate(Est_Pay, Est_Pay_Unit, Est_Occupation, Est_Area, !is.na(Pay_Min)),
         # Home page job-type tables: TRUE unless edjobs classify_work_schedule() marks the posting as a substitute,
         # extra duty, part-time, student or temporary job (the same call as the pipeline's
         # k12_jobtype_weekly_totals.csv, so the counts agree).
         .Not_Marked = is.na(classify_work_schedule(title, k12_position = position, role_hint = Role_Hint))) %>%
  select(District, title, position, location, `Posted Pay`, `Typical pay (BLS est.)`, date_posted, url,
         Posting_Source, Posting_Identity_Method, Posting_ID, Also_On_Feed, Pay_Min, Pay_Max, Pay_Unit, Est_Pay, Est_Pay_Unit,
         .Not_Marked) %>%
  # A direct posting OPI also lists (counted once, from our scrape).
  mutate(Posting_Source = ifelse(Also_On_Feed %in% c(TRUE, "TRUE"), paste0(Posting_Source, " \u00b7 also on OPI"), Posting_Source)) %>%
  distinct(Posting_ID, .keep_all = TRUE) %>%
  mutate(District = str_squish(as.character(District))) %>%
  mutate(date_posted = format_posted_or_listed_date(date_posted)) %>%
  mutate(date_posted = fill_first_seen(date_posted, District, title, url, "K-12", lookup = first_seen_table)) %>%
  arrange(District, title) %>%
  mutate(url = paste0('<a href="', url, '" target="_blank">', url, '</a>')) %>%
  rename(Title = title, Position = position, Location = location,
         `Posted / listed` = date_posted, Link = url,
         Source = Posting_Source, `Identity method` = Posting_Identity_Method)

# salarymap2.csv covers only this project's directly-scraped districts
# (k12_district_registry.csv), not Montana's full ~398-district universe --
# combineddata above has many more distinct District values (every district
# the OPI statewide fallback feed surfaces), but only the registry's districts
# have a Latitude/Longitude to put on the map. See DATA_COOKBOOK.md's "OPI
# statewide fallback feed" note.
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
# What the Home page's job-type and top-employer tables leave out while its switch is on.
HOME_SWITCH_LABEL <- "Leave out substitutes, coaching, part-time, student and temporary jobs"
NOT_MARKED_NOTE <- paste("With the switch above the tables on (the default), substitutes, coaching and other extra-duty",
                         "stipends, and postings whose title says part-time, student or temporary are left out.")
NOT_MARKED_NOTE_HE <- paste("With the switch above the tables on (the default), adjunct and part-time faculty, student jobs,",
                            "substitutes, and postings whose title says part-time or temporary are left out.")
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

bounded_timeline_value <- function(dates, days = 365) {
  latest <- max(dates)
  c(max(min(dates), latest - days), latest)
}

timeline_history_note <- function(dates) {
  span <- as.integer(max(dates) - min(dates))
  if (span < 365) {
    paste0("Only ", span, " days of archived history are currently available.")
  } else {
    ""
  }
}

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
# USGS's requested acknowledgment for The National Map's services
# (usgs.gov FAQ "What are the Terms of Use/Licensing for map services and data
# from The National Map?", updated 2022-11-10).
USGS_TILE_CREDIT <- paste('<a href="https://www.usgs.gov/programs/national-geospatial-program/national-map"',
                          'target="_blank" rel="noopener">USGS The National Map</a>: map services and data available',
                          "from U.S. Geological Survey, National Geospatial Program")

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
  nav_panel(
    "Home", value = "intro", icon = icon("house"),
    h1(class = "page-title", "Education Jobs in Montana"),
    uiOutput("data_load_issues_banner"),
    layout_columns(
      col_widths = c(4, 4, 4),
      uiOutput("kpi_k12_total", fill = TRUE),
      uiOutput("kpi_he_total", fill = TRUE),
      uiOutput("kpi_last_refreshed", fill = TRUE)
    ),
    # Drives the four tables below (counts, Share, sparklines) and the Jobs table their links open; KPI cards keep
    # both numbers.
    div(class = "home-basis-switch", style = "margin: 4px 0 -4px;",
        input_switch("home_not_marked", HOME_SWITCH_LABEL, value = TRUE, width = "100%")),
    layout_columns(
      col_widths = c(6, 6),
      dash_card("Top K-12 Hiring Districts This Week",
                div(style = "overflow-x: auto;", tableOutput("top_k12_districts")),
                info = help_popover("Top K-12 hiring districts",
                  p("The five districts with the most postings in this week's scrape, all job types (teachers, aides, drivers and so on). ", NOT_MARKED_NOTE,
                    " Last 12 Weeks: the district's postings in each of its last 12 weekly scrapes, counted the same way. Click a district to see its jobs."),
                  source = "each district's own job board, read twice a week, and the Office of Public Instruction's Montana job board.")),
      dash_card("Top Higher Ed Hiring Institutions This Week",
                div(style = "overflow-x: auto;", tableOutput("top_he_institutions")),
                info = help_popover("Top higher ed hiring institutions",
                  p("The five colleges with the most postings in this week's scrape, faculty and staff. ", NOT_MARKED_NOTE_HE,
                    " Last 12 Weeks: the college's postings in each of its last 12 weekly scrapes, counted the same way. Click a college to see its jobs."),
                  source = "each college's own job board, read twice a week."))
    ),
    layout_columns(
      col_widths = c(6, 6),
      dash_card("Top K-12 Job Types This Week",
                div(style = "overflow-x: auto;", tableOutput("top_k12_job_types")),
                info = help_popover("Top K-12 job types",
                  p("The five most-posted K-12 job types in this week's scrape, with each type's share of those postings. ", NOT_MARKED_NOTE,
                    " The sources never say a job is full-time, so this counts postings not marked otherwise. Most-posted is not the same as most in demand: a count of open postings also reflects turnover and how often a district posts."),
                  p("Last 12 Weeks: that type's postings in each of the last 12 weekly scrapes, counted the same way. Click a type to see its jobs."),
                  source = "each district's own job board, read twice a week, and the Office of Public Instruction's Montana job board.")),
      dash_card("Top Higher Ed Job Types This Week",
                div(style = "overflow-x: auto;", tableOutput("top_he_job_types")),
                info = help_popover("Top higher ed job types",
                  p("The five most-posted college job types in this week's scrape, faculty and staff, with each type's share of those postings. ", NOT_MARKED_NOTE_HE,
                    " Most-posted is not the same as most in demand."),
                  p("Last 12 Weeks: that type's postings in each of the last 12 weekly scrapes, counted the same way. Click a type to see its jobs."),
                  source = "each college's own job board, read twice a week."))
    ),
    dash_card(
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
      )
    ),
    div(style = "text-align:center; color:#999; font-size:0.85em; padding:15px;",
        paste0("Refreshed on: ", last_refreshed_date, " · Created by Mike Bostick"))
  ),

  nav_panel(
    "Map", value = "map_tab", icon = icon("map-location-dot"),
    h1(class = "page-title", "Where the Openings Are"),
    card(
      full_screen = TRUE,
      card_header(
        class = "d-flex justify-content-between align-items-center",
        "Montana Education Job Openings Map",
        info_popover(
          "About this map",
          p("Only this project's ", n_distinct(map_k12$Name), " directly tracked K-12 districts and ",
            n_distinct(map_he$Name), " directly tracked Higher Ed institutions are shown here (with current openings)."),
          p("The K-12 Jobs Table also includes OPI's statewide \"Jobs for Teachers\" feed, but OPI coverage is not independently verified as a complete census of Montana vacancies. OPI postings are matched to districts through the district each posting's OPI page names; districts this dashboard doesn't scrape directly are mapped from those postings."),
          p("Circle size reflects current openings; color reflects teacher/faculty vacancy rate where available. Click a marker to jump to its filtered Jobs Table."),
          p("K-12 and Higher Ed vacancy rates use different staffing sources (CCD vs. IPEDS) and years -- the shared color scale is for a rough at-a-glance read, not a precise cross-type comparison."),
          p(class = "mb-0", "A red \"Partial\" badge means that district's postings come from an automated monitor of the district's own site rather than a structured job-board platform (AppliTrack/SchoolSpring/TedK12/Tyler Portico) -- its current-openings count may be less complete or slower to reflect changes than a platform-monitored district's count.")
        )
      ),
      layout_sidebar(
        fillable = FALSE,
        sidebar = sidebar(
          title = "Filters",
          width = 300,
          textInput(
            "map_search_keyword",
            label = tagList(icon("magnifying-glass"), " Search by keyword or role:"),
            value = "",
            placeholder = "e.g., special ed, coach, bus driver..."
          ),
          div(
            class = "map-chips",
            span("Popular: "),
            actionLink("map_chip_sped", "Special Ed"),
            actionLink("map_chip_math", "Mathematics"),
            actionLink("map_chip_elem", "Elementary"),
            actionLink("map_chip_science", "Science"),
            actionLink("map_chip_music", "Music / Art"),
            actionLink("map_chip_driver", "Bus Driver"),
            actionLink("map_chip_clear", "✕ Clear", class = "text-danger fw-semibold")
          ),
          selectInput(
            "map_county", "County:",
            choices = map_county_choices,
            selected = "all"
          ),
          checkboxGroupInput(
            "map_types", "Employer type:",
            choices = c("K-12 Districts" = "K-12 District", "Higher Ed" = "Higher Ed Institution"),
            selected = c("K-12 District", "Higher Ed Institution"),
            inline = TRUE
          ),
          selectInput(
            "map_salary_tier", "Pay:",
            # Built from PAY_BANDS. A posting counts by its posted pay,
            # else its district/institution role figure, else the BLS
            # estimate -- each in its own unit.
            choices = c("All pay" = "all", setNames(names(PAY_BANDS), vapply(PAY_BANDS, function(b) {
              paste0(if (b$unit == "hour") "Hourly: " else "Annual: ", b$label)
            }, character(1)))),
            selected = "all"
          ),
          selectInput(
            "map_urgency", "Posting volume:",
            choices = c(
              "All Active Locations" = "all",
              "High Volume (5+ openings)" = "5_plus",
              "Multiple Openings (2+)" = "2_plus",
              "New Postings This Week" = "has_new"
            ),
            selected = "all"
          ),
          actionButton("map_filter_reset", "Reset All Filters", icon = icon("arrow-rotate-left"),
                       class = "btn-outline-secondary btn-sm w-100")
        ),
        div(class = "mb-2", uiOutput("map_filter_count")),
        withSpinner(leafletOutput("combined_map", height = 650)),
        p(class = "text-muted small mt-2 mb-0",
          "Shows the directly tracked districts and colleges, plus districts this dashboard doesn't scrape directly that post on OPI this week (marked in their popup). Circle size = current openings; color = vacancy rate. ",
          "Click a marker to see its jobs.",
          if (nzchar(he_place_note)) tags$br(), he_place_note)
      )
    )
  ),

  # ------------------ K-12 ------------------
  nav_menu(
    "K-12", icon = icon("school"),
    nav_panel(
      "Jobs", value = "k12_table", icon = icon("table"),
      div(
        class = "table-toolbar",
        div(
          style = "display: flex; align-items: center; gap: 8px; flex-wrap: wrap;",
          span(style = "font-weight: 600; font-size: 13.5px; color: #334155;", "Filter Postings:"),
          radioGroupButtons(
            inputId = "k12_quick_filter",
            label = NULL,
            choices = c(
              "All Active Postings" = "all",
              "🟢 New This Week" = "new"
            ),
            selected = "all",
            status = "primary",
            size = "sm",
            checkIcon = list(yes = icon("check"))
          )
        ),
        uiOutput("k12_filter_status")
      ),
      p(class = "text-muted small mb-2",
        "Posted Pay is what the posting itself states; the other pay columns are labeled estimates, not this job's offer. ",
        info_popover("About the pay columns",
          p(class = "mb-0", POSTED_LISTED_NOTE, paste0("Posted Pay is the pay the job posting itself states (hourly, daily, annual, or a season stipend, as written); blank where the posting gives no figure. ",
        "Typical pay (BLS est.) fills in where the posting states none: the Bureau of Labor Statistics' ",
        if (!is.na(oews_year)) paste0("May ", oews_year, " ") else "",
        "median pay for that role in the posting's region (hover for the role and area; OEWS, all employers, not just schools), so treat it as a regional estimate, not this job's offer. "),
        "Teacher salary columns reflect MT DLI Teacher Compensation data (Source: OPI GEMS) and are shown on teaching postings only; Montana publishes no district-level pay data for paraprofessional, bus driver, or other classified roles. OPI Jobs for Teachers rows show the district named on the posting's OPI page; Location keeps OPI's raw city."))),
      DTOutput("k12_jobs", fill = FALSE)
    ),
    nav_panel(
      "Districts", value = "k12_summary", icon = icon("school"),
      navset_card_tab(
        id = "k12_summary_tabs",
        nav_panel(
          title = tagList(icon("table-list"), " District Directory"),
          value = "k12_summary_dir",
          h4("One row per district -- current openings, teacher vacancy rate, and salary data ",
             help_popover("District directory",
               p(tags$strong("Openings: "), "postings in this week's scrape (all job types) and those new since last week. Posting Data says where they come from: the district's own board, a monitor of its own site (Partial), or only OPI's statewide board."),
               p(tags$strong("Teacher vacancy rate and students per teacher: "), "current teacher postings, and enrollment, divided by teacher FTE (NCES Common Core of Data)."),
               p(tags$strong("Teacher pay: "), "average salary and the 10th-90th percentile range (Montana Department of Labor & Industry, from OPI's GEMS data). ", tags$strong("General Fund Budget: "), "the district's General Fund expenditure (OPI school finance data files)."),
               p(tags$strong("County, poverty and lunch: "), "county median household income, median rent, mining/energy share of jobs and 5-year population change (Census American Community Survey 5-year estimates, with 90% margins of error); school-age children in poverty (Census SAIPE), with its approximate 90% range; share of students eligible for free or reduced-price lunch (NCES Common Core of Data)."),
               source = "see each group above; full definitions in the District Profiles download's (?) on the Data tab.")),
          DTOutput("k12_summary_table", fill = FALSE),
          uiOutput("k12_summary_footnote")
        ),
        nav_panel(
          title = tagList(icon("code-compare"), " Head-to-Head Comparator"),
          value = "k12_summary_comp",
          p(class = "text-muted small", style = "margin-top: 6px;",
            "Select up to four school districts to evaluate staffing demand, DLI compensation benchmarks, and community demographics side-by-side."),
          layout_columns(
            col_widths = c(8, 4),
            selectizeInput(
              "k12_compare_districts",
              label = "Select School Districts (up to 4):",
              choices = sort(unique(mapdata2_k12$Name)),
              selected = c("Billings Public Schools", "Kalispell Public Schools"),
              multiple = TRUE,
              width = "100%",
              options = list(maxItems = 4, placeholder = "Type or select up to 4 districts...")
            ),
            div(
              tags$label("Quick Presets:", style = "display: block; margin-bottom: 5px;"),
              div(
                class = "btn-group",
                actionButton("k12_comp_preset_top", "Top Hiring", class = "btn-sm btn-outline-secondary", icon = icon("fire")),
                actionButton("k12_comp_preset_largest", "Largest", class = "btn-sm btn-outline-secondary", icon = icon("users")),
                actionButton("k12_comp_preset_clear", "Clear", class = "btn-sm btn-outline-secondary", icon = icon("xmark"))
              )
            )
          ),
          uiOutput("k12_compare_cards"),
          layout_columns(
            col_widths = c(4, 4, 4),
            dash_card("Teacher Avg Salary & County Median Income", info = help_popover("Teacher pay and county income",
                        p(tags$strong("Teacher Avg Salary: "), "the average salary of the district's teachers, for the school system the Montana Department of Labor & Industry reports it under (blank where it suppresses the figure or no system matches)."),
                        p(tags$strong("County Median Income: "), "median household income in the district's county."),
                        source = "Montana Department of Labor & Industry, Labor Market Information, teacher pay from OPI's GEMS data; Census American Community Survey 5-year estimates."),
                      withSpinner(plotlyOutput("k12_compare_salary_plot", height = "360px"))),
            dash_card("Student Enrollment",
                      withSpinner(plotlyOutput("k12_compare_enrollment_plot", height = "360px")),
                      info = help_popover("Student enrollment",
                        p("Pre-K through grade 12 fall enrollment. Districts are in the same order in all three charts, largest enrollment first."),
                        source = "NCES Common Core of Data, via the Urban Institute's Education Data Portal.")),
            # Two bar charts, not one dual-axis chart (Mike 2026-11-16): a line
            # across districts implied a trend, and the two axes' scales made the
            # bars-vs-line comparison arbitrary. Same district order in both.
            dash_card("Active Openings",
                      withSpinner(plotlyOutput("k12_compare_openings_plot", height = "360px")),
                      info = help_popover("Active openings",
                        p("Postings in this week's scrape, all job types (teachers, aides, coaches, drivers and so on)."),
                        source = "each district's own job board, and the Office of Public Instruction's Montana job board."))
          ),
          dash_card("Active Openings in Selected Districts",
                    DTOutput("k12_compare_jobs_table", fill = FALSE),
                    info = help_popover("Openings in the selected districts",
                      p("Every current posting from the districts chosen above, with the same columns as the K-12 Jobs tab: see \"About the pay columns\" there.")))
        )
      )
    ),
    nav_panel(
      "Trends", value = "k12_trends", icon = icon("chart-line"),
      navset_card_tab(
        id = "k12_trends_tabs",
        nav_panel(
          title = tagList(icon("chart-column"), " Current Trends"),
          value = "k12_trends_current",
          p(class = "text-muted", style = "margin-top: 5px; margin-bottom: 12px;",
            "Current subject distribution across active K-12 postings with 12-week vacancy sparklines. ",
            help_popover("Current K-12 trends",
              p("Teacher postings in this week's scrape by subject, with each subject's postings over its last 12 weekly scrapes. The subject is read from the job title (\"Major subject groups\" combines subjects, e.g. all STEM). Non-teaching jobs are not counted here."),
              source = "the districts' job boards, scraped weekly; subjects by this dashboard's title classifier.")),
          layout_sidebar(
            fillable = FALSE,
            sidebar = sidebar(
              width = 260,
              selectInput(
                "district_current",
                "District:",
                choices = sort(unique(k12nowsum$District)),
                selected = "Total"
              ),
              radioButtons("k12_detail_level_current", "View:",
                           choices = c("Individual subjects" = "detail",
                                       "Major subject groups" = "agg"),
                           selected = "detail")
            ),
            div(class = "trends-table-container mt-0",
                withSpinner(tableOutput("k12_current_trends_table")))
          )
        ),
        nav_panel(
          title = tagList(icon("chart-line"), " Multi-Year Trends"),
          value = "k12_trends_historical",
          p(class = "text-muted", style = "margin-top: 5px; margin-bottom: 12px;",
            "Multi-year vacancy volume time series tracking hiring trends across weekly snapshots. ",
            help_popover("Multi-year K-12 trends",
              p("Teacher postings counted in each weekly scrape, by subject (read from the job title). A count is how many postings were up that week, not how many were new."),
              source = "the districts' job boards, scraped weekly and kept in the K-12 History Archive (Data tab).")),
          layout_sidebar(
            fillable = FALSE,
            sidebar = sidebar(
              width = 260,
              selectInput(
                "district_trend",
                "District:",
                choices = sort(unique(k12sum$District)),
                selected = "Total"
              ),
              pickerInput(
                "broad_category",
                "Teacher category:",
                choices  = sort(unique(k12sum$Broad_Category)),
                selected = sort(unique(k12sum$Broad_Category)),
                multiple = TRUE,
                width = "100%",
                options = pickerOptions(actionsBox = TRUE, liveSearch = TRUE, selectedTextFormat = "count > 3")
              ),
              radioButtons("k12_detail_level_trends", "View:",
                           choices = c("Individual subjects" = "detail",
                                       "Major subject groups" = "agg"),
                           selected = "detail")
            ),
            div(style = "color:#777; font-size:0.9em;", textOutput("k12_slider_label")),
            sliderInput(
              "k12_scroll",
              "Scroll timeline:",
              min = min(k12sum$Archive_Date),
              max = max(k12sum$Archive_Date),
              value = k12_timeline_value,
              timeFormat = "%Y-%m-%d",
              width = "100%"
            ),
            withSpinner(plotlyOutput("k12_longitudinal_plot")),
            # Method note (2026-11-03): how OPI postings are de-duplicated against
            # district boards (opi_reconcile.R, scripts/reconcile_opi_history.R).
            # Below the multi-year chart since 2026-11-17 (Mike): it explains the
            # chart's earlier weeks.
            div(class = "alert alert-info small mt-3 mb-0", role = "note",
                tags$strong("How postings are counted: "),
                "a job listed on both a district's own board and Montana OPI's statewide board counts once. ",
                "Since November 3, 2026 each OPI posting is checked against the district's board using its description; ",
                "earlier weeks were recomputed the same way but from OPI's subject titles alone, so they may include roughly 30 ",
                "postings a week that OPI listed twice.")
          )
        )
      )
    ),
    k12_spells_panel()
  ),

  # ------------------ Higher Ed ------------------
  nav_menu(
    "Higher Ed", icon = icon("building-columns"),
    nav_panel(
      "Jobs", value = "he_table", icon = icon("table"),
      div(
        class = "table-toolbar",
        div(
          style = "display: flex; align-items: center; gap: 8px; flex-wrap: wrap;",
          span(style = "font-weight: 600; font-size: 13.5px; color: #334155;", "Filter Postings:"),
          radioGroupButtons(
            inputId = "he_quick_filter",
            label = NULL,
            choices = c(
              "All Active Postings" = "all",
              "🟢 New This Week" = "new"
            ),
            selected = "all",
            status = "primary",
            size = "sm",
            checkIcon = list(yes = icon("check"))
          ),
          radioButtons(
            "he_table_appointment", "Appointment:",
            choices = c(
              "All roles" = "all",
              "Faculty/instructor (non-adjunct)" = "Faculty/instructor (non-adjunct)",
              "Adjunct/part-time faculty" = "Adjunct/part-time faculty",
              "Other / not faculty" = "Other / not faculty"
            ),
            selected = "all", inline = TRUE
          )
        ),
        uiOutput("he_filter_status")
      ),
      p(class = "text-muted small mb-2",
        "Posted Pay is what the posting itself states; the other pay columns are labeled estimates, not this job's offer. ",
        info_popover("About the pay columns",
          p(class = "mb-0", POSTED_LISTED_NOTE, "Posted Pay is the pay the job posting itself states (hourly, annual, or per credit hour, as written); blank where the posting gives no figure. Typical pay (IPEDS est.) fills in for staff postings that state none: the college's average pay for its full-time staff in that job category (IPEDS; hover for the category), not this job's offer. Avg. Salary, Full-Time Instructional Staff is the college's IPEDS average for full-time instructional staff on 9- to 12-month contracts, all ranks (via the Urban Institute), not this job's offer."))),
      DTOutput("he_jobs", fill = FALSE)
    ),
    nav_panel(
      "Colleges", value = "he_summary", icon = icon("building-columns"),
      navset_card_tab(
        id = "he_summary_tabs",
        nav_panel(
          title = tagList(icon("building-columns"), " Institution Directory"),
          value = "he_summary_dir",
          h4("One row per institution -- current openings, faculty vacancy rate, and salary data ",
             help_popover("Institution directory",
               p(tags$strong("Openings: "), "postings in this week's scrape, split into full-time and adjunct/part-time faculty by the job title, and those new since last week."),
               p(tags$strong("Faculty vacancy rate, faculty count and students per faculty: "), "full-time faculty postings, and enrollment, divided by full-time instructional staff (IPEDS)."),
               p(tags$strong("Salaries: "), "IPEDS average salary of full-time instructional staff on 9- to 12-month contracts, all ranks."),
               p(tags$strong("Students: "), "5-year enrollment trend (IPEDS) and the share of students receiving Pell Grants (Federal Student Aid)."),
               p(tags$strong("County: "), "the college's county's median income, rent, mining/energy share of jobs and population trend (Census American Community Survey 5-year estimates)."),
               source = "IPEDS and Federal Student Aid data via the Urban Institute's Education Data Portal; Census ACS; the colleges' job boards.")),
          DTOutput("he_summary_table", fill = FALSE),
          uiOutput("he_summary_footnote")
        ),
        nav_panel(
          title = tagList(icon("code-compare"), " Head-to-Head Comparator"),
          value = "he_summary_comp",
          p(class = "text-muted small", style = "margin-top: 6px;",
            "Select up to four higher education institutions to evaluate faculty demand, IPEDS salary benchmarks, and institutional enrollment side-by-side."),
          layout_columns(
            col_widths = c(8, 4),
            selectizeInput(
              "he_compare_insts",
              label = "Select Institutions (up to 4):",
              choices = sort(unique(mapdata2_he$Name)),
              selected = c("Montana State University", "University of Montana"),
              multiple = TRUE,
              width = "100%",
              options = list(maxItems = 4, placeholder = "Type or select up to 4 institutions...")
            ),
            div(
              tags$label("Quick Presets:", style = "display: block; margin-bottom: 5px;"),
              div(
                class = "btn-group",
                actionButton("he_comp_preset_top", "Top Hiring", class = "btn-sm btn-outline-secondary", icon = icon("fire")),
                actionButton("he_comp_preset_clear", "Clear", class = "btn-sm btn-outline-secondary", icon = icon("xmark"))
              )
            )
          ),
          uiOutput("he_compare_cards"),
          layout_columns(
            col_widths = c(6, 6),
            dash_card("Avg. Salary, Full-Time Instructional Staff (IPEDS)", info = help_popover("Faculty average salary",
                        p("The average salary of full-time instructional staff on 9- to 12-month contracts, all academic ranks, for the latest IPEDS year and the year before. IPEDS collects no salaries for part-time staff, or for full-time staff on contracts under 9 months."),
                        source = "IPEDS, via the Urban Institute's Education Data Portal."),
                      withSpinner(plotlyOutput("he_compare_salary_plot", height = "360px"))),
            dash_card("Openings by Appointment Type", info = help_popover("Openings by appointment type",
                        p("This week's postings, sorted by the job title: adjunct or part-time faculty (titles with \"adjunct\" or \"part-time\"), full-time faculty or instructor (titles such as instructor, professor, lecturer, librarian), or other (staff)."),
                        source = "each college's own job board."),
                      withSpinner(plotlyOutput("he_compare_openings_plot", height = "360px")))
          ),
          dash_card("Active Openings in Selected Institutions", info = help_popover("Openings in the selected institutions",
                      p("Every current posting from the colleges chosen above, with the same columns as the Higher Ed Jobs tab.")),
                    DTOutput("he_compare_jobs_table", fill = FALSE))
        )
      )
    ),
    nav_panel(
      "Trends", value = "he_trends", icon = icon("chart-line"),
      navset_card_tab(
        id = "he_trends_tabs",
        nav_panel(
          title = tagList(icon("chart-column"), " Current Trends"),
          value = "he_trends_current",
          p(class = "text-muted", style = "margin-top: 5px; margin-bottom: 12px;",
            "Current institution and discipline breakdown across active higher education postings with 12-week sparklines. ",
            help_popover("Current higher ed trends",
              p("Faculty postings in this week's scrape by discipline, with each discipline's postings over its last 12 weekly scrapes. The discipline is read from the job title. Staff postings are not counted here; the Appointment buttons split full-time from adjunct/part-time."),
              source = "each college's own job board, scraped weekly; disciplines by this dashboard's title classifier.")),
          layout_sidebar(
            fillable = FALSE,
            sidebar = sidebar(
              width = 260,
              selectInput("inst_current", "Institution:",
                          choices = sort(unique(henowsum_he$Institution)), selected = "Total"),
              radioButtons("he_current_appointment", "Appointment:",
                           choices = c(
                             "All faculty postings" = "all",
                             "Faculty/instructor (non-adjunct)" = "Instructor/Teacher/Faculty",
                             "Adjunct/part-time faculty" = "Adjunct/Part-Time Faculty"
                           ),
                           selected = "all"),
              radioButtons("he_detail_level_current", "View:",
                           choices = c("Individual fields" = "detail", "Major academic areas" = "agg"),
                           selected = "detail")
            ),
            div(class = "trends-table-container mt-0",
                withSpinner(tableOutput("he_current_trends_table")))
          )
        ),
        nav_panel(
          title = tagList(icon("chart-line"), " Multi-Year Trends"),
          value = "he_trends_historical",
          p(class = "text-muted", style = "margin-top: 5px; margin-bottom: 12px;",
            "Multi-year vacancy volume time series tracking higher education hiring trends across weekly snapshots. ",
            help_popover("Multi-year higher ed trends",
              p("Faculty postings counted in each weekly scrape, by discipline (read from the job title). A count is how many postings were up that week, not how many were new."),
              source = "each college's own job board, scraped weekly and kept in the Higher Ed Archive (Data tab).")),
          layout_sidebar(
            fillable = FALSE,
            sidebar = sidebar(
              width = 260,
              selectInput(
                "inst_trend",
                "Institution:",
                choices = sort(unique(hesum_he$Institution)),
                selected = "Total"
              ),
              pickerInput(
                "he_category",
                "Category:",
                choices  = sort(unique(hesum_he$Category)),
                selected = sort(unique(hesum_he$Category)),
                multiple = TRUE,
                width = "100%",
                options = pickerOptions(actionsBox = TRUE, liveSearch = TRUE, selectedTextFormat = "count > 3")
              ),
              radioButtons("he_chart_type", "Jobs:", choices = c(
                "All Jobs" = "all",
                "Faculty/instructor (non-adjunct)" = "Instructor/Teacher/Faculty",
                "Adjunct/part-time faculty" = "Adjunct/Part-Time Faculty"
              ), selected = "all"),
              radioButtons("he_detail_level_trends", "View:",
                           choices = c("Individual fields" = "detail", "Major academic areas" = "agg"),
                           selected = "detail")
            ),
            div(style = "color:#777; font-size:0.9em;", textOutput("he_slider_label")),
            sliderInput(
              "he_scroll",
              "Scroll timeline:",
              min = min(hesum_he$Archive_Date),
              max = max(hesum_he$Archive_Date),
              value = he_timeline_value,
              timeFormat = "%Y-%m-%d",
              width = "100%"
            ),
            withSpinner(plotlyOutput("he_longitudinal_plot"))
          )
        )
      )
    ),
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
                "Historical record of weekly K-12 job postings across Montana (3,200+ records) for hiring seasonality and longitudinal teacher demand studies."),
      data_tile("download_spells",
                "Each posting's first and last week on the boards this dashboard tracks, days listed, and subject flags (STEM, SPED, etc.). Not a time-to-fill measure: see the note on the Listing Duration tab."),
      data_tile("download_district_benchmarks",
                "District-level profiles: MT DLI salaries (10th/avg/90th), NCES teacher FTE & enrollment, student-to-teacher ratios, and Census poverty/rent.",
                heading = "District Profiles",
                sources = "Montana Department of Labor & Industry (teacher pay); OPI school finance data files; NCES Common Core of Data (via the Urban Institute); Census American Community Survey 5-year estimates and SAIPE."),
      data_tile("download_weekly_totals",
                "Weekly longitudinal vacancy totals across Montana school districts (3,700+ observations). Ideal for seasonal hiring cycles and supply/demand modeling.",
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
                                    state_name = "Montana", feedback_repo = FEEDBACK_REPO_DEFAULT)
  k12_not_marked_only <- shared$k12_not_marked_only
  selected_district <- shared$selected_district
  selected_k12_query <- shared$selected_k12_query
  selected_k12_type <- shared$selected_k12_type
  selected_pay_band <- shared$selected_pay_band
  map_filtered <- shared$map_filtered
  filtered_hesum <- shared$filtered_hesum


  # -------- New This Week --------
  output$k12_new_table <- renderDT({
    datatable(
      k12_new_this_week %>%
        select(title, District, location, Broad_Category, Posting_Source,
               Posting_Identity_Method, url),
      options = list(scrollX = TRUE)
    )
  })


  # -------- K-12 --------
  output$k12_jobs <- renderDT({
    df <- combineddata
    if (!is.null(selected_district())) df <- df %>% filter(District == selected_district())
    if (!is.null(selected_k12_type())) df <- df %>% filter(Position == selected_k12_type())
    if (k12_not_marked_only()) df <- df %>% filter(.Not_Marked)
    # Same matcher and searchable text as map_filtered(), so the count here
    # equals the popup's "N matching openings".
    if (!is.null(selected_k12_query())) {
      df <- df[match_job_query(paste(coalesce(df$Title, ""), coalesce(df$Position, "")), selected_k12_query()), , drop = FALSE]
    }
    if (!is.null(selected_pay_band())) df <- df[in_pay_band(df$.Pay_Value, df$.Pay_Unit, selected_pay_band(), PAY_BANDS), , drop = FALSE]
    df <- df %>% select(-any_of(HIDDEN_COLS))
    if (isTRUE(identical(input$k12_quick_filter, "new"))) {
      df <- df %>% filter(Posting_ID %in% k12_new_this_week$Posting_ID)
    }
    df <- df %>% select(-any_of(c("Posting_ID", "Identity method", "Posting_Identity_Method", ".salary_district")))
    datatable(df, filter = "top", escape = FALSE, extensions = "Buttons",
              options = list(scrollX = TRUE, dom = "Bfrtip", buttons = c("copy", "csv", "print")))
  })


  # District Summary -- everything the map popups show, as a real
  # exportable table. Teacher_Avg_Salary + 10th/90th percentile band (MT
  # DLI Teacher Compensation Report), not a base-salary-plus-prior-year
  # pair -- see DATA_COOKBOOK.md for why this is a different metric.
  output$k12_summary_table <- renderDT({
    k12_rows <- combined_map_data %>% filter(Type == "K-12 District")
    year <- unique(na.omit(k12_rows$Salary_Year))
    salary_year_label <- if (length(year) > 0) year[1] else "current year"
    finance_year <- unique(na.omit(k12_rows$Finance_FY))
    finance_year_label <- if (length(finance_year) > 0) finance_year[1] else "current fiscal year"

    df <- k12_rows %>%
      arrange(desc(CurrentCount)) %>%
      transmute(
        District = Name,
        County,
        `Current Openings` = CurrentCount,
        # Real, sortable/filterable column -- not just a map badge or a
        # buried code comment -- so "why does this district look quiet" is
        # answerable directly from the exportable table, not just the map.
        # "Full" is the overwhelming majority (every district on a real ATS
        # platform); see the Map tab's helpText for what "Partial" means.
        `Posting Data` = Data_Coverage,
        `New This Week` = WeeklyNew,
        `Teacher Vacancy Rate` = Vacancy_Rate,
        Enrollment,
        `Students per Teacher` = round(Students_Per_Teacher, 1),
        `Teacher Avg Salary` = Teacher_Avg_Salary,
        `Teacher Salary Range (10th-90th %ile)` = ifelse(
          is.na(Teacher_Salary_10th_Pctile) | is.na(Teacher_Salary_90th_Pctile), NA_character_,
          paste0(scales::dollar(Teacher_Salary_10th_Pctile), " - ", scales::dollar(Teacher_Salary_90th_Pctile))
        ),
        `Annual General Fund Budget` = Total_General_Fund_Expenditure,
        `County Median Income` = Median_Household_Income,
        `County Median Rent (per month)` = Median_Gross_Rent,
        `County Mining/Energy Jobs` = Mining_Employment_Share,
        `County Figures: 90% Margin of Error` = county_moe_summary(Median_Household_Income_MOE, Median_Gross_Rent_MOE,
                                                            Mining_Employment_Share, Mining_Employment_Share_MOE),
        `County Population Trend (5yr)` = Population_Change_Pct,
        # Numbers, formatted by DT below, so the column sorts as numbers (the
        # table sorts on the server, in R, by the underlying value); where the rate is a
        # stand-in (a school with no SAIPE geography of its own) the next
        # column says so.
        `School-Age Children in Poverty (Census est.)` = Child_Poverty_Rate,
        `Approx. 90% Range` = format_poverty_range(Child_Poverty_Low, Child_Poverty_High),
        `Poverty Estimate Basis` = ifelse(is.na(Child_Poverty_Rate), NA_character_,
                                      ifelse(is.na(Child_Poverty_Basis), "District", "Surrounding district")),
        # School-based count beside the Census estimate (CCD school directory):
        # share of students eligible for free or reduced-price lunch, and its year.
        `Free/Reduced Lunch` = Free_Reduced_Lunch_Share,
        `Lunch Data Year` = ifelse(is.na(Free_Reduced_Lunch_Share), NA_character_, FRL_Year)
      )
    names(df)[names(df) == "Teacher Avg Salary"] <- paste0("Teacher Avg Salary (", salary_year_label, ")")
    names(df)[names(df) == "Annual General Fund Budget"] <- paste0("Annual General Fund Budget (FY", finance_year_label, ")")

    # Numeric columns stay numbers so the server-side sort is numeric
    # (2026-11-09 review: "9%" sorted after "92%", "100%" first or last);
    # DT formats them for display. Matched by prefix: some headers get a year.
    cols_like <- function(prefixes) names(df)[vapply(names(df), function(n) any(startsWith(n, prefixes)), logical(1))]
    datatable(df, filter = "top", extensions = "Buttons",
              options = list(scrollX = TRUE, dom = "Bfrtip", buttons = c("copy", "csv", "print"), pageLength = 18)) %>%
      formatPercentage(cols_like(c("Teacher Vacancy Rate", "County Mining/Energy Jobs", "School-Age Children in Poverty (Census est.)", "County Population Trend (5yr)")), digits = 1) %>%
      formatPercentage(cols_like(c("Free/Reduced Lunch")), digits = 0) %>%
      formatCurrency(cols_like(c("Teacher Avg Salary", "County Median Income", "Annual General Fund Budget", "County Median Rent (per month)")), digits = 0) %>%
      formatRound("Students per Teacher", digits = 1)
  })

  output$k12_summary_footnote <- renderUI({
    year <- unique(na.omit(combined_map_data$Salary_Year[combined_map_data$Type == "K-12 District"]))
    source <- unique(na.omit(combined_map_data$Salary_Source[combined_map_data$Type == "K-12 District"]))
    finance_fy <- unique(na.omit(combined_map_data$Finance_FY[combined_map_data$Type == "K-12 District"]))
    finance_source <- unique(na.omit(combined_map_data$Finance_Source[combined_map_data$Type == "K-12 District"]))
    acs_year <- unique(na.omit(combined_map_data$ACS_Year[combined_map_data$Type == "K-12 District"]))
    saipe_year <- unique(na.omit(combined_map_data$SAIPE_Year[combined_map_data$Type == "K-12 District"]))
    req(length(year) > 0, length(source) > 0)
    tagList(
      helpText(
        "Salary data:", source[1], paste0("(", year[1], " school year)"), "—",
        tags$a(href = DLI_SALARY_SOURCE_URL, target = "_blank", "lmi.mt.gov"),
        ". Average salary and 10th/90th percentile pay range (reflecting starting to senior teacher pay) — not a contract base salary."
      ),
      if (length(finance_fy) > 0 && length(finance_source) > 0) {
        helpText(
          "General Fund expenditure:", finance_source[1], paste0("(FY", finance_fy[1], ")."),
          "This is total day-to-day operating spending, not per-pupil or per-teacher spending."
        )
      },
      if (length(acs_year) > 0) {
        helpText(
          "County context (income, rent, mining/energy employment share, population trend): US Census Bureau, American Community Survey 5-Year Estimates",
          paste0("(", acs_year[1], ")"), "—",
          tags$a(href = "https://www.census.gov/data/developers/data-sets/acs-5year.html", target = "_blank", "census.gov"),
          ". County-level, not district-level -- sibling districts in the same county share the same figures.",
          "\u00b1 values are the Census Bureau's 90% margins of error (the mining share's from Census's formula for a",
          "proportion); a share whose margin is at least as large as the share is marked \"not distinguishable from 0\".",
          "County population totals are set to Census's population estimates, so the 5-year trend has no margin of error."
        )
      },
      helpText(
        "Free/reduced lunch: share of students eligible for free or reduced-price lunch, NCES Common Core of Data",
        "school directory (Lunch Data Year: that district's newest reporting year) --",
        tags$a(href = "https://educationdata.urban.org/documentation/", target = "_blank", "educationdata.urban.org"),
        ". A school-based count, not a poverty estimate: schools serving free meals to all (community eligibility)",
        "may count every student; a share of 100% is marked \"every student counted (likely free meals for all)\".",
        "Left blank where schools holding under 80% of a district's students reported."
      ),
      helpText(
        "Employers that aren't public school districts are on the map too: special-education cooperatives and a",
        "hospital school (NCES Common Core of Data), the Northern Cheyenne Tribal School (CCD's Bureau of Indian",
        "Education schools) and private schools, whose teacher and student counts come from the NCES Private School",
        "Universe Survey, 2023-24 -- the newest edition, older than the public-district figures. No public source",
        "reports their teacher pay or budgets, so those stay blank.",
        tags$a(href = "https://nces.ed.gov/surveys/pss/", target = "_blank", "nces.ed.gov/surveys/pss")
      ),
      if (length(saipe_year) > 0) {
        helpText(
          "School-age children in poverty: US Census Bureau, Small Area Income and Poverty Estimates (SAIPE)",
          paste0("(", saipe_year[1], ")"), "—",
          tags$a(href = "https://www.census.gov/programs-surveys/saipe/data/datasets.html", target = "_blank", "census.gov/saipe"),
          ". District-level. For districts split between an elementary and a high-school district, this pools the two: children 5-17 in poverty summed over both districts, divided by their children 5-17 summed -- see DATA_COOKBOOK.md.",
          # Census: "A true poverty \"rate\" for children cannot be determined from these figures,
          # because the numerator and denominator refer to slightly different universes" (SAIPE
          # school district overview, revised 2026-01-12; Mike chose this label 2026-11-15).
          "Census's estimate of related children 5-17 in families in poverty, divided by all children 5-17 in the district.",
          "Census notes this is not a true poverty rate: foster children, other children not related to the householder and",
          "children in group quarters are counted in the second figure only.",
          # "Quantifying Relative Error in the School District Estimates" (census.gov, revised 2025-12-17).
          "The range beside each estimate is Census's approximate 90% range for a district of that size: Census publishes",
          "no margin of error for one district, only median relative errors by district size, which it calls an approximate",
          "upper bound. Under 2,500 people an estimate can be off by about 110% of itself; at 65,000 or more, by about 25%.",
          "A private or tribal school has no Census poverty estimate of its own; it shows its surrounding district's estimate (marked \"Surrounding district\")."
        )
      }
    )
  })


  output$k12_compare_cards <- renderUI({
    selected <- input$k12_compare_districts
    if (is.null(selected) || length(selected) == 0) {
      return(div(class = "alert alert-info", style = "margin-top: 15px;",
                 icon("circle-info"), " Please select one to four school districts above to display comparative benchmarks."))
    }
    
    col_width <- case_when(
      length(selected) == 1 ~ 12,
      length(selected) == 2 ~ 6,
      length(selected) == 3 ~ 4,
      TRUE ~ 3
    )

    k12_rows <- combined_map_data %>%
      filter(Type == "K-12 District", Name %in% selected)

    cards <- lapply(selected, function(dname) {
      row <- k12_rows %>% filter(Name == dname)
      if (nrow(row) == 0) return(NULL)

      avg_sal <- if (!is.na(row$Teacher_Avg_Salary[1])) scales::dollar(row$Teacher_Avg_Salary[1]) else "N/A"
      band_sal <- if (!is.na(row$Teacher_Salary_10th_Pctile[1]) && !is.na(row$Teacher_Salary_90th_Pctile[1])) {
        paste0(scales::dollar(row$Teacher_Salary_10th_Pctile[1]), " - ", scales::dollar(row$Teacher_Salary_90th_Pctile[1]))
      } else "N/A"
      gen_fund <- if (!is.na(row$Total_General_Fund_Expenditure[1])) scales::dollar(row$Total_General_Fund_Expenditure[1]) else "N/A"
      vac_rate <- if (!is.na(row$Vacancy_Rate[1])) scales::percent(row$Vacancy_Rate[1], accuracy = 0.1) else "N/A"
      enroll <- if (!is.na(row$Enrollment[1])) scales::comma(row$Enrollment[1]) else "N/A"
      spt <- if (!is.na(row$Students_Per_Teacher[1])) sprintf("%.1f", row$Students_Per_Teacher[1]) else "N/A"
      rent <- if (!is.na(row$Median_Gross_Rent[1])) paste0(scales::dollar(row$Median_Gross_Rent[1]), "/mo", format_moe_dollars(row$Median_Gross_Rent_MOE[1])) else "N/A"
      poverty <- if (!is.na(row$Child_Poverty_Rate[1])) scales::percent(row$Child_Poverty_Rate[1], accuracy = 0.1) else "N/A"
      if (!is.na(row$Child_Poverty_Rate[1]) && !is.na(row$Child_Poverty_Basis[1])) poverty <- paste(poverty, "(surrounding district)")
      poverty_range <- format_poverty_range(row$Child_Poverty_Low[1], row$Child_Poverty_High[1])
      if (!is.na(row$Child_Poverty_Rate[1]) && !is.na(poverty_range)) poverty <- paste0(poverty, " (", poverty_range, ")")
      frl <- if (!is.na(row$Free_Reduced_Lunch_Share[1])) paste0(scales::percent(row$Free_Reduced_Lunch_Share[1], accuracy = 1), " (", row$FRL_Year[1], ")") else "N/A"
      if (!is.na(row$Free_Reduced_Lunch_Share[1]) && row$Free_Reduced_Lunch_Share[1] >= 0.995) frl <- paste(frl, "-- every student counted (likely free meals for all)")

      column(
        width = col_width,
        div(
          class = "box box-solid box-primary",
          style = "border-top: 3px solid #2a78d6; box-shadow: 0 1px 3px rgba(0,0,0,0.08); margin-bottom: 20px;",
          div(
            class = "box-header with-border", style = "background: #f7f9fa; padding: 10px 15px;",
            h4(style = "margin: 0; font-size: 15px; font-weight: 600; color: #222;", dname),
            tags$small(class = "text-muted", paste0(row$County[1], " County"))
          ),
          div(
            class = "box-body", style = "padding: 15px;",
            fluidRow(
              column(6, div(style = "text-align: center; border-right: 1px solid #eee;",
                           div(style = "font-size: 22px; font-weight: 700; color: #2a78d6;", row$CurrentCount[1]),
                           div(style = "font-size: 11px; text-transform: uppercase; color: #777;", "Active Openings"))),
              column(6, div(style = "text-align: center;",
                           div(style = "font-size: 22px; font-weight: 700; color: #e67e22;", vac_rate),
                           div(style = "font-size: 11px; text-transform: uppercase; color: #777;", "Vacancy Rate")))
            ),
            tags$hr(style = "margin: 12px 0;"),
            tags$table(
              style = "width: 100%; font-size: 13px; line-height: 1.8;",
              tags$tr(tags$td(class = "text-muted", "Teacher Avg Salary:"), tags$td(style = "text-align: right; font-weight: 600;", avg_sal)),
              tags$tr(tags$td(class = "text-muted", "Salary Band (10th-90th):"), tags$td(style = "text-align: right; font-weight: 600; font-size: 11.5px;", band_sal)),
              tags$tr(tags$td(class = "text-muted", "Enrollment:"), tags$td(style = "text-align: right; font-weight: 600;", enroll)),
              tags$tr(tags$td(class = "text-muted", "Students / Teacher:"), tags$td(style = "text-align: right; font-weight: 600;", spt)),
              tags$tr(tags$td(class = "text-muted", "General Fund Budget:"), tags$td(style = "text-align: right; font-weight: 600;", gen_fund)),
              tags$tr(tags$td(class = "text-muted", "County Median Rent:"), tags$td(style = "text-align: right; font-weight: 600;", rent)),
              tags$tr(tags$td(class = "text-muted", "Children in Poverty (Census est.):"), tags$td(style = "text-align: right; font-weight: 600;", poverty)),
              tags$tr(tags$td(class = "text-muted", "Free/Reduced Lunch:"), tags$td(style = "text-align: right; font-weight: 600;", frl))
            )
          )
        )
      )
    })
    fluidRow(cards)
  })

  output$k12_compare_salary_plot <- renderPlotly({
    selected <- input$k12_compare_districts
    if (is.null(selected) || length(selected) == 0) {
      return(plot_ly(type = "scatter", mode = "none") %>% layout(
        annotations = list(list(text = "Select one or more districts to display salary comparison",
                                showarrow = FALSE, font = list(size = 14, color = "#666"))),
        xaxis = list(visible = FALSE), yaxis = list(visible = FALSE)
      ))
    }
    df <- combined_map_data %>%
      filter(Type == "K-12 District", Name %in% selected) %>%
      select(Name, Enrollment, Teacher_Avg_Salary, Median_Household_Income) %>%
      # Same district order as the enrollment and openings charts.
      arrange(desc(coalesce(Enrollment, -1)), Name) %>%
      mutate(Name = factor(Name, levels = Name))
    
    plot_ly(df, x = ~Name) %>%
      add_bars(y = ~Teacher_Avg_Salary, name = "Teacher Avg Salary (MT DLI)", marker = list(color = "#4a90e2")) %>%
      add_bars(y = ~Median_Household_Income, name = "County Median Household Income", marker = list(color = "#50e3c2")) %>%
      layout(
        barmode = "group",
        xaxis = list(title = "", tickangle = -15),
        yaxis = list(title = "Annual Compensation ($)", tickformat = "$,.0f"),
        legend = list(orientation = "h", x = 0, y = 1.15),
        margin = list(b = 60, l = 60, r = 20, t = 40)
      )
  })


  # -------- Combined map (Introduction tab) --------
  output$combined_map <- renderLeaflet({
    leaflet() %>%
      # Basemaps with open terms, OpenStreetMap first (Mike, 2026-11-15; claude-notes/2026-11-15_basemap-options.md).
      # Esri's tiles were dropped: its terms need Esri software or an ArcGIS
      # Online subscription for use like this. USGS The National Map is public
      # domain ("There are no restrictions"), with an acknowledgment requested;
      # OpenStreetMap needs its credit, which addTiles() shows by default.
      # OSM's tile policy: "https://tile.openstreetmap.org/{z}/{x}/{y}.png" exactly
      # (Leaflet's default still uses the old a/b/c subdomains).
      addTiles(
        urlTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        attribution = '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> contributors',
        options = tileOptions(maxZoom = 19),
        group = "OpenStreetMap (Default)"
      ) %>%
      addTiles(
        urlTemplate = "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}",
        attribution = USGS_TILE_CREDIT,
        options = tileOptions(maxZoom = 16),
        group = "USGS National Map"
      ) %>%
      addTiles(
        urlTemplate = "https://basemap.nationalmap.gov/arcgis/rest/services/USGSShadedReliefOnly/MapServer/tile/{z}/{y}/{x}",
        attribution = USGS_TILE_CREDIT,
        options = tileOptions(maxZoom = 16),
        group = "Shaded Relief"
      ) %>%
      addTiles(
        urlTemplate = "https://basemap.nationalmap.gov/arcgis/rest/services/USGSHydroCached/MapServer/tile/{z}/{y}/{x}",
        options = tileOptions(maxZoom = 16),
        group = "Shaded Relief"
      ) %>%
      setView(lng = -111.5, lat = 46.8, zoom = 7) %>%
      addLayersControl(
        baseGroups = c("OpenStreetMap (Default)", "USGS National Map", "Shaded Relief"),
        options = layersControlOptions(collapsed = TRUE)
      ) %>%
      addLegend(position = "bottomright", pal = vacancy_rate_palette, values = vacancy_rate_domain,
                title = "Vacancy rate", labFormat = labelFormat(suffix = "%", transform = function(x) 100 * x),
                na.label = "N/A")
  })
  outputOptions(output, "combined_map", suspendWhenHidden = FALSE)


  observeEvent(input$map_county, {
    if (is.null(input$map_county) || input$map_county == "all") {
      leafletProxy("combined_map") %>%
        setView(lng = -111.5, lat = 46.8, zoom = 7)
    } else {
      county_data <- combined_map_data %>%
        filter(County == input$map_county, !is.na(Latitude), !is.na(Longitude))
      if (nrow(county_data) > 0) {
        if (nrow(county_data) == 1) {
          leafletProxy("combined_map") %>%
            setView(lng = county_data$Longitude[1], lat = county_data$Latitude[1], zoom = 9)
        } else {
          leafletProxy("combined_map") %>%
            fitBounds(
              lng1 = min(county_data$Longitude) - 0.15,
              lat1 = min(county_data$Latitude) - 0.15,
              lng2 = max(county_data$Longitude) + 0.15,
              lat2 = max(county_data$Latitude) + 0.15
            )
        }
      }
    }
  }, ignoreInit = TRUE)

  observe({
    df <- map_filtered()

    # Clear unconditionally so unchecking every map-type box empties the map,
    # then bail before with(df, paste0(...)) runs on a 0-row frame (harmless
    # today -- addCircleMarkers iterates off lng/lat length so a mismatched
    # length-1 popup vector is never read -- but an explicit guard so a
    # reader doesn't have to re-derive that; matches the he_scroll observer).
    proxy <- leafletProxy("combined_map", data = df) %>% clearMarkers()
    qcew_row <- match(sub(",.*$", "", trimws(as.character(df$County))), qcew_school_pay$County)
    df$School_Pay_County <- ifelse(df$Type == "K-12 District", qcew_school_pay$Avg_Annual_Pay[qcew_row], NA_real_)
    df$School_Pay_Year <- qcew_school_pay$Year[qcew_row]
    if (nrow(df) == 0) return()

    # Informative hover tooltip labels
    labels <- with(df, sprintf(
      "<strong>%s</strong><br/>%s%s%s",
      Name,
      ifelse(SearchActive,
             sprintf("<span style='color:#198754;font-weight:600;'>🎯 %d matching opening%s for \"%s\"</span><br/>",
                     DisplayCount, ifelse(DisplayCount == 1, "", "s"), SearchQuery),
             sprintf("%d active opening%s<br/>", CurrentCount, ifelse(CurrentCount == 1, "", "s"))),
      ifelse(!is.na(Vacancy_Rate), sprintf("Vacancy rate: %.1f%%<br/>", Vacancy_Rate * 100), ""),
      "<span style='color:#666;font-size:11px;'>Click marker for details & jobs</span>"
    )) %>% lapply(HTML)

    popups <- with(df, paste0(
      "<div><strong>", Name, "</strong><br/>", ifelse(!is.na(Campus_Of), "Higher Ed campus or site", Type), "</div>",
      ifelse(SearchActive,
             paste0("<div style='margin:4px 0;background:#e8f5e9;color:#2e7d32;padding:3px 8px;border-radius:4px;font-weight:600;font-size:0.9em;'>",
                    "🎯 ", DisplayCount, " matching opening", ifelse(DisplayCount == 1, "", "s"),
                    " for &ldquo;", SearchQuery, "&rdquo; (out of ", CurrentCount, " total)</div>",
                    ifelse(nzchar(MatchingSample), paste0("<div style='margin-bottom:4px;font-size:0.85em;'><strong>Matching:</strong> ", MatchingSample, "</div>"), "")),
             ""),
      # Visible badge, not just a code comment -- Data_Coverage is "Full" for
      # every district on a real structured job-board platform this project
      # scrapes via a documented API (AppliTrack/SchoolSpring/TedK12/Tyler
      # Portico); "Partial" comes from k12_district_coverage_tiers() in
      # misc_district_scrapers.R for every other directly-scraped district
      # (a heuristic single-page scrape of the district's own site instead).
      # HE institutions carry Data_Coverage = NA (no tier designed for HE
      # yet) -- guarded explicitly so an NA never reaches this ifelse as a
      # bare comparison (NA != "Full" is NA, not FALSE, which would inject a
      # literal "NA" badge onto every HE marker rather than showing nothing).
      ifelse(!SearchActive & !is.na(Data_Coverage) & Data_Coverage != "Full",
             paste0("<div style='margin:2px 0;'><span style='background:#fdecea;color:#a92f1e;",
                    "font-size:0.78em;font-weight:bold;padding:1px 6px;border-radius:8px;'>",
                    Data_Coverage, "</span></div>"),
             ""),
      "<div>Current openings: <strong>", CurrentCount, "</strong></div>",
      ifelse(!is.na(Campus_Note), paste0("<div style='font-size:0.85em;color:#666;'>", Campus_Note, "</div>"), ""),
      "<div>New this week: ", WeeklyNew, "</div>",
      ifelse(!is.na(Vacancy_Rate),
             paste0("<div>", ifelse(Type == "K-12 District", "Teacher", "Faculty"),
                    " vacancy rate: ", scales::percent(Vacancy_Rate, accuracy = 0.1), "</div>"),
             ""),
      ifelse(!SearchActive & nzchar(SampleTitles), paste0("<div>Recent postings: ", SampleTitles, "</div>"), ""),
      ifelse(!is.na(Students_Per_Teacher),
             paste0("<div>Students per ", ifelse(Type == "K-12 District", "teacher", "faculty member"), ": ",
                    sprintf("%.1f", Students_Per_Teacher),
                    " (", format(Enrollment, big.mark = ","), " students)</div>"),
             ""),
      ifelse(!is.na(Enrollment_Change_Pct),
             paste0("<div>Enrollment trend (5yr): ", ifelse(Enrollment_Change_Pct >= 0, "+", ""),
                    scales::percent(Enrollment_Change_Pct, accuracy = 0.1), "</div>"),
             ""),
      ifelse(!is.na(Pell_Recipient_Share),
             paste0("<div>Pell Grant recipients: ", scales::percent(Pell_Recipient_Share, accuracy = 0.1),
                    " of students (", Pell_Year, ")</div>"),
             ""),
      ifelse(!is.na(Teacher_Avg_Salary),
             paste0("<div>Teacher avg salary: ", scales::dollar(Teacher_Avg_Salary),
                    ifelse(!is.na(Teacher_Salary_10th_Pctile) & !is.na(Teacher_Salary_90th_Pctile),
                           paste0(" (", scales::dollar(Teacher_Salary_10th_Pctile), " - ",
                                  scales::dollar(Teacher_Salary_90th_Pctile), ")"),
                           ""),
                    " &middot; ", Salary_Year, "</div>"),
             ""),
      ifelse(!is.na(Faculty_Avg_Salary),
             paste0("<div>Avg. salary, full-time instructional staff (IPEDS, 9–12-month contracts): ", scales::dollar(Faculty_Avg_Salary),
                    ifelse(!is.na(Faculty_Avg_Salary_Professor),
                           paste0(" (Professor rank: ", scales::dollar(Faculty_Avg_Salary_Professor), ")"),
                           ""),
                    " &middot; ", Salary_Year, "</div>"),
             ""),
      ifelse(!is.na(Salary_Source),
             paste0("<div style='font-size:0.85em;color:#666;'>Salary source: ", Salary_Source, "</div>"),
             ""),
      ifelse(!is.na(Median_Household_Income),
             paste0("<div style='font-size:0.85em;color:#666;margin-top:4px;'>County: median income ",
                    scales::dollar(Median_Household_Income), format_moe_dollars(Median_Household_Income_MOE),
                    ", median rent ", scales::dollar(Median_Gross_Rent), "/mo", format_moe_dollars(Median_Gross_Rent_MOE),
                    ifelse(!is.na(Mining_Employment_Share) & Mining_Employment_Share >= 0.05,
                           paste0(", ", scales::percent(Mining_Employment_Share, accuracy = 1), format_moe_points(Mining_Employment_Share_MOE),
                                  " of jobs in mining/energy"),
                           ""),
                    "</div>"),
             ""),
      ifelse(!is.na(Child_Poverty_Rate),
             paste0("<div style='font-size:0.85em;color:#666;'>",
                    ifelse(is.na(Child_Poverty_Basis), "District: ", ""),
                    scales::percent(Child_Poverty_Rate, accuracy = 0.1), " of school-age children in poverty (Census est.",
                    ifelse(is.na(Child_Poverty_Low) | is.na(Child_Poverty_High), "",
                           paste0("; ", format_poverty_range(Child_Poverty_Low, Child_Poverty_High))), ")",
                    ifelse(is.na(Child_Poverty_Basis), "", paste0(" (", sub("^Surrounding", "surrounding", Child_Poverty_Basis), ")")),
                    "</div>"),
             ""),
      ifelse(!is.na(Free_Reduced_Lunch_Share),
             paste0("<div style='font-size:0.85em;color:#666;'>",
                    scales::percent(Free_Reduced_Lunch_Share, accuracy = 1),
                    " of students eligible for free/reduced-price lunch (", FRL_Year, ")",
                    ifelse(Free_Reduced_Lunch_Share >= 0.995, " -- every student counted (likely free meals for all)", ""),
                    "</div>"),
             ""),
      ifelse(!is.na(School_Pay_County),
             paste0("<div style='font-size:0.85em;color:#666;'>", sub(",.*$", "", County),
                    " public school employees averaged ", scales::dollar(School_Pay_County, accuracy = 1),
                    " in ", School_Pay_Year, " (all roles; BLS QCEW)</div>"),
             ""),
      "<div style='margin-top:6px;'>",
      "<a href='", Link, "' target='_blank'>Careers page</a>",
      " &nbsp;|&nbsp; ",
      # Carries the active map search with it, so the Jobs tab opens on just
      # the postings this popup counted. URL-encoded so quotes in the query
      # can't break out of the JS string.
      "<a href='#' onclick=\"Shiny.setInputValue('map_popup_view_jobs', {entity: '",
      gsub("'", "&#39;", Name, fixed = TRUE),
      "', query: '",
      ifelse(SearchActive,
             vapply(coalesce(SearchKeyword, ""), utils::URLencode, character(1), reserved = TRUE, USE.NAMES = FALSE),
             ""),
      "', band: '", ifelse(SearchActive, SearchBand, ""),
      "'}, {priority: 'event'}); return false;\">",
      ifelse(SearchActive,
             paste0("View ", DisplayCount, " matching job", ifelse(DisplayCount == 1, "", "s")),
             "View all jobs"),
      " &rarr;</a>",
      "</div>"
    ))

    proxy %>%
      addCircleMarkers(
        lng = ~Longitude, lat = ~Latitude,
        radius = ~map_marker_radius(DisplayCount),
        fillColor = ~vacancy_rate_palette(Vacancy_Rate),
        color = "#333333", weight = 1,
        fillOpacity = 0.85,
        layerId = ~Name,
        label = labels,
        labelOptions = labelOptions(
          style = list("font-weight" = "normal", padding = "4px 8px"),
          textsize = "12px",
          direction = "auto"
        ),
        popup = popups
      )
  })


  output$k12_slider_label <- renderText({
    req(input$k12_scroll)
    paste(
      c(
        timeline_history_note(k12sum$Archive_Date),
        paste0("Showing: ", input$k12_scroll[1], " to ", input$k12_scroll[2])
      )[nzchar(c(
        timeline_history_note(k12sum$Archive_Date),
        paste0("Showing: ", input$k12_scroll[1], " to ", input$k12_scroll[2])
      ))],
      collapse = " "
    )
  })


  output$he_summary_table <- renderDT({
    he_rows <- combined_map_data %>% filter(Type == "Higher Ed Institution")
    appointment_counts <- ccdata %>%
      count(Institution, Appointment, name = "Openings") %>%
      tidyr::complete(
        Institution,
        Appointment = c("Faculty/instructor (non-adjunct)", "Adjunct/part-time faculty"),
        fill = list(Openings = 0L)
      ) %>%
      tidyr::pivot_wider(names_from = Appointment, values_from = Openings, values_fill = 0)
    year <- unique(na.omit(he_rows$Salary_Year))
    year_label <- if (length(year) > 0) year[1] else "current"
    year_int <- suppressWarnings(as.integer(year_label))
    y1_label <- if (!is.na(year_int)) as.character(year_int - 1) else "1 year ago"
    y2_label <- if (!is.na(year_int)) as.character(year_int - 2) else "2 years ago"

    df <- he_rows %>%
      left_join(appointment_counts, by = c("Name" = "Institution")) %>%
      arrange(desc(CurrentCount)) %>%
      transmute(
        Institution = Name,
        County,
        `Current Openings` = CurrentCount,
        `Faculty/instructor (non-adjunct)` = coalesce(`Faculty/instructor (non-adjunct)`, 0L),
        `Adjunct/part-time faculty` = coalesce(`Adjunct/part-time faculty`, 0L),
        `New This Week` = WeeklyNew,
        `Faculty Vacancy Rate` = ifelse(is.na(Vacancy_Rate), NA_character_, scales::percent(Vacancy_Rate, accuracy = 0.1)),
        AvgFacultySalary = ifelse(is.na(Faculty_Avg_Salary), NA_character_, scales::dollar(Faculty_Avg_Salary)),
        AvgFacultySalaryY1 = ifelse(is.na(Faculty_Avg_Salary_Y1Ago), NA_character_, scales::dollar(Faculty_Avg_Salary_Y1Ago)),
        AvgFacultySalaryY2 = ifelse(is.na(Faculty_Avg_Salary_Y2Ago), NA_character_, scales::dollar(Faculty_Avg_Salary_Y2Ago)),
        ProfessorAvgSalary = ifelse(is.na(Faculty_Avg_Salary_Professor), NA_character_, scales::dollar(Faculty_Avg_Salary_Professor)),
        `Faculty Count` = Faculty_Count,
        Enrollment,
        `Students per Faculty` = ifelse(is.na(Students_Per_Teacher), NA_character_, sprintf("%.1f", Students_Per_Teacher)),
        `Enrollment Trend (5yr)` = ifelse(is.na(Enrollment_Change_Pct), NA_character_,
                                           paste0(ifelse(Enrollment_Change_Pct >= 0, "+", ""), scales::percent(Enrollment_Change_Pct, accuracy = 0.1))),
        `Pell Grant Recipient Share` = ifelse(is.na(Pell_Recipient_Share), NA_character_,
                                               paste0(scales::percent(Pell_Recipient_Share, accuracy = 0.1), " (", Pell_Year, ")")),
        `County Median Income` = ifelse(is.na(Median_Household_Income), NA_character_,
                                        paste0(scales::dollar(Median_Household_Income), format_moe_dollars(Median_Household_Income_MOE))),
        `County Median Rent` = ifelse(is.na(Median_Gross_Rent), NA_character_,
                                      paste0(scales::dollar(Median_Gross_Rent), "/mo", format_moe_dollars(Median_Gross_Rent_MOE))),
        `County Mining/Energy Jobs` = ifelse(is.na(Mining_Employment_Share), NA_character_,
                                             paste0(scales::percent(Mining_Employment_Share, accuracy = 0.1), format_moe_points(Mining_Employment_Share_MOE),
                                                    ifelse(indistinct_from_zero(Mining_Employment_Share, Mining_Employment_Share_MOE),
                                                           " (not distinguishable from 0)", ""))),
        `County Population Trend (5yr)` = ifelse(is.na(Population_Change_Pct), NA_character_,
                                                   paste0(ifelse(Population_Change_Pct >= 0, "+", ""), scales::percent(Population_Change_Pct, accuracy = 0.1)))
      )
    names(df)[names(df) == "AvgFacultySalary"] <- paste0("Avg. salary, full-time instructional staff (IPEDS, 9–12-month contracts), ", year_label)
    names(df)[names(df) == "AvgFacultySalaryY1"] <- paste0("Avg. salary, full-time instructional staff (IPEDS, 9–12-month contracts), ", y1_label)
    names(df)[names(df) == "AvgFacultySalaryY2"] <- paste0("Avg. salary, full-time instructional staff (IPEDS, 9–12-month contracts), ", y2_label)
    names(df)[names(df) == "ProfessorAvgSalary"] <- paste0("Professor Avg Salary (", year_label, ")")

    datatable(df, filter = "top", extensions = "Buttons",
              options = list(scrollX = TRUE, dom = "Bfrtip", buttons = c("copy", "csv", "print"), pageLength = 6))
  })


  observe({
    df <- filtered_hesum()
    req(nrow(df) > 0)

    df$Archive_Date <- as.Date(df$Archive_Date)
    he_dates <- sort(unique(df$Archive_Date))

    updateSliderInput(
      session,
      "he_scroll",
      min = min(he_dates),
      max = max(he_dates),
      value = bounded_timeline_value(he_dates, days = WINDOW_WEEKS * 7),
      timeFormat = "%Y-%m-%d"
    )

    session$userData$he_dates <- he_dates
  })


  output$he_slider_label <- renderText({
    req(input$he_scroll)
    paste(
      c(
        timeline_history_note(hesum_he$Archive_Date),
        paste0("Showing: ", input$he_scroll[1], " to ", input$he_scroll[2])
      )[nzchar(c(
        timeline_history_note(hesum_he$Archive_Date),
        paste0("Showing: ", input$he_scroll[1], " to ", input$he_scroll[2])
      ))],
      collapse = " "
    )
  })


}

shinyApp(ui = ui, server = server)
