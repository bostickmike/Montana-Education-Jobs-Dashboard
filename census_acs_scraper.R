# Montana county-level socioeconomic context from the US Census Bureau's
# American Community Survey (ACS) 5-Year Estimates, via the Census Data API
# directly -- ported from Wyoming's census_acs_scraper.R, same endpoints/
# variables/quirks, just fips=30. See Wyoming's own header comment for the
# full "why" behind each of the four figures (income, rent, mining/oil & gas
# employment share, population trend) and why ACS 5-Year (not the
# Population Estimates Program) is used for the population trend --
# unchanged here.
#
# Requires a free Census API key (https://api.census.gov/data/key_signup.html),
# read from CENSUS_API_KEY (a GitHub Actions secret for the weekly pipeline,
# .Renviron locally) -- confirmed live 2026-08-06 that Montana's endpoints
# need one exactly like Wyoming's do (302-redirect to an error page
# otherwise).
#
# One row per Montana county (56 total, see RESEARCH_NOTES.md's FIPS
# table), joined onto salarymap2.csv's existing County column -- unlike
# Wyoming's own County format ("<Name> County, Wyoming", matching the
# Census API's NAME field exactly), this project's registry stores County
# WITHOUT the state suffix ("Yellowstone County", not "Yellowstone County,
# Montana") -- parse_census_income_rent_population() strips it so the join
# key matches without needing to change the registry's existing format.

suppressMessages({
  library(httr2)
  library(dplyr)
})

ACS_DETAIL_ENDPOINT <- "https://api.census.gov/data/%d/acs/acs5"
ACS_SUBJECT_ENDPOINT <- "https://api.census.gov/data/%d/acs/acs5/subject"
MT_STATE_FIPS <- "30"

`%||%` <- function(x, y) if (is.null(x)) y else x

census_api_key <- function() {
  key <- Sys.getenv("CENSUS_API_KEY")
  if (!nzchar(key)) {
    stop(
      "CENSUS_API_KEY environment variable is not set -- get a free key at ",
      "https://api.census.gov/data/key_signup.html and set it as an environment ",
      "variable (a GitHub Actions secret for the weekly pipeline, .Renviron locally)."
    )
  }
  key
}

# Fetches one ACS table's variables for every Montana county in one call.
# endpoint_template: ACS_DETAIL_ENDPOINT or ACS_SUBJECT_ENDPOINT.
fetch_acs_mt_counties <- function(endpoint_template, get_vars, year, api_key) {
  url <- sprintf(endpoint_template, year)
  resp <- request(url) %>%
    req_url_query(
      get = paste(get_vars, collapse = ","),
      `for` = "county:*",
      `in` = paste0("state:", MT_STATE_FIPS),
      key = api_key
    ) %>%
    perform_with_retry()
  parse_acs_json(resp_body_string(resp))
}

# Pure transformation: the Census API returns a JSON array-of-arrays (first
# row is column names) rather than an array of objects -- fromJSON() on
# that shape gives a character matrix, not a data frame with real column
# names, so this does that conversion and coerces every column except
# NAME/state/county to numeric. Kept separate from the network fetch so
# it's testable against a captured fixture.
parse_acs_json <- function(json_text) {
  raw <- jsonlite::fromJSON(json_text)
  if (is.null(raw) || nrow(raw) < 2) {
    return(data.frame())
  }
  header <- raw[1, ]
  body <- as.data.frame(raw[-1, , drop = FALSE], stringsAsFactors = FALSE)
  names(body) <- header

  non_numeric_cols <- c("NAME", "state", "county")
  for (col in setdiff(names(body), non_numeric_cols)) {
    body[[col]] <- suppressWarnings(as.numeric(body[[col]]))
  }
  body
}

# Census ACS uses negative sentinel codes (e.g. -666666666) for "not
# computed"/suppressed cells in some tables -- the same shape of problem
# clean_ipeds_value() handles for IPEDS.
clean_acs_value <- function(x) ifelse(is.na(x) | x < 0, NA_real_, x)

fetch_census_income_rent_population <- function(year = NULL, api_key = census_api_key()) {
  year <- year %||% latest_acs5_year()
  raw <- fetch_acs_mt_counties(ACS_DETAIL_ENDPOINT, c("NAME", "B19013_001E", "B25064_001E", "B01003_001E"), year, api_key)
  parse_census_income_rent_population(raw, year)
}

