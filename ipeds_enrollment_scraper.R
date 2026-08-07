# Montana HE institution fall enrollment from IPEDS, via the Urban
# Institute's Education Data Portal -- ported from Wyoming's
# ipeds_enrollment_scraper.R, same endpoint/fields/quirks, just fips=30 and
# MT_IPEDS_UNITID_MAP. See Wyoming's own header comment for the full "why"
# on est_fte/rep_fte coalescing and the fall-enrollment endpoint actually
# being FTE data despite its URL segment name -- unchanged here.
#
# Depends on ipeds_salary_scraper.R being sourced first -- reuses its
# fetch_ipeds_paginated() and MT_IPEDS_UNITID_MAP.

suppressMessages({
  library(httr2)
  library(dplyr)
})

IPEDS_ENROLLMENT_ENDPOINT <- "https://educationdata.urban.org/api/v1/college-university/ipeds/fall-enrollment"

clean_ipeds_enrollment_value <- function(x) ifelse(is.na(x) | x < 0, NA_real_, x)

fetch_ipeds_mt_enrollment_for_year <- function(year) {
  url <- paste0(IPEDS_ENROLLMENT_ENDPOINT, "/", year, "/?fips=30")
  fetch_ipeds_paginated(url)
}

# IPEDS publishes fall enrollment with roughly a 1-2 year lag -- walks
# backward the same way find_latest_ipeds_salary_year() does.
find_latest_ipeds_enrollment_year <- function(start_year = as.integer(format(Sys.Date(), "%Y")),
                                               years_back = 5) {
  for (year in seq(start_year, start_year - years_back)) {
    df <- fetch_ipeds_mt_enrollment_for_year(year)
    if (nrow(df) > 0) return(list(year = year, data = df))
  }
  list(year = NA_integer_, data = data.frame())
}

# Pure transformation, kept separate from the network fetch so it's
# testable against a captured fixture.
parse_ipeds_he_enrollment <- function(df, year) {
  if (nrow(df) == 0) {
    return(data.frame(Name = character(0), Enrollment = numeric(0), Enrollment_Year = character(0), stringsAsFactors = FALSE))
  }

  totals <- df %>%
    transmute(
      unitid,
      fte = coalesce(clean_ipeds_enrollment_value(est_fte), clean_ipeds_enrollment_value(rep_fte))
    ) %>%
    group_by(unitid) %>%
    summarize(Enrollment = if (all(is.na(fte))) NA_real_ else sum(fte, na.rm = TRUE), .groups = "drop")

  MT_IPEDS_UNITID_MAP %>%
    left_join(totals, by = "unitid") %>%
    mutate(Enrollment_Year = as.character(year)) %>%
    select(Name, Enrollment, Enrollment_Year)
}

fetch_ipeds_he_enrollment <- function() {
  latest <- find_latest_ipeds_enrollment_year()
  parse_ipeds_he_enrollment(latest$data, latest$year)
}

# Institution enrollment trend vs. n_years_back -- HE's analogue of the
# Census county context chunk's Population_Change_Pct. Kept as a pure
# join+compute function, separate from the two live fetches, so it's
# testable without network access.
compute_enrollment_change <- function(current, prior) {
  if (nrow(current) == 0 || nrow(prior) == 0) {
    return(data.frame(Name = character(0), Enrollment_Change_Pct = numeric(0), stringsAsFactors = FALSE))
  }
  current %>%
    select(Name, Enrollment) %>%
    inner_join(prior %>% select(Name, Enrollment_Prior = Enrollment), by = "Name") %>%
    mutate(Enrollment_Change_Pct = ifelse(!is.na(Enrollment) & !is.na(Enrollment_Prior) & Enrollment_Prior > 0,
                                           (Enrollment - Enrollment_Prior) / Enrollment_Prior, NA_real_)) %>%
    select(Name, Enrollment_Change_Pct)
}

# trend_years_back = 5 matches the K-12 side's Population_Change_Pct window.
fetch_ipeds_he_enrollment_trend <- function(trend_years_back = 5) {
  latest <- find_latest_ipeds_enrollment_year()
  if (is.na(latest$year)) {
    return(data.frame(Name = character(0), Enrollment_Change_Pct = numeric(0), stringsAsFactors = FALSE))
  }
  current <- parse_ipeds_he_enrollment(latest$data, latest$year)
  prior_year <- latest$year - trend_years_back
  prior <- parse_ipeds_he_enrollment(fetch_ipeds_mt_enrollment_for_year(prior_year), prior_year)
  compute_enrollment_change(current, prior)
}
