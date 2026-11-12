# Direct HTTP/API scrapers for K-12 district and Higher Ed job boards.
#
# Each source is split into a fetch_*() function (does the HTTP call, the
# only part that needs live network) and a parse_*() function (pure logic
# on already-fetched text/JSON, testable against a static fixture with no
# network at all).
#
# Ported from the Wyoming Education Jobs Dashboard's direct_api_scrapers.R.
# AppliTrack (K-12) and PeopleAdmin (Higher Ed) are the first two platforms
# ported, covering Montana's largest K-12 districts and its PeopleAdmin-based
# public universities respectively. Both fetch/parse pairs below are
# state-agnostic (parameterized by tenant path / feed URL) and carried over
# from Wyoming largely unchanged; other platforms (PowerSchool/SchoolSpring/
# TedK12, NEOGOV, and Montana-specific platforms like Tyler Portico, Paycom,
# JazzHR) get added here as each is built out.

suppressMessages({
  library(httr2)
  library(rvest)
  library(xml2)
  library(jsonlite)
  library(purrr)
  library(dplyr)
})
# The AppliTrack, SchoolSpring detail/ending, PeopleAdmin pay/date and NEOGOV card-pay
# functions moved to the edjobs package in phase 3 (2026-11-11); attached here so every
# script that sources this file still has them. Fix those in edjobs.
suppressMessages(library(edjobs))

# ---------------------------------------------------------------------------
# AppliTrack (Frontline Education) -- Billings, Missoula (MCPS), Great
# Falls, Bozeman, Helena, Butte, Belgrade, East Helena, Lockwood, Hamilton,
# Havre, and likely more as the district registry grows
# ---------------------------------------------------------------------------

# NOTE on MUS branch campuses with no independent UNITID (Gallatin College
# MSU under Montana State University, City College at MSU Billings under
# Montana State University Billings, per RESEARCH_NOTES.md): both already
# appear in their parent institution's PeopleAdmin feed under real
# "Gallatin College"/"City College" Location values, confirmed live
# 2026-08-07 -- neither needs its own registry row or scraper. Bitterroot
# College (merged into University of Montana's own reporting) had zero
# open postings at the same check, so its coverage-via-parent-board status
# is unconfirmed either way, unlike the other two.



# extract_posted_pay() is in edjobs, attached by k12_he_classification.R; standalone scripts
# (repro_scraper.R, live_check_autofix.R) source this file on its own.
if (!exists("extract_posted_pay", mode = "function")) source("k12_he_classification.R")


# ---------------------------------------------------------------------------
# PeopleAdmin -- Montana State University (Bozeman), MSU Billings, MSU
# Northern, Great Falls College MSU, and likely more as the HE institution
# registry grows
# ---------------------------------------------------------------------------

# feed_url is the institution's own published Atom feed, e.g.
# "https://jobs.montana.edu/postings/search.atom" -- every Montana PeopleAdmin
# instance checked so far publishes one at that same /postings/search.atom
# path.
#
# location_fallback is used only for entries that don't carry an <author>
# element. Montana's PeopleAdmin institutions are multi-department
# universities where each posting's real <author><name> (e.g. "Facility
# Services", "Center for Faculty Excellence") is a far more useful Location
# than one institution-wide string -- confirmed live on MSU Bozeman's feed,
# where every entry checked had a populated <author><name>. Wyoming's own
# PeopleAdmin scraper always passed a hardcoded location_fallback because
# its PeopleAdmin institutions (Eastern/Sheridan/Northwest) are single-campus
# community colleges where per-posting department granularity isn't in the
# feed; that fallback path is kept here for any Montana entry that turns out
# to lack an <author>, rather than assumed to never fire.
#
# The feed carries no pay, so with fetch_pay each posting's own page is read
# for it (parse_peopleadmin_posting_pay()): one request per posting, spaced
# out. A failed page leaves only that posting's pay and dates blank.
#
# The same page gives the posting's dates (parse_peopleadmin_posting_dates()).
# Its "Open Date" replaces the feed's <published>, which moves when a posting
# is re-published: 11 of 16 MSU Billings/Great Falls postings with an Open
# Date on 2026-11-04 opened earlier than <published> said, one by two years
# (a Great Falls pool open since 2024-06-26, <published> 2026-08-13). MSU
# Bozeman and Northern leave both date fields blank (198 postings), so they
# keep <published> and have no Close_Date; MSU states its dates only in prose
# ("Screening of applications will begin on October 30, 2026"), a review
# start rather than a close, not read here.
fetch_peopleadmin_atom <- function(feed_url, location_fallback = NA_character_, fetch_pay = TRUE, detail_delay = 0.3) {
  resp <- request(feed_url) %>% perform_with_retry()
  postings <- parse_peopleadmin_atom(resp_body_string(resp), location_fallback)
  if (!fetch_pay || nrow(postings) == 0) {
    postings <- ensure_posted_pay_columns(postings)
    postings$Close_Date <- rep(NA_character_, nrow(postings))
    return(postings)
  }
  pages <- lapply(postings$Link, function(link) {
    Sys.sleep(detail_delay)
    tryCatch(resp_body_string(request(link) %>% perform_with_retry()), error = function(e) NA_character_)
  })
  pay <- dplyr::bind_rows(lapply(pages, parse_peopleadmin_posting_pay))
  dates <- dplyr::bind_rows(lapply(pages, parse_peopleadmin_posting_dates))
  postings$Posted_Date <- dplyr::coalesce(dates$Open_Date, as.character(postings$Posted_Date))
  postings$Close_Date <- dates$Close_Date
  cbind(postings, pay)
}





