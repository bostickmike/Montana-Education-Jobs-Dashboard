# State-specific classification helpers. The shared classifier (position,
# subject, broad category, HE job type and faculty category, title encoding
# and detail, posted pay, placeholders) lives in the edjobs package since
# phase 2 of the package migration (2026-11-11; edjobs 0.3.0), and this file
# attaches it, so every script that sources this file still gets the whole
# classifier. A change to classification belongs in edjobs, not here.
#
# Kept here: this state's district and institution name corrections
# (canonicalize_k12_district(), canonicalize_he_institution()) and the K-12
# posting-identity code, which differs between the states.

suppressMessages(library(dplyr))
suppressMessages(library(edjobs))

# Normalize scraped text without corrupting text that is already valid UTF-8.
# Some legacy listings really do contain raw Windows-1252 bytes, but treating
# every string as Windows-1252 turns valid characters such as “é” into
# mojibake. Only strings that fail a UTF-8 round trip are repaired as CP1252.
# The same repair as edjobs::fix_title_encoding(); this name is the one MT's
# posting-identity code uses.
normalize_posting_text <- function(x) fix_title_encoding(x)

normalize_posting_identity_component <- function(x) {
  out <- tolower(normalize_posting_text(x))
  gsub("\\s+", " ", out)
}

is_opi_statewide_posting <- function(url) {
  grepl(
    "apps\\.opi\\.mt\\.gov/mtjobsforteachers",
    normalize_posting_text(url),
    ignore.case = TRUE
  )
}

# A URL is a posting identity only when its path/query carries a known
# per-posting identifier. Board/listing URLs are deliberately not used: a
# board can host many simultaneous postings.
is_stable_posting_url <- function(url) {
  grepl(
    "(/jobs?/[^/?#]+|/job-list/[^/?#]+|/opening/\\d+|ViewJob\\.aspx\\?JobID=|[?&](jobId|jobID|id|AppliTrackJobId)=|\\.pdf(?:[?#]|$))",
    normalize_posting_text(url),
    perl = TRUE
  )
}

# Builds the one K-12 identity contract used by current counts, historical
# aggregates, trends, and week-over-week matching. Direct structured listings
# use their stable per-posting URL. Sources without one (including OPI's
# WebForms feed) get an explicit, count-preserving fallback. Equal fallback
# records receive an occurrence suffix so they are not silently collapsed;
# that suffix is deterministic within a source snapshot, not a claim that OPI
# supplies a stable posting ID.
add_k12_posting_identity <- function(df) {
  required <- c("title", "location", "date_posted", "url", "District")
  missing <- setdiff(required, names(df))
  if (length(missing) > 0) {
    stop(
      "add_k12_posting_identity(): missing column(s): ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  # A row-level fallback, not a column-level one: some archived weeks
  # predate Posting_Source existing at all (see history_accumulator bug
  # writeup), and bind_rows()-ing those alongside newer weeks that do have
  # the column fills the older rows' value with NA rather than dropping
  # the column -- so "column present" is not the same as "every row has a
  # real value". Checking na/blank per row (instead of gating the whole
  # URL-based guess on whether the column exists anywhere in df) means an
  # old, column-less row and a new row with a genuinely blank
  # Posting_Source get identical, correct treatment: guess OPI from its
  # known URL, otherwise default to "Direct district board".
  url_based_source <- ifelse(is_opi_statewide_posting(df$url),
                              "OPI Jobs for Teachers (statewide)",
                              "Direct district board")
  if ("Posting_Source" %in% names(df)) {
    source <- normalize_posting_text(df$Posting_Source)
    missing_source <- is.na(source) | !nzchar(source)
    source[missing_source] <- url_based_source[missing_source]
  } else {
    source <- url_based_source
  }

  title <- normalize_posting_identity_component(df$title)
  location <- normalize_posting_identity_component(df$location)
  posted <- normalize_posting_identity_component(df$date_posted)
  district <- normalize_posting_identity_component(df$District)
  url <- normalize_posting_text(df$url)
  is_opi <- is_opi_statewide_posting(url) |
    source == "OPI Jobs for Teachers (statewide)"
  stable_url <- !is_opi & !is.na(url) & nzchar(url) & is_stable_posting_url(url)

  fallback_base <- paste(
    ifelse(is_opi, "opi-fallback", "source-fallback"),
    normalize_posting_identity_component(source),
    district,
    title,
    location,
    posted,
    sep = "\u001f"
  )
  fallback_occurrence_group <- fallback_base
  if ("Archive_Date" %in% names(df)) {
    fallback_occurrence_group <- paste(
      fallback_base,
      normalize_posting_identity_component(df$Archive_Date),
      sep = "\u001f"
    )
  }
  fallback_occurrence <- ave(
    seq_along(fallback_base),
    fallback_occurrence_group,
    FUN = seq_along
  )

  posting_id <- paste0("fallback:", fallback_base, "#", fallback_occurrence)
  posting_id[stable_url] <- paste0("url:", tolower(url[stable_url]))

  df$Posting_Source <- source
  df$Posting_Identity_Method <- ifelse(
    stable_url,
    "Stable per-posting URL",
    ifelse(
      is_opi,
      "OPI fallback: title + raw location + posted date (not a stable OPI ID)",
      "Source fallback: title + location + posted date (no stable posting URL)"
    )
  )
  df$Posting_ID <- posting_id
  df
}

# summarize_k12_posting_counts() is in edjobs since 0.10.0.

find_k12_new_postings <- function(k12_history) {
  dates <- sort(unique(as.Date(k12_history$Archive_Date)))
  if (length(dates) < 2) return(k12_history[0, , drop = FALSE])

  latest <- dates[length(dates)]
  previous <- dates[length(dates) - 1]
  k12_history %>%
    filter(as.Date(Archive_Date) == latest) %>%
    anti_join(
      k12_history %>% filter(as.Date(Archive_Date) == previous) %>% select(Posting_ID),
      by = "Posting_ID"
    )
}

# ---------------------------------------------------------------------------
# K-12
# ---------------------------------------------------------------------------

# Normalizes district/location labels so one place doesn't split into
# several in the dashboard's dropdowns, trend lines and the weekly-totals
# download. Registry district names pass through unchanged; the labels this
# touches are OPI Jobs for Teachers' free-text locations, which arrive as
# "BILLINGS", "Billings" and "Billings, MT" for the same place: whitespace is
# squished, a trailing ", MT" / ", Mt." / ", Montana" is dropped, and an
# ALL-CAPS label is title-cased.
canonicalize_k12_district <- function(district) {
  d <- gsub("[[:space:]]+", " ", trimws(as.character(district)))
  d <- sub(",?[[:space:]]*(MT|Mt\\.?|Montana)\\.?$", "", d)
  all_caps <- !is.na(d) & grepl("[A-Z]", d) & d == toupper(d)
  d[all_caps] <- tools::toTitleCase(tolower(d[all_caps]))
  d
}

# ---------------------------------------------------------------------------
# Posted pay
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Higher Ed
# ---------------------------------------------------------------------------

# Fixes known misspellings of institution names at the source, the HE analog
# of canonicalize_k12_district() above. Empty for now -- no Montana
# institution name typos have been confirmed in scraped data yet. Plain
# passthrough for the same case_when(TRUE ~ ...) deprecation reason as
# canonicalize_k12_district() above.
canonicalize_he_institution <- function(institution) {
  institution
}

