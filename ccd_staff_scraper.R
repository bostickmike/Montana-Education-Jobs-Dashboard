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
#
# Extended 2026-08-07 from the original 18 districts to cover the 12
# districts added to the registry since -- every one of these 12 real LEA
# names is IDENTICAL to opi_finance_scraper.R's MT_OPI_FINANCE_LEA_MAP
# entries for the same district (both independently confirmed live
# against their own real 2024 API response, not copied from one to the
# other) -- strong evidence CCD's own district names are themselves
# sourced from OPI, not two coincidentally-matching naming schemes.
# Livingston's real HS district is "Park H S" (named after Park County,
# not the town) here too, same as it was in the OPI finance data.
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
  "Hardin Public Schools" = c("Hardin Elem", "Hardin H S"),
  "Glendive Public Schools" = c("Glendive Elem", "Dawson H S"),
  "Colstrip Public Schools" = c("Colstrip Elem", "Colstrip H S"),
  "Sidney Public Schools" = c("Sidney Elem", "Sidney H S"),
  "Stevensville Public Schools" = c("Stevensville Elem", "Stevensville H S"),
  "Big Sandy Public Schools" = c("Big Sandy K-12"),
  "Lame Deer Public Schools" = c("Lame Deer Elem", "Lame Deer H S"),
  "Poplar Public Schools" = c("Poplar Elem", "Poplar H S"),
  "Fairview Public Schools" = c("Fairview Elem", "Fairview H S"),
  "Rocky Boy Public Schools" = c("Rocky Boy Elem", "Rocky Boy H S"),
  "Ronan Public Schools" = c("Ronan Elem", "Ronan H S"),
  "Livingston Public Schools" = c("Livingston Elem", "Park H S"),
  "Lodge Grass Public Schools" = c("Lodge Grass Elem", "Lodge Grass H S"),
  "Wolf Point Public Schools" = c("Wolf Point Elem", "Wolf Point H S"),
  "Plentywood Public Schools" = c("Plentywood K-12 Schools"),
  # Elementary-only district (its high schoolers attend Whitefish H S, a separate board).
  "Olney-Bissell School District" = c("Olney-Bissell Elem")
)

suppressMessages({
  library(httr2)
  library(dplyr)
})

CCD_DISTRICT_DIRECTORY_ENDPOINT <- "https://educationdata.urban.org/api/v1/school-districts/ccd/directory"

