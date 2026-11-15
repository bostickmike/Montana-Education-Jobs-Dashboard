# Heuristic scrapers for K-12 districts with no real structured ATS --
# free-text/DOM prose on the district's own site rather than a job-board
# platform this project has a clean API-based scraper for. Mirrors the
# Wyoming Education Jobs Dashboard's misc_district_scrapers.R and this
# project's own misc_college_scrapers.R in spirit -- a real but
# acknowledged-less-reliable source, kept in its own file rather than
# blended into direct_api_scrapers.R as if it had the same reliability.
#
# Livingston (livingston.k12.mt.us) and Lodge Grass (lgschools.org) are the
# first two entries, found via the OPI-gap analysis of 2026-08-07 (the
# highest-volume OPI-only locations not yet on a supported platform).
# Wolf Point and Plentywood (also from that analysis) are further down
# this file -- both run Apptegy, a CMS whose pages need a real browser to
# render (see the "Apptegy (chromote-driven)" section below for why).
#
# Two other candidates from that same analysis are NOT here:
#   - "Box Elder" in the OPI gap list is very likely Rocky Boy Public
#     Schools under its real town name (already a registered AppliTrack
#     district; Rocky Boy is the reservation name, Box Elder the town,
#     the same pattern as Blackfeet CC/Browning) rather than a genuinely
#     separate uncovered district -- not independently verified further,
#     but not built as a new scraper on that basis. (Later corrected --
#     see Box Elder Public Schools' own investigation in this project's
#     history: it IS a real, separate district, but its own real
#     employment page turned out to be a static flyer IMAGE with no real
#     text at all, needing OCR to extract -- deliberately not built, one
#     confirmed case isn't worth a whole new extraction technique.)
#   - "Busby" is Northern Cheyenne Tribal School, a BIE-funded tribal
#     school -- explicitly out of scope per RESEARCH_NOTES.md's original
#     K-12 scoping decision ("Montana has multiple BIE-funded/tribally-
#     controlled K-12 schools on its 7 reservations... Out of scope for
#     v1, consistent with Wyoming's scope").
#
# Broadview (broadviewschools.org, an "Educational Networks" CMS district)
# was added 2026-08-16 from a follow-up OPI-gap pass -- see its own comment
# block below.
#
# A second, larger 2026-08-16 pass went deeper down that same OPI-gap
# ranking and specifically re-checked every remaining candidate against
# platforms this project had NOT yet tried for K-12 (Apptegy, Finalsite --
# both already used elsewhere in this project, just not for K-12 beyond
# Wolf Point/Plentywood). It found 6 more real districts, all documented in
# their own comment blocks below: Conrad, Westby, Choteau, Gardiner, and
# Malta (all Apptegy) and Drummond (also genuinely Apptegy, despite an
# initial red herring -- see its own comment). One more candidate, Condon
# (Swan Valley Elementary School District), was investigated and NOT added:
# its real site (swanvalleyelementary.org -- NOT swanvalleyschools.com,
# which is Saginaw, Michigan's same-named district, the same trap Ashland/
# Hot Springs/Lima/Nashua already caught this project in before) has exactly
# one real current posting, but described only in free-flowing prose with
# no title, heading, or list marker of any kind -- the same "one confirmed
# case isn't worth a whole new extraction technique" judgment call already
# made for Box Elder above.

suppressMessages({
  library(httr2)
  library(rvest)
  library(jsonlite)
})

# Livingston Public Schools (livingston.k12.mt.us) -- an Edlio/Blackboard-
# style CMS. Real postings are PDF links (class "attachment-type-pdf")
# grouped under school-building headers ("PARK HIGH SCHOOL", "SLEEPING
# GIANT MIDDLE SCHOOL", etc.) inside `div.page-block-files` blocks, each
# immediately preceded by a `div.page-block-text` header block -- but the
# same visual "OTHER DISTRICT POSTINGS" section genuinely mixes one real-
# postings items-block with a second items-block of boilerplate
# application forms/tax documents in the same header (confirmed live
# 2026-08-07), so section-heading scoping alone (the Dawson CC approach)
# doesn't cleanly separate them here. Filtered by title content instead:
# real postings never match the application-form/HR-document title
# pattern below, confirmed against every real title on the page.
LIVINGSTON_NON_JOB_TITLE_PATTERN <- "Application|W-4|\\bI-9\\b|Agreement|\\bCBA\\b|Handbook|Policy"

fetch_livingston_postings <- function(url = "https://www.livingston.k12.mt.us/apps/pages/index.jsp?uREC_ID=2055955&type=d&pREC_ID=2121638") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_livingston_postings(resp_body_string(resp), url)
}

parse_livingston_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  blocks <- rvest::html_elements(page, "div.page-block")

  rows <- list()
  current_header <- NA_character_
  for (block in blocks) {
    cls <- rvest::html_attr(block, "class")
    if (grepl("page-block-text", cls, fixed = TRUE)) {
      txt <- trimws(rvest::html_text2(block))
      if (nzchar(txt) && nchar(txt) < 60) current_header <- txt
    } else if (grepl("page-block-files", cls, fixed = TRUE)) {
      links <- rvest::html_elements(block, ".attachment-type-pdf")
      if (length(links) == 0) next
      titles <- rvest::html_text2(links)
      keep <- !grepl(LIVINGSTON_NON_JOB_TITLE_PATTERN, titles, ignore.case = TRUE)
      if (!any(keep)) next
      rows[[length(rows) + 1]] <- data.frame(
        Title = titles[keep],
        Location = current_header,
        Posted_Date = NA_character_,
        Link = rvest::html_attr(links, "href")[keep],
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Lodge Grass Public Schools (lgschools.org) -- an "Educational Networks"
# CMS with real openings split across 3 tabs of the same Employment page
# (uREC_ID=373420): the default view ("Certified Job Opening"), pREC_ID
# 1206958 ("Classified Job Openings"), and pREC_ID 1206962 ("Coach - Open
# Positions") -- confirmed live 2026-08-07 that a 4th tab
# ("Application Forms", pREC_ID 693676) is boilerplate, correctly
# excluded by not being fetched at all. All 3 real tabs share the same
# markup: every posting is an `a.en-pe-btn` link, but the SAME class is
# also used for the page's own "Apply Now" call-to-action button (appears
# once or twice per tab) -- filtered out by exact title match rather than
# a content pattern, since "Apply Now" title text is fixed and known. A
# real, confirmed content-authoring defect on the Certified tab -- 6 of
# the 11 real titles are pasted twice in slightly different list order --
# is resolved with the same unique()-based dedup as Miles CC. A genuinely
# empty tab (e.g. Coach, when no coaching positions are posted) shows the
# literal text "Coaching Positions will be posted when available" instead
# of any `a.en-pe-btn` elements -- a real empty state, not a parsing gap.
LODGEGRASS_APPLY_NOW_TITLES <- c(
  "Apply Now – Certified Educator Application",
  "Apply Now – Classified Application",
  "Apply Now – Coach Application"
)

LODGEGRASS_TABS <- list(
  list(pREC_ID = NA, location = "Certified"),
  list(pREC_ID = "1206958", location = "Classified"),
  list(pREC_ID = "1206962", location = "Coach")
)

fetch_lodgegrass_postings <- function(base_url = "https://www.lgschools.org/apps/pages/index.jsp?uREC_ID=373420&type=d") {
  all_tabs <- lapply(LODGEGRASS_TABS, function(tab) {
    tab_url <- if (is.na(tab$pREC_ID)) base_url else paste0(base_url, "&termREC_ID=&pREC_ID=", tab$pREC_ID)
    resp <- request(tab_url) %>%
      req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
      perform_with_retry()
    parse_lodgegrass_postings(resp_body_string(resp), tab$location, tab_url)
  })
  dplyr::bind_rows(all_tabs)
}

parse_lodgegrass_postings <- function(html_text, location, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  titles <- rvest::html_text2(rvest::html_elements(page, "a.en-pe-btn"))
  titles <- unique(trimws(titles))
  titles <- titles[!(titles %in% LODGEGRASS_APPLY_NOW_TITLES) & nzchar(titles)]

  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = location,
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# Broadview School District (broadviewschools.org) -- a third "Educational
# Networks" CMS district (same platform as Livingston/Lodge Grass), found via
# the 2026-08-16 OPI-gap follow-up pass. Structurally different from both
# prior districts, though: instead of one page (Livingston) or one uREC_ID
# with 3 tab query params (Lodge Grass), Broadview splits real postings
# across 4 separate pages -- 3 under one uREC_ID (425960: Certified
# pREC_ID=783189, Classified pREC_ID=1074965, Extra Curricular
# pREC_ID=1069330) plus a 4th under a totally different uREC_ID (559289,
# pREC_ID=1200157) for "Coaching Position Vacancies" -- a joint Broadview/
# Lavina Sports Cooperative page (Lavina itself is not a registered district
# in this project; these rows are tagged with a Location that makes the
# co-op sourcing explicit rather than silently attributing them to Broadview
# alone).
#
# No shared CSS class marks postings the way Lodge Grass's a.en-pe-btn does
# -- confirmed live 2026-08-16, each of the 4 pages is free-authored prose/
# list text, and each uses a DIFFERENT list convention:
#   - Classified: "-TITLE" dash-prefixed lines, e.g. "-BUS DRIVERS".
#   - Coaching co-op: ALL-CAPS lines following a "...the following
#     positions:" trigger line, e.g. "CHEERLEADING ADVISOR (HS/JH)".
#   - Extra Curricular: a single Title Case line immediately following the
#     page's "For the <year> School Year" header line, then free prose
#     description -- only one real posting existed live, so this function's
#     multi-posting behavior on this specific page is unconfirmed.
#   - Certified: 0 real postings live (just the page's own contact block) --
#     parsed with the same dash-list style as Classified on the assumption
#     it shares that convention when populated (same uREC_ID family, same
#     superintendent-authored page), but that assumption is NOT independently
#     confirmed against a real populated Certified page.
# Every page shares one real, confirmed contact-block boundary ("If you are
# interested" or "Please submit") that reliably marks the end of real posting
# content, used here as a shared stop line the way Wolf Point uses "Find Us".
BROADVIEW_PAGES <- list(
  list(uREC_ID = "425960", pREC_ID = "783189", location = "Certified", style = "dash"),
  list(uREC_ID = "425960", pREC_ID = "1074965", location = "Classified", style = "dash"),
  list(uREC_ID = "425960", pREC_ID = "1069330", location = "Extra Curricular", style = "titleline"),
  list(uREC_ID = "559289", pREC_ID = "1200157", location = "Coaching (Broadview/Lavina Co-op)", style = "allcaps")
)

BROADVIEW_STOP_LINE_PATTERN <- "^(If you are interested|Please submit)"

fetch_broadview_postings <- function() {
  all_pages <- lapply(BROADVIEW_PAGES, function(pg) {
    url <- paste0("https://www.broadviewschools.org/apps/pages/index.jsp?uREC_ID=",
                  pg$uREC_ID, "&type=d&pREC_ID=", pg$pREC_ID)
    resp <- request(url) %>%
      req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
      perform_with_retry()
    parse_broadview_page(resp_body_string(resp), pg$location, pg$style, url)
  })
  dplyr::bind_rows(all_pages)
}

parse_broadview_page <- function(html_text, location, style, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  stop_idx <- which(grepl(BROADVIEW_STOP_LINE_PATTERN, lines))
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  titles <- switch(style,
    dash = trimws(sub("^-+", "", lines[grepl("^-", lines)])),
    allcaps = {
      trigger <- which(grepl("following positions:$", lines, ignore.case = TRUE))
      if (length(trigger) == 0 || trigger[1] >= length(lines)) character(0) else {
        candidates <- lines[(trigger[1] + 1):length(lines)]
        candidates[grepl("^[A-Z0-9][A-Z0-9 /()'-]+$", candidates) & nchar(candidates) <= 60]
      }
    },
    titleline = {
      trigger <- which(grepl("School Year$", lines))
      if (length(trigger) == 0 || trigger[1] >= length(lines)) character(0) else {
        cand <- lines[trigger[1] + 1]
        if (grepl("[.:]$", cand) || nchar(cand) > 60) character(0) else cand
      }
    },
    character(0)
  )

  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = unique(titles), Location = location, Posted_Date = NA_character_,
             Link = url, stringsAsFactors = FALSE)
}


# Scobey Schools (scobeyschools.com) -- a Weebly site (found via a
# 2026-08-16 follow-up on Scobey specifically, the single highest-volume
# OPI-only location left after the two prior passes -- it was on the
# original 23-town candidate list but never got a definitive answer
# recorded). Real postings are bold/colored `*TITLE` lines grouped under
# real (non-asterisk) category headers ("TEACHING STAFF", "SUPPORT TEACHING
# STAFF", "BUS DRIVERS", "COACHING STAFF") -- confirmed live 2026-08-16, 13
# real postings. Only https (not plain http) redirects to www and fails to
# resolve for this domain -- confirmed live the site is only reachable over
# plain http, an intentionally different req_url scheme from every other
# scraper in this file, not an oversight. Every real header/posting line in
# the raw page carries a leading zero-width space (U+200B) baked into the
# site's own authored content -- stripped here, not a parsing artifact.
fetch_scobey_postings <- function(url = "http://scobeyschools.com/employment.html") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_scobey_postings(resp_body_string(resp), url)
}

parse_scobey_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(gsub("​", "", lines))
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "TEACHING STAFF")
  stop_idx <- which(grepl("^SCOBEY SCHOOLS IS IN NEED OF|^CURRENT JOB OPENINGS", lines))
  if (length(start_idx) == 0 || length(stop_idx) == 0 || stop_idx[1] <= start_idx[1]) return(empty)
  window <- lines[start_idx[1]:(stop_idx[1] - 1)]

  rows <- list()
  current_header <- NA_character_
  for (line in window) {
    if (grepl("^\\*", line)) {
      title <- trimws(sub("^\\*", "", line))
      if (nzchar(title) && !is.na(current_header)) {
        rows[[length(rows) + 1]] <- data.frame(Title = title, Location = current_header,
                                                Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
      }
    } else {
      current_header <- line
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Ramsay School District #3 (ramsayschool.com) -- found in the 2026-08-23
# pass working down the remaining OPI-gap candidate list. A plain
# WordPress site, no chromote needed. Real postings sit in one real,
# testable structural marker: an `<h2>Open Positions</h2>` heading
# immediately followed by a single `<p>` whose lines are `<br>`-separated
# titles (rvest::html_text2() already splits a `<br>` the same way it
# splits a block boundary) -- confirmed live 2026-08-23, 2 real postings
# (Bus Monitor, Para-Professional).
fetch_ramsay_postings <- function(url = "https://ramsayschool.com/employment/") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_ramsay_postings(resp_body_string(resp), url)
}

parse_ramsay_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  heading <- rvest::html_elements(page, xpath = "//h2[contains(text(), 'Open Positions')]")
  if (length(heading) == 0) return(empty)

  p_node <- rvest::html_element(heading[[1]], xpath = "following-sibling::p[1]")
  if (is.na(p_node)) return(empty)

  titles <- trimws(strsplit(rvest::html_text2(p_node), "\n")[[1]])
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Ramsay", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Roy School District 74 (roy.k12.mt.us) -- found in the same 2026-08-23
# pass, a plain Joomla site (`sp-page-builder`), no chromote needed. Real
# postings are two prose sentences sharing one real, repeatable template
# ("Roy School District 74 is looking for a <TITLE>.") plus one separately
# authored bold/underlined all-caps line ("BUS DRIVER NEEDED") -- confirmed
# live 2026-08-23, 3 real postings (Head Cook, Full-time Paraprofessional,
# Bus Driver).
fetch_roy_postings <- function(url = "https://roy.k12.mt.us/") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_roy_postings(resp_body_string(resp), url)
}

parse_roy_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]

  looking_lines <- lines[grepl("is looking for an?\\s", lines)]
  looking_titles <- trimws(sub(".*is looking for an?\\s+([^.]+)\\..*", "\\1", looking_lines))

  bus_titles <- if (any(grepl("^BUS DRIVER NEEDED", lines))) "Bus Driver" else character(0)

  titles <- c(looking_titles, bus_titles)
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Roy", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Arrowhead Elementary School District #75 (arrowheadk8.com, serving Pray
# and Emigrant) -- found in the same 2026-08-23 pass, a modern WordPress/
# Divi site, no chromote needed. Real postings are each a genuine `<h2>`
# heading inside their own Divi card, bounded by 2 real, stable page
# headings that aren't postings themselves ("Join the Arrowhead Team" the
# intro, "Equal Opportunity Employer" the boilerplate after) -- confirmed
# live 2026-08-23, 3 real postings (Substitute Employment, Special
# Education Paraprofessional, Certified Teachers). This site's WAF blocks
# httr2's request with the same Mac/Chrome-120 UA every other plain-fetch
# scraper in this file uses (a real HTTP 403, confirmed live) but allows a
# Windows/Chrome-124 UA -- a real, confirmed site-specific requirement, not
# an arbitrary swap.
ARROWHEAD_START_HEADING <- "Join the Arrowhead Team"
ARROWHEAD_STOP_HEADING <- "Equal Opportunity Employer"

fetch_arrowhead_postings <- function(url = "https://arrowheadk8.com/careers/") {
  resp <- request(url) %>%
    perform_with_retry()
  parse_arrowhead_postings(resp_body_string(resp), url)
}

parse_arrowhead_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  headings <- trimws(rvest::html_text2(rvest::html_elements(page, "h2")))

  start_idx <- which(headings == ARROWHEAD_START_HEADING)
  stop_idx <- which(headings == ARROWHEAD_STOP_HEADING)
  if (length(start_idx) == 0 || length(stop_idx) == 0 || stop_idx[1] <= start_idx[1] + 1) return(empty)

  titles <- headings[(start_idx[1] + 1):(stop_idx[1] - 1)]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Pray", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}


# Hinsdale Public Schools (hinsdale.k12.mt.us, found 2026-08-24) --
# named "HINSDALE PUBLIC SCHOOLS" in its own page title but branded
# "sp-page-builder"/CMS chrome that doesn't match any platform this
# project already tracks (an unbranded CMS, same effort-level decline
# as declaring it "no recognized platform" rather than forcing a fit).
# The real employment content sits at a URL ending in "-Untitled.html"
# (a naming red flag that has meant "no real content" before -- Lavina's
# own decline this session used the same naming pattern) but this one
# genuinely does have real content, confirmed live: a plain httr2 fetch
# (no chromote needed). Real postings are a numbered list, 2 of the 3
# titles literally being ".docx" filenames -- stripped along with the
# leading "N. " list marker. Confirmed live 2026-08-24, 3 real postings.
# Starts after the real intro sentence (matched by regex since it's
# realistically stable phrasing, not likely to be re-authored casually),
# stops at "Please contact:", the real, stable boundary before contact
# info.
HINSDALE_START_PATTERN <- "^The Hinsdale School District is currently looking for the following positions:"

fetch_hinsdale_postings <- function(url = "https://hinsdale.k12.mt.us/District/1557-Untitled.html") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_hinsdale_postings(resp_body_string(resp), url)
}

