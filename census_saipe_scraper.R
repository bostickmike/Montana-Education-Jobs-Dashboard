# Montana school-district-level child poverty rate from the US Census
# Bureau's Small Area Income and Poverty Estimates (SAIPE) program, via the
# Census Data API's SAIPE School District time series -- ported from
# Wyoming's census_saipe_scraper.R, but needs the same elementary/HS-split
# handling ccd_staff_scraper.R and salary_scrapers.R already needed:
# Montana's districts aren't uniformly "unified" the way Wyoming's 48 are.
# https://www.census.gov/programs-surveys/saipe/data/datasets.html
#
# SAIPE reports three separate geography types for Montana --
# "school district (unified)" (used by this project's 3 already-unified
# K-12 districts: East Helena, Lockwood, Hamilton), "school district
# (elementary)", and "school district (secondary)" (the other 15 districts,
# each needing both an elementary AND a high-school-district rate). Unlike
# CCD's teachers_total_fte (a real count that can just be summed across an
# elementary+HS pair, see MT_CCD_LEA_MAP), SAIPE reports a RATE, which
# can't be summed the same way -- Child_Poverty_Rate for a split district is
# a plain unweighted average of its elementary and secondary rates, a
# documented simplification (not enrollment-weighted, to keep this scraper
# self-contained rather than depending on ccd_staff_scraper.R just for
# weights) rather than a single authoritative district-wide figure.
#
# MT_SAIPE_DISTRICT_MAP is hand-maintained and confirmed against the live
# API response (2026-08-06, 2022 data), the same way MT_CCD_LEA_MAP and
# MT_DLI_DISTRICT_MAP are -- some HS districts are named after their county
# rather than their town here too (Kalispell's is "Flathead High School
# District", Lewistown's is "Fergus High School District"), matching what
# CCD already showed.

suppressMessages({
  library(httr2)
  library(dplyr)
})

SAIPE_SCHDIST_ENDPOINT <- "https://api.census.gov/data/timeseries/poverty/saipe/schdist"

MT_SAIPE_DISTRICT_MAP <- list(
  "Billings Public Schools" = c("Billings Elementary School District", "Billings High School District"),
  "Missoula County Public Schools" = c("Missoula Elementary School District", "Missoula High School District"),
  "Great Falls Public Schools" = c("Great Falls Elementary School District", "Great Falls High School District"),
  "Bozeman Public Schools" = c("Bozeman Elementary School District", "Bozeman High School District"),
  "Helena Public Schools" = c("Helena Elementary School District", "Helena High School District"),
  "Butte School District 1" = c("Butte Elementary School District", "Butte High School District"),
  "Belgrade School District 44" = c("Belgrade Elementary School District", "Belgrade High School District"),
  "East Helena Public Schools" = c("East Helena K-12"),
  "Lockwood Schools" = c("Lockwood K-12"),
  "Hamilton School District 3" = c("Hamilton K-12 Schools"),
  "Havre Public Schools" = c("Havre Elementary School District", "Havre High School District"),
  "Whitefish School District" = c("Whitefish Elementary School District", "Whitefish High School District"),
  "Columbia Falls School District 6" = c("Columbia Falls Elementary School District", "Columbia Falls High School District"),
  "Polson School District" = c("Polson Elementary School District", "Polson High School District"),
  "Lewistown Public Schools" = c("Lewistown Elementary School District", "Fergus High School District"),
  "Laurel Public Schools" = c("Laurel Elementary School District", "Laurel High School District"),
  "Kalispell Public Schools" = c("Kalispell Elementary School District", "Flathead High School District"),
  "Hardin Public Schools" = c("Hardin Elementary School District", "Hardin High School District"),
  # Added 2026-08-07, confirmed live against the real 2024 SAIPE response
  # for all three geography levels (unified/elementary/secondary) --
  # SAIPE's own naming differs in small ways from CCD's/OPI finance's for
  # the same district (e.g. "Big Sandy K-12 Schools" here vs. CCD's "Big
  # Sandy K-12", no trailing "Schools"), so each name was independently
  # verified rather than copied across files. Unlike MT_DLI_DISTRICT_MAP,
  # both Lame Deer and Lodge Grass DO have real SAIPE data -- no equivalent
  # gap here.
  "Glendive Public Schools" = c("Glendive Elementary School District", "Dawson High School District"),
  "Colstrip Public Schools" = c("Colstrip Elementary School District", "Colstrip High School District"),
  "Sidney Public Schools" = c("Sidney Elementary School District", "Sidney High School District"),
  "Stevensville Public Schools" = c("Stevensville Elementary School District", "Stevensville High School District"),
  "Big Sandy Public Schools" = c("Big Sandy K-12 Schools"),
  "Lame Deer Public Schools" = c("Lame Deer Elementary School District", "Lame Deer High School District"),
  "Poplar Public Schools" = c("Poplar Elementary School District", "Poplar High School District"),
  "Fairview Public Schools" = c("Fairview Elementary School District", "Fairview High School District"),
  "Rocky Boy Public Schools" = c("Rocky Boy Elementary School District", "Rocky Boy High School District"),
  "Ronan Public Schools" = c("Ronan Elementary School District", "Ronan High School District"),
  "Livingston Public Schools" = c("Livingston Elementary School District", "Park High School District"),
  "Lodge Grass Public Schools" = c("Lodge Grass Elementary School District", "Lodge Grass High School District")
)

