# OPI "Jobs for Teachers" is Montana's statewide fallback feed, the analog
# of Wyoming's WSBA vacancies page -- but unlike WSBA (a plain server-
# rendered page), it's an ASP.NET WebForms GridView with __VIEWSTATE
# postback paging, so these tests cover both the pure table parser and the
# postback-field extraction/chaining that fetch_opi_statewide_postings()
# needs to walk pages 2+.

test_that("parse_opi_job_page extracts real statewide postings from page 1", {
  # Real fixture captured 2026-08-06 from
  # https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx --
  # trimmed to just the <form> (surrounding nav/CSS stripped) with the
  # __VIEWSTATE/__EVENTVALIDATION crypto blobs replaced by short markers,
  # since the tests only need to prove extraction reads whatever value is
  # present, not the real (84KB/38KB) opaque payloads.
  html <- paste(readLines(test_path("fixtures", "opi_jobs_page1.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_opi_job_page(html, "https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx")

  expect_equal(nrow(result), 50)
  expect_equal(result$Title[1:3], c("CTE – Industrial Technology Education", "Administrative - Other", "English"))
  # The grid's own City column, inconsistently formatted across real rows
  # ("Wolf Point " vs "Wolf Point, Montana") -- passed through as-is, not
  # normalized, same as every other platform's raw Location field.
  expect_equal(result$Location[1:2], c("Wolf Point", "Wolf Point, Montana"))
  expect_equal(result$Posted_Date[1], "08/06/2026")
  # No stable per-posting URL exists on this ASP.NET WebForms site
  # (confirmed live with chromote: clicking a posting navigates to
  # frmJobDetailsPublic.aspx with no query string or job ID at all) -- every
  # row's Link is the shared statewide listing URL.
  expect_true(all(result$Link == "https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx"))
})

test_that("parse_opi_job_page returns zero rows (not an error) when the grid table is missing", {
  result <- parse_opi_job_page("<html><body><p>No grid here</p></body></html>", "https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("extract_aspnet_postback_fields reads hidden inputs and each select's selected/first option", {
  html <- paste(readLines(test_path("fixtures", "opi_jobs_page1.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  fields <- extract_aspnet_postback_fields(html)

  expect_equal(fields[["__VIEWSTATE"]], "FAKE_VIEWSTATE_VALUE_FOR_TESTING")
  expect_equal(fields[["__VIEWSTATEGENERATOR"]], "AA117435")
  # No <option selected> in the real page -- the district filter defaults to
  # "%" (all districts), its first <option>'s value, confirming the
  # select-with-no-explicit-selection fallback path.
  expect_equal(fields[["ctl00$ContentPlaceHolder1$ddlDistrict"]], "%")
})

test_that("fetch_opi_statewide_postings chains postback pages using each page's own fresh tokens, and stops on a short page", {
  page1 <- paste(readLines(test_path("fixtures", "opi_jobs_page1.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  page2 <- paste(readLines(test_path("fixtures", "opi_jobs_page2.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  # Synthetic short final page (3 rows, not a real capture) -- proves the
  # "stop once a page comes back under page_size" heuristic fires; every
  # real page captured so far happened to be full (50 rows), so this case
  # needs a synthetic fixture the same way test-schoolspring-scraper.R's
  # empty-response case does.
  page3_short <- '<html><body><form id="aspnetForm" method="post">
    <input name="__EVENTTARGET" type="hidden" value=""/>
    <input name="__EVENTARGUMENT" type="hidden" value=""/>
    <input name="__VIEWSTATE" type="hidden" value="FAKE_PAGE3"/>
    <input name="__VIEWSTATEGENERATOR" type="hidden" value="AA117435"/>
    <input name="__EVENTVALIDATION" type="hidden" value="FAKE_EV_PAGE3"/>
    <select name="ctl00$ContentPlaceHolder1$ddlDistrict"><option value="%">All</option></select>
    <table id="ctl00_ContentPlaceHolder1_grdJobListing">
      <tr><th>Vacancy Area</th><th>City</th><th>Grade Range(s)</th><th>Posted</th><th>Closing Date</th></tr>
      <tr><td><a id="ctl00_ContentPlaceHolder1_grdJobListing_ctl02_btnJobDetailsPublic" href="javascript:__doPostBack(&#39;x&#39;,&#39;&#39;)">Music</a></td><td>Terry</td><td>High School</td><td>08/01/2026</td><td>Open Until Filled</td></tr>
      <tr><td><a id="ctl00_ContentPlaceHolder1_grdJobListing_ctl03_btnJobDetailsPublic" href="javascript:__doPostBack(&#39;x&#39;,&#39;&#39;)">Art</a></td><td>Terry</td><td>High School</td><td>08/01/2026</td><td>Open Until Filled</td></tr>
      <tr><td><a id="ctl00_ContentPlaceHolder1_grdJobListing_ctl04_btnJobDetailsPublic" href="javascript:__doPostBack(&#39;x&#39;,&#39;&#39;)">PE</a></td><td>Terry</td><td>High School</td><td>08/01/2026</td><td>Open Until Filled</td></tr>
    </table>
  </form></body></html>'

  httr2::local_mocked_responses(list(
    httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(page1)),
    httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(page2)),
    httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(page3_short))
  ))

  result <- fetch_opi_statewide_postings(page_size = 50)

  expect_equal(nrow(result), 103)
  expect_equal(result$Title[1], "CTE – Industrial Technology Education")
  # Page 2's real first posting -- confirms the second (POST) request really
  # returned page2's fixture content, not a re-fetch of page1.
  expect_true("School Counseling" %in% result$Title)
  # The synthetic short final page's real content, confirming paging
  # actually stopped here (only 3 mocked responses were queued -- a fourth
  # request would error) rather than looping forever.
  expect_equal(sum(result$Title == "Music" & result$Location == "Terry"), 1)
})
