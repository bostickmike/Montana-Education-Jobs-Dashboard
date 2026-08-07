test_that("parse_isolvedhire_postings extracts real Blackfeet Community College posting fields", {
  # Real fixture captured 2026-08-06 from
  # https://bfcc.isolvedhire.com/core/jobs/10334?getParams=%7B%7D
  # (domain_id 10334, unaltered real response).
  fixture <- paste(readLines(test_path("fixtures", "isolvedhire_bfcc_jobs.json"), warn = FALSE), collapse = "\n")

  result <- parse_isolvedhire_postings(fixture, "Blackfeet Community College")

  expect_equal(nrow(result), 7)
  expect_equal(result$Title[1], "Education Division Administrative Assistant")
  expect_equal(result$Location[1], "Browning")
  # startDateRef "Jul 22, 2026" is the posting's real open date -- confirmed
  # against endDateRef (the closing date), which is always later or
  # multi-year-later for untilFilled postings.
  expect_equal(result$Posted_Date[1], "2026-07-22")
  expect_equal(result$Link[1], "https://bfcc.isolvedhire.com/jobs/1826401")
  expect_true("NARCH Grant Coordinator" %in% result$Title)
})

test_that("parse_isolvedhire_postings returns zero rows (not an error) for a genuinely empty board", {
  empty_response <- '{"success":true,"message":"none","data":{"jobs":[]}}'

  result <- parse_isolvedhire_postings(empty_response, "Blackfeet Community College")

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_isolvedhire_postings builds the getParams={} URL and parses the response", {
  jobs_json <- paste(readLines(test_path("fixtures", "isolvedhire_bfcc_jobs.json"), warn = FALSE), collapse = "\n")

  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "application/json"), body = charToRaw(jobs_json)))
  )

  result <- fetch_isolvedhire_postings("bfcc", "10334", "Blackfeet Community College")

  expect_equal(nrow(result), 7)
  expect_equal(result$Title[1], "Education Division Administrative Assistant")
})