parse_peopleadmin_atom <- function(xml_text, location_fallback = NA_character_) {
  doc <- xml2::read_xml(xml_text)
  ns <- c(a = "http://www.w3.org/2005/Atom")
  entries <- xml2::xml_find_all(doc, "//a:entry", ns)

  if (length(entries) == 0) {
    return(data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE))
  }

  titles <- xml2::xml_text(xml2::xml_find_first(entries, "a:title", ns))
  links <- xml2::xml_attr(xml2::xml_find_first(entries, "a:link", ns), "href")
  published <- xml2::xml_text(xml2::xml_find_first(entries, "a:published", ns))
  posted_date <- as.Date(substr(published, 1, 10))

  authors <- xml2::xml_text(xml2::xml_find_first(entries, "a:author/a:name", ns))
  # xml_find_first() returns "" (not NA) when a:author/a:name is absent for
  # a given entry -- normalize that to NA so ifelse() below falls through to
  # location_fallback instead of storing an empty string as a real Location.
  authors[!nzchar(authors)] <- NA_character_
  locations <- ifelse(is.na(authors), location_fallback, authors)

  data.frame(
    Title = titles,
    Location = locations,
    Posted_Date = as.character(posted_date),
    Link = links,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# SchoolSpring / PowerSchool Unified Talent -- Whitefish, Columbia Falls,
# Polson, Lewistown, Laurel, and likely more as the district registry grows
# ---------------------------------------------------------------------------

# domain_name is the district's own schoolspring.com subdomain, e.g.
# "laurel.schoolspring.com" -- the interactive UI at that domain sits
# behind bot protection, but api.schoolspring.com's own JSON endpoint
# (which the UI's own JS calls) is unprotected and takes domain_name as a
# plain query parameter. Paginated at page_size per page; keeps requesting
# subsequent pages until one comes back short or empty.
fetch_schoolspring_postings <- function(domain_name, page_size = 50) {
  all_pages <- list()
  page <- 1
  repeat {
    resp <- request("https://api.schoolspring.com/api/Jobs/GetPagedJobsWithSearch") %>%
      req_url_query(
        domainName = domain_name, keyword = "", location = "", category = "",
        gradelevel = "", jobtype = "", organization = "",
        page = page, size = page_size, sortDateAscending = "false"
      ) %>%
      perform_with_retry()

    page_df <- parse_schoolspring_json(resp_body_string(resp), domain_name)
    if (nrow(page_df) == 0) break

    all_pages[[length(all_pages) + 1]] <- page_df
    if (nrow(page_df) < page_size) break  # last page was partial -> no more pages
    page <- page + 1
  }

  if (length(all_pages) == 0) {
    return(data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE))
  }
  dplyr::bind_rows(all_pages)
}

parse_schoolspring_json <- function(json_text, domain_name) {
  parsed <- jsonlite::fromJSON(json_text, simplifyVector = TRUE)
  jobs <- parsed$value$jobsList

  if (is.null(jobs) || length(jobs) == 0 || nrow(jobs) == 0) {
    return(data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE))
  }

  # SchoolSpring occasionally exposes its own example vacancies as active
  # records. These are placeholder text, not jobs candidates can apply for.
  jobs <- jobs[!grepl("^Sample (Classified|Certified) Position$", jobs$title,
                      ignore.case = TRUE), , drop = FALSE]
  if (nrow(jobs) == 0) {
    return(data.frame(Title = character(0), Location = character(0),
                      Posted_Date = character(0), Link = character(0),
                      stringsAsFactors = FALSE))
  }

  data.frame(
    Title = jobs$title,
    Location = jobs$location,
    Posted_Date = substr(jobs$displayDate, 1, 10),
    Link = paste0("https://", domain_name, "/jobs/", jobs$jobId),
    stringsAsFactors = FALSE
  )
}













# ---------------------------------------------------------------------------
# TedK12 / PowerSchool Hire -- some districts dual-brand SchoolSpring and
# TedK12 on the same underlying PowerSchool Unified Talent platform; this
# is the fallback for districts only reachable via their tedk12.com/hire
# URL
# ---------------------------------------------------------------------------

# TedK12/PowerSchool Hire serves genuinely different content depending on
# the request's User-Agent, not on whether a browser executes JS -- a
# request with httr2's default UA gets a near-empty modern app shell
# (rebranded "SchoolSpring" -- same corporate family, different product)
# with zero job rows, while a request that identifies as a real browser
# gets the real, classic jQuery-based job board with real
# <tr id="JobList_N"> rows. Confirmed in the Wyoming port by comparing a
# plain curl fetch (empty shell) against a chromote-rendered page (real
# content) for the same URL, then confirming curl -A "<real browser UA>"
# alone reproduces the real content -- no browser automation needed in
# production, just a real User-Agent header. Applied here from the start
# rather than waiting to rediscover it against Montana's own TedK12
# districts.
fetch_tedk12_postings <- function(url) {
  resp <- request(url) %>%
    req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") %>%
    perform_with_retry()
  parse_tedk12_postings(resp_body_string(resp), url)
}

