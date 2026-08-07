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

# ---------------------------------------------------------------------------
# AppliTrack (Frontline Education) -- Billings, Missoula (MCPS), Great
# Falls, Bozeman, Helena, Butte, Belgrade, East Helena, Lockwood, Hamilton,
# Havre, and likely more as the district registry grows
# ---------------------------------------------------------------------------

# tenant_path is everything between applitrack.com/ and /onlineapp/ in the
# district's own URL, e.g. "billings" for
# https://www.applitrack.com/billings/onlineapp/default.aspx. The listing
# markup itself (ul.postingsList, table.title td#wrapword, li span.label/
# span.normal) comes from fetching Output.asp directly (the endpoint
# default.aspx's own inline script injects via document.write()) rather
# than rendering default.aspx in a browser and waiting for that injection
# to happen.
fetch_applitrack_postings <- function(tenant_path) {
  resp <- request(paste0("https://www.applitrack.com/", tenant_path, "/onlineapp/jobpostings/Output.asp")) %>%
    req_url_query(all = "1") %>%
    req_perform()
  # Applitrack serves Windows-1252 bytes with no charset in Content-Type, so
  # httr2 guesses UTF-8. Any posting containing a curly quote/en-dash/etc.
  # then fails to decode -- resp_body_string() returns NA rather than
  # erroring, and parse_applitrack_output(NA) silently yields zero rows.
  # That looks identical to a district with genuinely no openings -- this
  # was a confirmed real bug in the Wyoming port (10 of 25 WY districts hit
  # it, one hiding 69 real postings), so it's handled explicitly here from
  # the start rather than waiting to rediscover it in Montana's own data.
  parse_applitrack_output(resp_body_string(resp, encoding = "Windows-1252"))
}

parse_applitrack_output <- function(js_text) {
  # Response body is a series of document.write('<html fragment>') calls
  # with single quotes escaped as \' for JS string-literal safety; joining
  # every literal's un-escaped content reconstructs the full HTML the
  # browser would otherwise inject into the page.
  writes <- regmatches(js_text, gregexpr("document\\.write\\('(.*?)'\\);", js_text))[[1]]
  literals <- sub("^document\\.write\\('(.*)'\\);$", "\\1", writes)
  html <- paste(gsub("\\\\'", "'", literals), collapse = "")

  if (!nzchar(html)) {
    return(data.frame(title = character(0), position = character(0), position2 = character(0),
                       date_posted = character(0), location = character(0), closing_date = character(0),
                       stringsAsFactors = FALSE))
  }

  soup <- rvest::read_html(html)
  postings <- rvest::html_elements(soup, "ul.postingsList")

  if (length(postings) == 0) {
    return(data.frame(title = character(0), position = character(0), position2 = character(0),
                       date_posted = character(0), location = character(0), closing_date = character(0),
                       stringsAsFactors = FALSE))
  }

  rows <- lapply(postings, function(p) {
    title <- rvest::html_text2(rvest::html_element(p, "table.title td#wrapword"))
    labels <- rvest::html_text2(rvest::html_elements(p, "li span.label"))
    values <- rvest::html_text2(rvest::html_elements(p, "li span.normal"))

    # "Position Type:" can consume TWO consecutive values (category +
    # subcategory, e.g. "Support Staff/" and "Para-Educator Special
    # Services") when the next value isn't itself another label's value
    # (heuristic: doesn't contain ":"). Getting this wrong shifts every
    # subsequent field by one position, corrupting date_posted/location/
    # closing_date even though position2 itself is discarded downstream
    # (combinedclean only keeps title/date_posted/position/location/url/
    # District).
    field <- setNames(as.list(rep(NA_character_, 5)), c("position", "position2", "date_posted", "location", "closing_date"))
    j <- 1
    for (label in labels) {
      if (label == "Position Type:") {
        field$position <- values[j]
        if (j + 1 <= length(values) && !grepl(":", values[j + 1])) {
          field$position2 <- values[j + 1]
          j <- j + 1
        }
      } else if (label == "Date Posted:") {
        field$date_posted <- values[j]
      } else if (label == "Location:") {
        field$location <- values[j]
      } else if (label == "Closing Date:") {
        field$closing_date <- values[j]
      }
      j <- j + 1
    }

    data.frame(title = title, position = field$position, position2 = field$position2,
               date_posted = field$date_posted, location = field$location,
               closing_date = field$closing_date, stringsAsFactors = FALSE)
  })

  do.call(rbind, rows)
}

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
fetch_peopleadmin_atom <- function(feed_url, location_fallback = NA_character_) {
  resp <- request(feed_url) %>% req_perform()
  parse_peopleadmin_atom(resp_body_string(resp), location_fallback)
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
      req_perform()

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
    req_perform()
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
      title <- .x %>% rvest::html_node("td:nth-child(1) a") %>% rvest::html_text(trim = TRUE)
      date_posted <- .x %>% rvest::html_node("td:nth-child(2)") %>% rvest::html_text(trim = TRUE)
      position <- .x %>% rvest::html_node("td:nth-child(3)") %>% rvest::html_text(trim = TRUE)
      location <- .x %>% rvest::html_node("td:nth-child(4)") %>% rvest::html_text(trim = TRUE)
      data.frame(title = title, date_posted = date_posted, position = position,
                 location = location, url = url, stringsAsFactors = FALSE)
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
  resp <- request(paste0(base_url, "/api/Positions")) %>% req_perform()
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
parse_tylerportico_positions <- function(json_text, institution_name, base_url) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

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
    stringsAsFactors = FALSE
  )
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
fetch_opi_statewide_postings <- function(
    url = "https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx",
    page_size = 50, max_pages = 60) {
  resp <- request(url) %>% req_perform()
  html <- resp_body_string(resp)

  all_pages <- list(parse_opi_job_page(html, url))
  page_num <- 2
  while (nrow(all_pages[[length(all_pages)]]) == page_size && page_num <= max_pages) {
    fields <- extract_aspnet_postback_fields(html)
    fields[["__EVENTTARGET"]] <- "ctl00$ContentPlaceHolder1$grdJobListing"
    fields[["__EVENTARGUMENT"]] <- paste0("Page$", page_num)

    resp <- do.call(req_body_form, c(list(request(url)), fields)) %>% req_perform()
    html <- resp_body_string(resp)
    all_pages[[length(all_pages) + 1]] <- parse_opi_job_page(html, url)
    page_num <- page_num + 1
  }

  dplyr::bind_rows(all_pages)
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
                       stringsAsFactors = FALSE)

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
      stringsAsFactors = FALSE
    )
  }))
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
  resp <- request(base_url) %>% req_perform()
  parse_jazzhr_postings(resp_body_string(resp), institution_name)
}

# Each posting shows a city (always "Butte, MT" here -- Montana Tech has one
# campus, so it carries no distinguishing signal) and a department (e.g.
# "Admissions", "Petroleum Engineering", "Highlands College") -- Location
# uses the department, the more useful field, the same choice already made
# for Montana's PeopleAdmin institutions above. Confirmed live 2026-08-06
# that Highlands College postings appear on Montana Tech's own board with
# department "Highlands College" rather than needing a separate registry
# entry/scrape target, unlike every other platform here which is one
# registry row per institution.
#
# No Posted_Date field exists anywhere on this listing page (confirmed real
# absence, not a parsing gap -- same as some AppliTrack districts' missing
# closing_date) -- left NA.
parse_jazzhr_postings <- function(html_text, institution_name) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)

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
      stringsAsFactors = FALSE
    )
  }))
}
