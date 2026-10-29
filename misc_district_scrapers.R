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

# Custer Public Schools (custerschools.org) -- genuinely Finalsite (unlike
# every other district found in the same 2026-08-16 pass, which turned out
# to be Apptegy despite an initial "Finalsite cluster" hypothesis -- see the
# Apptegy section below for the correction). A plain httr2 request works
# fine here, no chromote needed: real postings are a clean `<ul><li>` list
# immediately following a `<p><strong>Job Openings:</strong></p>` marker,
# confirmed live 2026-08-16, 6 real postings.
#
# Use the www. host explicitly: the apex custerschools.org has no A record
# (only www. does), so a plain request to the bare domain intermittently
# fails DNS resolution ("Could not resolve host: custerschools.org") and
# the whole district drops out of that week's data (confirmed 2026-09-01).
fetch_custer_postings <- function(url = "https://www.custerschools.org/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_custer_postings(resp_body_string(resp), url)
}

parse_custer_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  marker <- rvest::html_elements(page, xpath = "//p[strong[contains(text(), 'Job Openings')]]")
  if (length(marker) == 0) return(empty)

  list_node <- rvest::html_element(marker[[1]], xpath = "following-sibling::ul[1]")
  if (is.na(list_node)) return(empty)

  titles <- trimws(rvest::html_text2(rvest::html_elements(list_node, "li")))
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Custer", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
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

# North Star Public Schools (sites.google.com/nsschools.org, serving both
# Rudyard and Gildford -- the OPI feed's "RUDYARD" and "RUDYARD/GILDFORD"
# rows are the same single district) -- found in the same 2026-08-23 pass.
# A modern (published, publicly reachable) Google Sites page -- unlike
# Wyola's own Google Site, which redirects to a Google sign-in wall and is
# genuinely not publicly reachable, confirmed live -- real content renders
# server-side into a plain httr2 fetch, no chromote needed, the same as
# Big Timber's own Google Sites page (declined separately, see this
# session's memory notes, for lacking a repeatable multi-posting
# structure). Real postings sit under 2 real category headers ending in
# ":" ("Substitutes:"/"Transportation:"), the same colon-suffix convention
# as Plevna above; "Elementary Positions"/"MS/HS Positions" are 2 more
# real category headers but with NO colon and no real title beneath them
# (just a "Search North Star Elem - 1233"-style broken job-board-widget
# placeholder line) -- both genuinely empty right now, not a parsing gap,
# excluded for free since only colon-suffixed lines start title
# collection here. Confirmed live 2026-08-23, 2 real postings (Substitute
# Teachers, Bus Drivers). Stops at "Employment Application", the real,
# stable boundary before the document-link section.
NORTHSTAR_STOP_LINE <- "Employment Application"

fetch_northstar_postings <- function(url = "https://sites.google.com/nsschools.org/home/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_northstar_postings(resp_body_string(resp), url)
}

parse_northstar_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "The North Star Public Schools has the following positions open:")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == NORTHSTAR_STOP_LINE)
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  rows <- list()
  current_header <- NA_character_
  for (line in lines) {
    if (grepl(":$", line)) {
      current_header <- sub(":$", "", line)
      next
    }
    if (!is.na(current_header)) {
      rows[[length(rows) + 1]] <- data.frame(Title = line, Location = current_header,
                                              Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Trego School District 53 (sites.google.com, found 2026-08-24 while
# re-checking the OPI-gap candidate list) -- another modern, publicly
# reachable Google Sites page, same as North Star above: real content
# renders server-side into a plain httr2 fetch, no chromote needed. Real
# postings sit under one real flat-list header ("Jobs Available at Trego
# School"), no colon-suffixed sub-categories like North Star -- confirmed
# live 2026-08-24, 2 real postings (Snow Removal, K-1 Teacher). Stops at
# "Report abuse", the same real Google Sites footer boundary North Star
# uses.
TREGO_STOP_LINE <- "Report abuse"

fetch_trego_postings <- function(url = "https://www.tregoschool.org/about-us/our-staff/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_trego_postings(resp_body_string(resp), url)
}

parse_trego_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Jobs Available at Trego School")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == TREGO_STOP_LINE)
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  titles <- lines[nzchar(lines)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Trego", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Baker Public Schools (baker.k12.mt.us, found 2026-08-24 in the first
# pass against OPI's own full district list -- see
# [[mt-dashboard-full-opi-coverage-goal]]) -- Finalsite, same platform
# as Thompson Falls/Hobson/Shepherd above. Real postings sit only under
# "CLASSIFIED POSITIONS AVAILABLE" -- the page's own "CERTIFIED POSITIONS
# AVAILABLE" section explicitly defers entirely to OPI's statewide feed
# ("Please visit our listings on OPI Jobs for Teachers..."), the same
# no-independent-listing pattern as Dodson/Baker's own Certified
# section, deliberately excluded rather than scraped. Confirmed live
# 2026-08-24, 3 real postings. Stops at "All interested parties are to
# fill out...", the real, stable boundary before the application-form
# instructions.
fetch_baker_postings <- function(url = "https://www.baker.k12.mt.us/quick-links/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_baker_postings(resp_body_string(resp), url)
}

parse_baker_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "CLASSIFIED POSITIONS AVAILABLE")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(grepl("^All interested parties", lines))
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  titles <- lines[nzchar(lines)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Baker", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Cut Bank School District #15 (sites.google.com/view/cutbankjobs, found
# 2026-08-24) -- another publicly published Google Sites page, same
# platform as North Star/Trego/Reed Point/Lincoln above -- resolves a
# real candidate left unresolved in an earlier session ("employment URL
# 404'd, needs chromote site nav"; the real URL turned out to be an
# entirely separate `sites.google.com/view/...` site, not a page under
# the district's own main domain). Real postings sit under a
# date-suffixed header ("Open Positions (as of August 13, 2026)"),
# matched by a regex tolerant of the date changing. Confirmed live
# 2026-08-24, 5 real postings. Stops at "Virtual Tours of Cut Bank
# Schools", the real, stable boundary before the school-tour links.
CUTBANK_START_PATTERN <- "^Open Positions \\(as of .+\\)$"

fetch_cutbank_postings <- function(url = "https://sites.google.com/view/cutbankjobs/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_cutbank_postings(resp_body_string(resp), url)
}

parse_cutbank_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(grepl(CUTBANK_START_PATTERN, lines))
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "Virtual Tours of Cut Bank Schools")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  titles <- lines[nzchar(lines)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Cut Bank", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
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

# St Regis School District (stregisschool.org, found 2026-08-24) --
# Apptegy, plain httr2 fetch is NOT sufficient here (needs chromote like
# most Apptegy pages), 3 real category headers (Stipend Extracurricular/
# Part-Time/Full-Time, plus a headerless "Substitute Positions Opened"
# block), most titles a flat one-per-line list, but 2 of them
# (Bus Route Driver, Groundskeeper) are "Title - description" combined
# on one line -- split on " - " and keep only the part before it, same
# technique for both shapes rather than two separate branches. Confirmed
# live 2026-08-24, 14 real postings across all 4 sections ("Full-Time
# Position:" itself is genuinely empty, correctly contributing 0 rows).
# Trailing non-breaking spaces (U+00A0) show up throughout this page's
# own authored content, same class of issue as Chinook/Lolo, stripped
# explicitly. Stops at the real "Substitute wage is..." sentence, the
# stable boundary before contact info.
STREGIS_NBSP <- intToUtf8(160)
STREGIS_HEADERS <- c("Stipend Extracurricular Positions Open:", "Part-Time Position:", "Full-Time Position:", "Substitute Positions Opened")

parse_stregis_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- gsub(STREGIS_NBSP, "", lines, fixed = TRUE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "OPEN POSITIONS")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(grepl("^Substitute wage is", lines))
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  lines <- lines[!(lines %in% STREGIS_HEADERS)]

  titles <- vapply(lines, function(line) {
    if (grepl(" - ", line, fixed = TRUE)) {
      trimws(strsplit(line, " - ", fixed = TRUE)[[1]][1])
    } else {
      line
    }
  }, character(1), USE.NAMES = FALSE)

  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "St Regis", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_stregis_postings <- function(chromote_session, url = "https://www.stregisschool.org/page/employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_stregis_postings(text, url)
}

# Valier School District #18 (Google Sites, found 2026-08-24) -- 3
# separate categories (Teaching/Classified/Coaches) each with their own
# real "Valier Schools is currently seeking applicants for...:" marker
# sentence, immediately followed by either a real title or the literal
# "None at this time" empty state -- Teaching and Coaches are genuinely
# empty right now, only Classified has 1 real posting. This takes just
# the single line immediately after each marker as that category's
# title, which is all that's needed for every category confirmed live
# 2026-08-24 (none had more than 1 real title at once) -- would need
# generalizing to a real per-category list if a future check finds a
# category with more than one real opening at a time.
VALIER_MARKER_PATTERN <- "^Valier Schools is currently seeking applicants for"

fetch_valier_postings <- function(url = "https://www.valier.k12.mt.us/about-us/Employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_valier_postings(resp_body_string(resp), url)
}

parse_valier_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  marker_idx <- which(grepl(VALIER_MARKER_PATTERN, lines))
  marker_idx <- marker_idx[marker_idx < length(lines)]
  if (length(marker_idx) == 0) return(empty)

  titles <- lines[marker_idx + 1]
  titles <- titles[titles != "None at this time"]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Valier", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
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

  page <- rvest::read_html(html_text)
  titles <- rvest::html_text2(rvest::html_elements(page, "table.uk-table tbody tr .el-title"))
  titles <- trimws(titles)
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Roberts", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Florence-Carlton School District 15-6 (florencecarlton.org, found
# 2026-08-24) -- Apptegy, but its real employment page URL isn't a plain
# nav link (found instead by following the page's own "CLICK HERE TO
# VIEW AVAILABLE POSITIONS" link). A genuinely rich page: 3 "OPEN X
# Positions" categories (Administrator/Certified/Classified) each with a
# real title-then-full-job-description block, a separate "OPEN Coaching
# Positions" category with 3 more such blocks, and a flat "Substitutes"
# list at the end -- too heterogeneous for one marker-based rule, so
# this uses a title-shape heuristic instead: real titles are short
# (<=90 chars), ALL-CAPS-or-title-case-with-no-lowercase-only-words
# lines that don't end in ":" and aren't the "PLEASE COMPLETE..."
# submission-instructions sentence (also ALL-CAPS, but always much
# longer and always ending differently) -- confirmed against every real
# posting on this page live 2026-08-24. One posting spans 2 lines
# ("SEEKING TWO (2) EVENING SHIFT SCHOOL CUSTODIANS" / "AND ONE (1) MID
# SHIFT SCHOOL CUSTODIAN"), merged into one title by detecting the
# "AND "-continuation line. The flat "Substitutes" list at the end is
# Title Case, not ALL-CAPS, so it's extracted separately as a normal
# flat list. Confirmed live 2026-08-24, 9 real postings (1 Certified +
# 1 Classified [2 openings] + 3 Coaching + 4 Substitute categories).
# Trailing non-breaking spaces (U+00A0) are pervasive in this page's own
# authored content, the same class of issue as Chinook/Lolo/St Regis,
# stripped explicitly.
FLORENCECARLTON_NBSP <- intToUtf8(160)

looks_like_florencecarlton_title <- function(line) {
  if (nchar(line) > 90) return(FALSE)
  if (grepl(":$", line)) return(FALSE)
  if (grepl("^PLEASE COMPLETE", line)) return(FALSE)
  if (!grepl("^[A-Z0-9][A-Z0-9 ().,'&/-]*$", line)) return(FALSE)
  if (!grepl("[A-Z]{2,}", line)) return(FALSE)
  TRUE
}

parse_florencecarlton_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- gsub(FLORENCECARLTON_NBSP, " ", lines, fixed = TRUE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "District Open Positions/Equal Employment, Equal Education")
  stop_idx <- which(lines == "Equal Employment, Equal Education")
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)
  body <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]

  caps_titles <- body[vapply(body, looks_like_florencecarlton_title, logical(1))]
  merged <- character(0)
  for (t in caps_titles) {
    if (grepl("^AND ", t) && length(merged) > 0) {
      merged[length(merged)] <- paste(merged[length(merged)], t)
    } else {
      merged <- c(merged, t)
    }
  }

  sub_idx <- which(body == "Substitutes")
  sub_titles <- character(0)
  if (length(sub_idx) > 0) {
    remaining <- body[(sub_idx[1] + 1):length(body)]
    stop2 <- which(grepl("^If interested please submit", remaining))
    if (length(stop2) > 0) remaining <- remaining[seq_len(stop2[1] - 1)]
    remaining <- remaining[!grepl("^We need substitutes", remaining)]
    sub_titles <- remaining[nzchar(remaining)]
  }

  titles <- c(merged, sub_titles)
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Florence-Carlton", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_florencecarlton_postings <- function(chromote_session, url = "https://www.florencecarlton.org/page/available-positions-equal-employment-equal-education") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_florencecarlton_postings(text, url)
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

# West Yellowstone School (wolverine.life, found 2026-08-24) -- Apptegy,
# gated behind a JS "Client Challenge" bot-check that plain httr2/curl
# can't pass, same as Victor below, so this needs a real chromote render
# like the other Apptegy districts. One flat list of 5 real postings
# under "Classified Positions for 2026-2027 School Year:", stopping at
# the "Please contact Superintendent..." closing sentence. The first
# item's own hyperlinked "Job Description"/"Vacancy" link labels run
# straight into the title text with no space in innerText (e.g. "Food
# Service Worker (...)- Job Description, Vacancy"), stripped by pattern.
# "Extra-Curricular Positions for 2026-2027 School Year" is itself one
# real posting (a single hyperlink to its own job description doc), not
# a second category header -- confirmed live 2026-08-24 there's no list
# beneath it, matching the flat single-list structure of the whole page.
WESTYELLOWSTONE_SUFFIX_PATTERN <- "-\\s*Job Description.*$"

parse_westyellowstone_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Classified Positions for 2026-2027 School Year:")
  stop_idx <- which(grepl("^Please contact Superintendent", lines))
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)
  body <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]

  titles <- trimws(sub(WESTYELLOWSTONE_SUFFIX_PATTERN, "", body))
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "West Yellowstone", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_westyellowstone_postings <- function(chromote_session, url = "https://wolverine.life/page/employment-opportunities") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_westyellowstone_postings(text, url)
}

# Bonner School District #14 (bonner.k12.mt.us, found 2026-08-25) --
# Apptegy. One flat list of real titles under "CURRENT OPENINGS", stops
# at "Application Forms" (generic evergreen application-form links, not
# real postings). Confirmed live 2026-08-25, 1 real posting ("Substitute
# Teachers, always hiring!"). Basin School District and Bynum School are
# both same-named-elsewhere traps (Idaho City, ID and Midland, TX
# respectively) -- their real Montana counterparts have no independent
# web presence found, declined.
parse_bonner_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "CURRENT OPENINGS")
  stop_idx <- which(lines == "Application Forms")
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)
  titles <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Bonner", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_bonner_postings <- function(chromote_session, url = "https://www.bonner.k12.mt.us/o/bonner-school-district-14/page/employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_bonner_postings(text, url)
}

# Deer Park School (deerpark.k12.mt.us, found 2026-08-25) -- Apptegy.
# 2 fixed category headers ("CERTIFIED STAFF OPENINGS"/"CLASSIFIED STAFF
# OPENINGS"), each followed by either the literal empty-marker "*No
# current openings*" or real content, stopping at the "Find Us" footer.
# The one boilerplate "Certified Application" link-label line and the
# "Please submit..." instruction sentences are filtered explicitly.
# Confirmed live 2026-08-25: Certified is empty, Classified has 1 real
# posting ("Substitute Teacher Application (Pay DOE)" -- the district's
# own phrasing folds the role and its pay note into one title line, kept
# as-is rather than stripped, since there's no separate plain "Substitute
# Teacher" line to prefer).
DEERPARK_SECTIONS <- c("CERTIFIED STAFF OPENINGS", "CLASSIFIED STAFF OPENINGS")

parse_deerpark_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == DEERPARK_SECTIONS[1])
  stop_idx <- which(lines == "Find Us")
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)
  body <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]

  body <- body[!(body %in% DEERPARK_SECTIONS)]
  body <- body[body != "*No current openings*"]
  body <- body[!grepl("^Please submit", body)]
  body <- body[body != "Certified Application"]

  titles <- body[nzchar(body)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Deer Park", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_deerpark_postings <- function(chromote_session, url = "https://www.deerpark.k12.mt.us/page/employment-opportunities") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_deerpark_postings(text, url)
}