# td:nth-child(1..4) = title/date/position/location. The header row's title
# cell reads literally "Job Title" (its sortable-column link text) and is
# filtered out.
parse_tedk12_postings <- function(html_text, url) {
  empty <- data.frame(title = character(0), date_posted = character(0), position = character(0),
                       location = character(0), url = character(0), stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  rows <- rvest::html_nodes(page, "tr")
  if (length(rows) == 0) return(empty)

  # map_df() over zero matched <tr> elements returns a zero-COLUMN data
  # frame (not just zero rows), since it has no iteration to infer column
  # names from -- the `length(rows) == 0` guard above exists specifically
  # to avoid falling into that case and hitting "Unknown or uninitialised
  # column" warnings on the filter below.
  result <- rows %>%
    purrr::map_df(~{
      title_link <- .x %>% rvest::html_node("td:nth-child(1) a")
      title <- title_link %>% rvest::html_text(trim = TRUE)
      date_posted <- .x %>% rvest::html_node("td:nth-child(2)") %>% rvest::html_text(trim = TRUE)
      position <- .x %>% rvest::html_node("td:nth-child(3)") %>% rvest::html_text(trim = TRUE)
      location <- .x %>% rvest::html_node("td:nth-child(4)") %>% rvest::html_text(trim = TRUE)
      detail_url <- xml2::url_absolute(rvest::html_attr(title_link, "href"), url)
      data.frame(title = title, date_posted = date_posted, position = position,
                 location = location, url = detail_url, stringsAsFactors = FALSE)
    })

  result[!is.na(result$title) & nzchar(result$title) & result$title != "Job Title", , drop = FALSE]
}

# ---------------------------------------------------------------------------
# Tyler Portico -- Kalispell Public Schools (SD5), Montana's only top-tier
# district on this platform; a genuine one-off, not part of a reusable
# multi-district cluster like AppliTrack or SchoolSpring above.
# ---------------------------------------------------------------------------

# Tyler Portico has no public API documentation (confirmed via web search --
# unlike PeopleAdmin/AppliTrack/SchoolSpring, this is a newer Tyler Technologies
# product with nothing indexed). The endpoint below was found by downloading
# the tenant's own Angular bundle (main.*.js from
# https://kalispellpublicschoolsmt.tylerportico.com/tess/citizen/) and reading
# its compiled source for the job-board service's HTTP calls -- not
# trial-and-error path guessing. getOpenPositions() there calls
# `${BaseJobBoardHref}/Positions` with BaseJobBoardHref == "api", unauthenticated
# (no applicantId), which returns every open posting as one JSON array with no
# pagination. tenant_subdomain is the part before ".tylerportico.com", e.g.
# "kalispellpublicschoolsmt".
fetch_tylerportico_postings <- function(tenant_subdomain, institution_name) {
  base_url <- paste0("https://", tenant_subdomain, ".tylerportico.com/tess/citizen")
  resp <- request(paste0(base_url, "/api/Positions")) %>% perform_with_retry()
  parse_tylerportico_positions(resp_body_string(resp), institution_name, base_url)
}

# institution_name is used as a Location fallback for every row: Kalispell's
# live feed returns locationDescription: null on all 49 postings checked
# (confirmed live 2026-08-06) -- this is a single-district job board like
# Wyoming's PeopleAdmin colleges, not a multi-department one like Montana's
# own PeopleAdmin institutions, so there's no finer-grained per-posting
# location signal available here. The ifelse guard is kept anyway in case a
# future Tyler Portico tenant (if this scraper gets reused) does populate it.
#
# Link is reconstructed as base_url/jobs/job-list/{id} -- confirmed live by
# driving the real Angular app with chromote (headless Chrome), clicking a
# posting, and reading window.location.href, since this route isn't a plain
# <a href> in the markup (Tyler's Forge/Material components bind clicks in
# JS) and isn't derivable from the minified bundle by string search alone.
#
# Close_Date is postingEndDate only when it is a real end date: Tyler fills an
# open-ended posting's end with the day it is fetched plus one year (37 of 39
# Kalispell postings fetched 2026-11-03 "end" 2027-11-03; 44 of 49 fetched
# 2026-08-06 "end" 2027-08-06), so that value (+/- a day for time zones) is NA.
parse_tylerportico_positions <- function(json_text, institution_name, base_url, fetched = Sys.Date()) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0), Job_Code = character(0),
                       Close_Date = character(0), stringsAsFactors = FALSE)

  positions <- jsonlite::fromJSON(json_text, simplifyVector = TRUE)
  if (length(positions) == 0 || nrow(positions) == 0) return(empty)

  locations <- positions$locationDescription
  locations[is.na(locations)] <- ""
  locations <- ifelse(nzchar(locations), locations, institution_name)

  data.frame(
    Title = positions$title,
    Location = locations,
    Posted_Date = substr(positions$postingStartDate, 1, 10),
    Link = paste0(base_url, "/jobs/job-list/", positions$id),
    # The district's own job code ("JP491280 - 1271"); OPI descriptions of the
    # same job quote it ("JP054494"), an exact key for opi_matcher.R.
    Job_Code = if ("code" %in% names(positions)) as.character(positions$code) else NA_character_,
    Close_Date = tylerportico_close_date(positions$postingEndDate, fetched),
    stringsAsFactors = FALSE
  )
}

tylerportico_close_date <- function(end_date, fetched = Sys.Date()) {
  end <- as.Date(substr(as.character(end_date), 1, 10))
  placeholder <- seq(as.Date(fetched), by = "1 year", length.out = 2)[2]
  ifelse(is.na(end) | abs(as.numeric(end - placeholder)) <= 1, NA_character_, format(end))
}

# ---------------------------------------------------------------------------
# OPI "Jobs for Teachers" -- Montana's statewide fallback feed
# (apps.opi.mt.gov/mtjobsforteachers/), covering every district not scraped
# directly above, the Montana analog of Wyoming's WSBA vacancies page.
# ---------------------------------------------------------------------------

# This is a classic ASP.NET WebForms GridView with __VIEWSTATE-based postback
# paging (100 rows/page, ~11+ pages live) rather than a real API or a normal
# multi-page URL -- confirmed live (not guessed) that a bare
# __EVENTTARGET/__EVENTARGUMENT POST 302-redirects to an ErrorPage.aspx
# unless every other form field (every hidden __VIEWSTATE*/__EVENT* field
# plus the current value of every filter <select>: ddlVacancyArea,
# ddlGradeRange, ddlDistrict, ddlSchool) is resubmitted too -- ASP.NET
# WebForms requires the full form round-tripped on every postback, not just
# the fields that changed. extract_aspnet_postback_fields() below does that
# generically (all hidden inputs + each select's selected/first option) so
# it isn't tied to this page's specific field names, in case another
# ASP.NET WebForms site needs the same treatment later. Each page's fresh
# __VIEWSTATE/__EVENTVALIDATION must be used for the *next* page's request
# -- confirmed live that page 1's tokens can't be reused for page 3.
extract_aspnet_postback_fields <- function(html_text) {
  page <- rvest::read_html(html_text)
  form <- rvest::html_element(page, "form")
  fields <- list()

  inputs <- rvest::html_elements(form, "input")
  for (inp in inputs) {
    name <- rvest::html_attr(inp, "name")
    if (is.na(name)) next
    type <- rvest::html_attr(inp, "type")
    if (is.na(type)) type <- "text"
    if (type %in% c("submit", "button", "image")) next
    if (type %in% c("checkbox", "radio")) {
      if (!is.na(rvest::html_attr(inp, "checked"))) {
        value <- rvest::html_attr(inp, "value")
        fields[[name]] <- if (is.na(value)) "on" else value
      }
      next
    }
    value <- rvest::html_attr(inp, "value")
    fields[[name]] <- if (is.na(value)) "" else value
  }

  selects <- rvest::html_elements(form, "select")
  for (sel in selects) {
    name <- rvest::html_attr(sel, "name")
    if (is.na(name)) next
    options <- rvest::html_elements(sel, "option")
    selected <- Filter(function(o) !is.na(rvest::html_attr(o, "selected")), options)
    opt <- if (length(selected) > 0) selected[[1]] else options[[1]]
    value <- rvest::html_attr(opt, "value")
    fields[[name]] <- if (is.na(value)) rvest::html_text2(opt) else value
  }

  fields
}

