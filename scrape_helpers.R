# Shared scraping-resilience helpers for the weekly pipeline.
#
# Every per-institution/per-district scraper chunk should call its scrape
# function through safe_scrape() rather than bare: if a site's HTML changed,
# a page timed out, or a selector stopped matching, an uncaught error would
# otherwise halt the entire weekly run -- including the final munge chunks
# that write the CSVs the live app reads -- so a problem with one source
# would silently prevent that week's data update for every other source too.
# There's also no persisted record of what each run actually scraped without
# this, so a source quietly returning 0 rows (a broken selector, not a
# genuine empty week) looks identical to a real empty week with nothing to
# distinguish them after the fact.
#
# safe_scrape() wraps a scrape function so a failure degrades to "this one
# source is missing from this week's data" instead of "nothing updated this
# week," and logs every run's outcome (ok/empty/error, row count, message)
# to scrape_log.csv so failures and selector drift are visible without
# having to notice a downstream count looks off.

# Every fetch_*() function across this project's scraper files ends its
# httr2 pipe with this instead of a bare req_perform() -- a single 429/503
# against a shared multi-tenant host (AppliTrack, SchoolSpring, ...) or a
# transient blip against any other live source would otherwise drop that
# whole source for the week (confirmed real: Rocky Mountain College lost
# entirely to a bare 429 on the 2026-09-01 run). httr2's req_retry() retries
# 429/503 and honors a Retry-After header by default; a persistent failure
# (a genuinely broken or migrated tenant, a 404, a real 500) still surfaces
# as an error after the retries, exactly as before -- safe_scrape() logs it
# same as always. Takes and returns the same shapes as req_perform(), so it
# drops into any existing `request(...) %>% ... %>% req_perform()` pipe as a
# straight substitution for the last step.
#
# is_transient overrides which responses count as retryable (NULL keeps
# httr2's 429/503 default) -- see is_transient_gateway_error() below.
perform_with_retry <- function(req, max_tries = 3, is_transient = NULL) {
  req %>%
    httr2::req_retry(max_tries = max_tries, backoff = function(i) 2^i,
                     is_transient = is_transient) %>%
    httr2::req_perform()
}

# httr2's default retries only 429/503, so a 502/504 or a Cloudflare
# 520-524 (origin unreachable/timed out) fails on the very first try. For a
# small district site behind Cloudflare those are intermittent, not "the
# page is gone": Roberts Public School lost two straight weeks to a single
# 520 (2026-09-22) and 502 (2026-09-29) while the page itself was up with
# the same 3 postings.
is_transient_gateway_error <- function(resp) {
  httr2::resp_status(resp) %in% c(429, 502, 503, 504, 520:524)
}

# Follows a JSON API's pagination link (defaulting to resp[["next"]]) until
# exhausted, collecting records into a single consolidated data frame. Uses
# httr2::resp_body_json(simplifyVector = TRUE) so that JSON null values across
# mixed or optional fields (e.g. Urban Institute IPEDS/CCD directory/salary
# endpoints) are converted into NA consistently without failing per-record
# as.data.frame() calls.
fetch_json_paginated <- function(url,
                                 results_field = "results",
                                 next_field = "next",
                                 max_pages = NULL,
                                 req_modifier = identity) {
  pages <- list()
  page_count <- 0L

  while (!is.null(url) && nzchar(url)) {
    if (!is.null(max_pages) && page_count >= max_pages) break

    req <- req_modifier(httr2::request(url))
    resp <- req %>% perform_with_retry() %>% httr2::resp_body_json(simplifyVector = TRUE)
    res <- resp[[results_field]]

    if (is.data.frame(res) && nrow(res) > 0) {
      pages[[length(pages) + 1]] <- res
    } else if (is.list(res) && length(res) > 0) {
      pages[[length(pages) + 1]] <- as.data.frame(res)
    }

    page_count <- page_count + 1L
    url <- resp[[next_field]]
  }

  if (length(pages) == 0) return(data.frame())
  dplyr::bind_rows(pages)
}

# Build a zero-row data frame with the given column names, so a failed or
# empty scrape can still be bind_rows()'d/rbind()'d with everything else
# without special-casing a NULL result at every call site.
empty_df <- function(cols) {
  as.data.frame(
    stats::setNames(rep(list(character(0)), length(cols)), cols),
    stringsAsFactors = FALSE
  )
}

