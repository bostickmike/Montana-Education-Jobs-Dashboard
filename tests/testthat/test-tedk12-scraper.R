# TedK12 needed its first real Montana district once research confirmed
# Hardin School Districts 17H & 1 (Crow Agency/Hardin) -- flagged in the
# original scoping as having "no identifiable third-party ATS" -- actually
# runs its job board on hardinpublic.tedk12.com/hire/index.aspx, the same
# PowerSchool Hire platform already ported from Wyoming. Real fixture
# captured 2026-08-06 via `curl -A "<real browser UA>"`, replacing the
# generic Wyoming (Goshen) capture this test used to run against.

test_that("parse_tedk12_postings extracts real Hardin, MT job rows from a real browser-rendered capture", {
  # Regression: TedK12/PowerSchool Hire serves a near-empty modern app
  # shell to a request with no/default User-Agent, but the real classic
  # jQuery job board (this fixture) to one that looks like a browser -- see
  # fetch_tedk12_postings()'s header comment for the full story.
  html <- paste(readLines(test_path("fixtures", "tedk12_hardin_mt.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_tedk12_postings(html, "https://hardinpublic.tedk12.com/hire/index.aspx")

  expect_equal(nrow(result), 6)
  expect_true(all(result$url == "https://hardinpublic.tedk12.com/hire/index.aspx"))
  # The sortable-column header row ("Job Title"/"Posting Date"/etc., not a
  # real posting) must not survive into the result.
  expect_false("Job Title" %in% result$title)

  tech <- result[result$title == "Maintenance Technician IV - District Wide", ]
  expect_equal(nrow(tech), 1)
  expect_equal(tech$date_posted, "07/31/2026")
  expect_equal(tech$position, "Maintenance")
  expect_equal(tech$location, "District Wide")
})

test_that("parse_tedk12_postings returns zero rows (not an error) when there's no job table at all", {
  result <- parse_tedk12_postings("<html><body><p>Not a TedK12 page</p></body></html>", "https://example.tedk12.com/hire/index.aspx")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("title", "date_posted", "position", "location", "url"))
})