parse_hinsdale_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(grepl(HINSDALE_START_PATTERN, lines))
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "Please contact:")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  # The "N. " marker is hand-typed text, not an <ol>, and the district
  # dropped it once the list shrank to a single posting (2026-09-22:
  # just "Route Bus Drivers", unnumbered) -- so every line in the block
  # is a candidate, with the marker stripped if present. The "*Pay is
  # dependent on experience..." footnote is the only non-posting line
  # between the intro and "Please contact:".
  titles <- lines[!startsWith(lines, "*")]
  titles <- sub("^[0-9]+\\.\\s*", "", titles)
  titles <- sub("\\.(docx|pdf|doc)$", "", titles, ignore.case = TRUE)
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Hinsdale", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}


# Roberts Public School (robertsrockets.org, found 2026-08-24) -- a
# Joomla-based CMS ("uikit"/"el-item" theme classes), plain httr2 fetch.
# Real postings render as a genuine HTML table (`table.uk-table`), each
# with its own `.el-title` element -- but that same CSS class is reused
# elsewhere on the page for unrelated application-form cards, so the
# selector is scoped to `table.uk-table tbody tr .el-title` specifically
# rather than matched loosely. Confirmed live 2026-08-24, 3 real
# postings (Full Time Custodian, Substitute Teachers Needed, Classroom
# Aide). Its Cloudflare front intermittently answers 502/520 to CI
# runners, so it retries those too, with a longer budget (~1 min).
# From 2026-11-03 the site answers HTTP 200 with the bare text " site under
# maintenance " (no HTML); read_html() took that for a file path. A body with
# no markup now fails with that text as the error, so the run logs an error
# (the source wasn't healthy) that says what happened.
fetch_roberts_postings <- function(url = "https://www.robertsrockets.org/index.php/district-information/district-employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry(max_tries = 6, is_transient = is_transient_gateway_error)
  parse_roberts_postings(resp_body_string(resp), url)
}

parse_roberts_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  if (!grepl("<", html_text, fixed = TRUE)) {
    stop("Roberts returned a page with no HTML: \"", substr(trimws(html_text), 1, 80), "\"", call. = FALSE)
  }
  page <- rvest::read_html(html_text)
  titles <- rvest::html_text2(rvest::html_elements(page, "table.uk-table tbody tr .el-title"))
  titles <- trimws(titles)
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Roberts", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}


# Winnett Public Schools (winnettschool.org, found 2026-08-24) --
# Squarespace, same platform as Terry above, plain httr2 fetch. 3 real
# category headers (Certified/Classified/Coaching Positions Open:),
# each a flat list of 0+ titles before its own boilerplate "[X] Staff
# Application" link line -- one title ("Activity Bus Driver - Bus
# driver needed to transport...") combines title and description on one
# line via " - ", split the same way as Lolo/St Regis/Winnett's own
# other combined-line cases. A stray bare-year artifact line ("2026-2027
# School Year") under Certified is the same kind of content-authoring
# leftover as Froid's, excluded by pattern. Squarespace's own inline
# `<style>` block text leaks into html_text2() as literal "#block-..."
# lines on this page (not seen on Terry's own page), filtered out
# explicitly. Confirmed live 2026-08-24, 4 real postings; Certified is
# genuinely empty right now. Stops at "Teacher Application
# Requirements:", the real, stable boundary before generic application
# instructions.
WINNETT_CATEGORIES <- c("Certified Positions Open:", "Classified Positions Open:", "Coaching Positions Open:")
WINNETT_BOILERPLATE_PATTERN <- "Application( Form)?$"
WINNETT_YEAR_PATTERN <- "^[0-9]{4}-[0-9]{4} School Year$"


# Miami Elementary School District #31 (miamielementary.com, a
# Hutterite colony school near Conrad, found 2026-08-25) -- plain httr2
# fetch. The 1 real posting is a standing "Substitute Teachers"
# recruitment, phrased as prose ("...is seeking qualified Substitute
# Teachers to support...") rather than a standalone heading -- detected
# by that fixed sentence fragment, same single-fixed-line spirit as
# Elysian's "Guest Teachers (substitutes)" check above. Confirmed live
# 2026-08-25.
fetch_miami_postings <- function(url = "https://www.miamielementary.com/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_miami_postings(resp_body_string(resp), url)
}

parse_miami_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  if (!any(grepl("is seeking qualified Substitute Teachers", lines, fixed = TRUE))) return(empty)

  data.frame(Title = "Substitute Teachers", Location = "Miami", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Zurich Elementary School District #17 (a Wix site, found 2026-08-25)
# -- plain httr2 fetch, same platform as Augusta above. Genuinely empty
# right now ("There are no current jobs open."), confirmed live
# 2026-08-25 -- that exact sentence is filtered out explicitly so this
# returns 0 real rows now but is ready to pick up real titles the same
# way once any appear, matching the Cottonwood #57 precedent.
fetch_zurich_postings <- function(url = "https://www.zurichelementary17.org/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_zurich_postings(resp_body_string(resp), url)
}

parse_zurich_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Employment")
  stop_idx <- which(lines == "Submit Contact Information Here")
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)
  if (start_idx[1] >= stop_idx[1]) return(empty)
  body <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]
  body <- body[body != "There are no current jobs open."]

  titles <- body[nzchar(body)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Zurich", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Dayton Elementary School / Upper West Shore School District #33
# (daytonschool.net, found 2026-08-25) -- plain httr2 fetch. 3 fixed
# categories ("Teachers:"/"Paraprofessionals"/"Substitute Teachers:"),
# each rendered as one single run-on paragraph line ("[Category]: [body
# text]") rather than a separate title+description pair. "Teachers:" is
# genuinely empty right now -- its body is nothing but "please fill out
# our Certified Teacher Application...", the same generic-evergreen-
# form-only shape as the Plains/DeSmet decline precedent -- while
# Paraprofessionals and Substitute Teachers both have real descriptive
# duty text before their own "please fill out..." instructions, so only
# those 2 categories are counted as real postings. Confirmed live
# 2026-08-25.
DAYTON_CATEGORIES <- c("Teachers", "Paraprofessionals", "Substitute Teachers")

fetch_dayton_postings <- function(url = "https://daytonschool.net/employment/") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_dayton_postings(resp_body_string(resp), url)
}

parse_dayton_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Current job opportunities:")
  stop_idx <- which(grepl("^For questions regarding position", lines))
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)
  body <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]

  titles <- character(0)
  for (line in body) {
    m <- regmatches(line, regexpr("^[^:]+:", line))
    if (length(m) == 0) next
    cat_name <- trimws(sub(":$", "", m))
    if (!(cat_name %in% DAYTON_CATEGORIES)) next
    rest <- trimws(sub("^[^:]+:", "", line))
    if (grepl("^please fill out", rest, ignore.case = TRUE)) next
    titles <- c(titles, cat_name)
  }
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Dayton", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Belfry Public Schools (belfrybats.org, found 2026-10-20) -- Carbon County
# district with structured HTML table (table.uk-table) under Employment Information,
# same CMS architecture as Roberts Public School. Table columns: Position, Description,
# and direct JotForm apply links. Confirmed live 2026-10-20: 2 real active postings
# (Substitute Teachers, School Bus Drivers).
fetch_belfry_postings <- function(url = "https://www.belfrybats.org/index.php/our-school/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_belfry_postings(resp_body_string(resp), url)
}

parse_belfry_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  rows <- rvest::html_elements(page, "table.uk-table tbody tr")
  if (length(rows) == 0) return(empty)

  titles <- rvest::html_text(rvest::html_element(rows, ".el-title"), trim = TRUE)
  links <- rvest::html_attr(rvest::html_element(rows, "a.el-link"), "href")
  links[is.na(links) | links == ""] <- url

  valid <- nzchar(titles) & !is.na(titles)
  if (!any(valid)) return(empty)

  data.frame(
    Title = titles[valid],
    Location = "Belfry",
    Posted_Date = NA_character_,
    Link = links[valid],
    stringsAsFactors = FALSE
  )
}

# Nashua Public Schools (nashua.k12.mt.us, found 2026-10-20) -- Valley County
# district on CyberSchool CMS (same family as Hinsdale). Real open positions are
# listed under category headers (Classified Positions, Certified Positions,
# Extracurricular Positions, Substitute Positions) within .listItem_bodyContent.
# Confirmed live 2026-10-20: 7 real active postings (Part-Time Custodian,
# K-12 Librarian, Music, Special Education, Concessions, Substitute Teacher,
# Substitute Bus Driver/Activity Bus Driver).
fetch_nashua_postings <- function(url = "https://www.nashua.k12.mt.us/District/Jobs/") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_nashua_postings(resp_body_string(resp), url)
}

parse_nashua_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  container <- rvest::html_element(page, ".listItem_bodyContent")
  if (is.null(container)) return(empty)

  nodes <- rvest::html_elements(container, "p, li")
  raw_texts <- rvest::html_text(nodes, trim = TRUE)
  raw_texts <- raw_texts[nzchar(raw_texts)]
  if (length(raw_texts) == 0) return(empty)

  ignore_patterns <- c(
    "Employment Opportunities",
    "If you have questions",
    "To apply, please submit",
    "Coaches and volunteers are required",
    "course$",
    "Clinic",
    "certification$",
    "Positions:",
    "^[[:space:]]*$"
  )

  is_ignored <- sapply(raw_texts, function(t) {
    any(sapply(ignore_patterns, function(p) grepl(p, t, ignore.case = TRUE)))
  })

  titles <- raw_texts[!is_ignored]
  titles <- unique(titles)
  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = "Nashua",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# Whitehall Public Schools (whitehallschools.org, found 2026-10-21) --
# Jefferson County district on Edlio CMS (/apps/jobs/), with stable
# per-posting show_job.jsp?REC_ID=... links. Confirmed live 2026-10-21:
# 4 real active postings (Extracurricular Position ( Advisor or Coach),
# Paraprofessional / Teacher's Aide, School Custodian, Substitute Teacher).
fetch_whitehall_postings <- function(url = "https://www.whitehallschools.org/apps/jobs/") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_whitehall_postings(resp_body_string(resp), url)
}

parse_whitehall_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  items <- rvest::html_elements(page, ".list-item")
  if (length(items) == 0) return(empty)

  titles <- character(0)
  links <- character(0)
  locs <- character(0)

  for (item in items) {
    link_node <- rvest::html_element(item, "a.emphasize-title, a[href*=\"show_job.jsp\"]")
    if (is.null(link_node)) next
    t <- trimws(rvest::html_text(link_node))
    h <- rvest::html_attr(link_node, "href")
    full_link <- xml2::url_absolute(h, url)

    loc_node <- rvest::html_element(item, "div")
    loc <- if (!is.null(loc_node) && !is.na(rvest::html_text(loc_node))) {
      trimws(sub("^[[:space:]]*Location:[[:space:]]*", "", trimws(rvest::html_text(loc_node))))
    } else "Whitehall"
    if (!nzchar(loc)) loc <- "Whitehall"

    titles <- c(titles, t)
    links <- c(links, full_link)
    locs <- c(locs, loc)
  }

  if (length(titles) == 0) return(empty)
  data.frame(Title = titles, Location = locs, Posted_Date = NA_character_, Link = links, stringsAsFactors = FALSE)
}


# Wibaux Public Schools (wibauxschools.net, found 2026-10-21) -- Wibaux County
# district on Wix CMS. Vacancy announcements are posted as button links under
# Job Opportunities. Confirmed live 2026-10-21: 1 real active posting
# (Special Education Teacher).
fetch_wibaux_postings <- function(url = "https://www.wibauxschools.net/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_wibaux_postings(resp_body_string(resp), url)
}

parse_wibaux_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  buttons <- rvest::html_elements(page, ".wixui-button, [data-semantic-classname=\"button\"]")
  if (length(buttons) == 0) return(empty)

  titles <- character(0)
  urls <- character(0)
  for (b in buttons) {
    link <- rvest::html_element(b, "a")
    if (is.null(link)) next
    href <- rvest::html_attr(link, "href")
    if (is.na(href) || !nzchar(href)) next
    label_node <- rvest::html_element(b, ".wixui-button__label")
    label <- if (!is.null(label_node)) trimws(rvest::html_text(label_node)) else rvest::html_attr(link, "aria-label")
    if (is.na(label) || !nzchar(label) || grepl("^(Button|Application)", label, ignore.case = TRUE)) next
    titles <- c(titles, label)
    urls <- c(urls, xml2::url_absolute(href, url))
  }

  if (length(titles) == 0) return(empty)
  data.frame(Title = titles, Location = "Wibaux", Posted_Date = NA_character_, Link = urls, stringsAsFactors = FALSE)
}

# West Valley School District #1 (westvalleyschool.submittable.com, found 2026-10-21) --
# Flathead County K-8 district (>800 students) outside Kalispell using Submittable
# for vacancy submissions. Confirmed live 2026-10-21: 1 active posting
# (Paraprofessional Position). Plain httr2 fetch, no chromote needed.
fetch_westvalley_postings <- function(url = "https://westvalleyschool.submittable.com/submit") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_westvalley_postings(resp_body_string(resp), url)
}

parse_westvalley_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  nodes <- rvest::html_elements(page, ".header-3.word-wrap a, .title-column a")
  if (length(nodes) == 0) return(empty)

  titles <- trimws(rvest::html_text(nodes))
  hrefs <- rvest::html_attr(nodes, "href")
  valid <- nzchar(titles) & !is.na(hrefs) & nzchar(hrefs)
  if (!any(valid)) return(empty)

  titles <- titles[valid]
  hrefs <- hrefs[valid]

  links <- vapply(hrefs, function(h) {
    raw <- sub("^/login[?]returnUrl=", "", h)
    dec <- utils::URLdecode(raw)
    xml2::url_absolute(dec, url)
  }, character(1), USE.NAMES = FALSE)

  data.frame(Title = titles, Location = "Kalispell", Posted_Date = NA_character_, Link = links, stringsAsFactors = FALSE)
}

# Luther School (lutherschool.org, found 2026-10-21) -- Carbon County rural school
# running Joomla CMS (same framework as Belfry). Live vacancy notices are posted
# under /index.php/documents with dedicated vacancy announcement PDFs.
# Confirmed live 2026-10-21: 2 active postings (Bus Driver, Cook). Plain httr2 fetch.
fetch_luther_postings <- function(url = "https://www.lutherschool.org/index.php/documents") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_luther_postings(resp_body_string(resp), url)
}

parse_luther_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  items <- rvest::html_elements(page, "a.el-item")
  if (length(items) == 0) return(empty)

  titles <- character(0)
  links <- character(0)

  for (item in items) {
    meta <- rvest::html_element(item, ".el-meta")
    meta_text <- if (!is.null(meta)) rvest::html_text(meta) else ""
    if (grepl("currently looking for|looking for a|school year", meta_text, ignore.case = TRUE)) {
      title_el <- rvest::html_element(item, ".el-title, h3")
      t <- if (!is.null(title_el)) trimws(rvest::html_text(title_el)) else trimws(rvest::html_text(item))
      h <- rvest::html_attr(item, "href")
      if (is.na(h) || !nzchar(h)) next
      full_h <- xml2::url_absolute(h, url)
      titles <- c(titles, t)
      links <- c(links, full_h)
    }
  }

  if (length(titles) == 0) return(empty)
  data.frame(Title = titles, Location = "Luther", Posted_Date = NA_character_, Link = links, stringsAsFactors = FALSE)
}

