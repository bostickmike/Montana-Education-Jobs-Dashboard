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

suppressMessages({
  library(httr2)
  library(rvest)
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

# ---------------------------------------------------------------------------
# Apptegy (chromote-driven) -- Wolf Point, Plentywood
# ---------------------------------------------------------------------------

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

# Fetches both Apptegy districts sharing one chromote session (created
# once here, closed at the end) -- mirrors Wyoming's
# fetch_all_misc_district_postings()'s chromote_session_factory pattern,
# just scoped to only the 2 districts that need it instead of being
# threaded through every platform in this file. chromote_session_factory
# defaults to NULL so this function -- and by extension
# Mt_ED_Jobs.Rmd's own use of it -- stays testable without a real browser
# available; passing NULL returns an empty result for both districts
# (via safe_scrape's own error handling) rather than crashing.
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

  dplyr::bind_rows(wolfpoint, plentywood)
}
