# Montana Higher Ed faculty salary data from IPEDS (the federal Integrated
# Postsecondary Education Data System), via the Urban Institute's Education
# Data Portal -- same real public JSON REST API Wyoming's ipeds_salary_scraper.R
# uses, just fips=30 and Montana's own institutions.
# https://educationdata.urban.org/documentation/
#
# Endpoint used: college-university/ipeds/salaries-instructional-staff/{year}
# filtered to fips=30 (Montana). Per NCES, HR/SAL data is reported "as of
# November 1" of the same calendar year as the survey year.
#
# MT_IPEDS_UNITID_MAP covers exactly the institutions this project already
# job-scrapes (he_institution_registry.csv), matching Wyoming's own
# salarymap.csv scope (its 9 rows are exactly its 9 job-scraped
# institutions, not a broader MUS-wide reference set). Montana's own
# structural quirks (RESEARCH_NOTES.md's Higher Ed section) don't need any
# special-casing here the way Wyoming's Sheridan/Gillette shared-unitid case
# does: Highlands College of Montana Tech has its own separate unitid
# (180081) and reports its own faculty salary independently of Montana
# Tech's (180416), so no merged-entity Salary_Note is needed for any
# institution in this map.
#
# Each institution reports one row per (academic_rank x contract_length x
# sex) combination; academic_rank/contract_length/sex == 99 means "all
# ranks/lengths/sexes combined". Negative values (-1, -2, -3) are IPEDS/
# Urban sentinel codes for not-available/not-applicable/suppressed, not
# real data, and are treated as NA.
#
# Extended 2026-08-07 from the original 6 (confirmed live 2026-08-06) to
# cover the 7 HE institutions added to the registry since: Blackfeet CC,
# Carroll College, Dawson CC, Miles CC, Rocky Mountain College, University
# of Montana, and University of Providence -- each unitid confirmed live
# against the Urban Institute's college directory AND its own real 2024
# salaries-instructional-staff response (not just matched by name in the
# directory). Three of these (Blackfeet CC, Dawson CC, Miles CC -- all
# small 2-year colleges) genuinely have NO academic_rank=1 ("Professor")
# rank-tier record at all in the 2024 data -- confirmed live, a real
# absence (these institutions don't use a tenure-track Professor rank
# system), not a query bug -- so Faculty_Avg_Salary_Professor is
# real NA for all three via the existing left_join below, no special-
# casing needed. University of Montana's real unitid (180489) is
# "The University of Montana" in the directory, distinct from University
# of Montana Western (180692) and Helena College (180276) -- neither of
# which gets its own row here, matching he_institution_registry.csv's own
# choice not to give either its own registry row (both ride UM's NEOGOV
# jobs board, confirmed live in direct_api_scrapers.R's own comments).

suppressMessages({
  library(httr2)
  library(dplyr)
})

IPEDS_SALARY_ENDPOINT <- "https://educationdata.urban.org/api/v1/college-university/ipeds/salaries-instructional-staff"

MT_IPEDS_UNITID_MAP <- tibble::tribble(
  ~unitid, ~Name,
  180461L, "Montana State University",
  180179L, "Montana State University Billings",
  180522L, "Montana State University-Northern",
  180249L, "Great Falls College MSU",
  180416L, "Montana Tech",
  180197L, "Flathead Valley Community College",
  180373L, "Miles Community College",
  180151L, "Dawson Community College",
  180054L, "Blackfeet Community College",
  180489L, "University of Montana",
  180106L, "Carroll College",
  180595L, "Rocky Mountain College",
  180258L, "University of Providence",
  # Added 2026-08-07, confirmed live against the Urban Institute's own
  # college directory endpoint (college-university/ipeds/directory/2023)
  # for the 4 tribal colleges added to the registry since -- Stone Child's
  # unitid (366340) doesn't follow the 1804xx/1802xx pattern the rest of
  # this map does, which is why it wasn't guessed at.
  180212L, "Fort Peck Community College",
  180328L, "Little Big Horn College",
  180647L, "Salish Kootenai College",
  366340L, "Stone Child College",
  # Added 2026-08-07 alongside their new heuristic scrapers
  # (misc_college_scrapers.R) -- confirmed live against the Urban
  # Institute's college directory and real 2024 salary response.
  180203L, "Aaniiih Nakoda College",
  180160L, "Chief Dull Knife College",
  # Highlands College (180081) -- added 2026-08-07 once its postings were
  # split out from Montana Tech's on direct_api_scrapers.R's JazzHR side.
  # Real, permanent gap unlike every entry above: confirmed live across
  # 2020-2024, IPEDS's salaries-instructional-staff and FSA's grants
  # endpoints have ZERO rows for this unitid in any year checked -- not
  # missing a rank tier like Blackfeet/Dawson/Miles/the tribal colleges
  # above, genuinely no HR-survey or Pell data reported under its own
  # unitid at all (almost certainly consolidated into Montana Tech's own
  # HR/financial-aid reporting, since they share physical
  # administration). Faculty_Avg_Salary/Pell_Recipient_Share are real NA
  # for Highlands College every run. Fall-enrollment IS reported
  # separately (3 real rows confirmed live for 2023), so Enrollment/
  # Enrollment_Change_Pct/Students_Per_Teacher work normally.
  180081L, "Highlands College"
)

