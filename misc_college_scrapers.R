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
    perform_with_retry()
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
    perform_with_retry()
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

# Stone Child College (stonechild.edu/page/employment-rfps) -- Apptegy,
# the same CMS platform as Wolf Point/Plentywood in
# misc_district_scrapers.R (needs a live chromote_session; see that
# file's "Apptegy (chromote-driven)" section for why a browser is
# required at all -- a plain httr2 request gets a Fastly JS challenge
# shell with no real content). Real postings sit in a plain bullet list
# between the page's own "Current Job Openings" heading and its
# "Download SCC Employment Application" link (a boilerplate form, not a
# posting) -- confirmed live 2026-08-07, 5 real postings. A separate
# "Open Bids/Requests for Proposals (RFP)" section further down the same
# page is genuinely different content (grant/contract RFPs, not jobs) --
# excluded by the same upper-bound scoping. No Posted_Date, single real
# campus (Box Elder).
fetch_stonechild_postings <- function(chromote_session, url = "https://www.stonechild.edu/page/employment-rfps") {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(5)
  text <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  parse_stonechild_postings(text, url)
}

parse_stonechild_postings <- function(rendered_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  lines <- strsplit(rendered_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  start_idx <- which(lines == "Current Job Openings")
  end_idx <- which(lines == "Download SCC Employment Application")
  if (length(start_idx) == 0 || length(end_idx) == 0 || end_idx[1] <= start_idx[1] + 1) return(empty)

  titles <- lines[(start_idx[1] + 1):(end_idx[1] - 1)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = "Box Elder", Posted_Date = NA_character_,
             Link = url, stringsAsFactors = FALSE)
}

# Aaniiih Nakoda College (ancollege.edu/careers) -- a Wix-hosted static
# page, real current postings in free-text blocks (confirmed live
# 2026-08-07, no client-side rendering gap: a plain httr2 GET already
# ships the real postings in the raw HTML, no chromote needed unlike
# Stone Child's Wix site). No stable per-posting section markup (no
# heading tags, no repeatable class -- Wix's own generated classes are
# per-component GUIDs, not a reusable selector) -- but each posting's
# real title is itself a hyperlink to that posting's PDF/DOCX description
# (e.g. "CIS Assistant" linking to the same file its own "Read the full
# job description here." link right after it points to), the same href
# on both anchors. Recovered by pairing every `<a>` whose trimmed text is
# "here"/"here." with the anchor immediately before it in document order
# -- the intro paragraph's 3 unrelated links (Campus Safety/Clery Act,
# Catalog, the blank job Application form) are never immediately followed
# by a "here" link, so they're naturally excluded, not filtered by name.
# No Posted_Date (free-text prose, no consistent date field), single real
# campus (Harlem/Fort Belknap Agency).
fetch_ancollege_postings <- function(url = "https://www.ancollege.edu/careers") {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_ancollege_postings(resp_body_string(resp))
}

parse_ancollege_postings <- function(html_text) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  links <- rvest::html_elements(page, "a[href*='_files/ugd']")
  if (length(links) < 2) return(empty)

  texts <- trimws(rvest::html_text2(links))
  hrefs <- rvest::html_attr(links, "href")
  is_here <- grepl("^here\\.?$", texts, ignore.case = TRUE)

  # A "here" link's title is whatever real (non-"here") anchor came right
  # before it -- guards against two "here" links in a row (shouldn't
  # happen, but would otherwise silently pair a "here" with another
  # "here" instead of a real title).
  title_idx <- which(is_here) - 1L
  valid <- title_idx >= 1 & !is_here[pmax(title_idx, 1)]
  title_idx <- title_idx[valid]
  here_idx <- which(is_here)[valid]

  if (length(title_idx) == 0) return(empty)

  data.frame(
    Title = texts[title_idx],
    Location = "Harlem",
    Posted_Date = NA_character_,
    Link = hrefs[here_idx],
    stringsAsFactors = FALSE
  )
}

# Chief Dull Knife College (cdkc.edu/faculty-staff/employment/) -- a
# WordPress site using the Gutenberg "File" block for each real posting:
# a `div.wp-block-file` with two real anchors, the title (no class,
# e.g. "Birney Trustee App 08 2026") and a "Download" button (real class
# "wp-block-file__button") pointing at the same PDF -- confirmed live
# 2026-08-07, a plain httr2 GET already ships the real content, no
# chromote needed.
#
# As of 2026-08-07 the page's one real File block is "Birney Trustee App"
# -- a school-board trustee-seat application, not an employment posting
# (a real, recurring non-job category on tribal college sites, not a
# one-off) -- so CDKC_NON_JOB_TITLE_PATTERN excludes it by keyword rather
# than by its exact dated filename, the same way MILES_CC_NON_TITLE_LABELS
# excludes section labels above: this scraper is expected to return zero
# real rows right now, and start surfacing real postings the moment CDKC
# publishes one, without code changes. No Posted_Date (the file title
# sometimes embeds a date, but it's not a structured field), single real
# campus (Lame Deer).
CDKC_NON_JOB_TITLE_PATTERN <- "trustee"

