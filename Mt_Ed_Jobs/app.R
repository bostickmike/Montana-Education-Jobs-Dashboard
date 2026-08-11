library(shiny)
library(shinydashboard)
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

#--------------------------------------------------
# Load K-12 data
#--------------------------------------------------
combineddata <- read.csv("combinedclean.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("District", "title", "position", "location", "date_posted", "url"), "combinedclean.csv") %>%
  select(District, title, position, location, date_posted, url) %>%
  mutate(District = str_squish(as.character(District))) %>%
  mutate(date_posted = format_posted_or_listed_date(date_posted)) %>%
  arrange(District, title) %>%
  mutate(url = paste0('<a href="', url, '" target="_blank">', url, '</a>')) %>%
  rename(Title = title, Position = position, Location = location,
         `Posted / listed` = date_posted, Link = url)

# salarymap2.csv covers only this project's directly-scraped districts
# (k12_district_registry.csv), not Montana's full ~398-district universe --
# combineddata above has many more distinct District values (every district
# the OPI statewide fallback feed surfaces), but only the registry's districts
# have a Latitude/Longitude to put on the map. See DATA_COOKBOOK.md's "OPI
# statewide fallback feed" note.
mapdata2_k12 <- read.csv("salarymap2.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("District", "County", "Latitude", "Longitude", "Job_Link",
                             "Teacher_Count", "Teacher_Salary_10th_Pctile", "Teacher_Avg_Salary",
                             "Teacher_Salary_90th_Pctile", "Salary_Year", "Salary_Source",
                             "Teachers_Total_FTE", "Enrollment",
                             "Median_Household_Income", "Median_Gross_Rent", "Mining_Employment_Share",
                             "Population_Change_Pct", "ACS_Year", "Child_Poverty_Rate", "SAIPE_Year"),
                           "salarymap2.csv") %>%
  rename(Name = District)