# Evergreen School District #50 (evergreensd50.com, found 2026-08-25) --
# Apptegy. One flat list of 5 real titles under "CLASSIFIED:", stops at
# the "All application materials must be submitted..." closing
# sentence -- no "CERTIFIED:" section currently shown at all (not even
# an empty one). Confirmed live 2026-08-25, 5 real postings.
parse_evergreen_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "CLASSIFIED:")
  stop_idx <- which(grepl("^All application materials must be submitted", lines))
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)
  titles <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Evergreen", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_evergreen_postings <- function(chromote_session, url = "https://www.evergreensd50.com/page/employment-opportunities") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_evergreen_postings(text, url)
}

# Lone Rock School District (lonerockschool.org, found 2026-08-25) --
# Apptegy, real slug is "/page/employment" (a bare "/employment" 404s).
# The 1 real posting under "Classified Positions:" is the single line
# immediately after the header, stopping before the trailing description
# paragraph and the "District Employment Applications." boilerplate
# link. The page also has a substitute-teacher recruiting section
# listing 6 sub-categories (bus driver/classroom/custodial/kitchen/
# office staff/para professional substitutes) as one free-running prose
# sentence with no clean per-item title boundary -- declined as
# genuinely unstructured, same bar as the Rapelje/Grass Range precedent,
# so only the Classified Positions postings are extracted.
#
# 2026-09-22 break: the district renamed the "District Employment
# Applications." link to "Classified Employee Application" and added a
# second posting, so the old single stop line vanished and the parser
# returned 0 for two weeks. The list now ends at whichever comes first of
# the "If selected, ..." paragraph (present in both layouts) or either
# application-link line, and every line in between is a posting.
parse_lonerock_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Classified Positions:")
  if (length(start_idx) == 0) return(empty)
  is_stop <- grepl("^If selected,", lines) |
    lines %in% c("District Employment Applications.", "Classified Employee Application")
  stop_idx <- which(is_stop & seq_along(lines) > start_idx[1])
  if (length(stop_idx) == 0 || stop_idx[1] == start_idx[1] + 1) return(empty)
  body <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]

  data.frame(Title = body, Location = "Lone Rock", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_lonerock_postings <- function(chromote_session, url = "https://www.lonerockschool.org/page/employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_lonerock_postings(text, url)
}

# Sweet Grass County High School / Big Timber (sgchs.com, found 2026-10-20) --
# Apptegy. Category headings match "^Open .* Positions$" (e.g. "Open Coaching
# Positions", "Open Bus Driving Positions", "Open Teaching Positions"), with
# real titles listed beneath each section, terminating at the "Find Us" /
# "Quick Links" footer. Application instructions above the open positions
# are excluded. Confirmed live 2026-10-20, 5 real postings (Assistant Boys
# Basketball Coach, ROUTE BUS DRIVERS, SUBSTITUTE BUS DRIVER, TRANSPORTATION
# MAINTENANCE SUPERVISOR, SUBSTITUTE TEACHERS).
parse_bigtimber_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(grepl("^Open .* Positions$", lines, ignore.case = TRUE))
  if (length(start_idx) == 0) return(empty)

  first_start <- start_idx[1]
  stop_idx <- which(lines %in% c("Find Us", "Quick Links"))
  last_end <- if (length(stop_idx) > 0 && any(stop_idx > first_start)) {
    min(stop_idx[stop_idx > first_start]) - 1
  } else {
    length(lines)
  }

  if (last_end < first_start) return(empty)

  body <- lines[first_start:last_end]
  titles <- body[!grepl("^Open .* Positions$", body, ignore.case = TRUE)]
  titles <- titles[!grepl("^(none|no open|no current)", titles, ignore.case = TRUE)]
  titles <- titles[nzchar(titles)]

  if (length(titles) == 0) return(empty)

  data.frame(
    Title = titles,
    Location = "Big Timber",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

fetch_bigtimber_postings <- function(chromote_session, url = "https://www.sgchs.com/page/employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_bigtimber_postings(text, url)
}

# Dixon School District #9 (dixonschool.org, a publicly published Google
# Sites page, found 2026-08-25) -- plain httr2 fetch. 3 real postings,
# 2 different marker-line-immediately-after-title shapes on the same
# page: the 1 real detailed job posting is followed by "Posting: ...",
# while the 2 standing recruitment titles ("Certified Substitute
# Teacher", "Substitute Teachers") are each followed by a "Please
# complete the ... Application and send it to ..." sentence -- both
# patterns matched with a single combined regex, same
# marker-immediately-after-title spirit as Ennis's "Reports to:"
# technique above. Confirmed live 2026-08-25, 3 real postings.
fetch_dixon_postings <- function(url = "https://www.dixonschool.org/about-dixon-school/employment-opportunities") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_dixon_postings(resp_body_string(resp), url)
}

parse_dixon_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Current Open Positions")
  stop_idx <- which(lines == "Equal Opportunity Employer")
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)
  body <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]

  marker_idx <- which(grepl("^Posting:", body) | grepl("^Please complete the .* Application and send it to", body))
  marker_idx <- marker_idx[marker_idx > 1]
  titles <- unique(body[marker_idx - 1])
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Dixon", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Elysian School District #23 (a publicly published Google Sites page,
# found 2026-08-25) -- plain httr2 fetch. The page's "District
# Employment" section explicitly defers all non-substitute openings to
# OPI's own site ("For a complete list of our current openings please
# visit OPI's website"), same shape as the prior-session Dodson decline
# -- but unlike Dodson, this page also has its own standing "Guest
# Teachers (substitutes)" recruitment section, matching this project's
# established "bare category name = real posting" convention for
# standing substitute-recruiting sections (Winnett/Florence-Carlton/
# Creston). Confirmed live 2026-08-25: exactly 1 real posting.
fetch_elysian_postings <- function(url = "https://sites.google.com/a/elysianschool.org/ely23/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_elysian_postings(resp_body_string(resp), url)
}

parse_elysian_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  if (!("Guest Teachers (substitutes)" %in% lines)) return(empty)

  data.frame(Title = "Guest Teachers (substitutes)", Location = "Elysian", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Fair-Mont-Egan Schools (fmemontana.net, a publicly published Google
# Sites page, found 2026-08-25) -- plain httr2 fetch. Same 3-fixed-
# category shape as Deer Park/Creston (Administrative/Certified/
# Classified, each either "No positions are currently available" or
# real content), but here a category can hold more than one real
# posting, so this walks all 3 category positions and takes each
# category's own content window rather than just checking the single
# next line. Each real title's own "[X] Job Description/Application
# Directions" and "[Category] Application" boilerplate lines are
# filtered out. Confirmed live 2026-08-25: Administrative and Certified
# are both empty, Classified has 2 real postings.
FAIRMONTEGAN_CATEGORIES <- c("Administrative", "Certified", "Classified")

fetch_fairmontegan_postings <- function(url = "https://www.fmemontana.net/human-resources/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_fairmontegan_postings(resp_body_string(resp), url)
}

parse_fairmontegan_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  stop_idx <- which(lines == "Non-Discrimination Policy")
  if (length(stop_idx) == 0) return(empty)
  cat_idx <- which(lines[seq_len(stop_idx[1] - 1)] %in% FAIRMONTEGAN_CATEGORIES)
  cat_idx <- utils::tail(cat_idx, length(FAIRMONTEGAN_CATEGORIES))
  if (length(cat_idx) < length(FAIRMONTEGAN_CATEGORIES)) return(empty)

  bounds <- c(cat_idx, stop_idx[1])
  titles <- character(0)
  for (i in seq_along(cat_idx)) {
    seg <- lines[(bounds[i] + 1):(bounds[i + 1] - 1)]
    seg <- seg[seg != "No positions are currently available"]
    seg <- seg[!grepl("Job Description/Application Directions$", seg)]
    seg <- seg[!grepl("^(Administrative|Certified|Classified) Application$", seg)]
    seg <- seg[nzchar(seg)]
    titles <- c(titles, seg)
  }
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Fair-Mont-Egan", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Lustre District 23 (lustregradeschool.com, a publicly published Google
# Sites page, found 2026-08-25) -- plain httr2 fetch. Real postings are
# listed as bare PDF filename link labels (e.g. "Part-time Bus
# Driver.pdf"), not clean prose titles -- the trailing ".pdf" is
# stripped. Stops before the school's own address/phone line. Confirmed
# live 2026-08-25, 3 real postings.
fetch_lustre_postings <- function(url = "https://www.lustregradeschool.com/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_lustre_postings(resp_body_string(resp), url)
}

parse_lustre_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Employment Opportunities")
  stop_idx <- which(grepl("Lustre Grade Lane", lines))
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)
  body <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]
  body <- body[grepl("\\.pdf$", body)]
  titles <- sub("\\.pdf$", "", body)
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Lustre", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

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

# Broadus Public Schools (broadus.net, found 2026-10-21) -- Powder River County
# district on a published Google Sites page. Confirmed live 2026-10-21:
# 4 real active postings under h3 headings (Activity Bus Drivers, JH/HS SPED Teacher,
# Assistant Cook, Substitute Teachers).
fetch_broadus_postings <- function(url = "https://www.broadus.net/job-openings") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_broadus_postings(resp_body_string(resp), url)
}

parse_broadus_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  h3s <- rvest::html_elements(page, "h3")
  titles <- trimws(rvest::html_text(h3s))
  titles <- titles[nzchar(titles)]

  titles <- titles[!grepl("Application$", titles, ignore.case = TRUE)]
  titles <- sub("[[:space:]]+-[[:space:]]+[$][0-9]+/day$", "", titles)
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Broadus", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
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

# Hot Springs School District (hssdmt.org, found 2026-10-21) -- Sanders County
# district running Apptegy. Real postings sit under ALL-CAPS section headers
# (CERTIFIED JOB OPENINGS, CLASSIFIED JOBS OPENINGS, EXTRA CURRICULAR JOB OPENINGS).
# Confirmed live 2026-10-21: 8 real active postings. Handled via the shared
# chromote session in fetch_apptegy_k12_postings().
fetch_hotsprings_postings <- function(chromote_session, url = "https://www.hssdmt.org/page/district-employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_hotsprings_postings(text, url)
}

HOTSPRINGS_SECTION_HEADERS <- c(
  "ADMINISTRATIVE JOB OPENINGS",
  "CERTIFIED JOB OPENINGS",
  "CLASSIFIED JOBS OPENINGS",
  "EXTRA CURRICULAR JOB OPENINGS"
)
HOTSPRINGS_STOP_LINES <- c("All Deadlines:", "Find Us", "Hot Springs School District")

parse_hotsprings_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  if (is.null(rendered_text) || !nzchar(rendered_text)) return(empty)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  in_jobs <- FALSE
  titles <- character(0)

  for (line in lines) {
    if (line %in% HOTSPRINGS_SECTION_HEADERS) {
      in_jobs <- TRUE
      next
    }
    if (in_jobs && (line %in% HOTSPRINGS_STOP_LINES || grepl("^All Deadlines:", line))) {
      in_jobs <- FALSE
      break
    }
    if (in_jobs) {
      # exclude contact names / phone numbers
      if (!grepl("^(Contact|Mike Cutler|Superintendent|Sam Hoff|Jim Lawson|[(]406[)])", line)) {
        titles <- c(titles, line)
      }
    }
  }

  if (length(titles) == 0) return(empty)
  data.frame(Title = titles, Location = "Hot Springs", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Frenchtown K-12 Schools (ftsd.org, Missoula County, adopted 2026-10-28 Batch 24).
# District website runs Apptegy behind Fastly. Headless chromote navigates directly.
# Employment page: https://www.ftsd.org/page/open-employment-opportunities/
# Confirmed live 2026-10-28: 6 real active postings. Handled via the shared
# chromote session in fetch_apptegy_k12_postings().
fetch_frenchtown_postings <- function(chromote_session, url = "https://www.ftsd.org/page/open-employment-opportunities/") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_frenchtown_postings(text, url)
}

parse_frenchtown_postings <- function(rendered_text, url = "https://www.ftsd.org/page/open-employment-opportunities/") {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  if (is.null(rendered_text) || !nzchar(trimws(rendered_text))) return(empty)

  lines <- trimws(strsplit(rendered_text, "\n")[[1]])
  lines <- lines[nzchar(lines)]

  start_idx <- which(grepl("OPEN EMPLOYMENT OPPORTUNITIES", lines, ignore.case = TRUE))
  stop_idx <- which(lines == "Find Us" | grepl("^Frenchtown School District$", lines))

  if (length(start_idx) == 0) return(empty)

  valid_stops <- stop_idx[stop_idx > start_idx[1]]
  end_pos <- if (length(valid_stops) > 0) valid_stops[1] - 1 else length(lines)
  if (end_pos <= start_idx[1]) return(empty)

  window <- lines[(start_idx[1] + 1):end_pos]
  ignore_patterns <- "^(Employment/Current Open Positions|Job Application|Certified Application|Classified Application|Coaching Application)$"
  window <- window[!grepl(ignore_patterns, window, ignore.case = TRUE)]

  if (length(window) == 0) return(empty)

  data.frame(
    Title = window,
    Location = "Frenchtown",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# Highwood Public Schools (highwood.k12.mt.us, found 2026-10-21 via OPI Directory) --
# Chouteau County rural district on CyberSchool CMS. Positions sit within
# .listItem_holder with clean .listItem_heading, .listItem_metaPostedDate, and
# .listItem_headingLink. Confirmed live 2026-10-21: 4 active postings (Route or
# Substitute Expedition Driver, Route Activity or Substitute Bus Drivers,
# Janitorial, Substitute Teachers). Plain httr2 fetch, no chromote needed.
fetch_highwood_postings <- function(url = "https://www.highwood.k12.mt.us/District/Jobs/") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_highwood_postings(resp_body_string(resp), url)
}

parse_highwood_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  holders <- rvest::html_elements(page, ".listItem_holder")
  if (length(holders) == 0) return(empty)

  titles <- trimws(rvest::html_text(rvest::html_element(holders, ".listItem_heading")))
  raw_dates <- trimws(rvest::html_text(rvest::html_element(holders, ".listItem_metaPostedDate")))
  clean_dates <- sub(" 12:00:00 AM", "", raw_dates)
  clean_dates <- sub("^[A-Za-z]+, ", "", clean_dates)
  clean_dates[!nzchar(clean_dates)] <- NA_character_

  hrefs <- rvest::html_attr(rvest::html_element(holders, ".listItem_headingLink"), "href")
  valid <- nzchar(titles) & !is.na(titles)
  if (!any(valid)) return(empty)

  titles <- titles[valid]
  clean_dates <- clean_dates[valid]
  hrefs <- hrefs[valid]
  links <- vapply(hrefs, function(h) xml2::url_absolute(h, url), character(1), USE.NAMES = FALSE)

  data.frame(Title = titles, Location = "Highwood", Posted_Date = clean_dates, Link = links, stringsAsFactors = FALSE)
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

# Cardwell Elementary School (cardwellschool.org, found 2026-10-21 via OPI Directory) --
# Jefferson County rural K-8 school on Published Google Sites. Openings sit
# under "Open Positions for the [year] school year:" in paragraph elements.
# Confirmed live 2026-10-21: 1 active posting (1st and 2nd Grade Classroom Teacher (in January)).
# Plain httr2 fetch, no chromote needed.
fetch_cardwell_postings <- function(url = "https://sites.google.com/cardwellschool.org/cougars/join-cardwell") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_cardwell_postings(resp_body_string(resp), url)
}