# Append one row to the scrape run log, creating it with a header if it
# doesn't exist yet.
log_scrape_result <- function(source_name, status, n_rows,
                               error_message = NA_character_,
                               log_path = "scrape_log.csv") {
  entry <- data.frame(
    timestamp = as.character(Sys.time()),
    source = source_name,
    status = status,
    n_rows = n_rows,
    error_message = error_message,
    stringsAsFactors = FALSE
  )
  utils::write.table(
    entry,
    file = log_path,
    sep = ",",
    row.names = FALSE,
    col.names = !file.exists(log_path),
    append = file.exists(log_path)
  )
  invisible(entry)
}

# Run scrape_fn() under tryCatch, log the outcome, and always return a data
# frame with `expected_cols` -- the real scraped result on success, or an
# empty frame with the same shape on failure/empty result, so a caller can
# unconditionally rbind()/bind_rows() every source's result without checking
# for NULL or a missing/misnamed column first.
safe_scrape <- function(source_name, scrape_fn, expected_cols, log_path = "scrape_log.csv") {
  outcome <- tryCatch(
    list(df = scrape_fn(), error = NULL),
    error = function(e) list(df = NULL, error = conditionMessage(e))
  )

  if (!is.null(outcome$error)) {
    log_scrape_result(source_name, status = "error", n_rows = 0L,
                       error_message = outcome$error, log_path = log_path)
    message("safe_scrape: ", source_name, " failed: ", outcome$error)
    return(empty_df(expected_cols))
  }

  df <- outcome$df
  if (is.null(df) || nrow(df) == 0) {
    log_scrape_result(source_name, status = "empty", n_rows = 0L, log_path = log_path)
    return(empty_df(expected_cols))
  }

  log_scrape_result(source_name, status = "ok", n_rows = nrow(df), log_path = log_path)
  if ("Posted_Date" %in% names(df)) df$Posted_Date <- as.character(df$Posted_Date)
  if ("date_posted" %in% names(df)) df$date_posted <- as.character(df$date_posted)
  df
}