# Weekly ALL-category posting totals per district/institution -- powers the
# sparkline trend next to each entity's raw count on the Top Hiring tables.
k12_district_weekly_totals <- read.csv("k12_district_weekly_totals.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("District", "Archive_Date", "n"), "k12_district_weekly_totals.csv") %>%
  mutate(Archive_Date = as.Date(Archive_Date))
he_institution_weekly_totals <- read.csv("he_institution_weekly_totals.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("Institution", "Archive_Date", "n"), "he_institution_weekly_totals.csv") %>%
  mutate(Archive_Date = as.Date(Archive_Date))

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
  box(width = 12, status = "info",
      div(
        tags$span(style = "font-weight:bold;", paste0(label, ": ")),
        tags$span(mover$name),
        tags$span(style = paste0("color:", delta_color, "; font-weight:bold; margin-left:8px;"),
                   paste0(arrow, " ", abs(mover$delta))),
        tags$span(style = "color:#999; font-size:0.85em; margin-left:6px;",
                   paste0("(", mover$prior, " → ", mover$latest,
                          " since ", format(mover$prior_date, "%b %d"), ")"))
      )
  )
}

k12sum <- read.csv("allsum.csv", fileEncoding = "UTF-8") %>%
  validate_and_pad_schema(c("Broad_Category", "Archive_Date", "District", "sum"), "allsum.csv") %>%
  mutate(District = str_squish(as.character(District)),
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
  mutate(Broad_Category = dplyr::recode(Broad_Category,
                                        "English Language Arts Secondary" = "Engl. LA",
                                        "Secondary Social Studies" = "Soc. St.",
                                        "Special Education - General" = "SpEd - General",
                                        "Special Education - Resource/Life Skills" = "SpEd - Resource/LS",
                                        "CTE - Trades, Ag & Technical" = "CTE - Trades/Ag",
                                        "CTE - Business & Family Sciences" = "CTE - Biz/Family"),
         District = str_squish(iconv(District, from = "", to = "UTF-8"))) %>%
  filter(Broad_Category != "Other")

#--------------------------------------------------
# Load Higher Ed data
#--------------------------------------------------
ccdata <- read_xlsx("hedata.xlsx") %>%
  validate_and_pad_schema(c("Institution", "Title", "Location", "Posted_Date", "Link"), "hedata.xlsx") %>%
  select(Institution, Title, Location, Posted_Date, Link) %>%
  arrange(Institution, Title) %>%
  mutate(
    Appointment = classify_he_appointment(Title),
    Posted_Date = format_posted_or_listed_date(Posted_Date)
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
  validate_and_pad_schema(c("title", "Archive_Date", "location", "District"), "k12jobanalysis.csv") %>%
  mutate(Archive_Date = as.Date(Archive_Date))

k12_new_this_week <- {
  dates <- sort(unique(k12_history$Archive_Date))
  if (length(dates) >= 2) {
    latest <- dates[length(dates)]
    previous <- dates[length(dates) - 1]
    k12_history %>%
      filter(Archive_Date == latest) %>%
      anti_join(k12_history %>% filter(Archive_Date == previous), by = c("title", "location", "District"))
  } else {
    k12_history[0, ]
  }
}

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

# Vacancy rate needs a minimum FTE to be a meaningful comparison -- a
# no-op against Montana's real data (every registered district has 50+
# FTE) but keeps a future small entity from producing a noisy rate.
VACANCY_RATE_MIN_FTE <- 10

DLI_SALARY_SOURCE_URL <- "https://lmi.mt.gov/Publications/index"
IPEDS_SALARY_SOURCE_URL <- "https://educationdata.urban.org"

k12_teacher_current_counts <- k12_history %>%
  filter(Archive_Date == max(Archive_Date)) %>%
  count(District, name = "TeacherCurrentCount")

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
         Child_Poverty_Rate, SAIPE_Year)

he_current_counts <- ccdata %>% count(Institution, name = "CurrentCount")
he_sample_titles <- ccdata %>%
  group_by(Institution) %>%
  summarize(SampleTitles = paste(head(Title, 3), collapse = "; "), .groups = "drop")
he_weekly_new <- he_new_this_week %>% count(Institution, name = "WeeklyNew")

he_faculty_current_counts <- he_history %>%
  filter(Archive_Date == max(Archive_Date)) %>%
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
    Child_Poverty_Rate = NA_real_, SAIPE_Year = NA_integer_
  ) %>%
  select(Name, Longitude, Latitude, Type, CurrentCount, WeeklyNew, SampleTitles,
         Link, Teacher_Count, Teacher_Salary_10th_Pctile, Teacher_Avg_Salary,
         Teacher_Salary_90th_Pctile, Salary_Year,
         Faculty_Avg_Salary, Faculty_Avg_Salary_Professor, Faculty_Count,
         Faculty_Avg_Salary_Y1Ago, Faculty_Avg_Salary_Y2Ago,
         Vacancy_Rate, Vacancy_Numerator, Vacancy_Denominator, Salary_Source, County,
         Enrollment, Students_Per_Teacher, Enrollment_Change_Pct, Pell_Recipient_Share, Pell_Year,
         Median_Household_Income, Median_Gross_Rent, Mining_Employment_Share, Population_Change_Pct, ACS_Year,
         Child_Poverty_Rate, SAIPE_Year)

combined_map_data <- bind_rows(map_k12, map_he)

# Map marker size/color -- ported verbatim.
MAP_MARKER_MIN_RADIUS <- 6
MAP_MARKER_MAX_RADIUS <- 24
map_marker_radius <- function(current_count) {
  pmin(MAP_MARKER_MAX_RADIUS, MAP_MARKER_MIN_RADIUS + 1.2 * sqrt(current_count))
}
compute_vacancy_rate_domain <- function(vacancy_rate) {
  if (all(is.na(vacancy_rate))) c(0, 1) else range(vacancy_rate, na.rm = TRUE)
}
vacancy_rate_domain <- compute_vacancy_rate_domain(combined_map_data$Vacancy_Rate)
vacancy_rate_palette <- colorNumeric(palette = "YlOrRd", domain = vacancy_rate_domain, na.color = "#9e9e9e")

#--------------------------------------------------
# UI
#--------------------------------------------------
ui <- dashboardPage(
  skin = 'black',
  dashboardHeader(title = "Mont Edu Jobs"),
  dashboardSidebar(
    sidebarMenu(
      id = "sidebar_tabs",
      menuItem("Home", tabName = "intro", icon = icon("house")),
      menuItem("Map", tabName = "map_tab", icon = icon("map-location-dot")),
      menuItem("K-12 Careers", tabName = "k12_root", icon = icon("school"),
               menuSubItem("Jobs Table", tabName = "k12_table"),
               menuSubItem("District Summary", tabName = "k12_summary"),
               menuSubItem("Longitudinal Teacher Trends", tabName = "k12_trends"),
               menuSubItem("Current Teacher Trends", tabName = "k12_current"),
               menuSubItem("New This Week", tabName = "k12_new")
      ),
      menuItem("Higher Ed Careers", tabName = "he_root", icon = icon("university"),
               menuSubItem("Jobs Table", tabName = "he_table"),
               menuSubItem("Institution Summary", tabName = "he_summary"),
               menuSubItem("Longitudinal Faculty Trends", tabName = "he_trends"),
               menuSubItem("Current Faculty Trends", tabName = "he_current"),
               menuSubItem("New This Week", tabName = "he_new")
      )
    )
  ),
  dashboardBody(
    tags$head(
      tags$style(HTML("
    .main-header .logo {
      font-size: 19px;
    }
    .leaflet-tooltip {
      max-width: 800px !important;
      min-width: 400px !important;
      white-space: normal !important;
      background-color: rgba(255,255,255,0.95);
      padding: 6px 10px;
      border-radius: 6px;
      border: 1px solid gray;
      font-size: 14px;
      display: inline-block;
    }
  ")),
      tags$script(HTML("
    $(document).on('click', '.sidebar-menu a[data-toggle=\"tab\"]', function() {
      if ($(window).width() < 768) {
        $('body').removeClass('sidebar-open');
      }
    });
  "))
    )
    ,
    tabItems(
      # ------------------ Global Introduction ------------------
      tabItem(
        tabName = "intro",
        h1("Education Jobs in Montana"),
        uiOutput("data_load_issues_banner"),
        fluidRow(
          valueBoxOutput("kpi_k12_total", width = 4),
          valueBoxOutput("kpi_he_total", width = 4),
          valueBoxOutput("kpi_last_refreshed", width = 4)
        ),
        fluidRow(
          column(width = 6, uiOutput("k12_biggest_mover")),
          column(width = 6, uiOutput("he_biggest_mover"))
        ),
        fluidRow(
          box(title = "Top K-12 Hiring Districts This Week", width = 6, status = "primary",
              div(style = "overflow-x: auto;", tableOutput("top_k12_districts"))),
          box(title = "Top Higher Ed Hiring Institutions This Week", width = 6, status = "primary",
              div(style = "overflow-x: auto;", tableOutput("top_he_institutions")))
        ),
        fluidRow(
          box(title = "Highest Teacher Vacancy Rate", width = 6, status = "primary",
              withSpinner(plotlyOutput("k12_vacancy_leaderboard", height = 320)),
              helpText("Districts with at least", VACANCY_RATE_MIN_FTE, "teacher FTE.")),
          box(title = "Highest Faculty Vacancy Rate", width = 6, status = "primary",
              withSpinner(plotlyOutput("he_vacancy_leaderboard", height = 320)),
              helpText("Institutions with at least", VACANCY_RATE_MIN_FTE, "full-time faculty."))
        ),
        div(style = "color:#999; font-size:0.8em; padding: 0 5px 5px;",
            "K-12 vacancy rate is current teacher postings ÷ CCD teacher FTE; Higher Ed vacancy rate is current instructor/faculty postings ÷ IPEDS full-time instructional staff. ",
            "The two use different staffing sources and reporting years — compare rates within a type (district vs. district, institution vs. institution), not across K-12 and Higher Ed."),
        div(style = "text-align:center; color:#999; font-size:0.85em; padding:15px;",
            paste0("Refreshed on: ", last_refreshed_date, " · Created by Michael Bostick"))
      ),

      tabItem(
        tabName = "map_tab",
        h1("Where the Openings Are"),
        box(width = 12, title = "Montana Education Job Openings Map", status = "primary",
            checkboxGroupInput(
              "map_types", "Show:",
              choices = c("K-12 Districts" = "K-12 District", "Higher Ed Institutions" = "Higher Ed Institution"),
              selected = c("K-12 District", "Higher Ed Institution"),
              inline = TRUE
            ),
            withSpinner(leafletOutput("combined_map", height = 650)),
            helpText(paste0(
              "Only this project's ", n_distinct(map_k12$Name), " directly-scraped K-12 districts and ",
              n_distinct(map_he$Name), " directly-scraped Higher Ed institutions are shown here (with current openings). ",
              "Postings from every other Montana school district also appear in the K-12 Jobs Table, via the state's own OPI \"Jobs for Teachers\" statewide feed -- but that feed has no map coordinates for those districts, so they aren't plotted. ",
              "Circle size reflects current openings; color reflects teacher/faculty vacancy rate where available. Click a marker to jump to its filtered Jobs Table. ",
              "K-12 and Higher Ed vacancy rates use different staffing sources (CCD vs. IPEDS) and years -- the shared color scale is for a rough at-a-glance read, not a precise cross-type comparison."
            ))
        )
      ),

      tabItem(
        tabName = "k12_table",
        uiOutput("k12_filter_status"),
        DTOutput("k12_jobs")
      ),
      tabItem(
        tabName = "k12_summary",
        h4("One row per directly-scraped district -- current openings, teacher vacancy rate, and salary data"),
        DTOutput("k12_summary_table"),
        uiOutput("k12_summary_footnote")
      ),
      tabItem(
        tabName = "k12_new",
        h4("New teacher postings since the previous weekly snapshot"),
        DTOutput("k12_new_table")
      ),

      # ------------------ K-12 ------------------
      tabItem(
        tabName = "k12_trends",

        radioButtons("k12_detail_level_trends", "Category detail:",
                     choices = c("Simple" = "agg", "Detailed" = "detail"),
                     selected = "agg", inline = TRUE),

        fluidRow(
          column(
            width = 6,
            pickerInput(
              "broad_category",
              "Choose Teacher Category:",
              choices  = sort(unique(k12sum_agg$Broad_Category)),
              selected = sort(unique(k12sum_agg$Broad_Category)),
              multiple = TRUE,
              width = "100%",
              options = pickerOptions(actionsBox = TRUE, liveSearch = TRUE, selectedTextFormat = "count > 3")
            )
          ),
          column(
            width = 6,
            selectInput(
              "district_trend",
              "Choose District:",
              choices = sort(unique(k12sum$District)),
              selected = "Total",
              width = "100%"
            )
          )
        ),

        sliderInput(
          "k12_scroll",
          "Scroll timeline:",
          min = min(k12sum$Archive_Date),
          max = max(k12sum$Archive_Date),
          value = c(max(k12sum$Archive_Date) - 365,
                    max(k12sum$Archive_Date)),
          timeFormat = "%Y-%m-%d",
          width = "100%"
        ),

        withSpinner(plotlyOutput("k12_longitudinal_plot"))
      ),

      tabItem(
        tabName = "k12_current",

        radioButtons("k12_detail_level_current", "Category detail:",
                     choices = c("Simple" = "agg", "Detailed" = "detail"),
                     selected = "agg", inline = TRUE),

        selectInput(
          "district_current",
          "Choose District:",
          choices = sort(unique(k12nowsum$District)),
          selected = "Total"
        ),

        div(style = "overflow-x: auto;", withSpinner(tableOutput("k12_current_trends_table")))
      ),

      # ------------------ Higher Ed ------------------
      tabItem(
        tabName = "he_table",
        uiOutput("he_filter_status"),
        radioButtons(
          "he_table_appointment", "Appointment:",
          choices = c(
            "All roles" = "all",
            "Faculty/instructor (non-adjunct)" = "Faculty/instructor (non-adjunct)",
            "Adjunct/part-time faculty" = "Adjunct/part-time faculty",
            "Other / not faculty" = "Other / not faculty"
          ),
          selected = "all", inline = TRUE
        ),
        DTOutput("he_jobs")
      ),
      tabItem(
        tabName = "he_summary",
        h4("One row per directly-scraped institution -- current openings, faculty vacancy rate, and salary data"),
        DTOutput("he_summary_table"),
        uiOutput("he_summary_footnote")
      ),
      tabItem(
        tabName = "he_trends",

        radioButtons("he_detail_level_trends", "Category detail:",
                     choices = c("Simple" = "agg", "Detailed" = "detail"),
                     selected = "agg", inline = TRUE),

        fluidRow(
          column(
            width = 6,
            pickerInput(
              "he_category",
              "Choose Category:",
              choices  = sort(unique(hesum_he_agg$Category)),
              selected = sort(unique(hesum_he_agg$Category)),
              multiple = TRUE,
              width = "100%",
              options = pickerOptions(actionsBox = TRUE, liveSearch = TRUE, selectedTextFormat = "count > 3")
            )
          ),
          column(
            width = 6,
            selectInput(
              "inst_trend",
              "Select Institution:",
              choices = sort(unique(hesum_he$Institution)),
              selected = "Total",
              width = "100%"
            )
          )
        ),

        textOutput("he_slider_label"),
        sliderInput(
          "he_scroll",
          "Scroll timeline:",
          min = min(hesum_he$Archive_Date),
          max = max(hesum_he$Archive_Date),
          value = c(
            max(hesum_he$Archive_Date) - 365,
            max(hesum_he$Archive_Date)
          ),
          timeFormat = "%Y-%m-%d",
          width = "100%"
        ),

        radioButtons("he_chart_type", NULL, choices = c(
          "All Jobs" = "all",
          "Faculty/instructor (non-adjunct)" = "Instructor/Teacher/Faculty",
          "Adjunct/part-time faculty" = "Adjunct/Part-Time Faculty"
        ), selected = "all", inline = TRUE),

        withSpinner(plotlyOutput("he_longitudinal_plot"))),

      tabItem(tabName = "he_current",
              radioButtons("he_detail_level_current", "Category detail:",
                           choices = c("Simple" = "agg", "Detailed" = "detail"),
                           selected = "agg", inline = TRUE),
              radioButtons("he_current_appointment", "Appointment:",
                           choices = c(
                             "All faculty postings" = "all",
                             "Faculty/instructor (non-adjunct)" = "Instructor/Teacher/Faculty",
                             "Adjunct/part-time faculty" = "Adjunct/Part-Time Faculty"
                           ),
                           selected = "all", inline = TRUE),
              selectInput("inst_current", "Select Institution:",
                          choices = sort(unique(henowsum_he$Institution)), selected = "Total"),
              div(style = "overflow-x: auto;", withSpinner(tableOutput("he_current_trends_table")))),

      tabItem(
        tabName = "he_new",
        h4("New faculty postings since the previous weekly snapshot"),
        radioButtons(
          "he_new_appointment", "Appointment:",
          choices = c(
            "All faculty postings" = "all",
            "Faculty/instructor (non-adjunct)" = "Faculty/instructor (non-adjunct)",
            "Adjunct/part-time faculty" = "Adjunct/part-time faculty"
          ),
          selected = "all", inline = TRUE
        ),
        DTOutput("he_new_table")
      )
    )
  )
)


#--------------------------------------------------
# Server
#--------------------------------------------------
server <- function(input, output, session) {

  selected_district <- reactiveVal(NULL)
  selected_institution <- reactiveVal(NULL)

  output$data_load_issues_banner <- renderUI({
    req(length(DATA_LOAD_ISSUES) > 0)
    box(width = 12, status = "danger", title = "Data issue detected",
        tags$ul(lapply(DATA_LOAD_ISSUES, tags$li)),
        helpText("This is a schema problem in the underlying data pipeline, not something wrong with your view of the dashboard -- the missing field(s) above need a pipeline fix."))
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

  output$kpi_k12_total <- renderValueBox({
    valueBox(format(nrow(combineddata), big.mark = ","),
             tagList("Open K-12 Postings", wow_delta_ui(compute_wow_delta(k12_district_weekly_totals))),
             icon = tags$i(HTML(make_sparkline_svg_light(statewide_weekly_series(k12_district_weekly_totals)))),
             color = "blue")
  })
  output$kpi_he_total <- renderValueBox({
    valueBox(format(nrow(ccdata), big.mark = ","),
             tagList(
               "Open Higher Ed Postings",
               tags$small(
                 style = "display: block; font-size: 11px; opacity: 0.85;",
                 sprintf(
                   "%s faculty/instructor (non-adjunct) | %s adjunct/part-time faculty",
                   format(he_faculty_counts$faculty_instructor, big.mark = ","),
                   format(he_faculty_counts$adjunct_part_time, big.mark = ",")
                 )
               ),
               wow_delta_ui(compute_wow_delta(he_institution_weekly_totals))
             ),
             icon = tags$i(HTML(make_sparkline_svg_light(statewide_weekly_series(he_institution_weekly_totals)))),
             color = "purple")
  })
  output$kpi_last_refreshed <- renderValueBox({
    valueBox(last_refreshed_date, "Last Refreshed", icon = icon("calendar"), color = "green")
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
      k12_new_this_week %>% select(title, District, location, Broad_Category, url),
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

  # -------- K-12 --------
  output$k12_jobs <- renderDT({
    df <- combineddata
    if (!is.null(selected_district())) df <- df %>% filter(District == selected_district())
    datatable(df, filter = "top", escape = FALSE, extensions = "Buttons",
              options = list(scrollX = TRUE, dom = "Bfrtip", buttons = c("copy", "csv", "print")))
  })

  output$k12_filter_status <- renderUI({
    if (is.null(selected_district())) return(NULL)
    div(style = "margin-bottom: 10px;",
        strong(paste("Showing:", selected_district())),
        actionButton("clear_k12_filter", "Show All Districts", class = "btn-xs", style = "margin-left: 10px;")
    )
  })
  observeEvent(input$clear_k12_filter, { selected_district(NULL) })

  # District Summary -- everything the map popups show, as a real
  # exportable table. Teacher_Avg_Salary + 10th/90th percentile band (MT
  # DLI Teacher Compensation Report), not a base-salary-plus-prior-year
  # pair -- see DATA_COOKBOOK.md for why this is a different metric.
  output$k12_summary_table <- renderDT({
    k12_rows <- combined_map_data %>% filter(Type == "K-12 District")
    year <- unique(na.omit(k12_rows$Salary_Year))
    salary_year_label <- if (length(year) > 0) year[1] else "current year"

    df <- k12_rows %>%
      arrange(desc(CurrentCount)) %>%
      transmute(
        District = Name,
        County,
        `Current Openings` = CurrentCount,
        `New This Week` = WeeklyNew,
        `Teacher Vacancy Rate` = ifelse(is.na(Vacancy_Rate), NA_character_, scales::percent(Vacancy_Rate, accuracy = 0.1)),
        Enrollment,
        `Students per Teacher` = ifelse(is.na(Students_Per_Teacher), NA_character_, sprintf("%.1f", Students_Per_Teacher)),
        `Teacher Avg Salary` = ifelse(is.na(Teacher_Avg_Salary), NA_character_, scales::dollar(Teacher_Avg_Salary)),
        `Teacher Salary Range (10th-90th %ile)` = ifelse(
          is.na(Teacher_Salary_10th_Pctile) | is.na(Teacher_Salary_90th_Pctile), NA_character_,
          paste0(scales::dollar(Teacher_Salary_10th_Pctile), " - ", scales::dollar(Teacher_Salary_90th_Pctile))
        ),
        `County Median Income` = ifelse(is.na(Median_Household_Income), NA_character_, scales::dollar(Median_Household_Income)),
        `County Median Rent` = ifelse(is.na(Median_Gross_Rent), NA_character_, paste0(scales::dollar(Median_Gross_Rent), "/mo")),
        `County Mining/Energy Jobs` = ifelse(is.na(Mining_Employment_Share), NA_character_, scales::percent(Mining_Employment_Share, accuracy = 0.1)),
        `County Population Trend (5yr)` = ifelse(is.na(Population_Change_Pct), NA_character_,
                                                   paste0(ifelse(Population_Change_Pct >= 0, "+", ""), scales::percent(Population_Change_Pct, accuracy = 0.1))),
        `District Child Poverty Rate` = ifelse(is.na(Child_Poverty_Rate), NA_character_, scales::percent(Child_Poverty_Rate, accuracy = 0.1))
      )
    names(df)[names(df) == "Teacher Avg Salary"] <- paste0("Teacher Avg Salary (", salary_year_label, ")")

    datatable(df, filter = "top", extensions = "Buttons",
              options = list(scrollX = TRUE, dom = "Bfrtip", buttons = c("copy", "csv", "print"), pageLength = 18))
  })

  output$k12_summary_footnote <- renderUI({
    year <- unique(na.omit(combined_map_data$Salary_Year[combined_map_data$Type == "K-12 District"]))
    source <- unique(na.omit(combined_map_data$Salary_Source[combined_map_data$Type == "K-12 District"]))
    acs_year <- unique(na.omit(combined_map_data$ACS_Year[combined_map_data$Type == "K-12 District"]))
    saipe_year <- unique(na.omit(combined_map_data$SAIPE_Year[combined_map_data$Type == "K-12 District"]))
    req(length(year) > 0, length(source) > 0)
    tagList(
      helpText(
        "Salary data:", source[1], paste0("(", year[1], " school year)"), "—",
        tags$a(href = DLI_SALARY_SOURCE_URL, target = "_blank", "lmi.mt.gov"),
        ". Average salary and 10th/90th percentile band -- not a contract base salary."
      ),
      if (length(acs_year) > 0) {
        helpText(
          "County context (income, rent, mining/energy employment share, population trend): US Census Bureau, American Community Survey 5-Year Estimates",
          paste0("(", acs_year[1], ")"), "—",
          tags$a(href = "https://www.census.gov/data/developers/data-sets/acs-5year.html", target = "_blank", "census.gov"),
          ". County-level, not district-level -- sibling districts in the same county share the same figures."
        )
      },
      if (length(saipe_year) > 0) {
        helpText(
          "District child poverty rate: US Census Bureau, Small Area Income and Poverty Estimates (SAIPE)",
          paste0("(", saipe_year[1], ")"), "—",
          tags$a(href = "https://www.census.gov/programs-surveys/saipe/data/datasets.html", target = "_blank", "census.gov/saipe"),
          ". District-level. For districts split between an elementary and a high-school district, this is an unweighted average of the two rates -- see DATA_COOKBOOK.md."
        )
      }
    )
  })

  # -------- Combined map (Introduction tab) --------
  output$combined_map <- renderLeaflet({
    leaflet() %>%
      addTiles() %>%
      setView(lng = -111.5, lat = 46.8, zoom = 7) %>%
      addLegend(position = "bottomright", pal = vacancy_rate_palette, values = vacancy_rate_domain,
                title = "Vacancy rate", labFormat = labelFormat(suffix = "%", transform = function(x) 100 * x),
                na.label = "N/A")
  })
  outputOptions(output, "combined_map", suspendWhenHidden = FALSE)

  map_filtered <- reactive({
    df <- combined_map_data %>% filter(Type %in% input$map_types, CurrentCount > 0)
    df
  })

  observe({
    df <- map_filtered()

    popups <- with(df, paste0(
      "<div><strong>", Name, "</strong><br/>", Type, "</div>",
      "<div>Current openings: <strong>", CurrentCount, "</strong></div>",
      "<div>New this week: ", WeeklyNew, "</div>",
      ifelse(!is.na(Vacancy_Rate),
             paste0("<div>", ifelse(Type == "K-12 District", "Teacher", "Faculty"),
                    " vacancy rate: ", scales::percent(Vacancy_Rate, accuracy = 0.1), "</div>"),
             ""),
      ifelse(nzchar(SampleTitles), paste0("<div>Recent postings: ", SampleTitles, "</div>"), ""),
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
                    " &middot; ", Salary_Year, "</div>"),
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
             paste0("<div style='font-size:0.85em;color:#666;'>District: ",
                    scales::percent(Child_Poverty_Rate, accuracy = 0.1), " child poverty rate</div>"),
             ""),
      "<div style='margin-top:6px;'>",
      "<a href='", Link, "' target='_blank'>Careers page</a>",
      " &nbsp;|&nbsp; ",
      "<a href='#' onclick=\"Shiny.setInputValue('popup_view_jobs', '",
      gsub("'", "&#39;", Name, fixed = TRUE),
      "', {priority: 'event'}); return false;\">View all jobs &rarr;</a>",
      "</div>"
    ))

    leafletProxy("combined_map", data = df) %>%
      clearMarkers() %>%
      addCircleMarkers(
        lng = ~Longitude, lat = ~Latitude,
        radius = ~map_marker_radius(CurrentCount),
        fillColor = ~vacancy_rate_palette(Vacancy_Rate),
        color = "#333333", weight = 1,
        fillOpacity = 0.85,
        layerId = ~Name,
        popup = popups
      )
  })

  observeEvent(input$popup_view_jobs, {
    entity <- input$popup_view_jobs
    row <- combined_map_data %>% filter(Name == entity)
    req(nrow(row) > 0)

    if (row$Type[1] == "K-12 District") {
      selected_district(entity)
      updateTabItems(session, "sidebar_tabs", "k12_table")
    } else {
      selected_institution(entity)
      updateTabItems(session, "sidebar_tabs", "he_table")
    }
  })


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
    if (!identical(input$he_table_appointment, "all")) {
      df <- df %>% filter(Appointment == input$he_table_appointment)
    }
    datatable(df, filter = "top", escape = FALSE, extensions = "Buttons",
              options = list(scrollX = TRUE, dom = "Bfrtip", buttons = c("copy", "csv", "print")))
  })

  output$he_filter_status <- renderUI({
    if (is.null(selected_institution())) return(NULL)
    div(style = "margin-bottom: 10px;",
        strong(paste("Showing:", selected_institution())),
        actionButton("clear_he_filter", "Show All Institutions", class = "btn-xs", style = "margin-left: 10px;")
    )
  })
  observeEvent(input$clear_he_filter, { selected_institution(NULL) })

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
        tags$a(href = IPEDS_SALARY_SOURCE_URL, target = "_blank", "educationdata.urban.org")
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
      value = c(max(he_dates) - WINDOW_WEEKS*7, max(he_dates)),
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
    paste0("Showing: ", input$he_scroll[1], " to ", input$he_scroll[2])
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
}

shinyApp(ui = ui, server = server)