# Pages until a page comes back with fewer than page_size rows (same
# stop-paging heuristic as fetch_schoolspring_postings() above), capped at
# max_pages as a safety bound against an infinite loop if the site's paging
# behavior ever changes. page_size is 50 -- confirmed live by counting
# distinct grdJobListing row control IDs on a page (each row's control ID
# appears twice in the raw HTML, once in its id= attribute and once inside
# its own __doPostBack() call, so a naive substring count of
# "btnJobDetailsPublic" reads 100 per page, double the real row count).
#
# fetch_details = TRUE also opens each posting's detail view to read the pay
# its description states (Pay_* columns; ~25% of postings state one,
# 2026-10-31) and the employer's district (OPI_District). There's no
# per-posting URL, so each detail is the row's own postback from the listing
# page it sits on, with a session cookie: ~0.75 s per posting, ~5 minutes for
# a full week. A failed detail leaves only that posting's pay and district
# NA, and detail fetching stops once detail_budget_secs is spent (the rest
# keep NA), so it can't push the weekly run past its timeout.
# apps.opi.mt.gov (since about 2026-11-03) serves a GoDaddy "R1" chain ending
# in the self-signed "GoDaddy TLS Root CA - R1", which standard trust stores
# don't include yet (Mozilla inclusion request bug 1996117), instead of the
# R1 cross-sign to the trusted G2 root -- so every request failed TLS
# verification and the weekly run would get no OPI postings. OPI requests
# verify against certs/opi_godaddy_r1.pem: GoDaddy's own R1 root, its R1->G2
# cross-sign and the DV R1v1 intermediate, from certs.godaddy.com/repository
# (SHA-256 fingerprints in that file). Verification stays on; only this host
# uses the bundle. Once OPI serves the cross-sign (or R1 is in the system
# store) the bundle still verifies, and it can be dropped.
opi_ca_bundle <- function() {
  for (p in c("certs/opi_godaddy_r1.pem", "../certs/opi_godaddy_r1.pem")) if (file.exists(p)) return(normalizePath(p))
  if (requireNamespace("here", quietly = TRUE) && file.exists(here::here("certs", "opi_godaddy_r1.pem"))) return(here::here("certs", "opi_godaddy_r1.pem"))
  NULL
}
opi_request <- function(url) {
  req <- request(url)
  ca <- opi_ca_bundle()
  if (!is.null(ca)) req <- req_options(req, cainfo = ca)
  req
}

fetch_opi_statewide_postings <- function(
    url = "https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx",
    page_size = 50, max_pages = 60, fetch_details = TRUE,
    detail_delay = 0.5, detail_budget_secs = 900) {
  jar <- tempfile()
  on.exit(unlink(jar), add = TRUE)
  deadline <- Sys.time() + detail_budget_secs
  read_page <- function(html) {
    rows <- parse_opi_job_page(html, url)
    if (!fetch_details || nrow(rows) == 0) return(rows)
    cbind(rows, fetch_opi_page_details(html, url, jar, deadline, detail_delay))
  }

  resp <- opi_request(url) %>% req_cookie_preserve(jar) %>% perform_with_retry()
  html <- resp_body_string(resp)

  all_pages <- list(read_page(html))
  page_num <- 2
  while (nrow(all_pages[[length(all_pages)]]) == page_size && page_num <= max_pages) {
    fields <- extract_aspnet_postback_fields(html)
    fields[["__EVENTTARGET"]] <- "ctl00$ContentPlaceHolder1$grdJobListing"
    fields[["__EVENTARGUMENT"]] <- paste0("Page$", page_num)

    resp <- do.call(req_body_form, c(list(opi_request(url) %>% req_cookie_preserve(jar)), fields)) %>%
      perform_with_retry()
    html <- resp_body_string(resp)
    all_pages[[length(all_pages) + 1]] <- read_page(html)
    page_num <- page_num + 1
  }

  out <- dplyr::bind_rows(all_pages)
  if (!fetch_details) return(out)
  out <- ensure_posted_pay_columns(out)
  if (!"OPI_District" %in% names(out)) out$OPI_District <- rep(NA_character_, nrow(out))
  for (col in c("OPI_Website", "OPI_School", "OPI_Description")) {
    if (!col %in% names(out)) out[[col]] <- rep(NA_character_, nrow(out))
  }
  out
}

# The postback target of each posting row's details link, in the same row
# order parse_opi_job_page() returns.
opi_detail_targets <- function(html_text) {
  table <- rvest::html_element(rvest::read_html(html_text), "#ctl00_ContentPlaceHolder1_grdJobListing")
  if (is.na(table)) return(character(0))
  links <- rvest::html_elements(table, "a[id*='btnJobDetailsPublic']")
  sub("^javascript:__doPostBack\\('([^']+)'.*$", "\\1", rvest::html_attr(links, "href"))
}

# Pay_* and OPI_District for every posting on one listing page, one detail
# postback each.
fetch_opi_page_details <- function(html_text, url, jar, deadline, delay) {
  fields <- extract_aspnet_postback_fields(html_text)
  none <- function() cbind(extract_posted_pay(NA_character_), OPI_District = NA_character_,
                           OPI_Website = NA_character_, OPI_School = NA_character_, OPI_Description = NA_character_)
  dplyr::bind_rows(lapply(opi_detail_targets(html_text), function(target) {
    if (Sys.time() > deadline) return(none())
    Sys.sleep(delay)
    tryCatch({
      f <- fields
      f[["__EVENTTARGET"]] <- target
      f[["__EVENTARGUMENT"]] <- ""
      resp <- do.call(req_body_form, c(list(opi_request(url) %>% req_cookie_preserve(jar)), f)) %>%
        perform_with_retry()
      details <- parse_opi_job_details(resp_body_string(resp))
      # School and the description's opening let opi_matcher.R tell which
      # board posting (if any) is the same opening.
      cbind(extract_posted_pay(details$Description), OPI_District = details$District_Name,
            OPI_Website = details$Website, OPI_School = details$School,
            OPI_Description = substr(gsub("\\s+", " ", details$Description), 1, 600))
    }, error = function(e) none())
  }))
}

