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
