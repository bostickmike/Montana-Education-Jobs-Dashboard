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

#--------------------------------------------------
# Schema guard -- ported from Wyoming's app.R verbatim (state-agnostic). Any
# dataset actually missing an expected column gets that column backfilled
# with NA so downstream mutate/select references don't hard-crash the whole
# app, and the problem is recorded in DATA_LOAD_ISSUES for a visible
# Home-tab banner instead of a silent blank field or an opaque stack trace.
#--------------------------------------------------
DATA_LOAD_ISSUES <- character(0)

validate_and_pad_schema <- function(df, required_cols, source_name) {
  missing <- setdiff(required_cols, names(df))
  if (length(missing) > 0) {
    DATA_LOAD_ISSUES <<- c(DATA_LOAD_ISSUES, sprintf(
      "%s is missing expected column(s): %s. That data will show blank until the pipeline is fixed.",
      source_name, paste(missing, collapse = ", ")
    ))
    for (col in missing) df[[col]] <- NA
  }
  df
}

# The repository pipeline classifies these same title patterns in
# k12_he_classification.R. Keep the deployed app self-contained while the
# dashboard distinguishes appointment type without inferring FTE where a
# source does not explicitly provide it.
classify_he_appointment <- function(titles) {
  titles <- as.character(titles)
  dplyr::case_when(
    grepl("Adjunct|Part[- ]?Time", titles, ignore.case = TRUE) ~ "Adjunct/part-time faculty",
    grepl("Instructor|Instructional|Teacher|Faculty|Professor|Lecturer|Post Doc|Subject Matter Expert|Librarian|Educator",
          titles, ignore.case = TRUE) ~ "Faculty/instructor (non-adjunct)",
    TRUE ~ "Other / not faculty"
  )
}

summarize_he_faculty_postings <- function(titles) {
  appointment <- classify_he_appointment(titles)
  list(
    faculty_instructor = sum(appointment == "Faculty/instructor (non-adjunct)", na.rm = TRUE),
    adjunct_part_time = sum(appointment == "Adjunct/part-time faculty", na.rm = TRUE)
  )
}

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

# Sources that keep evergreen pools active may retain an original posting
# date for years. Make that distinction visible without discarding a still-
# open opportunity or inventing a newer date the source does not provide.
format_posted_or_listed_date <- function(dates, stale_after_days = 180) {
  values <- as.character(dates)
  parsed <- as.Date(lubridate::parse_date_time(
    values,
    orders = c("ymd", "mdy", "dmy", "b d Y h:M p", "B d Y h:M p", "Y-m-d H:M:S"),
    tz = "UTC",
    quiet = TRUE
  ))
  stale <- !is.na(parsed) & parsed < Sys.Date() - stale_after_days
  values[stale] <- paste("Listed since", values[stale])
  values
}

# "Posted / listed" for a board that gives no posted date: the first weekly
# run that found the posting (posting_first_seen.csv, written by
# scripts/build_posting_spells.R; the key must match first_seen_key() in
# posting_spells.R). "On the board since at least" when the posting was
# already up the first time that board was scraped. Without the file (a
# deploy before the weekly run first writes it) the column is as before.
first_seen_key <- function(district, title, url) {
  sq <- function(x) tolower(gsub("\\s+", " ", trimws(as.character(x))))
  paste(sq(district), sq(title), trimws(as.character(url)), sep = " | ")
}
first_seen_table <- tryCatch(read.csv("posting_first_seen.csv", colClasses = "character", fileEncoding = "UTF-8"),
                             error = function(e) NULL, warning = function(w) NULL)
fill_first_seen <- function(posted, district, title, url, segment, lookup = first_seen_table) {
  posted <- as.character(posted)
  if (is.null(lookup) || !all(c("Segment", "Key", "First_Seen", "Left_Censored") %in% names(lookup))) return(posted)
  lookup <- lookup[lookup$Segment == segment, , drop = FALSE]
  k <- match(first_seen_key(district, title, url), lookup$Key)
  blank <- is.na(posted) | !nzchar(trimws(posted))
  seen <- lookup$First_Seen[k]
  label <- ifelse(lookup$Left_Censored[k] %in% "TRUE", paste("On the board since at least", seen), paste("First seen", seen))
  ifelse(blank & !is.na(k) & !is.na(seen) & nzchar(seen), label, posted)
}
POSTED_LISTED_NOTE <- paste0(
  "Posted / listed is the date the posting gives. Where the job board gives none, it shows the first week this ",
  "dashboard found the posting (\"First seen\"), or \"On the board since at least\" when the posting was already up ",
  "the first time we checked that board. ")

# Pay as the posting itself states it (Pay_* from extract_posted_pay() in the
# pipeline): "$21.46–$22.81/hr", "$46,500–$71,803/yr", "$3,691 stipend".
# Units are never converted -- an hourly wage isn't turned into an annual
# figure, since hours per year aren't known.
format_posted_pay <- function(pay_min, pay_max, pay_unit) {
  fmt <- function(x) ifelse(x >= 1000, scales::dollar(x, accuracy = 1), scales::dollar(x, accuracy = 0.01))
  amount <- ifelse(is.na(pay_min), NA_character_,
                   ifelse(is.na(pay_max) | pay_min == pay_max, fmt(pay_min), paste0(fmt(pay_min), "\u2013", fmt(pay_max))))
  suffix <- unname(c(hour = "/hr", day = "/day", month = "/mo", year = "/yr",
                     "credit hour" = "/credit hr", stipend = " stipend")[pay_unit])
  ifelse(is.na(amount), "\u2014", paste0(amount, ifelse(is.na(suffix), "", suffix)))
}

# BLS OEWS regional median for the posting's role (Est_* from
# attach_oews_estimates() in the pipeline), shown only where the posting
# states no pay: "$34,750/yr", with the role and area in a hover tooltip
# ("BLS median for teaching assistants, West Montana nonmetro").
format_bls_estimate <- function(est_pay, est_unit, occupation, area, has_posted_pay) {
  format_pay_estimate(est_pay, est_unit, paste0("BLS median for ", tolower(occupation), ", ", area), has_posted_pay)
}

# Same for higher-ed staff postings: the institution's IPEDS average for the
# posting's staff category ("IPEDS average for full-time management staff,
# Montana State University").
format_ipeds_estimate <- function(est_pay, est_unit, category, institution, has_posted_pay) {
  format_pay_estimate(est_pay, est_unit, paste0("IPEDS average for full-time ", category, " staff, ", institution),
                      has_posted_pay)
}

format_pay_estimate <- function(est_pay, est_unit, tooltip, has_posted_pay) {
  show <- !has_posted_pay & !is.na(est_pay)
  tip <- htmltools::htmlEscape(tooltip, attribute = TRUE)
  ifelse(show,
         paste0("<span title=\"", tip, "\" style=\"border-bottom: 1px dotted #888; cursor: help;\">",
                format_posted_pay(est_pay, est_pay, est_unit), "</span>"),
         "\u2014")
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
in_pay_band <- function(value, unit, band) {
  if (is.null(band) || !band %in% names(PAY_BANDS)) return(rep(TRUE, length(value)))
  b <- PAY_BANDS[[band]]
  !is.na(value) & !is.na(unit) & unit == b$unit & value >= b$lo & value < b$hi
}

# The figure a posting is filtered on: its posted pay (midpoint of a range)
# when stated by the hour or year; nothing when stated in another unit (a
# day rate or stipend is the posting's own figure, so no estimate replaces
# it); otherwise the fallback the caller supplies (district role figure, then
# the BLS estimate).
posting_pay_value <- function(pay_min, pay_max, pay_unit, fallback_value, fallback_unit) {
  posted <- !is.na(pay_min)
  filterable <- posted & pay_unit %in% c("hour", "year")
  data.frame(
    value = ifelse(filterable, (pay_min + coalesce(pay_max, pay_min)) / 2, ifelse(posted, NA_real_, fallback_value)),
    unit = ifelse(filterable, pay_unit, ifelse(posted, NA_character_, fallback_unit)),
    stringsAsFactors = FALSE
  )
}

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
              "Est_Pay", "Est_Pay_Unit", "Est_Occupation", "Est_Area", "Est_Year")) {
  if (!col %in% names(combineddata)) combineddata[[col]] <- NA
}
oews_year <- na.omit(combineddata$Est_Year)[1]
combineddata <- combineddata %>%
  validate_and_pad_schema(c("District", "title", "position", "location", "date_posted", "url",
                            "Posting_Source", "Posting_Identity_Method", "Posting_ID"),
                          "combinedclean.csv") %>%
  mutate(`Posted Pay` = format_posted_pay(Pay_Min, Pay_Max, Pay_Unit),
         `Typical pay (BLS est.)` = format_bls_estimate(Est_Pay, Est_Pay_Unit, Est_Occupation, Est_Area, !is.na(Pay_Min))) %>%
  select(District, title, position, location, `Posted Pay`, `Typical pay (BLS est.)`, date_posted, url,
         Posting_Source, Posting_Identity_Method, Posting_ID, Also_On_Feed, Pay_Min, Pay_Max, Pay_Unit, Est_Pay, Est_Pay_Unit) %>%
  # A direct posting OPI also lists (counted once, from our scrape).
  mutate(Posting_Source = ifelse(Also_On_Feed %in% c(TRUE, "TRUE"), paste0(Posting_Source, " \u00b7 also on OPI"), Posting_Source)) %>%
  distinct(Posting_ID, .keep_all = TRUE) %>%
  mutate(District = str_squish(as.character(District))) %>%
  mutate(date_posted = format_posted_or_listed_date(date_posted)) %>%
  mutate(date_posted = fill_first_seen(date_posted, District, title, url, "K-12")) %>%
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
for (col in c("Child_Poverty_Basis", "Free_Reduced_Lunch_Share", "FRL_Year")) {
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
                           "salarymap2.csv") %>%
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
         .Pay_Value, .Pay_Unit)

