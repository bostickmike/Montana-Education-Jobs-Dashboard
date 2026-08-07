# Heuristic scrapers for HE institutions with no real structured ATS --
# free-text prose on the institution's own site rather than a job-board
# platform this project has a clean API-based scraper for. Mirrors the
# Wyoming Education Jobs Dashboard's misc_district_scrapers.R in spirit
# (own header comment there: "inherently less reliable than every other
# source in this pipeline... tested against real captured content"), just
# on the Higher Ed side and named accordingly.
#
# Miles Community College (milescc.edu/employment/) is the first entry:
# real, current openings in plain prose, not JSON/HTML with real per-
# posting markup. Confirmed live 2026-08-06: every job title on the page
# is inside its own <strong> tag ending in ":", immediately followed by
# a small, stable set of repeating section-label <strong> tags (also
# ending in ":") -- "Qualifications:", "Application Process:",
# "Preferred:", "Work Schedule:", "Required:". Titles are recovered by
# taking every colon-terminated <strong> NOT in that label set. This is a
# real heuristic, not a guarantee -- a future posting using a section
# label this list doesn't yet know about would be silently misread as a
# job title (or vice versa), which is why this lives in its own file
# clearly separated from the platform-API scrapers in
# direct_api_scrapers.R rather than blended in as if it had the same
# reliability.
#
# No stable per-posting URL, Location, or Posted_Date exists on this page
# (one long page, no anchors/IDs per posting, deadlines given in free-text
# prose in inconsistent formats) -- Location is the institution's one real
# campus city, Posted_Date is left NA (a genuine absence, not a parsing
# gap), and Link is the shared employment page URL for every row, the same
# honest-fallback pattern already used for Montana's other sources with no
# real per-posting deep link (the OPI statewide feed in
# direct_api_scrapers.R).

suppressMessages({
  library(httr2)
  library(rvest)
  library(xml2)
})

MILES_CC_NON_TITLE_LABELS <- c(
  "Qualifications:", "Application Process:", "Preferred:", "Required:", "Work Schedule:"
)

fetch_miles_cc_postings <- function(url = "https://www.milescc.edu/employment/") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    req_perform()
  parse_miles_cc_postings(resp_body_string(resp), url)
}

parse_miles_cc_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  strong_texts <- rvest::html_text2(rvest::html_elements(page, "strong"))

  titles <- strong_texts[
    grepl(":$", strong_texts) &
      !(strong_texts %in% MILES_CC_NON_TITLE_LABELS)
  ]
  titles <- sub(":$", "", titles)
  titles <- unique(titles[nzchar(titles)])

  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = "Miles City",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# Dawson Community College (dawson.edu/employment-opportunities.html) --
# real, current openings grouped under labeled <h4> section headings
# ("Coach Openings:", "Faculty Openings", "Adjunct Faculty Openings:",
# "Administrative Openings:", "Staff Openings:",
# "Part-time/Temporary/Other Openings:", "Internal Openings:") each
# immediately followed (when non-empty) by a Firespring-CMS
# `div.collection.collection--list` block whose items are real per-
# posting links (confirmed live 2026-08-07: 7 real postings, each a
# PDF/DOCX download rather than an HTML detail page, e.g. "Assistant I
# Track Coach"). A heading with no postings currently open (e.g. "Internal
# Openings:") has no following collection div at all -- its immediate
# next sibling is the next heading -- so this is a real, cleanly
# detectable empty-section case, not a parsing failure. Filtering on
# section headings containing "Openings" is what excludes the page's own
# boilerplate application-form links ("DCC Employment Application", "Fill
# out our secure employment application online") which live under the
# unrelated "How to Apply:" heading and would otherwise look identical
# (same markup, same /file_download/ URL pattern).
DAWSON_CC_OPENINGS_HEADING_PATTERN <- "Openings"

fetch_dawson_cc_postings <- function(url = "https://www.dawson.edu/employment-opportunities.html") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    req_perform()
  parse_dawson_cc_postings(resp_body_string(resp), url)
}

parse_dawson_cc_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  headings <- rvest::html_elements(page, "h4")
  heading_texts <- rvest::html_text2(headings)
  opening_idx <- grep(DAWSON_CC_OPENINGS_HEADING_PATTERN, heading_texts)

  rows <- lapply(opening_idx, function(i) {
    sib <- xml2::xml_find_first(headings[[i]], "following-sibling::*[1][self::div]")
    if (is.na(sib)) return(NULL)

    links <- rvest::html_elements(sib, ".collection-item-label a")
    if (length(links) == 0) return(NULL)

    hrefs <- rvest::html_attr(links, "href")
    hrefs <- ifelse(grepl("^https?://", hrefs), hrefs, paste0("https://www.dawson.edu", hrefs))

    data.frame(
      Title = rvest::html_text2(links),
      Location = "Glendive",
      Posted_Date = NA_character_,
      Link = hrefs,
      stringsAsFactors = FALSE
    )
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]

  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Carroll College (carroll.edu/faculty-staff-positions) -- real, current
# openings under an accordion widget, confirmed live 2026-08-07: every
# `.accordion__trigger` button on the page is a real job title (the page
# has exactly two "Positions" sections, Faculty and Staff, and no
# unrelated accordion elsewhere on the page uses this class), 16 real
# postings. No per-posting URL (application is by email to
# employment@carroll.edu), no Posted_Date, single real campus (Helena) --
# same honest-fallback pattern as Miles CC above.
fetch_carroll_college_postings <- function(url = "https://www.carroll.edu/faculty-staff-positions") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    req_perform()
  parse_carroll_college_postings(resp_body_string(resp), url)
}

parse_carroll_college_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  titles <- rvest::html_text2(rvest::html_elements(page, ".accordion__trigger"))
  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = "Helena",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# Rocky Mountain College (rocky.edu/employment) -- a real WordPress/
# Elementor "loop" of custom-post-type postings, each with its own real
# detail-page URL (e.g. rocky.edu/employment/opportunities/{slug}/,
# confirmed live 200s standalone) and a real department term -- cleaner
# than Miles/Dawson/Carroll's free-text pattern, but still no ATS vendor
# behind it, so it lives here rather than in direct_api_scrapers.R. The
# loop's first item is a hidden Elementor template row with no title link
# (confirmed live) -- filtered out by requiring a real title. No
# Posted_Date field exists on the listing page. Location stores the real
# department (Admissions, Aviation, Athletics, etc.) rather than a city,
# same "Location repurposed as department for a single-campus
# institution" convention as JazzHR/PeopleAdmin multi-department schools
# (see DATA_COOKBOOK.md).
fetch_rocky_mountain_college_postings <- function(url = "https://rocky.edu/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    req_perform()
  parse_rocky_mountain_college_postings(resp_body_string(resp))
}

parse_rocky_mountain_college_postings <- function(html_text) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  items <- rvest::html_elements(page, "div.e-loop-item")
  if (length(items) == 0) return(empty)

  rows <- lapply(items, function(item) {
    title_el <- rvest::html_element(item, ".elementor-heading-title a")
    title <- rvest::html_text2(title_el)
    if (is.na(title) || !nzchar(title)) return(NULL)

    dept_el <- rvest::html_element(item, ".elementor-post-info__terms-list-item")
    dept <- rvest::html_text2(dept_el)

    data.frame(
      Title = title,
      Location = ifelse(is.na(dept), "Billings", dept),
      Posted_Date = NA_character_,
      Link = rvest::html_attr(title_el, "href"),
      stringsAsFactors = FALSE
    )
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]

  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}