fetch_ccd_paginated <- function(url) {
  fetch_json_paginated(url)
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
# `lea_map`: registry district -> CCD lea_names (the hand map). `leaid_map`
# (optional): registry district -> NCES LEAIDs for every other district; the
# pipeline passes crosswalk_leaids(district_crosswalk, exclude = names(MT_CCD_LEA_MAP))
# (opi_reconcile.R). By LEAID, not name: CCD names two districts "Cottonwood
# Elem" (Gallatin and Hill), and a name match summed both (2026-11-09 rehearsal).
parse_ccd_teacher_fte <- function(df, lea_map = MT_CCD_LEA_MAP, leaid_map = NULL) {
  if (nrow(df) == 0) {
    return(data.frame(District = character(0), Teachers_Total_FTE = numeric(0),
                       Enrollment = numeric(0), stringsAsFactors = FALSE))
  }

  by_lea <- df %>%
    filter(agency_type == 1, !is.na(number_of_schools), number_of_schools >= 1) %>%
    transmute(
      leaid = if ("leaid" %in% names(df)) as.character(leaid) else NA_character_,
      lea_name = trimws(lea_name),
      Teachers_Total_FTE = ifelse(is.na(teachers_total_fte) | teachers_total_fte < 0, NA_real_, teachers_total_fte),
      Enrollment = ifelse(is.na(enrollment) | enrollment < 0, NA_real_, enrollment)
    )

  rows <- lapply(names(lea_map), function(district) {
    lea_names <- lea_map[[district]]
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

  extra <- leaid_map[setdiff(names(leaid_map), names(lea_map))]
  rows <- c(rows, lapply(names(extra), function(district) {
    matched <- by_lea %>% filter(leaid %in% as.character(extra[[district]]))
    if (nrow(matched) == 0) {
      return(data.frame(District = district, Teachers_Total_FTE = NA_real_,
                         Enrollment = NA_real_, stringsAsFactors = FALSE))
    }
    data.frame(District = district,
               Teachers_Total_FTE = sum(matched$Teachers_Total_FTE, na.rm = TRUE),
               Enrollment = sum(matched$Enrollment, na.rm = TRUE), stringsAsFactors = FALSE)
  }))

  dplyr::bind_rows(rows)
}

fetch_ccd_teacher_fte <- function(lea_map = MT_CCD_LEA_MAP, leaid_map = NULL) {
  latest <- find_latest_ccd_directory_year()
  result <- parse_ccd_teacher_fte(latest$data, lea_map, leaid_map)
  if (nrow(result) > 0) result$CCD_Year <- as.character(latest$year)
  result
}

# ---------------------------------------------------------------------------
# Free/reduced-price lunch share (2026-11-09)
# ---------------------------------------------------------------------------
# Share of students eligible for free or reduced-price lunch, from CCD's
# school-level directory (free_or_reduced_price_lunch, enrollment), summed to
# the district. Shown beside SAIPE's child poverty rate: a school-based count
# rather than a Census model estimate. Two caveats, both stated on the
# dashboard: a school using community eligibility (free meals for all) may
# count every student, and a district only gets a share when its reporting
# schools hold at least FRL_MIN_REPORTED_SHARE of its enrollment (no figure
# from a few small schools). CCD marks a missing count as -1.
CCD_SCHOOL_DIRECTORY_ENDPOINT <- "https://educationdata.urban.org/api/v1/schools/ccd/directory"
FRL_MIN_REPORTED_SHARE <- 0.8

fetch_ccd_school_directory <- function(fips, year) {
  fetch_json_paginated(paste0(CCD_SCHOOL_DIRECTORY_ENDPOINT, "/", year, "/?fips=", fips))
}

# `id_map`: one entry per map entity (district or school) -> NCES ids. A
# 7-digit id is a district (all its schools); a 12-digit id is one school
# (a charter inside a host district).
parse_ccd_frl_share <- function(schools, id_map) {
  empty <- data.frame(District = character(0), Free_Reduced_Lunch_Share = numeric(0),
                       FRL_Schools_Reporting = integer(0), stringsAsFactors = FALSE)
  if (nrow(schools) == 0 || length(id_map) == 0) return(empty)
  s <- data.frame(ncessch = as.character(schools$ncessch), leaid = as.character(schools$leaid),
                  frl = suppressWarnings(as.numeric(schools$free_or_reduced_price_lunch)),
                  enrollment = suppressWarnings(as.numeric(schools$enrollment)), stringsAsFactors = FALSE)
  s <- s[!is.na(s$enrollment) & s$enrollment > 0, , drop = FALSE]
  rows <- lapply(names(id_map), function(entity) {
    ids <- as.character(id_map[[entity]])
    mine <- s[s$leaid %in% ids[nchar(ids) == 7] | s$ncessch %in% ids[nchar(ids) == 12], , drop = FALSE]
    rep <- mine[!is.na(mine$frl) & mine$frl >= 0, , drop = FALSE]
    share <- if (nrow(rep) == 0 || sum(rep$enrollment) < FRL_MIN_REPORTED_SHARE * sum(mine$enrollment)) {
      NA_real_
    } else {
      min(1, sum(rep$frl) / sum(rep$enrollment))
    }
    data.frame(District = entity, Free_Reduced_Lunch_Share = share,
               FRL_Schools_Reporting = nrow(rep), stringsAsFactors = FALSE)
  })
  dplyr::bind_rows(rows)
}

# Each entity takes the newest year in which it has a share (FRL_Year says
# which): some districts skip a year (WY 2024: 8 of 48 reported no counts).
# When no year's directory answers at all (CCD down), it stops instead of
# returning blank rows, so safe_scrape() logs an error and the pipeline keeps
# last run's values (review, 2026-11-09: an outage had logged "ok" and blanked
# every district's share).
fetch_ccd_frl_share <- function(fips, id_map, start_year = as.integer(format(Sys.Date(), "%Y")), years_back = 4) {
  out <- NULL
  answered <- 0L
  errors <- character(0)
  for (year in seq(start_year, start_year - years_back)) {
    todo <- setdiff(names(id_map), out$District)
    if (length(todo) == 0) break
    schools <- tryCatch(fetch_ccd_school_directory(fips, year),
                        error = function(e) { errors <<- c(errors, conditionMessage(e)); data.frame() })
    if (nrow(schools) == 0 || !"free_or_reduced_price_lunch" %in% names(schools)) next
    answered <- answered + 1L
    r <- parse_ccd_frl_share(schools, id_map[todo])
    r <- r[!is.na(r$Free_Reduced_Lunch_Share), , drop = FALSE]
    if (nrow(r) > 0) out <- dplyr::bind_rows(out, transform(r, FRL_Year = as.character(year)))
  }
  if (answered == 0L) {
    stop("fetch_ccd_frl_share(): no CCD school-directory year answered",
         if (length(errors)) paste0(" (", errors[1], ")") else "")
  }
  missing <- setdiff(names(id_map), out$District)
  dplyr::bind_rows(out, data.frame(District = missing, Free_Reduced_Lunch_Share = rep(NA_real_, length(missing)),
                                   FRL_Schools_Reporting = rep(0L, length(missing)),
                                   FRL_Year = rep(NA_character_, length(missing)), stringsAsFactors = FALSE))
}

# Staffing for an entity that isn't its own district in CCD's district
# directory (a charter inside a host district): teachers and students summed
# over its schools in the school directory. Same `id_map` as parse_ccd_frl_share().
parse_ccd_school_staffing <- function(schools, id_map) {
  if (nrow(schools) == 0 || length(id_map) == 0) {
    return(data.frame(District = character(0), Teachers_Total_FTE = numeric(0), Enrollment = numeric(0)))
  }
  fte <- suppressWarnings(as.numeric(schools$teachers_fte)); enr <- suppressWarnings(as.numeric(schools$enrollment))
  fte[!is.na(fte) & fte < 0] <- NA; enr[!is.na(enr) & enr < 0] <- NA
  dplyr::bind_rows(lapply(names(id_map), function(entity) {
    ids <- as.character(id_map[[entity]])
    i <- as.character(schools$leaid) %in% ids[nchar(ids) == 7] | as.character(schools$ncessch) %in% ids[nchar(ids) == 12]
    data.frame(District = entity,
               Teachers_Total_FTE = if (any(i) && any(!is.na(fte[i]))) sum(fte[i], na.rm = TRUE) else NA_real_,
               # 0 students means none enrolled here (a BOCES, a state school whose
               # students are counted elsewhere), not a ratio of 0: NA.
               Enrollment = if (any(i) && sum(enr[i], na.rm = TRUE) > 0) sum(enr[i], na.rm = TRUE) else NA_real_,
               stringsAsFactors = FALSE)
  }))
}

# The geographic school districts (NCES LEAIDs) a point lies in, from the
# Census Bureau's public geocoder (no key): one unified district, or an
# elementary and a secondary district where a town is split (Butte Elem +
# Butte H S). For a school with no poverty estimate of its own (a charter, a
# private or tribal school), the surrounding district's SAIPE rate stands in
# (a split's two rates averaged, as for registry districts), labeled as such.
# NA when the geocoder finds none.
geocode_school_district <- function(lat, lon) {
  if (is.na(lat) || is.na(lon)) return(NA_character_)
  resp <- httr2::request("https://geocoding.geo.census.gov/geocoder/geographies/coordinates") %>%
    httr2::req_url_query(x = lon, y = lat, benchmark = "Public_AR_Current", vintage = "Current_Current",
                         layers = "Unified School Districts,Elementary School Districts,Secondary School Districts",
                         format = "json") %>%
    perform_with_retry()
  geo <- jsonlite::fromJSON(httr2::resp_body_string(resp))$result$geographies
  ids <- unlist(lapply(c("Unified School Districts", "Elementary School Districts", "Secondary School Districts"),
                       function(layer) { g <- geo[[layer]]; if (is.data.frame(g) && nrow(g) > 0 && !is.null(g$GEOID)) as.character(g$GEOID) }))
  if (length(ids) == 0) NA_character_ else unique(ids)
}

# A school's surrounding-district child poverty rate (charter, private, tribal
# or early-childhood school with no SAIPE geography of its own): the SAIPE
# rates of the districts geocode() finds at its point, averaged where a town is
# split into elementary and secondary districts. `saipe`: LEAID,
# Child_Poverty_Rate (and SAIPE_Year). `district_names`: LEAID -> display name.
# Returns status "ok", "none" (no district found / no rate) or "failed" (the
# geocoder errored: the caller keeps last run's value and logs it).
surrounding_district_poverty <- function(lat, lon, saipe, district_names = NULL, geocode = geocode_school_district) {
  res <- list(status = "none", rate = NA_real_, year = NA, basis = NA_character_)
  host <- tryCatch(geocode(lat, lon), error = function(e) structure(NA_character_, failed = TRUE))
  if (isTRUE(attr(host, "failed"))) { res$status <- "failed"; return(res) }
  h <- match(host, as.character(saipe$LEAID))
  h <- h[!is.na(h) & !is.na(saipe$Child_Poverty_Rate[h])]
  if (length(h) == 0) return(res)
  ids <- as.character(saipe$LEAID[h])
  nm <- if (!is.null(district_names)) unique(ifelse(is.na(district_names[ids]), ids, district_names[ids])) else ids
  res$status <- "ok"
  res$rate <- mean(saipe$Child_Poverty_Rate[h])
  if ("SAIPE_Year" %in% names(saipe)) res$year <- saipe$SAIPE_Year[h[1]]
  res$basis <- paste("Surrounding district:", paste(nm, collapse = " / "))
  res
}