# Weekly ALL-category posting totals per district/institution -- powers the
# sparkline trend next to each entity's raw count on the Top Hiring tables.
k12_district_weekly_totals <- read.csv("k12_district_weekly_totals.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("District", "Archive_Date", "n"), "k12_district_weekly_totals.csv") %>%
  # An employer whose map row covers several posting names counts once.
  mutate(Archive_Date = as.Date(Archive_Date), District = relabel_employer(District)) %>%
  group_by(District, Archive_Date) %>%
  summarise(n = sum(n), .groups = "drop")
he_institution_weekly_totals <- read.csv("he_institution_weekly_totals.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("Institution", "Archive_Date", "n"), "he_institution_weekly_totals.csv") %>%
  mutate(Archive_Date = as.Date(Archive_Date))

data_dictionary <- if (file.exists("data_dictionary.csv")) {
  read.csv("data_dictionary.csv", stringsAsFactors = FALSE)
} else {
  data.frame(Dataset = character(0), File_Name = character(0), Column_Name = character(0),
             Data_Type = character(0), Primary_Authority = character(0), Definition = character(0))
}

# Listing-duration ("spells") tabs: the duration KPIs and charts are paused
# (2026-11-02 audit, claude-notes/2026-11-02_spells-trust-audit.md). A spell
# is a District + title's first-to-last week on our weekly scrapes, and most
# spell endings and starts come from our own coverage (scrapers added, broken
# or switched) rather than from hiring, so they can't be read as
# time-to-fill. The table stays, labeled for what it is.
spells_paused_note <- function(what) {
  div(class = "alert alert-warning mb-3", role = "note",
      tags$strong("Time-to-fill estimates are paused while we rebuild them. "),
      paste0("This table shows how long each ", what, " stayed listed on the boards we track, from the first to the last ",
             "week we saw it. That is not the same as time-to-fill: a posting can drop off because it was filled, ",
             "cancelled, moved to another board, or because our collection missed that week, and many were already ",
             "listed before we started tracking their board. \u201cNo longer listed\u201d means only that it no longer appears."))
}
SPELL_STATUS_LABELS <- c("Closed / Filled" = "No longer listed")
relabel_spell_status <- function(df) {
  if (nrow(df) > 0 && "Status" %in% names(df)) {
    hit <- df$Status %in% names(SPELL_STATUS_LABELS)
    df$Status[hit] <- SPELL_STATUS_LABELS[df$Status[hit]]
  }
  df
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

# Tiny inline trend chart (no axes/legend, just the shape of a trend) for
# the Top Hiring tables and KPI tiles -- ported verbatim from Wyoming's
# app.R, state-agnostic (pure SVG templating over a numeric series).
make_sparkline_svg <- function(series, accent = "#2a78d6") {
  series <- series[!is.na(series)]
  if (length(series) < 2) return("")

  w <- 96; h <- 28; pad <- 3
  rng <- range(series)
  span <- diff(rng)
  if (span == 0) span <- 1

  n <- length(series)
  step_x <- (w - pad * 2) / (n - 1)
  xs <- pad + (seq_len(n) - 1) * step_x
  ys <- pad + (1 - (series - rng[1]) / span) * (h - pad * 2)

  line_path <- paste0(ifelse(seq_along(xs) == 1, "M", "L"), round(xs, 1), ",", round(ys, 1), collapse = " ")
  area_path <- paste0(line_path, " L", round(xs[n], 1), ",", h - pad, " L", round(xs[1], 1), ",", h - pad, " Z")

  dot_color <- if (series[n] > series[1]) "#1baf7a" else if (series[n] < series[1]) "#e34948" else "#999999"

  sprintf(
    '<svg width="%d" height="%d" viewBox="0 0 %d %d" style="vertical-align:middle;"><path d="%s" fill="%s22" stroke="none"></path><path d="%s" fill="none" stroke="%s" stroke-width="1.75" stroke-linejoin="round" stroke-linecap="round"></path><circle cx="%s" cy="%s" r="2.5" fill="%s"></circle></svg>',
    w, h, w, h, area_path, accent, line_path, accent, round(xs[n], 1), round(ys[n], 1), dot_color
  )
}

# Larger, monochrome-white variant for the KPI tiles' icon slot.
make_sparkline_svg_light <- function(series) {
  series <- series[!is.na(series)]
  if (length(series) < 2) return("")

  w <- 160; h <- 80; pad <- 6
  rng <- range(series)
  span <- diff(rng)
  if (span == 0) span <- 1

  n <- length(series)
  step_x <- (w - pad * 2) / (n - 1)
  xs <- pad + (seq_len(n) - 1) * step_x
  ys <- pad + (1 - (series - rng[1]) / span) * (h - pad * 2)

  line_path <- paste0(ifelse(seq_along(xs) == 1, "M", "L"), round(xs, 1), ",", round(ys, 1), collapse = " ")
  area_path <- paste0(line_path, " L", round(xs[n], 1), ",", h - pad, " L", round(xs[1], 1), ",", h - pad, " Z")

  sprintf(
    '<svg width="%d" height="%d" viewBox="0 0 %d %d"><path d="%s" fill="rgba(255,255,255,0.18)" stroke="none"></path><path d="%s" fill="none" stroke="rgba(255,255,255,0.85)" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"></path><circle cx="%s" cy="%s" r="3.5" fill="#ffffff"></circle></svg>',
    w, h, w, h, area_path, line_path, round(xs[n], 1), round(ys[n], 1)
  )
}

# Current Trends table -- one row per category: current count, a 12-week
# sparkline, and delta vs month/quarter/year ago. Ported verbatim from
# Wyoming's app.R (state-agnostic: works off whatever history it's given,
# will just show flat/NA deltas until Montana's pipeline has accumulated
# enough real weekly history -- see this project's app-scope decision).
build_current_trends_table <- function(history, accent) {
  dates <- sort(unique(history$Archive_Date))
  if (length(dates) == 0) return(NULL)
  latest <- max(dates)

  nearest_on_or_before <- function(target) {
    candidates <- dates[dates <= target]
    if (length(candidates) == 0) return(NA)
    max(candidates)
  }
  month_ago <- nearest_on_or_before(latest - 28)
  quarter_ago <- nearest_on_or_before(latest - 90)
  year_ago <- nearest_on_or_before(latest - 365)

  current <- history %>%
    filter(Archive_Date == latest) %>%
    group_by(Category) %>%
    summarize(`Current Postings` = sum(n), .groups = "drop") %>%
    arrange(desc(`Current Postings`))
  if (nrow(current) == 0) return(NULL)

  value_at <- function(cat, date) {
    if (is.na(date)) return(NA_integer_)
    v <- history$n[history$Category == cat & history$Archive_Date == date]
    if (length(v) == 0) 0L else sum(v)
  }
  fmt_delta <- function(now, then) {
    if (is.na(then)) return("<span style='color:#999;'>—</span>")
    d <- now - then
    color <- if (d > 0) "#1baf7a" else if (d < 0) "#e34948" else "#999999"
    arrow <- if (d >= 0) "▲" else "▼"
    sprintf("<span style='color:%s;'>%s %d</span>", color, arrow, abs(d))
  }

  current$`Last 12 Weeks` <- vapply(current$Category, function(cat) {
    series <- history %>%
      filter(Category == cat) %>%
      group_by(Archive_Date) %>%
      summarize(n = sum(n), .groups = "drop") %>%
      arrange(Archive_Date) %>%
      tail(12) %>%
      pull(n)
    make_sparkline_svg(series, accent = accent)
  }, character(1))

  current$`vs Month Ago` <- mapply(function(cat, now) fmt_delta(now, value_at(cat, month_ago)),
                                    current$Category, current$`Current Postings`)
  current$`vs Quarter Ago` <- mapply(function(cat, now) fmt_delta(now, value_at(cat, quarter_ago)),
                                      current$Category, current$`Current Postings`)
  current$`vs Year Ago` <- mapply(function(cat, now) fmt_delta(now, value_at(cat, year_ago)),
                                   current$Category, current$`Current Postings`)

  current
}

# Statewide week-over-week delta for the KPI tiles -- ported verbatim.
# The weekly-totals downloads keep one snapshot per week (decided 2026-11-02):
# a week with an extra run (the August catch-up runs) would otherwise list
# every district twice. The latest snapshot in each ISO week wins.
latest_snapshot_per_week <- function(weekly_totals) {
  d <- as.Date(weekly_totals$Archive_Date)
  wk <- format(d, "%G-W%V")
  latest <- tapply(d, wk, max)
  weekly_totals[!is.na(d) & d == as.Date(latest[wk], origin = "1970-01-01"), , drop = FALSE]
}

compute_wow_delta <- function(weekly_totals, min_days_back = 5) {
  totals <- weekly_totals %>% group_by(Archive_Date) %>% summarize(n = sum(n), .groups = "drop") %>% arrange(Archive_Date)
  if (nrow(totals) < 2) return(NA_integer_)
  latest <- max(totals$Archive_Date)
  candidates <- totals$Archive_Date[totals$Archive_Date <= latest - min_days_back]
  if (length(candidates) == 0) return(NA_integer_)
  prior <- max(candidates)
  totals$n[totals$Archive_Date == latest] - totals$n[totals$Archive_Date == prior]
}

# "Biggest mover" -- ported verbatim. Needs a longer window than a week to
# mean anything (confirmed on Wyoming's real data; will read the same way
# once Montana's pipeline has a few weeks of history).
find_biggest_mover <- function(weekly_totals, name_col, min_days_back = 21) {
  dates <- sort(unique(weekly_totals$Archive_Date))
  if (length(dates) < 2) return(NULL)
  latest <- max(dates)
  candidates <- dates[dates <= latest - min_days_back]
  if (length(candidates) == 0) return(NULL)
  prior <- max(candidates)

  wide <- weekly_totals %>%
    filter(Archive_Date %in% c(latest, prior)) %>%
    tidyr::pivot_wider(names_from = Archive_Date, values_from = n, values_fill = 0)
  names(wide)[names(wide) == as.character(prior)] <- "Prior"
  names(wide)[names(wide) == as.character(latest)] <- "Latest"
  wide$Delta <- wide$Latest - wide$Prior

  top <- wide %>% arrange(desc(abs(Delta))) %>% slice(1)
  list(name = top[[name_col]], prior = top$Prior, latest = top$Latest, delta = top$Delta,
       prior_date = prior, latest_date = latest)
}

render_mover_box <- function(mover, label) {
  if (is.null(mover)) return(NULL)
  arrow <- if (mover$delta >= 0) "▲" else "▼"
  delta_color <- if (mover$delta >= 0) "#1baf7a" else "#e34948"
  card(card_body(
      class = "py-2",
      div(
        tags$span(style = "font-weight:bold;", paste0(label, ": ")),
        tags$span(mover$name),
        tags$span(style = paste0("color:", delta_color, "; font-weight:bold; margin-left:8px;"),
                   paste0(arrow, " ", abs(mover$delta))),
        tags$span(style = "color:#999; font-size:0.85em; margin-left:6px;",
                   paste0("(", mover$prior, " → ", mover$latest,
                          " since ", format(mover$prior_date, "%b %d"), ")"))
      )
  ))
}

# bslib value box with shinydashboard::valueBox()'s argument order, so the
# Time-to-Fill boxes kept their calls. Colors map onto Bootstrap theme names.
kpi_value_box <- function(value, subtitle, icon = NULL, color = "blue", ...) {
  theme <- switch(color, blue = "primary", green = "success", red = "danger",
                  purple = "purple", "primary")
  value_box(title = subtitle, value = value, showcase = icon, theme = theme, ...)
}

k12sum <- read.csv("allsum.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("Broad_Category", "Archive_Date", "District", "sum"), "allsum.csv") %>%
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

# A week with zero postings for a category is simply absent from the source
# aggregation, not an explicit 0 -- geom_line() would silently connect
# through the gap. tidyr::complete() fills every combination with a real 0.
k12sum <- k12sum %>%
  tidyr::complete(Broad_Category, Archive_Date, District, fill = list(sum = 0))


k12nowsum <- read.csv("allnow.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("Broad_Category", "Sum", "District"), "allnow.csv") %>%
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
              "Est_Pay", "Est_Pay_Unit", "Est_Occupation", "Est_Area", "Est_Year")) {
  if (!col %in% names(ccdata)) ccdata[[col]] <- NA
}
ccdata <- ccdata %>%
  validate_and_pad_schema(c("Institution", "Title", "Location", "Posted_Date", "Link"), "hedata.xlsx") %>%
  mutate(`Posted Pay` = format_posted_pay(Pay_Min, Pay_Max, Pay_Unit),
         `Typical pay (IPEDS est.)` = format_ipeds_estimate(Est_Pay, Est_Pay_Unit, Est_Occupation, Est_Area, !is.na(Pay_Min))) %>%
  select(Institution, Title, Location, `Posted Pay`, `Typical pay (IPEDS est.)`, Posted_Date, Link,
         Pay_Min, Pay_Max, Pay_Unit, Est_Pay, Est_Pay_Unit) %>%
  arrange(Institution, Title) %>%
  mutate(
    Appointment = classify_he_appointment(Title),
    Posted_Date = format_posted_or_listed_date(Posted_Date),
    Posted_Date = fill_first_seen(Posted_Date, Institution, Title, Link, "HE")
  ) %>%
  rename(`Posted / listed` = Posted_Date)
ccdata$Link <- paste0('<a href="', ccdata$Link, '" target="_blank">', ccdata$Link, '</a>')
he_faculty_counts <- summarize_he_faculty_postings(ccdata$Title)

mapdata2_he <- read.csv("salarymap.csv") %>%
  validate_and_pad_schema(c("Name", "Longitude", "Latitude", "Link", "Faculty_Avg_Salary",
                             "Faculty_Avg_Salary_Professor", "Faculty_Count", "Salary_Year",
                             "Salary_Source", "Faculty_Avg_Salary_Y1Ago", "Faculty_Avg_Salary_Y2Ago",
                             "County", "Median_Household_Income", "Median_Gross_Rent",
                             "Mining_Employment_Share", "Population_Change_Pct", "ACS_Year",
                             "Enrollment", "Enrollment_Change_Pct", "Pell_Recipient_Share", "Pell_Year"),
                           "salarymap.csv") %>%
  mutate(Salary_Year = as.character(Salary_Year), Pell_Year = as.character(Pell_Year))

# Institution faculty salary lookup for the Higher Ed Jobs Table
he_salary_lookup <- mapdata2_he %>%
  select(Name, Faculty_Avg_Salary) %>%
  mutate(
    `Avg Faculty Salary` = ifelse(
      is.na(Faculty_Avg_Salary),
      "—",
      scales::dollar(Faculty_Avg_Salary, accuracy = 1)
    )
  )

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
  select(Institution, Title, Location, Appointment, `Posted Pay`, `Typical pay (IPEDS est.)`, `Avg Faculty Salary`,
         `Posted / listed`, Link, .Pay_Value, .Pay_Unit)

hesum_he <- read.csv("allsum_he.csv") %>%
  validate_and_pad_schema(c("Category", "Archive_Date", "Institution", "Job_Type", "sum"), "allsum_he.csv") %>%
  filter(Category != "Uncategorized")

hesum_he$Archive_Date <- as.Date(hesum_he$Archive_Date)

hesum_he <- hesum_he %>%
  tidyr::complete(Category, Archive_Date, Institution, Job_Type, fill = list(sum = 0))
he_dates <- sort(unique(hesum_he$Archive_Date))
WINDOW_WEEKS <- 52
hesum_he$Category <- as.factor(hesum_he$Category)

henowsum_he <- read.csv("allnow_he.csv") %>%
  validate_and_pad_schema(c("Category", "Job_Type", "Sum", "Institution"), "allnow_he.csv") %>%
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
                          "k12jobanalysis.csv") %>%
  mutate(Archive_Date = as.Date(Archive_Date), District = relabel_employer(District))

k12_new_this_week <- find_k12_new_postings(k12_history)

he_history <- read.csv("facultydata.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("Title", "Location", "Institution", "Link", "Archive_Date", "Job_Type", "Category"), "facultydata.csv") %>%
  mutate(Archive_Date = as.Date(Archive_Date)) %>%
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
         Child_Poverty_Rate, SAIPE_Year, Child_Poverty_Basis, Free_Reduced_Lunch_Share, FRL_Year, Total_General_Fund_Expenditure, Finance_FY, Finance_Source,
         Data_Coverage)

he_current_counts <- ccdata %>% count(Institution, name = "CurrentCount")
he_sample_titles <- ccdata %>%
  group_by(Institution) %>%
  summarize(SampleTitles = paste(head(Title, 3), collapse = "; "), .groups = "drop")
he_weekly_new <- he_new_this_week %>% count(Institution, name = "WeeklyNew")

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
    Child_Poverty_Rate = NA_real_, SAIPE_Year = NA_integer_,
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
         Child_Poverty_Rate, SAIPE_Year, Child_Poverty_Basis, Free_Reduced_Lunch_Share, FRL_Year, Total_General_Fund_Expenditure, Finance_FY, Finance_Source)

combined_map_data <- bind_rows(map_k12, map_he)

map_county_choices <- c("All Counties" = "all", setNames(
  sort(unique(na.omit(combined_map_data$County))),
  sub(", Montana$", "", sort(unique(na.omit(combined_map_data$County))))
))

# Map marker size/color -- ported verbatim.
MAP_MARKER_MIN_RADIUS <- 6
MAP_MARKER_MAX_RADIUS <- 24
map_marker_radius <- function(current_count) {
  pmin(MAP_MARKER_MAX_RADIUS, MAP_MARKER_MIN_RADIUS + 1.2 * sqrt(current_count))
}
# Flexible query matching for map and job searches. Supports keywords,
# abbreviations (e.g. "special ed", "sped", "math", "cte"), and multi-word queries.
match_job_query <- function(title_vec, query) {
  if (is.null(query) || !nzchar(trimws(query))) return(rep(TRUE, length(title_vec)))
  q <- trimws(query)
  q_lower <- tolower(q)
  pattern <- if (q_lower %in% c("special ed", "sped", "special education")) {
    "special[[:space:]]*ed|sped|special[[:space:]]*educ"
  } else if (q_lower %in% c("math", "mathematics")) {
    "math"
  } else if (q_lower %in% c("pe", "phys ed", "physical education")) {
    "physical[[:space:]]*ed|phys[[:space:]]*ed|\\bpe\\b"
  } else if (q_lower %in% c("cte", "career and technical", "vocational")) {
    "cte|career[[:space:]]*and[[:space:]]*tech|vocational|industrial[[:space:]]*arts"
  } else if (q_lower %in% c("bus driver", "driver", "transportation")) {
    "driver|transportation"
  } else {
    words <- strsplit(q, "[[:space:]]+")[[1]]
    words <- words[nzchar(words)]
    if (length(words) > 1) {
      paste0("(?=.*", words, ")", collapse = "")
    } else {
      words
    }
  }
  !is.na(title_vec) & grepl(pattern, title_vec, ignore.case = TRUE, perl = TRUE)
}

compute_vacancy_rate_domain <- function(vacancy_rate) {
  if (all(is.na(vacancy_rate))) c(0, 1) else range(vacancy_rate, na.rm = TRUE)
}
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

# Titled card, the bslib stand-in for shinydashboard::box().
dash_card <- function(title = NULL, ..., full_screen = FALSE, class = NULL) {
  card(
    full_screen = full_screen,
    class = class,
    if (!is.null(title)) card_header(title),
    card_body(..., fillable = FALSE)
  )
}

# An "(i) label" link that opens explanatory text in a popover, so long
# method notes stay one click away instead of filling the page.
info_popover <- function(label, ..., placement = "auto") {
  popover(
    tags$a(href = "#", class = "info-pop", role = "button", onclick = "return false;",
           icon("circle-info"), " ", label),
    ...,
    title = label,
    placement = placement,
    options = list(customClass = "info-popover")
  )
}

# One download tile on the Data page.
download_tile <- function(icon_name, heading, text, output_id, label) {
  div(
    class = "download-tile",
    h4(icon(icon_name), " ", heading),
    p(text),
    downloadButton(output_id, label, class = "btn-outline-primary btn-sm w-100")
  )
}

ui <- page_navbar(
  id = "sidebar_tabs",
  title = tags$span(icon("graduation-cap"), " Montana Education Jobs"),
  window_title = "Montana Education Jobs",
  theme = app_theme,
  fillable = FALSE,
  navbar_options = navbar_options(theme = "dark", bg = "#1e293b"),
  header = tags$head(
    tags$style(HTML("
    .bslib-page-navbar > .navbar .navbar-brand { font-weight: 600; font-size: 1.1rem; }
    .navbar .dropdown-header { font-size: 11px; letter-spacing: 0.08em; text-transform: uppercase; }
    h1.page-title { font-size: 1.6rem; font-weight: 600; margin: 4px 0 14px; }
    h3.page-title { font-size: 1.3rem; font-weight: 600; margin: 4px 0 8px; }
    .card { margin-bottom: 1rem; }
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
    .map-chips { margin-top: -8px; font-size: 12px; color: #64748b; line-height: 1.9; }
    .map-chips a { margin-right: 8px; font-weight: 500; }
    .bslib-sidebar-layout > .sidebar .form-group { margin-bottom: 0.75rem; }
    .page-sidebar { border: none; --_sidebar-bg: transparent; }
    /* On a phone the collapsed sidebar is just a chevron; name it. */
    @media (max-width: 575.98px) {
      .bslib-sidebar-layout.sidebar-collapsed > .collapse-toggle { width: auto; padding: 4px 10px; border: 1px solid var(--bs-border-color); border-radius: 6px; }
      .bslib-sidebar-layout.sidebar-collapsed > .collapse-toggle::after { content: 'Filters'; margin-left: 6px; font-size: 0.9rem; }
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
    layout_columns(
      col_widths = c(6, 6),
      uiOutput("k12_biggest_mover"),
      uiOutput("he_biggest_mover")
    ),
    layout_columns(
      col_widths = c(6, 6),
      dash_card("Top K-12 Hiring Districts This Week",
                div(style = "overflow-x: auto;", tableOutput("top_k12_districts"))),
      dash_card("Top Higher Ed Hiring Institutions This Week",
                div(style = "overflow-x: auto;", tableOutput("top_he_institutions")))
    ),
    layout_columns(
      col_widths = c(6, 6),
      dash_card("Highest Teacher Vacancy Rate",
                withSpinner(plotlyOutput("k12_vacancy_leaderboard", height = 320)),
                helpText("Districts with at least", VACANCY_RATE_MIN_FTE, "full-time teachers (FTE).")),
      dash_card("Highest Faculty Vacancy Rate",
                withSpinner(plotlyOutput("he_vacancy_leaderboard", height = 320)),
                helpText("Institutions with at least", VACANCY_RATE_MIN_FTE, "full-time faculty."))
    ),
    dash_card(
      "Montana K-12 coverage", class = "border-warning",
      tags$p(
        "The K-12 Jobs Table combines postings from ", sum(map_k12$Data_Coverage != OPI_ONLY_COVERAGE, na.rm = TRUE),
        " directly tracked district boards with Montana OPI's statewide Jobs for Teachers feed. ",
        "A job on both counts once: an OPI posting is checked, posting by posting, against the district's own board, and one that is the same opening ",
        "isn't counted again (the district's posting is marked \u201calso on OPI\u201d). OPI postings the district's board doesn't list count from OPI \u2014 ",
        "many districts post their teaching jobs only there \u2014 as do OPI postings for districts we don't track."
      ),
      tags$p(
        "OPI is a valuable statewide source, but its publication rules and coverage have not been independently verified as a complete census of Montana vacancies. ",
        "A job absent from this dashboard is not evidence that no vacancy exists."
      ),
      tags$p(
        class = "mb-0",
        "Districts we don't track appear on the Map and District Summary when they post on OPI, marked \u201c", OPI_ONLY_COVERAGE, "\u201d, with NCES location and staffing and the same salary, finance and Census context where those sources cover them. ",
        "Private and tribal schools, co-ops and other employers outside the public district list stay in the Jobs Table only."
      )
    ),
    div(style = "color:#999; font-size:0.8em; padding: 0 5px 5px;",
        "K-12 vacancy rate is current teacher postings ÷ full-time teacher staffing (NCES CCD); Higher Ed vacancy rate is current instructor/faculty postings ÷ full-time instructional staff (NCES IPEDS). ",
        "The two use different staffing sources and reporting years — compare rates within a type (district vs. district, institution vs. institution), not across K-12 and Higher Ed."),
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
          p("The K-12 Jobs Table also includes OPI's statewide \"Jobs for Teachers\" feed, but OPI coverage is not independently verified as a complete census of Montana vacancies. OPI postings are matched to districts through the district each posting's OPI page names; districts we don't track are mapped from those postings."),
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
          "Shows the directly tracked districts and colleges, plus districts we don't track that post on OPI this week (marked in their popup). Circle size = current openings; color = vacancy rate. ",
          "Click a marker to see its jobs.")
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
          h4("One row per district -- current openings, teacher vacancy rate, and salary data"),
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
            col_widths = c(6, 6),
            dash_card("Teacher Avg Salary & County Median Income",
                      withSpinner(plotlyOutput("k12_compare_salary_plot", height = "360px"))),
            dash_card("Student Enrollment & Active Openings",
                      withSpinner(plotlyOutput("k12_compare_metrics_plot", height = "360px")))
          ),
          dash_card("Active Openings in Selected Districts",
                    DTOutput("k12_compare_jobs_table", fill = FALSE))
        )
      )
    ),
    nav_panel(
      "Trends", value = "k12_trends", icon = icon("chart-line"),
      # Method note (2026-11-03): how OPI postings are de-duplicated against
      # district boards (opi_reconcile.R, scripts/reconcile_opi_history.R).
      div(class = "alert alert-info small mb-2", role = "note",
          tags$strong("How postings are counted: "),
          "a job listed on both a district's own board and Montana OPI's statewide board counts once. ",
          "Since November 3, 2026 each OPI posting is checked against the district's board using its description; ",
          "earlier weeks were recomputed the same way but from OPI's subject titles alone, so they may include roughly 30 ",
          "postings a week that OPI listed twice."),
      navset_card_tab(
        id = "k12_trends_tabs",
        nav_panel(
          title = tagList(icon("chart-column"), " Current Trends"),
          value = "k12_trends_current",
          p(class = "text-muted", style = "margin-top: 5px; margin-bottom: 12px;",
            "Current subject distribution across active K-12 postings with 12-week vacancy sparklines."),
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
            "Multi-year vacancy volume time series tracking hiring trends across weekly snapshots."),
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
            withSpinner(plotlyOutput("k12_longitudinal_plot"))
          )
        )
      )
    ),
    nav_panel(
      "Listing Duration", value = "k12_spells", icon = icon("stopwatch"),
      h3(class = "page-title", tagList(icon("stopwatch"), " K-12 Listing Duration")),
      p(class = "text-muted small",
        "How long each K-12 posting stayed listed on the job boards this dashboard tracks."),
      spells_paused_note("posting"),
      layout_sidebar(
        fillable = FALSE,
        class = "page-sidebar",
        sidebar = sidebar(
          title = "Filters",
          width = 260,
          selectInput("k12_spell_status", "Listing status:",
                      choices = c("All Postings" = "all",
                                  "Still Active (Open)" = "Still Active",
                                  "No longer listed" = "No longer listed"),
                      selected = "all"),
          selectInput("k12_spell_position", "Position group:",
                      choices = c("All Roles" = "all",
                                  "Teacher" = "Teacher",
                                  "Administration" = "Administration",
                                  "Support Staff / Classified" = "Support"),
                      selected = "all"),
          selectInput("k12_spell_discipline", "Discipline / shortage area:",
                      choices = c("All Disciplines" = "all",
                                  "STEM (Math & Science)" = "stem",
                                  "Special Education" = "sped",
                                  "Elementary Education" = "elementary",
                                  "Secondary Education" = "secondary",
                                  "Administration" = "admin",
                                  "Support / Classified" = "support"),
                      selected = "all"),
          selectInput("k12_spell_district", "District:",
                      choices = c("All Districts" = "all"),
                      selected = "all")
        ),
        # Duration KPI boxes and charts paused (spells_paused_note()); their
        # server outputs are kept for when the rebuilt spells return.
        card(
          card_header(
            class = "d-flex justify-content-between align-items-center",
            "Postings and how long they stayed listed",
            info_popover(
              "How days listed is counted",
              p(class = "mb-0", "Days listed = the span from the first to the last weekly scrape that showed the posting, plus 7 days. It starts when we first saw the posting (often after it was posted) and ends when it stopped appearing, whatever the reason.")
            )
          ),
          card_body(
            fillable = FALSE,
            div(class = "trends-table-container mt-0",
                withSpinner(DTOutput("k12_spell_table", fill = FALSE)))
          )
        )
      )
    )
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
          p(class = "mb-0", POSTED_LISTED_NOTE, "Posted Pay is the pay the job posting itself states (hourly, annual, or per credit hour, as written); blank where the posting gives no figure. Typical pay (IPEDS est.) fills in for staff postings that state none: the college's average pay for its full-time staff in that job category (IPEDS; hover for the category), not this job's offer. Avg Faculty Salary reflects full-time instructional staff compensation from IPEDS via Urban Institute."))),
      DTOutput("he_jobs", fill = FALSE)
    ),
    nav_panel(
      "Colleges", value = "he_summary", icon = icon("building-columns"),
      navset_card_tab(
        id = "he_summary_tabs",
        nav_panel(
          title = tagList(icon("building-columns"), " Institution Directory"),
          value = "he_summary_dir",
          h4("One row per institution -- current openings, faculty vacancy rate, and salary data"),
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
            dash_card("Faculty Average Salary (IPEDS)",
                      withSpinner(plotlyOutput("he_compare_salary_plot", height = "360px"))),
            dash_card("Openings by Appointment Type",
                      withSpinner(plotlyOutput("he_compare_openings_plot", height = "360px")))
          ),
          dash_card("Active Openings in Selected Institutions",
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
            "Current institution and discipline breakdown across active higher education postings with 12-week sparklines."),
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
            "Multi-year vacancy volume time series tracking higher education hiring trends across weekly snapshots."),
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
    nav_panel(
      "Listing Duration", value = "he_spells", icon = icon("stopwatch"),
      h3(class = "page-title", tagList(icon("stopwatch"), " Higher Ed Listing Duration")),
      p(class = "text-muted small",
        "How long each higher ed posting stayed listed on the job boards this dashboard tracks."),
      spells_paused_note("posting"),
      layout_sidebar(
        fillable = FALSE,
        class = "page-sidebar",
        sidebar = sidebar(
          title = "Filters",
          width = 260,
          selectInput("he_spell_status", "Listing status:",
                      choices = c("All Postings" = "all",
                                  "Still Active (Open)" = "Still Active",
                                  "No longer listed" = "No longer listed"),
                      selected = "all"),
          selectInput("he_spell_job_type", "Appointment type:",
                      choices = c("All Appointments" = "all",
                                  "Full-Time / Regular Faculty" = "Instructor/Teacher/Faculty",
                                  "Adjunct / Part-Time Faculty" = "Adjunct/Part-Time Faculty"),
                      selected = "all"),
          selectInput("he_spell_discipline", "Academic focus:",
                      choices = c("All Disciplines" = "all",
                                  "STEM Fields" = "stem",
                                  "Health Sciences & Nursing" = "health",
                                  "Career & Technical (CTE)" = "cte"),
                      selected = "all"),
          selectInput("he_spell_institution", "Institution:",
                      choices = c("All Institutions" = "all"),
                      selected = "all")
        ),
        # Duration KPI boxes and charts paused (spells_paused_note()).
        card(
          card_header(
            class = "d-flex justify-content-between align-items-center",
            "Postings and how long they stayed listed",
            info_popover(
              "How days listed is counted",
              p(class = "mb-0", "Days listed = the span from the first to the last weekly scrape that showed the posting, plus 7 days. It starts when we first saw the posting (often after it was posted) and ends when it stopped appearing, whatever the reason.")
            )
          ),
          card_body(
            fillable = FALSE,
            div(class = "trends-table-container mt-0",
                withSpinner(DTOutput("he_spell_table", fill = FALSE)))
          )
        )
      )
    )
  ),

  # ------------------ Data & community ------------------
  nav_panel(
    "Data", value = "data_tab", icon = icon("database"),
    h1(class = "page-title", "Data Sources & Open Research Downloads"),
    p(class = "lead", "Transparent data provenance, methodology documentation, and downloadable datasets for researchers, policy analysts, school administrators, and the public."),

    dash_card(
      "Open Research Downloads",
      p("Every weekly snapshot is preserved. Download current or multi-year longitudinal datasets in standard CSV format:"),
      layout_column_wrap(
        width = "230px", fill = FALSE,
        download_tile("briefcase", "Active K-12 Jobs",
                      "All current public school job openings in Montana with standardized titles, positions, locations, links, and district salary benchmarks.",
                      "download_active_k12", "Active Jobs (CSV)"),
        download_tile("clock-rotate-left", "K-12 History Archive",
                      "Historical record of weekly K-12 job postings across Montana (3,200+ records) for hiring seasonality and longitudinal teacher demand studies.",
                      "download_history_k12", "Historical K-12 (CSV)"),
        download_tile("stopwatch", "K-12 Listing Duration",
                      "Each posting's first and last week on the boards we track, days listed, and subject flags (STEM, SPED, etc.). Not a time-to-fill measure: see the caveats on the Listing Duration tab.",
                      "download_spells", "Listing Duration (CSV)"),
        download_tile("school", "District Profiles",
                      "District-level profiles: MT DLI salaries (10th/avg/90th), NCES teacher FTE & enrollment, student-to-teacher ratios, and Census poverty/rent.",
                      "download_district_benchmarks", "District Profiles (CSV)"),
        download_tile("chart-line", "K-12 Weekly Vacancies",
                      "Weekly longitudinal vacancy totals across Montana school districts (3,700+ observations). Ideal for seasonal hiring cycles and supply/demand modeling.",
                      "download_weekly_totals", "Weekly Totals (CSV)"),
        download_tile("building-columns", "Higher Ed Archive",
                      "Longitudinal postings for instructional faculty, adjuncts, and staff across the Montana University System, tribal colleges, and community colleges.",
                      "download_history_he", "Higher Ed Archive (CSV)"),
        download_tile("stopwatch", "Higher Ed Listing Duration",
                      "Each faculty/staff posting's first and last week on the boards we track, days listed, and discipline flags. Not a time-to-fill measure: see the caveats on the Listing Duration tab.",
                      "download_he_spells", "Higher Ed Listing Duration (CSV)"),
        download_tile("graduation-cap", "Higher Ed Profiles",
                      "Institution-level profiles: IPEDS UNITID, instructional faculty salaries (all ranks and professor), enrollment, and federal Pell shares.",
                      "download_he_benchmarks", "Higher Ed Profiles (CSV)"),
        download_tile("chart-line", "Higher Ed Weekly Vacancies",
                      "Weekly longitudinal vacancy totals across Montana colleges, universities, and tribal colleges. Ideal for tracking higher ed hiring seasonality.",
                      "download_he_weekly_totals", "Higher Ed Weekly Totals (CSV)"),
        download_tile("book", "Data Dictionary",
                      "Comprehensive machine-readable codebook documenting variable names, data types, definitions, and source authorities across all datasets.",
                      "download_dictionary", "Codebook (CSV)")
      )
    ),

    dash_card(
      "Interactive Data Dictionary & Variable Codebook",
      p("Search, sort, and filter variable definitions, data types, and primary source authorities across all datasets:"),
      div(style = "overflow-x: auto;", withSpinner(DTOutput("data_dictionary_table", fill = FALSE)))
    ),

    dash_card(
      "Data Provenance & Source Transparency",
      p("All datasets are compiled through automated, reproducible collection pipelines and federal/state data integration. Here is where every data point originates:"),
      div(class = "table-responsive",
        tags$table(
          class = "table table-striped table-bordered table-hover",
          tags$thead(
            tags$tr(
              tags$th("Dataset Layer"),
              tags$th("Primary Authority / Source"),
              tags$th("Refresh Frequency"),
              tags$th("Description & Research Utility")
            )
          ),
          tags$tbody(
            tags$tr(
              tags$td(strong("K-12 Active Vacancies")),
              tags$td("District Hiring Portals (Frontline/AppliTrack, SchoolSpring, TalentEd, Tyler Portico) + Montana OPI Jobs for Teachers"),
              tags$td(span(class = "badge text-bg-success", "Weekly")),
              tags$td("Standardized active postings across 180+ Montana school districts and regional education cooperatives, cleaned to remove duplicate listings and enriched with standardized job roles, categories, and direct application links.")
            ),
            tags$tr(
              tags$td(strong("K-12 Historical Archive")),
              tags$td("Historical Project Archive (2023-Present)"),
              tags$td(span(class = "badge text-bg-info", "Weekly Append")),
              tags$td("Multi-year archive of education postings used to model seasonal hiring waves, subject-area shortages (STEM, Special Education, CTE), and geographic vacancy patterns.")
            ),
            tags$tr(
              tags$td(strong("K-12 Teacher Compensation")),
              tags$td("Montana Dept of Labor & Industry (DLI) / OPI GEMS Certified Staff Collection"),
              tags$td(span(class = "badge text-bg-info", "Annual / Periodic")),
              tags$td("Published teacher compensation distributions (10th percentile, average, and 90th percentile) across 105+ Montana school districts. Sourced directly from official state regional wage reports.")
            ),
            tags$tr(
              tags$td(strong("District Staffing & Enrollment")),
              tags$td("NCES Common Core of Data (CCD) via Urban Institute"),
              tags$td(span(class = "badge text-bg-info", "Annual")),
              tags$td("Federal National Center for Education Statistics district-level teacher FTE and student enrollment counts. Powers vacancy-rate calculations and student-to-teacher ratios.")
            ),
            tags$tr(
              tags$td(strong("Higher Ed Faculty Compensation")),
              tags$td("NCES IPEDS Instructional Staff Salary Survey"),
              tags$td(span(class = "badge text-bg-info", "Annual")),
              tags$td("Average full-time instructional faculty salaries (all combined and full professor rank) for Montana University System campuses, tribal colleges, and community colleges.")
            ),
            tags$tr(
              tags$td(strong("County Economic Context")),
              tags$td("US Census Bureau (ACS 5-Year Estimates)"),
              tags$td(span(class = "badge text-bg-info", "Annual")),
              tags$td("County median household income, median gross rent, share of civilian labor force in agriculture/resource extraction, and 5-year population trajectory.")
            ),
            tags$tr(
              tags$td(strong("Student Need Context")),
              tags$td("Census SAIPE & US Dept of Education FSA"),
              tags$td(span(class = "badge text-bg-info", "Annual")),
              tags$td("Small Area Income and Poverty Estimates (SAIPE) district-level child poverty rates for K-12, and Federal Student Aid (FSA) undergraduate Pell Grant recipient shares for colleges.")
            )
          )
        )
      )
    ),

    dash_card(
      "Open Research Citation & Code",
      p("This project is open-source and maintained to promote labor market transparency in public education. If you use these datasets in academic research, policy analysis, or journalism, please cite:"),
      tags$blockquote(
        style = "font-size: 13px; background: #f9f9f9; padding: 10px 15px; border-left: 4px solid #2a78d6;",
        "Bostick, M. (2026). Montana Education Jobs Dashboard: Longitudinal Staffing Demand, Compensation, and Socioeconomic Context. ",
        tags$a(href = "https://github.com/bostickmike/Montana-Education-Jobs-Dashboard", target = "_blank", "https://github.com/bostickmike/Montana-Education-Jobs-Dashboard")
      ),
      p(style = "margin-bottom: 0; font-size: 12px; color: #777;",
        "To report discrepancies, missing districts, or data issues, please submit an issue on the ",
        tags$a(href = "https://github.com/bostickmike/Montana-Education-Jobs-Dashboard/issues", target = "_blank", "GitHub Issue Tracker"), ".")
    )
  ),

  nav_spacer(),
  nav_item(
    tags$a(
      class = "nav-link",
      href = "https://github.com/bostickmike/Montana-Education-Jobs-Dashboard/issues/new?template=data_issue.yml",
      target = "_blank", rel = "noopener",
      icon("flag"), " Feedback"
    )
  )
)