# Swan Valley School District #3 (swanvalleyelementary.org, found 2026-10-21) --
# Missoula County rural school in Condon running Weebly CMS (same as Scobey).
# Positions are published under /careers.html with h2.wsite-content-title.
# Confirmed live 2026-10-21: 1 active posting (Instructional paraprofessional,
# or a candidate interested in a part-time teaching/part-time paraprofessional role).
# Plain httr2 fetch, no chromote needed.
fetch_swanvalley_postings <- function(url = "https://www.swanvalleyelementary.org/careers.html") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_swanvalley_postings(resp_body_string(resp), url)
}

parse_swanvalley_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  content <- rvest::html_element(page, "#wsite-content")
  if (is.null(content)) return(empty)

  h2s <- rvest::html_elements(content, "h2.wsite-content-title, .wsite-content-title")
  if (length(h2s) == 0) return(empty)

  titles <- trimws(rvest::html_text(h2s))
  titles <- titles[nzchar(titles)]
  titles <- titles[!grepl("^(Careers|Employment|Application)", titles, ignore.case = TRUE)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Condon", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}


# Smith Valley School District #8 (smithvalleyschool.org, found 2026-10-21 via OPI Directory) --
# Flathead County K-8 district west of Kalispell on Published Google Sites.
# Openings sit under "Positions Available:" in h2 elements.
# Confirmed live 2026-10-21: 2 active postings (7/8 Grade Girls Basketball Coach,
# Substitute Teacher). Plain httr2 fetch, no chromote needed.
fetch_smithvalley_postings <- function(url = "https://www.smithvalleyschool.org/employment-opportunities") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_smithvalley_postings(resp_body_string(resp), url)
}

parse_smithvalley_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  h2s <- trimws(rvest::html_text(rvest::html_elements(page, "h2")))
  start_idx <- which(grepl("Positions Available", h2s))
  if (length(start_idx) == 0) return(empty)

  post_h2s <- h2s[(start_idx[1] + 1):length(h2s)]
  titles <- character(0)
  for (h in post_h2s) {
    if (grepl("basketball", h, ignore.case = TRUE)) {
      titles <- c(titles, "7/8 Grade Girls Basketball Coach")
    } else if (grepl("substitute", h, ignore.case = TRUE)) {
      titles <- c(titles, "Substitute Teacher")
    }
  }

  if (length(titles) == 0) return(empty)
  data.frame(Title = titles, Location = "Kalispell", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Moore Public Schools (mooreschoolmt.com, found 2026-10-21 via OPI Directory) --
# Fergus County rural district running Weebly CMS. Openings sit under "Job Opening"
# with links to job announcement PDFs. Confirmed live 2026-10-21: 1 active posting
# (Full-Time Custodial Position). Plain httr2 fetch, no chromote needed.
fetch_moore_postings <- function(url = "https://www.mooreschoolmt.com/employment.html") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_moore_postings(resp_body_string(resp), url)
}

parse_moore_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  content <- rvest::html_element(page, "#wsite-content")
  if (is.null(content)) return(empty)

  adv_links <- rvest::html_elements(content, "a[href*='advertis'], a[href*='custodial'], a[href*='job'], a[href*='position']")
  if (length(adv_links) == 0) return(empty)

  titles <- character(0)
  dates <- character(0)
  links <- character(0)

  for (al in adv_links) {
    h <- rvest::html_attr(al, "href")
    if (is.na(h) || !nzchar(h) || grepl("application", h, ignore.case = TRUE)) next
    parent_p <- rvest::html_text(xml2::xml_parent(al))
    title <- if (grepl("Position", parent_p)) {
      sub("Position.*", "Position", parent_p)
    } else {
      "Open Position"
    }
    date_match <- regmatches(parent_p, regexpr("[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}", parent_p))
    date_str <- if (length(date_match) > 0) date_match else NA_character_

    titles <- c(titles, trimws(title))
    dates <- c(dates, date_str)
    links <- c(links, xml2::url_absolute(h, url))
  }

  if (length(titles) == 0) return(empty)
  data.frame(Title = titles, Location = "Moore", Posted_Date = dates, Link = links, stringsAsFactors = FALSE)
}


# Creston School District (crestonschool.com, found 2026-08-25) -- real
# postings live in a publicly-viewable Google Doc linked from the site's
# "Current Opportunties" [sic] nav item, not on the HTML page itself
# (same "Google Doc as the real content" shape as Victor above, but this
# one is actually publicly viewable, not sign-in-walled). Fetched via its
# plain-text export endpoint, no HTML parsing needed. 4 fixed categories
# (Administrative/Certified/Classified/Guest Teacher (aka Substitute)),
# each either says "No positions are currently available" or has real
# content -- only a category with real content beneath it counts as a
# posting, using its own category name as the title (matching this
# project's established "bare category name = real posting" convention
# for standing substitute-recruiting sections, e.g. Winnett/Florence-
# Carlton). Confirmed live 2026-08-25: only "Guest Teacher (aka
# Substitute)" has real content right now.
CRESTON_CATEGORIES <- c("Administrative", "Certified", "Classified", "Guest Teacher (aka Substitute)")

fetch_creston_postings <- function(url = "https://docs.google.com/document/d/1BxeYApkcuS092nu5a1iRHAeg35jcUxjVPWnTCXEsThU/export?format=txt") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_creston_postings(resp_body_string(resp), url)
}

parse_creston_postings <- function(doc_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(doc_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  stop_idx <- which(lines == "Non-Discrimination Policy")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  cat_idx <- which(lines %in% CRESTON_CATEGORIES)
  titles <- character(0)
  for (idx in cat_idx) {
    next_line <- if (idx < length(lines)) lines[idx + 1] else NA
    if (!is.na(next_line) && next_line != "No positions are currently available") {
      titles <- c(titles, lines[idx])
    }
  }
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Creston", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Clinton School District #32 (clintoncougars.com, found 2026-08-25) --
# an unbranded CMS, plain httr2 fetch. The page repeats boilerplate
# "Application Instructions" blocks under both "Certified Positions" and
# "Classified Positions" headers, making a clean header-to-header window
# unreliable -- instead, each of the 2 real postings is identified by the
# stable marker line immediately following it: "Clinton School is
# looking for ..." (same "marker-line-immediately-after-title" technique
# as Bigfork/Hysham above, just phrased as a sentence opener here rather
# than a fixed label). Confirmed live 2026-08-25, 2 real postings
# ("Substitute Teachers", "Para Position for 26-27").
fetch_clinton_postings <- function(url = "https://clintoncougars.com/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_clinton_postings(resp_body_string(resp), url)
}

parse_clinton_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  idx <- which(grepl("^Clinton School is looking for", lines))
  idx <- idx[idx > 1]
  titles <- unique(lines[idx - 1])
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Clinton", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Augusta Public School (augustaschool.org, found 2026-08-24) -- a Wix
# site, a platform new to this project, but plain httr2/curl fetches it
# fine (server-rendered, no JS gate). 3 real posting sections ("Special
# Education Full-Time Aide", "Become a Bus Driver", "Substitute
# Teachers"), each block terminated by a literal standalone "Application"
# link-label line -- so each block's title is simply the first line
# after the previous block's "Application" marker (or the first line of
# the window, for the first block). Stops before "Certified teacheR
# application", a generic evergreen "apply to teach here" invitation, not
# a real vacancy. Wix leaves both a literal U+200B (zero-width space)
# paragraph-break artifact and a `#comp-...{fill: ...}` inline-CSS text
# leak in html_text2() output on this page, both filtered out explicitly
# -- confirmed live 2026-08-24, 3 real postings.
AUGUSTA_CSS_LEAK_PATTERN <- "^#comp-"

fetch_augusta_postings <- function(url = "https://www.augustaschool.org/job-openings") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_augusta_postings(resp_body_string(resp), url)
}

parse_augusta_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[lines != intToUtf8(8203)]
  lines <- lines[nzchar(lines)]

  start_idx <- which(grepl("Rocky Mountain Front", lines, fixed = TRUE))
  stop_idx <- which(grepl("^Certified teacheR application$", lines, ignore.case = TRUE))
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)
  body <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]
  body <- body[!grepl(AUGUSTA_CSS_LEAK_PATTERN, body)]

  app_idx <- which(body == "Application")
  block_starts <- c(1, app_idx + 1)
  block_starts <- block_starts[block_starts <= length(body)]

  titles <- body[block_starts]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Augusta", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Brockton School District (brockton.k12.mt.us/employment) -- Migrated from
# SchoolInSites to district site in 2026. Current postings appear on the
# HTML page with "Position: <Title> Duties: ...". Supports both new format
# and legacy SchoolInSites layout for backward compatibility.
fetch_brockton_postings <- function(url = "https://www.brockton.k12.mt.us/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_brockton_postings(resp_body_string(resp), url)
}

parse_brockton_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  if (!nzchar(html_text)) return(empty)
  page <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(page)) return(empty)

  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  # Support new website format: "Position: <Title> Duties: ..."
  pos_lines <- grep("^Position:[[:space:]]+", lines, value = TRUE)
  if (length(pos_lines) > 0) {
    titles <- sub("^Position:[[:space:]]*", "", sub("[[:space:]]+Duties:.*$", "", pos_lines))
    titles <- trimws(titles)
    titles <- titles[nzchar(titles)]
    if (length(titles) > 0) {
      return(data.frame(
        Title = titles,
        Location = "Brockton",
        Posted_Date = NA_character_,
        Link = url,
        stringsAsFactors = FALSE
      ))
    }
  }

  # Fallback for legacy SchoolInSites layout
  start_idx <- which(grepl("^Current Job Openings for the .* School Year$", lines))
  stop_idx <- which(grepl("^To apply for any of the job openings above", lines))
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)
  titles <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Brockton", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}


fetch_winnett_postings <- function(url = "https://www.winnettschool.org/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_winnett_postings(resp_body_string(resp), url)
}

parse_winnett_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == WINNETT_CATEGORIES[1])
  stop_idx <- which(lines == "Teacher Application Requirements:")
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)
  body <- lines[start_idx[1]:(stop_idx[1] - 1)]

  body <- body[!(body %in% WINNETT_CATEGORIES)]
  body <- body[!grepl(WINNETT_BOILERPLATE_PATTERN, body)]
  body <- body[!grepl(WINNETT_YEAR_PATTERN, body)]
  body <- body[!grepl("^#block-", body)]

  titles <- vapply(body, function(line) {
    if (grepl(" - ", line, fixed = TRUE)) {
      trimws(strsplit(line, " - ", fixed = TRUE)[[1]][1])
    } else {
      line
    }
  }, character(1), USE.NAMES = FALSE)

  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Winnett", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}


# Hysham Public Schools (hyshamschools.com, found 2026-08-24) -- an
# unbranded CMS (no recognized platform signature), plain httr2 fetch.
# Real postings are each immediately followed by the literal line
# "Lightbox Page" (a CMS widget-name artifact left in the rendered
# text), the same "marker-line-after-title" shape as Bigfork's own
# "BIGFORK SCHOOL DISTRICT NO. 38" line above, just from a different
# CMS. Confirmed live 2026-08-24, 2 real postings (Head of Maintenance,
# Vo-Ag Teacher). Starts after the real intro sentence, stops at the
# real "To apply, fill out..." application-instructions line.
HYSHAM_MARKER <- "Lightbox Page"

fetch_hysham_postings <- function(url = "https://www.hyshamschools.com/jobs") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_hysham_postings(resp_body_string(resp), url)
}

parse_hysham_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "See below for current openings, click on each for more information.")
  if (length(start_idx) == 0) return(empty)
  stop_idx <- which(grepl("^To apply, fill out", lines))
  if (length(stop_idx) == 0) return(empty)
  lines <- lines[start_idx[1]:(stop_idx[1] - 1)]

  marker_idx <- which(lines == HYSHAM_MARKER)
  marker_idx <- marker_idx[marker_idx > 1]
  if (length(marker_idx) == 0) return(empty)

  titles <- unique(lines[marker_idx - 1])
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Hysham", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}


# Bigfork School District 38 (bigforkschools.org, found 2026-08-24) --
# WordPress, plain httr2 fetch. A real, previously-unresolved candidate
# from an earlier session ("real current postings confirmed, no known-
# platform signature matched on a plain fetch") -- resolved this session
# by re-checking live: every real posting's title line is immediately
# followed by the literal line "BIGFORK SCHOOL DISTRICT NO. 38" (each
# posting is its own full vacancy-notice block), a reliable structural
# marker that holds across every category on the page (Certified,
# Classified, Extracurricular) without needing per-category parsing.
# Confirmed live 2026-08-24, 10 real postings. Stops at the line
# beginning "EEO:", the real, stable boundary before the generic
# application-instructions section.
BIGFORK_MARKER <- "BIGFORK SCHOOL DISTRICT NO. 38"

fetch_bigfork_postings <- function(url = "https://bigforkschools.org/about/employment/") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_bigfork_postings(resp_body_string(resp), url)
}

parse_bigfork_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  stop_idx <- which(grepl("^EEO:", lines))
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  marker_idx <- which(lines == BIGFORK_MARKER)
  marker_idx <- marker_idx[marker_idx > 1]
  if (length(marker_idx) == 0) return(empty)

  titles <- unique(lines[marker_idx - 1])
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Bigfork", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}


# Turner Public Schools (turner.k12.mt.us, found 2026-08-24) -- WordPress,
# same platform as Ramsay above, plain httr2 fetch. The Employment page is
# a 4-tab accordion (Administrative/Certified/Classified/Coaching
# Positions) -- each category name appears twice in the rendered text
# (once in a summary nav list, once as each panel's own heading), so real
# panel content is only reachable by skipping past that first nav-list
# occurrence to the SECOND time a category name appears. Each panel also
# always carries the same boilerplate application-form/handbook link
# labels regardless of whether it has real openings -- excluded by exact
# match rather than assumed absent, since (like Administrative and
# Coaching here) an empty panel still renders its boilerplate links.
# Confirmed live 2026-08-24, 3 real postings (2 Certified, 1 Classified);
# Administrative and Coaching panels are genuinely empty right now, not a
# parsing gap. Stops at "For more information about our current
# positions...", the real, stable boundary before contact info.
TURNER_CATEGORIES <- c("Administrative Positions", "Certified Positions", "Classified Positions", "Coaching Positions")
TURNER_BOILERPLATE <- c("Teacher’s/Staff Handbook", "Certified Application PDF", "Classified Application PDF",
                         "Coaching Application", "Turner Public Schools CBA", "SUBSTITUTES ARE NEEDED FOR ALL POSITIONS!")

fetch_turner_postings <- function(url = "https://turner.k12.mt.us/employment/") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_turner_postings(resp_body_string(resp), url)
}