# One posting's detail view (frmJobDetailsPublic.aspx). The description sits
# in a read-only textarea as escaped HTML, so it's parsed twice: once out of
# the page, once to turn its markup into text. District_Name is the
# employer's real district ("Darby K-12 Schools"), which the listing grid
# lacks; it's kept as OPI_District, in OPI's own (and OPI finance's)
# district naming.
parse_opi_job_details <- function(html_text) {
  page <- rvest::read_html(html_text)
  text_of <- function(selector) {
    node <- rvest::html_element(page, selector)
    if (is.na(node)) NA_character_ else trimws(rvest::html_text2(node))
  }
  raw <- text_of("#txtJobDescription")
  description <- if (is.na(raw) || !nzchar(raw)) NA_character_ else
    rvest::html_text2(rvest::read_html(paste0("<div>", raw, "</div>")))
  # The employer's own website (lnkWebSite), shown as text; OPI's href
  # prepends a second scheme to values that already have one, so the text
  # is used.
  website <- text_of("#ctl00_ContentPlaceHolder1_lnkWebSite")
  if (!is.na(website) && !nzchar(website)) website <- NA_character_
  data.frame(District_Name = text_of("#ctl00_ContentPlaceHolder1_lblDistrict"),
             School = text_of("#ctl00_ContentPlaceHolder1_lblSchool"),
             Description = description, Website = website, stringsAsFactors = FALSE)
}

# The grid has no District column (only City) despite a District filter
# dropdown existing elsewhere on the page -- Location is the posting's City
# as the feed itself reports it, not a canonicalized legal district name.
# Link is the same statewide listing URL for every row: confirmed live with
# chromote that clicking a posting navigates to frmJobDetailsPublic.aspx
# with no query string or job ID in the URL at all (the detail view is
# session/ViewState-driven, like the rest of this ASP.NET WebForms page) --
# there is no stable per-posting URL to construct here, unlike Tyler
# Portico's SPA above.
parse_opi_job_page <- function(html_text, url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       Close_Date = character(0), stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  table <- rvest::html_element(page, "#ctl00_ContentPlaceHolder1_grdJobListing")
  if (is.na(table)) return(empty)

  rows <- rvest::html_elements(table, "tr")
  job_rows <- Filter(function(r) length(rvest::html_elements(r, "a[id*='btnJobDetailsPublic']")) > 0, rows)
  if (length(job_rows) == 0) return(empty)

  do.call(rbind, lapply(job_rows, function(r) {
    tds <- rvest::html_elements(r, "td")
    data.frame(
      Title = rvest::html_text2(tds[[1]]),
      Location = rvest::html_text2(tds[[2]]),
      Posted_Date = rvest::html_text2(tds[[4]]),
      Link = url,
      Close_Date = if (length(tds) >= 5) opi_close_date(rvest::html_text2(tds[[5]])) else NA_character_,
      stringsAsFactors = FALSE
    )
  }))
}

# The grid's "Closing Date" column: almost always "Open Until Filled" (362
# of 366 postings, 2026-11-04), else a date ("11/13/2026"). A date becomes
# YYYY-MM-DD; any other wording is kept as written; blank is NA.
opi_close_date <- function(x) {
  x <- trimws(x)
  d <- suppressWarnings(as.Date(x, format = "%m/%d/%Y"))
  ifelse(!is.na(d) & grepl("^\\d{1,2}/\\d{1,2}/\\d{4}$", x), format(d),
         ifelse(is.na(x) | !nzchar(x), NA_character_, x))
}

# ---------------------------------------------------------------------------
# JazzHR -- Montana Tech (and Highlands College, which shares Montana Tech's
# board rather than having its own -- see parse_jazzhr_postings() below)
# ---------------------------------------------------------------------------

# JazzHR's default hosted careers page lives at
# https://<subdomain>.applytojob.com/apply -- Montana Tech's is
# "montanatechuniversity" (confirmed via web search, not guessed). The
# listing is plain server-rendered HTML (unlike Tyler Portico's SPA above),
# so no API reverse-engineering was needed here.
fetch_jazzhr_postings <- function(subdomain, institution_name) {
  base_url <- paste0("https://", subdomain, ".applytojob.com/apply")
  resp <- request(base_url) %>% perform_with_retry()
  parse_jazzhr_postings(resp_body_string(resp), institution_name)
}

# Highlands College's real department label on Montana Tech's own JazzHR
# board -- exact match, not a substring/regex (confirmed live 2026-08-06,
# re-confirmed 2026-08-07 when this became a real Institution split
# instead of just a Location value; see this file's header for how the
# other 3 "rides a parent's board" institutions -- Helena College, UM
# Western, Missoula College -- get the same treatment on the NEOGOV
# side).
JAZZHR_HIGHLANDS_COLLEGE_DEPARTMENT <- "Highlands College"

# Each posting shows a city (always "Butte, MT" here -- Montana Tech has one
# campus, so it carries no distinguishing signal) and a department (e.g.
# "Admissions", "Petroleum Engineering", "Highlands College") -- Location
# uses the department, the more useful field, the same choice already made
# for Montana's PeopleAdmin institutions above. Institution is derived
# per-posting from that same department field (2026-08-07): every posting
# whose department is exactly "Highlands College" is attributed to
# Highlands College's own registry row rather than lumped into Montana
# Tech's count -- previously Location carried this distinction but every
# posting was still counted/mapped under whatever institution_name the
# caller passed in.
#
# No Posted_Date field exists anywhere on this listing page (confirmed real
# absence, not a parsing gap -- same as some AppliTrack districts' missing
# closing_date) -- left NA.
parse_jazzhr_postings <- function(html_text, institution_name) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       Institution = character(0), stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  items <- rvest::html_elements(page, ".jobs-list li.list-group-item")
  if (length(items) == 0) return(empty)

  do.call(rbind, lapply(items, function(item) {
    title <- rvest::html_text2(rvest::html_element(item, "h3 a"))
    link <- rvest::html_attr(rvest::html_element(item, "h3 a"), "href")
    detail_fields <- rvest::html_text2(rvest::html_elements(item, "ul.list-group-item-text > li"))
    department <- if (length(detail_fields) >= 2) detail_fields[2] else institution_name

    data.frame(
      Title = title,
      Location = department,
      Posted_Date = NA_character_,
      Link = link,
      Institution = ifelse(identical(department, JAZZHR_HIGHLANDS_COLLEGE_DEPARTMENT),
                            JAZZHR_HIGHLANDS_COLLEGE_DEPARTMENT, institution_name),
      stringsAsFactors = FALSE
    )
  }))
}