# Generate a discrepancy report comparing statewide OPI postings against
# directly scraped district job boards. Flags unmatched postings for covered
# districts (stale postings as potential ghosts, recent postings as ATS drift
# or unlisted direct vacancies) while ignoring independent employers and
# uncovered districts.
generate_opi_discrepancy_report <- function(opi_df, direct_df, registry) {
  empty <- data.frame(
    District = character(0),
    Source = character(0),
    Title = character(0),
    Date_Posted = character(0),
    Location = character(0),
    URL = character(0),
    Discrepancy_Type = character(0),
    Detected_Date = character(0),
    stringsAsFactors = FALSE
  )
  if (nrow(opi_df) == 0) return(empty)

  required_opi <- c("title", "date_posted", "location")
  required_direct <- c("title", "date_posted", "District")
  required_registry <- c("District", "City")

  missing_opi <- setdiff(required_opi, names(opi_df))
  missing_direct <- setdiff(required_direct, names(direct_df))
  missing_registry <- setdiff(required_registry, names(registry))
  if (length(missing_opi) > 0 || length(missing_direct) > 0 || length(missing_registry) > 0) {
    stop(
      "Cannot generate discrepancy report; missing columns: ",
      paste(c(missing_opi, missing_direct, missing_registry), collapse = ", "),
      call. = FALSE
    )
  }

  normalize <- function(x) {
    normalized <- tolower(trimws(as.character(x)))
    normalized[is.na(x)] <- NA_character_
    gsub("[^[:alnum:]]+", " ", normalized)
  }
  complete_key <- function(title, date) {
    normalized_title <- normalize(title)
    normalized_date <- trimws(as.character(date))
    valid <- !is.na(normalized_title) & nzchar(normalized_title) &
      !is.na(date) & nzchar(normalized_date)
    key <- rep(NA_character_, length(title))
    key[valid] <- paste(normalized_title[valid], normalized_date[valid], sep = "\r")
    key
  }

  direct_keys <- complete_key(direct_df$title, direct_df$date_posted)
  direct_keys <- paste(direct_df$District, direct_keys, sep = "\r")
  direct_keys <- direct_keys[!is.na(direct_keys)]

  city_forms <- normalize(registry$City)
  opi_keys <- complete_key(opi_df$title, opi_df$date_posted)
  opi_locations <- paste0(" ", normalize(opi_df$location), " ")
  direct_districts <- unique(direct_df$District)

  parse_discrepancy_date <- function(dp) {
    if (inherits(dp, "Date")) return(dp)
    if (is.na(dp) || !nzchar(trimws(as.character(dp)))) return(as.Date(NA))
    d <- tryCatch(as.Date(as.character(dp)), error = function(e) NA)
    if (!is.na(d)) return(d)
    tryCatch(as.Date(as.character(dp), format = "%m/%d/%Y"), error = function(e) NA)
  }

  discrepancy_rows <- list()
  for (i in seq_len(nrow(opi_df))) {
    loc <- opi_locations[i]
    if (is.na(loc) || !nzchar(trimws(loc))) next

    city_matches <- which(vapply(
      city_forms,
      function(city) !is.na(city) && nzchar(city) && grepl(paste0(" ", city, " "), loc, fixed = TRUE),
      logical(1)
    ))
    if (length(city_matches) == 0) next

    # "East Helena" also contains "Helena"; only use the most-specific city.
    city_matches <- city_matches[nchar(city_forms[city_matches]) == max(nchar(city_forms[city_matches]))]
    matched_districts <- registry$District[city_matches]

    active_districts <- intersect(matched_districts, direct_districts)
    if (length(active_districts) == 0) next

    candidate_keys <- paste(active_districts, opi_keys[i], sep = "\r")
    if (length(direct_keys) > 0 && any(candidate_keys %in% direct_keys)) {
      next
    }

    dp <- opi_df$date_posted[i]
    parsed_date <- parse_discrepancy_date(dp)
    discrepancy_type <- if (is.na(parsed_date)) {
      "Unmatched on direct scraper (no date)"
    } else if (parsed_date < (Sys.Date() - 60)) {
      paste0("Potential ghost posting on OPI (stale date: ", dp, ")")
    } else {
      "Unmatched on direct scraper (investigate ATS drift or unlisted posting)"
    }

    u <- if ("url" %in% names(opi_df)) opi_df$url[i] else NA_character_

    discrepancy_rows[[length(discrepancy_rows) + 1]] <- data.frame(
      District = paste(active_districts, collapse = "; "),
      Source = "OPI",
      Title = as.character(opi_df$title[i]),
      Date_Posted = as.character(dp),
      Location = as.character(opi_df$location[i]),
      URL = as.character(u),
      Discrepancy_Type = discrepancy_type,
      Detected_Date = as.character(Sys.Date()),
      stringsAsFactors = FALSE
    )
  }

  if (length(discrepancy_rows) == 0) return(empty)
  dplyr::bind_rows(discrepancy_rows)
}

# OPI exposes only a posting title, city, and date. Keep its statewide rows
# unless those fields identify the same posting on a directly scraped board;
# matching on city alone would hide unrelated employers in shared cities.
remove_opi_direct_duplicates <- function(opi_df, direct_df, registry, report_path = NULL) {
  required_opi <- c("title", "date_posted", "location")
  required_direct <- c("title", "date_posted", "District")
  required_registry <- c("District", "City")

  missing_opi <- setdiff(required_opi, names(opi_df))
  missing_direct <- setdiff(required_direct, names(direct_df))
  missing_registry <- setdiff(required_registry, names(registry))
  if (length(missing_opi) > 0 || length(missing_direct) > 0 || length(missing_registry) > 0) {
    stop(
      "Cannot deduplicate OPI postings; missing columns: ",
      paste(c(missing_opi, missing_direct, missing_registry), collapse = ", "),
      call. = FALSE
    )
  }

  if (!is.null(report_path)) {
    rep <- generate_opi_discrepancy_report(opi_df, direct_df, registry)
    write.csv(rep, report_path, row.names = FALSE)
  }

  normalize <- function(x) {
    normalized <- tolower(trimws(as.character(x)))
    normalized[is.na(x)] <- NA_character_
    gsub("[^[:alnum:]]+", " ", normalized)
  }
  complete_key <- function(title, date) {
    normalized_title <- normalize(title)
    normalized_date <- trimws(as.character(date))
    valid <- !is.na(normalized_title) & nzchar(normalized_title) &
      !is.na(date) & nzchar(normalized_date)
    key <- rep(NA_character_, length(title))
    key[valid] <- paste(normalized_title[valid], normalized_date[valid], sep = "\r")
    key
  }

  direct_keys <- complete_key(direct_df$title, direct_df$date_posted)
  direct_keys <- paste(direct_df$District, direct_keys, sep = "\r")
  direct_keys <- direct_keys[!is.na(direct_keys)]
  if (length(direct_keys) == 0 || nrow(opi_df) == 0) return(opi_df)

  city_forms <- normalize(registry$City)
  opi_keys <- complete_key(opi_df$title, opi_df$date_posted)
  opi_locations <- paste0(" ", normalize(opi_df$location), " ")
  is_duplicate <- vapply(seq_len(nrow(opi_df)), function(i) {
    if (is.na(opi_keys[i]) || is.na(opi_locations[i])) return(FALSE)

    city_matches <- which(vapply(
      city_forms,
      function(city) !is.na(city) && grepl(paste0(" ", city, " "), opi_locations[i], fixed = TRUE),
      logical(1)
    ))
    if (length(city_matches) == 0) return(FALSE)

    # "East Helena" also contains "Helena"; only use the most-specific city.
    city_matches <- city_matches[nchar(city_forms[city_matches]) == max(nchar(city_forms[city_matches]))]
    candidate_keys <- paste(registry$District[city_matches], opi_keys[i], sep = "\r")
    any(candidate_keys %in% direct_keys)
  }, logical(1))

  opi_df[!is_duplicate, , drop = FALSE]
}

