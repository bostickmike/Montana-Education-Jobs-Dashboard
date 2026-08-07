test_that("parse_jazzhr_postings extracts real Montana Tech posting fields, using department as Location", {
  # Real fixture captured 2026-08-06 from
  # https://montanatechuniversity.applytojob.com/apply -- trimmed to just
  # the .jobs-list container (surrounding page chrome/CSS stripped).
  html <- paste(readLines(test_path("fixtures", "jazzhr_montanatech.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_jazzhr_postings(html, "Montana Tech")

  expect_equal(nrow(result), 15)
  expect_equal(result$Title[1:3], c(
    "Adjunct Faculty for AY 26 (Fall '25, Spring '26& Summer '26)",
    "Adjunct Faculty for AY 27 (Fall '26, Spring '27 & Summer '27)",
    "Admissions Representative II"
  ))
  # Every real posting is "Butte, MT" (Montana Tech has one campus, so city
  # carries no distinguishing signal) -- department is used instead, the
  # same choice already made for Montana's multi-department PeopleAdmin
  # institutions.
  expect_equal(result$Location[1:3], c("All Departments", "All Departments", "Admissions"))
  # Regression: Highlands College shares Montana Tech's own board rather
  # than having a separate one -- confirmed live, its postings show up here
  # with department "Highlands College", not on any separate registry entry.
  # Institution (2026-08-07) now attributes those rows to Highlands College
  # itself, not Montana Tech, while everything else still counts as Montana
  # Tech -- Location keeps carrying the raw department either way.
  expect_true("Highlands College" %in% result$Location)
  highlands_rows <- result[result$Location == "Highlands College", ]
  expect_true(nrow(highlands_rows) > 0)
  expect_true(all(highlands_rows$Institution == "Highlands College"))
  expect_true(all(result$Institution[result$Location != "Highlands College"] == "Montana Tech"))
  expect_equal(result$Link[3], "https://montanatechuniversity.applytojob.com/apply/KObLHITePi/Admissions-Representative-II")
  # No Posted_Date field exists anywhere on this listing page -- confirmed
  # real absence, not a parsing gap.
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_jazzhr_postings returns zero rows (not an error) when there's no jobs-list at all", {
  result <- parse_jazzhr_postings("<html><body><p>No jobs here</p></body></html>", "Montana Tech")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link", "Institution"))
})

test_that("fetch_jazzhr_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "jazzhr_montanatech.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_jazzhr_postings("montanatechuniversity", "Montana Tech")

  expect_equal(nrow(result), 15)
  expect_equal(result$Title[1], "Adjunct Faculty for AY 26 (Fall '25, Spring '26& Summer '26)")
})