# ---------------------------------------------------------------------------
# Paycom -- Flathead Valley Community College
# ---------------------------------------------------------------------------

# Paycom has no public API (confirmed via web search) and its hosted career
# page (paycomonline.net/v4/ats/web.php/portal/<portal_key>/career-page) is a
# React SPA whose job data doesn't come from any request visible via normal
# browser network-tab/CDP capture in the usual case -- found instead by
# downloading the SPA's own compiled bundle
# (portal-applicant-tracking.us-cent.paycomonline.net/career-portal/main/*.js,
# itself only discoverable via a small sprawl.json build manifest referenced
# from the career page's initial HTML) and reading its real
# api/ats/job-posting-previews/search POST call and the exact
# filtersForQuery shape it sends (every field below is required -- omitting
# distanceFrom/sortOption, or a wrong header name, makes the same endpoint
# 200-and-return zero results instead of erroring, which looks identical to
# a genuinely empty board). The JWT it authenticates with is embedded
# directly in the initial career-page HTML (no separate login step) and is
# short-lived (~2 hour `exp` claim) -- fetched fresh on every call, never
# cached or persisted.
extract_paycom_jwt <- function(html_text) {
  m <- regmatches(html_text, regexpr("eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+", html_text))
  if (length(m) == 0) stop("No JWT found in Paycom career page HTML")
  m
}

fetch_paycom_postings <- function(portal_key, institution_name, page_size = 100, detail_delay = 0.3) {
  career_page_url <- paste0("https://www.paycomonline.net/v4/ats/web.php/portal/", portal_key, "/career-page")
  career_resp <- request(career_page_url) %>% perform_with_retry()
  token <- extract_paycom_jwt(resp_body_string(career_resp))

  search_url <- "https://portal-applicant-tracking.us-cent.paycomonline.net/api/ats/job-posting-previews/search"
  filters <- list(
    distanceFrom = 0, workEnvironments = list(), positionTypes = list(),
    educationLevels = list(), categories = list(), travelTypes = list(),
    shiftTypes = list(), otherFilters = list(), keywordSearchText = "",
    location = "", sortOption = "N"
  )

  all_pages <- list()
  skip <- 0
  repeat {
    resp <- request(search_url) %>%
      req_headers(Authorization = paste("Bearer", token), Locale = "en-US", `Translation-Highlights` = "false") %>%
      req_body_json(list(skip = skip, take = page_size, filtersForQuery = filters)) %>%
      perform_with_retry()
    page_df <- parse_paycom_postings(resp_body_string(resp), portal_key)
    if (nrow(page_df) == 0) break

    all_pages[[length(all_pages) + 1]] <- page_df
    if (nrow(page_df) < page_size) break
    skip <- skip + page_size
  }

  postings <- dplyr::bind_rows(all_pages)
  if (nrow(postings) == 0) return(ensure_posted_pay_columns(postings))

  # The search previews cut each description off at ~150 characters, so pay
  # comes from each posting's own detail record (api/ats/job-postings/{id},
  # the call the SPA makes when a posting is opened; same bearer token). One
  # request per posting, spaced out. A failed detail call leaves only that
  # posting's pay blank.
  detail_url <- "https://portal-applicant-tracking.us-cent.paycomonline.net/api/ats/job-postings/"
  job_ids <- sub("^.*/jobs/", "", postings$Link)
  pay <- dplyr::bind_rows(lapply(job_ids, function(id) {
    Sys.sleep(detail_delay)
    tryCatch({
      resp <- request(paste0(detail_url, id)) %>%
        req_headers(Authorization = paste("Bearer", token), Locale = "en-US", `Translation-Highlights` = "false") %>%
        perform_with_retry()
      parse_paycom_posting_pay(resp_body_string(resp))
    }, error = function(e) parse_paycom_posting_pay(NA_character_))
  }))
  cbind(postings, pay)
}

# Pay from a posting's detail record: salaryRange is the line the posting
# page prints ("$125,000.00 - $155,000.00 Salary", "$16.15 - $20.00 Hourly"),
# empty when the posting states no pay (every adjunct posting at FVCC,
# 2026-10-30). Kept verbatim as Pay_Text.
parse_paycom_posting_pay <- function(json_text) {
  salary_range <- NA_character_
  if (!is.na(json_text)) {
    salary_range <- jsonlite::fromJSON(json_text)$jobPosting$salaryRange
    if (is.null(salary_range) || !nzchar(trimws(salary_range))) salary_range <- NA_character_
  }
  pay <- extract_posted_pay(salary_range)
  pay$Pay_Text <- ifelse(is.na(pay$Pay_Min), NA_character_, trimws(salary_range))
  pay
}