# 2026-11-22: the File blocks' link text is the file name ("HR Job Posting 9
# 2026", "Birney Vacancy Open Until Filled"), so each linked document is read:
# a Board of Trustees vacancy is dropped whatever the file is called, and the
# title comes from the document's "Position Title:" / "Job Posting:" line.
# The .docx link is the posting's stable identity (posting_spells.R), so a
# better title doesn't split the posting's spell. A document that can't be read
# keeps the file-name title.
CDKC_TRUSTEE_TEXT_PATTERN <- "(?i)board of trustee"
CDKC_UA <- "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

fetch_cdkc_postings <- function(url = "https://www.cdkc.edu/faculty-staff/employment/") {
  resp <- request(url) %>%
    req_user_agent(CDKC_UA) %>%
    perform_with_retry()
  rows <- parse_cdkc_postings(resp_body_string(resp))
  texts <- vapply(rows$Link, cdkc_document_text, character(1), USE.NAMES = FALSE)
  refine_cdkc_postings(rows, texts)
}

# The text of a linked .docx or .pdf; NA when it can't be fetched or read.
cdkc_document_text <- function(link) {
  if (is.na(link) || !grepl("\\.(docx|pdf)$", link, ignore.case = TRUE)) return(NA_character_)
  tryCatch({
    resp <- request(link) %>% req_user_agent(CDKC_UA) %>% perform_with_retry()
    tmp <- tempfile(fileext = if (grepl("\\.pdf$", link, ignore.case = TRUE)) ".pdf" else ".docx")
    on.exit(unlink(tmp), add = TRUE)
    writeBin(resp_body_raw(resp), tmp)
    if (grepl("\\.pdf$", tmp)) return(paste(pdftools::pdf_text(tmp), collapse = "\n"))
    xml <- paste(readLines(unz(tmp, "word/document.xml"), warn = FALSE, encoding = "UTF-8"), collapse = "")
    cdkc_docx_xml_text(xml)
  }, error = function(e) NA_character_)
}

# word/document.xml -> text, one line per paragraph.
cdkc_docx_xml_text <- function(xml) {
  xml <- gsub("</w:p>", "\n", xml, fixed = TRUE)
  xml <- gsub("<w:tab/>|<w:br/>", " ", xml)
  txt <- gsub("<[^>]+>", "", xml)
  txt <- xml2::xml_text(xml2::read_html(paste0("<p>", gsub("\n", "&#10;", txt, fixed = TRUE), "</p>")))
  trimws(txt)
}

# Drops Board of Trustees vacancies and takes each title from its document.
refine_cdkc_postings <- function(rows, texts) {
  if (nrow(rows) == 0) return(rows)
  keep <- is.na(texts) | !grepl(CDKC_TRUSTEE_TEXT_PATTERN, texts, perl = TRUE)
  doc_title <- vapply(texts, function(t) {
    if (is.na(t)) return(NA_character_)
    lines <- trimws(strsplit(t, "\n", fixed = TRUE)[[1]])
    m <- regmatches(t, regexec("(?i)Position Title:\\s*(.+?)\\s*(?:Institution:|Reports To:|Department:|Status:|\n|$)", t, perl = TRUE))[[1]]
    if (length(m) == 2 && nzchar(m[2])) return(m[2])
    jp <- grep("^(?i)Job Posting:\\s*\\S", lines, value = TRUE, perl = TRUE)
    if (length(jp)) return(trimws(sub("^(?i)Job Posting:", "", jp[1], perl = TRUE)))
    NA_character_
  }, character(1), USE.NAMES = FALSE)
  rows$Title <- ifelse(is.na(doc_title), rows$Title, doc_title)
  rows <- rows[keep, , drop = FALSE]
  rownames(rows) <- NULL
  rows
}

parse_cdkc_postings <- function(html_text) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  blocks <- rvest::html_elements(page, "div.wp-block-file")
  if (length(blocks) == 0) return(empty)

  rows <- lapply(blocks, function(block) {
    title_el <- rvest::html_element(block, "a:not([class])")
    title <- rvest::html_text2(title_el)
    if (is.na(title) || !nzchar(title)) return(NULL)
    if (grepl(CDKC_NON_JOB_TITLE_PATTERN, title, ignore.case = TRUE)) return(NULL)

    data.frame(
      Title = title,
      Location = "Lame Deer",
      Posted_Date = NA_character_,
      Link = rvest::html_attr(title_el, "href"),
      stringsAsFactors = FALSE
    )
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]

  if (length(rows) == 0) return(empty)
  do.call(rbind, rows)
}
