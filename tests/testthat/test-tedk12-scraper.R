# TedK12 is ported but not yet exercised against a live Montana district --
# every Montana district found so far that dual-brands SchoolSpring/TedK12
# (Whitefish, Columbia Falls, Polson, Lewistown, Laurel) is reachable via
# the SchoolSpring API directly, the same pattern Wyoming saw (TedK12 only
# needed as a fallback when SchoolSpring doesn't cover a district). This
# fixture is carried over from the Wyoming port unchanged rather than
# freshly captured -- it's a generic browser-rendered capture of TedK12's
# classic job-table markup (title/date/position/location columns), not
# Wyoming-specific content, so it still validates the parser's real
# structure. Replace with a real Montana capture the first time a Montana
# district actually needs this path.

test_that("parse_tedk12_postings extracts real job rows from a real browser-rendered capture", {
  # Regression: TedK12/PowerSchool Hire serves a near-empty modern app
  # shell to a request with no/default User-Agent, but the real classic
  # jQuery job board (this fixture) to one that looks like a browser -- see
  # fetch_tedk12_postings()'s header comment for the full story.
  html <- paste(readLines(test_path("fixtures", "tedk12_goshen.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_tedk12_postings(html, "https://example.tedk12.com/hire/index.aspx")

  expect_equal(nrow(result), 12)
  expect_true(all(result$url == "https://example.tedk12.com/hire/index.aspx"))
  # The sortable-column header row ("Job Title"/"Posting Date"/etc., not a
  # real posting) must not survive into the result.
  expect_false("Job Title" %in% result$title)

  clerk <- result[result$title == "Office Clerk - Platte River High School", ]
  expect_equal(nrow(clerk), 1)
  expect_equal(clerk$date_posted, "08/04/2026")
  expect_equal(clerk$position, "Support")
  expect_equal(clerk$location, "Platte River High School")
})

test_that("parse_tedk12_postings returns zero rows (not an error) when there's no job table at all", {
  result <- parse_tedk12_postings("<html><body><p>Not a TedK12 page</p></body></html>", "https://example.tedk12.com/hire/index.aspx")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("title", "date_posted", "position", "location", "url"))
})