# postedOn is genuinely empty ("") on every real posting checked (confirmed
# live 2026-08-06, all 29 of FVCC's current postings) -- not a parsing gap,
# same as JazzHR's completely absent Posted_Date field above. Link uses each
# posting's real jobId in a route confirmed live with chromote (clicking a
# posting navigates the browser to exactly this URL, and it resolves
# standalone on a fresh unauthenticated request too, unlike the OPI
# statewide feed's session-only detail view).
parse_paycom_postings <- function(json_text, portal_key) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  parsed <- jsonlite::fromJSON(json_text, simplifyVector = TRUE)
  jobs <- parsed$jobPostingPreviews
  if (is.null(jobs) || length(jobs) == 0 || nrow(jobs) == 0) return(empty)

  posted <- jobs$postedOn
  posted[!nzchar(posted)] <- NA_character_

  data.frame(
    Title = jobs$jobTitle,
    Location = jobs$locations,
    Posted_Date = posted,
    Link = paste0("https://www.paycomonline.net/v4/ats/web.php/portal/", portal_key, "/jobs/", jobs$jobId),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# isolved Hire (applican) -- Blackfeet Community College
# ---------------------------------------------------------------------------

# The public jobs page (e.g. https://bfcc.isolvedhire.com/jobs/) renders via
# a Vue web-components bundle with no job data in the raw HTML or in any
# request to the refer-io.appspot.com widget it also loads (that widget is
# an unrelated employee-referral feature, a dead end confirmed by live
# chromote network capture). The real source is the site's own backend at
# {subdomain}.isolvedhire.com/core/jobs/{domain_id} -- domain_id is a
# per-institution site ID (10334 for Blackfeet CC) only discoverable by
# capturing the live page's network requests once per institution. Requires
# a non-null getParams query param (the endpoint 500s without one) but an
# empty JSON object is accepted and returns the full unfiltered list, same
# 7 postings confirmed live 2026-08-06 matching what chromote rendered.
fetch_isolvedhire_postings <- function(subdomain, domain_id, institution_name) {
  api_url <- paste0("https://", subdomain, ".isolvedhire.com/core/jobs/", domain_id,
                     "?getParams=%7B%7D")
  resp <- request(api_url) %>% perform_with_retry()
  parse_isolvedhire_postings(resp_body_string(resp), institution_name)
}

# startDateRef is the posting's real open/start date (not the closing date,
# which is endDateRef) -- confirmed against the live BFCC postings, where
# startDateRef consistently precedes endDateRef by weeks to years (the
# latter driven by untilFilled postings carrying a multi-year placeholder
# close date).
#
# Pay comes from the posting's own structured fields: minSalary/maxSalary
# (strings, sometimes with commas: "45,888") and payTypeFrame ("per hour",
# "per year"), the same words the board prints. They're joined into the
# board's own wording and read with extract_posted_pay(), so a posting with
# no stated pay stays NA.
parse_isolvedhire_postings <- function(json_text, institution_name) {
  empty <- ensure_posted_pay_columns(
    data.frame(Title = character(0), Location = character(0),
               Posted_Date = character(0), Link = character(0),
               stringsAsFactors = FALSE))

  parsed <- jsonlite::fromJSON(json_text, simplifyVector = TRUE)
  jobs <- parsed$data$jobs
  if (is.null(jobs) || length(jobs) == 0 || nrow(jobs) == 0) return(empty)

  field <- function(x) if (is.null(x)) rep(NA_character_, nrow(jobs)) else as.character(x)
  lo <- field(jobs$minSalary); hi <- field(jobs$maxSalary)
  pay_text <- ifelse(is.na(lo) | !nzchar(lo), NA_character_,
                     paste0("$", lo, ifelse(is.na(hi) | !nzchar(hi), "", paste0(" - $", hi)),
                            " ", field(jobs$payTypeFrame)))
  pay <- extract_posted_pay(pay_text)
  pay$Pay_Text <- ifelse(is.na(pay$Pay_Min), NA_character_, trimws(sub(" NA$", "", pay_text)))

  cbind(data.frame(
    Title = trimws(jobs$title),
    Location = jobs$city,
    Posted_Date = as.character(as.Date(jobs$startDateRef, format = "%b %d, %Y")),
    Link = jobs$jobUrl,
    stringsAsFactors = FALSE
  ), pay)
}

# ---------------------------------------------------------------------------
# NEOGOV Attract -- University of Montana (whose board also covers three
# branch/affiliate campuses under the same feed, confirmed live by their
# real street addresses in the Location field: Missoula College and Helena
# College postings, plus University of Montana Western's -- e.g. "Vice
# Chancellor of Administration and Finance" at 710 S Atlantic St, Dillon,
# MT, UM Western's real campus address.)
# ---------------------------------------------------------------------------

# Real street addresses seen live in this feed's Location field, mapped to
# each posting's real institution (2026-08-07) -- "32 Campus Dr" (UM's own
# main-campus address) and "1205 E Broadway St" (Missoula College's own
# address) are BOTH in Missoula, so city alone can't disambiguate; street
# match is required for those two. Helena and Dillon are each
# unambiguous by city alone within this feed -- confirmed live two
# distinct Helena street addresses (1115 N Roberts St, the main building,
# and 2300 Airport Rd, a real trades-program annex -- e.g. "Diesel
# Mechanics Instructor" posts there) both belong to Helena College, no
# other UM-network entity is Helena-based. Anything that matches none of
# these (e.g. a real remote/out-of-state posting confirmed live at
# "St. Clair County, IL, USA" for a research-center field position) falls
# back to institution_name -- the umbrella board owner, University of
# Montana, is the honest default for a posting with no real MT branch-
# campus address.
neogov_location_to_institution <- function(location, default_institution) {
  if (grepl("1205 E Broadway St", location, fixed = TRUE)) return("Missoula College")
  if (grepl("Helena, MT", location, fixed = TRUE)) return("Helena College")
  if (grepl("Dillon, MT", location, fixed = TRUE)) return("University of Montana Western")
  default_institution
}

# The public careers page (e.g.
# https://ummissoula.attract.neoed.com/p/careers) is server-rendered but
# ships zero real job data in the initial HTML -- window.initialData's
# "jobs" array is just a single widget-config placeholder object, not
# actual postings. The real data comes from a same-origin JobList endpoint
# the page's own JS calls client-side, requiring the
# "X-Requested-With: XMLHttpRequest" header (a plain curl/httr2 request
# without it 404s even with the right query string and session cookies --
# confirmed by comparing a raw request against one replayed from inside a
# real page load via chromote's Runtime.evaluate). Returns an HTML
# fragment (job-card anchors), not JSON. Each posting's real detail-page
# link embeds ephemeral visitor/session query params that 500 if reused
# from a different session -- confirmed live the same link resolves fine
# with that query string stripped, so Link stores the bare URL. No posted-
# date field exists anywhere in the fragment -- a real absence, same
# pattern as JazzHR/Paycom's missing date.
fetch_neogov_postings <- function(subdomain, institution_name, page_size = 50) {
  all_pages <- list()
  page <- 1
  repeat {
    resp <- request(paste0("https://", subdomain, ".attract.neoed.com/JobList")) %>%
      req_url_query(
        layoutId = "Jobs-1",
        websiteUrl = paste0("https://", subdomain, ".attract.neogov.com"),
        themeId = "2", language = "en", subdomain = subdomain,
        page = page, pageSize = page_size, contains = ""
      ) %>%
      req_headers(`X-Requested-With` = "XMLHttpRequest") %>%
      perform_with_retry()

    page_df <- parse_neogov_postings(resp_body_string(resp), institution_name)
    if (nrow(page_df) == 0) break

    all_pages[[length(all_pages) + 1]] <- page_df
    if (nrow(page_df) < page_size) break
    page <- page + 1
  }

  if (length(all_pages) == 0) {
    return(ensure_posted_pay_columns(
      data.frame(Title = character(0), Location = character(0),
                 Posted_Date = character(0), Link = character(0),
                 Institution = character(0),
                 stringsAsFactors = FALSE)))
  }
  postings <- dplyr::bind_rows(all_pages)

  # The Attract job cards carry no pay, but every Link points at the same
  # posting on NEOGOV's schooljobs.com board
  # (schooljobs.com/careers/<subdomain>/jobs/<id>/...), whose listing prints
  # the pay on each card ("Hourly Staff Full-time - $22.53 Hourly"). Pay is
  # joined in by job ID; postings missing from that listing (47 of UM's 58
  # were on it, 2026-10-30) keep NA. If the listing can't be fetched, every
  # posting keeps NA pay and the postings themselves are unaffected.
  pay <- tryCatch(fetch_schooljobs_card_pay(subdomain), error = function(e) {
    message("schooljobs pay listing failed for ", subdomain, ": ", conditionMessage(e))
    NULL
  })
  job_id <- sub("^.*/jobs/([0-9]+).*$", "\\1", postings$Link)
  idx <- if (is.null(pay)) rep(NA_integer_, nrow(postings)) else match(job_id, pay$Job_ID)
  for (col in POSTED_PAY_COLUMNS) {
    postings[[col]] <- if (is.null(pay)) (if (col %in% c("Pay_Min", "Pay_Max")) NA_real_ else NA_character_) else pay[[col]][idx]
  }
  postings
}

# The schooljobs.com listing for one agency, as Job_ID + Pay_*. Same AJAX
# endpoint, X-Requested-With gate and 10-per-page paging that Wyoming's
# NEOGOV scraper uses for its colleges.
fetch_schooljobs_card_pay <- function(agency, base_domain = "https://www.schooljobs.com") {
  all_pages <- list()
  page <- 1
  repeat {
    resp <- request(paste0(base_domain, "/careers/home/index")) %>%
      req_url_query(agency = agency, sort = "PositionTitle", isDescendingSort = "false", page = page) %>%
      req_headers(`X-Requested-With` = "XMLHttpRequest") %>%
      perform_with_retry()
    page_pay <- parse_neogov_card_pay(resp_body_string(resp))
    if (nrow(page_pay) == 0) break
    all_pages[[length(all_pages) + 1]] <- page_pay
    page <- page + 1
  }
  dplyr::bind_rows(all_pages)
}


parse_neogov_postings <- function(html_text, institution_name) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       Institution = character(0), stringsAsFactors = FALSE)

  page <- rvest::read_html(html_text)
  boxes <- rvest::html_elements(page, "a.jobs__box")
  if (length(boxes) == 0) return(empty)

  titles <- rvest::html_text2(rvest::html_elements(boxes, ".jobs__box__heading"))
  locations <- rvest::html_text2(rvest::html_elements(boxes, ".jobs__box__text"))
  links <- sub("\\?.*$", "", rvest::html_attr(boxes, "href"))

  data.frame(
    Title = titles,
    Location = locations,
    Posted_Date = NA_character_,
    Link = links,
    Institution = vapply(locations, neogov_location_to_institution, character(1),
                          default_institution = institution_name, USE.NAMES = FALSE),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# ADP Workforce Now (careercenter) -- University of Providence
# ---------------------------------------------------------------------------

# The public recruitment page (e.g.
# https://workforcenow.adp.com/mascsr/default/mdf/recruitment/recruitment.html?cid={cid}&ccId={cc_id}&type=JS&lang=en_US)
# is a client-rendered app shell -- ADP's frontend bundle varies between
# page loads (observed both a "synerg-web-components" build and an
# "mdf-wc" build fetching the same recruitment.html, an A/B-tested rollout
# apparently keyed off something other than the URL) but both call the
# same real, unauthenticated JSON API underneath:
# mascsr/default/careercenter/public/events/staffing/v1/job-requisitions.
# Requires cid (the employer's ADP client ID) and ccId (career-center ID,
# "19000101_000001" for every real career-center site checked so far, but
# treated as a real per-institution parameter rather than hardcoded, in
# case a future institution's differs). Each posting's real detail-page
# URL isn't returned in the JSON directly -- confirmed live with chromote
# that clicking a posting appends "&jobId={ExternalJobID}" to the
# recruitment.html URL itself (client-side routing, not a separate page),
# where ExternalJobID is a stringField buried in each job's
# customFieldGroup, not a top-level field.
fetch_adp_workforcenow_postings <- function(cid, cc_id, institution_name, top = 100) {
  resp <- request("https://workforcenow.adp.com/mascsr/default/careercenter/public/events/staffing/v1/job-requisitions") %>%
    req_url_query(cid = cid, ccId = cc_id, lang = "en_US", locale = "en_US", `$top` = top) %>%
    perform_with_retry()
  parse_adp_workforcenow_postings(resp_body_string(resp), cid, cc_id)
}

adp_extract_external_job_id <- function(job) {
  string_fields <- job$customFieldGroup$stringFields
  for (field in string_fields) {
    if (identical(field$nameCode$codeValue, "ExternalJobID")) return(field$stringValue)
  }
  NA_character_
}

parse_adp_workforcenow_postings <- function(json_text, cid, cc_id) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

  parsed <- jsonlite::fromJSON(json_text, simplifyVector = FALSE)
  jobs <- parsed$jobRequisitions
  if (is.null(jobs) || length(jobs) == 0) return(empty)

  base_url <- paste0("https://workforcenow.adp.com/mascsr/default/mdf/recruitment/recruitment.html?cid=",
                      cid, "&ccId=", cc_id, "&type=JS&lang=en_US")

  rows <- lapply(jobs, function(job) {
    city <- tryCatch(job$requisitionLocations[[1]]$address$cityName, error = function(e) NA_character_)
    if (is.null(city)) city <- NA_character_
    ext_id <- adp_extract_external_job_id(job)

    data.frame(
      Title = job$requisitionTitle,
      Location = city,
      Posted_Date = substr(job$postDate, 1, 10),
      Link = paste0(base_url, "&jobId=", ext_id),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}
