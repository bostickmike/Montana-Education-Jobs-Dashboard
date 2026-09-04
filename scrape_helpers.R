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
perform_with_retry <- function(req, max_tries = 3) {
  req %>%
    httr2::req_retry(max_tries = max_tries, backoff = function(i) 2^i) %>%
    httr2::req_perform()
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
  df
}

# OPI exposes only a posting title, city, and date. Keep its statewide rows
# unless those fields identify the same posting on a directly scraped board;
# matching on city alone would hide unrelated employers in shared cities.
remove_opi_direct_duplicates <- function(opi_df, direct_df, registry) {
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