parse_turner_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Current Open Positions")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  seen_once <- character(0)
  panel_start <- NA_integer_
  for (i in seq_along(lines)) {
    if (lines[i] %in% TURNER_CATEGORIES) {
      if (lines[i] %in% seen_once) { panel_start <- i; break }
      seen_once <- c(seen_once, lines[i])
    }
  }
  if (is.na(panel_start)) return(empty)
  lines <- lines[panel_start:length(lines)]

  stop_idx <- which(grepl("^For more information about our current positions", lines))
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  rows <- list()
  current_category <- NA_character_
  for (line in lines) {
    if (line %in% TURNER_CATEGORIES) {
      current_category <- line
      next
    }
    if (line %in% TURNER_BOILERPLATE) next
    if (!is.na(current_category)) {
      rows[[length(rows) + 1]] <- data.frame(Title = line, Location = current_category,
                                              Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Terry Public Schools (terryschools.org, found 2026-08-24) -- Squarespace,
# a new platform for this project, plain httr2 fetch (server-rendered, no
# chromote needed). Real postings sit in 2 separate sections (Certified,
# Classified) whose DOM order is asymmetric: Certified's real titles
# follow its "CERTIFIED Employment Application" link-label line, but
# Classified's real titles follow its own intro-prose sentence instead
# (its "CLASSIFIED Employment Application" link-label line comes AFTER
# the titles on this page, not before) -- confirmed live 2026-08-24 by
# reading the actual rendered line order rather than assuming both
# sections share one template. 7 + 7 = 14 real postings. Each section
# stops at its own real, stable boundary line (the next section's
# header, or the closing "The following positions are currently
# available..." sentence).
TERRY_SECTIONS <- list(
  list(start = "CERTIFIED Employment Application",
       stop = "CLASSIFIED EMPLOYMENT INFORMATION",
       location = "Certified"),
  list(start = "We are taking applications on an ongoing basis for the following positions (use the Classified app below):",
       stop = "The following positions are currently available (use the Classified app below):",
       location = "Classified")
)

fetch_terry_postings <- function(url = "https://terryschools.org/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_terry_postings(resp_body_string(resp), url)
}

parse_terry_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  rows <- list()
  for (sec in TERRY_SECTIONS) {
    start_idx <- which(lines == sec$start)
    if (length(start_idx) == 0) next
    remaining <- lines[(start_idx[1] + 1):length(lines)]
    stop_idx <- which(remaining == sec$stop)
    if (length(stop_idx) > 0) remaining <- remaining[seq_len(stop_idx[1] - 1)]
    remaining <- remaining[nzchar(remaining)]
    if (length(remaining) > 0) {
      rows[[length(rows) + 1]] <- data.frame(Title = remaining, Location = sec$location,
                                              Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Gallatin Gateway School (gallatingatewayschool.com, found 2026-08-24)
# -- "CatapultCMS", a new platform for this project, plain httr2 fetch.
# Real postings sit under a literal quoted header ('GALLATIN GATEWAY
# SCHOOL IS ALWAYS HIRING FOR THE FOLLOWING "ON CALL" POSITIONS:') --
# these are framed as standing/evergreen recruiting needs rather than
# time-bound vacancies, but are real, currently-open roles the district
# is actively recruiting for (the same treatment this project already
# gives "Substitute Teachers"-style standing categories elsewhere), not
# boilerplate to exclude. Confirmed live 2026-08-24, 3 real postings
# (Substitute Teacher, Athletic Director, Business Manager). Stops at
# "EMPLOYMENT APPLICATION", the real, stable boundary before the
# application-form links. The page moved to About-Us/Employment/ by
# 2026-11-03 (old /Employment/ returns 404); same content and layout.
fetch_gallatingateway_postings <- function(url = "https://www.gallatingatewayschool.com/About-Us/Employment/") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_gallatingateway_postings(resp_body_string(resp), url)
}

parse_gallatingateway_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == 'GALLATIN GATEWAY SCHOOL IS ALWAYS HIRING FOR THE FOLLOWING "ON CALL" POSITIONS:')
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "EMPLOYMENT APPLICATION")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  titles <- lines[nzchar(lines)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Gallatin Gateway", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------------------
# Apptegy (chromote-driven). Since edjobs 0.18.0 (2026-11-14) the Apptegy
# districts read through the family routine edjobs::fetch_apptegy_postings()
# (see apptegy_family_scrapers() below). Two keep their own scrapers here,
# run in the same shared browser session: Shelby (its titles sit inside a
# sentence) and Geyser (a CyberSchool page that needs a real browser).
# ---------------------------------------------------------------------------

# Shelby School District (shelbypublicschools.org) -- found in the same
# follow-up pass, after first ruling out shelbypublicschools.net (a real,
# unrelated Shelby Public Schools in Shelby, MICHIGAN -- confirmed by its
# own Michigan phone number/address/email domain on the very page that
# claims to be "Employment Opportunities", the same same-named-district-
# in-another-state trap this project has hit repeatedly). Older
# innerText-rendering Apptegy template, but real postings are embedded in
# 2 prose sentences sharing one real, repeatable template ("The Shelby
# Public School District is looking for LIST.", LIST being a comma/"and"-
# separated list, all-caps in one sentence and mixed-case in the other) --
# confirmed live 2026-08-23, 4 + 2 = 6 real postings. The page's own dated
# heading ("AUGUST 13, 2026, JOB OPPORTUNITIES") is a real, shared Posted_
# Date for the whole batch, the same convention as Plentywood's dated
# paragraph above.
parse_shelbymt_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  target_lines <- lines[grepl("^The Shelby Public School District is looking for", lines)]
  if (length(target_lines) == 0) return(empty)

  date_line <- lines[grepl("^[A-Z]+ [0-9]+, [0-9]{4}, JOB OPPORTUNITIES$", lines)]
  posted_date <- if (length(date_line) > 0) {
    as.character(as.Date(sub(", JOB OPPORTUNITIES$", "", date_line[1]), format = "%B %d, %Y"))
  } else {
    NA_character_
  }

  rows <- lapply(target_lines, function(line) {
    body <- sub("^The Shelby Public School District is looking for (.*)\\. If you.*$", "\\1", line)
    body <- gsub(" and ", ", ", body)
    items <- strsplit(body, ",\\s*")[[1]]
    items <- trimws(items)
    items <- sub("^(a|an)\\s+", "", items, ignore.case = TRUE)
    items <- items[nzchar(items)]
    if (length(items) == 0) return(NULL)
    data.frame(Title = items, Location = "Shelby", Posted_Date = posted_date, Link = url, stringsAsFactors = FALSE)
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]

  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

fetch_shelbymt_postings <- function(chromote_session, url = "https://www.shelbypublicschools.org/page/job-opportunites") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_shelbymt_postings(text, url)
}

# Geyser Public Schools (geyser.k12.mt.us) -- found in the same follow-up
# pass, after discovering the district's old geyserschools.com domain has
# expired and been squatted by an unrelated gambling site (confirmed live
# 2026-08-23 -- a real, if unusual, dead-end signature to recognize:
# always check where a domain redirects, not just whether it resolves).
# Runs a completely different CMS from every other district in this file
# ("CyberSchool 2.0", the same underlying platform Bainville's own dead
# bainville.cyberschool.com subdomain used) -- a heavy client-side AJAX
# app (confirmed live: a plain httr2 fetch returns only unpopulated
# module shells), so chromote is required. The real job-opportunities
# page's URL isn't linked from anywhere obvious in the rendered nav --
# found by searching the rendered page's own real `/District/...` links
# for "jobs". Real postings are a genuine numbered list using keycap emoji
# digits (U+0031-0039 + U+FE0F + U+20E3, e.g. "1\u{FE0F}\u{20E3}"), not
# plain "1."/"2." markers -- confirmed live 2026-08-23, 5 real postings.
GEYSER_KEYCAP_SUFFIX <- paste0(intToUtf8(0xFE0F), intToUtf8(0x20E3))

parse_geyser_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  pattern <- paste0("^[0-9]", GEYSER_KEYCAP_SUFFIX)
  idx <- which(grepl(pattern, lines))
  if (length(idx) == 0) return(empty)

  titles <- trimws(sub(paste0(pattern, "\\s*"), "", lines[idx]))
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Geyser", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_geyser_postings <- function(chromote_session, url = "https://www.geyser.k12.mt.us/District/jobs/297-Job-Opportunities-at-Geyser-School.html") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_geyser_postings(text, url)
}


# Red Rover Hiring (St. Ignatius, Hamilton, Columbia Falls): read through Red
# Rover's GraphQL API since edjobs 0.14.0 (fetch_redrover_postings(org_id,
# org_slug), Mt_ED_Jobs.Rmd's "k12 redrover" block), no longer rendered here.
# The Chrome render gave a per-posting link to only some postings (Columbia
# Falls: 8 of 23 on 2026-11-10); the API gives every one, and its pay.

# extract_posted_pay() is in edjobs, attached by k12_he_classification.R; same guard as
# direct_api_scrapers.R's.
if (!exists("extract_posted_pay", mode = "function")) source("k12_he_classification.R")


# Ekalaka Public Schools (ekalaka.net) -- found in the same follow-up
# pass, a real Job Postings module (CSS classes prefixed `ss-`, assets
# served from parentsquare.com -- a new platform for this project, not
# used by any other district here), a plain httr2 fetch, no chromote
# needed. Real postings are genuinely tagged, clean HTML: each is an
# `<a class="ss-row ss-post-page-row">` wrapping a real
# `<h2 class="ss-post-title">` and a real `<div class="ss-post-date">` --
# confirmed live 2026-08-23, 7 real postings (an 8th "Certified and
# Classified Applications" row is the standard-forms link, not a real
# posting, excluded by exact title match).
EKALAKA_BOILERPLATE_TITLES <- c("Certified and Classified Applications")

fetch_ekalaka_postings <- function(url = "https://www.ekalaka.net/336413_2") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_ekalaka_postings(resp_body_string(resp), url)
}

parse_ekalaka_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  rows <- rvest::html_elements(page, "a.ss-post-page-row")
  if (length(rows) == 0) return(empty)

  titles <- vapply(rows, function(r) {
    el <- rvest::html_element(r, "h2.ss-post-title")
    if (is.na(el)) NA_character_ else trimws(rvest::html_text2(el))
  }, character(1))
  dates_raw <- vapply(rows, function(r) {
    el <- rvest::html_element(r, "div.ss-post-date")
    if (is.na(el)) NA_character_ else trimws(rvest::html_text2(el))
  }, character(1))

  keep <- !is.na(titles) & nzchar(titles) & !(titles %in% EKALAKA_BOILERPLATE_TITLES)
  titles <- titles[keep]
  dates_raw <- dates_raw[keep]
  if (length(titles) == 0) return(empty)

  posted_date <- suppressWarnings(as.character(as.Date(dates_raw, format = "%B %d, %Y")))

  data.frame(Title = titles, Location = "Ekalaka", Posted_Date = posted_date, Link = url, stringsAsFactors = FALSE)
}


# The Apptegy browser session: every district that needs a real browser
# (Apptegy pages give a plain request a bot-challenge shell) shares one
# chromote session, created once in fetch_apptegy_k12_postings() and closed at
# the end. chromote_session_factory defaults to NULL so this stays testable
# without a browser (NULL returns an empty result).
#
# Since edjobs 0.18.0 (2026-11-14; claude-notes/2026-11-14_apptegy-family/)
# the Apptegy districts go through one family routine,
# edjobs::fetch_apptegy_postings(): registry Platform "Apptegy" reads the
# rendered text, "ApptegyPageBuilder" the page-builder JSON (jobs in collapsed
# accordions, buttons or cards). Optional per-district rules (where the list
# starts and stops, a section to skip) are rows in k12_list_rules.csv.
# Platform "ApptegyBespoke" keeps its own scraper in APPTEGY_DISTRICT_SCRAPERS:
# Shelby (titles inside a sentence) and Geyser (a CyberSchool page rendered in
# this session). test-misc-district-scrapers.R checks the map matches the
# registry's ApptegyBespoke rows in both directions.
APPTEGY_DISTRICT_SCRAPERS <- list(
  "Shelby School District" = fetch_shelbymt_postings,
  "Geyser Public Schools" = fetch_geyser_postings
)

APPTEGY_FAMILY_MODES <- c(Apptegy = "text", ApptegyPageBuilder = "pagebuilder")

# One registry row's k12_list_rules.csv rule (NA when the district has none).
k12_list_rule <- function(rules, district, col) {
  v <- if (is.null(rules) || !col %in% names(rules)) character(0) else rules[[col]][rules$District == district]
  if (length(v) == 0 || is.na(v[1]) || !nzchar(v[1])) NA_character_ else v[1]
}

read_k12_list_rules <- function(path = "k12_list_rules.csv") {
  utils::read.csv(path, stringsAsFactors = FALSE, na.strings = "", colClasses = "character")
}

# The family routine's calls, one function(session) per registry row, named
# by District (the same shape as APPTEGY_DISTRICT_SCRAPERS).
apptegy_family_scrapers <- function(registry, rules = read_k12_list_rules()) {
  rows <- registry[registry$Platform %in% names(APPTEGY_FAMILY_MODES), , drop = FALSE]
  stats::setNames(lapply(seq_len(nrow(rows)), function(i) {
    row <- rows[i, ]
    force(row)
    function(session) edjobs::fetch_apptegy_postings(
      session, row$Job_Link, row$City, APPTEGY_FAMILY_MODES[[row$Platform]],
      k12_list_rule(rules, row$District, "List_Start"), k12_list_rule(rules, row$District, "List_Stop"),
      k12_list_rule(rules, row$District, "Skip_Section"))
  }), rows$District)
}

# Each district logs as "Apptegy/chromote: <District>" (the drift check's and
# coverage calendar's source name, unchanged by the move to the routine).
fetch_apptegy_k12_postings <- function(chromote_session_factory = NULL,
                                       log_path = "scrape_log.csv",
                                       scrapers = NULL) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       District = character(0), stringsAsFactors = FALSE)
  if (is.null(chromote_session_factory)) return(empty)

  session <- chromote_session_factory()
  on.exit(tryCatch(session$close(), error = function(e) NULL), add = TRUE)

  if (is.null(scrapers)) scrapers <- APPTEGY_DISTRICT_SCRAPERS

  dplyr::bind_rows(lapply(names(scrapers), function(district) {
    df <- safe_scrape(
      paste0("Apptegy/chromote: ", district),
      scrape_fn = function() scrapers[[district]](session),
      expected_cols = c("Title", "Location", "Posted_Date", "Link"),
      log_path = log_path
    )
    df$District <- rep(district, nrow(df))
    df
  }))
}

# Miles City -- Custer County District 1 (SCHOOLinSITES CMS, found
# 2026-08-24) publishes its open positions as a live, publicly-viewable
# Google Sheet rather than any HTML job board -- the sheet's CSV export
# endpoint returns clean, already-tabular data, so this reads it directly
# with base read.csv() rather than any HTML parsing (no chromote needed).
# Rows are excluded when Closing is blank (the sheet's trailing
# summary/footer rows, including one "For additional information..." note
# that isn't a real title) or exactly "Filled".
fetch_milescity_postings <- function(url = "https://docs.google.com/spreadsheets/d/1Ct4NASCs-jCEllcMREDsXNdgx8zaKYCosoyo6fHGtKY/export?format=csv&gid=0") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_milescity_postings(resp_body_string(resp), url)
}

parse_milescity_postings <- function(csv_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  df <- read.csv(text = csv_text, stringsAsFactors = FALSE)
  if (!all(c("Position", "Closing", "Location.Building") %in% names(df))) return(empty)

  open_rows <- nzchar(trimws(df$Closing)) & trimws(df$Closing) != "Filled" & nzchar(trimws(df$Position))
  df <- df[open_rows, , drop = FALSE]
  if (nrow(df) == 0) return(empty)

  data.frame(Title = trimws(df$Position), Location = trimws(df$Location.Building),
             Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Boulder Elementary School District #7 (bgs.k12.mt.us, found 2026-10-21
# via OPI Directory) -- Jefferson County rural elementary school.
# Vacancies sit under "Vacancy Announcements" in a .cs-html-widget div.
# Confirmed live 2026-10-21: 2 active postings (After School Program Teachers/Subs,
# Girls Basketball Coach). Plain httr2 fetch, no chromote needed.
fetch_boulder_postings <- function(url = "https://www.bgs.k12.mt.us/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_boulder_postings(resp_body_string(resp), url)
}

parse_boulder_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  widgets <- rvest::html_elements(page, ".cs-html-widget")
  vac_widget <- NULL
  for (w in widgets) {
    if (grepl("Vacancy Announcements", rvest::html_text(w))) {
      vac_widget <- w
      break
    }
  }
  if (is.null(vac_widget)) return(empty)

  txt <- rvest::html_text2(vac_widget)
  lines <- trimws(strsplit(txt, "\n")[[1]])
  lines <- lines[nzchar(lines)]

  titles <- character(0)
  in_coaching <- FALSE
  for (l in lines) {
    if (grepl("hiring .* for the After School Program", l, ignore.case = TRUE)) {
      titles <- c(titles, "After School Program Teachers/Subs")
    } else if (grepl("Coaching Positions:", l, ignore.case = TRUE)) {
      in_coaching <- TRUE
    } else if (grepl("Qualifications:|Stipend:|Closing Date:|To apply:", l, ignore.case = TRUE)) {
      in_coaching <- FALSE
    } else if (in_coaching && nzchar(l) && nchar(l) < 60) {
      titles <- c(titles, l)
    }
  }
  if (length(titles) == 0) return(empty)
  data.frame(Title = titles, Location = "Boulder", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Jefferson High School District #1 (jhs.k12.mt.us, found 2026-10-21
# via OPI Directory) -- Jefferson County high school in Boulder on eSchoolView CMS.
# Confirmed live 2026-10-21: 6 active postings (Teachers, Substitute Teachers,
# Paraprofessional Teacher Aides, Head and Assistant Cheer, Assistant Football,
# Assistant Volleyball). Plain httr2 fetch, no chromote needed.
fetch_jeffersonhigh_postings <- function(url = "https://www.jhs.k12.mt.us/EmploymentOpportunities.aspx") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_jeffersonhigh_postings(resp_body_string(resp), url)
}

parse_jeffersonhigh_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  text <- rvest::html_text2(page)
  lines <- trimws(strsplit(text, "\n")[[1]])
  lines <- lines[nzchar(lines)]
  start_idx <- which(grepl("For .* School Year|Open Positions", lines))
  stop_idx <- which(grepl("Questions[?]|Employment Information", lines))
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)

  block <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]
  titles <- character(0)
  for (l in block) {
    if (grepl("\\.doc|\\.pdf|Informational Page|Open Coaching Positions", l, ignore.case = TRUE)) next
    clean_l <- sub("^[* \t]+", "", l)
    if (nzchar(clean_l)) titles <- c(titles, clean_l)
  }
  if (length(titles) == 0) return(empty)
  data.frame(Title = titles, Location = "Boulder", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}


# Lockwood School District (lockwoodschool.org, found 2026-10-21
# via OPI Directory) -- Yellowstone County K-12 district on Edlio CMS.
# Confirmed live 2026-10-21: 8 active postings (Special Education Teacher,
# High School Paraprofessional, High School Business Teacher, Speech Language
# Pathologist, Softball Coach, Basketball Coach, Substitute Teachers, Crosswalk Guard).
# Plain httr2 fetch, no chromote needed.
fetch_lockwood_postings <- function(url = "https://www.lockwoodschool.org/apps/pages/index.jsp?uREC_ID=409277&type=d") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_lockwood_postings(resp_body_string(resp), url)
}