#--------------------------------------------------
# Server
#--------------------------------------------------
server <- function(input, output, session) {

  selected_district <- reactiveVal(NULL)
  selected_institution <- reactiveVal(NULL)
  # Map search carried over from a map popup's "View matching jobs" link;
  # NULL whenever the Jobs tab is reached any other way.
  selected_k12_query <- reactiveVal(NULL)
  selected_he_query <- reactiveVal(NULL)
  # Pay band carried over from a map popup (PAY_BANDS name), or NULL.
  selected_pay_band <- reactiveVal(NULL)

  output$data_load_issues_banner <- renderUI({
    req(length(DATA_LOAD_ISSUES) > 0)
    card(class = "border-danger",
         card_header(class = "bg-danger text-white", "Data issue detected"),
         card_body(
           tags$ul(lapply(DATA_LOAD_ISSUES, tags$li)),
           helpText("This is a schema problem in the underlying data pipeline, not something wrong with your view of the dashboard -- the missing field(s) above need a pipeline fix.")))
  })

  # -------- Intro KPIs --------
  wow_delta_ui <- function(delta) {
    if (is.na(delta)) return(NULL)
    arrow <- if (delta >= 0) "▲" else "▼"
    tags$div(style = "font-size: 0.85em; margin-top: 2px;", paste0(arrow, " ", abs(delta), " vs last week"))
  }

  statewide_weekly_series <- function(weekly_totals) {
    weekly_totals %>%
      group_by(Archive_Date) %>%
      summarize(n = sum(n), .groups = "drop") %>%
      arrange(Archive_Date) %>%
      tail(12) %>%
      pull(n)
  }

  output$kpi_k12_total <- renderUI({
    kpi_value_box(format(nrow(combineddata), big.mark = ","),
                  "Open K-12 Postings",
                  icon = HTML(make_sparkline_svg_light(statewide_weekly_series(k12_district_weekly_totals))),
                  color = "blue",
                  wow_delta_ui(compute_wow_delta(k12_district_weekly_totals)))
  })
  output$kpi_he_total <- renderUI({
    kpi_value_box(format(nrow(ccdata), big.mark = ","),
             "Open Higher Ed Postings",
             icon = HTML(make_sparkline_svg_light(statewide_weekly_series(he_institution_weekly_totals))),
             color = "purple",
               tags$small(
                 style = "display: block; font-size: 11px; opacity: 0.85;",
                 sprintf(
                   "%s faculty/instructor (non-adjunct) | %s adjunct/part-time faculty",
                   format(he_faculty_counts$faculty_instructor, big.mark = ","),
                   format(he_faculty_counts$adjunct_part_time, big.mark = ",")
                 )
               ),
               wow_delta_ui(compute_wow_delta(he_institution_weekly_totals)))
  })
  output$kpi_last_refreshed <- renderUI({
    kpi_value_box(last_refreshed_date, "Last Refreshed", icon = icon("calendar"), color = "green")
  })

  output$k12_biggest_mover <- renderUI({
    render_mover_box(find_biggest_mover(k12_district_weekly_totals, "District"), "Biggest K-12 mover")
  })
  output$he_biggest_mover <- renderUI({
    render_mover_box(find_biggest_mover(he_institution_weekly_totals, "Institution"), "Biggest Higher Ed mover")
  })

  output$top_k12_districts <- renderTable({
    top <- combineddata %>% count(District, sort = TRUE, name = "Open Postings") %>% head(5)
    top$`Last 12 Weeks` <- vapply(top$District, function(d) {
      series <- k12_district_weekly_totals %>%
        filter(District == d) %>%
        arrange(Archive_Date) %>%
        tail(12) %>%
        pull(n)
      make_sparkline_svg(series, accent = "#2a78d6")
    }, character(1))
    top$District <- paste0(
      '<a href="#" onclick="Shiny.setInputValue(\'popup_view_jobs\', \'',
      gsub("'", "&#39;", top$District, fixed = TRUE),
      '\', {priority: \'event\'}); return false;">',
      top$District,
      '</a>'
    )
    top
  }, sanitize.text.function = function(x) x)

  output$top_he_institutions <- renderTable({
    top <- ccdata %>% count(Institution, sort = TRUE, name = "Open Postings") %>% head(5)
    top$`Last 12 Weeks` <- vapply(top$Institution, function(inst) {
      series <- he_institution_weekly_totals %>%
        filter(Institution == inst) %>%
        arrange(Archive_Date) %>%
        tail(12) %>%
        pull(n)
      make_sparkline_svg(series, accent = "#4a3aa7")
    }, character(1))
    top$Institution <- paste0(
      '<a href="#" onclick="Shiny.setInputValue(\'popup_view_jobs\', \'',
      gsub("'", "&#39;", top$Institution, fixed = TRUE),
      '\', {priority: \'event\'}); return false;">',
      top$Institution,
      '</a>'
    )
    top
  }, sanitize.text.function = function(x) x)

  output$k12_vacancy_leaderboard <- renderPlotly({
    df <- combined_map_data %>%
      filter(Type == "K-12 District", !is.na(Vacancy_Rate)) %>%
      arrange(desc(Vacancy_Rate)) %>%
      head(8)
    validate(need(nrow(df) > 0, "No districts currently meet the minimum-FTE threshold for a vacancy rate."))

    plot <- ggplot(df, aes(x = reorder(Name, Vacancy_Rate), y = Vacancy_Rate,
                            text = paste0(Name, ": ", Vacancy_Numerator, " / ", Vacancy_Denominator,
                                          " = ", scales::percent(Vacancy_Rate, accuracy = 0.1)))) +
      geom_bar(stat = "identity", fill = "#2a78d6") +
      geom_text(aes(label = scales::percent(Vacancy_Rate, accuracy = 0.1)), hjust = -0.15, size = 3) +
      labs(x = NULL, y = "Teacher vacancy rate") +
      scale_y_continuous(labels = scales::percent, expand = expansion(mult = c(0, 0.2))) +
      coord_flip() +
      theme_minimal()

    ggplotly(plot, tooltip = "text")
  })

  output$he_vacancy_leaderboard <- renderPlotly({
    df <- combined_map_data %>%
      filter(Type == "Higher Ed Institution", !is.na(Vacancy_Rate)) %>%
      arrange(desc(Vacancy_Rate)) %>%
      head(8)
    validate(need(nrow(df) > 0, "No institutions currently meet the minimum-FTE threshold for a vacancy rate."))

    plot <- ggplot(df, aes(x = reorder(Name, Vacancy_Rate), y = Vacancy_Rate,
                            text = paste0(Name, ": ", Vacancy_Numerator, " / ", Vacancy_Denominator,
                                          " = ", scales::percent(Vacancy_Rate, accuracy = 0.1)))) +
      geom_bar(stat = "identity", fill = "#4a3aa7") +
      geom_text(aes(label = scales::percent(Vacancy_Rate, accuracy = 0.1)), hjust = -0.15, size = 3) +
      labs(x = NULL, y = "Faculty vacancy rate") +
      scale_y_continuous(labels = scales::percent, expand = expansion(mult = c(0, 0.2))) +
      coord_flip() +
      theme_minimal()

    ggplotly(plot, tooltip = "text")
  })

  # -------- New This Week --------
  output$k12_new_table <- renderDT({
    datatable(
      k12_new_this_week %>%
        select(title, District, location, Broad_Category, Posting_Source,
               Posting_Identity_Method, url),
      options = list(scrollX = TRUE)
    )
  })
  output$he_new_table <- renderDT({
    df <- he_new_this_week
    if (!identical(input$he_new_appointment, "all")) {
      df <- df %>% filter(Appointment == input$he_new_appointment)
    }
    datatable(
      df %>% select(Title, Institution, Location, Appointment, Category, Link),
      options = list(scrollX = TRUE)
    )
  })

  # ------------------ Open Research Downloads ------------------
  output$download_active_k12 <- downloadHandler(
    filename = function() { paste0("montana_active_k12_jobs_", Sys.Date(), ".csv") },
    content = function(file) {
      write.csv(combineddata %>% select(-any_of(c(".Pay_Value", ".Pay_Unit"))), file, row.names = FALSE, na = "")
    }
  )

  output$download_history_k12 <- downloadHandler(
    filename = function() { paste0("montana_k12_historical_archive_", Sys.Date(), ".csv") },
    content = function(file) {
      file.copy("k12jobanalysis.csv", file)
    }
  )

  output$download_district_benchmarks <- downloadHandler(
    filename = function() { paste0("montana_district_profiles_", Sys.Date(), ".csv") },
    content = function(file) {
      file.copy("salarymap2.csv", file)
    }
  )

  output$download_history_he <- downloadHandler(
    filename = function() { paste0("montana_higher_ed_historical_archive_", Sys.Date(), ".csv") },
    content = function(file) {
      file.copy("facultydata.csv", file)
    }
  )

  output$download_he_benchmarks <- downloadHandler(
    filename = function() { paste0("montana_higher_ed_profiles_", Sys.Date(), ".csv") },
    content = function(file) {
      file.copy("salarymap.csv", file)
    }
  )

  output$download_weekly_totals <- downloadHandler(
    filename = function() { paste0("montana_k12_weekly_vacancy_series_", Sys.Date(), ".csv") },
    content = function(file) {
      write.csv(latest_snapshot_per_week(read.csv("k12_district_weekly_totals.csv", fileEncoding = "UTF-8")), file, row.names = FALSE)
    }
  )

  output$download_he_weekly_totals <- downloadHandler(
    filename = function() { paste0("montana_he_weekly_vacancy_series_", Sys.Date(), ".csv") },
    content = function(file) {
      write.csv(latest_snapshot_per_week(read.csv("he_institution_weekly_totals.csv", fileEncoding = "UTF-8")), file, row.names = FALSE)
    }
  )

  output$download_spells <- downloadHandler(
    filename = function() { paste0("montana_job_duration_spells_", Sys.Date(), ".csv") },
    content = function(file) {
      file.copy("job_duration_spells.csv", file)
    }
  )

  output$download_he_spells <- downloadHandler(
    filename = function() { paste0("montana_he_job_duration_spells_", Sys.Date(), ".csv") },
    content = function(file) {
      if (file.exists("he_job_duration_spells.csv")) {
        file.copy("he_job_duration_spells.csv", file)
      } else {
        write.csv(data.frame(), file)
      }
    }
  )

  output$download_dictionary <- downloadHandler(
    filename = function() { paste0("montana_data_dictionary_", Sys.Date(), ".csv") },
    content = function(file) {
      file.copy("data_dictionary.csv", file)
    }
  )

  output$data_dictionary_table <- renderDT({
    req(data_dictionary)
    datatable(
      data_dictionary,
      filter = "top",
      escape = FALSE,
      options = list(pageLength = 15, scrollX = TRUE)
    )
  })

  # -------- K-12 --------
  output$k12_jobs <- renderDT({
    df <- combineddata
    if (!is.null(selected_district())) df <- df %>% filter(District == selected_district())
    # Same matcher and searchable text as map_filtered(), so the count here
    # equals the popup's "N matching openings".
    if (!is.null(selected_k12_query())) {
      df <- df[match_job_query(paste(coalesce(df$Title, ""), coalesce(df$Position, "")), selected_k12_query()), , drop = FALSE]
    }
    if (!is.null(selected_pay_band())) df <- df[in_pay_band(df$.Pay_Value, df$.Pay_Unit, selected_pay_band()), , drop = FALSE]
    df <- df %>% select(-any_of(c(".Pay_Value", ".Pay_Unit")))
    if (isTRUE(identical(input$k12_quick_filter, "new"))) {
      df <- df %>% filter(Posting_ID %in% k12_new_this_week$Posting_ID)
    }
    df <- df %>% select(-any_of(c("Posting_ID", "Identity method", "Posting_Identity_Method", ".salary_district")))
    datatable(df, filter = "top", escape = FALSE, extensions = "Buttons",
              options = list(scrollX = TRUE, dom = "Bfrtip", buttons = c("copy", "csv", "print")))
  })

  output$k12_filter_status <- renderUI({
    if (is.null(selected_district())) return(NULL)
    div(style = "margin-bottom: 10px;",
        strong(paste0("Showing: ", selected_district(),
                      if (!is.null(selected_k12_query())) paste0(" \u2014 jobs matching \u201c", selected_k12_query(), "\u201d") else "",
                      if (!is.null(selected_pay_band())) paste0(" \u2014 pay ", PAY_BANDS[[selected_pay_band()]]$label) else "")),
        actionButton("clear_k12_filter", "Show All Districts", class = "btn-xs", style = "margin-left: 10px;")
    )
  })
  observeEvent(input$clear_k12_filter, { selected_district(NULL); selected_k12_query(NULL); selected_pay_band(NULL) })

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
        `County Population Trend (5yr)` = Population_Change_Pct,
        # Numbers, formatted by DT below, so the column sorts as numbers (the
        # table sorts on the server, in R, by the underlying value); where the rate is a
        # stand-in (a school with no SAIPE geography of its own) the next
        # column says so.
        `District Child Poverty Rate` = Child_Poverty_Rate,
        `Poverty Rate Basis` = ifelse(is.na(Child_Poverty_Rate), NA_character_,
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
      formatPercentage(cols_like(c("Teacher Vacancy Rate", "County Mining/Energy Jobs", "District Child Poverty Rate", "County Population Trend (5yr)")), digits = 1) %>%
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
          ". County-level, not district-level -- sibling districts in the same county share the same figures."
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
          "District child poverty rate: US Census Bureau, Small Area Income and Poverty Estimates (SAIPE)",
          paste0("(", saipe_year[1], ")"), "—",
          tags$a(href = "https://www.census.gov/programs-surveys/saipe/data/datasets.html", target = "_blank", "census.gov/saipe"),
          ". District-level. For districts split between an elementary and a high-school district, this is an unweighted average of the two rates -- see DATA_COOKBOOK.md.",
          "A private or tribal school has no Census poverty estimate of its own; it shows its surrounding district's rate (marked \"Surrounding district\")."
        )
      }
    )
  })

  #--------------------------------------------------
  # K-12 Head-to-Head Comparator
  #--------------------------------------------------
  observeEvent(input$k12_comp_preset_top, {
    top_districts <- combined_map_data %>%
      filter(Type == "K-12 District") %>%
      arrange(desc(CurrentCount)) %>%
      pull(Name) %>%
      head(3)
    updateSelectizeInput(session, "k12_compare_districts", selected = top_districts)
  })

  observeEvent(input$k12_comp_preset_largest, {
    largest_districts <- combined_map_data %>%
      filter(Type == "K-12 District") %>%
      arrange(desc(Enrollment)) %>%
      pull(Name) %>%
      head(3)
    updateSelectizeInput(session, "k12_compare_districts", selected = largest_districts)
  })

  observeEvent(input$k12_comp_preset_clear, {
    updateSelectizeInput(session, "k12_compare_districts", selected = character(0))
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
      rent <- if (!is.na(row$Median_Gross_Rent[1])) paste0(scales::dollar(row$Median_Gross_Rent[1]), "/mo") else "N/A"
      poverty <- if (!is.na(row$Child_Poverty_Rate[1])) scales::percent(row$Child_Poverty_Rate[1], accuracy = 0.1) else "N/A"
      if (!is.na(row$Child_Poverty_Rate[1]) && !is.na(row$Child_Poverty_Basis[1])) poverty <- paste(poverty, "(surrounding district)")
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
              tags$tr(tags$td(class = "text-muted", "Child Poverty Rate:"), tags$td(style = "text-align: right; font-weight: 600;", poverty)),
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
      select(Name, Teacher_Avg_Salary, Median_Household_Income)
    
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

  output$k12_compare_metrics_plot <- renderPlotly({
    selected <- input$k12_compare_districts
    if (is.null(selected) || length(selected) == 0) {
      return(plot_ly(type = "scatter", mode = "none") %>% layout(
        annotations = list(list(text = "Select one or more districts to display staffing metrics",
                                showarrow = FALSE, font = list(size = 14, color = "#666"))),
        xaxis = list(visible = FALSE), yaxis = list(visible = FALSE)
      ))
    }
    df <- combined_map_data %>%
      filter(Type == "K-12 District", Name %in% selected) %>%
      select(Name, Enrollment, CurrentCount)
    
    plot_ly(df, x = ~Name) %>%
      add_bars(y = ~Enrollment, name = "Enrollment", yaxis = "y1", marker = list(color = "#34495e")) %>%
      add_lines(y = ~CurrentCount, name = "Active Openings", yaxis = "y2",
                line = list(color = "#e74c3c", width = 3), marker = list(size = 8, color = "#e74c3c")) %>%
      layout(
        xaxis = list(title = "", tickangle = -15),
        yaxis = list(title = "Student Enrollment", tickformat = ",.0f"),
        yaxis2 = list(title = "Active Openings", overlaying = "y", side = "right", showgrid = FALSE),
        legend = list(orientation = "h", x = 0, y = 1.15),
        margin = list(b = 60, l = 60, r = 50, t = 40)
      )
  })

  output$k12_compare_jobs_table <- renderDT({
    selected <- input$k12_compare_districts
    df <- combineddata
    if (!is.null(selected) && length(selected) > 0) {
      df <- df %>% filter(District %in% selected)
    } else {
      df <- df[0, ]
    }
    datatable(df %>% select(-any_of(c(".Pay_Value", ".Pay_Unit"))), filter = "top", escape = FALSE, extensions = "Buttons",
              options = list(scrollX = TRUE, dom = "Bfrtip", buttons = c("copy", "csv", "print"), pageLength = 10))
  })

  # -------- Combined map (Introduction tab) --------
  output$combined_map <- renderLeaflet({
    leaflet() %>%
      # Esri World Light Gray, not CARTO Positron: CARTO's basemaps now require
      # an API key and serve an "API KEY REQUIRED" image tile without one.
      # The reference layer adds place names on top of the label-free base.
      addProviderTiles(providers$Esri.WorldGrayCanvas, group = "Clean (Default)") %>%
      addTiles(
        urlTemplate = "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}",
        options = tileOptions(maxZoom = 16),
        group = "Clean (Default)"
      ) %>%
      addTiles(group = "OpenStreetMap") %>%
      addProviderTiles(providers$Esri.WorldTopoMap, group = "Topographic") %>%
      setView(lng = -111.5, lat = 46.8, zoom = 7) %>%
      addLayersControl(
        baseGroups = c("Clean (Default)", "OpenStreetMap", "Topographic"),
        options = layersControlOptions(collapsed = TRUE)
      ) %>%
      addLegend(position = "bottomright", pal = vacancy_rate_palette, values = vacancy_rate_domain,
                title = "Vacancy rate", labFormat = labelFormat(suffix = "%", transform = function(x) 100 * x),
                na.label = "N/A")
  })
  outputOptions(output, "combined_map", suspendWhenHidden = FALSE)

  # Quick suggestion chips for position search
  observeEvent(input$map_chip_sped, {
    updateTextInput(session, "map_search_keyword", value = "special ed")
  })
  observeEvent(input$map_chip_math, {
    updateTextInput(session, "map_search_keyword", value = "mathematics")
  })
  observeEvent(input$map_chip_elem, {
    updateTextInput(session, "map_search_keyword", value = "elementary")
  })
  observeEvent(input$map_chip_science, {
    updateTextInput(session, "map_search_keyword", value = "science")
  })
  observeEvent(input$map_chip_music, {
    updateTextInput(session, "map_search_keyword", value = "music")
  })
  observeEvent(input$map_chip_driver, {
    updateTextInput(session, "map_search_keyword", value = "bus driver")
  })
  observeEvent(input$map_chip_clear, {
    updateTextInput(session, "map_search_keyword", value = "")
  })

  map_filtered <- reactive({
    df <- combined_map_data %>% filter(Type %in% input$map_types, CurrentCount > 0)

    # Search keyword / role / subject query filter, and the pay band. Both
    # narrow each dot to its matching postings (count, samples, popup).
    kw <- if (!is.null(input$map_search_keyword)) trimws(input$map_search_keyword) else ""
    band <- input$map_salary_tier
    band_on <- !is.null(band) && band %in% names(PAY_BANDS)
    if (nzchar(kw) || band_on) {
      searchable_k12 <- paste(coalesce(combineddata$Title, ""), coalesce(combineddata$Position, ""))
      k12_matches <- combineddata[match_job_query(searchable_k12, kw) &
                                    in_pay_band(combineddata$.Pay_Value, combineddata$.Pay_Unit, if (band_on) band), , drop = FALSE]

      searchable_he <- paste(coalesce(ccdata$Title, ""), coalesce(ccdata$Appointment, ""))
      he_matches <- ccdata[match_job_query(searchable_he, kw) &
                             in_pay_band(ccdata$.Pay_Value, ccdata$.Pay_Unit, if (band_on) band), , drop = FALSE]

      k12_counts <- if (nrow(k12_matches) > 0) {
        as.data.frame(table(Name = k12_matches$District), stringsAsFactors = FALSE)
      } else {
        data.frame(Name = character(0), Freq = integer(0))
      }
      names(k12_counts) <- c("Name", "MatchingCount")

      k12_samples <- if (nrow(k12_matches) > 0) {
        k12_matches %>%
          group_by(District) %>%
          summarize(MatchingSample = paste(head(unique(Title), 3), collapse = "; "), .groups = "drop") %>%
          rename(Name = District)
      } else {
        data.frame(Name = character(0), MatchingSample = character(0))
      }

      he_counts <- if (nrow(he_matches) > 0) {
        as.data.frame(table(Name = he_matches$Institution), stringsAsFactors = FALSE)
      } else {
        data.frame(Name = character(0), Freq = integer(0))
      }
      names(he_counts) <- c("Name", "MatchingCount")

      he_samples <- if (nrow(he_matches) > 0) {
        he_matches %>%
          group_by(Institution) %>%
          summarize(MatchingSample = paste(head(unique(Title), 3), collapse = "; "), .groups = "drop") %>%
          rename(Name = Institution)
      } else {
        data.frame(Name = character(0), MatchingSample = character(0))
      }

      all_counts <- bind_rows(k12_counts, he_counts)
      all_samples <- bind_rows(k12_samples, he_samples)

      df <- df %>%
        inner_join(all_counts, by = "Name") %>%
        left_join(all_samples, by = "Name") %>%
        mutate(
          MatchingCount = coalesce(MatchingCount, 0L),
          MatchingSample = coalesce(MatchingSample, ""),
          DisplayCount = MatchingCount,
          SearchActive = TRUE,
          SearchQuery = paste(c(if (nzchar(kw)) kw, if (band_on) PAY_BANDS[[band]]$label), collapse = " \u00b7 "),
          SearchKeyword = kw,
          SearchBand = if (band_on) band else ""
        ) %>%
        filter(MatchingCount > 0)
    } else {
      df <- df %>%
        mutate(
          MatchingCount = CurrentCount,
          MatchingSample = SampleTitles,
          DisplayCount = CurrentCount,
          SearchActive = FALSE,
          SearchQuery = "",
          SearchKeyword = "",
          SearchBand = ""
        )
    }

    # Filter by county
    if (!is.null(input$map_county) && input$map_county != "all") {
      df <- df %>% filter(County == input$map_county)
    }

    # Filter by posting volume / freshness
    if (!is.null(input$map_urgency) && input$map_urgency != "all") {
      if (input$map_urgency == "5_plus") {
        df <- df %>% filter(DisplayCount >= 5)
      } else if (input$map_urgency == "2_plus") {
        df <- df %>% filter(DisplayCount >= 2)
      } else if (input$map_urgency == "has_new") {
        df <- df %>% filter(WeeklyNew > 0)
      }
    }

    df
  })

  output$map_filter_count <- renderUI({
    filtered_df <- map_filtered()
    filtered_n <- nrow(filtered_df)
    kw <- if (!is.null(input$map_search_keyword)) trimws(input$map_search_keyword) else ""
    total_active <- nrow(combined_map_data %>% filter(CurrentCount > 0))
    total_postings <- sum(filtered_df$DisplayCount, na.rm = TRUE)

    if (filtered_n == 0) {
      if (nzchar(kw)) {
        tags$span(
          class = "badge",
          style = "background-color: #d9534f; font-size: 0.9em; padding: 6px 12px; font-weight: 500; border-radius: 4px;",
          sprintf('No locations currently have open positions matching "%s" under selected filters — try broadening your search or click Reset.', kw)
        )
      } else {
        tags$span(
          class = "badge",
          style = "background-color: #d9534f; font-size: 0.9em; padding: 6px 12px; font-weight: 500; border-radius: 4px;",
          "No locations match all selected filters — broaden criteria or click Reset Filters."
        )
      }
    } else {
      if (nzchar(kw)) {
        tags$span(
          class = "badge",
          style = "background-color: #198754; font-size: 0.9em; padding: 6px 12px; font-weight: 500; border-radius: 4px;",
          sprintf('Showing %d locations with %s matching openings for "%s"',
                  filtered_n, format(total_postings, big.mark = ","), kw)
        )
      } else {
        tags$span(
          class = "badge",
          style = "background-color: #2a78d6; font-size: 0.9em; padding: 6px 12px; font-weight: 500; border-radius: 4px;",
          sprintf("Showing %d of %d active locations (%s current openings across filtered locations)",
                  filtered_n, total_active, format(total_postings, big.mark = ","))
        )
      }
    }
  })

  observeEvent(input$map_filter_reset, {
    updateTextInput(session, "map_search_keyword", value = "")
    updateCheckboxGroupInput(session, "map_types", selected = c("K-12 District", "Higher Ed Institution"))
    updateSelectInput(session, "map_county", selected = "all")
    updateSelectInput(session, "map_salary_tier", selected = "all")
    updateSelectInput(session, "map_urgency", selected = "all")
  })

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
      "<div><strong>", Name, "</strong><br/>", Type, "</div>",
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
             paste0("<div>Avg. faculty salary: ", scales::dollar(Faculty_Avg_Salary),
                    ifelse(!is.na(Faculty_Avg_Salary_Professor),
                           paste0(" (Professor rank: ", scales::dollar(Faculty_Avg_Salary_Professor), ")"),
                           ""),
                    " &middot; ", Salary_Year, "</div>",
                    # IPEDS's "all combined" figure blends every reported
                    # contract length -- full-time 9-12 month faculty
                    # alongside lower-paid part-time/adjunct instructional
                    # staff -- into one average. A small institution leaning
                    # heavily on adjuncts can report a much lower blended
                    # figure than its own full-time faculty actually earn
                    # (confirmed real, not a scrape error: Blackfeet
                    # Community College's $25,621 reflects a $54,317
                    # full-time cohort blended with a larger, lower-paid
                    # part-time one). No reliable full-time-only breakout is
                    # available from this source (IPEDS's contract-length
                    # codes aren't consistently documented enough to split
                    # this safely), so this is a disclosure rather than a fix.
                    "<div style='font-size:0.8em;color:#666;'>Blends full-time and part-time/adjunct instructional staff pay into one average.</div>"),
             ""),
      ifelse(!is.na(Salary_Source),
             paste0("<div style='font-size:0.85em;color:#666;'>Salary source: ", Salary_Source, "</div>"),
             ""),
      ifelse(!is.na(Median_Household_Income),
             paste0("<div style='font-size:0.85em;color:#666;margin-top:4px;'>County: median income ",
                    scales::dollar(Median_Household_Income), ", median rent ", scales::dollar(Median_Gross_Rent), "/mo",
                    ifelse(!is.na(Mining_Employment_Share) & Mining_Employment_Share >= 0.05,
                           paste0(", ", scales::percent(Mining_Employment_Share, accuracy = 1), " of jobs in mining/energy"),
                           ""),
                    "</div>"),
             ""),
      ifelse(!is.na(Child_Poverty_Rate),
             paste0("<div style='font-size:0.85em;color:#666;'>",
                    ifelse(is.na(Child_Poverty_Basis), "District: ", ""),
                    scales::percent(Child_Poverty_Rate, accuracy = 0.1), " child poverty rate",
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

  observeEvent(input$popup_view_jobs, {
    navigate_to_entity_jobs(input$popup_view_jobs)
  })

  observeEvent(input$map_popup_view_jobs, {
    ev <- input$map_popup_view_jobs
    query <- trimws(utils::URLdecode(if (is.null(ev$query)) "" else ev$query))
    band <- if (!is.null(ev$band) && ev$band %in% names(PAY_BANDS)) ev$band else NULL
    navigate_to_entity_jobs(ev$entity, if (nzchar(query)) query else NULL, band)
  })

  navigate_to_entity_jobs <- function(entity, query = NULL, band = NULL) {
    selected_k12_query(query)
    selected_he_query(query)
    selected_pay_band(band)
    row <- combined_map_data %>% filter(Name == entity)
    if (nrow(row) > 0) {
      if (row$Type[1] == "K-12 District") {
        selected_district(entity)
        nav_select("sidebar_tabs", "k12_table", session = session)
      } else {
        selected_institution(entity)
        nav_select("sidebar_tabs", "he_table", session = session)
      }
    } else if (entity %in% combineddata$District) {
      selected_district(entity)
      nav_select("sidebar_tabs", "k12_table", session = session)
    } else if (entity %in% ccdata$Institution) {
      selected_institution(entity)
      nav_select("sidebar_tabs", "he_table", session = session)
    }
  }


  # ---- K-12 longitudinal trends ----
  observeEvent(input$k12_detail_level_trends, {
    cats <- if (identical(input$k12_detail_level_trends, "detail")) {
      sort(unique(k12sum$Broad_Category))
    } else {
      sort(unique(k12sum_agg$Broad_Category))
    }
    updatePickerInput(session, "broad_category", choices = cats, selected = cats)
  }, ignoreInit = TRUE)

  filtered_k12sum <- reactive({
    req(input$district_trend, input$broad_category, input$k12_detail_level_trends)

    base <- if (identical(input$k12_detail_level_trends, "detail")) k12sum else k12sum_agg

    base %>%
      dplyr::filter(
        input$district_trend == "Total" |
          District == input$district_trend,
        Broad_Category %in% input$broad_category
      )
  })

  df_windowed <- reactive({
    df <- filtered_k12sum()
    req(nrow(df) > 0, input$k12_scroll)

    df <- df %>%
      filter(
        Archive_Date >= input$k12_scroll[1],
        Archive_Date <= input$k12_scroll[2]
      )

    df <- df %>%
      filter(District != "Total") %>%
      group_by(Broad_Category, Archive_Date) %>%
      summarise(sum = sum(sum), .groups = "drop") %>%
      arrange(Broad_Category, Archive_Date)

    df
  })

  output$k12_longitudinal_plot <- renderPlotly({
    df <- df_windowed()

    validate(
      need(nrow(df) > 0, "No data for selected districts.")
    )

    all_dates <- sort(unique(df$Archive_Date))

    p <- ggplot(df, aes(
      x = Archive_Date,
      y = sum,
      color = Broad_Category,
      group = Broad_Category,
      text = paste0(
        "Date: ", Archive_Date, "<br>",
        "Category: ", Broad_Category, "<br>",
        "Postings: ", sum
      )
    )) +
      geom_line() +
      geom_point(size = 1) +
      scale_color_manual(values = if (identical(input$k12_detail_level_trends, "detail")) K12_CATEGORY_COLORS_DETAIL else K12_CATEGORY_COLORS_AGG) +
      labs(x = "Archive Date", y = "Number of Postings") +
      scale_x_date(
        breaks = all_dates,
        labels = scales::date_format("%b %d")
      ) +
      theme_minimal() +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
        legend.position = "bottom",
        legend.key.size = unit(0.5, "cm"),
        legend.box.spacing = unit(0.2, "cm"),
        legend.text = element_text(size = 8),
        legend.title = element_text(size = 10)
      )

    ggplotly(p, height = 500, tooltip = "text")
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

  output$k12_current_trends_table <- renderTable({
    req(input$k12_detail_level_current)
    hist_src <- if (identical(input$k12_detail_level_current, "detail")) k12sum else k12sum_agg
    history <- hist_src %>%
      filter(District == input$district_current) %>%
      transmute(Category = Broad_Category, Archive_Date, n = sum)

    result <- build_current_trends_table(history, accent = "#2a78d6")
    req(!is.null(result))
    result
  }, sanitize.text.function = function(x) x)

  # -------- Higher Ed --------
  output$he_jobs <- renderDT({
    df <- ccdata
    if (!is.null(selected_institution())) df <- df %>% filter(Institution == selected_institution())
    if (!is.null(selected_he_query())) {
      df <- df[match_job_query(paste(coalesce(df$Title, ""), coalesce(df$Appointment, "")), selected_he_query()), , drop = FALSE]
    }
    if (!is.null(selected_pay_band())) df <- df[in_pay_band(df$.Pay_Value, df$.Pay_Unit, selected_pay_band()), , drop = FALSE]
    df <- df %>% select(-any_of(c(".Pay_Value", ".Pay_Unit")))
    if (!identical(input$he_table_appointment, "all")) {
      df <- df %>% filter(Appointment == input$he_table_appointment)
    }
    if (isTRUE(identical(input$he_quick_filter, "new"))) {
      new_keys <- paste(he_new_this_week$Title, he_new_this_week$Institution, sep = "@@@")
      current_keys <- paste(df$Title, df$Institution, sep = "@@@")
      df <- df[current_keys %in% new_keys, ]
    }
    datatable(df, filter = "top", escape = FALSE, extensions = "Buttons",
              options = list(scrollX = TRUE, dom = "Bfrtip", buttons = c("copy", "csv", "print")))
  })

  output$he_filter_status <- renderUI({
    if (is.null(selected_institution())) return(NULL)
    div(style = "margin-bottom: 10px;",
        strong(paste0("Showing: ", selected_institution(),
                      if (!is.null(selected_he_query())) paste0(" \u2014 jobs matching \u201c", selected_he_query(), "\u201d") else "",
                      if (!is.null(selected_pay_band())) paste0(" \u2014 pay ", PAY_BANDS[[selected_pay_band()]]$label) else "")),
        actionButton("clear_he_filter", "Show All Institutions", class = "btn-xs", style = "margin-left: 10px;")
    )
  })
  observeEvent(input$clear_he_filter, { selected_institution(NULL); selected_he_query(NULL); selected_pay_band(NULL) })

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
        `County Median Income` = ifelse(is.na(Median_Household_Income), NA_character_, scales::dollar(Median_Household_Income)),
        `County Median Rent` = ifelse(is.na(Median_Gross_Rent), NA_character_, paste0(scales::dollar(Median_Gross_Rent), "/mo")),
        `County Mining/Energy Jobs` = ifelse(is.na(Mining_Employment_Share), NA_character_, scales::percent(Mining_Employment_Share, accuracy = 0.1)),
        `County Population Trend (5yr)` = ifelse(is.na(Population_Change_Pct), NA_character_,
                                                   paste0(ifelse(Population_Change_Pct >= 0, "+", ""), scales::percent(Population_Change_Pct, accuracy = 0.1)))
      )
    names(df)[names(df) == "AvgFacultySalary"] <- paste0("Avg Faculty Salary (", year_label, ")")
    names(df)[names(df) == "AvgFacultySalaryY1"] <- paste0("Avg Faculty Salary (", y1_label, ")")
    names(df)[names(df) == "AvgFacultySalaryY2"] <- paste0("Avg Faculty Salary (", y2_label, ")")
    names(df)[names(df) == "ProfessorAvgSalary"] <- paste0("Professor Avg Salary (", year_label, ")")

    datatable(df, filter = "top", extensions = "Buttons",
              options = list(scrollX = TRUE, dom = "Bfrtip", buttons = c("copy", "csv", "print"), pageLength = 6))
  })

  output$he_summary_footnote <- renderUI({
    year <- unique(na.omit(combined_map_data$Salary_Year[combined_map_data$Type == "Higher Ed Institution"]))
    source <- unique(na.omit(combined_map_data$Salary_Source[combined_map_data$Type == "Higher Ed Institution"]))
    acs_year <- unique(na.omit(combined_map_data$ACS_Year[combined_map_data$Type == "Higher Ed Institution"]))
    pell_year <- unique(na.omit(combined_map_data$Pell_Year[combined_map_data$Type == "Higher Ed Institution"]))
    req(length(year) > 0, length(source) > 0)
    tagList(
      helpText(
        "Salary data:", source[1], paste0("(", year[1], " data)"), "—",
        tags$a(href = IPEDS_SALARY_SOURCE_URL, target = "_blank", "educationdata.urban.org"),
        ". Blends full-time and part-time/adjunct instructional staff pay into one average",
        "— a small institution leaning heavily on adjuncts can report a much lower blended",
        "figure than its own full-time faculty actually earn."
      ),
      if (length(acs_year) > 0) {
        helpText(
          "County context (income, rent, mining/energy employment share, population trend): US Census Bureau, American Community Survey 5-Year Estimates",
          paste0("(", acs_year[1], ")"), "—",
          tags$a(href = "https://www.census.gov/data/developers/data-sets/acs-5year.html", target = "_blank", "census.gov")
        )
      },
      if (length(pell_year) > 0) {
        helpText(
          "Pell Grant recipient share: US Dept. of Education, Federal Student Aid, via Urban Institute Education Data Portal",
          paste0("(", pell_year[1], " data — usually a year or more older than the salary/enrollment figures above, since FSA's own data lags IPEDS's)"), "—",
          tags$a(href = "https://educationdata.urban.org/documentation/colleges.html", target = "_blank", "educationdata.urban.org"),
          ". Recipients ÷ that same year's IPEDS FTE enrollment — a headcount-over-FTE ratio, not two directly comparable counts."
        )
      }
    )
  })

  #--------------------------------------------------
  # Higher Ed Head-to-Head Comparator
  #--------------------------------------------------
  observeEvent(input$he_comp_preset_top, {
    top_insts <- combined_map_data %>%
      filter(Type == "Higher Ed Institution") %>%
      arrange(desc(CurrentCount)) %>%
      pull(Name) %>%
      head(3)
    updateSelectizeInput(session, "he_compare_insts", selected = top_insts)
  })

  observeEvent(input$he_comp_preset_clear, {
    updateSelectizeInput(session, "he_compare_insts", selected = character(0))
  })

  output$he_compare_cards <- renderUI({
    selected <- input$he_compare_insts
    if (is.null(selected) || length(selected) == 0) {
      return(div(class = "alert alert-info", style = "margin-top: 15px;",
                 icon("circle-info"), " Please select one to four institutions above to display comparative benchmarks."))
    }
    
    col_width <- case_when(
      length(selected) == 1 ~ 12,
      length(selected) == 2 ~ 6,
      length(selected) == 3 ~ 4,
      TRUE ~ 3
    )

    he_rows <- combined_map_data %>%
      filter(Type == "Higher Ed Institution", Name %in% selected)

    cards <- lapply(selected, function(iname) {
      row <- he_rows %>% filter(Name == iname)
      if (nrow(row) == 0) return(NULL)

      avg_sal <- if (!is.na(row$Faculty_Avg_Salary[1])) scales::dollar(row$Faculty_Avg_Salary[1]) else "N/A"
      prof_sal <- if (!is.na(row$Faculty_Avg_Salary_Professor[1])) scales::dollar(row$Faculty_Avg_Salary_Professor[1]) else "N/A"
      vac_rate <- if (!is.na(row$Vacancy_Rate[1])) scales::percent(row$Vacancy_Rate[1], accuracy = 0.1) else "N/A"
      enroll <- if (!is.na(row$Enrollment[1])) scales::comma(row$Enrollment[1]) else "N/A"
      spf <- if (!is.na(row$Students_Per_Teacher[1])) sprintf("%.1f", row$Students_Per_Teacher[1]) else "N/A"
      enroll_trend <- if (!is.na(row$Enrollment_Change_Pct[1])) paste0(ifelse(row$Enrollment_Change_Pct[1] >= 0, "+", ""), scales::percent(row$Enrollment_Change_Pct[1], accuracy = 0.1)) else "N/A"
      pell <- if (!is.na(row$Pell_Recipient_Share[1])) scales::percent(row$Pell_Recipient_Share[1], accuracy = 0.1) else "N/A"

      column(
        width = col_width,
        div(
          class = "box box-solid box-primary",
          style = "border-top: 3px solid #2a78d6; box-shadow: 0 1px 3px rgba(0,0,0,0.08); margin-bottom: 20px;",
          div(
            class = "box-header with-border", style = "background: #f7f9fa; padding: 10px 15px;",
            h4(style = "margin: 0; font-size: 15px; font-weight: 600; color: #222;", iname),
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
              tags$tr(tags$td(class = "text-muted", "Avg Faculty Salary:"), tags$td(style = "text-align: right; font-weight: 600;", avg_sal)),
              tags$tr(tags$td(class = "text-muted", "Full Professor Avg:"), tags$td(style = "text-align: right; font-weight: 600;", prof_sal)),
              tags$tr(tags$td(class = "text-muted", "FTE Enrollment:"), tags$td(style = "text-align: right; font-weight: 600;", enroll)),
              tags$tr(tags$td(class = "text-muted", "Students / Faculty:"), tags$td(style = "text-align: right; font-weight: 600;", spf)),
              tags$tr(tags$td(class = "text-muted", "5-Yr Enrollment Trend:"), tags$td(style = "text-align: right; font-weight: 600;", enroll_trend)),
              tags$tr(tags$td(class = "text-muted", "Pell Grant Share:"), tags$td(style = "text-align: right; font-weight: 600;", pell))
            )
          )
        )
      )
    })
    fluidRow(cards)
  })

  output$he_compare_salary_plot <- renderPlotly({
    selected <- input$he_compare_insts
    if (is.null(selected) || length(selected) == 0) {
      return(plot_ly(type = "scatter", mode = "none") %>% layout(
        annotations = list(list(text = "Select one or more institutions to display salary comparison",
                                showarrow = FALSE, font = list(size = 14, color = "#666"))),
        xaxis = list(visible = FALSE), yaxis = list(visible = FALSE)
      ))
    }
    df <- combined_map_data %>%
      filter(Type == "Higher Ed Institution", Name %in% selected) %>%
      select(Name, Faculty_Avg_Salary, Faculty_Avg_Salary_Y1Ago)
    
    plot_ly(df, x = ~Name) %>%
      add_bars(y = ~Faculty_Avg_Salary, name = "Current Avg Faculty Salary", marker = list(color = "#2b5876")) %>%
      add_bars(y = ~Faculty_Avg_Salary_Y1Ago, name = "Prior Year Avg Faculty Salary", marker = list(color = "#4e4376")) %>%
      layout(
        barmode = "group",
        xaxis = list(title = "", tickangle = -15),
        yaxis = list(title = "Annual Compensation ($)", tickformat = "$,.0f"),
        legend = list(orientation = "h", x = 0, y = 1.15),
        margin = list(b = 60, l = 60, r = 20, t = 40)
      )
  })

  output$he_compare_openings_plot <- renderPlotly({
    selected <- input$he_compare_insts
    if (is.null(selected) || length(selected) == 0) {
      return(plot_ly(type = "scatter", mode = "none") %>% layout(
        annotations = list(list(text = "Select one or more institutions to display openings breakdown",
                                showarrow = FALSE, font = list(size = 14, color = "#666"))),
        xaxis = list(visible = FALSE), yaxis = list(visible = FALSE)
      ))
    }
    df <- ccdata %>%
      filter(Institution %in% selected) %>%
      count(Institution, Appointment, name = "Count")
    
    if (nrow(df) == 0) {
      return(plot_ly(type = "scatter", mode = "none") %>% layout(
        annotations = list(list(text = "No active postings for selected institutions",
                                showarrow = FALSE, font = list(size = 14, color = "#666"))),
        xaxis = list(visible = FALSE), yaxis = list(visible = FALSE)
      ))
    }

    plot_ly(df, x = ~Institution, y = ~Count, color = ~Appointment, type = "bar") %>%
      layout(
        barmode = "stack",
        xaxis = list(title = "", tickangle = -15),
        yaxis = list(title = "Active Openings"),
        legend = list(orientation = "h", x = 0, y = 1.15),
        margin = list(b = 60, l = 50, r = 20, t = 40)
      )
  })

  output$he_compare_jobs_table <- renderDT({
    selected <- input$he_compare_insts
    df <- ccdata
    if (!is.null(selected) && length(selected) > 0) {
      df <- df %>% filter(Institution %in% selected)
    } else {
      df <- df[0, ]
    }
    datatable(df %>% select(-any_of(c(".Pay_Value", ".Pay_Unit"))), filter = "top", escape = FALSE, extensions = "Buttons",
              options = list(scrollX = TRUE, dom = "Bfrtip", buttons = c("copy", "csv", "print"), pageLength = 10))
  })

  observeEvent(input$he_detail_level_trends, {
    cats <- if (identical(input$he_detail_level_trends, "detail")) {
      sort(unique(hesum_he$Category))
    } else {
      sort(unique(hesum_he_agg$Category))
    }
    updatePickerInput(session, "he_category", choices = cats, selected = cats)
  }, ignoreInit = TRUE)

  filtered_hesum <- reactive({
    req(input$inst_trend, input$he_category, input$he_chart_type, input$he_detail_level_trends)

    base <- if (identical(input$he_detail_level_trends, "detail")) hesum_he else hesum_he_agg

    df <- if (input$inst_trend == "Total") {
      base
    } else {
      base %>% filter(Institution == input$inst_trend)
    }

    df <- df %>% filter(Category %in% input$he_category)

    if (!identical(input$he_chart_type, "all")) {
      df <- df %>% filter(Job_Type == input$he_chart_type)
    }

    df
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

  he_windowed <- reactive({
    df <- filtered_hesum()
    req(input$he_scroll)

    df %>%
      filter(
        Archive_Date >= as.Date(input$he_scroll[1]),
        Archive_Date <= as.Date(input$he_scroll[2]),
        Institution != "Total"
      ) %>%
      arrange(Archive_Date)
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

  output$he_longitudinal_plot <- renderPlotly({
    df <- he_windowed()
    validate(need(nrow(df) > 0, "No data for selected institution/category/date range."))

    df <- df %>%
      group_by(Category, Archive_Date) %>%
      summarize(sum = sum(sum), .groups = "drop") %>%
      arrange(Category, Archive_Date) %>%
      mutate(Category = factor(Category))

    p <- ggplot(df, aes(
      x = Archive_Date,
      y = sum,
      color = Category,
      group = Category,
      text = paste0(
        "Date: ", Archive_Date, "<br>",
        "Category: ", Category, "<br>",
        "Postings: ", sum
      )
    )) +
      geom_line() +
      geom_point(size = 1) +
      scale_color_manual(values = if (identical(input$he_detail_level_trends, "detail")) HE_CATEGORY_COLORS_DETAIL else HE_CATEGORY_COLORS_AGG) +
      labs(x = "Archive Date", y = "Number of Postings") +
      theme_minimal() +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1, size = 8),
        legend.position = "bottom",
        legend.key.size = unit(0.5, "cm"),
        legend.box.spacing = unit(0.2, "cm"),
        legend.text = element_text(size = 8),
        legend.title = element_text(size = 10)
      )

    ggplotly(p, height = 500, tooltip = "text")
  })

  output$he_current_trends_table <- renderTable({
    req(input$he_detail_level_current, input$he_current_appointment)
    hist_src <- if (identical(input$he_detail_level_current, "detail")) hesum_he else hesum_he_agg
    history <- hist_src %>%
      filter(
        Institution == input$inst_current,
        identical(input$he_current_appointment, "all") | Job_Type == input$he_current_appointment
      ) %>%
      transmute(Category, Archive_Date, n = sum)

    result <- build_current_trends_table(history, accent = "#4a3aa7")
    req(!is.null(result))
    result
  }, sanitize.text.function = function(x) x)

  # ------------------ K-12 Vacancy Spells Server Logic ------------------
  observe({
    if (nrow(job_duration_spells) > 0) {
      dists <- sort(unique(job_duration_spells$District))
      updateSelectInput(session, "k12_spell_district",
                        choices = c("All Districts" = "all", setNames(dists, dists)),
                        selected = "all")
    }
  })

  filtered_spells <- reactive({
    req(nrow(job_duration_spells) > 0)
    df <- job_duration_spells

    if (!is.null(input$k12_spell_status) && !identical(input$k12_spell_status, "all")) {
      df <- df %>% filter(Status == input$k12_spell_status)
    }

    if (!is.null(input$k12_spell_position) && !identical(input$k12_spell_position, "all")) {
      if (identical(input$k12_spell_position, "Support")) {
        df <- df %>% filter(Position != "Teacher" & Position != "Administration")
      } else {
        df <- df %>% filter(Position == input$k12_spell_position)
      }
    }

    if (!is.null(input$k12_spell_discipline) && !identical(input$k12_spell_discipline, "all")) {
      disc <- input$k12_spell_discipline
      if (disc == "stem" && "is_stem" %in% names(df)) df <- df %>% filter(is_stem == 1)
      else if (disc == "sped" && "is_sped" %in% names(df)) df <- df %>% filter(is_sped == 1)
      else if (disc == "elementary" && "is_elementary" %in% names(df)) df <- df %>% filter(is_elementary == 1)
      else if (disc == "secondary" && "is_secondary" %in% names(df)) df <- df %>% filter(is_secondary == 1)
      else if (disc == "admin" && "is_admin" %in% names(df)) df <- df %>% filter(is_admin == 1)
      else if (disc == "support" && "is_support_staff" %in% names(df)) df <- df %>% filter(is_support_staff == 1)
    }

    if (!is.null(input$k12_spell_district) && !identical(input$k12_spell_district, "all")) {
      df <- df %>% filter(District == input$k12_spell_district)
    }

    df
  })

  output$k12_spell_median_box <- renderUI({
    df <- filtered_spells()
    med <- if (nrow(df) > 0) round(median(df$Estimated_Days_Open, na.rm = TRUE)) else 0
    kpi_value_box(
      paste0(med, " Days"),
      "Median Vacancy Duration",
      icon = icon("stopwatch"),
      color = "blue"
    )
  })

  output$k12_spell_active_box <- renderUI({
    df <- filtered_spells()
    active_n <- if (nrow(df) > 0) sum(df$Status == "Still Active", na.rm = TRUE) else 0
    kpi_value_box(
      scales::comma(active_n),
      "Currently Open Spells",
      icon = icon("door-open"),
      color = "green"
    )
  })

  output$k12_spell_persistent_box <- renderUI({
    df <- filtered_spells()
    persist_n <- if (nrow(df) > 0) sum(df$Status == "Still Active" & df$Estimated_Days_Open >= 60, na.rm = TRUE) else 0
    kpi_value_box(
      scales::comma(persist_n),
      "Persistent Spells (≥60 Days)",
      icon = icon("triangle-exclamation"),
      color = "red"
    )
  })

  output$k12_spell_hardest_box <- renderUI({
    df <- filtered_spells()
    hardest <- "None"
    if (nrow(df) >= 1 && "Broad_Category" %in% names(df)) {
      cat_dur <- df %>%
        group_by(Broad_Category) %>%
        summarize(med = median(Estimated_Days_Open, na.rm = TRUE), n = n(), .groups = "drop") %>%
        filter(n >= 1) %>%
        arrange(desc(med))
      if (nrow(cat_dur) > 0) hardest <- cat_dur$Broad_Category[1]
    }
    kpi_value_box(
      hardest,
      "Longest Duration Category",
      icon = icon("graduation-cap"),
      color = "purple"
    )
  })

  output$k12_spell_duration_plot <- renderPlotly({
    df <- filtered_spells()
    if (nrow(df) == 0) {
      p <- ggplot() +
        annotate("text", x = 0.5, y = 0.5, label = "No vacancy spells match the selected filter criteria", size = 4, color = "#666666") +
        theme_void()
      return(ggplotly(p) %>% config(displayModeBar = FALSE))
    }

    cat_summary <- df %>%
      group_by(Broad_Category) %>%
      summarize(
        Median_Days = round(median(Estimated_Days_Open, na.rm = TRUE)),
        Postings = n(),
        .groups = "drop"
      ) %>%
      filter(!is.na(Broad_Category) & Broad_Category != "" & Postings >= 1) %>%
      arrange(desc(Median_Days)) %>%
      head(12)

    if (nrow(cat_summary) == 0) {
      p <- ggplot() +
        annotate("text", x = 0.5, y = 0.5, label = "No category data available for selected filter", size = 4, color = "#666666") +
        theme_void()
      return(ggplotly(p) %>% config(displayModeBar = FALSE))
    }

    p <- ggplot(cat_summary, aes(
      x = reorder(Broad_Category, Median_Days),
      y = Median_Days,
      text = paste0("<b>", Broad_Category, "</b><br>Median Open: ", Median_Days, " days<br>Total Spells: ", Postings)
    )) +
      geom_col(fill = "#2a78d6", width = 0.65) +
      coord_flip() +
      labs(x = NULL, y = "Median Days Open") +
      theme_minimal() +
      theme(
        axis.text.y = element_text(size = 9),
        panel.grid.major.y = element_blank()
      )

    ggplotly(p, tooltip = "text") %>% config(displayModeBar = FALSE)
  })

  output$k12_spell_distrib_plot <- renderPlotly({
    df <- filtered_spells()
    bin_levels <- c("1–14 Days", "15–30 Days", "31–60 Days", "61–90 Days", "90+ Days")
    if (nrow(df) == 0) {
      p <- ggplot() +
        annotate("text", x = 0.5, y = 0.5, label = "No vacancy spells match the selected filter criteria", size = 4, color = "#666666") +
        theme_void()
      return(ggplotly(p) %>% config(displayModeBar = FALSE))
    }

    df <- df %>%
      mutate(Duration_Bin = case_when(
        Estimated_Days_Open <= 14 ~ "1–14 Days",
        Estimated_Days_Open <= 30 ~ "15–30 Days",
        Estimated_Days_Open <= 60 ~ "31–60 Days",
        Estimated_Days_Open <= 90 ~ "61–90 Days",
        TRUE ~ "90+ Days"
      )) %>%
      mutate(Duration_Bin = factor(Duration_Bin, levels = bin_levels))

    bin_counts <- df %>%
      count(Duration_Bin, name = "Count") %>%
      tidyr::complete(Duration_Bin = factor(bin_levels, levels = bin_levels), fill = list(Count = 0)) %>%
      filter(!is.na(Duration_Bin))

    p <- ggplot(bin_counts, aes(
      x = Duration_Bin, y = Count,
      text = paste0("<b>", Duration_Bin, "</b><br>Spells: ", Count)
    )) +
      geom_col(fill = "#e67e22", width = 0.6) +
      labs(x = NULL, y = "Number of Vacancies") +
      theme_minimal() +
      theme(
        axis.text.x = element_text(angle = 25, hjust = 1, size = 8),
        panel.grid.major.x = element_blank()
      )

    ggplotly(p, tooltip = "text") %>% config(displayModeBar = FALSE)
  })

  output$k12_spell_table <- renderDT({
    df <- filtered_spells()
    cols_to_show <- c("District", "Title", "Position", "Broad_Category",
                      "First_Seen_Date", "Last_Seen_Date", "Estimated_Days_Open", "Status")
    existing_cols <- intersect(cols_to_show, names(df))

    df_display <- if (nrow(df) > 0) {
      df %>% select(all_of(existing_cols)) %>% arrange(desc(Estimated_Days_Open))
    } else {
      df[0, existing_cols, drop = FALSE]
    }

    datatable(
      df_display %>% rename(any_of(c(`Days listed` = "Estimated_Days_Open", `First seen` = "First_Seen_Date",
                                     `Last seen` = "Last_Seen_Date", Listing = "Status",
                                     Category = "Broad_Category"))),
      options = list(
        pageLength = 15,
        lengthMenu = c(10, 15, 25, 50, 100),
        dom = "Bfrtip",
        buttons = c("copy", "csv", "excel")
      ),
      extensions = "Buttons",
      rownames = FALSE,
      escape = FALSE
    )
  })

  # ------------------ Higher Ed Vacancy Spells ------------------
  observe({
    if (nrow(he_job_duration_spells) > 0) {
      insts <- sort(unique(he_job_duration_spells$Institution))
      updateSelectInput(session, "he_spell_institution",
                        choices = c("All Institutions" = "all", setNames(insts, insts)),
                        selected = "all")
    }
  })

  filtered_he_spells <- reactive({
    req(nrow(he_job_duration_spells) > 0)
    df <- he_job_duration_spells

    if (!is.null(input$he_spell_status) && !identical(input$he_spell_status, "all")) {
      df <- df %>% filter(Status == input$he_spell_status)
    }

    if (!is.null(input$he_spell_job_type) && !identical(input$he_spell_job_type, "all")) {
      df <- df %>% filter(Job_Type == input$he_spell_job_type)
    }

    if (!is.null(input$he_spell_discipline) && !identical(input$he_spell_discipline, "all")) {
      disc <- input$he_spell_discipline
      if (disc == "stem" && "is_stem" %in% names(df)) df <- df %>% filter(is_stem == 1)
      else if (disc == "health" && "is_health" %in% names(df)) df <- df %>% filter(is_health == 1)
      else if (disc == "cte" && "is_cte" %in% names(df)) df <- df %>% filter(is_cte == 1)
    }

    if (!is.null(input$he_spell_institution) && !identical(input$he_spell_institution, "all")) {
      df <- df %>% filter(Institution == input$he_spell_institution)
    }

    df
  })

  output$he_spell_median_box <- renderUI({
    df <- filtered_he_spells()
    med <- if (nrow(df) > 0) round(median(df$Estimated_Days_Open, na.rm = TRUE)) else 0
    kpi_value_box(
      paste0(med, " Days"),
      "Median Vacancy Duration",
      icon = icon("stopwatch"),
      color = "blue"
    )
  })

  output$he_spell_active_box <- renderUI({
    df <- filtered_he_spells()
    active_n <- if (nrow(df) > 0) sum(df$Status == "Still Active", na.rm = TRUE) else 0
    kpi_value_box(
      scales::comma(active_n),
      "Currently Open Searches",
      icon = icon("door-open"),
      color = "green"
    )
  })

  output$he_spell_persistent_box <- renderUI({
    df <- filtered_he_spells()
    persist_n <- if (nrow(df) > 0) sum(df$Status == "Still Active" & df$Estimated_Days_Open >= 90, na.rm = TRUE) else 0
    kpi_value_box(
      scales::comma(persist_n),
      "Persistent Searches (≥90 Days)",
      icon = icon("triangle-exclamation"),
      color = "red"
    )
  })

  output$he_spell_hardest_box <- renderUI({
    df <- filtered_he_spells()
    hardest <- "None"
    if (nrow(df) >= 1 && "Category" %in% names(df)) {
      cat_dur <- df %>%
        group_by(Category) %>%
        summarize(med = median(Estimated_Days_Open, na.rm = TRUE), n = n(), .groups = "drop") %>%
        filter(n >= 1) %>%
        arrange(desc(med))
      if (nrow(cat_dur) > 0) hardest <- cat_dur$Category[1]
    }
    kpi_value_box(
      hardest,
      "Longest Duration Discipline",
      icon = icon("building-columns"),
      color = "purple"
    )
  })

  output$he_spell_duration_plot <- renderPlotly({
    df <- filtered_he_spells()
    if (nrow(df) == 0) {
      p <- ggplot() +
        annotate("text", x = 0.5, y = 0.5, label = "No vacancy spells match the selected filter criteria", size = 4, color = "#666666") +
        theme_void()
      return(ggplotly(p) %>% config(displayModeBar = FALSE))
    }

    cat_summary <- df %>%
      group_by(Category) %>%
      summarize(
        Median_Days = round(median(Estimated_Days_Open, na.rm = TRUE)),
        Postings = n(),
        .groups = "drop"
      ) %>%
      filter(!is.na(Category) & Category != "" & Postings >= 1) %>%
      arrange(desc(Median_Days)) %>%
      head(12)

    if (nrow(cat_summary) == 0) {
      p <- ggplot() +
        annotate("text", x = 0.5, y = 0.5, label = "No discipline data available for selected filter", size = 4, color = "#666666") +
        theme_void()
      return(ggplotly(p) %>% config(displayModeBar = FALSE))
    }

    p <- ggplot(cat_summary, aes(
      x = reorder(Category, Median_Days),
      y = Median_Days,
      text = paste0("<b>", Category, "</b><br>Median Open: ", Median_Days, " days<br>Total Spells: ", Postings)
    )) +
      geom_col(fill = "#2a78d6", width = 0.65) +
      coord_flip() +
      labs(x = NULL, y = "Median Days Open") +
      theme_minimal() +
      theme(
        axis.text.y = element_text(size = 9),
        panel.grid.major.y = element_blank()
      )

    ggplotly(p, tooltip = "text") %>% config(displayModeBar = FALSE)
  })

  output$he_spell_distrib_plot <- renderPlotly({
    df <- filtered_he_spells()
    bin_levels <- c("1–30 Days", "31–60 Days", "61–90 Days", "91–180 Days", "180+ Days")
    if (nrow(df) == 0) {
      p <- ggplot() +
        annotate("text", x = 0.5, y = 0.5, label = "No vacancy spells match the selected filter criteria", size = 4, color = "#666666") +
        theme_void()
      return(ggplotly(p) %>% config(displayModeBar = FALSE))
    }

    df <- df %>%
      mutate(Duration_Bin = case_when(
        Estimated_Days_Open <= 30 ~ "1–30 Days",
        Estimated_Days_Open <= 60 ~ "31–60 Days",
        Estimated_Days_Open <= 90 ~ "61–90 Days",
        Estimated_Days_Open <= 180 ~ "91–180 Days",
        TRUE ~ "180+ Days"
      )) %>%
      mutate(Duration_Bin = factor(Duration_Bin, levels = bin_levels))

    bin_counts <- df %>%
      count(Duration_Bin, name = "Count") %>%
      tidyr::complete(Duration_Bin = factor(bin_levels, levels = bin_levels), fill = list(Count = 0)) %>%
      filter(!is.na(Duration_Bin))

    p <- ggplot(bin_counts, aes(
      x = Duration_Bin, y = Count,
      text = paste0("<b>", Duration_Bin, "</b><br>Spells: ", Count)
    )) +
      geom_col(fill = "#9b59b6", width = 0.6) +
      labs(x = NULL, y = "Number of Vacancies") +
      theme_minimal() +
      theme(
        axis.text.x = element_text(angle = 25, hjust = 1, size = 8),
        panel.grid.major.x = element_blank()
      )

    ggplotly(p, tooltip = "text") %>% config(displayModeBar = FALSE)
  })

  output$he_spell_table <- renderDT({
    df <- filtered_he_spells()
    cols_to_show <- c("Institution", "Title", "Job_Type", "Category",
                      "First_Seen_Date", "Last_Seen_Date", "Estimated_Days_Open", "Status")
    existing_cols <- intersect(cols_to_show, names(df))

    df_display <- if (nrow(df) > 0) {
      df %>% select(all_of(existing_cols)) %>% arrange(desc(Estimated_Days_Open))
    } else {
      df[0, existing_cols, drop = FALSE]
    }

    datatable(
      df_display %>% rename(any_of(c(`Days listed` = "Estimated_Days_Open", `First seen` = "First_Seen_Date",
                                     `Last seen` = "Last_Seen_Date", Listing = "Status",
                                     Category = "Broad_Category"))),
      options = list(
        pageLength = 15,
        lengthMenu = c(10, 15, 25, 50, 100),
        dom = "Bfrtip",
        buttons = c("copy", "csv", "excel")
      ),
      extensions = "Buttons",
      rownames = FALSE,
      escape = FALSE
    )
  })
}

shinyApp(ui = ui, server = server)