# Strips the ", Montana" suffix from the API's own NAME field so County
# matches this project's registry format ("Yellowstone County", not
# "Yellowstone County, Montana") -- see this file's header for why.
strip_state_suffix <- function(name) sub(", Montana$", "", name)

parse_census_income_rent_population <- function(raw, year) {
  if (nrow(raw) == 0) {
    return(data.frame(County = character(0), Median_Household_Income = numeric(0),
                       Median_Gross_Rent = numeric(0), Population = numeric(0),
                       ACS_Year = integer(0), stringsAsFactors = FALSE))
  }
  raw %>%
    transmute(
      County = strip_state_suffix(NAME),
      Median_Household_Income = clean_acs_value(B19013_001E),
      Median_Gross_Rent = clean_acs_value(B25064_001E),
      Population = clean_acs_value(B01003_001E),
      ACS_Year = year
    )
}

fetch_census_mining_employment_share <- function(year = NULL, api_key = census_api_key()) {
  year <- year %||% latest_acs5_year()
  raw <- fetch_acs_mt_counties(ACS_SUBJECT_ENDPOINT, c("NAME", "S2403_C01_001E", "S2403_C01_004E"), year, api_key)
  parse_census_mining_employment_share(raw)
}

parse_census_mining_employment_share <- function(raw) {
  if (nrow(raw) == 0) {
    return(data.frame(County = character(0), Mining_Employment_Share = numeric(0), stringsAsFactors = FALSE))
  }
  raw %>%
    transmute(
      County = strip_state_suffix(NAME),
      total = clean_acs_value(S2403_C01_001E),
      mining = clean_acs_value(S2403_C01_004E),
      Mining_Employment_Share = ifelse(!is.na(total) & total > 0, mining / total, NA_real_)
    ) %>%
    select(County, Mining_Employment_Share)
}

# Population change vs. n_years_back, both from ACS 5-Year vintages. Kept
# as a pure join+compute function, separate from the two live fetches, so
# it's testable without network access.
compute_population_change <- function(current, prior) {
  if (nrow(current) == 0 || nrow(prior) == 0) {
    return(data.frame(County = character(0), Population_Change_Pct = numeric(0), stringsAsFactors = FALSE))
  }
  current %>%
    select(County, Population) %>%
    inner_join(prior %>% select(County, Population_Prior = Population), by = "County") %>%
    mutate(Population_Change_Pct = ifelse(!is.na(Population) & !is.na(Population_Prior) & Population_Prior > 0,
                                           (Population - Population_Prior) / Population_Prior, NA_real_)) %>%
    select(County, Population_Change_Pct)
}

# ACS 5-Year estimates publish roughly a year behind the current calendar
# year -- walks backward the same way find_latest_ipeds_salary_year() and
# find_latest_ccd_directory_year() do, rather than hardcoding a year that
# will eventually go stale. Checks a cheap single-variable request rather
# than the full multi-variable one.
latest_acs5_year <- function(start_year = as.integer(format(Sys.Date(), "%Y")),
                              years_back = 3, api_key = census_api_key()) {
  for (year in seq(start_year, start_year - years_back)) {
    result <- tryCatch(
      fetch_acs_mt_counties(ACS_DETAIL_ENDPOINT, c("NAME", "B01003_001E"), year, api_key),
      error = function(e) data.frame()
    )
    if (nrow(result) > 0) return(year)
  }
  stop("latest_acs5_year(): no working ACS 5-Year vintage found in the last ", years_back, " years.")
}

# Full pipeline: income, rent, mining-employment share, and population
# change vs. 5 years earlier, one row per MT county. trend_years_back
# controls how far back the population-change comparison looks -- 5 years,
# refreshed at the same "once a year is plenty" cadence as the DLI/IPEDS
# salary data elsewhere in this pipeline.
fetch_census_county_context <- function(api_key = census_api_key(), trend_years_back = 5) {
  year <- latest_acs5_year(api_key = api_key)

  current <- fetch_census_income_rent_population(year, api_key)
  prior <- fetch_census_income_rent_population(year - trend_years_back, api_key)
  mining <- fetch_census_mining_employment_share(year, api_key)
  pop_change <- compute_population_change(current, prior)

  current %>%
    left_join(mining, by = "County") %>%
    left_join(pop_change, by = "County")
}
