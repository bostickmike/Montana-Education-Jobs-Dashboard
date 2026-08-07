test_that("parse_paycom_postings extracts real Flathead Valley CC posting fields", {
  # Real fixture captured 2026-08-06 from a POST to
  # https://portal-applicant-tracking.us-cent.paycomonline.net/api/ats/job-posting-previews/search
  # (Flathead Valley Community College, portal key
  # 23D9610C7FF62DF6DF80223B0B1ED6E3) -- unaltered real response.
  fixture <- paste(readLines(test_path("fixtures", "paycom_fvcc.json"), warn = FALSE), collapse = "\n")

  result <- parse_paycom_postings(fixture, "23D9610C7FF62DF6DF80223B0B1ED6E3")

  expect_equal(nrow(result), 29)
  expect_equal(result$Title[1:3], c(
    "Adjunct Instructor, Music", "Temp, Barista, Common Grounds", "Coordinator, Communications and Social Media"
  ))
  expect_equal(result$Location[1], "KALISPELL, MT 59901")
  # jobId 74763 -- confirmed live with chromote that clicking this exact
  # posting in the real rendered app navigates the browser to exactly this
  # URL, and that the URL also resolves standalone on a fresh
  # unauthenticated request (unlike the OPI statewide feed above, which has
  # no stable per-posting URL at all).
  expect_equal(result$Link[2], "https://www.paycomonline.net/v4/ats/web.php/portal/23D9610C7FF62DF6DF80223B0B1ED6E3/jobs/74763")
  # postedOn is genuinely "" on every real posting -- confirmed real
  # absence, not a parsing gap, same as JazzHR's missing Posted_Date field.
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_paycom_postings returns zero rows (not an error) for a genuinely empty board", {
  empty_response <- '{"jobPostingPreviews":[],"jobPostingPreviewsCount":0}'

  result <- parse_paycom_postings(empty_response, "23D9610C7FF62DF6DF80223B0B1ED6E3")

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("extract_paycom_jwt finds the embedded JWT in the career page HTML", {
  # Synthetic JWT-shaped token, not a real captured credential (Paycom's
  # real tokens are short-lived but still shouldn't be committed to the
  # repo) -- structurally identical (three base64url segments, real
  # header/payload key names) to what the live page actually embeds.
  html <- paste(readLines(test_path("fixtures", "paycom_fvcc_career_page.html"), warn = FALSE), collapse = "\n")

  token <- extract_paycom_jwt(html)

  expect_true(grepl("^eyJ", token))
  expect_equal(length(strsplit(token, "\\.")[[1]]), 3)
})

test_that("extract_paycom_jwt errors clearly when no token is present", {
  expect_error(extract_paycom_jwt("<html><body>no token here</body></html>"), "No JWT found")
})

test_that("fetch_paycom_postings fetches the career page, extracts the token, and posts the search request", {
  career_html <- paste(readLines(test_path("fixtures", "paycom_fvcc_career_page.html"), warn = FALSE), collapse = "\n")
  jobs_json <- paste(readLines(test_path("fixtures", "paycom_fvcc.json"), warn = FALSE), collapse = "\n")

  httr2::local_mocked_responses(list(
    httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(career_html)),
    httr2::response(200, headers = list("Content-Type" = "application/json"), body = charToRaw(jobs_json))
  ))

  result <- fetch_paycom_postings("23D9610C7FF62DF6DF80223B0B1ED6E3", "Flathead Valley Community College")

  expect_equal(nrow(result), 29)
  expect_equal(result$Title[1], "Adjunct Instructor, Music")
})
