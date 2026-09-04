# Montana HE institution Pell Grant recipient share, from the US Department
# of Education's Federal Student Aid (FSA) office, via the Urban
# Institute's Education Data Portal -- ported from Wyoming's
# fsa_pell_scraper.R, same endpoint/fields/quirks, just fips=30 and
# MT_IPEDS_UNITID_MAP. See Wyoming's own header comment for the full "why"
# on matching Pell/enrollment years and this being an honest recipients-
# over-FTE-enrollment ratio, not two directly comparable headcounts --
# unchanged here.
#
# Depends on ipeds_salary_scraper.R (MT_IPEDS_UNITID_MAP) and
# ipeds_enrollment_scraper.R (parse_ipeds_he_enrollment()) both being
# sourced first.

suppressMessages({
  library(httr2)
  library(dplyr)
})

FSA_GRANTS_ENDPOINT <- "https://educationdata.urban.org/api/v1/college-university/fsa/grants"
FSA_PELL_GRANT_TYPE <- 4L

# FSA grants records mix real JSON nulls (a grant_type row an institution
# has no recipients for) with populated fields, which breaks
# fetch_ipeds_paginated()'s per-record as.data.frame() the same way it
# breaks on CCD's directory endpoint (see ccd_staff_scraper.R). This
# variant hands the conversion off to jsonlite via simplifyVector = TRUE,
# which turns nulls into NA correctly.
fetch_ipeds_directory_paginated <- function(url) {
  pages <- list()
  while (!is.null(url)) {
    resp <- request(url) %>% perform_with_retry() %>% resp_body_json(simplifyVector = TRUE)
    pages[[length(pages) + 1]] <- resp$results
    url <- resp[["next"]]
  }
  if (length(pages) == 0) return(data.frame())
  dplyr::bind_rows(pages)
}

clean_fsa_value <- function(x) ifelse(is.na(x) | x < 0, NA_real_, x)

fetch_fsa_mt_grants_for_year <- function(year) {
  url <- paste0(FSA_GRANTS_ENDPOINT, "/", year, "/?fips=30")
  fetch_ipeds_directory_paginated(url)
}

# FSA publishes this survey with a longer lag than IPEDS's own surveys --
# walks backward the same way find_latest_ipeds_salary_year()/
# find_latest_ipeds_enrollment_year() do.
find_latest_fsa_grants_year <- function(start_year = as.integer(format(Sys.Date(), "%Y")),
                                        years_back = 6) {
  for (year in seq(start_year, start_year - years_back)) {
    df <- fetch_fsa_mt_grants_for_year(year)
    if (nrow(df) > 0) return(list(year = year, data = df))
  }
  list(year = NA_integer_, data = data.frame())
}

# Pure transformation, kept separate from the network fetches so it's
# testable against captured fixtures. enrollment_df is the output of
# parse_ipeds_he_enrollment() for the SAME year as grants_df.
parse_ipeds_he_pell_share <- function(grants_df, enrollment_df, year) {
  if (nrow(grants_df) == 0 || nrow(enrollment_df) == 0) {
    return(data.frame(Name = character(0), Pell_Recipient_Share = numeric(0), Pell_Year = character(0), stringsAsFactors = FALSE))
  }

  pell <- grants_df %>%
    filter(grant_type == FSA_PELL_GRANT_TYPE) %>%
    transmute(unitid, Pell_Recipients = clean_fsa_value(grant_recipients_unitid))

  MT_IPEDS_UNITID_MAP %>%
    left_join(pell, by = "unitid") %>%
    left_join(enrollment_df %>% select(Name, Enrollment), by = "Name") %>%
    mutate(
      Pell_Recipient_Share = ifelse(!is.na(Pell_Recipients) & !is.na(Enrollment) & Enrollment > 0,
                                     Pell_Recipients / Enrollment, NA_real_),
      Pell_Year = as.character(year)
    ) %>%
    select(Name, Pell_Recipient_Share, Pell_Year)
}

fetch_ipeds_he_pell_share <- function() {
  latest_grants <- find_latest_fsa_grants_year()
  if (is.na(latest_grants$year)) {
    return(data.frame(Name = character(0), Pell_Recipient_Share = numeric(0), Pell_Year = character(0), stringsAsFactors = FALSE))
  }
  enrollment_df <- parse_ipeds_he_enrollment(
    fetch_ipeds_mt_enrollment_for_year(latest_grants$year), latest_grants$year
  )
  parse_ipeds_he_pell_share(latest_grants$data, enrollment_df, latest_grants$year)
}
