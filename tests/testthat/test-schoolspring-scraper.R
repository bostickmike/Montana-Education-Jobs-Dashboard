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

# Real detail records captured 2026-11-03 from api.schoolspring.com/api/Jobs/<jobId>.
ss_job_fixture <- function(id) {
  paste(readLines(test_path("fixtures", paste0("schoolspring_job_", id, ".json")), warn = FALSE), collapse = "\n")
}

test_that("parse_schoolspring_job_json reads a filled posting with no deadline", {
  # Lewistown District Nurse: left the board, record still says Filled (50);
  # "Posted until filled" is stored as closeDate 2050-01-01.
  r <- parse_schoolspring_job_json(ss_job_fixture(5803798))
  expect_equal(r$job_id, "5803798")
  expect_equal(r$Job_Status, "filled")
  expect_true(is.na(r$Close_Date))
  expect_equal(c(r$Pay_Min, r$Pay_Max, r$Pay_Unit), c("25.67", "25.67", "hour"))
})

test_that("parse_schoolspring_job_json keeps the deadline applicants see, not the UTC closeDate", {
  # Ronan assistant girls' basketball: closeDate 2026-11-14T06:59 (UTC) is
  # "Nov 13, 2026 11:59 PM (Mountain Standard Time)" on the board. Its
  # "Per Year" $1,919.10 is a coaching stipend, not a salary.
  r <- parse_schoolspring_job_json(ss_job_fixture(5732320))
  expect_equal(r$Close_Date, "2026-11-13")
  expect_equal(r$Job_Status, "posted")
  expect_equal(r$Pay_Unit, "stipend")
  expect_equal(r$Pay_Min, 1919.1)
  expect_match(r$Pay_Text, "^\\$1,919\\.10 Per Year")
})

test_that("parse_schoolspring_job_json reads units from the amount when the label is ambiguous", {
  # Belgrade .5 FTE math teacher: "Hourly and Certified Pay" $22,725-$26,622 is a salary.
  r <- parse_schoolspring_job_json(ss_job_fixture(5785656))
  expect_equal(c(r$Pay_Min, r$Pay_Max), c(22725, 26622))
  expect_equal(r$Pay_Unit, "year")
  # Belgrade substitute bus driver: "Substitute" $45 says neither hour nor day.
  r <- parse_schoolspring_job_json(ss_job_fixture(5747025))
  expect_true(is.na(r$Pay_Min) && is.na(r$Pay_Unit) && is.na(r$Pay_Text))
})

test_that("add_schoolspring_details joins detail fields by job ID and leaves failed ones NA", {
  postings <- data.frame(Title = c("Coach", "Teacher"), Location = "Ronan, Montana",
                         Posted_Date = "2026-06-01",
                         Link = c("https://ronan.schoolspring.com/jobs/5732320",
                                  "https://ronan.schoolspring.com/jobs/1"),
                         stringsAsFactors = FALSE)
  httr2::local_mocked_responses(function(req) {
    if (grepl("/5732320$", req$url)) {
      httr2::response(200, headers = list("Content-Type" = "application/json"), body = charToRaw(ss_job_fixture(5732320)))
    } else {
      httr2::response(404)
    }
  })
  r <- add_schoolspring_details(postings, delay = 0)
  expect_equal(nrow(r), 2)
  expect_equal(r$Close_Date, c("2026-11-13", NA))
  expect_equal(r$Pay_Unit, c("stipend", NA))
  expect_equal(r$Title, postings$Title)
})
