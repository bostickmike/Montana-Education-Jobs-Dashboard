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

# ---------------------------------------------------------------------------
# Apptegy (chromote-driven) -- Wolf Point, Plentywood, Conrad, Westby,
# Choteau, Gardiner, Malta, Drummond, Deer Lodge, Townsend
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

# Fetches all 10 Apptegy districts sharing one chromote session (created
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

  dplyr::bind_rows(wolfpoint, plentywood, conrad, westby, choteau, gardiner, malta, drummond, deerlodge, townsend)
}