# Central Safety Net Fallback: when a registered district's own direct scrape
# produced no rows this run (ATS outage, platform migration, scraping error),
# its surviving OPI postings are relabeled to the canonical registry district
# name so the district doesn't vanish from the dashboard for that week.
# Districts whose direct scrape did return rows keep their OPI rows under OPI's
# raw location label -- the registry-backed views (Map, District Summary,
# vacancy rates) count only direct rows for them, per DATA_COOKBOOK.md, and
# relabeling would double count jobs OPI and the district board word
# differently.
apply_opi_district_fallback <- function(opi_df, registry, direct_df = NULL) {
  if (nrow(opi_df) == 0) return(opi_df)
  if (!"location" %in% names(opi_df)) return(opi_df)
  if (!"District" %in% names(opi_df)) {
    opi_df$District <- opi_df$location
  }

  normalize_txt <- function(x) {
    normalized <- tolower(trimws(as.character(x)))
    normalized[is.na(x)] <- ""
    normalized <- gsub(",\\s*mt\\.?", "", normalized, ignore.case = TRUE)
    normalized <- gsub(",\\s*montana\\.?", "", normalized, ignore.case = TRUE)
    normalized <- gsub("\\s+mt$", "", normalized, ignore.case = TRUE)
    normalized <- gsub("\\s+montana$", "", normalized, ignore.case = TRUE)
    gsub("[^[:alnum:]]+", " ", normalized)
  }

  norm_cities <- trimws(normalize_txt(registry$City))
  city_counts <- table(norm_cities[nzchar(norm_cities)])
  unique_cities <- names(city_counts[city_counts == 1])

  primary_multi <- c(
    "big timber" = "Sweet Grass County High School",
    "bigfork" = "Bigfork School District 38",
    "billings" = "Billings Public Schools",
    "boulder" = "Boulder Elementary",
    "bozeman" = "Bozeman Public Schools",
    "clancy" = "Montana City Elementary School District #27",
    "columbia falls" = "Columbia Falls School District 6",
    "conrad" = "Conrad Public Schools",
    "havre" = "Havre Public Schools",
    "kalispell" = "Kalispell Public Schools",
    "lolo" = "Lolo School District 7",
    "marion" = "Marion School District #54",
    "missoula" = "Missoula County Public Schools",
    "stevensville" = "Stevensville Public Schools",
    "wolf point" = "Wolf Point Public Schools"
  )

  custom_phrases <- c(
    "10 miles north of troy" = "Troy School District",
    "4 miles north of harlem" = "Harlem Public Schools",
    "5 miles west of stanford" = "Stanford Public Schools",
    "6 miles east of wolf point" = "Frontier Elementary School",
    "841 bear canyon road" = "Bozeman Public Schools",
    "billings sd3" = "Billings Public Schools",
    "billings shepherd worden custer hysham" = "Billings Public Schools",
    "bozeman area" = "Bozeman Public Schools",
    "clancy mt city" = "Montana City Elementary School District #27",
    "east of kalispell" = "Kalispell Public Schools",
    "eureka" = "Eureka Public Schools",
    "manhattan amsterdam" = "Amsterdam School District #75",
    "mcleod" = "Sweet Grass County High School",
    "melville" = "Sweet Grass County High School",
    "mosby" = "Winnett Public Schools",
    "rocky boy" = "Rocky Boy Public Schools",
    "rocky boy agency" = "Rocky Boy Public Schools",
    "rudyard" = "North Star Public Schools",
    "rudyard gildford" = "North Star Public Schools",
    "rural havre" = "Havre Public Schools",
    "saint ignatius" = "St. Ignatius School District 28",
    "saint ignatius salish teacher" = "St. Ignatius School District 28",
    "sand coulee" = "Centerville Public Schools",
    "seeley lake" = "Seeley Lake Elementary #34",
    "st regis" = "Superior School District",
    "swan river in bigfork" = "Swan River School District #4",
    "ten minutes from missoula" = "Missoula County Public Schools",
    "valley view polson" = "Polson School District",
    "vida" = "Circle Public Schools",
    "wilsall" = "Shields Valley Public Schools"
  )

  direct_active <- if (!is.null(direct_df) && "District" %in% names(direct_df)) {
    unique(direct_df$District[!is.na(direct_df$District) & nzchar(direct_df$District)])
  } else {
    character(0)
  }

  registry_bases <- trimws(sub(" (school|district|elementary|public|high|schools|unified).*", "",
                               normalize_txt(registry$District)))
  registry_by_length <- order(nchar(registry_bases), decreasing = TRUE)

  for (i in seq_len(nrow(opi_df))) {
    cur_district <- as.character(opi_df$District[i])
    if (!is.na(cur_district) && cur_district %in% registry$District) next

    loc_raw <- as.character(opi_df$location[i])
    loc_norm <- trimws(normalize_txt(loc_raw))
    title_norm <- if ("title" %in% names(opi_df)) trimws(normalize_txt(opi_df$title[i])) else ""

    mapped_district <- NA_character_

    # 1. Custom phrase match
    for (phrase in names(custom_phrases)) {
      if (grepl(phrase, loc_norm, fixed = TRUE)) {
        mapped_district <- custom_phrases[[phrase]]
        break
      }
    }

    # 2. Specific sub-district match in title or location. Longest district
    # name first, so "East Helena" matches East Helena Public Schools rather
    # than Helena Public Schools.
    if (is.na(mapped_district)) {
      for (k in registry_by_length) {
        d_name <- registry$District[k]
        d_norm <- normalize_txt(d_name)
        d_base <- trimws(sub(" (school|district|elementary|public|high|schools|unified).*", "", d_norm))
        if (nchar(d_base) >= 5) {
          if (grepl(paste0(" ", d_base, " "), paste0(" ", loc_norm, " "), fixed = TRUE) ||
              grepl(paste0(" ", d_base, " "), paste0(" ", title_norm, " "), fixed = TRUE)) {
            mapped_district <- d_name
            break
          }
        }
      }
    }

    # 3. Direct unique city match or primary multi match
    if (is.na(mapped_district)) {
      city_idx <- which(norm_cities == loc_norm)
      if (length(city_idx) == 1) {
        mapped_district <- registry$District[city_idx]
      } else if (length(city_idx) > 1) {
        # A bare city name shared by several registry districts only maps to
        # that city's primary district; otherwise it's ambiguous and stays raw.
        if (loc_norm %in% names(primary_multi)) {
          mapped_district <- primary_multi[[loc_norm]]
        }
      }
    }

    # 4. Partial city match
    if (is.na(mapped_district)) {
      for (city in unique_cities) {
        if (nzchar(city) && grepl(paste0(" ", city, " "), paste0(" ", loc_norm, " "), fixed = TRUE)) {
          city_idx <- which(norm_cities == city)
          if (length(city_idx) == 1) {
            mapped_district <- registry$District[city_idx]
            break
          }
        }
      }
    }

    if (!is.na(mapped_district) && mapped_district %in% registry$District &&
        !mapped_district %in% direct_active) {
      opi_df$District[i] <- mapped_district
    }
  }

  opi_df
}
