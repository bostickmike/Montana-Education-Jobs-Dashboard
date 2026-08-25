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
    req_perform()
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
      req_perform()
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
      req_perform()
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
fetch_custer_postings <- function(url = "https://custerschools.org/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    req_perform()
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
    req_perform()
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
    req_perform()
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
    req_perform()
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
    req_user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36") %>%
    req_perform()
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
    req_perform()
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
    req_perform()
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
    req_perform()
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
    req_perform()
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
    req_perform()
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
    req_perform()
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
    req_perform()
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
    req_perform()
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
    req_perform()
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
    req_perform()
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
    req_perform()
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
    req_perform()
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
    req_perform()
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

  start_idx <- which(grepl("^Townsend School Job Vacancies:", lines))
  stop_idx <- which(lines == "ATHLETIC DIRECTOR")
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
    title <- if (grepl(" - ", line, fixed = TRUE)) trimws(sub(" -.*$", "", line)) else line
    if (nzchar(title)) {
      rows[[length(rows) + 1]] <- data.frame(Title = title, Location = location,
                                              Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
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
# -- confirmed live 2026-08-23, 5 real postings. A "Load More" button
# suggests additional postings may exist beyond what a plain fetch's
# initial HTML contains (unconfirmed either way -- this function only
# captures what's present without JS pagination, the same limitation
# every other plain-fetch scraper in this file already has). Stops at
# that "Load More" label, the real, stable boundary before the page's
# "Employment Information" boilerplate section.
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
  stop_idx <- which(lines == "Load More")
  if (length(stop_idx) == 0 || stop_idx[1] <= start_idx[1]) return(empty)

  titles <- lines[(start_idx[1] + 1):(stop_idx[1] - 1)]
  titles <- sub(" \\(opens in new window/tab\\)$", "", titles)
  titles <- titles[nzchar(titles)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Thompson Falls", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
}

fetch_thompsonfalls_postings <- function(url = "https://www.thompsonfalls.net/employment") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    req_perform()
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

# St. Ignatius School District (jobs.redroverk12.com/org/2261) -- found
# 2026-08-24 while re-checking the OPI-gap candidate list ("SAINT
# IGNATIUS" and "SAINT IGNATIUS- SALISH TEACHER" are the same district;
# both collapse into this one registry row). Red Rover Hiring, a new
# platform for this project -- a client-side-rendered Next.js app, no
# API endpoint findable in the static HTML, needs a real browser like
# Apptegy, folded into the same shared chromote session below for that
# reason even though it isn't Apptegy itself (same precedent as Geyser's
# CyberSchool 2.0). Confirmed live 2026-08-24: "Found 8 job openings",
# but 2 are generic evergreen application-form placeholders ("Classified
# Application", "Volunteer Application") rather than real openings --
# the same class of noise Arlee's own "Classified Application"/
# "Certified Application" exclusion handles, extended here with
# "Volunteer Application". Each real posting is a repeating block of
# [employment type, title, category, location, (salary, optional)]
# followed by a literal "APPLY NOW" line and then a relative-date line
# ("27 days ago") -- parsed by splitting on "APPLY NOW" as the reliable
# per-posting boundary (the salary line's presence varies, so a fixed
# stride doesn't work) and discarding the trailing date line, which
# standardize_date() can't parse anyway (Mt_Ed_Jobs.Rmd only handles
# absolute dates) so it isn't worth carrying through as free text.
# "No location specified" is the page's own literal placeholder for a
# real missing value, normalized to NA here rather than kept as prose.
STIGNATIUS_PLACEHOLDER_TITLES <- c("Classified Application", "Certified Application", "Volunteer Application")

parse_stignatius_postings <- function(rendered_text, url) {
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
    if (line == "APPLY NOW") {
      if (length(block) >= 2) {
        title <- block[2]
        location <- if (length(block) >= 4) block[4] else NA_character_
        if (!is.na(location) && location == "No location specified") location <- NA_character_
        if (!(title %in% STIGNATIUS_PLACEHOLDER_TITLES)) {
          rows[[length(rows) + 1]] <- data.frame(Title = title, Location = location,
                                                   Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
        }
      }
      block <- character(0)
      i <- i + 2
      next
    }
    block <- c(block, line)
    i <- i + 1
  }
  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}

fetch_stignatius_postings <- function(chromote_session, url = "https://jobs.redroverk12.com/org/2261") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(5)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_stignatius_postings(text, url)
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
    req_perform()
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
    req_perform()
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

# Fetches all 31 districts (29 Apptegy + Geyser's CyberSchool + St.
# Ignatius's Red Rover Hiring) sharing one chromote session (created
# once here, closed at the end) -- mirrors Wyoming's
# fetch_all_misc_district_postings()'s chromote_session_factory pattern,
# just scoped to only the districts that need it instead of being
# threaded through every platform in this file. chromote_session_factory
# defaults to NULL so this function -- and by extension
# Mt_ED_Jobs.Rmd's own use of it -- stays testable without a real browser
# available; passing NULL returns an empty result for every district (via
# safe_scrape's own error handling) rather than crashing.
fetch_apptegy_k12_postings <- function(chromote_session_factory = NULL) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       District = character(0), stringsAsFactors = FALSE)
  if (is.null(chromote_session_factory)) return(empty)

  session <- chromote_session_factory()
  on.exit(tryCatch(session$close(), error = function(e) NULL), add = TRUE)

  wolfpoint <- fetch_wolfpoint_postings(session)
  if (nrow(wolfpoint) > 0) wolfpoint$District <- "Wolf Point Public Schools"

  plentywood <- fetch_plentywood_postings(session)
  if (nrow(plentywood) > 0) plentywood$District <- "Plentywood Public Schools"

  conrad <- fetch_conrad_postings(session)
  if (nrow(conrad) > 0) conrad$District <- "Conrad Public Schools"

  westby <- fetch_westby_postings(session)
  if (nrow(westby) > 0) westby$District <- "Westby School District 3"

  choteau <- fetch_choteau_postings(session)
  if (nrow(choteau) > 0) choteau$District <- "Choteau School District"

  gardiner <- fetch_gardiner_postings(session)
  if (nrow(gardiner) > 0) gardiner$District <- "Gardiner Public Schools"

  malta <- fetch_malta_postings(session)
  if (nrow(malta) > 0) malta$District <- "Malta Public Schools"

  drummond <- fetch_drummond_postings(session)
  if (nrow(drummond) > 0) drummond$District <- "Drummond Public Schools"

  deerlodge <- fetch_deerlodge_postings(session)
  if (nrow(deerlodge) > 0) deerlodge$District <- "Deer Lodge School District #1"

  townsend <- fetch_townsend_postings(session)
  if (nrow(townsend) > 0) townsend$District <- "Townsend School District"

  hayslodgepole <- fetch_hayslodgepole_postings(session)
  if (nrow(hayslodgepole) > 0) hayslodgepole$District <- "Hays-Lodge Pole School District"

  plevna <- fetch_plevna_postings(session)
  if (nrow(plevna) > 0) plevna$District <- "Plevna School District #55"

  sunburst <- fetch_sunburst_postings(session)
  if (nrow(sunburst) > 0) sunburst$District <- "Sunburst Schools"

  belt <- fetch_belt_postings(session)
  if (nrow(belt) > 0) belt$District <- "Belt Public Schools"

  bigsky <- fetch_bigsky_postings(session)
  if (nrow(bigsky) > 0) bigsky$District <- "Big Sky School District 72"

  melstone <- fetch_melstone_postings(session)
  if (nrow(melstone) > 0) melstone$District <- "Melstone Public Schools"

  roundup <- fetch_roundup_postings(session)
  if (nrow(roundup) > 0) roundup$District <- "Roundup School District"

  wss <- fetch_wss_postings(session)
  if (nrow(wss) > 0) wss$District <- "White Sulphur Springs Schools"

  shelbymt <- fetch_shelbymt_postings(session)
  if (nrow(shelbymt) > 0) shelbymt$District <- "Shelby School District"

  geyser <- fetch_geyser_postings(session)
  if (nrow(geyser) > 0) geyser$District <- "Geyser Public Schools"

  centerville <- fetch_centerville_postings(session)
  if (nrow(centerville) > 0) centerville$District <- "Centerville Public Schools"

  arlee <- fetch_arlee_postings(session)
  if (nrow(arlee) > 0) arlee$District <- "Arlee Joint School District"

  chinook <- fetch_chinook_postings(session)
  if (nrow(chinook) > 0) chinook$District <- "Chinook Public Schools"

  darby <- fetch_darby_postings(session)
  if (nrow(darby) > 0) darby$District <- "Darby School District 9"

  dutton <- fetch_dutton_postings(session)
  if (nrow(dutton) > 0) dutton$District <- "Dutton/Brady Public School District"

  stignatius <- fetch_stignatius_postings(session)
  if (nrow(stignatius) > 0) stignatius$District <- "St. Ignatius School District"

  stanford <- fetch_stanford_postings(session)
  if (nrow(stanford) > 0) stanford$District <- "Stanford Public Schools"

  lolo <- fetch_lolo_postings(session)
  if (nrow(lolo) > 0) lolo$District <- "Lolo School District 7"

  froid <- fetch_froid_postings(session)
  if (nrow(froid) > 0) froid$District <- "Froid Public Schools"

  huntley <- fetch_huntley_postings(session)
  if (nrow(huntley) > 0) huntley$District <- "Huntley Project School District"

  parkcity <- fetch_parkcity_postings(session)
  if (nrow(parkcity) > 0) parkcity$District <- "Park City Schools"

  dplyr::bind_rows(wolfpoint, plentywood, conrad, westby, choteau, gardiner, malta, drummond, deerlodge, townsend,
                    hayslodgepole, plevna, sunburst, belt, bigsky, melstone, roundup, wss, shelbymt, geyser, centerville,
                    arlee, chinook, darby, dutton, stignatius, stanford, lolo, froid, huntley, parkcity)
}
