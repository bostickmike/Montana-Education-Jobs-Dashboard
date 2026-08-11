test_that("parse_schoolspring_json extracts real Montana posting fields from a single page", {
  # Real fixture captured 2026-08-06 from
  # https://api.schoolspring.com/api/Jobs/GetPagedJobsWithSearch?domainName=lewistown.schoolspring.com...
  fixture <- paste(readLines(test_path("fixtures", "schoolspring_lewistown.json"), warn = FALSE), collapse = "\n")

  result <- parse_schoolspring_json(fixture, "lewistown.schoolspring.com")

  expect_equal(nrow(result), 10)
  expect_equal(result$Title[1:3], c(
    "District Nurse",
    "Fergus High School Head Cheer Coach",
    "Lewistown Junior High School Head and Assistant Volleyball Coaches"
  ))
  expect_equal(result$Location[1], "Lewistown, Montana")
  expect_equal(result$Posted_Date[1], "2026-06-25")
  expect_equal(result$Link[1], "https://lewistown.schoolspring.com/jobs/5803798")
  # Real title containing an HTML entity -- confirms JSON string decoding
  # (not raw HTML) is what's happening here, not a coincidence of ASCII-only
  # titles.
  expect_equal(result$Title[6], "Custodian - Lewis &amp; Clark Elementary")
})

test_that("parse_schoolspring_json returns zero rows (not an error) for a genuinely empty district", {
  # Real shape confirmed live for Columbia Falls SD6 and Polson SD -- valid
  # domainName, success:true, empty jobsList -- not an error response.
  empty_response <- '{"success":true,"message":"","validationErrors":[],"value":{"page":1,"size":50,"jobsList":[]}}'

  result <- parse_schoolspring_json(empty_response, "sd6.schoolspring.com")

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("parse_schoolspring_json excludes SchoolSpring sample vacancies", {
  fixture <- '{"success":true,"message":"","validationErrors":[],"value":{"page":1,"size":25,"jobsList":[
    {"jobId":1,"employer":"SchoolSpring","title":"Sample Certified Position","location":"Example, Montana","displayDate":"2010-02-16T06:00:00"},
    {"jobId":2,"employer":"Real District","title":"Science Teacher","location":"Real, Montana","displayDate":"2026-08-01T06:00:00"}
  ]}}'

  result <- parse_schoolspring_json(fixture, "example.schoolspring.com")

  expect_equal(nrow(result), 1)
  expect_equal(result$Title, "Science Teacher")
})

test_that("fetch_schoolspring_postings stops paging once a page comes back short", {
  fixture <- paste(readLines(test_path("fixtures", "schoolspring_lewistown.json"), warn = FALSE), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "application/json"), body = charToRaw(fixture)))
  )

  # 10 real rows < the default page_size of 50, so fetch_schoolspring_postings
  # should stop after the first page rather than requesting a second one
  # (which the mock above has no second response queued for -- a second
  # request would error rather than return more of the same page).
  result <- fetch_schoolspring_postings("lewistown.schoolspring.com")

  expect_equal(nrow(result), 10)
})