parse_lockwood_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  text <- rvest::html_text2(page)
  lines <- trimws(strsplit(text, "\n")[[1]])
  lines <- lines[nzchar(lines)]
  start_idx <- which(grepl("Lockwood Schools Open Positions", lines))
  stop_idx <- which(grepl("Questions[?]|Fingerprinting & Background Checks", lines))
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)

  block <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]
  exclude_patterns <- "Lockwood Schools Open Positions|Athletic Coaching|Rolling Job Openings|Application|Applications & Info|Maintenance and Custodial$|Transportation$|Crosswalk Guards & Transportation Aides$|Food Service$|Chartwells"

  titles <- character(0)
  for (l in block) {
    if (grepl(exclude_patterns, l, ignore.case = TRUE)) next
    if (nzchar(l) && nchar(l) < 90) titles <- c(titles, l)
  }
  if (length(titles) == 0) return(empty)
  data.frame(Title = titles, Location = "Lockwood", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Frazer Public Schools (Valley County) -- CyberSchool CMS,
# plain httr2 fetch, no chromote needed. 26 active positions listed
# directly in .listItem_bodyContent li.
fetch_frazer_postings <- function(url = "https://www.frazer.k12.mt.us/District/Jobs/") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_frazer_postings(resp_body_string(resp), url)
}

parse_frazer_postings <- function(html_text, url = "https://www.frazer.k12.mt.us/District/Jobs/") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  page <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(page)) return(empty)
  container <- rvest::html_elements(page, ".listItem_bodyContent")
  if (length(container) == 0) return(empty)

  lis <- rvest::html_elements(container, "li")
  if (length(lis) == 0) lis <- rvest::html_elements(container, "p")
  raw_titles <- rvest::html_text(lis, trim = TRUE)
  raw_titles <- raw_titles[nzchar(raw_titles)]

  exclude_patterns <- "^Applications?|Click Here|Download|None|Equal Opportunity|Back to"
  titles <- raw_titles[!grepl(exclude_patterns, raw_titles, ignore.case = TRUE)]
  titles <- titles[nchar(titles) < 90]
  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = "Frazer",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}


# Richey Public Schools (Dawson County) -- CyberSchool CMS,
# plain httr2 fetch, no chromote needed. Active positions listed
# in #maincontent .cs-html-widget strong / headings.
fetch_richey_postings <- function(url = "https://www.richey.k12.mt.us/currentopenings") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_richey_postings(resp_body_string(resp), url)
}

parse_richey_postings <- function(html_text, url = "https://www.richey.k12.mt.us/currentopenings") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  page <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(page)) return(empty)
  elems <- rvest::html_elements(page, "#maincontent .cs-html-widget strong, #maincontent .cs-html-widget h1, #maincontent .cs-html-widget h2, #maincontent .cs-html-widget h3, #maincontent .cs-html-widget h4")
  if (length(elems) == 0) return(empty)

  raw_titles <- rvest::html_text(elems, trim = TRUE)
  raw_titles <- gsub("\u00a0", " ", raw_titles)
  raw_titles <- trimws(raw_titles)
  raw_titles <- raw_titles[nzchar(raw_titles)]

  exclude_patterns <- "^Current Job Posting$|^Current Job Openings?$|^Login$|^Career Opportunities$|^We are committed|^Posted On$"
  titles <- raw_titles[!grepl(exclude_patterns, raw_titles, ignore.case = TRUE)]
  titles <- titles[nchar(titles) < 90]
  titles <- unique(titles)
  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = "Richey",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Judith Gap Schools (CyberSchool CMS AJAX Jobs Widget)
# ---------------------------------------------------------------------------
fetch_judithgap_postings <- function(url = "https://www.judithgap.k12.mt.us/District/Portal/Employment") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  body <- resp_body_string(resp)
  ppid_m <- regmatches(body, regexpr("grab_jobsdata\\((\\d+)", body))
  ppid <- if (length(ppid_m) > 0) sub("grab_jobsdata\\(", "", ppid_m) else "384"

  ajax_url <- paste0(
    "https://www.judithgap.k12.mt.us/ajax/responsive/Jobs/jobs_content.cfm?ppid=",
    ppid,
    "&alias=District&scid=1&ad=0&gcdid=0&homepage=false&cross=false"
  )
  ajax_resp <- request(ajax_url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_judithgap_postings(resp_body_string(ajax_resp), url = url)
}

parse_judithgap_postings <- function(html_text, url = "https://www.judithgap.k12.mt.us/District/Portal/Employment") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)
  panels <- rvest::html_elements(doc, ".panel-default")
  if (length(panels) == 0) return(empty)

  rows <- list()
  for (p in panels) {
    p_text <- rvest::html_text2(p)
    date_m <- regmatches(p_text, regexpr("Date Posted\\s*:\\s*([A-Za-z]+\\s+\\d+\\s*,\\s*\\d{4})", p_text))
    posted_date <- if (length(date_m) > 0) {
      sub("Date Posted\\s*:\\s*", "", date_m)
    } else {
      NA_character_
    }

    lines <- strsplit(p_text, "\n")[[1]]
    lines <- trimws(lines)
    lines <- lines[nzchar(lines)]

    for (line in lines) {
      if (grepl("Custodian|Cook Position|Teacher|Driver|Aide|Secretary|Principal|Superintendent", line, ignore.case = TRUE) &&
          !grepl("School District|Qualifications|Duties|Responsibilities|accepting applications|seeking applications|Details|Dates", line, ignore.case = TRUE)) {
        clean_title <- gsub("^Judith Gap School\\s*[-–]\\s*", "", line)
        clean_title <- gsub("\\s+Position$", "", clean_title)
        rows[[length(rows) + 1]] <- data.frame(
          Title = clean_title,
          Location = "Judith Gap",
          Posted_Date = posted_date,
          Link = url,
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (length(rows) == 0) return(empty)
  res <- dplyr::bind_rows(rows)
  unique(res)
}

# ---------------------------------------------------------------------------
# Whitewater Public Schools (Finalsite CMS)
# ---------------------------------------------------------------------------
fetch_whitewater_postings <- function(url = "https://whitewater.k12.mt.us/employment") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_whitewater_postings(resp_body_string(resp), url = url)
}

parse_whitewater_postings <- function(html_text, url = "https://whitewater.k12.mt.us/employment") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)
  sections <- rvest::html_elements(doc, ".fsPageContent .fsContent")
  if (length(sections) == 0) return(empty)

  rows <- list()
  for (sec in sections) {
    header_el <- rvest::html_element(sec, "header .fsElementTitle, h2.fsElementTitle")
    if (length(header_el) == 0 || is.na(header_el)) next
    header_text <- trimws(rvest::html_text(header_el))
    if (!nzchar(header_text) || grepl("POSITION OPENINGS", header_text, ignore.case = TRUE)) next

    parts <- strsplit(header_text, ",|\\bor\\b")[[1]]
    for (part in trimws(parts)) {
      if (nzchar(part) && grepl("teacher|driver|custodian|coach|aide|substitute", part, ignore.case = TRUE)) {
        rows[[length(rows) + 1]] <- data.frame(
          Title = part,
          Location = "Whitewater",
          Posted_Date = NA_character_,
          Link = url,
          stringsAsFactors = FALSE
        )
      }
    }
  }

  if (length(rows) == 0) return(empty)
  dplyr::bind_rows(rows)
}

# ---------------------------------------------------------------------------
# Google Doc Preview Text Extractor (Shared Helper for Victor & Superior)
# ---------------------------------------------------------------------------
extract_google_doc_preview_text <- function(html_text) {
  if (is.null(html_text) || !nzchar(trimws(html_text))) return("")
  matches <- gregexpr("\"s\":\"([^\"]+)\"", html_text)
  strings <- regmatches(html_text, matches)[[1]]
  if (length(strings) == 0) return("")

  text_parts <- vapply(strings, function(s) {
    txt <- sub("^\"s\":\"", "", sub("\"$", "", s))
    txt <- gsub("\\\\n", "\n", txt)
    txt <- gsub("\\\\u0027", "\x27", txt)
    txt <- gsub("\\\\u0010|\\\\u0011|\\\\u0012|\\\\u001c", "", txt)
    txt
  }, character(1))
  paste(text_parts, collapse = "\n")
}

# ---------------------------------------------------------------------------
# Victor School District (Google Doc Preview Job Board)
# ---------------------------------------------------------------------------
fetch_victor_postings <- function(preview_url = "https://docs.google.com/document/d/1hPjGJCP2_6t4nOMl9xx7oZlK061x5KWd/preview") {
  resp <- request(preview_url) %>%
    perform_with_retry()
  parse_victor_postings(resp_body_string(resp), url = "https://www.victor.k12.mt.us/page/employment")
}

parse_victor_postings <- function(html_text, url = "https://www.victor.k12.mt.us/page/employment") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  text <- extract_google_doc_preview_text(html_text)
  if (!nzchar(text)) return(empty)

  date_m <- regmatches(text, regexpr("updated\\s+(\\d{1,2}/\\d{1,2}/\\d{4})", text, ignore.case = TRUE))
  posted_date <- if (length(date_m) > 0) {
    sub("updated\\s+", "", date_m, ignore.case = TRUE)
  } else {
    NA_character_
  }

  lines <- strsplit(text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  roles <- character(0)
  for (i in seq_along(lines)) {
    line <- lines[i]
    if (grepl("Openings:", line, ignore.case = TRUE) || grepl("Athletics/Coaching", line, ignore.case = TRUE)) {
      is_sub <- grepl("Substitute", line, ignore.case = TRUE)
      if (is_sub) {
        roles <- c(roles, "Substitute")
        next
      }
      j <- i + 1
      while (j <= length(lines) && !grepl("Openings:|Athletics/Coaching|equal opportunity", lines[j], ignore.case = TRUE)) {
        subline <- lines[j]
        if (!grepl("download|None at this time|Substitutes for the following", subline, ignore.case = TRUE) &&
            nzchar(subline)) {
          clean <- gsub("^\\d+\\s+", "", subline)
          clean <- gsub("\\s+positions?$", "", clean, ignore.case = TRUE)
          if (grepl("teacher|paraprofessional|coach|custodian", clean, ignore.case = TRUE)) {
            roles <- c(roles, clean)
          }
        }
        j <- j + 1
      }
    }
  }

  roles <- unique(roles)
  if (length(roles) == 0) return(empty)
  data.frame(
    Title = roles,
    Location = "Victor",
    Posted_Date = posted_date,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Superior School District (Google Doc Preview Job Board)
# ---------------------------------------------------------------------------
fetch_superior_postings <- function(preview_url = "https://docs.google.com/document/d/1ujnHba2a-gWdThpUB-T43LoCZoR_ViXzxZKTEuq67_g/preview") {
  resp <- request(preview_url) %>%
    perform_with_retry()
  parse_superior_postings(resp_body_string(resp), url = "https://www.ssd3.us/page/employment")
}

parse_superior_postings <- function(html_text, url = "https://www.ssd3.us/page/employment") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  text <- extract_google_doc_preview_text(html_text)
  if (!nzchar(text)) return(empty)

  lines <- strsplit(text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  roles <- character(0)
  for (line in lines) {
    m <- regmatches(line, regexpr("^[^–—-]*[–—-]", line))
    if (length(m) > 0) {
      prefix <- trimws(sub("[–—-]$", "", m))
      if (grepl("driver|teacher|paraprofessional|custodian|cook|coach|aide|substitute", prefix, ignore.case = TRUE) &&
          !grepl("District|Equal|Anyone|Online", prefix, ignore.case = TRUE)) {
        roles <- c(roles, prefix)
      }
    }
  }

  roles <- unique(roles)
  if (length(roles) == 0) return(empty)
  data.frame(
    Title = roles,
    Location = "Superior",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}


# ---------------------------------------------------------------------------
# Rapelje School District (ParentSquare CMS)
# ---------------------------------------------------------------------------
fetch_rapelje_postings <- function(url = "https://www.rapelje.k12.mt.us/job-listings") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_rapelje_postings(resp_body_string(resp), url = url)
}

parse_rapelje_postings <- function(html_text, url = "https://www.rapelje.k12.mt.us/job-listings") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  spans <- rvest::html_elements(doc, "span[style*='18px']")
  if (length(spans) == 0) return(empty)

  roles <- trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(spans)))
  roles <- roles[nzchar(roles)]
  roles <- roles[!grepl("apply|contact|opportunity|equal", roles, ignore.case = TRUE)]
  roles <- unique(roles)
  if (length(roles) == 0) return(empty)

  data.frame(
    Title = roles,
    Location = "Rapelje",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}


# ---------------------------------------------------------------------------
# Monforton School District #27 (WordPress Page)
# ---------------------------------------------------------------------------
fetch_monforton_postings <- function(url = "https://monfortonschool.org/contact-us/job-openings/") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_monforton_postings(resp_body_string(resp), url = url)
}

parse_monforton_postings <- function(html_text, url = "https://monfortonschool.org/contact-us/job-openings/") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  btn_spans <- rvest::html_elements(doc, "a.w-btn span.w-btn-label, .w-btn-wrapper a.w-btn")
  if (length(btn_spans) == 0) return(empty)

  texts <- unique(trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(btn_spans))))
  texts <- texts[nzchar(texts)]
  roles <- texts[!grepl("VIEW MORE|Translate|Menu", texts, ignore.case = TRUE)]
  if (length(roles) == 0) return(empty)

  data.frame(
    Title = roles,
    Location = "Bozeman",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Grass Range Public Schools (Joomla CMS / Article Notice)
# ---------------------------------------------------------------------------
fetch_grassrange_postings <- function(url = "https://grps.k12.mt.us/staff/open-positions") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_grassrange_postings(resp_body_string(resp), url = url)
}

parse_grassrange_postings <- function(html_text, url = "https://grps.k12.mt.us/staff/open-positions") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  p_nodes <- rvest::html_elements(doc, "div[itemprop='articleBody'] p")
  roles <- character(0)
  for (p in p_nodes) {
    txt <- trimws(rvest::html_text(p))
    if (grepl("school year:", txt, ignore.case = TRUE)) {
      after_txt <- sub(".*school year:[[:space:]]*", "", txt, ignore.case = TRUE)
      after_txt <- sub("[.][[:space:]]*$", "", after_txt)
      after_txt <- gsub("[\u00a0\r\n\t ]+", " ", after_txt)
      parts <- strsplit(after_txt, "[[:space:]]+and[[:space:]]+|[;,]")[[1]]
      for (part in trimws(parts)) {
        part <- sub("[.]+$", "", trimws(part))
        if (grepl("^[a-z]", part)) {
          part <- paste0(toupper(substr(part, 1, 1)), substr(part, 2, nchar(part)))
        }
        if (nzchar(part)) roles <- c(roles, part)
      }
    }
  }

  roles <- unique(roles)
  if (length(roles) == 0) return(empty)

  data.frame(
    Title = roles,
    Location = "Grass Range",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Heart Butte K-12 Schools (WordPress CMS)
# ---------------------------------------------------------------------------
fetch_heartbutte_postings <- function(url = "https://heartbutte.k12.mt.us/employment/") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_heartbutte_postings(resp_body_string(resp), url = url)
}

parse_heartbutte_postings <- function(html_text, url = "https://heartbutte.k12.mt.us/employment/") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  p_nodes <- rvest::html_elements(doc, ".wpb_wrapper p, p")
  roles <- character(0)
  found_header <- FALSE
  for (p in p_nodes) {
    txt <- trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(p)))
    if (grepl("Positions Available:", txt, ignore.case = TRUE)) {
      found_header <- TRUE
      next
    }
    if (found_header) {
      if (grepl("Application deadline|Please call", txt, ignore.case = TRUE)) break
      if (nzchar(txt)) {
        roles <- c(roles, txt)
      }
    }
  }

  coach_li <- rvest::html_elements(doc, ".gmail_default li, .wpb_wrapper ul li")
  for (li in coach_li) {
    txt <- trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(li)))
    if (nzchar(txt)) {
      roles <- c(roles, paste0("Head Coach - ", txt))
    }
  }

  roles <- unique(roles)
  if (length(roles) == 0) return(empty)

  data.frame(
    Title = roles,
    Location = "Heart Butte",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Noxon Public Schools (Apptegy CMS)
# ---------------------------------------------------------------------------
fetch_noxon_postings <- function(url = "https://www.noxonschools.com/o/nps/page/certified-listings") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_noxon_postings(resp_body_string(resp), url = url)
}

parse_noxon_postings <- function(html_text, url = "https://www.noxonschools.com/o/nps/page/certified-listings") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  m <- regmatches(html_text, regexec("window[.]clientWorkStateTemp[[:space:]]*=[[:space:]]*JSON[.]parse[(](.*?)[)];", html_text))[[1]]
  if (length(m) < 2) return(empty)

  parsed_data <- tryCatch({
    raw_json <- jsonlite::fromJSON(m[2])
    jsonlite::fromJSON(raw_json)
  }, error = function(e) NULL)
  if (is.null(parsed_data) || is.null(parsed_data$page$content)) return(empty)

  extract_all_html <- function(x) {
    out <- character(0)
    if (is.character(x)) {
      if (any(grepl("<[a-z]+[^>]*>", x, ignore.case = TRUE))) {
        out <- c(out, x[grepl("<[a-z]+[^>]*>", x, ignore.case = TRUE)])
      }
    } else if (is.data.frame(x)) {
      for (col in names(x)) out <- c(out, extract_all_html(x[[col]]))
    } else if (is.list(x)) {
      for (elem in x) out <- c(out, extract_all_html(elem))
    }
    out
  }

  htmls <- extract_all_html(parsed_data$page$content)
  roles <- character(0)
  for (h in htmls) {
    doc <- tryCatch(rvest::read_html(h), error = function(e) NULL)
    if (is.null(doc)) next
    st_nodes <- rvest::html_elements(doc, "strong, b")
    for (st in st_nodes) {
      txt <- trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(st)))
      if (grepl("Teacher|Instructor|Counselor|Principal|Superintendent|Coach|Custodian|Driver|Aide", txt, ignore.case = TRUE) &&
          !grepl("Open Certified Positions|About Our School|Why Noxon|What We|Contact Information", txt, ignore.case = TRUE)) {
        txt <- sub("[[:space:]]+[-–—][[:space:]]*$", "", txt)
        txt <- sub("^(?:full-time|part-time)[[:space:]]+", "", txt, ignore.case = TRUE)
        if (nzchar(txt)) roles <- c(roles, txt)
      }
    }
  }

  roles <- unique(roles)
  if (length(roles) == 0) return(empty)

  data.frame(
    Title = roles,
    Location = "Noxon",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Seeley Lake Elementary #34 (Apptegy CMS)
# ---------------------------------------------------------------------------
fetch_seeleylake_postings <- function(url = "https://www.sleonline.org/page/join-our-team") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_seeleylake_postings(resp_body_string(resp), url = url)
}

