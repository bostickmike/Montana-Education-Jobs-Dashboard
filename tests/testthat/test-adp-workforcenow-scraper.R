test_that("parse_adp_workforcenow_postings extracts real University of Providence posting fields", {
  # Real fixture captured 2026-08-07 from
  # https://workforcenow.adp.com/mascsr/default/careercenter/public/events/staffing/v1/job-requisitions
  # (cid 7b7a7621-2d08-46ed-a694-79735466f015, ccId 19000101_000001,
  # unaltered real response -- 4 real postings, matching the rendered
  # page's own "Current Openings (4 of 4)" count).
  fixture <- paste(readLines(test_path("fixtures", "adp_uprovidence_jobs.json"), warn = FALSE), collapse = "\n")

  result <- parse_adp_workforcenow_postings(fixture, "7b7a7621-2d08-46ed-a694-79735466f015", "19000101_000001")

  expect_equal(nrow(result), 4)
  expect_equal(result$Title[1], "Adjunct Instructor of Biology")
  expect_equal(result$Location[1], "Great Falls")
  expect_equal(result$Posted_Date[1], "2026-07-31")
  # ExternalJobID (566249) is buried in customFieldGroup$stringFields, not
  # a top-level field -- confirmed live with chromote that clicking this
  # exact posting appends "&jobId=566249" to the recruitment.html URL.
  expect_equal(result$Link[1],
    "https://workforcenow.adp.com/mascsr/default/mdf/recruitment/recruitment.html?cid=7b7a7621-2d08-46ed-a694-79735466f015&ccId=19000101_000001&type=JS&lang=en_US&jobId=566249")
})

test_that("parse_adp_workforcenow_postings returns zero rows (not an error) for a genuinely empty board", {
  empty_response <- '{"jobRequisitions":[]}'

  result <- parse_adp_workforcenow_postings(empty_response, "7b7a7621-2d08-46ed-a694-79735466f015", "19000101_000001")

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_adp_workforcenow_postings queries the job-requisitions endpoint with cid/ccId and parses the response", {
  fixture <- paste(readLines(test_path("fixtures", "adp_uprovidence_jobs.json"), warn = FALSE), collapse = "\n")

  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "application/json"), body = charToRaw(fixture)))
  )

  result <- fetch_adp_workforcenow_postings("7b7a7621-2d08-46ed-a694-79735466f015", "19000101_000001", "University of Providence")

  expect_equal(nrow(result), 4)
  expect_equal(result$Title[1], "Adjunct Instructor of Biology")
})
