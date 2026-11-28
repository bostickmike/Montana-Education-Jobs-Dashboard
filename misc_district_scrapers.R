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


# Lodge Grass Public Schools (lgschools.org) -- an "Educational Networks"
# (Not run since 2026-11-22: the registry row is Platform OPIOnly, the
# pages unchanged since 4-30-2026; kept until the district clerk answers.)
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

  # Each title's guidelines, in the block after its heading, state its pay ("Starting pay is $16.27 per hour", 2026-11-25).
  guidelines <- vapply(which(valid), function(i) {
    block <- rvest::html_element(nodes[[i]], xpath = "ancestor::div[contains(concat(' ', @class, ' '), ' category ')][1]/following-sibling::div[1]")
    if (inherits(block, "xml_missing")) NA_character_ else rvest::html_text2(block)
  }, character(1))
  cbind(data.frame(Title = titles, Location = "Kalispell", Posted_Date = NA_character_, Link = links, stringsAsFactors = FALSE),
        extract_posted_pay(guidelines))
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
  out <- data.frame(Title = titles, Location = "Kalispell", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE)
  # Substitutes' pay is a line of its own ("All substitutes are paid $15/hour.", 2026-11-25).
  lines <- strsplit(rvest::html_text2(page), "\n")[[1]]
  sub_pay <- grep("^\\s*All substitutes are paid", lines, value = TRUE)
  cbind(out, extract_posted_pay(ifelse(titles == "Substitute Teacher" & length(sub_pay) > 0, sub_pay[1], NA_character_)))
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
# starts and stops, a section to skip) are the registry row's List_Start,
# List_Stop and List_Skip (k12_list_rules.csv until 2026-11-16).
# Platform "ApptegyBespoke" keeps its own scraper in APPTEGY_DISTRICT_SCRAPERS:
# Shelby (titles inside a sentence) and Geyser (a CyberSchool page rendered in
# this session). test-misc-district-scrapers.R checks the map matches the
# registry's ApptegyBespoke rows in both directions.
APPTEGY_DISTRICT_SCRAPERS <- list(
  "Shelby School District" = fetch_shelbymt_postings,
  "Geyser Public Schools" = fetch_geyser_postings
)

APPTEGY_FAMILY_MODES <- c(Apptegy = "text", ApptegyPageBuilder = "pagebuilder")

# One registry row's list rule (NA when the district has none).
k12_list_rule <- function(rules, district, col) {
  v <- if (is.null(rules) || !col %in% names(rules)) character(0) else rules[[col]][rules$District == district]
  if (length(v) == 0 || is.na(v[1]) || !nzchar(v[1])) NA_character_ else v[1]
}

# Every district's list rules: k12_district_registry.csv's District, List_Start, List_Stop, List_Skip.
read_k12_list_rules <- function(path = "k12_district_registry.csv") {
  r <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = "", colClasses = "character")
  r[, c("District", "List_Start", "List_Stop", "List_Skip")]
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
      k12_list_rule(rules, row$District, "List_Skip"))
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
  pay_text <- character(0)
  in_coaching <- FALSE
  for (l in lines) {
    if (grepl("hiring .* for the After School Program", l, ignore.case = TRUE)) {
      titles <- c(titles, "After School Program Teachers/Subs")
      pay_text <- c(pay_text, l)
    } else if (grepl("Coaching Positions:", l, ignore.case = TRUE)) {
      in_coaching <- TRUE
    } else if (grepl("Qualifications:|Stipend:|Closing Date:|To apply:", l, ignore.case = TRUE)) {
      in_coaching <- FALSE
    } else if (in_coaching && nzchar(l) && nchar(l) < 60) {
      titles <- c(titles, l)
      pay_text <- c(pay_text, NA_character_)
    }
  }
  if (length(titles) == 0) return(empty)
  # The after-school line states its pay ("Pay starts at $18 per hour"); a coach's is "District Pay Scale".
  cbind(data.frame(Title = titles, Location = "Boulder", Posted_Date = NA_character_, Link = url, stringsAsFactors = FALSE),
        extract_posted_pay(pay_text))
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

    # A panel is one posting when it has a real heading (2026-11-21: "Bus Driver", whose body also says "Immediate
    # Bus Driver Position" and "Requirements: Bus Driver Training ...", was read as three postings). A panel headed
    # "Untitled" can hold several in its body (10-21: Custodian / Boiler Operator and School Cook): read by line.
    heading <- trimws(rvest::html_text2(rvest::html_element(p, ".panel-heading")))
    if (!is.na(heading) && nzchar(heading) && !grepl("^untitled$", heading, ignore.case = TRUE)) {
      rows[[length(rows) + 1]] <- data.frame(Title = heading, Location = "Judith Gap", Posted_Date = posted_date,
                                             Link = url, stringsAsFactors = FALSE)
      next
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
      if (length(titles) > 0 && any(vapply(titles, function(t) grepl(t, clean_title, fixed = TRUE) || grepl(clean_title, t, fixed = TRUE), logical(1)))) {
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
  # An error, not 0 rows, when the page isn't the Weebly employment page it was (2026-11-22): Pleasant Valley has
  # never had a posting here, so "0 rows" couldn't tell an empty board from a page the parser no longer reads.
  # (html_element() returns xml_missing, not NULL, when nothing matches: the old is.null() test never fired.)
  if (!nzchar(html)) stop("Pleasant Valley page is empty")
  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) stop("Pleasant Valley page didn't parse as HTML")

  content <- html_element(doc, "#wsite-content")
  if (inherits(content, "xml_missing")) stop("Pleasant Valley page has no #wsite-content: not the employment page, or the site changed")

  h2s <- html_elements(content, "h2.wsite-content-title, .wsite-content-title")
  # Even an empty board has its "Employment Opportunities" heading.
  if (length(h2s) == 0) stop("Pleasant Valley page has no .wsite-content-title heading: the site changed")

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
  # An error, not 0 rows, when the page isn't the Weebly employment page it was (2026-11-22): Circle has never had
  # a posting here, so "0 rows" couldn't tell an empty board from a page the parser no longer reads.
  # (html_element() returns xml_missing, not NULL, when nothing matches: the old is.null() test never fired.)
  if (!nzchar(html)) stop("Circle page is empty")
  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) stop("Circle page didn't parse as HTML")

  content <- html_element(doc, "#wsite-content")
  if (inherits(content, "xml_missing")) stop("Circle page has no #wsite-content: not the employment page, or the site changed")

  h2s <- html_elements(content, "h2.wsite-content-title, .wsite-content-title, .paragraph")
  # Even an empty board has its application-links paragraph.
  if (length(h2s) == 0) stop("Circle page has no .wsite-content-title or .paragraph block: the site changed")

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
# A registry district with no board of its own (Platform "OPIOnly", opi_reconcile.R) gets the label the
# OPI-only map rows carry (app.R's OPI_ONLY_COVERAGE): its postings come from OPI, not a scrape.
k12_district_coverage_tiers <- function(registry_csv = "k12_district_registry.csv") {
  registry <- read.csv(registry_csv, stringsAsFactors = FALSE)
  partial <- registry[!(registry$Platform %in% MT_DIRECT_API_PLATFORMS), ]
  data.frame(District = partial$District,
             Data_Coverage = ifelse(partial$Platform %in% "OPIOnly", "Postings via OPI's statewide board", "Partial"),
             stringsAsFactors = FALSE)
}