# Follows the API's `next` pagination link until exhausted, returning every
# result row as one data frame.
fetch_ipeds_paginated <- function(url) {
  rows <- list()
  while (!is.null(url)) {
    resp <- request(url) %>% req_perform() %>% resp_body_json()
    rows <- c(rows, resp$results)
    url <- resp[["next"]]
  }
  if (length(rows) == 0) return(data.frame())
  bind_rows(lapply(rows, function(r) as.data.frame(r, stringsAsFactors = FALSE)))
}

fetch_ipeds_mt_salaries_for_year <- function(year) {
  url <- paste0(IPEDS_SALARY_ENDPOINT, "/", year, "/?fips=30")
  fetch_ipeds_paginated(url)
}

# IPEDS publishes this survey with roughly a 1-2 year lag -- walk backward
# from the current year until a non-empty response is found rather than
# hardcoding a year that will eventually go stale.
find_latest_ipeds_salary_year <- function(start_year = as.integer(format(Sys.Date(), "%Y")),
                                           years_back = 5) {
  for (year in seq(start_year, start_year - years_back)) {
    df <- fetch_ipeds_mt_salaries_for_year(year)
    if (nrow(df) > 0) return(list(year = year, data = df))
  }
  list(year = NA_integer_, data = data.frame())
}

clean_ipeds_value <- function(x) ifelse(is.na(x) | x < 0, NA_real_, x)

# Pure transformation, kept separate from the network fetch above so it can
# be tested against a captured fixture instead of hitting the live API.
parse_ipeds_he_salaries <- function(df, year) {
  if (nrow(df) == 0) {
    return(data.frame(
      Name = character(0), Faculty_Avg_Salary = numeric(0),
      Faculty_Avg_Salary_Professor = numeric(0), Faculty_Count = numeric(0),
      Salary_Year = character(0), stringsAsFactors = FALSE
    ))
  }

  overall <- df %>%
    filter(academic_rank == 99, contract_length == 99, sex == 99) %>%
    transmute(unitid,
              Faculty_Avg_Salary = clean_ipeds_value(average_salary),
              Faculty_Count = clean_ipeds_value(instruc_staff_count))

  professor <- df %>%
    filter(academic_rank == 1, contract_length == 99, sex == 99) %>%
    transmute(unitid, Faculty_Avg_Salary_Professor = clean_ipeds_value(average_salary))

  MT_IPEDS_UNITID_MAP %>%
    left_join(overall, by = "unitid") %>%
    left_join(professor, by = "unitid") %>%
    mutate(Salary_Year = as.character(year)) %>%
    select(Name, Faculty_Avg_Salary, Faculty_Avg_Salary_Professor, Faculty_Count, Salary_Year)
}

fetch_ipeds_he_salaries <- function() {
  latest <- find_latest_ipeds_salary_year()
  parse_ipeds_he_salaries(latest$data, latest$year)
}

# Pure transformation for one year of trend data -- kept separate from the
# network fetch below so it's testable against a captured fixture. Only the
# headline "all ranks combined" figure is extracted.
parse_ipeds_salary_trend_year <- function(df, year) {
  if (nrow(df) == 0) {
    return(data.frame(Name = character(0), Year = integer(0), Faculty_Avg_Salary = numeric(0)))
  }
  overall <- df %>%
    filter(academic_rank == 99, contract_length == 99, sex == 99) %>%
    transmute(unitid, Faculty_Avg_Salary = clean_ipeds_value(average_salary))
  MT_IPEDS_UNITID_MAP %>%
    left_join(overall, by = "unitid") %>%
    transmute(Name, Year = year, Faculty_Avg_Salary)
}

# Faculty_Avg_Salary going back n_years, for a multi-year salary trend
# alongside fetch_ipeds_he_salaries()'s single latest-year figure. IPEDS is
# queryable by year going back indefinitely (unlike the DLI Teacher
# Compensation Report, which only ever has the latest edition -- see
# salary_scrapers.R), so this is just re-running
# parse_ipeds_salary_trend_year() for each of the last few years. Returns
# long format (one row per Name x Year); callers pivot wide if they need it.
fetch_ipeds_he_salary_trend <- function(n_years = 3) {
  latest <- find_latest_ipeds_salary_year()
  if (is.na(latest$year)) {
    return(data.frame(Name = character(0), Year = integer(0), Faculty_Avg_Salary = numeric(0)))
  }

  years <- seq(latest$year, latest$year - n_years + 1)
  rows <- lapply(years, function(y) {
    df <- if (y == latest$year) latest$data else fetch_ipeds_mt_salaries_for_year(y)
    parse_ipeds_salary_trend_year(df, y)
  })
  bind_rows(rows)
}
