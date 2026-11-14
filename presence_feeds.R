# Montana's statewide feed for the daily presence check (edjobs::refresh_presence(), called by
# .github/workflows/presence.yml; notes: claude-notes/2026-11-13_presence-redrover-opi-wsba.md).
#
# OPI has no posting ID anywhere, so each posting is keyed by edjobs::opi_posting_key(): its detail
# page's district and school, the list's title, the posted date and the description excerpt the weekly
# archive stores (OPI_Description), so a weekly row gives the same key. A detail page is one postback,
# so a day reads only the ones it needs: a list row (title + town + posted date) whose list key held as
# many postings at the last check as it does today reuses those postings' keys; every other row's page
# is read. Expect a few dozen detail pages a day, and all of them (~360) on the first day.
# Not part of the weekly pipeline: the weekly OPI scrape (fetch_opi_statewide_postings()) is unchanged.
# Needs direct_api_scrapers.R sourced first (opi_request(), parse_opi_job_page(), opi_detail_targets(),
# parse_opi_job_details(), extract_aspnet_postback_fields()).

OPI_PRESENCE_BOARD <- "OPI Jobs for Teachers (statewide)"
OPI_LISTING_URL <- "https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx"

# What a list row shows of a posting.
opi_list_key <- function(title, location, posted) {
  paste(edjobs::presence_norm(title), edjobs::presence_norm(location), edjobs::presence_iso_date(posted), sep = " | ")
}

# Keys a list key can reuse: its postings' stretches still open on the board's last day seen.
opi_reusable_keys <- function(known) {
  if (is.null(known) || nrow(known) == 0) return(list())
  open <- known[known$Last_Day == max(known$Last_Day) & !is.na(known$List_Key) & !is.na(known$Link_Key), , drop = FALSE]
  if (nrow(open) == 0) return(list())
  lapply(split(open, open$List_Key), function(x) x[order(x$Link_Key), c("Link_Key", "District"), drop = FALSE])
}

# Every list page, in order, each with its HTML (for that page's detail postbacks).
opi_list_pages <- function(url, jar, page_size, max_pages) {
  html <- resp_body_string(opi_request(url) %>% req_cookie_preserve(jar) %>% perform_with_retry())
  pages <- list(list(html = html, rows = parse_opi_job_page(html, url)))
  page_num <- 2
  while (nrow(pages[[length(pages)]]$rows) == page_size && page_num <= max_pages) {
    fields <- extract_aspnet_postback_fields(html)
    fields[["__EVENTTARGET"]] <- "ctl00$ContentPlaceHolder1$grdJobListing"
    fields[["__EVENTARGUMENT"]] <- paste0("Page$", page_num)
    html <- resp_body_string(do.call(req_body_form, c(list(opi_request(url) %>% req_cookie_preserve(jar)), fields)) %>%
                               perform_with_retry())
    pages[[length(pages) + 1]] <- list(html = html, rows = parse_opi_job_page(html, url))
    page_num <- page_num + 1
  }
  pages
}

# One posting's detail page, by its row's postback target on that list page.
opi_detail_row <- function(page_html, target, url, jar) {
  f <- extract_aspnet_postback_fields(page_html)
  f[["__EVENTTARGET"]] <- target
  f[["__EVENTARGUMENT"]] <- ""
  resp <- do.call(req_body_form, c(list(opi_request(url) %>% req_cookie_preserve(jar)), f)) %>% perform_with_retry()
  d <- parse_opi_job_details(resp_body_string(resp))
  # The same excerpt fetch_opi_page_details() archives as OPI_Description.
  data.frame(District = d$District_Name, School = d$School,
             Description = substr(gsub("\\s+", " ", d$Description), 1, 600), stringsAsFactors = FALSE)
}

#' OPI rows for the daily check: District, title, url, Link_Key, List_Key.
fetch_opi_presence <- function(known = NULL, url = OPI_LISTING_URL, page_size = 50, max_pages = 60,
                               delay = 0.5, budget_secs = 900) {
  jar <- tempfile()
  on.exit(unlink(jar), add = TRUE)
  deadline <- Sys.time() + budget_secs
  pages <- opi_list_pages(url, jar, page_size, max_pages)
  rows <- dplyr::bind_rows(lapply(seq_along(pages), function(p) {
    r <- pages[[p]]$rows
    if (nrow(r) == 0) return(NULL)
    r$page <- p; r$row <- seq_len(nrow(r))
    r
  }))
  if (is.null(rows) || nrow(rows) == 0) {
    return(data.frame(District = character(0), title = character(0), url = character(0), Link_Key = character(0),
                      List_Key = character(0), stringsAsFactors = FALSE))
  }
  rows$List_Key <- opi_list_key(rows$Title, rows$Location, rows$Posted_Date)
  reuse <- opi_reusable_keys(known)
  n_today <- table(rows$List_Key)
  reusable <- names(n_today)[names(n_today) %in% names(reuse) &
                               as.integer(n_today) == vapply(reuse[names(n_today)], function(x) if (is.null(x)) -1L else nrow(x), integer(1))]
  rows$base <- NA_character_
  rows$District <- NA_character_
  for (lk in reusable) {
    i <- which(rows$List_Key == lk)
    rows$base[i] <- sub("#\\d+$", "", reuse[[lk]]$Link_Key)
    rows$District[i] <- reuse[[lk]]$District
  }
  # Detail pages for the rest, on the list page each row is on (that page's own postback state).
  for (p in unique(rows$page[is.na(rows$base)])) {
    targets <- opi_detail_targets(pages[[p]]$html)
    for (i in which(rows$page == p & is.na(rows$base))) {
      if (Sys.time() > deadline || rows$row[i] > length(targets)) next
      Sys.sleep(delay)
      d <- tryCatch(opi_detail_row(pages[[p]]$html, targets[rows$row[i]], url, jar), error = function(e) NULL)
      if (is.null(d)) next
      rows$base[i] <- edjobs::opi_posting_key(d$District, d$School, rows$Title[i], rows$Posted_Date[i], d$Description)
      rows$District[i] <- d$District
    }
  }
  key <- rep(NA_character_, nrow(rows))
  ok <- !is.na(rows$base)
  key[ok] <- edjobs::presence_occurrence_keys(rows$base[ok])
  data.frame(District = rows$District, title = rows$Title, url = url, Link_Key = key, List_Key = rows$List_Key,
             stringsAsFactors = FALSE)
}

PRESENCE_FEEDS <- list(edjobs::presence_feed(OPI_PRESENCE_BOARD, "OPI", function(known) fetch_opi_presence(known)))