parse_cardwell_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  ps <- rvest::html_elements(page, "p")
  p_texts <- trimws(rvest::html_text(ps))
  open_idx <- which(grepl("Open Positions", p_texts))
  if (length(open_idx) == 0) return(empty)

  titles <- character(0)
  for (idx in (open_idx[1] + 1):min(open_idx[1] + 5, length(p_texts))) {
    txt <- p_texts[idx]
    if (grepl("Teacher|Custodian|Driver|Cook|Aide|Para|Principal", txt, ignore.case = TRUE) &&
        !grepl("Application|Email|Facebook|Supervising", txt, ignore.case = TRUE)) {
      titles <- c(titles, txt)
    }
  }

  if (length(titles) == 0) return(empty)
  data.frame(Title = titles, Location = "Cardwell", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
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

# Culbertson School District 17-C (culbertsonschool.com, found
# 2026-08-24) -- Finalsite, same platform as Shepherd/Roberts's shared
# family above, plain httr2 fetch. The page groups postings under 3
# headers ("Employment Opportunities: Certified Positions"/"...Classified
# Positions"/"Roos-Valley Special Education Cooperative"), but Certified
# and the Roos-Valley Coop are both genuinely empty right now -- each has
# only its own boilerplate "[X] Application" link line and no actual
# title, confirmed live 2026-08-24. Only Classified currently has 2 real
# titles ("Substitute Teachers", "Activity Bus Drivers"). Boilerplate
# application-link lines are filtered by containing the word
# "Application" anywhere (not just as a suffix, since one of them --
# "Certified Application Roos-Valley Coop" -- has real words after it).
CULBERTSON_HEADER_PATTERN <- "^Employment Opportunities:"

fetch_culbertson_postings <- function(url = "https://www.culbertsonschool.com/about-us/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_culbertson_postings(resp_body_string(resp), url)
}

parse_culbertson_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- gsub(intToUtf8(160), " ", lines, fixed = TRUE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(grepl("^Employment Opportunities: Certified Positions$", lines))
  stop_idx <- which(lines == "Please complete and return to:")
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)
  body <- lines[start_idx[1]:(stop_idx[1] - 1)]

  body <- body[!grepl(CULBERTSON_HEADER_PATTERN, body)]
  body <- body[body != "Open until filled"]
  body <- body[!grepl("Application", body, fixed = TRUE)]
  body <- body[body != "Roos-Valley Special Education Cooperative"]

  titles <- body[nzchar(body)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Culbertson", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Cottonwood School District #57 (a publicly published Google Sites
# page, found 2026-08-24) -- same platform as Lincoln/Independent above,
# plain httr2 fetch. "Job Openings" appears 3 times as a plain nav link
# (each followed by "Staff") before the 4th, real occurrence as the page
# heading -- picking the *last* match avoids the nav links. Currently
# genuinely empty ("There are currently no job openings for Cottonwood
# School District #57"), confirmed live 2026-08-24 -- that exact sentence
# is filtered out explicitly so this returns 0 real rows now but is
# ready to pick up real titles the same way once any appear.
fetch_cottonwood57_postings <- function(url = "https://www.cottonwood57.org/job-openings") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_cottonwood57_postings(resp_body_string(resp), url)
}

parse_cottonwood57_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  job_idx <- which(lines == "Job Openings")
  stop_idx <- which(grepl("^Google Sites", lines))
  if (length(job_idx) == 0 || length(stop_idx) == 0) return(empty)
  start_idx <- job_idx[length(job_idx)]
  if (start_idx >= stop_idx[1]) return(empty)
  body <- lines[(start_idx + 1):(stop_idx[1] - 1)]
  body <- body[!grepl("^There are currently no job openings", body)]

  titles <- body[nzchar(body)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Cottonwood", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
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

# Lincoln School District #38 (sites.google.com, found 2026-08-24) --
# another publicly published Google Sites page, same platform as North
# Star/Trego/Reed Point above, but with only 1 genuine real posting
# right now ("Para Professional Job Opening") rather than a repeatable
# category-header list -- confirmed live 2026-08-24 there's no other
# structural marker to generalize from yet, so this parses a single
# fixed window between the real "CLICK HERE FOR APPLICATION" link-label
# line and the real closing prose sentence, same spirit as North Star's
# single-category case but with only one line inside the window instead
# of several.
LINCOLN_STOP_LINE <- "Please inquire at 406-362-4201 for current employment opportunities."

fetch_lincoln_postings <- function(url = "https://sites.google.com/a/lincoln.k12.mt.us/webpage2/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_lincoln_postings(resp_body_string(resp), url)
}

parse_lincoln_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "CLICK HERE FOR APPLICATION")
  if (length(start_idx) == 0) return(empty)
  stop_idx <- which(lines == LINCOLN_STOP_LINE)
  if (length(stop_idx) == 0 || stop_idx[1] <= start_idx[1] + 1) return(empty)

  titles <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Lincoln", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Independent School (independent.k12.mt.us, north of Billings, found
# 2026-08-24) -- a real public county school district, despite the name
# reading like a private school ("INDEPENDENT SCHOOL - BILLINGS" in the
# OPI feed) -- confirmed live via its own real address, phone, and
# superintendent contact. Another publicly published Google Sites page,
# same platform as North Star/Trego/Reed Point/Lincoln above, but with a
# genuinely different real shape: 3 real postings are each an ALL-CAPS
# short title line immediately followed by a long prose paragraph, no
# colon/dash suffix convention -- matched by an all-caps-short-line
# heuristic instead, since there's no other real structural marker to
# anchor on. Confirmed live 2026-08-24, 3 real postings (Special
# Education Teacher, School Counselor, Substitutes Wanted). Starts after
# "JOB OPENINGS", stops at the real "Report abusePage details" Google
# Sites footer boundary.
looks_like_independent_title <- function(line) {
  if (nchar(line) > 60) return(FALSE)
  if (!grepl("^[A-Z0-9 &'/.-]+$", line)) return(FALSE)
  if (!grepl("[A-Z]", line)) return(FALSE)
  TRUE
}

fetch_independent_postings <- function(url = "https://www.independent.k12.mt.us/job-openings") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_independent_postings(resp_body_string(resp), url)
}

parse_independent_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "JOB OPENINGS")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "Report abusePage details")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  titles <- lines[vapply(lines, looks_like_independent_title, logical(1))]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Independent", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Shepherd School District #37 (shepherd.k12.mt.us, found 2026-08-24) --
# Finalsite, same platform as Thompson Falls/Hobson above, but a genuine
# multi-category flat-list template unlike either of those: 4 real
# category headers (Administrator/Certified Teaching/Classified/
# Coaching Positions), each followed directly by 0+ short title lines
# with no per-category boilerplate to filter -- reuses the Hays-Lodge
# Pole/Dutton title-shape heuristic (length cap, no trailing "."/":")
# to separate real titles from the longer prose sentences (application
# instructions, substitute-role blurbs) interleaved between categories.
# Confirmed live 2026-08-24, 18 real postings (0 Administrator, 5
# Certified, 4 Classified, 9 Coaching -- "Assistant High School
# Wrestling Coach" is a real, genuinely duplicated title, kept as 2 rows
# the same way Wolf Point's own duplicates are). Stops at the line
# beginning "Shepherd School District #37 does not discriminate", the
# real, stable boundary before contact info.
SHEPHERD_CATEGORIES <- c("Administrator Positions:", "Certified Teaching Positions:", "Classified Positions:", "Coaching Positions:")

looks_like_shepherd_title <- function(line) {
  if (nchar(line) > 55) return(FALSE)
  if (grepl("[.:]$", line)) return(FALSE)
  if (!grepl("[A-Za-z]", line)) return(FALSE)
  TRUE
}

fetch_shepherd_postings <- function(url = "https://www.shepherd.k12.mt.us/dist-office/jobs/overview") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_shepherd_postings(resp_body_string(resp), url)
}