parse_seeleylake_postings <- function(html_text, url = "https://www.sleonline.org/page/join-our-team") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  m <- regmatches(html_text, regexec("window[.]clientWorkStateTemp[[:space:]]*=[[:space:]]*JSON[.]parse[(](.*?)[)];", html_text))[[1]]
  if (length(m) < 2) return(empty)

  parsed_data <- tryCatch({
    raw_json <- jsonlite::fromJSON(m[2])
    jsonlite::fromJSON(raw_json)
  }, error = function(e) NULL)
  if (is.null(parsed_data) || is.null(parsed_data$page$content)) return(empty)

  extract_all_html <- function(x) {
    out <- character(0)
    if (is.character(x)) {
      if (any(grepl("<[a-z]+[^>]*>", x, ignore.case = TRUE))) {
        out <- c(out, x[grepl("<[a-z]+[^>]*>", x, ignore.case = TRUE)])
      }
    } else if (is.data.frame(x)) {
      for (col in names(x)) out <- c(out, extract_all_html(x[[col]]))
    } else if (is.list(x)) {
      for (elem in x) out <- c(out, extract_all_html(elem))
    }
    out
  }

  htmls <- extract_all_html(parsed_data$page$content)
  roles <- character(0)
  for (h in htmls) {
    doc <- tryCatch(rvest::read_html(h), error = function(e) NULL)
    if (is.null(doc)) next
    st_nodes <- rvest::html_elements(doc, "strong, b")
    for (st in st_nodes) {
      txt <- trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(st)))
      if (grepl("Substitute|Teacher|Coach|Driver|Para|Custodian|Clerk|Aide", txt, ignore.case = TRUE) &&
          !grepl("looking to fill|following positions|completed applications", txt, ignore.case = TRUE)) {
        txt <- sub("[[:space:]]*[-–—][[:space:]]*Approx.*$", "", txt, ignore.case = TRUE)
        txt <- trimws(txt)
        if (nzchar(txt)) roles <- c(roles, txt)
      }
    }
  }

  roles <- unique(roles)
  if (length(roles) == 0) return(empty)

  data.frame(
    Title = roles,
    Location = "Seeley Lake",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# East Glacier Park Grade School (CyberSchool CMS)
# ---------------------------------------------------------------------------
fetch_eastglacier_postings <- function(url = "https://eastglacierschool.com/employment") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_eastglacier_postings(resp_body_string(resp), url = url)
}

parse_eastglacier_postings <- function(html_text, url = "https://eastglacierschool.com/employment") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  widgets <- rvest::html_elements(doc, ".cs-html-widget p strong, .cs-html-widget h2 strong, .cs-html-widget span strong")
  roles <- character(0)
  for (w in widgets) {
    txt <- trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(w)))
    if (grepl("Teacher|Coach|Driver|Para|Custodian|Clerk|Aide|Specialist", txt, ignore.case = TRUE) &&
        !grepl("All Other Applicants|Application|Notaries|Available Positions", txt, ignore.case = TRUE)) {
      roles <- c(roles, txt)
    }
  }

  roles <- unique(roles)
  if (length(roles) == 0) return(empty)

  data.frame(
    Title = roles,
    Location = "East Glacier Park",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Charlo School District 7J (charlo.k12.mt.us)
# ---------------------------------------------------------------------------
fetch_charlo_postings <- function(url = "https://charlo.k12.mt.us/") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_charlo_postings(resp_body_string(resp), url = url)
}

parse_charlo_postings <- function(html_text, url = "https://charlo.k12.mt.us/") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  title_nodes <- rvest::html_elements(doc, ".announcements__card-title")
  if (length(title_nodes) == 0) return(empty)

  roles <- character(0)
  links <- character(0)

  for (ti in title_nodes) {
    txt <- trimws(rvest::html_text(ti))
    if (grepl("^[Hh]iring[[:space:]]+", txt)) {
      role <- trimws(sub("^[Hh]iring[[:space:]]+", "", txt))
      a_parent <- rvest::html_element(ti, xpath = "./ancestor::a[1]")
      href <- if (!is.na(a_parent)) rvest::html_attr(a_parent, "href") else NA_character_
      if (is.na(href) || href == "#main-content" || !nzchar(href)) {
        href <- url
      } else {
        href <- xml2::url_absolute(href, url)
      }
      if (nzchar(role)) {
        roles <- c(roles, role)
        links <- c(links, href)
      }
    }
  }

  if (length(roles) == 0) return(empty)

  data.frame(
    Title = roles,
    Location = "Charlo",
    Posted_Date = NA_character_,
    Link = links,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Canyon Creek School District #4 (canyoncreekschool.org, Edlio CMS)
# ---------------------------------------------------------------------------
fetch_canyoncreek_postings <- function(url = "https://www.canyoncreekschool.org/apps/jobs/") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_canyoncreek_postings(resp_body_string(resp), url = url)
}

parse_canyoncreek_postings <- function(html_text, url = "https://www.canyoncreekschool.org/apps/jobs/") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  job_nodes <- rvest::html_elements(doc, "a[href*='show_job.jsp']")
  if (length(job_nodes) == 0) return(empty)

  titles <- character(0)
  links <- character(0)

  for (n in job_nodes) {
    t <- trimws(rvest::html_text(n))
    h <- rvest::html_attr(n, "href")
    full_link <- if (!is.na(h) && nzchar(h)) xml2::url_absolute(h, url) else url
    if (nzchar(t)) {
      titles <- c(titles, t)
      links <- c(links, full_link)
    }
  }

  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = "Billings",
    Posted_Date = NA_character_,
    Link = links,
    stringsAsFactors = FALSE
  )
}


# ---------------------------------------------------------------------------
# Helena Flats School District #15 (Apptegy CMS)
# ---------------------------------------------------------------------------
fetch_helenaflats_postings <- function(url = "https://www.helenaflats.org/page/employment") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_helenaflats_postings(resp_body_string(resp), url = url)
}

parse_helenaflats_postings <- function(html_text, url = "https://www.helenaflats.org/page/employment") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  m <- regmatches(html_text, regexec("window[.]clientWorkStateTemp[[:space:]]*=[[:space:]]*JSON[.]parse[(](.*?)[)];", html_text))[[1]]
  if (length(m) < 2) return(empty)

  parsed_data <- tryCatch({
    raw_json <- jsonlite::fromJSON(m[2])
    jsonlite::fromJSON(raw_json)
  }, error = function(e) NULL)
  if (is.null(parsed_data) || is.null(parsed_data$page$content)) return(empty)

  extract_all_html <- function(x) {
    out <- character(0)
    if (is.character(x)) {
      if (any(grepl("<[a-z]+[^>]*>", x, ignore.case = TRUE))) {
        out <- c(out, x[grepl("<[a-z]+[^>]*>", x, ignore.case = TRUE)])
      }
    } else if (is.data.frame(x)) {
      for (col in names(x)) out <- c(out, extract_all_html(x[[col]]))
    } else if (is.list(x)) {
      for (elem in x) out <- c(out, extract_all_html(elem))
    }
    out
  }

  htmls <- extract_all_html(parsed_data$page$content)
  roles <- character(0)
  for (h in htmls) {
    doc <- tryCatch(rvest::read_html(h), error = function(e) NULL)
    if (is.null(doc)) next
    st_nodes <- rvest::html_elements(doc, "strong, b")
    for (st in st_nodes) {
      txt <- trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(st)))
      if (grepl("Paraprofessional|Teacher|Substitute|Custodian|Driver|Aide", txt, ignore.case = TRUE) &&
          !grepl("Equal Opportunity|Qualifications|Why Join|How to Apply", txt, ignore.case = TRUE)) {
        txt <- sub("[[:space:]]+[-–—][[:space:]]*Helena Flats.*$", "", txt, ignore.case = TRUE)
        txt <- trimws(txt)
        if (nzchar(txt)) roles <- c(roles, txt)
      }
    }
    p_nodes <- rvest::html_elements(doc, "p")
    for (p in p_nodes) {
      txt <- trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(p)))
      if (grepl("Substitutes Needed", txt, ignore.case = TRUE)) {
        sub_match <- regmatches(txt, regexec("(Substitutes Needed[^$0-9<]*)", txt))[[1]]
        if (length(sub_match) >= 2) {
          roles <- c(roles, trimws(sub_match[2]))
        }
      }
    }
  }

  roles <- unique(roles)
  if (length(roles) == 0) return(empty)

  data.frame(
    Title = roles,
    Location = "Kalispell",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}


# ---------------------------------------------------------------------------
# Jordan Public Schools (SchoolInSites CMS / homepage announcements)
# ---------------------------------------------------------------------------
fetch_jordan_postings <- function(url = "https://www.jordanpublicschools.org") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_jordan_postings(resp_body_string(resp), url = url)
}

parse_jordan_postings <- function(html_text, url = "https://www.jordanpublicschools.org") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  imgs <- rvest::html_elements(doc, "img[alt*='looking to hire'], img[alt*='Positions Available'], img[alt*='positions available'], img[alt*='Coaching']")
  titles <- character(0)
  for (img in imgs) {
    alt <- rvest::html_attr(img, "alt")
    m_hire <- regmatches(alt, regexec("looking to hire (?:a |an )?([^.]+)", alt, ignore.case = TRUE))[[1]]
    if (length(m_hire) > 1) {
      raw <- m_hire[2]
      if (grepl("head of maintenance", raw, ignore.case = TRUE)) {
        titles <- c(titles, "Head of Maintenance")
      } else if (grepl("music teacher", raw, ignore.case = TRUE)) {
        titles <- c(titles, "K-12 Music Teacher")
      } else {
        titles <- c(titles, trimws(raw))
      }
    }
    if (grepl("Coaching Positions Available!", alt, ignore.case = TRUE)) {
      if (grepl("Junior High Football Head Coach", alt)) titles <- c(titles, "Junior High Football Head Coach and Assistant Coach")
      if (grepl("Junior High Boys Basketball Coach", alt)) titles <- c(titles, "Junior High Boys Basketball Coach")
      if (grepl("High School Boys Basketball Coach", alt)) titles <- c(titles, "High School Boys Basketball Coach")
    }
  }

  extra_nodes <- rvest::html_elements(doc, ".cs-item-title, .cs-image-widget p, .content-zone p")
  for (node in extra_nodes) {
    txt <- trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(node)))
    if (nzchar(txt) && grepl("^(?:teacher|coach|custodian|para|substitute)", txt, ignore.case = TRUE) &&
        !grepl("application|handbook|welcome", txt, ignore.case = TRUE)) {
      titles <- c(titles, txt)
    }
  }

  titles <- unique(titles[nzchar(titles)])
  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = "Jordan",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Pioneer Elementary School District #41 (SchoolCMS)
# ---------------------------------------------------------------------------
fetch_pioneer_postings <- function(url = "http://pioneerschool.us/41034_2") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_pioneer_postings(resp_body_string(resp), url = url)
}

parse_pioneer_postings <- function(html_text, url = "http://pioneerschool.us/41034_2") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  headings <- rvest::html_elements(doc, "h1, h2, h3, h4, strong")
  titles <- character(0)
  for (h in headings) {
    txt <- trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(h)))
    if (grepl("substitute teachers wanted", txt, ignore.case = TRUE)) {
      titles <- c(titles, "Substitute Teacher")
    } else if (nzchar(txt) && !grepl("^(?:job opening|join our team|welcome|navigation|home|calendar|pioneer)", txt, ignore.case = TRUE) &&
               grepl("teacher|aide|custodian|coach|driver|specialist|principal|superintendent", txt, ignore.case = TRUE)) {
      titles <- c(titles, txt)
    }
  }

  titles <- unique(titles[nzchar(titles)])
  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = "Billings",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Opheim Public Schools (Google Sites)
# ---------------------------------------------------------------------------
fetch_opheim_postings <- function(url = "https://sites.google.com/site/opheimschool/office") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_opheim_postings(resp_body_string(resp), url = url)
}

parse_opheim_postings <- function(html_text, url = "https://sites.google.com/site/opheimschool/office") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  body_text <- rvest::html_text2(rvest::html_element(doc, "body"))
  lines <- trimws(strsplit(body_text, "\n")[[1]])
  lines <- lines[nzchar(lines)]

  titles <- character(0)
  for (i in seq_along(lines)) {
    l <- lines[i]
    if (grepl("Substitute teachers", l, ignore.case = TRUE)) {
      titles <- c(titles, "Substitute Teacher")
    }
    if (grepl("Substitute (?:e-)?bus drivers", l, ignore.case = TRUE)) {
      titles <- c(titles, "Substitute Bus Driver")
    }
    if (grepl("School Faculty Openings", l, ignore.case = TRUE)) {
      for (j in (i + 1):min(length(lines), i + 5)) {
        next_l <- lines[j]
        if (grepl("application|report abuse|current staff|google sites", next_l, ignore.case = TRUE)) break
        if (grepl("complete listing|see OPI|^[(]", next_l, ignore.case = TRUE)) next
        if (grepl("^music$", next_l, ignore.case = TRUE)) {
          titles <- c(titles, "Music Teacher")
        } else if (grepl("teacher|math|science|english|grade|elementary", next_l, ignore.case = TRUE)) {
          titles <- c(titles, next_l)
        }
      }
    }
  }

  titles <- unique(titles[nzchar(titles)])
  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = "Opheim",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Pryor Public Schools (Divi CMS, pryorwarriors.org)
# ---------------------------------------------------------------------------
fetch_pryor_postings <- function(url = "https://pryorwarriors.org/human-resources/") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_pryor_postings(resp_body_string(resp), url = url)
}

parse_pryor_postings <- function(html_text, url = "https://pryorwarriors.org/human-resources/") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  blurbs <- rvest::html_elements(doc, ".et_pb_blurb")
  titles <- character(0)
  links <- character(0)

  for (b in blurbs) {
    hdr <- rvest::html_element(b, ".et_pb_module_header")
    if (is.na(hdr)) next
    hdr_txt <- trimws(rvest::html_text2(hdr))
    if (!grepl("hiring", hdr_txt, ignore.case = TRUE) || grepl("^we are hiring$", hdr_txt, ignore.case = TRUE)) next
    if (grepl("application|handbook|agreement|compensation|form|plan|proposal", hdr_txt, ignore.case = TRUE)) next

    clean_title <- sub("^(foundations|we are)[[:space:]]+hiring[[:space:]]+(for[[:space:]]+)?", "", hdr_txt, ignore.case = TRUE)
    clean_title <- trimws(clean_title)
    if (!nzchar(clean_title)) next

    link_node <- rvest::html_element(b, ".et_pb_blurb_description a")
    link_href <- if (!is.na(link_node)) rvest::html_attr(link_node, "href") else url
    if (is.na(link_href) || !nzchar(link_href)) link_href <- url

    titles <- c(titles, clean_title)
    links <- c(links, link_href)
  }

  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = "Pryor",
    Posted_Date = NA_character_,
    Link = links,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# West Glacier Elementary School District #8 (Google Sites)
# ---------------------------------------------------------------------------
fetch_westglacier_postings <- function(url = "https://www.westglacierelementary.org/opportunities/employment") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_westglacier_postings(resp_body_string(resp), url = url)
}

parse_westglacier_postings <- function(html_text, url = "https://www.westglacierelementary.org/opportunities/employment") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  links <- rvest::html_elements(doc, "a")
  titles <- character(0)
  links_out <- character(0)

  for (l in links) {
    txt <- trimws(rvest::html_text2(l))
    href <- rvest::html_attr(l, "href")
    if (is.na(href) || !nzchar(href)) next
    clean_title <- sub("[[:space:]]+Position[[:space:]]+Description.*$", "", txt, ignore.case = TRUE)
    clean_title <- trimws(clean_title)

    if (grepl("(Teacher|Custodian|Maintenance|Aide|Paraprofessional|Driver|Coach|Nurse|Cook|Secretary)", clean_title, ignore.case = TRUE) &&
        !grepl("(Application|Handbook|Policy|Plan)", clean_title, ignore.case = TRUE)) {
      if (length(titles) > 0 && any(sapply(titles, function(t) grepl(t, clean_title, fixed = TRUE) || grepl(clean_title, t, fixed = TRUE)))) {
        next
      }
      abs_url <- xml2::url_absolute(href, url)
      titles <- c(titles, clean_title)
      links_out <- c(links_out, abs_url)
    }
  }

  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = rep("West Glacier", length(titles)),
    Posted_Date = rep(NA_character_, length(titles)),
    Link = links_out,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Trout Creek School District #6 (Edlio CMS, troutcreekeagles.org)
