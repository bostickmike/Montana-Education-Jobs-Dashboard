# Montana K-12 teacher FTE (staff headcount, not job postings) from NCES's
# Common Core of Data (CCD), via the Urban Institute Education Data Portal
# API -- same endpoint/pattern as Wyoming's ccd_staff_scraper.R, just
# fips=30 and a genuinely different district-name-matching problem.
# https://educationdata.urban.org/documentation/
#
# Montana's elementary/HS district fragmentation (confirmed in
# RESEARCH_NOTES.md: ~398 nominal districts vs. Wyoming's 48) means CCD
# reports each of this project's 18 combined "one job-board, one scrape
# target" districts as ONE OR TWO separate CCD LEA records -- an
# elementary-only district (e.g. "Billings Elem") plus a same-town or
# same-county high-school-only district (e.g. "Billings H S"), or
# occasionally one already-unified "K-12" record (East Helena, Lockwood,
# Hamilton). There's no reliable name-matching rule general enough to pair
# these automatically -- some HS districts are named after their town
# ("Billings H S"), others after their county instead ("Fergus H S" is
# Lewistown's real HS district, "Flathead H S" is Kalispell's) -- so
# MT_CCD_LEA_MAP below is hand-maintained and confirmed against the live
# CCD directory response (2026-08-06, 2022 data), the same way Wyoming's
# own IPEDS_UNITID_MAP is hand-maintained rather than derived.
MT_CCD_LEA_MAP <- list(
  "Billings Public Schools" = c("Billings Elem", "Billings H S"),
  "Missoula County Public Schools" = c("Missoula Elem", "Missoula H S"),
  "Great Falls Public Schools" = c("Great Falls Elem", "Great Falls H S"),
  "Bozeman Public Schools" = c("Bozeman Elem", "Bozeman H S"),
  "Helena Public Schools" = c("Helena Elem", "Helena H S"),
  "Butte School District 1" = c("Butte Elem", "Butte H S"),
  "Belgrade School District 44" = c("Belgrade Elem", "Belgrade H S"),
  "East Helena Public Schools" = c("East Helena K-12"),
  "Lockwood Schools" = c("Lockwood K-12"),
  "Hamilton School District 3" = c("Hamilton K-12 Schools"),
  "Havre Public Schools" = c("Havre Elem", "Havre H S"),
  "Whitefish School District" = c("Whitefish Elem", "Whitefish H S"),
  "Columbia Falls School District 6" = c("Columbia Falls Elem", "Columbia Falls H S"),
  "Polson School District" = c("Polson Elem", "Polson H S"),
  "Lewistown Public Schools" = c("Lewistown Elem", "Fergus H S"),
  "Laurel Public Schools" = c("Laurel Elem", "Laurel H S"),
  "Kalispell Public Schools" = c("Kalispell Elem", "Flathead H S"),
  "Hardin Public Schools" = c("Hardin Elem", "Hardin H S")
)

suppressMessages({
  library(httr2)
  library(dplyr)
})

CCD_DISTRICT_DIRECTORY_ENDPOINT <- "https://educationdata.urban.org/api/v1/school-districts/ccd/directory"

fetch_ccd_paginated <- function(url) {
  # CCD directory records have real JSON nulls mixed in with populated
  # fields (a district with no CBSA/CSA assignment, etc.), which breaks a
  # per-record as.data.frame(). simplifyVector = TRUE hands that off to
  # jsonlite, which turns nulls into NA correctly.
  pages <- list()
  while (!is.null(url)) {
    resp <- request(url) %>% req_perform() %>% resp_body_json(simplifyVector = TRUE)
    pages[[length(pages) + 1]] <- resp$results
    url <- resp[["next"]]
  }
  if (length(pages) == 0) return(data.frame())
  dplyr::bind_rows(pages)
}

fetch_ccd_mt_directory_for_year <- function(year) {
  url <- paste0(CCD_DISTRICT_DIRECTORY_ENDPOINT, "/", year, "/?fips=30")
  fetch_ccd_paginated(url)
}

# CCD lags similarly to IPEDS -- walk backward from the current year until a
# non-empty response is found rather than hardcoding a year that will
# eventually go stale.
find_latest_ccd_directory_year <- function(start_year = as.integer(format(Sys.Date(), "%Y")),
                                            years_back = 5) {
  for (year in seq(start_year, start_year - years_back)) {
    df <- fetch_ccd_mt_directory_for_year(year)
    if (nrow(df) > 0) return(list(year = year, data = df))
  }
  list(year = NA_integer_, data = data.frame())
}

# Sums Teachers_Total_FTE/Enrollment across each combined District's one or
# two real CCD LEA records (per MT_CCD_LEA_MAP above). A record genuinely
# missing from that run's CCD response (or with NA teachers_total_fte) drops
# that record out of the sum rather than propagating NA to the whole
# District -- e.g. if only Fergus H S is temporarily missing, Lewistown
# still gets Lewistown Elem's real FTE rather than NA for both.
parse_ccd_teacher_fte <- function(df) {
  if (nrow(df) == 0) {
    return(data.frame(District = character(0), Teachers_Total_FTE = numeric(0),
                       Enrollment = numeric(0), stringsAsFactors = FALSE))
  }

  by_lea <- df %>%
    filter(agency_type == 1, !is.na(number_of_schools), number_of_schools >= 1) %>%
    transmute(
      lea_name = trimws(lea_name),
      Teachers_Total_FTE = ifelse(is.na(teachers_total_fte) | teachers_total_fte < 0, NA_real_, teachers_total_fte),
      Enrollment = ifelse(is.na(enrollment) | enrollment < 0, NA_real_, enrollment)
    )

  rows <- lapply(names(MT_CCD_LEA_MAP), function(district) {
    lea_names <- MT_CCD_LEA_MAP[[district]]
    matched <- by_lea %>% filter(lea_name %in% lea_names)
    if (nrow(matched) == 0) {
      return(data.frame(District = district, Teachers_Total_FTE = NA_real_,
                         Enrollment = NA_real_, stringsAsFactors = FALSE))
    }
    data.frame(
      District = district,
      Teachers_Total_FTE = sum(matched$Teachers_Total_FTE, na.rm = TRUE),
      Enrollment = sum(matched$Enrollment, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })

  dplyr::bind_rows(rows)
}

fetch_ccd_teacher_fte <- function() {
  latest <- find_latest_ccd_directory_year()
  result <- parse_ccd_teacher_fte(latest$data)
  if (nrow(result) > 0) result$CCD_Year <- as.character(latest$year)
  result
}