parse_shepherd_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == SHEPHERD_CATEGORIES[1])
  if (length(start_idx) == 0) return(empty)
  stop_idx <- which(grepl("^Shepherd School District #37 does not discriminate", lines))
  if (length(stop_idx) == 0) return(empty)
  lines <- lines[start_idx[1]:(stop_idx[1] - 1)]

  rows <- list()
  current_category <- NA_character_
  for (line in lines) {
    if (line %in% SHEPHERD_CATEGORIES) {
      current_category <- sub(":$", "", line)
      next
    }
    if (!is.na(current_category) && looks_like_shepherd_title(line)) {
      rows[[length(rows) + 1]] <- data.frame(Title = line, Location = current_category,
                                              Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
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

# Swan River School District #4 (swanriverschool.org, Bigfork, found
# 2026-08-24) -- WordPress, plain httr2 fetch, but a genuinely different
# shape than Ramsay/Turner/Terry above: 6 real category headers marked
# `<strong><u>Label</u>...</strong>` in the raw HTML (colon placed
# inconsistently either inside or outside the </u> tag depending on
# category, so matched loosely and stripped after capture), each
# followed by either plain prose, a real "No positions open at this
# time." empty state, or (Substitute Positions only) a real `<li>` list
# -- html_text2() collapses this whole block into a couple of very long
# unbroken lines with no newlines between category label and body, so
# this is parsed by regex-splitting the RAW HTML on the header markup
# itself (not the post-html_text2 plain text like every other heuristic
# in this file), then stripping tags from each resulting body segment
# separately. Confirmed live 2026-08-24, 5 real postings across 3
# non-empty categories (Substitute/Aide/Classified); Certified/Coaching/
# Administrative are genuinely empty right now, not a parsing gap.
SWANRIVER_EMPTY_TEXT <- "No positions open at this time."
SWANRIVER_STOP <- "Swan River School is an Equal Opportunity Employer"
SWANRIVER_HEADER_PATTERN <- "<strong><u>\\s*([^<]*?)\\s*</u>:?\\s*</strong>:?"

fetch_swanriver_postings <- function(url = "https://www.swanriverschool.org/human-resources/") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_swanriver_postings(resp_body_string(resp), url)
}

parse_swanriver_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  start_pos <- regexpr("<strong><u>\\s*Certified Positions", html_text, perl = TRUE)
  if (start_pos < 0) return(empty)
  stop_pos <- regexpr(SWANRIVER_STOP, html_text, fixed = TRUE)
  if (stop_pos < 0) return(empty)
  segment <- substr(html_text, start_pos, stop_pos - 1)

  matches <- gregexpr(SWANRIVER_HEADER_PATTERN, segment, perl = TRUE)[[1]]
  if (matches[1] < 0) return(empty)
  match_lens <- attr(matches, "match.length")
  labels <- regmatches(segment, gregexpr(SWANRIVER_HEADER_PATTERN, segment, perl = TRUE))[[1]]
  labels <- sub(SWANRIVER_HEADER_PATTERN, "\\1", labels, perl = TRUE)
  labels <- sub(":$", "", trimws(labels))

  rows <- list()
  for (i in seq_along(matches)) {
    body_start <- matches[i] + match_lens[i]
    body_end <- if (i < length(matches)) matches[i + 1] - 1 else nchar(segment)
    body_html <- substr(segment, body_start, body_end)
    body_page <- rvest::read_html(paste0("<div>", body_html, "</div>"))
    body_lines <- strsplit(trimws(rvest::html_text2(body_page)), "\n")[[1]]
    body_lines <- trimws(body_lines)
    body_lines <- body_lines[nzchar(body_lines)]
    body_lines <- body_lines[body_lines != SWANRIVER_EMPTY_TEXT]
    body_lines <- body_lines[!grepl("^\\(click here", body_lines)]
    body_lines <- body_lines[!grepl("^\\(All positions available", body_lines)]
    if (length(body_lines) > 0) {
      rows[[length(rows) + 1]] <- data.frame(Title = body_lines, Location = labels[i],
                                              Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
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

# Reed Point School District (reedpoint.k12.mt.us, found 2026-08-24) --
# another publicly published Google Sites page, same platform as North
# Star/Trego above. Real postings sit under a flat "Job Openings-" header
# (a trailing dash instead of North Star's colon or Trego's no-marker
# convention) -- confirmed live 2026-08-24, 2 real postings (Kitchen
# Substitute, Substitute Teachers). Stops at the first line matching
# "Applications are available..." rather than a fixed stop line, since
# the real ADA-notice boilerplate/"Report abuse" footer that follows
# isn't a single distinctive string on this page.
REEDPOINT_STOP_PATTERN <- "^Applications are available"

fetch_reedpoint_postings <- function(url = "https://www.reedpoint.k12.mt.us/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_reedpoint_postings(resp_body_string(resp), url)
}

parse_reedpoint_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Job Openings-")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(grepl(REEDPOINT_STOP_PATTERN, lines))
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  titles <- lines[nzchar(lines)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Reed Point", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Hobson Public School (hobson.k12.mt.us, found 2026-08-24) -- Finalsite,
# same platform as Thompson Falls, but a different page shape: real
# postings sit in prose under a year-suffixed header ("Current Openings
# at Hobson Public School for the 2026-2027 school year:") rather than
# Thompson Falls's RSS-feed-style "Post RSS Feeds"/"Load More" boundary
# -- matched by a regex tolerant of the school-year string changing
# rather than a literal line, since this page's own content will
# presumably get re-authored with a new year string every fall.
# Confirmed live 2026-08-24, 3 real postings (Vo-Ag Teacher, Physical
# Education, Elementary Education). Stops at the line beginning "Listing
# of all Current Teacher Openings", the real, stable boundary before the
# OPI-referral/CBA/application-form document links.
HOBSON_START_PATTERN <- "^Current Openings at Hobson Public School for the .+ school year:$"
HOBSON_STOP_PATTERN <- "^Listing of all Current Teacher Openings"

fetch_hobson_postings <- function(url = "https://www.hobson.k12.mt.us/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_hobson_postings(resp_body_string(resp), url)
}

parse_hobson_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(grepl(HOBSON_START_PATTERN, lines))
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(grepl(HOBSON_STOP_PATTERN, lines))
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  titles <- lines[nzchar(lines)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Hobson", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
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
# application-form links.
fetch_gallatingateway_postings <- function(url = "https://www.gallatingatewayschool.com/Employment/") {
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
# Apptegy (chromote-driven) -- Wolf Point, Plentywood, Conrad, Westby,
# Choteau, Gardiner, Malta, Drummond, Deer Lodge, Townsend, Hays-Lodge
# Pole, Plevna, Sunburst, Belt, Big Sky, Melstone, Roundup, White Sulphur
# Springs, Shelby, Centerville -- plus Geyser, a genuinely different CMS
# ("CyberSchool 2.0") that also needs a real browser to render, folded
# into this same shared-session aggregator below since the fetch/parse
# split (navigate, read innerText) is identical regardless of which CMS
# is on the other end.
# ---------------------------------------------------------------------------

# Wolf Point/Plentywood (found 2026-08-07) sit on an older Apptegy template
# where every real posting renders straight into visible page text --
# document.body.innerText (below) sees it all. The 8 districts found
# 2026-08-16 (Conrad, Westby, Choteau, Gardiner, Malta, Drummond, Deer
# Lodge, Townsend) all sit on a NEWER Apptegy "page-builder" template
# instead. Confirmed live: for 5 of them (Westby, Choteau, Malta, Deer
# Lodge, Townsend) real postings STILL render into visible innerText fine,
# so they reuse that exact same technique below (Deer Lodge is the one
# exception that uses the JSON decode anyway -- see its own comment for
# why). But for Conrad, Gardiner, and Drummond, real posting content lives
# inside an accordion panel, a two-column button layout, or similar
# page-builder component whose content is authored into the page's
# underlying JSON data but genuinely never renders into visible DOM text at
# page-load time (an innerText read returns 0 real postings for these 3,
# confirmed live) -- these 3 instead decode the page's own embedded JSON
# payload directly (see
# decode_apptegy_pagebuilder_nodes() below) rather than reading rendered
# text at all.
#
# That JSON payload -- assigned via `window.clientWorkStateTemp =
# JSON.parse("...")` in a `<script>` tag on every page-builder-template
# Apptegy page (confirmed present even on the 3 that don't strictly need it)
# -- is DOUBLE JSON-encoded: the outer `<script>` tag contains a JS string
# literal (itself JSON-escaped, matching JSON string-escaping rules closely
# enough that decoding it as a bare JSON string works) whose decoded value
# is a second, separate JSON document. decode_apptegy_pagebuilder_nodes()
# undoes both layers and returns the real page content tree
# (`page$content$structure$nodes`) for each per-district function below to
# walk on its own known terms -- deliberately NOT a generic "extract every
# posting from any page-builder tree" walker: an early prototype of that
# swept in real noise (the page's own H1 title, an unrelated mid-page
# announcement, boilerplate "Apply Now"/application-instruction buttons) that
# only per-district knowledge of each page's real shape can safely exclude.
decode_apptegy_pagebuilder_nodes <- function(html_text) {
  needle <- "window.clientWorkStateTemp = JSON.parse("
  start <- regexpr(needle, html_text, fixed = TRUE)
  if (start == -1) return(NULL)
  rest <- substring(html_text, start + attr(start, "match.length"))

  # A single vectorized (PCRE, compiled-C) regex match for a JSON-escaped
  # quoted string -- NOT a per-character R loop growing a vector with
  # repeated c() calls, which is quadratic in string length and, on a
  # ~200KB real payload, was observed live to take minutes rather than
  # milliseconds.
  quoted_string <- regmatches(rest, regexpr('^"(?:[^"\\\\]|\\\\.)*"', rest, perl = TRUE))
  if (length(quoted_string) == 0) return(NULL)

  inner_json_text <- jsonlite::fromJSON(quoted_string)
  data <- jsonlite::fromJSON(inner_json_text, simplifyVector = FALSE)
  data$page$content$structure$nodes
}

# Generic (type-matching only, not content-interpreting) depth-first lookup
# across a page-builder nodes tree -- shared by the per-district functions
# below to locate their own known nodes by type/name, not to decide on their
# own which content is a real posting.
find_all_apptegy_nodes <- function(nodes, predicate) {
  out <- list()
  if (is.null(nodes)) return(out)
  for (node in nodes) {
    if (predicate(node)) out[[length(out) + 1]] <- node
    if (!is.null(node$nodes)) out <- c(out, find_all_apptegy_nodes(node$nodes, predicate))
  }
  out
}

find_apptegy_node <- function(nodes, predicate) {
  found <- find_all_apptegy_nodes(nodes, predicate)
  if (length(found) == 0) NULL else found[[1]]
}

# A CONTENT_NODE_TEXT node's content$html is real author-written HTML
# (<p>/<li> items, sometimes wrapping an <a> link) -- this splits it into
# plain-text lines the same way rvest::html_text2() splits on block
# boundaries, for the districts below whose postings are plain paragraph/
# list text with no per-posting link worth keeping separately.
apptegy_html_fragment_to_lines <- function(html_frag) {
  if (is.null(html_frag) || !nzchar(html_frag)) return(character(0))
  x <- gsub("<li>|<p( [^>]*)?>", "\n", html_frag)
  x <- gsub("</li>|</p>", "", x)
  x <- gsub("<[^>]+>", "", x)
  x <- gsub("&amp;", "&", x)
  lines <- trimws(strsplit(x, "\n")[[1]])
  lines[nzchar(lines)]
}

# Conrad Public Schools (conradschools.org) -- real postings live inside 3
# named accordion panels on the Employment page ("Certified Staff
# Vacancies", "Classified & Support Staff Vacancies", "Coaching Positions"),
# confirmed live 2026-08-16: 12 real postings across the 3 panels. A 4th,
# separately-authored posting ("Substitute Bus Driver") sits OUTSIDE any
# panel as a bare page heading + prose description -- deliberately excluded,
# not missed: its own "Revised Posting Date: March 14, 2019" shows it's a
# static, years-stale evergreen posting, not a real current opening (the
# same judgment call already applied to Malta's stale news-article posting
# below).
CONRAD_PANEL_NAMES <- c("Certified Staff Vacancies", "Classified & Support Staff Vacancies", "Coaching Positions")

parse_conrad_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  nodes <- decode_apptegy_pagebuilder_nodes(html_text)
  if (is.null(nodes)) return(empty)

  rows <- lapply(CONRAD_PANEL_NAMES, function(panel_name) {
    panel <- find_apptegy_node(nodes, function(n) {
      !is.null(n$type) && n$type == "CONTENT_NODE_PANEL" &&
        !is.null(n$properties$text) && n$properties$text == panel_name
    })
    if (is.null(panel)) return(NULL)
    text_node <- find_apptegy_node(panel$nodes, function(n) !is.null(n$type) && n$type == "CONTENT_NODE_TEXT")
    if (is.null(text_node)) return(NULL)
    titles <- apptegy_html_fragment_to_lines(text_node$content$html)
    if (length(titles) == 0) return(NULL)
    data.frame(Title = titles, Location = panel_name, Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Savage Public Schools (savagepublicschool.com, Richland County, adopted 2026-10-29 Batch 25).
# Apptegy CMS behind Fastly. Job openings authored inside accordion panels:
# "Certified Positions", "Classified Positions", and "Extracurricular Positions".
# Decodes the page-builder nodes tree via decode_apptegy_pagebuilder_nodes().
# Confirmed live 2026-10-29: 8 real active postings.
parse_savage_postings <- function(html_text, url = "https://www.savagepublicschool.com/page/employment") {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  nodes <- decode_apptegy_pagebuilder_nodes(html_text)
  if (is.null(nodes)) return(empty)

  panels <- find_all_apptegy_nodes(nodes, function(n) {
    !is.null(n$type) && n$type == "CONTENT_NODE_PANEL" &&
      !is.null(n$properties$text) && grepl("Positions", n$properties$text, ignore.case = TRUE)
  })
  if (length(panels) == 0) return(empty)

  rows <- lapply(panels, function(panel) {
    text_node <- find_apptegy_node(panel$nodes, function(n) !is.null(n$type) && n$type == "CONTENT_NODE_TEXT")
    if (is.null(text_node)) return(NULL)
    titles <- apptegy_html_fragment_to_lines(text_node$content$html)
    if (length(titles) == 0) return(NULL)
    data.frame(
      Title = titles,
      Location = "Savage",
      Posted_Date = NA_character_,
      Link = url,
      stringsAsFactors = FALSE
    )
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Gardiner Public Schools (gardiner.org) -- real postings sit in a
# two-column button layout: one "Two Columns" node holds just the 2 category
# headings ("Certified Positions"/"Classified Positions"), and a SEPARATE
# "Two Columns" node further down holds the real posting buttons, matched to
# a category by column position (column 1 = Certified, column 2 =
# Classified) rather than a shared parent -- confirmed live 2026-08-16: 3
# Certified + 2 Classified = 5 real postings, each with its own real
# application-document link. A 3rd "Two Columns" button node further down
# ("Certified Application"/"Classified Application") is boilerplate, not
# postings -- excluded by exact title match, the same defensive pattern
# Lodge Grass's "Apply Now" exclusion already uses in this file.
GARDINER_BOILERPLATE_BUTTON_TITLES <- c("Certified Application", "Classified Application")

apptegy_heading_text <- function(node) {
  if (is.null(node) || is.null(node$content$html)) return(NA_character_)
  txt <- gsub("<[^>]+>", "", node$content$html)
  txt <- trimws(gsub("&amp;", "&", txt))
  if (nzchar(txt)) txt else NA_character_
}

parse_gardiner_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  nodes <- decode_apptegy_pagebuilder_nodes(html_text)
  if (is.null(nodes)) return(empty)

  heading_pair <- find_apptegy_node(nodes, function(n) {
    !is.null(n$type) && n$type == "LAYOUT_NODE_DOUBLE_COLUMN" && length(n$nodes) == 2 &&
      all(vapply(n$nodes, function(col) {
        length(col$nodes) >= 1 && !is.null(col$nodes[[1]]$type) && col$nodes[[1]]$type == "CONTENT_NODE_HEADING"
      }, logical(1)))
  })
  if (is.null(heading_pair)) return(empty)
  categories <- vapply(heading_pair$nodes, function(col) apptegy_heading_text(col$nodes[[1]]), character(1))
  if (any(is.na(categories))) return(empty)

  double_cols <- find_all_apptegy_nodes(nodes, function(n) !is.null(n$type) && n$type == "LAYOUT_NODE_DOUBLE_COLUMN")
  rows <- list()
  for (dc in double_cols) {
    if (length(dc$nodes) != 2) next
    for (i in 1:2) {
      button_nodes <- Filter(function(n) !is.null(n$type) && n$type == "CONTENT_NODE_BUTTON", dc$nodes[[i]]$nodes)
      if (length(button_nodes) == 0) next
      titles <- unlist(lapply(button_nodes, function(n) vapply(n$content$buttons, function(b) b$title, character(1))))
      titles <- titles[!(titles %in% GARDINER_BOILERPLATE_BUTTON_TITLES) & nzchar(titles)]
      if (length(titles) == 0) next
      rows[[length(rows) + 1]] <- data.frame(Title = titles, Location = categories[i], Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Drummond Public Schools (drummondschool.net) -- an initial plain-curl probe
# of its homepage returned Apptegy's Cloudflare-style bot-challenge shell (a
# `_fs-ch-...` asset path in that shell briefly suggested Finalsite instead,
# but the page's own real footer branding and `window.clientWorkStateTemp`
# payload confirm it's genuinely Apptegy -- a real, corrected finding, not a
# guess). Real postings sit in ONE CONTENT_NODE_TEXT block covering the
# whole page body -- 2 bold `<strong>` paragraphs mark "Certified Positions"/
# "Classified Positions", and each real posting is its own `<p>`, some
# wrapping a real per-posting link (`<a href="https://aptg.co/...">`, a
# real Apptegy link-shortener domain) and some plain text -- confirmed live
# 2026-08-16: 3 Certified + 5 Classified = 8 real postings. Parsed by
# reading that one fragment as its own small HTML document (not a flat-text
# scan) specifically so each posting's own <a> link, when present, is used
# as its Title rather than swept-in trailing text -- one real posting
# ("Half-Time K-12 Librarian") has a "/Other Teaching Duties" annotation
# sitting outside its <a> tag, deliberately not appended to the Title for
# the same reason. Stops at "Contact Superintendent...", the real, stable
# boundary between real postings and the page's application instructions.
parse_drummond_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  nodes <- decode_apptegy_pagebuilder_nodes(html_text)
  if (is.null(nodes)) return(empty)

  text_node <- find_apptegy_node(nodes, function(n) {
    !is.null(n$type) && n$type == "CONTENT_NODE_TEXT" && !is.null(n$content$html) &&
      grepl("Certified Positions", n$content$html, fixed = TRUE)
  })
  if (is.null(text_node)) return(empty)

  frag <- rvest::read_html(paste0("<div>", text_node$content$html, "</div>"))
  ps <- rvest::html_elements(frag, "p")

  rows <- list()
  category <- NA_character_
  started <- FALSE
  for (p in ps) {
    strong_txt <- trimws(rvest::html_text2(rvest::html_elements(p, "strong")))
    full_txt <- trimws(rvest::html_text2(p))
    if (grepl("Contact Superintendent", full_txt, fixed = TRUE)) break

    if (length(strong_txt) > 0 && grepl("^(Certified|Classified) Positions$", strong_txt[1])) {
      category <- sub(" Positions$", "", strong_txt[1])
      started <- TRUE
      next
    }
    if (!started || !nzchar(full_txt)) next

    a_el <- rvest::html_element(p, "a")
    title <- if (!is.na(a_el)) trimws(rvest::html_text2(a_el)) else trimws(strsplit(full_txt, "\n")[[1]][1])
    if (nzchar(title)) {
      rows[[length(rows) + 1]] <- data.frame(Title = title, Location = category, Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Westby School District 3 (westbyschool.k12.mt.us) -- older-template-style
# Apptegy page (real content renders straight into visible innerText, unlike
# Conrad/Gardiner/Drummond above), but its 2 real postings are free-form
# prose (a title line, then a compensation/type line, then bulleted
# Responsibilities/Requirements) rather than Wolf Point's ALL-CAPS section
# style. Confirmed live 2026-08-16: both real title lines are immediately
# followed by a compensation/employment-type line ("Full-Time, 12-month
# position" / "$18-22/hour") -- used as the one reliable structural signal
# to find them, since neither "Responsibilities"/"Requirements" (the
# following bullet-list headers) nor the bullets themselves match that
# pattern. Only 2 real postings exist live, so this function's behavior on a
# 3rd differently-formatted posting is unconfirmed.
parse_westby_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Employment Opportunities")
  stop_idx <- which(lines == "Applications")
  if (length(start_idx) == 0 || length(stop_idx) == 0 || stop_idx[1] <= start_idx[1] + 1) return(empty)
  window <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]

  titles <- character(0)
  if (length(window) > 1) {
    for (i in seq_len(length(window) - 1)) {
      if (grepl("^(Full-Time|Part-Time|\\$[0-9])", window[i + 1])) titles <- c(titles, window[i])
    }
  }
  if (length(titles) == 0) return(empty)
  data.frame(Title = titles, Location = "Westby", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

# Choteau School District (choteauschools.net) -- real content renders into
# visible innerText fine. Real postings are a clean single-column list under
# 2 real category headers ("Current Open Certified Teaching Positions:" /
# "Current Open Classified Positions:"), confirmed live 2026-08-16: 1
# Certified + 4 Classified = 5 real postings, ending at "Applications:" (a
# real, stable boundary before the boilerplate application-form links).
parse_choteau_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  cert_idx <- which(lines == "Current Open Certified Teaching Positions:")
  class_idx <- which(lines == "Current Open Classified Positions:")
  if (length(cert_idx) == 0 || length(class_idx) == 0 || class_idx[1] <= cert_idx[1]) return(empty)
  stop_idx <- which(lines == "Applications:")
  class_end <- if (length(stop_idx) > 0 && stop_idx[1] > class_idx[1]) stop_idx[1] - 1 else length(lines)

  rows <- list()
  if (class_idx[1] > cert_idx[1] + 1) {
    rows[[1]] <- data.frame(Title = lines[(cert_idx[1] + 1):(class_idx[1] - 1)], Location = "Certified",
                             Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
  }
  if (class_end >= class_idx[1] + 1) {
    rows[[2]] <- data.frame(Title = lines[(class_idx[1] + 1):class_end], Location = "Classified",
                             Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Malta Public Schools (maltaschools.org) -- real content renders into
# visible innerText fine. Real postings sit under real category headers,
# each ending in the literal word " Openings" ("Administrative Openings",
# "Certified Openings", "Classified Openings", "Coaching Openings", "Other
# Employment Openings"), confirmed live 2026-08-16: 5 Certified + 3
# Classified + 3 Coaching = 11 real postings. Administrative and "Other
# Employment" are real, genuinely EMPTY categories right now (immediately
# followed by the next header, or by the page's "Find Us" footer) -- a real
# absence, not a parsing gap, the same empty-tab handling already applied to
# Lodge Grass's Coach tab. The stale 2021 "Malta Schools Job Openings" NEWS
# ARTICLE this district also publishes (a different page entirely,
# /article/503728) is deliberately NOT the source used here -- this
# function reads /page/district-employment, the real, currently-maintained
# listings page.
parse_malta_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  header_idx <- which(grepl(" Openings$", lines))
  stop_idx <- which(lines == "Find Us")
  if (length(header_idx) == 0 || length(stop_idx) == 0) return(empty)

  rows <- list()
  for (i in seq_along(header_idx)) {
    start <- header_idx[i] + 1
    end <- if (i < length(header_idx)) header_idx[i + 1] - 1 else stop_idx[1] - 1
    if (start > end) next
    category <- sub(" Openings$", "", lines[header_idx[i]])
    rows[[length(rows) + 1]] <- data.frame(Title = lines[start:end], Location = category,
                                            Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Deer Lodge School District #1 (deerlodgeschools.org) -- found 2026-08-16
# in a further follow-up pass past the original 23-town list, checking a
# handful of additional higher-volume OPI-only candidates by hand. Real
# postings live in 2 different real shapes on the same page, confirmed
# live: a plain top text block with bare `<p><strong>Title</strong></p>`
# lines (2 real postings, ending at the first application-link paragraph),
# plus 3 separate CONTENT_NODE_CARD components further down whose own h2
# heading is sometimes the real title itself ("Bus Driver"), sometimes a
# generic recruiting label with the real title as the first real sentence
# inside its own body text ("Certified Teacher" card body's own opening
# line is "Special Education Teacher 5th/6th grades"), and one card
# ("Substitutes Wanted") is genuinely NOT a specific posting at all -- a
# standing "we always take substitute applications" ad, deliberately
# excluded. 4 real current postings total. Uses
# decode_apptegy_pagebuilder_nodes() like Conrad/Gardiner/Drummond, not the
# innerText technique -- confirmed live this page's card content does
# render into visible innerText fine here (unlike Conrad's accordions), but
# the JSON gives a much more reliable per-card heading/body split than
# text-scanning would.
DEERLODGE_GENERIC_CARD_HEADINGS <- c("Substitutes Wanted")

parse_deerlodge_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  nodes <- decode_apptegy_pagebuilder_nodes(html_text)
  if (is.null(nodes)) return(empty)

  rows <- list()

  text_node <- find_apptegy_node(nodes, function(n) {
    !is.null(n$type) && n$type == "CONTENT_NODE_TEXT" && !is.null(n$content$html) &&
      grepl("Current open positions:", n$content$html, fixed = TRUE)
  })
  if (!is.null(text_node)) {
    frag <- rvest::read_html(paste0("<div>", text_node$content$html, "</div>"))
    ps <- rvest::html_elements(frag, "p")
    for (p in ps) {
      if (grepl("Current open positions:", rvest::html_text2(p), fixed = TRUE)) next
      a_el <- rvest::html_element(p, "a")
      if (!is.na(a_el)) break
      title <- trimws(rvest::html_text2(p))
      if (nzchar(title)) {
        rows[[length(rows) + 1]] <- data.frame(Title = title, Location = "Deer Lodge",
                                                Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
      }
    }
  }

  cards <- find_all_apptegy_nodes(nodes, function(n) !is.null(n$type) && n$type == "CONTENT_NODE_CARD")
  for (card in cards) {
    heading <- trimws(gsub("<[^>]+>", "", card$content$heading$content$html))
    if (heading %in% DEERLODGE_GENERIC_CARD_HEADINGS) next
    if (heading == "Certified Teacher") {
      body_lines <- apptegy_html_fragment_to_lines(card$content$text$content$html)
      real_title <- body_lines[!grepl("^We are looking for|^Click on the link", body_lines)]
      if (length(real_title) > 0) {
        rows[[length(rows) + 1]] <- data.frame(Title = real_title[1], Location = "Deer Lodge",
                                                Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
      }
      next
    }
    if (nzchar(heading)) {
      rows[[length(rows) + 1]] <- data.frame(Title = heading, Location = "Deer Lodge",
                                              Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }

  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Townsend School District (townsend.k12.mt.us) -- found in the same
# 2026-08-16 follow-up pass as Deer Lodge above. Real content renders into
# visible innerText fine. Real postings sit under 2 real category headers
# ("Internal Openings"/"External Openings"), each posting authored as
# "TITLE - description prose" on one line -- confirmed live 2026-08-16, 1
# Internal + 4 External = 5 real postings. Every real header/posting line
# on this page carries a trailing non-breaking space (U+00A0) baked into
# the site's own authored content -- stripped here, not a parsing artifact
# (the same class of issue as Scobey's leading zero-width spaces above,
# different character). Stops at "ATHLETIC DIRECTOR", a large centered
# heading that starts a full job-description DOCUMENT for the "HS/MS
# Activities Director" posting already captured above -- real reference
# material, not a second posting.
TOWNSEND_NBSP <- intToUtf8(160)

parse_townsend_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- gsub(TOWNSEND_NBSP, " ", lines, fixed = TRUE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(grepl("^Townsend School Job Vacancies", lines))
  stop_idx <- which(grepl("^Contact:", lines) | lines == "ATHLETIC DIRECTOR")
  if (length(start_idx) == 0 || length(stop_idx) == 0 || stop_idx[1] <= start_idx[1]) return(empty)
  window <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]

  rows <- list()
  location <- NA_character_
  for (line in window) {
    if (line %in% c("Internal Openings", "External Openings")) {
      location <- sub(" Openings$", "", line)
      next
    }
    if (is.na(location)) next
    if (grepl(" - ", line, fixed = TRUE)) {
      title <- trimws(sub(" -.*$", "", line))
      if (nzchar(title)) {
        rows[[length(rows) + 1]] <- data.frame(Title = title, Location = location,
                                                Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
      }
    } else {
      # Reject prose / continuation fragments
      if (grepl("[.]|[$]|available here|master agreement|endorsement|qualify|application|prorated|agreement", line, ignore.case = TRUE)) next
      if (grepl("^[a-z]", line)) next
      if (nchar(line) > 60) next
      title <- line
      if (nzchar(title)) {
        rows[[length(rows) + 1]] <- data.frame(Title = title, Location = location,
                                                Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
      }
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Hays-Lodge Pole School District (hlpschools.k12.mt.us) -- found in the
# 2026-08-23 pass working down the remaining OPI-gap candidate list. Older
# innerText-rendering Apptegy template, same as Wolf Point/Plentywood.
# Real postings sit under 2 real headers ("Certified Positions"/
# "Classified Positions", no trailing colon) but -- unlike Choteau's clean
# list -- are interleaved with real prose (benefits copy, application
# instructions) that a naive "everything after the header" scrape would
# wrongly sweep in. Confirmed live 2026-08-23: 2 Certified + 3 Classified =
# 5 real postings. looks_like_hayslodgepole_title() reuses Wolf Point's
# sentence-rejection heuristic (length cap, no trailing "."/":" , no
# digit-dot list marker) plus one addition -- rejecting any line
# containing "$" -- needed because "$5000.00 Sign-On Bonus" is short and
# unpunctuated enough to otherwise pass Wolf Point's own filter unchanged.
# Both real headers carry a trailing non-breaking space (U+00A0) baked
# into the site's own authored content -- the same class of issue as
# Townsend's TOWNSEND_NBSP above, different character, stripped below
# rather than left to silently defeat the `lines == "Certified Positions"`
# match (trimws() alone does not strip U+00A0).
HAYSLODGEPOLE_NBSP <- intToUtf8(160)

looks_like_hayslodgepole_title <- function(line) {
  if (nchar(line) > 55) return(FALSE)
  if (grepl("[.:]$", line)) return(FALSE)
  if (grepl("^[0-9]+\\.", line)) return(FALSE)
  if (!grepl("[A-Za-z]", line)) return(FALSE)
  if (grepl("\\$", line)) return(FALSE)
  TRUE
}

parse_hayslodgepole_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- gsub(HAYSLODGEPOLE_NBSP, " ", lines, fixed = TRUE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Certified Positions")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[start_idx[1]:length(lines)]

  stop_idx <- which(lines == "Find Us" | grepl("^For technical questions", lines))
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  header_pattern <- "^(Certified|Classified) Positions$"
  rows <- list()
  current_header <- NA_character_
  for (line in lines) {
    if (grepl(header_pattern, line)) {
      current_header <- sub(" Positions$", "", line)
      next
    }
    if (!is.na(current_header) && looks_like_hayslodgepole_title(line)) {
      rows[[length(rows) + 1]] <- data.frame(Title = line, Location = current_header,
                                              Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

fetch_hayslodgepole_postings <- function(chromote_session, url = "https://www.hlpschools.k12.mt.us/page/jobs") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_hayslodgepole_postings(text, url)
}

# Plevna School District #55 (plevnacougars.com) -- found in the same
# 2026-08-23 pass as Hays-Lodge Pole above. Older innerText-rendering
# Apptegy template. Real postings are a genuinely clean list (no prose
# interleaved, unlike Hays-Lodge Pole) grouped under real Title-Case
# headers ending in ":" ("Certified Teaching Positions:", "Basketball
# Coaching Position:", "Track Coaching Positions:", "Substitutes:") --
# confirmed live 2026-08-23, 10 real postings. The colon suffix alone is
# enough to tell a header from a title line here (no title line on this
# page ends in ":"), so this doesn't need Hays-Lodge Pole's title-shape
# heuristic. Starts after "<school year> School Year Positions Open:" and
# stops at "Full Family Health Insurance Offered", the real, stable start
# of the page's benefits copy that immediately follows the last posting.
PLEVNA_STOP_LINE <- "Full Family Health Insurance Offered"

parse_plevna_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(grepl("^[0-9]{4}-[0-9]{4} School Year Positions Open:$", lines))
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == PLEVNA_STOP_LINE)
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  rows <- list()
  current_header <- NA_character_
  for (line in lines) {
    if (grepl(":$", line)) {
      current_header <- sub(":$", "", line)
      next
    }
    if (!is.na(current_header)) {
      rows[[length(rows) + 1]] <- data.frame(Title = line, Location = current_header,
                                              Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

fetch_plevna_postings <- function(chromote_session, url = "https://www.plevnacougars.com/o/plevna/page/employment-plevna") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_plevna_postings(text, url)
}

# Sunburst Schools (sunburst.k12.mt.us) -- found in the same 2026-08-23
# pass. Older innerText-rendering Apptegy template. Real postings are a
# flat, single-category list right after "Sunburst Public Schools has the
# following jobs open:", no per-category headers at all (unlike every
# other Apptegy district in this file) -- confirmed live 2026-08-23, 4
# real postings (Cook, Guidance Counselor, Substitute Teachers, Bus
# Drivers). Stops at the first "Please click here..." application-link
# line, the real, stable boundary before boilerplate.
parse_sunburst_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Sunburst Public Schools has the following jobs open:")
  if (length(start_idx) == 0) return(empty)

  stop_idx <- which(grepl("^Please click here", lines))
  stop_idx <- stop_idx[stop_idx > start_idx[1]]
  end <- if (length(stop_idx) > 0) stop_idx[1] - 1 else length(lines)
  if (end < start_idx[1] + 1) return(empty)

  titles <- lines[(start_idx[1] + 1):end]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Sunburst", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_sunburst_postings <- function(chromote_session, url = "https://www.sunburst.k12.mt.us/page/employment-opportunities") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_sunburst_postings(text, url)
}

# Belt Public Schools (beltschool.com) -- found in a follow-up 2026-08-23
# pass working further down the OPI-gap candidate list. Older
# innerText-rendering Apptegy template. Real postings sit under 2 real
# colon-suffixed headers ("Certified Openings:"/"Classified Openings:",
# the same convention as Plevna above), but a real prose paragraph
# ("Belt School also has classified openings for...") immediately follows
# the last real title with no further header before it -- unlike Plevna,
# where a benefits-copy STOP_LINE alone was enough, here the window is
# truncated at that prose paragraph's own stable opening words before the
# colon-header loop ever runs, since the paragraph would otherwise be
# swept in as a 4th "Classified Openings" title. Confirmed live
# 2026-08-23: 0 Certified (genuinely empty right now) + 3 Classified = 3
# real postings.
BELT_STOP_PATTERN <- "^Belt School also has classified openings"

parse_belt_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Certified Openings:")
  if (length(start_idx) == 0) return(empty)
  stop_idx <- which(grepl(BELT_STOP_PATTERN, lines))
  if (length(stop_idx) == 0 || stop_idx[1] <= start_idx[1]) return(empty)
  window <- lines[start_idx[1]:(stop_idx[1] - 1)]

  rows <- list()
  current_header <- NA_character_
  for (line in window) {
    if (grepl(":$", line)) {
      current_header <- sub(":$", "", line)
      next
    }
    if (!is.na(current_header)) {
      rows[[length(rows) + 1]] <- data.frame(Title = line, Location = current_header,
                                              Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

fetch_belt_postings <- function(chromote_session, url = "https://www.beltschool.com/page/employment-opportunities") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_belt_postings(text, url)
}

# Big Sky School District 72 (bssd72.org) -- found in the same follow-up
# pass. Older innerText-rendering Apptegy template. Real postings sit
# under 2 real bare (no colon) category headers ("Teaching"/"District
# Staff") -- matched by literal known name here (like Conrad's
# CONRAD_PANEL_NAMES above), not a colon-suffix rule, since neither header
# ends in ":". Confirmed live 2026-08-23: 2 Teaching + 2 District Staff =
# 4 real postings. Starts after "Current Openings", stops at
# "Applications", the real, stable boundary before the boilerplate
# application-form list.
BIGSKY_HEADERS <- c("Teaching", "District Staff")

parse_bigsky_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Current Openings")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "Applications")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  rows <- list()
  current_header <- NA_character_
  for (line in lines) {
    if (line %in% BIGSKY_HEADERS) {
      current_header <- line
      next
    }
    if (!is.na(current_header)) {
      rows[[length(rows) + 1]] <- data.frame(Title = line, Location = current_header,
                                              Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

fetch_bigsky_postings <- function(chromote_session, url = "https://www.bssd72.org/page/employment-opportunities") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_bigsky_postings(text, url)
}

# Melstone Public Schools (melstonepublicschools.org) -- found in the same
# follow-up pass. Older innerText-rendering Apptegy template, but its own
# structure is a repeated field-label card ("Title:" / "Description:" /
# "Benefits:" / "Application:") rather than a header+list -- a real,
# reliable marker distinct from every other Apptegy district in this file:
# every real posting's title is literally the plain-text line right after
# a bare "Title:" line, confirmed live 2026-08-23 across all 4 real
# postings (2 full-time: Head Cook, Head Maintenance/Custodian; 2
# substitute-pool: Substitute Route Bus Drivers/Activity Drivers,
# Substitute Teachers/Kitchen Staff/Custodian).
parse_melstone_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  title_idx <- which(lines == "Title:")
  if (length(title_idx) == 0) return(empty)
  titles <- lines[title_idx + 1]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Melstone", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_melstone_postings <- function(chromote_session, url = "https://www.melstonepublicschools.org/page/employment-opportunities") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_melstone_postings(text, url)
}

# Roundup School District (roundup.k12.mt.us) -- found in a further
# follow-up 2026-08-23 pass working down to the last few OPI-gap
# candidates. Older innerText-rendering Apptegy template. Real postings
# sit under 3 real bare (no colon) category headers ("Certified
# Positions"/"Extracurricular Positions"/"Classified Positions and
# Substitutes"), matched by literal known name like Big Sky's
# BIGSKY_HEADERS above. Confirmed live 2026-08-23: 1 Certified + 5
# Extracurricular + 7 Classified = 13 real postings, the single largest
# haul of any district added this session. Starts after "Open Positions",
# stops at "Required Application Materials", the real, stable boundary
# before the application-requirements comparison table.
ROUNDUP_HEADERS <- c("Certified Positions", "Extracurricular Positions", "Classified Positions and Substitutes")

parse_roundup_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Open Positions")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "Required Application Materials")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  rows <- list()
  current_header <- NA_character_
  for (line in lines) {
    if (line %in% ROUNDUP_HEADERS) {
      current_header <- line
      next
    }
    if (!is.na(current_header)) {
      rows[[length(rows) + 1]] <- data.frame(Title = line, Location = current_header,
                                              Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

fetch_roundup_postings <- function(chromote_session, url = "https://www.roundup.k12.mt.us/page/roundup-public-schools-employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_roundup_postings(text, url)
}

# White Sulphur Springs Schools (whitesulphur.k12.mt.us) -- found in the
# same follow-up pass. Older innerText-rendering Apptegy template. Real
# postings are a genuinely flat, single-category list right after
# "Current Openings" (no per-category headers, the same shape as Sunburst
# above) -- confirmed live 2026-08-23, 5 real postings (Counselor,
# Secretary, Bus Driver, a combined "JH/HS Coaching- VB, JH Boys
# Basketball" line, Music). Stops at "Application Information", the real,
# stable boundary before the boilerplate application-form list.
parse_wss_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Current Openings")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "Application Information")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]
  lines <- lines[nzchar(lines)]
  if (length(lines) == 0) return(empty)

  data.frame(Title = lines, Location = "White Sulphur Springs", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_wss_postings <- function(chromote_session, url = "https://www.whitesulphur.k12.mt.us/page/employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_wss_postings(text, url)
}

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

# Thompson Falls Public Schools (thompsonfalls.net) -- found in the same
# follow-up pass. Genuinely Finalsite (confirmed by the real "Powered by
# Finalsite" footer), a plain httr2 fetch, no chromote needed. Real
# postings are a clean list right after "Post RSS Feeds Subscribe to Post
# Alerts" (a real, stable Finalsite widget label, not authored content)
# -- confirmed live 2026-08-23 (5 postings, with a "Load More" button) and
# again 2026-09-07 (3 postings, no "Load More" -- the button only appears
# when there are enough postings to paginate). The stop boundary is
# whichever comes first of "Load More" or the "Employment Information"
# section header that always follows the openings list -- the earlier
# version keyed only on "Load More" and silently returned 0 once the
# button went away (drift-check issue #1, 2026-09-07).
parse_thompsonfalls_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(grepl("^Post RSS Feeds", lines))
  if (length(start_idx) == 0) return(empty)
  stop_candidates <- which(lines %in% c("Load More", "Employment Information"))
  stop_candidates <- stop_candidates[stop_candidates > start_idx[1]]
  if (length(stop_candidates) == 0) return(empty)
  stop_idx <- min(stop_candidates)
  # Markers back to back = no postings. Without this, (start + 1):(stop - 1)
  # counts backwards and returns the two marker lines as fake postings.
  if (stop_idx <= start_idx[1] + 1) return(empty)

  titles <- lines[(start_idx[1] + 1):(stop_idx - 1)]
  titles <- sub(" \\(opens in new window/tab\\)$", "", titles)
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Thompson Falls", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_thompsonfalls_postings <- function(url = "https://www.thompsonfalls.net/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_thompsonfalls_postings(resp_body_string(resp), url)
}

# Centerville Public Schools (centerville.k12.mt.us, serving Sand Coulee)
# -- found in the same follow-up pass. Older innerText-rendering Apptegy
# template. Real postings are a genuinely flat, single-category list
# right after "Employment Opportunities at Centerville Public Schools"
# (the same flat-list shape as Sunburst/White Sulphur Springs above) --
# confirmed live 2026-08-23, 4 real postings. Stops at "Applications",
# the real, stable boundary before the boilerplate application-form list.
parse_centerville_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Employment Opportunities at Centerville Public Schools")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "Applications")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]
  if (length(lines) == 0) return(empty)

  data.frame(Title = lines, Location = "Sand Coulee", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_centerville_postings <- function(chromote_session, url = "https://www.centerville.k12.mt.us/page/job-openings") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_centerville_postings(text, url)
}

# Arlee Joint School District (arleeschools.org) -- found in a further
# 2026-08-23 follow-up pass working down to the last remaining OPI-gap
# candidates. Older innerText-rendering Apptegy template, but its real
# postings sit in a genuine 3-column table ("Job Description" / "Application"
# / "Closing Date") rather than a header+list -- innerText renders each
# row as 3 consecutive lines (title, application type, closing date), so
# every 3rd line starting right after the 3-line header is a real title.
# Confirmed live 2026-08-23, 8 real postings.
parse_arlee_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Job Description")
  if (length(start_idx) == 0) return(empty)
  body <- lines[(start_idx[1] + 3):length(lines)]

  stop_idx <- which(body == "Find Us")
  if (length(stop_idx) > 0) body <- body[seq_len(stop_idx[1] - 1)]

  n_rows <- length(body) %/% 3
  if (n_rows == 0) return(empty)
  titles <- body[seq(1, by = 3, length.out = n_rows)]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Arlee", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_arlee_postings <- function(chromote_session, url = "https://www.arleeschools.org/page/employment-opportunities") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_arlee_postings(text, url)
}

# Chinook Public Schools (chinookschools.org) -- found in the same
# follow-up pass. Older innerText-rendering Apptegy template. Real
# postings sit under 3 real bare (no colon) category headers, matched by
# literal known name like Big Sky/Roundup above. The first category
# ("CURRENT TEACHING AND AIDE OPENINGS") is immediately followed by a
# real "Application Details:" sub-marker and prose (pay range, experience
# bands) before the next category header -- skipped via a `skipping` flag
# set at that literal marker and cleared at the next real header, the
# same 2-state pattern Wolf Point's CURRENTLY-FILLED-header exclusion
# uses elsewhere in this file. Confirmed live 2026-08-23: 1 + 1 + 5 = 7
# real postings. "Application Details:" and "Activity Drivers" both carry
# a trailing non-breaking space (U+00A0) baked into the site's own
# authored content -- stripped here, the same class of issue as
# Townsend's TOWNSEND_NBSP above, different district. Stops at
# "QUESTIONS?", the real, stable boundary before contact info.
CHINOOK_HEADERS <- c("CURRENT TEACHING AND AIDE OPENINGS", "ADDITIONAL/EXTRA CURRICULAR OPENINGS", "CUSTODIAL, KITCHEN, AND OTHER OPENINGS")
CHINOOK_NBSP <- intToUtf8(160)

parse_chinook_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- gsub(CHINOOK_NBSP, "", lines, fixed = TRUE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  stop_all_idx <- which(lines == "QUESTIONS?")
  if (length(stop_all_idx) > 0) lines <- lines[seq_len(stop_all_idx[1] - 1)]

  rows <- list()
  current_header <- NA_character_
  skipping <- FALSE
  for (line in lines) {
    if (line %in% CHINOOK_HEADERS) {
      current_header <- line
      skipping <- FALSE
      next
    }
    if (grepl("^Application Details:", line)) {
      skipping <- TRUE
      next
    }
    if (!is.na(current_header) && !skipping) {
      rows[[length(rows) + 1]] <- data.frame(Title = line, Location = current_header,
                                              Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

fetch_chinook_postings <- function(chromote_session, url = "https://www.chinookschools.org/page/employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_chinook_postings(text, url)
}

# Darby School District 9 (darby.k12.mt.us) -- found in the same
# follow-up pass. Older innerText-rendering Apptegy template. Real
# postings are a genuinely flat, single-category list right after "Open
# Positions" (the same flat-list shape as Sunburst/White Sulphur Springs/
# Centerville above) -- confirmed live 2026-08-23, 6 real postings. Stops
# at "Applications", the real, stable boundary before the tabbed
# application-form links.
parse_darby_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Open Positions")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "Applications")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]
  if (length(lines) == 0) return(empty)

  data.frame(Title = lines, Location = "Darby", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_darby_postings <- function(chromote_session, url = "https://www.darby.k12.mt.us/page/employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_darby_postings(text, url)
}

# Dutton/Brady Public School District (dbps.k12.mt.us) -- found in the
# same follow-up pass; its real employment page URL isn't a plain
# `/page/...` link findable from the rendered nav, found instead by
# decoding the site's own `window.clientWorkStateTemp` JSON menu tree for
# a "Careers"/slug pair (the same technique used to find Harlowton's and
# Melstone's real pages in an earlier session). Older innerText-rendering
# Apptegy template. Real postings are 2 short title lines each
# immediately followed by a real prose description paragraph -- reuses
# Hays-Lodge Pole's title-shape heuristic (length cap, no trailing
# "."/":" , no digit-dot list marker) since the same "title, then prose"
# interleaving shows up here, minus the "$" rule (no dollar amounts on
# this page). Confirmed live 2026-08-23, 2 real postings (Route and
# Relief School Bus Drivers, Substitute Teachers). Starts after
# "Employment Opportunities:", stops at "Find Us".
looks_like_dutton_title <- function(line) {
  if (nchar(line) > 55) return(FALSE)
  if (grepl("[.:]$", line)) return(FALSE)
  if (grepl("^[0-9]+\\.", line)) return(FALSE)
  if (!grepl("[A-Za-z]", line)) return(FALSE)
  TRUE
}

parse_dutton_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Employment Opportunities:")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "Find Us")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  titles <- lines[vapply(lines, looks_like_dutton_title, logical(1))]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Dutton", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_dutton_postings <- function(chromote_session, url = "https://dbps.k12.mt.us/page/careers") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_dutton_postings(text, url)
}

# Red Rover Hiring (jobs.redroverk12.com/org/<id>) -- first found 2026-08-24
# for St. Ignatius School District (org/2261, while re-checking the OPI-gap
# candidate list -- "SAINT IGNATIUS" and "SAINT IGNATIUS- SALISH TEACHER"
# are the same district, both collapsing into one registry row); Hamilton
# School District 3 (org/2362) joined 2026-09 after its AppliTrack tenant
# started returning a persistent HTTP 500. A client-side-rendered Next.js
# app, no API endpoint findable in the static HTML, needs a real browser
# like Apptegy, folded into the same shared chromote session below for that
# reason even though it isn't Apptegy itself (same precedent as Geyser's
# CyberSchool 2.0). Some boards carry generic evergreen application-form
# placeholders ("Classified Application", "Volunteer Application") rather
# than real openings -- the same class of noise Arlee's own "Classified
# Application"/"Certified Application" exclusion handles. Each real posting
# is a repeating block of [employment type, title, category, location,
# (salary, optional), ("Internal applicants only", optional)] followed by an
# "APPLY NOW" button line -- parsed by matching "^apply now" as the
# reliable per-posting boundary (the salary line's presence varies, so a
# fixed stride doesn't work). Some boards show a relative-date stamp on the
# following line ("27 days ago"), others go straight to the next block, and
# newer Next.js layouts concatenate the button and relative stamp into the
# same line ("Apply Now3 days ago" / "Apply Nowabout 1 month ago").
# The date isn't carried through -- standardize_date() only handles
# absolute dates anyway. "No location specified" is the board's own literal
# placeholder for a real missing value; rows carrying it fall back to
# `default_location` (the district's city) rather than keeping the prose.
REDROVER_PLACEHOLDER_TITLES <- c("Classified Application", "Certified Application", "Volunteer Application")

# Parser for any Red Rover Hiring board's rendered innerText -- title is
# always block[2] and location always block[4] of each "... APPLY NOW"
# block. See the section comment above for the block shape and the
# per-board "posted"-stamp difference this handles.
parse_redrover_postings <- function(rendered_text, url, default_location = NA_character_) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(grepl("^Found [0-9]+ job openings?$", lines))
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "Powered By")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  rows <- list()
  block <- character(0)
  i <- 1
  while (i <= length(lines)) {
    line <- lines[i]
    if (grepl("^apply now", line, ignore.case = TRUE)) {
      if (length(block) >= 2) {
        title <- block[2]
        location <- if (length(block) >= 4) block[4] else NA_character_
        if (!is.na(location) && location == "No location specified") location <- default_location
        if (!(title %in% REDROVER_PLACEHOLDER_TITLES)) {
          rows[[length(rows) + 1]] <- data.frame(Title = title, Location = location,
                                                   Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
        }
      }
      is_exact_apply_now <- grepl("^apply now$", line, ignore.case = TRUE)
      block <- character(0)
      i <- i + 1  # consume "APPLY NOW" (or "Apply Now<timestamp>")
      if (is_exact_apply_now && i <= length(lines) &&
          grepl("\\bago$|^(just posted|today|yesterday)$", lines[i], ignore.case = TRUE)) {
        i <- i + 1  # ... and the relative "posted" stamp, when on separate line
      }
      next
    }
    block <- c(block, line)
    i <- i + 1
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

fetch_redrover_postings <- function(chromote_session, url, default_location = NA_character_) {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(5)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_redrover_postings(text, url, default_location = default_location)
}

# Stanford Public Schools (stanfordmtschool.com) -- found 2026-08-24 while
# re-checking the OPI-gap candidate list. Apptegy, same platform as most
# of this section. Real postings are a flat, single-category list right
# after "Job Openings" (the same flat-list shape as Darby above), except
# the list starts with 2 evergreen application-form placeholders
# ("Certified Application", "Classified Application") -- the same class
# of noise Arlee's/St. Ignatius's own exclusion lists handle, filtered
# here by exact title match. Confirmed live 2026-08-24, 6 real postings.
# Stops at "Find Us", the real, stable boundary before contact info.
STANFORD_PLACEHOLDER_TITLES <- c("Certified Application", "Classified Application")

parse_stanford_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Job Openings")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "Find Us")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  titles <- lines[!(lines %in% STANFORD_PLACEHOLDER_TITLES)]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Stanford", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_stanford_postings <- function(chromote_session, url = "https://www.stanfordmtschool.com/page/employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_stanford_postings(text, url)
}

# Lolo School District 7 (loloschools.org) -- found 2026-08-24 while
# re-checking the OPI-gap candidate list. Apptegy, but an older
# prose-paragraph template unlike Darby/Stanford's flat title-per-line
# list: each real posting is one paragraph of "Title: description
# sentence(s)." or "Title. description sentence(s)." (2 of the 4 use a
# period instead of a colon after the title) under "CURRENT OPENING/S:".
# The title is extracted as everything before whichever of the first ":"
# or first ". " (period-then-space, so "(.33)" doesn't false-trigger)
# comes first in the line -- confirmed live 2026-08-24 this correctly
# handles both punctuation styles across all 4 real postings. Trailing
# non-breeaking spaces (U+00A0) show up mid-sentence on this page too,
# the same class of issue as Chinook/Townsend, normalized to a plain
# space here rather than stripped, since (unlike those pages) they can
# fall inside a real title. Stops at "SUBSTITUTE TEACHERS/AIDES/
# CUSTODIAL/SCHOOL NURSE", the real, stable boundary before the
# districtwide substitute-rate blurb.
LOLO_NBSP <- intToUtf8(160)

parse_lolo_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- gsub(LOLO_NBSP, " ", lines, fixed = TRUE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "CURRENT OPENING/S:")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "SUBSTITUTE TEACHERS/AIDES/CUSTODIAL/SCHOOL NURSE")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]
  if (length(lines) == 0) return(empty)

  titles <- vapply(lines, function(line) {
    colon_pos <- regexpr(":", line, fixed = TRUE)
    period_pos <- regexpr(". ", line, fixed = TRUE)
    candidates <- c(colon_pos, period_pos)
    candidates <- candidates[candidates > 0]
    if (length(candidates) == 0) return(trimws(line))
    trimws(substr(line, 1, min(candidates) - 1))
  }, character(1), USE.NAMES = FALSE)

  data.frame(Title = titles, Location = "Lolo", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_lolo_postings <- function(chromote_session, url = "https://www.loloschools.org/page/employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_lolo_postings(text, url)
}

# Froid Public Schools (froidschool.com) -- found 2026-08-24 while
# re-checking the OPI-gap candidate list. Apptegy. Real postings are a
# flat list under a year-suffixed header ("2026-2027 Open Positions:"),
# matched by regex since the year changes every fall -- confirmed live
# 2026-08-24, 3 real postings (Counselor, Substitute Teachers,
# Substitute Bus Driver). A stray bare-year line ("2026-2027") sits
# right after the real titles, a content-authoring leftover fragment
# rather than a 4th posting -- excluded by an explicit
# year-range-only-line pattern rather than a fixed row count, so it
# keeps working if the real title count changes. Stops at
# "Applications:", the real, stable boundary before the application-form
# links.
FROID_NBSP <- intToUtf8(160)
FROID_START_PATTERN <- "^[0-9]{4}-[0-9]{4} Open Positions:$"
FROID_YEAR_LINE_PATTERN <- "^[0-9]{4}-[0-9]{4}$"

parse_froid_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- gsub(FROID_NBSP, "", lines, fixed = TRUE)
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(grepl(FROID_START_PATTERN, lines))
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "Applications:")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  titles <- lines[!grepl(FROID_YEAR_LINE_PATTERN, lines)]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Froid", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_froid_postings <- function(chromote_session, url = "https://www.froidschool.com/page/open-positionsapplications") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_froid_postings(text, url)
}

# Huntley Project School District (huntley.k12.mt.us, Worden, found
# 2026-08-24) -- Apptegy. Real postings are a flat list right after
# "Open Positions" (the same flat-list shape as Darby above), but with a
# real prose paragraph in between the header and the first title on this
# page -- excluded by a plain length cap rather than a literal-line
# match, since the paragraph's exact wording is marketing copy likely to
# get re-authored. Confirmed live 2026-08-24, 5 real postings. Stops at
# "Find Us", the real, stable boundary before contact info.
parse_huntley_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Open Positions")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(lines == "Find Us")
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  titles <- lines[nchar(lines) <= 150]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Huntley Project", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_huntley_postings <- function(chromote_session, url = "https://www.huntley.k12.mt.us/page/employment-opportunities") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_huntley_postings(text, url)
}

# Park City Schools (parkcityschools.org, found 2026-08-24) -- Apptegy,
# but its real employment page URL isn't a plain nav link (found instead
# by decoding the site's own `window.clientWorkStateTemp` JSON menu tree
# for a nested "School Information > Employment information > Employment"
# slug, the same technique used for Dutton/Brady/Harlowton/Melstone in
# earlier sessions). Real postings render as a genuine 3-column
# (Job Title/Job Type/Job Description) table -- reuses Arlee's own
# repeating-triples technique unchanged. Confirmed live 2026-08-24, 2
# real postings (Substitute Teachers, Various Substitutes). Stops at
# "Find Us", the real, stable boundary before contact info.
parse_parkcity_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "EMPLOYMENT OPPORTUNITIES")
  if (length(start_idx) == 0) return(empty)
  body <- lines[(start_idx[1] + 4):length(lines)]

  stop_idx <- which(body == "Find Us")
  if (length(stop_idx) > 0) body <- body[seq_len(stop_idx[1] - 1)]

  n_rows <- length(body) %/% 3
  if (n_rows == 0) return(empty)
  titles <- body[seq(1, by = 3, length.out = n_rows)]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Park City", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_parkcity_postings <- function(chromote_session, url = "https://www.parkcityschools.org/page/employment-information") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_parkcity_postings(text, url)
}

# Alberton School District (alberton.k12.mt.us, found 2026-08-24 in the
# first pass against OPI's own full district list -- see
# [[mt-dashboard-full-opi-coverage-goal]]) -- Apptegy, but a genuinely
# hybrid page shape combining 3 different real structures: (1) a single
# prose-style posting whose title sits before a literal "|"-delimited
# "Title | Classified Application | 2026-2027 School Year" line (matched
# by regex on the trailing "School Year" rather than a fixed title,
# since the school year changes annually); (2) a flat "Coaching
# Positions" list, stopping at the real "Letter of interest..." sentence
# boundary; (3) a single standalone "Substitute Teachers" line with no
# header of its own. Confirmed live 2026-08-24, 6 real postings across
# all 3 shapes.
parse_alberton_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  rows <- list()

  pipe_idx <- which(grepl("\\|.*School Year$", lines))
  for (i in pipe_idx) {
    title <- trimws(strsplit(lines[i], "\\|")[[1]][1])
    rows[[length(rows) + 1]] <- title
  }

  coach_idx <- which(lines == "Coaching Positions")
  if (length(coach_idx) > 0) {
    remaining <- lines[(coach_idx[1] + 1):length(lines)]
    stop_idx <- which(grepl("^Letter of interest", remaining))
    if (length(stop_idx) > 0) remaining <- remaining[seq_len(stop_idx[1] - 1)]
    for (t in remaining) rows[[length(rows) + 1]] <- t
  }

  sub_idx <- which(lines == "Substitute Teachers")
  for (i in sub_idx) rows[[length(rows) + 1]] <- lines[i]

  titles <- unlist(rows)
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Alberton", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_alberton_postings <- function(chromote_session, url = "https://www.asdmt.org/page/employment-opportunities") {
  # District migrated domain from alberton.k12.mt.us to asdmt.org; the legacy
  # domain redirects via HTTP and can hang headless Chrome navigations.
  if (grepl("alberton\\.k12\\.mt\\.us", url)) {
    url <- sub("https?://(www\\.)?alberton\\.k12\\.mt\\.us", "https://www.asdmt.org", url)
  }
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_alberton_postings(text, url)
}

# Dillon School District 10 (dillonschools.org, found 2026-08-24) --
# Apptegy. Real postings are a genuinely flat, single-category list
# right after "Employment Opportunities" (the same flat-list shape as
# Darby above). Confirmed live 2026-08-24, 3 real postings. Stops at
# "Collective Bargaining Agreements and Salary Schedules can be viewed
# here.", the real, stable boundary before document links.
parse_dillon_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Employment Opportunities")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  stop_idx <- which(grepl("^Collective Bargaining Agreements", lines))
  if (length(stop_idx) > 0) lines <- lines[seq_len(stop_idx[1] - 1)]

  titles <- lines[nzchar(lines)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Dillon", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_dillon_postings <- function(chromote_session, url = "https://www.dillonschools.org/page/employment-opportunities") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_dillon_postings(text, url)
}

# Ennis Schools (ennisschools.org, found 2026-08-24) -- Apptegy, an
# older prose-description template (each real posting is a title
# immediately followed by a full job-description block, the same shape
# as Hays-Lodge Pole/Dutton above), plus a separate flat "Various
# Coaching Positions Open" list. Real Classified titles are found by the
# literal "Reports to:" line that immediately follows each one -- a
# reliable marker unique to this page's own template, the same
# marker-after-title technique as Bigfork's/Hysham's own pages.
# Confirmed live 2026-08-24, 5 real postings (2 Classified + 3
# Coaching); the page's own "CERTIFIED POSITIONS" section says "NONE AT
# THIS TIME", a real empty state correctly excluded since nothing here
# depends on that header at all.
parse_ennis_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  rows <- list()

  reports_idx <- which(grepl("^Reports to:", lines))
  reports_idx <- reports_idx[reports_idx > 1]
  for (i in reports_idx) {
    title <- lines[i - 1]
    if (nzchar(title)) rows[[length(rows) + 1]] <- title
  }

  coach_idx <- which(lines == "Various Coaching Positions Open")
  if (length(coach_idx) > 0) {
    remaining <- lines[(coach_idx[1] + 1):length(lines)]
    stop_idx <- which(grepl("^Reports to:", remaining))
    if (length(stop_idx) > 0) remaining <- remaining[seq_len(stop_idx[1] - 1)]
    for (t in remaining) rows[[length(rows) + 1]] <- t
  }

  titles <- unlist(rows)
  titles <- titles[nzchar(titles)]
  titles <- unique(titles)
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Ennis", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_ennis_postings <- function(chromote_session, url = "https://www.ennisschools.org/page/job-opportunities") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_ennis_postings(text, url)
}

# Columbus Public Schools (columbuscougars.com, found 2026-08-24) --
# Apptegy, but its real employment page URL isn't a plain nav link
# (found instead by decoding the site's own `window.clientWorkStateTemp`
# JSON menu tree for a nested "District Information > District
# Employment Opportunities" slug). Also a genuine same-named-district-
# elsewhere trap: an early search hit (columbuspublicschools.org) is
# Columbus, Nebraska, not Montana -- confirmed by the real Columbus, NE
# address on that page before it was discarded. Real postings render as
# a genuine 2-column (Opportunity/Description) table -- reuses Arlee's/
# Park City's own repeating-triples technique (title, "Apply Online",
# description), just a 2-column header instead of 3. Confirmed live
# 2026-08-24, 2 real postings (Facilities Technician, Substitute).
# Stops at "Find Us", the real, stable boundary before contact info.
parse_columbus_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Employment Opportunities")
  if (length(start_idx) == 0) return(empty)
  body <- lines[(start_idx[1] + 3):length(lines)]

  stop_idx <- which(body == "Find Us")
  if (length(stop_idx) > 0) body <- body[seq_len(stop_idx[1] - 1)]

  n_rows <- length(body) %/% 3
  if (n_rows == 0) return(empty)
  titles <- body[seq(1, by = 3, length.out = n_rows)]
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Columbus", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_columbus_postings <- function(chromote_session, url = "https://columbuscougars.com/page/district-employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_columbus_postings(text, url)
}

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

# Shields Valley Public Schools (svalleyk12.org, serving both Clyde Park
# and Wilsall -- the OPI feed's "CLYDE PARK" and "WILSALL" rows are the
# same single district) -- found in the same follow-up pass. Genuinely
# Finalsite (confirmed by the real "Powered by Finalsite" footer), a plain
# httr2 fetch, no chromote needed. Real postings each sit inside their own
# real `<p>` (or share a `<p>` with the preceding one via a real `<br>`,
# e.g. the header "Park Special Education Co-op Openings" and its one
# posting), each posting authored as a real `<a href="...google docs...">
# TITLE</a>` link -- title text lives inside the anchor itself, not
# guessed from surrounding prose. A posting already filled shows the same
# `<a>` markup plus the real word "Filled" elsewhere in the same line
# (confirmed live: 8 of 12 real posting lines are Filled right now) --
# excluded by checking for that literal word in the line's full plain
# text, the same "currently filled, not really open" judgment call Wolf
# Point's EAE exclusion and Conrad's stale-posting exclusion already made
# elsewhere in this file. Confirmed live 2026-08-23: 4 real currently-open
# postings across 3 of the page's 4 real "<Category> Openings" headers
# (K-12 Art under Certified Teacher; Maintenance/Grounds/Custodial
# Technician and High Needs Para Educator under Classified Staff;
# Occupational Therapist under Park Special Education Co-op -- Coaching/
# Advisor's own single posting, Head HS Football Coach, is Filled).
fetch_shieldsvalley_postings <- function(url = "https://svalleyk12.org/district/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_shieldsvalley_postings(resp_body_string(resp), url)
}

parse_shieldsvalley_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  containers <- rvest::html_elements(page, ".fsElementContent")
  target <- NULL
  for (container in containers) {
    if (grepl("Certified Teacher Openings", rvest::html_text2(container), fixed = TRUE)) {
      target <- container
      break
    }
  }
  if (is.null(target)) return(empty)

  frag_html <- as.character(target)
  x <- gsub("<p[^>]*>|</p>|<br\\s*/?>", "\n", frag_html)
  lines <- strsplit(x, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  rows <- list()
  current_header <- NA_character_
  for (line in lines) {
    plain <- trimws(gsub("<[^>]+>", "", line))
    if (grepl(" Openings$", plain)) {
      current_header <- sub(" Openings$", "", plain)
      next
    }
    if (is.na(current_header)) next
    a_match <- regmatches(line, regexpr("<a[^>]*>.*?</a>", line))
    if (length(a_match) == 0) next
    if (grepl("Filled", plain, fixed = TRUE)) next
    title <- trimws(gsub("<[^>]+>", "", sub("^<a[^>]*>(.*)</a>$", "\\1", a_match)))
    if (!nzchar(title)) next
    rows[[length(rows) + 1]] <- data.frame(Title = title, Location = current_header,
                                            Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# Apptegy content pages are a client-side-rendered Nuxt app -- a plain
# httr2 request gets a Fastly JS bot-challenge shell (3038 bytes, real
# content never reaches a non-JS-executing client at all), confirmed live
# 2026-08-07 for both districts. Real content only renders via an actual
# browser (chromote passes the challenge the same way any real browser
# would). This is the exact same platform Wyoming's own
# misc_district_scrapers.R already built chromote support for (4 of its
# own districts sit on Apptegy too) -- the browser-driving architecture
# (a shared session across every district that needs one, injected as a
# factory so the rest of this file's tests don't need a real browser) is
# ported directly from Wyoming's fetch_all_misc_district_postings(). The
# per-district PARSING is NOT ported, though -- Wyoming's 4 districts
# write free, unstructured prose (needing 3 separate regex heuristics just
# there); Montana's two are both cleanly structured (a real "Find Us"
# footer line reliably marks the end of real page content on every
# Apptegy page checked this session, used as a shared stop boundary
# below), so each gets its own straightforward parser instead.
#
# Both fetch_*_postings() functions take a live chromote_session (created
# once by fetch_apptegy_k12_postings() below and reused across both
# districts) rather than creating their own -- avoids paying browser
# startup cost twice.
fetch_wolfpoint_postings <- function(chromote_session, url = "https://www.wolfpointschools.org/page/job-opportunities-1") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(5)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_wolfpoint_postings(text, url)
}

# Real postings are grouped under ALL-CAPS section headers ending in ":"
# (ADMINISTRATIVE:, CERTIFIED OPENINGS:, CLASSIFIED OPENINGS:, DISTRICT:,
# OTHER OPENINGS:, COACHES:) -- confirmed live 2026-08-07, 19 real
# postings. One more header, "CERTIFIED POSITIONS CURRENTLY FILLED BY
# EAE'S*:", is deliberately excluded -- these are positions currently
# staffed by Emergency Authorized Educators, not real open postings (the
# page's own footnote explains this), matched by "CURRENTLY FILLED" in
# the header text. After the real section headers end, the page continues
# with real prose (application instructions, benefits info, a "Join the
# Team" staff-testimonial section) that a naive "everything after a
# header" scrape would wrongly sweep in -- filtered out here two ways:
# looks_like_wolfpoint_title() rejects anything that reads like a
# sentence (ends in "." or ":", starts with a digit-dot list marker, or is
# simply too long for a real job title), and the scan stops entirely at
# "Find Us" or "Join the Team", two real, stable section boundaries on
# this specific page (not a general Apptegy template guarantee -- a
# future district might not have "Join the Team" at all, which is fine,
# "Find Us" alone is confirmed present on every Apptegy page checked this
# session as the real footer start).
WOLFPOINT_STOP_LINES <- c("Find Us", "Join the Team")

looks_like_wolfpoint_title <- function(line) {
  if (nchar(line) > 55) return(FALSE)
  if (grepl("[.:]$", line)) return(FALSE)
  if (grepl("^[0-9]+\\.", line)) return(FALSE)
  if (!grepl("[A-Za-z]", line)) return(FALSE)
  if (grepl("^\\*", line)) return(FALSE)
  TRUE
}

parse_wolfpoint_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "JOB OPENINGS")
  if (length(start_idx) == 0) return(empty)
  lines <- lines[(start_idx[1] + 1):length(lines)]

  header_pattern <- "^[A-Z][A-Za-z0-9 /'*]+:$"
  titles <- character(0)
  current_header <- NA_character_
  skipping <- FALSE
  for (line in lines) {
    if (line %in% WOLFPOINT_STOP_LINES) break
    if (grepl(header_pattern, line)) {
      current_header <- line
      skipping <- grepl("CURRENTLY FILLED", line)
      next
    }
    if (!skipping && !is.na(current_header) && looks_like_wolfpoint_title(line)) {
      titles <- c(titles, line)
    }
  }

  if (length(titles) == 0) return(empty)
  data.frame(Title = titles, Location = "Wolf Point", Posted_Date = NA_character_,
             Link = url, stringsAsFactors = FALSE)
}

fetch_plentywood_postings <- function(chromote_session, url = "https://www.plentywood.k12.mt.us/o/plentywood/page/employment-opportunities") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(5)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_plentywood_postings(text, url)
}

# Real postings are a numbered list embedded mid-paragraph, not a real
# HTML list -- confirmed live 2026-08-07: "Classified Positions available
# (as of July 13,2026)Plentywood School has the following classified jobs
# available immediately 1. Assistant Cook  2. Activities Bus Driver
# 3. Substitute Teachers 4. Paraprofessional" is one single line of
# rendered text. The "(as of <date>)" phrase in that same sentence is a
# genuine Posted_Date signal (unlike Wolf Point/Stone Child, which have
# none at all) -- applied to every title extracted from that paragraph,
# since it's the one real date this page gives for the whole batch, not a
# per-posting date. Only a "Classified Positions" paragraph was found live
# -- no separate "Certified Positions" paragraph currently exists on the
# page, a real absence (no certified vacancies posted right now), not a
# parsing gap.
parse_plentywood_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  target_lines <- lines[grepl("^Classified Positions available|^Certified Positions available", lines)]
  if (length(target_lines) == 0) return(empty)

  rows <- lapply(target_lines, function(target_line) {
    date_match <- regmatches(target_line, regexpr("as of [A-Za-z]+ [0-9]+,\\s*[0-9]{4}", target_line))
    posted_date <- if (length(date_match) > 0 && nzchar(date_match)) {
      as.character(as.Date(sub("as of ", "", date_match), format = "%B %d,%Y"))
    } else {
      NA_character_
    }

    items <- regmatches(target_line, gregexpr("[0-9]+\\.\\s*[A-Za-z][A-Za-z '&/-]*", target_line))[[1]]
    titles <- trimws(sub("^[0-9]+\\.\\s*", "", items))
    titles <- titles[nzchar(titles)]
    if (length(titles) == 0) return(NULL)

    data.frame(Title = titles, Location = "Plentywood", Posted_Date = posted_date,
               Link = url, stringsAsFactors = FALSE)
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]

  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

# The 6 districts added 2026-08-16 (see their own parse_*_postings()
# comments above) all fetch the same way: navigate, wait for load, then pull
# EITHER document.documentElement.outerHTML (Conrad/Gardiner/Drummond, whose
# real content only exists in the page's embedded JSON payload, not
# rendered text) or document.body.innerText (Westby/Choteau/Malta, same
# rendered-text technique as Wolf Point/Plentywood below).
fetch_conrad_postings <- function(chromote_session, url = "https://conradschools.org/page/employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  html <- chromote_session$Runtime$evaluate("document.documentElement.outerHTML")$result$value
  parse_conrad_postings(html, url)
}

fetch_gardiner_postings <- function(chromote_session, url = "https://www.gardiner.org/page/job-openings") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  html <- chromote_session$Runtime$evaluate("document.documentElement.outerHTML")$result$value
  parse_gardiner_postings(html, url)
}

fetch_drummond_postings <- function(chromote_session, url = "https://www.drummondschool.net/page/application") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  html <- chromote_session$Runtime$evaluate("document.documentElement.outerHTML")$result$value
  parse_drummond_postings(html, url)
}

fetch_westby_postings <- function(chromote_session, url = "https://westbyschool.k12.mt.us/page/job-openings-applications") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_westby_postings(text, url)
}

fetch_choteau_postings <- function(chromote_session, url = "https://www.choteauschools.net/o/csd/page/employment-at-choteau-school-district") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_choteau_postings(text, url)
}

fetch_malta_postings <- function(chromote_session, url = "https://www.maltaschools.org/page/district-employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_malta_postings(text, url)
}

fetch_deerlodge_postings <- function(chromote_session, url = "https://www.deerlodgeschools.org/page/employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  html <- chromote_session$Runtime$evaluate("document.documentElement.outerHTML")$result$value
  parse_deerlodge_postings(html, url)
}

fetch_townsend_postings <- function(chromote_session, url = "https://www.townsend.k12.mt.us/page/employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_townsend_postings(text, url)
}

fetch_savage_postings <- function(chromote_session, url = "https://www.savagepublicschool.com/page/employment") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  html <- chromote_session$Runtime$evaluate("document.documentElement.outerHTML")$result$value
  parse_savage_postings(html, url)
}

# Fetches all 43 districts (40 Apptegy + Geyser's CyberSchool + St.
# Ignatius's and Hamilton's Red Rover Hiring) sharing one chromote session (created
# once here, closed at the end) -- mirrors Wyoming's
# fetch_all_misc_district_postings()'s chromote_session_factory pattern,
# just scoped to only the districts that need it instead of being
# threaded through every platform in this file. chromote_session_factory
# defaults to NULL so this function -- and by extension
# Mt_ED_Jobs.Rmd's own use of it -- stays testable without a real browser
# available; passing NULL returns an empty result for every district (via
# safe_scrape's own error handling) rather than crashing.
# The full set of districts fetch_apptegy_k12_postings() scrapes by default,
# keyed by the exact registry District name each one's row uses -- pulled
# out to a top-level constant (rather than a literal inside the function)
# specifically so test-misc-district-scrapers.R's own cross-check test can
# assert names(APPTEGY_DISTRICT_SCRAPERS) exactly matches
# k12_district_registry.csv's Apptegy/RedRoverK12 rows, in both directions.
# That test exists because this list and the registry are NOT the same
# data (one's a District -> fetch-function map, the other's the Map/District
# Summary join target) and nothing else keeps them in sync -- a registry row
# added here without a matching entry (or vice versa) previously would have
# silently scraped nothing for that district, or scraped a district with no
# registry row to join against, for weeks before anyone noticed.
APPTEGY_DISTRICT_SCRAPERS <- list(
  "Wolf Point Public Schools" = fetch_wolfpoint_postings,
  "Plentywood Public Schools" = fetch_plentywood_postings,
  "Conrad Public Schools" = fetch_conrad_postings,
  "Westby School District 3" = fetch_westby_postings,
  "Choteau School District" = fetch_choteau_postings,
  "Gardiner Public Schools" = fetch_gardiner_postings,
  "Malta Public Schools" = fetch_malta_postings,
  "Drummond Public Schools" = fetch_drummond_postings,
  "Deer Lodge School District #1" = fetch_deerlodge_postings,
  "Townsend School District" = fetch_townsend_postings,
  "Hays-Lodge Pole School District" = fetch_hayslodgepole_postings,
  "Plevna School District #55" = fetch_plevna_postings,
  "Sunburst Schools" = fetch_sunburst_postings,
  "Belt Public Schools" = fetch_belt_postings,
  "Big Sky School District 72" = fetch_bigsky_postings,
  "Melstone Public Schools" = fetch_melstone_postings,
  "Roundup School District" = fetch_roundup_postings,
  "White Sulphur Springs Schools" = fetch_wss_postings,
  "Shelby School District" = fetch_shelbymt_postings,
  "Geyser Public Schools" = fetch_geyser_postings,
  "Centerville Public Schools" = fetch_centerville_postings,
  "Arlee Joint School District" = fetch_arlee_postings,
  "Chinook Public Schools" = fetch_chinook_postings,
  "Darby School District 9" = fetch_darby_postings,
  "Dutton/Brady Public School District" = fetch_dutton_postings,
  "St. Ignatius School District" = function(session) {
    fetch_redrover_postings(session, "https://jobs.redroverk12.com/org/2261")
  },
  "Hamilton School District 3" = function(session) {
    fetch_redrover_postings(session, "https://jobs.redroverk12.com/org/2362",
                            default_location = "Hamilton")
  },
  "Columbia Falls School District 6" = function(session) {
    fetch_redrover_postings(session, "https://jobs.redroverk12.com/org/sd659912",
                            default_location = "Columbia Falls")
  },
  "Stanford Public Schools" = fetch_stanford_postings,
  "Lolo School District 7" = fetch_lolo_postings,
  "Froid Public Schools" = fetch_froid_postings,
  "Huntley Project School District" = fetch_huntley_postings,
  "Park City Schools" = fetch_parkcity_postings,
  "Alberton School District" = fetch_alberton_postings,
  "Dillon School District 10" = fetch_dillon_postings,
  "Ennis Schools" = fetch_ennis_postings,
  "Columbus Public Schools" = fetch_columbus_postings,
  "St Regis School District" = fetch_stregis_postings,
  "Florence-Carlton School District 15-6" = fetch_florencecarlton_postings,
  "West Yellowstone School District" = fetch_westyellowstone_postings,
  "Bonner School District #14" = fetch_bonner_postings,
  "Deer Park School District" = fetch_deerpark_postings,
  "Evergreen School District #50" = fetch_evergreen_postings,
  "Lone Rock School District" = fetch_lonerock_postings,
  "Sweet Grass County High School" = fetch_bigtimber_postings,
  "Hot Springs School District" = fetch_hotsprings_postings,
  "Frenchtown K-12 Schools" = fetch_frenchtown_postings,
  "Savage Public Schools" = fetch_savage_postings
)

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

# Sheridan Public Schools (sheridan.k12.mt.us, found 2026-10-21
# via OPI Directory) -- Madison County K-12 district on Published Google Sites.
# Confirmed live 2026-10-21: 4 active postings (Varsity Boys' Basketball-Head and
# Assistant Coach, Varsity Girls' Basketball-Assistant Coach, Substitute Teachers,
# Substitute Bus Drivers). Plain httr2 fetch, no chromote needed.
fetch_sheridan_postings <- function(url = "https://www.sheridan.k12.mt.us/district/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_sheridan_postings(resp_body_string(resp), url)
}

parse_sheridan_postings <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  page <- rvest::read_html(html_text)
  text <- rvest::html_text2(page)
  lines <- trimws(strsplit(text, "\n")[[1]])
  lines <- lines[nzchar(lines)]
  start_idx <- which(grepl("accepting applications for the following positions", lines))
  stop_idx <- which(grepl("SHERIDAN SCHOOL DISTRICT OPERATES ON A FOUR-DAY|Certified Application", lines))
  if (length(start_idx) == 0 || length(stop_idx) == 0) return(empty)

  block <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]
  titles <- character(0)
  for (l in block) {
    if (grepl("Applications for the following|winter/spring coaching positions", l, ignore.case = TRUE)) next
    clean_l <- sub(" \\(.*", "", l)
    clean_l <- trimws(clean_l)
    if (nzchar(clean_l)) titles <- c(titles, clean_l)
  }
  if (length(titles) == 0) return(empty)
  data.frame(Title = titles, Location = "Sheridan", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
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

# Lambert School District (Richland County) -- Finalsite CMS,
# plain httr2 fetch, no chromote needed. Active positions listed
# in #fsPageContent .fsContent ul li.
fetch_lambert_postings <- function(url = "https://www.lambertschool.net/career-opportunities/employment-opportunities") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_lambert_postings(resp_body_string(resp), url)
}

parse_lambert_postings <- function(html_text, url = "https://www.lambertschool.net/career-opportunities/employment-opportunities") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  page <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(page)) return(empty)
  lis <- rvest::html_elements(page, "#fsPageContent .fsContent ul li, main .fsContent ul li")
  if (length(lis) == 0) return(empty)

  raw_titles <- rvest::html_text(lis, trim = TRUE)
  raw_titles <- raw_titles[nzchar(raw_titles)]

  clean_titles <- character(0)
  for (t in raw_titles) {
    cleaned <- trimws(gsub("(?i)click here.*|,\\s*for job description.*", "", t))
    if (nzchar(cleaned) && nchar(cleaned) < 90 &&
        !grepl("^Applications?|Master Agreement|Alumni|None|Equal Opportunity", cleaned, ignore.case = TRUE)) {
      clean_titles <- c(clean_titles, cleaned)
    }
  }
  if (length(clean_titles) == 0) return(empty)

  data.frame(
    Title = clean_titles,
    Location = "Lambert",
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
# Ashland Public School (Published Google Sites Page)
# ---------------------------------------------------------------------------
fetch_ashland_postings <- function(url = "https://sites.google.com/ashlandpublicschool.com/aps-district-site/employment") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_ashland_postings(resp_body_string(resp), url = url)
}

parse_ashland_postings <- function(html_text, url = "https://sites.google.com/ashlandpublicschool.com/aps-district-site/employment") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  nodes <- rvest::html_elements(doc, "p.zfr3Q")
  texts <- trimws(rvest::html_text(nodes))
  start_idx <- grep("LOOKING FOR", texts, ignore.case = TRUE)
  end_idx <- grep("SCHOOL YEAR", texts, ignore.case = TRUE)
  if (length(start_idx) == 0 || length(end_idx) == 0 || end_idx[1] <= start_idx[1]) {
    return(empty)
  }

  roles <- texts[(start_idx[1] + 1):(end_idx[1] - 1)]
  roles <- trimws(gsub("[\u00a0\r\n\t ]+", " ", roles))
  roles <- roles[nzchar(roles)]
  roles <- gsub("Elementary Teacer", "Elementary Teacher", roles)
  roles <- unique(roles)
  if (length(roles) == 0) return(empty)

  data.frame(
    Title = roles,
    Location = "Ashland",
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
# Cayuse Prairie School District #10 (Apptegy CMS / Custom Notice)
# ---------------------------------------------------------------------------
fetch_cayuseprairie_postings <- function(url = "https://www.cayuseprairie.com/page/employment") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_cayuseprairie_postings(resp_body_string(resp), url = url)
}

parse_cayuseprairie_postings <- function(html_text, url = "https://www.cayuseprairie.com/page/employment") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  p_nodes <- rvest::html_elements(doc, "p")
  if (length(p_nodes) == 0) return(empty)

  roles <- character(0)
  for (p in p_nodes) {
    text <- trimws(rvest::html_text(p))
    if (grepl("^[0-9]+[)][[:space:]]*Cayuse Prairie School is (looking for|seeking)", text, ignore.case = TRUE)) {
      highlight <- rvest::html_elements(p, "span[style*='background-color'] strong, span strong")
      if (length(highlight) > 0) {
        role <- trimws(rvest::html_text(highlight[1]))
      } else {
        role <- sub("^[0-9]+[)][[:space:]]*Cayuse Prairie School is (?:looking for|seeking)[[:space:]]+(?:a[[:space:]]+)?", "", text, ignore.case = TRUE)
        role <- sub("[.].*$", "", role)
      }
      role <- trimws(gsub("[\u00a0\r\n\t ]+", " ", role))
      if (nzchar(role)) roles <- c(roles, role)
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
# Big Timber Grade School (Published Google Sites Page)
# ---------------------------------------------------------------------------
fetch_bigtimbergs_postings <- function(url = "https://sites.google.com/a/bigtimber-gs.k12.mt.us/btgs/staff/employment") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_bigtimbergs_postings(resp_body_string(resp), url = url)
}

parse_bigtimbergs_postings <- function(html_text, url = "https://sites.google.com/a/bigtimber-gs.k12.mt.us/btgs/staff/employment") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  roles <- character(0)
  p_nodes <- rvest::html_elements(doc, "p.zfr3Q, div.NsaAfc p")
  for (p in p_nodes) {
    txt <- trimws(rvest::html_text(p))
    if (grepl("accepting (?:applications|applicants) for (?:a )?", txt, ignore.case = TRUE)) {
      role <- sub(".*accepting (?:applications|applicants) for (?:a )?", "", txt, ignore.case = TRUE)
      role <- sub("[.].*$", "", role)
      role <- trimws(gsub("[\u00a0\r\n\t ]+", " ", role))
      if (nzchar(role)) roles <- c(roles, role)
    }
  }

  btn_nodes <- rvest::html_elements(doc, "a[aria-label*='Opening']")
  for (btn in btn_nodes) {
    lbl <- rvest::html_attr(btn, "aria-label")
    lbl <- sub("[[:space:]]+Opening$", "", trimws(lbl), ignore.case = TRUE)
    lbl <- trimws(gsub("[\u00a0\r\n\t ]+", " ", lbl))
    if (nzchar(lbl)) roles <- c(roles, lbl)
  }

  roles <- unique(roles)
  if (length(roles) == 0) return(empty)

  data.frame(
    Title = roles,
    Location = "Big Timber",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Elder Grove School District (Finalsite Posts CMS)
# ---------------------------------------------------------------------------
fetch_eldergrove_postings <- function(url = "https://www.eldergrove.k12.mt.us/about-eg/employment/available-positions") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_eldergrove_postings(resp_body_string(resp), url = url)
}

parse_eldergrove_postings <- function(html_text, url = "https://www.eldergrove.k12.mt.us/about-eg/employment/available-positions") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  titles <- rvest::html_elements(doc, ".fsListItems article .fsTitle a, .fsTitle a.fsPostLink")
  if (length(titles) == 0) return(empty)

  roles <- unique(trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(titles))))
  roles <- roles[nzchar(roles)]
  roles <- roles[!grepl("^(?:Certified|Classified) Positions?$", roles, ignore.case = TRUE)]
  if (length(roles) == 0) return(empty)

  data.frame(
    Title = roles,
    Location = "Billings",
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
# Hellgate Elementary School District #4 (hellgate.k12.mt.us)
# ---------------------------------------------------------------------------
fetch_hellgate_postings <- function(url = "https://www.hellgate.k12.mt.us/our-district/employment") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_hellgate_postings(resp_body_string(resp), url = url)
}

parse_hellgate_postings <- function(html_text, url = "https://www.hellgate.k12.mt.us/our-district/employment") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  content <- rvest::html_element(doc, "#fsPageContent")
  if (is.null(content)) return(empty)

  links <- rvest::html_elements(content, "span.fs_style_1 a, .fsElementContent a")
  if (length(links) == 0) return(empty)

  titles <- character(0)
  urls_out <- character(0)

  for (a in links) {
    txt <- trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(a)))
    href <- rvest::html_attr(a, "href")
    if (grepl("Substitute|Teacher|Para|Custodial|Food Service|Nurse|Driver|Coach|Aide|Specialist|Principal|Superintendent", txt, ignore.case = TRUE) &&
        !grepl("Forms|Schools|Handbook|Policy", txt, ignore.case = TRUE)) {
      full_link <- if (!is.na(href) && nzchar(href)) xml2::url_absolute(href, url) else url
      titles <- c(titles, txt)
      urls_out <- c(urls_out, full_link)
    }
  }

  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = "Missoula",
    Posted_Date = NA_character_,
    Link = urls_out,
    stringsAsFactors = FALSE
  )
  unique(df)
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
# Woodman Elementary School District #3 (Google Sites)
# ---------------------------------------------------------------------------
fetch_woodman_postings <- function(url = "http://www.woodmanschool.org/district-information/employment-opportunities") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_woodman_postings(resp_body_string(resp), url = url)
}

parse_woodman_postings <- function(html_text, url = "http://www.woodmanschool.org/district-information/employment-opportunities") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  paras <- rvest::html_elements(doc, "p, h1, h2, h3, h4, li")
  roles <- character(0)
  for (p in paras) {
    txt <- trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(p)))
    if (grepl("accepting applications for substitute teachers|substitute teacher application", txt, ignore.case = TRUE)) {
      roles <- c(roles, "Substitute Teacher")
    }
  }

  roles <- unique(roles)
  if (length(roles) == 0) return(empty)

  data.frame(
    Title = roles,
    Location = "Lolo",
    Posted_Date = NA_character_,
    Link = url,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Vaughn Elementary School District #74 (CyberSchool CMS)
# ---------------------------------------------------------------------------
fetch_vaughn_postings <- function(url = "https://www.vaughnschool.com/District/Jobs/") {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  parse_vaughn_postings(resp_body_string(resp), url = url)
}

parse_vaughn_postings <- function(html_text, url = "https://www.vaughnschool.com/District/Jobs/") {
  empty <- data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  doc <- tryCatch(rvest::read_html(html_text), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  nodes <- rvest::html_elements(doc, ".listItem_headingLink, .data_headingLink")
  if (length(nodes) == 0) return(empty)

  titles <- character(0)
  links_out <- character(0)
  for (n in nodes) {
    txt <- trimws(gsub("[\u00a0\r\n\t ]+", " ", rvest::html_text(n)))
    href <- rvest::html_attr(n, "href")
    if (nzchar(txt) && !grepl("^(?:Title|Jobs)$", txt, ignore.case = TRUE)) {
      full_link <- if (!is.na(href) && nzchar(href)) xml2::url_absolute(href, url) else url
      titles <- c(titles, txt)
      links_out <- c(links_out, full_link)
    }
  }

  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = "Vaughn",
    Posted_Date = NA_character_,
    Link = links_out,
    stringsAsFactors = FALSE
  )
  unique(df)
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
# Power Public Schools
# ---------------------------------------------------------------------------
fetch_power_postings <- function(url) {
  resp <- request(url) %>%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %>%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_power_postings(html, url)
}

parse_power_postings <- function(html, url) {
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

  links <- html_elements(doc, "a[href*=\"/District/Jobs/\"], a[href*=\"Jobs/\"]")
  titles <- character(0)
  links_out <- character(0)

  for (a in links) {
    href <- html_attr(a, "href")
    txt <- trimws(html_text2(a))
    if (grepl("[0-9]+-[A-Za-z0-9_-]+[.]html$", href) && nzchar(txt)) {
      titles <- c(titles, txt)
      links_out <- c(links_out, xml2::url_absolute(href, url))
    }
  }

  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = rep("Power", length(titles)),
    Posted_Date = rep(NA_character_, length(titles)),
    Link = links_out,
    stringsAsFactors = FALSE
  )
  unique(df)
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
fetch_cji_postings <- function(url = "https://www.cji.k12.mt.us/page/employmentcji") {
  pdf_url <- "https://aptg.co/c5tzQ5"
  text <- tryCatch({
    tmp <- tempfile(fileext = ".pdf")
    on.exit(unlink(tmp), add = TRUE)
    resp <- request(pdf_url) %>%
      req_headers("User-Agent" = "Mozilla/5.0") %>%
      perform_with_retry()
    writeBin(resp_body_raw(resp), tmp)
    paste(pdftools::pdf_text(tmp), collapse = "\n")
  }, error = function(e) "")
  parse_cji_postings(text, url)
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
# district whose Platform isn't one of the four real ATS platforms this
# project scrapes via a documented API (direct_api_scrapers.R). Every other
# Platform value (Apptegy, RedRoverK12, and every single-district
# `*Heuristic` platform) is scraped via this file -- misc_district_scrapers.R's
# own header comment already calls this whole file "a real but
# acknowledged-less-reliable source" relative to direct_api_scrapers.R's
# real platform APIs, so this function just makes that existing,
# already-true distinction visible on the dashboard instead of leaving it
# sitting only in code comments.
MT_DIRECT_API_PLATFORMS <- c("AppliTrack", "SchoolSpring", "TedK12", "TylerPortico")

# registry_csv is a parameter (not a hardcoded read) so this stays testable
# against a synthetic registry without touching the real committed file.
# Every district not returned here is implicitly "Full" -- callers coalesce
# a missing match to that, the same convention Wyoming's own version uses.
k12_district_coverage_tiers <- function(registry_csv = "k12_district_registry.csv") {
  registry <- read.csv(registry_csv, stringsAsFactors = FALSE)
  partial <- registry[!(registry$Platform %in% MT_DIRECT_API_PLATFORMS), ]
  data.frame(District = partial$District, Data_Coverage = "Partial", stringsAsFactors = FALSE)
}