# ---------------------------------------------------------------------------
fetch_troutcreek_postings <- function(url = "https://www.troutcreekeagles.org/apps/pages/index.jsp?uREC_ID=4449487&type=d&pREC_ID=2698685") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_troutcreek_postings(resp_body_string(resp), url = url)
}

parse_troutcreek_postings <- function(html_text, url = "https://www.troutcreekeagles.org/apps/pages/index.jsp?uREC_ID=4449487&type=d&pREC_ID=2698685") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  links <- rvest::html_elements(doc, ".page-block-text div a")
  titles <- character(0)
  links_out <- character(0)

  for (a in links) {
    txt <- trimws(rvest::html_text2(a))
    href <- rvest::html_attr(a, "href")
    if (nzchar(txt)) {
      clean_title <- sub("^[Ww]e are currently looking for[[:space:]]+", "", txt)
      clean_title <- sub("!$", "", clean_title)
      clean_title <- trimws(clean_title)
      if (!nzchar(clean_title) || grepl("Application|Form|Handbook", clean_title, ignore.case = TRUE)) next
      abs_url <- xml2::url_absolute(href, url)
      titles <- c(titles, clean_title)
      links_out <- c(links_out, abs_url)
    }
  }

  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = rep("Trout Creek", length(titles)),
    Posted_Date = rep(NA_character_, length(titles)),
    Link = links_out,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Kila School District #20
# ---------------------------------------------------------------------------
fetch_kila_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_kila_postings(html, url)
}

