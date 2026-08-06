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