# Pure transformation: SAIPE's array-of-arrays JSON shape has different
# column names than census_acs_scraper.R's ACS responses (SD_NAME instead
# of NAME), so this doesn't reuse parse_acs_json() -- reusing it would have
# silently tried to coerce SD_NAME (real district name text) to numeric via
# that function's NAME/state/county exclude-list, which doesn't know about
# SD_NAME.
parse_saipe_json <- function(json_text) {
  raw <- jsonlite::fromJSON(json_text)
  if (is.null(raw) || nrow(raw) < 2) {
    return(data.frame())
  }
  header <- raw[1, ]
  body <- as.data.frame(raw[-1, , drop = FALSE], stringsAsFactors = FALSE)
  names(body) <- header
  body
}

fetch_saipe_geography <- function(geocat, year, api_key) {
  resp <- request(SAIPE_SCHDIST_ENDPOINT) %>%
    req_url_query(
      get = paste(c("SD_NAME", "SAEPOVRAT5_17RV_PT"), collapse = ","),
      `for` = paste0("school district (", geocat, ")"),
      `in` = paste0("state:", MT_STATE_FIPS),
      time = year,
      key = api_key
    ) %>%
    req_perform()
  parse_saipe_json(resp_body_string(resp))
}

fetch_census_saipe_child_poverty <- function(year = NULL, api_key = census_api_key()) {
  year <- year %||% latest_saipe_year(api_key = api_key)
  unified <- fetch_saipe_geography("unified", year, api_key)
  elementary <- fetch_saipe_geography("elementary", year, api_key)
  secondary <- fetch_saipe_geography("secondary", year, api_key)
  parse_census_saipe_child_poverty(unified, elementary, secondary, year)
}

# Looks up each of MT_SAIPE_DISTRICT_MAP's 18 districts in whichever of the
# three geography responses has its matching SD_NAME row(s), averaging an
# elementary+HS pair's rates (see this file's header for why an average,
# not a sum). A district whose matching row(s) are entirely absent from
# this run's response gets real NA, not zero.
parse_census_saipe_child_poverty <- function(unified_df, elementary_df, secondary_df, year) {
  empty <- data.frame(District = character(0), Child_Poverty_Rate = numeric(0),
                       SAIPE_Year = integer(0), stringsAsFactors = FALSE)

  all_rows <- dplyr::bind_rows(unified_df, elementary_df, secondary_df)
  if (nrow(all_rows) == 0) return(empty)

  rates_by_name <- all_rows %>%
    transmute(SD_NAME = trimws(SD_NAME),
              rate = clean_acs_value(suppressWarnings(as.numeric(SAEPOVRAT5_17RV_PT))) / 100)

  rows <- lapply(names(MT_SAIPE_DISTRICT_MAP), function(district) {
    sd_names <- MT_SAIPE_DISTRICT_MAP[[district]]
    matched <- rates_by_name %>% filter(SD_NAME %in% sd_names)
    rate <- if (nrow(matched) == 0 || all(is.na(matched$rate))) {
      NA_real_
    } else {
      mean(matched$rate, na.rm = TRUE)
    }
    data.frame(District = district, Child_Poverty_Rate = rate, stringsAsFactors = FALSE)
  })

  result <- dplyr::bind_rows(rows)
  result$SAIPE_Year <- year
  result
}

# SAIPE publishes with a longer lag than ACS 5-Year -- walks backward the
# same way latest_acs5_year() and the other find_latest_*_year() functions
# elsewhere in this project do. Checks against the unified geography (a
# cheap single-request check) since all three geography types publish on
# the same schedule.
latest_saipe_year <- function(start_year = as.integer(format(Sys.Date(), "%Y")),
                               years_back = 4, api_key = census_api_key()) {
  for (year in seq(start_year, start_year - years_back)) {
    result <- tryCatch(fetch_saipe_geography("unified", year, api_key), error = function(e) data.frame())
    if (nrow(result) > 0) return(year)
  }
  stop("latest_saipe_year(): no working SAIPE vintage found in the last ", years_back, " years.")
}