parse_kila_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  tables <- html_elements(doc, "table")
  titles <- character(0)
  dates <- character(0)

  for (tbl in tables) {
    rows <- html_elements(tbl, "tr")
    for (r in rows) {
      cells <- trimws(html_text2(html_elements(r, "td, th")))
      if (length(cells) >= 3) {
        title <- cells[1]
        open_dt <- cells[3]
        if (nzchar(title) && !grepl("^(CLASSIFIED|SUBSTITUTE|COACHING|CERTIFIED|Job Title|No Open Positions)$", title, ignore.case = TRUE)) {
          titles <- c(titles, title)
          dates <- c(dates, if (grepl("^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}$", open_dt)) open_dt else NA_character_)
        }
      }
    }
  }

  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = rep("Kila", length(titles)),
    Posted_Date = dates,
    Link = rep(url, length(titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Lavina Public Schools
# ---------------------------------------------------------------------------
fetch_lavina_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_lavina_postings(html, url)
}

parse_lavina_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  ps <- html_elements(doc, ".pageData p, #content p, .maincontent p")
  texts <- trimws(html_text2(ps))

  start_idx <- which(grepl("accepting applications for the following positions", texts, ignore.case = TRUE))
  end_idx <- which(grepl("pending the number of participants|Open Until Filled", texts, ignore.case = TRUE))

  if (length(start_idx) == 0 || length(end_idx) == 0 || end_idx[1] <= start_idx[1] + 1) {
    return(empty)
  }

  titles <- texts[(start_idx[1] + 1):(end_idx[1] - 1)]
  titles <- titles[nzchar(titles)]

  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = rep("Lavina", length(titles)),
    Posted_Date = rep(NA_character_, length(titles)),
    Link = rep(url, length(titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Fromberg Public Schools
# ---------------------------------------------------------------------------
fetch_fromberg_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_fromberg_postings(html, url)
}

parse_fromberg_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  links <- html_elements(doc, ".fsResourceElement a.fsResourceLink, .fsResource a.fsResourceLink")
  titles <- character(0)
  links_out <- character(0)

  for (a in links) {
    href <- html_attr(a, "href")
    res_title <- html_attr(a, "data-resource-title")
    img_alt <- html_attr(html_element(a, "img"), "alt")
    txt <- trimws(html_text2(a))

    raw_title <- if (!is.na(res_title) && nzchar(res_title)) {
      res_title
    } else if (!is.na(img_alt) && nzchar(img_alt)) {
      img_alt
    } else {
      txt
    }

    if (!is.na(raw_title) && nzchar(raw_title)) {
      clean_title <- sub("[.][a-zA-Z0-9]+$", "", raw_title)
      clean_title <- sub("\\s*\\(PDF\\)$", "", clean_title, ignore.case = TRUE)
      clean_title <- trimws(gsub("([a-z])([A-Z])", "\\1 \\2", clean_title))
      if (nzchar(clean_title) && !grepl("^(Application|Form)$", clean_title, ignore.case = TRUE)) {
        titles <- c(titles, clean_title)
        links_out <- c(links_out, xml2::url_absolute(href, url))
      }
    }
  }

  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = rep("Fromberg", length(titles)),
    Posted_Date = rep(NA_character_, length(titles)),
    Link = links_out,
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Pleasant Valley School District #27
# ---------------------------------------------------------------------------
fetch_pleasantvalley_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_pleasantvalley_postings(html, url)
}

parse_pleasantvalley_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  content <- html_element(doc, "#wsite-content")
  if (is.null(content)) return(empty)

  h2s <- html_elements(content, "h2.wsite-content-title, .wsite-content-title")
  if (length(h2s) == 0) return(empty)

  titles <- trimws(html_text2(h2s))
  titles <- titles[nzchar(titles)]
  titles <- titles[!grepl("^(Careers|Employment|Application|No opening|No vacancies|None at this time)", titles, ignore.case = TRUE)]

  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = rep("Marion", length(titles)),
    Posted_Date = rep(NA_character_, length(titles)),
    Link = rep(url, length(titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Sun River Valley School District #24
# ---------------------------------------------------------------------------
fetch_sunrivervalley_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_sunrivervalley_postings(html, url)
}

parse_sunrivervalley_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  links <- html_elements(doc, "a[href*=\"show_job.jsp\"], a[href*=\"/apps/jobs/\"]")
  titles <- character(0)
  links_out <- character(0)

  for (a in links) {
    href <- html_attr(a, "href")
    txt <- trimws(html_text2(a))
    if (grepl("show_job\\.jsp", href) && nzchar(txt) && !grepl("^(Job Applications|Employment Opportunities)$", txt, ignore.case = TRUE)) {
      titles <- c(titles, txt)
      links_out <- c(links_out, xml2::url_absolute(href, url))
    }
  }

  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = rep("Simms", length(titles)),
    Posted_Date = rep(NA_character_, length(titles)),
    Link = links_out,
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Circle Public Schools
# ---------------------------------------------------------------------------
fetch_circle_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_circle_postings(html, url)
}

parse_circle_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  content <- html_element(doc, "#wsite-content")
  if (is.null(content)) return(empty)

  h2s <- html_elements(content, "h2.wsite-content-title, .wsite-content-title, .paragraph")
  if (length(h2s) == 0) return(empty)

  raw_titles <- trimws(html_text2(h2s))
  raw_titles <- raw_titles[nzchar(raw_titles)]
  titles <- raw_titles[!grepl("^(Employment Opportunities|Certified Salary|Click here for|Classified Personnel|Certified Personnel|Coaching Personnel|NOTE:|No opening)", raw_titles, ignore.case = TRUE)]

  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = rep("Circle", length(titles)),
    Posted_Date = rep(NA_character_, length(titles)),
    Link = rep(url, length(titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Forsyth Public Schools
# ---------------------------------------------------------------------------
fetch_forsyth_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_forsyth_postings(html, url)
}

parse_forsyth_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  titles <- character(0)
  links_out <- character(0)

  h1s <- html_elements(doc, "h1.entry-title, .post-title, h1, h2")
  h1_texts <- trimws(html_text2(h1s))
  valid_h1 <- h1_texts[grepl("wanted|opening|position|teacher|driver|custodian|coach", h1_texts, ignore.case = TRUE) &
                       !grepl("^(ADA Web Accessibility)$", h1_texts, ignore.case = TRUE)]

  pdf_link <- html_attr(html_elements(doc, ".entry-content a[href*=\".pdf\"], article a[href*=\".pdf\"]"), "href")

  if (length(valid_h1) > 0) {
    for (t in valid_h1) {
      titles <- c(titles, t)
      link <- if (length(pdf_link) > 0 && nzchar(pdf_link[1])) xml2::url_absolute(pdf_link[1], url) else url
      links_out <- c(links_out, link)
    }
  }

  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = rep("Forsyth", length(titles)),
    Posted_Date = rep(NA_character_, length(titles)),
    Link = links_out,
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# DeSmet Public School
# ---------------------------------------------------------------------------
fetch_desmet_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_desmet_postings(html, url)
}

parse_desmet_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  content <- html_elements(doc, ".entry-content, article, #main-content")
  if (length(content) == 0) return(empty)

  elements <- html_elements(content, "h1, h2, h3, h4, li, a")
  texts <- trimws(html_text2(elements))
  texts <- texts[nzchar(texts)]

  clean_titles <- texts[!grepl("^(Available Employment Opportunities|Fill Out an Application|Certified Staff Application|Classified Staff Application|DeSmet School is built|Jobs Available|DeSmet School|Character, Community)", texts, ignore.case = TRUE) &
                        grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position", texts, ignore.case = TRUE)]

  if (length(clean_titles) == 0) return(empty)

  df <- data.frame(
    Title = clean_titles,
    Location = rep("Missoula", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(url, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Fishtail School District #13
# ---------------------------------------------------------------------------
fetch_fishtail_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_fishtail_postings(html, url)
}

parse_fishtail_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  content <- html_elements(doc, "#av-primary-content, .entry-content, article")
  if (length(content) == 0) return(empty)

  elements <- html_elements(content, "h1, h2, h3, h4, li, a, p")
  if (length(elements) == 0) return(empty)

  texts <- trimws(html_text2(elements))
  texts <- texts[nzchar(texts)]

  clean_titles <- texts[!grepl("^(Available Employment Opportunities|Employment Opportunities|Job Openings|Safe Re-Opening|Application Form|Staff Application|ADA Web Accessibility|Click here|Download|Resources|Our School)", texts, ignore.case = TRUE) &
                        grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position|substitute|wanted", texts, ignore.case = TRUE)]

  if (length(clean_titles) == 0) return(empty)

  pdf_links <- html_attr(html_elements(content, "a[href*=\".pdf\"]"), "href")
  link_out <- if (length(pdf_links) > 0 && nzchar(pdf_links[1])) xml2::url_absolute(pdf_links[1], url) else url

  df <- data.frame(
    Title = clean_titles,
    Location = rep("Fishtail", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(link_out, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Nye School District #31
# ---------------------------------------------------------------------------
fetch_nye_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_nye_postings(html, url)
}

parse_nye_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  content <- html_elements(doc, ".entry-content, article, #main-content")
  if (length(content) == 0) return(empty)

  elements <- html_elements(content, "h1, h2, h3, h4, li, a, p")
  if (length(elements) == 0) return(empty)

  texts <- trimws(html_text2(elements))
  texts <- texts[nzchar(texts)]

  clean_titles <- texts[!grepl("^(Available Employment Opportunities|Employment Opportunities|Job Openings|Safe Re-Opening|Application Form|Staff Application|ADA Web Accessibility|Click here|Download|Resources|Our School)", texts, ignore.case = TRUE) &
                        grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position|substitute|wanted", texts, ignore.case = TRUE)]

  if (length(clean_titles) == 0) return(empty)

  pdf_links <- html_attr(html_elements(content, "a[href*=\".pdf\"]"), "href")
  link_out <- if (length(pdf_links) > 0 && nzchar(pdf_links[1])) xml2::url_absolute(pdf_links[1], url) else url

  df <- data.frame(
    Title = clean_titles,
    Location = rep("Nye", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(link_out, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Potomac Elementary School District #11
# ---------------------------------------------------------------------------
fetch_potomac_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_potomac_postings(html, url)
}

parse_potomac_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  content <- html_elements(doc, "main, [role=\"main\"], #SITE_PAGES")
  if (length(content) == 0) return(empty)

  elements <- html_elements(content, "h1, h2, h3, h4, p, li, a")
  if (length(elements) == 0) return(empty)

  raw_texts <- trimws(html_text2(elements))
  raw_texts <- raw_texts[nzchar(raw_texts)]

  # Filter generic headings, navigation, and standing application prompts
  clean_titles <- raw_texts[!grepl("^(Jobs|Contact the Clerk|Potomac School District Application|Click the document link|Document|Home|Calendar|Menu|Resources|Contact Us)", raw_texts, ignore.case = TRUE) &
                            grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position|substitute", raw_texts, ignore.case = TRUE)]

  if (length(clean_titles) == 0) return(empty)

  df <- data.frame(
    Title = clean_titles,
    Location = rep("Potomac", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(url, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Frontier Elementary School
# ---------------------------------------------------------------------------
fetch_frontier_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_frontier_postings(html, url)
}

parse_frontier_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  container <- html_elements(doc, ".listItem_bodyContent, #maincontent, .cs-html-widget, main, #content")
  if (length(container) == 0) container <- doc

  elements <- html_elements(container, "li, p, .listItem_holder, strong, h2, h3, h4")
  if (length(elements) == 0) return(empty)

  raw_titles <- trimws(html_text2(elements))
  raw_titles <- raw_titles[nzchar(raw_titles)]

  exclude_patterns <- "^(Applications?|Click Here|Download|None|Equal Opportunity|Back to|Current Jobs|Archive Jobs|View Jobs|Site Map|Skip To|Share|Alert|Login|Subscribe|Views)"
  clean_titles <- raw_titles[!grepl(exclude_patterns, raw_titles, ignore.case = TRUE) &
                             grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position|substitute|kitchen", raw_titles, ignore.case = TRUE)]
  clean_titles <- clean_titles[nchar(clean_titles) < 90]

  if (length(clean_titles) == 0) return(empty)

  df <- data.frame(
    Title = clean_titles,
    Location = rep("Wolf Point", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(url, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Saco Public Schools
# ---------------------------------------------------------------------------
fetch_saco_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_saco_postings(html, url)
}

parse_saco_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  container <- html_elements(doc, ".listItem_bodyContent, #maincontent, .cs-html-widget, main, #content")
  if (length(container) == 0) container <- doc

  elements <- html_elements(container, "li, p, .listItem_holder, strong, h2, h3, h4")
  if (length(elements) == 0) return(empty)

  raw_titles <- trimws(html_text2(elements))
  raw_titles <- raw_titles[nzchar(raw_titles)]

  exclude_patterns <- "^(Applications?|Click Here|Download|None|Equal Opportunity|Back to|Current Jobs|Archive Jobs|View Jobs|Site Map|Skip To|Share|Alert|Login|Subscribe|Views)"
  clean_titles <- raw_titles[!grepl(exclude_patterns, raw_titles, ignore.case = TRUE) &
                             grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position|substitute|kitchen", raw_titles, ignore.case = TRUE)]
  clean_titles <- clean_titles[nchar(clean_titles) < 90]

  if (length(clean_titles) == 0) return(empty)

  df <- data.frame(
    Title = clean_titles,
    Location = rep("Saco", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(url, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Ulm Public Schools
# ---------------------------------------------------------------------------
fetch_ulm_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_ulm_postings(html, url)
}

parse_ulm_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  content <- html_element(doc, "#wsite-content")
  if (is.null(content)) return(empty)

  elements <- html_elements(content, "h2.wsite-content-title, .wsite-content-title, .paragraph, p, li")
  if (length(elements) == 0) return(empty)

  raw_texts <- trimws(html_text2(elements))
  raw_texts <- raw_texts[nzchar(raw_texts)]

  clean_titles <- raw_texts[!grepl("^(Employment Opportunities|Certified Salary|Click here|Classified Personnel|Certified Personnel|Coaching Personnel|NOTE:|No opening|Equal Opportunity|Application Form)", raw_texts, ignore.case = TRUE) &
                            grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position|substitute", raw_texts, ignore.case = TRUE)]

  if (length(clean_titles) == 0) return(empty)

  df <- data.frame(
    Title = clean_titles,
    Location = rep("Ulm", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(url, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Montana City Elementary School District #27
# ---------------------------------------------------------------------------
fetch_montanacity_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_montanacity_postings(html, url)
}

parse_montanacity_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  container <- html_elements(doc, ".listItem_bodyContent, #maincontent, .cs-html-widget, main, #content")
  if (length(container) == 0) container <- doc

  elements <- html_elements(container, "li, p, .listItem_holder, strong, h2, h3, h4")
  if (length(elements) == 0) return(empty)

  raw_titles <- trimws(html_text2(elements))
  raw_titles <- raw_titles[nzchar(raw_titles)]

  exclude_patterns <- "^(Applications?|Click Here|Download|None|Equal Opportunity|Back to|Current Jobs|Archive Jobs|View Jobs|Site Map|Skip To|Share|Alert|Login|Subscribe|Views)"
  clean_titles <- raw_titles[!grepl(exclude_patterns, raw_titles, ignore.case = TRUE) &
                             grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position|substitute|kitchen", raw_titles, ignore.case = TRUE)]
  clean_titles <- clean_titles[nchar(clean_titles) < 90]

  if (length(clean_titles) == 0) return(empty)

  df <- data.frame(
    Title = clean_titles,
    Location = rep("Clancy", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(url, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Denton Public Schools
# ---------------------------------------------------------------------------
fetch_denton_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_denton_postings(html, url)
}

parse_denton_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  container <- html_elements(doc, ".listItem_bodyContent, #maincontent, .cs-html-widget, main, #content")
  if (length(container) == 0) container <- doc

  elements <- html_elements(container, "li, p, .listItem_holder, strong, h2, h3, h4")
  if (length(elements) == 0) return(empty)

  raw_titles <- trimws(html_text2(elements))
  raw_titles <- raw_titles[nzchar(raw_titles)]

  exclude_patterns <- "^(Applications?|Click Here|Download|None|Equal Opportunity|Back to|Current Jobs|Archive Jobs|View Jobs|Site Map|Skip To|Share|Alert|Login|Subscribe|Views)"
  clean_titles <- raw_titles[!grepl(exclude_patterns, raw_titles, ignore.case = TRUE) &
                             grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position|substitute|kitchen", raw_titles, ignore.case = TRUE)]
  clean_titles <- clean_titles[nchar(clean_titles) < 90]

  if (length(clean_titles) == 0) return(empty)

  df <- data.frame(
    Title = clean_titles,
    Location = rep("Denton", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(url, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Clancy Elementary School District #1
# ---------------------------------------------------------------------------
fetch_clancy_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_clancy_postings(html, url)
}

parse_clancy_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  container <- html_elements(doc, ".listItem_bodyContent, #maincontent, .cs-html-widget, main, #content")
  if (length(container) == 0) container <- doc

  elements <- html_elements(container, "li, p, .listItem_holder, strong, h2, h3, h4")
  if (length(elements) == 0) return(empty)

  raw_titles <- trimws(html_text2(elements))
  raw_titles <- raw_titles[nzchar(raw_titles)]

  exclude_patterns <- "^(Applications?|Click Here|Download|None|Equal Opportunity|Back to|Current Jobs|Archive Jobs|View Jobs|Site Map|Skip To|Share|Alert|Login|Subscribe|Views)"
  clean_titles <- raw_titles[!grepl(exclude_patterns, raw_titles, ignore.case = TRUE) &
                             grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position|substitute|kitchen", raw_titles, ignore.case = TRUE)]
  clean_titles <- clean_titles[nchar(clean_titles) < 90]

  if (length(clean_titles) == 0) return(empty)

  df <- data.frame(
    Title = clean_titles,
    Location = rep("Clancy", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(url, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Bainville K-12 Schools (Batch 23)
# ---------------------------------------------------------------------------
fetch_bainville_postings <- function(url = "https://www.bainvilleschool.com/page/employment") {
  doc_cert_url <- "https://docs.google.com/document/d/1n0ed1N5YGWsSs948BfXk1CYqK9BvzrGXIz4DRklS3mw/export?format=html"
  doc_class_url <- "https://docs.google.com/document/d/1nQVTrVJJususbBn9EvdT7xD1gDHFYeW3RQhdR10RTbQ/export?format=html"

  html_cert <- tryCatch({
    resp <- request(doc_cert_url) %>%
      req_headers("User-Agent" = "Mozilla/5.0") %>%
      perform_with_retry()
    resp_body_string(resp)
  }, error = function(e) "")

  html_class <- tryCatch({
    resp <- request(doc_class_url) %>%
      req_headers("User-Agent" = "Mozilla/5.0") %>%
      perform_with_retry()
    resp_body_string(resp)
  }, error = function(e) "")

  parse_bainville_postings(html_cert, html_class, url)
}

parse_bainville_postings <- function(html_cert, html_class, url = "https://www.bainvilleschool.com/page/employment") {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  titles <- character(0)

  if (nzchar(html_cert)) {
    doc1 <- tryCatch(read_html(html_cert), error = function(e) NULL)
    if (!is.null(doc1)) {
      lines <- strsplit(html_text2(doc1), "\n")[[1]]
      lines <- trimws(lines)
      lines <- lines[nzchar(lines)]
      start_i <- which(grepl("CERTIFIED JOB OPENINGS", lines, ignore.case = TRUE))
      stop_i <- which(grepl("Bainville School is a small", lines, ignore.case = TRUE))
      if (length(start_i) > 0 && length(stop_i) > 0 && stop_i[1] > start_i[1] + 1) {
        titles <- c(titles, lines[(start_i[1] + 1):(stop_i[1] - 1)])
      }
    }
  }

  if (nzchar(html_class)) {
    doc2 <- tryCatch(read_html(html_class), error = function(e) NULL)
    if (!is.null(doc2)) {
      lines <- strsplit(html_text2(doc2), "\n")[[1]]
      lines <- trimws(lines)
      lines <- lines[nzchar(lines)]
      curr_i <- which(grepl("^(202[0-9]-[0-9]{2}|Current Openings)$", lines, ignore.case = TRUE))
      addl_i <- which(grepl("Additional Openings for:", lines, ignore.case = TRUE))
      stop_i <- which(grepl("All applicants will be subject", lines, ignore.case = TRUE))
      if (length(curr_i) > 0 && length(addl_i) > 0) {
        last_curr <- max(curr_i[curr_i < addl_i[1]])
        if (addl_i[1] > last_curr + 1) {
          titles <- c(titles, lines[(last_curr + 1):(addl_i[1] - 1)])
        }
      }
      if (length(addl_i) > 0 && length(stop_i) > 0 && stop_i[1] > addl_i[1] + 1) {
        titles <- c(titles, lines[(addl_i[1] + 1):(stop_i[1] - 1)])
      }
    }
  }

  titles <- trimws(titles)
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = rep("Bainville", length(titles)),
    Posted_Date = rep(NA_character_, length(titles)),
    Link = rep(url, length(titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Chester-Joplin-Inverness Public Schools (Batch 23)
# ---------------------------------------------------------------------------
# The openings are one PDF linked from the employment page ("Click Here to
# view current open positions at CJI!"). The district replaces the PDF and its
# aptg.co short link from time to time: the link hard-coded until 2026-11-05
# (aptg.co/c5tzQ5, "Current Open Positions 7_13_26.pdf") went 404 and every run
# logged "empty". The page renders only in a browser (a plain request gets a
# bot-challenge shell), so the link is read from the rendered page each run.
# A missing link or failed download is an error, not an empty board.
find_cji_positions_link <- function(links) {
  # links: data frame of the page's anchors: text, href, context (the
  # enclosing block's text).
  if (is.null(links) || nrow(links) == 0) return(NA_character_)
  open <- grepl("open positions", links$context, ignore.case = TRUE)
  here <- open & grepl("^(click )?here!?$", trimws(links$text), ignore.case = TRUE)
  named <- grepl("open positions", links$text, ignore.case = TRUE)
  hit <- which(here | named)
  if (length(hit) == 0) return(NA_character_)
  links$href[hit[1]]
}

fetch_cji_postings <- function(chromote_session, url = "https://www.cji.k12.mt.us/page/employmentcji") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  js <- paste0("JSON.stringify(Array.from(document.querySelectorAll('a')).map(a => ({text: a.innerText.trim(), ",
               "href: a.href, context: (a.closest('p,div,li') || a).innerText.slice(0, 300)})))")
  links <- jsonlite::fromJSON(chromote_session$Runtime$evaluate(js)$result$value)
  pdf_url <- find_cji_positions_link(as.data.frame(links))
  if (is.na(pdf_url)) stop("CJI: no 'current open positions' link on the employment page")
  tmp <- tempfile(fileext = ".pdf")
  on.exit(unlink(tmp), add = TRUE)
  resp <- request(pdf_url) %>%
    req_headers("User-Agent" = "Mozilla/5.0") %>%
    perform_with_retry()
  writeBin(resp_body_raw(resp), tmp)
  parse_cji_postings(paste(pdftools::pdf_text(tmp), collapse = "\n"), url)
}

parse_cji_postings <- function(text, url = "https://www.cji.k12.mt.us/page/employmentcji") {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(text)) return(empty)

  lines <- strsplit(text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- gsub("[\u200b\ufeff]", "", lines)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  app_idx <- which(grepl("^Application$", lines, ignore.case = TRUE))
  if (length(app_idx) == 0) return(empty)

  titles <- character(0)
  for (idx in app_idx) {
    if (idx > 1) {
      prev_line <- lines[idx - 1]
      if (!grepl("CJI Current Open Positions|completed resumes", prev_line, ignore.case = TRUE)) {
        titles <- c(titles, prev_line)
      }
    }
  }

  titles <- trimws(titles)
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = rep("Chester", length(titles)),
    Posted_Date = rep(NA_character_, length(titles)),
    Link = rep(url, length(titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# ---------------------------------------------------------------------------
# Marion School District #54 (Batch 23)
# ---------------------------------------------------------------------------
fetch_marion_postings <- function(url = "https://sites.google.com/a/marionschoolmt.com/new-marion-school/district-information/employment") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_marion_postings(html, url)
}

parse_marion_postings <- function(html, url = "https://sites.google.com/a/marionschoolmt.com/new-marion-school/district-information/employment") {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)
  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  lines <- strsplit(html_text2(doc), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_i <- which(grepl("^VACANCIES$", lines, ignore.case = TRUE))
  stop_i <- which(grepl("^DISCLAIMER", lines, ignore.case = TRUE))
  if (length(start_i) == 0 || length(stop_i) == 0 || stop_i[1] <= start_i[1] + 1) return(empty)

  vac_lines <- lines[(start_i[1] + 1):(stop_i[1] - 1)]
  vac_lines <- vac_lines[!grepl("\\.pdf$", vac_lines, ignore.case = TRUE)]
  if (length(vac_lines) == 0) return(empty)

  titles <- character(0)
  for (vl in vac_lines) {
    if (grepl("guest teachers.*pool of substitutes", vl, ignore.case = TRUE)) {
      titles <- c(titles, "Guest Teacher / Pool of Substitutes")
    } else {
      titles <- c(titles, vl)
    }
  }

  titles <- trimws(titles)
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = rep("Marion", length(titles)),
    Posted_Date = rep(NA_character_, length(titles)),
    Link = rep(url, length(titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}

# Lima School District #12 (limaschoolmt.org, Beaverhead County, adopted 2026-10-28 Batch 24).
# District runs Apptegy with job announcements published via Thrillshare Live Feeds API.
# Live feed API: https://thrillshare-cmsv2.services.thrillshare.com/api/v2/s/107780/live_feeds
# Confirmed live 2026-10-28: 3 real active postings.
fetch_lima_postings <- function(url = "https://thrillshare-cmsv2.services.thrillshare.com/api/v2/s/107780/live_feeds") {
  json_str <- tryCatch({
    resp <- request(url) %>%
      req_headers("User-Agent" = "Mozilla/5.0") %>%
      perform_with_retry()
    resp_body_string(resp)
  }, error = function(e) "")
  parse_lima_postings(json_str)
}

parse_lima_postings <- function(json_str, base_url = "https://www.limaschoolmt.org") {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  if (is.null(json_str) || !nzchar(trimws(json_str))) return(empty)

  parsed <- tryCatch(jsonlite::fromJSON(json_str), error = function(e) NULL)
  if (is.null(parsed) || is.null(parsed$live_feeds) || length(parsed$live_feeds) == 0) return(empty)

  feeds <- parsed$live_feeds
  vacancy_idx <- which(grepl("POSITION VACANCY ANNOUNCEMENT", feeds$status, ignore.case = TRUE))
  if (length(vacancy_idx) == 0) return(empty)

  rows <- list()
  for (i in vacancy_idx) {
    status_raw <- feeds$status[i]
    status_text <- gsub("<br[ ]*/?>", "\n", status_raw, ignore.case = TRUE)
    status_text <- gsub("</p>", "\n", status_text, ignore.case = TRUE)
    status_text <- gsub("<[^>]+>", " ", status_text)
    doc_node <- tryCatch(xml2::read_html(paste0("<span>", status_text, "</span>")), error = function(e) NULL)
    if (!is.null(doc_node)) {
      status_text <- xml2::xml_text(doc_node)
    }

    lines <- trimws(strsplit(status_text, "\n")[[1]])
    lines <- lines[nzchar(lines)]

    title <- NA_character_
    pos_title_line <- grep("Position Title:", lines, ignore.case = TRUE, value = TRUE)
    if (length(pos_title_line) > 0) {
      title <- trimws(sub("^Position Title:[[:space:]]*", "", pos_title_line[1], ignore.case = TRUE))
    } else {
      hdr_idx <- which(grepl("POSITION VACANCY ANNOUNCEMENT", lines, ignore.case = TRUE))
      if (length(hdr_idx) > 0 && hdr_idx[1] < length(lines)) {
        title <- lines[hdr_idx[1] + 1]
      }
    }

    posted_date <- if (!is.null(feeds$formatted_date[i])) as.character(as.Date(feeds$formatted_date[i])) else NA_character_

    if (!is.na(title) && nzchar(title)) {
      rows[[length(rows) + 1]] <- data.frame(
        Title = title,
        Location = "Lima",
        Posted_Date = posted_date,
        Link = base_url,
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Joliet Public School District 86 (jolietschools.org, Carbon County, adopted 2026-10-29 Batch 25).
# Re-anchored to real Montana district website replacing stale Illinois SD86 TedK12 link.
# Job openings are displayed in a structured HTML table (table.employment-table) on
# https://www.jolietschools.org/district-information/important-clicks/employment-information.html.
# Confirmed live 2026-10-29: 5 real active postings (Bus Driver, Subs, 3 Coaching positions).
parse_joliet_postings <- function(html_text, url = "https://www.jolietschools.org/district-information/important-clicks/employment-information.html") {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  table <- rvest::html_element(doc, "table.employment-table")
  if (is.null(table)) return(empty)

  rows <- rvest::html_elements(table, "tbody tr")
  if (length(rows) == 0) return(empty)

  res <- lapply(rows, function(r) {
    title <- rvest::html_text2(rvest::html_element(r, ".el-title"))
    if (is.na(title) || !nzchar(trimws(title))) return(NULL)
    title <- trimws(title)

    desc <- rvest::html_text2(rvest::html_element(r, ".el-content"))
    link_el <- rvest::html_element(r, "a.el-link")
    link <- if (!is.null(link_el)) rvest::html_attr(link_el, "href") else url
    if (is.na(link) || !nzchar(link)) link <- url

    if (grepl("coaching", title, ignore.case = TRUE) && !is.na(desc) && nzchar(desc)) {
      lines <- trimws(strsplit(desc, "\n")[[1]])
      coach_titles <- lines[grepl("Coach", lines, ignore.case = TRUE) &
                            !grepl("looking for|positions for", lines, ignore.case = TRUE)]
      if (length(coach_titles) > 0) {
        return(data.frame(
          Title = coach_titles,
          Location = "Joliet",
          Posted_Date = NA_character_,
          Link = link,
          stringsAsFactors = FALSE
        ))
      }
    }

    data.frame(
      Title = title,
      Location = "Joliet",
      Posted_Date = NA_character_,
      Link = link,
      stringsAsFactors = FALSE
    )
  })

  res <- res[!vapply(res, is.null, logical(1))]
  if (length(res) == 0) return(empty)
  do.call(rbind, res)
}

fetch_joliet_postings <- function(url = "https://www.jolietschools.org/district-information/important-clicks/employment-information.html") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_joliet_postings(html, url)
}

# District-level data-completeness classification -- ported from Wyoming's
# own misc_district_coverage_tiers(), adapted to this project's different
# registry shape. Wyoming keeps directly-scraped districts split across two
# registries (a main one for real ATS platforms, a separate
# misc_district_registry for heuristic ones) and cross-checks its heuristic
# tier against WSBA's statewide feed specifically, so it has two distinct
# "Partial" sub-tiers ("WSBA + own page" vs "WSBA only"). Montana has one
# unified k12_district_registry.csv (every directly-scraped district, real
# platform or heuristic, in the same file, differentiated only by its
# Platform column -- see CLAUDE.md's "Scrapers are split by reliability, not
# by K-12/HE"), and OPI-direct dedup already applies uniformly to every
# registered district's rows, not just a heuristic subset -- so there's no
# Wyoming-style two-sub-tier split here, just one "Partial" tier for every
# district whose Platform isn't one of the real ATS platforms this project
# scrapes through an API (direct_api_scrapers.R; Red Rover's in edjobs since
# 0.14.0). Every other
# Platform value (Apptegy and every single-district
# `*Heuristic` platform) is scraped via this file -- misc_district_scrapers.R's
# own header comment already calls this whole file "a real but
# acknowledged-less-reliable source" relative to direct_api_scrapers.R's
# real platform APIs, so this function just makes that existing,
# already-true distinction visible on the dashboard instead of leaving it
# sitting only in code comments.
MT_DIRECT_API_PLATFORMS <- c("AppliTrack", "SchoolSpring", "TedK12", "TylerPortico", "RedRoverK12")

# registry_csv is a parameter (not a hardcoded read) so this stays testable
# against a synthetic registry without touching the real committed file.
# Every district not returned here is implicitly "Full" -- callers coalesce
# a missing match to that, the same convention Wyoming's own version uses.
k12_district_coverage_tiers <- function(registry_csv = "k12_district_registry.csv") {
  registry <- read.csv(registry_csv, stringsAsFactors = FALSE)
  partial <- registry[!(registry$Platform %in% MT_DIRECT_API_PLATFORMS), ]
  data.frame(District = partial$District, Data_Coverage = "Partial", stringsAsFactors = FALSE)
}
