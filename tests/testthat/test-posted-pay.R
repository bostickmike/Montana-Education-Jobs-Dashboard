
# --- Higher ed boards ---------------------------------------------------------

read_fixture <- function(name) paste(readLines(test_path("fixtures", name), warn = FALSE), collapse = "\n")

test_that("parse_isolvedhire_postings reads the structured min/max salary and pay frame", {
  out <- parse_isolvedhire_postings(read_fixture("isolvedhire_bfcc_jobs.json"), "Blackfeet Community College")
  expect_equal(out$Pay_Min, c(17, 45888, 18, 17, 50000, 16, 50477))
  expect_equal(out$Pay_Max, c(17.35, 47887, 18.21, 17.35, 50938, 17.35, 52676))
  expect_equal(out$Pay_Unit, c("hour", "year", "hour", "hour", "year", "hour", "year"))
  expect_equal(out$Pay_Text[2], "$45,888 - $47,887 per year")
  empty <- parse_isolvedhire_postings('{"data":{"jobs":[]}}', "Blackfeet Community College")
  expect_true(all(POSTED_PAY_COLUMNS %in% names(empty)))
})

test_that("parse_paycom_posting_pay reads salaryRange, and NA when a posting states none", {
  stated <- parse_paycom_posting_pay(read_fixture("paycom_fvcc_posting_125040_2026-10-30.json"))
  expect_equal(c(stated$Pay_Min, stated$Pay_Max), c(125000, 155000))
  expect_equal(stated$Pay_Unit, "year")
  expect_equal(stated$Pay_Text, "$125,000.00 - $155,000.00 Salary")
  adjunct <- parse_paycom_posting_pay(read_fixture("paycom_fvcc_posting_6792_2026-10-30.json"))
  expect_true(is.na(adjunct$Pay_Min) && is.na(adjunct$Pay_Text))
  expect_true(is.na(parse_paycom_posting_pay(NA_character_)$Pay_Min))
})

test_that("fetch_neogov_postings joins schooljobs pay onto the Attract postings by job ID", {
  attract <- read_fixture("neogov_ummissoula_joblist_2026-10-30.html")
  schooljobs <- read_fixture("schooljobs_ummissoula_joblist_2026-10-30.html")
  html <- function(body) httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(body))
  httr2::local_mocked_responses(function(req) {
    if (grepl("attract.neoed.com", req$url, fixed = TRUE)) return(html(attract))
    if (grepl("page=1(&|$)", req$url)) return(html(schooljobs))
    html("<html></html>")
  })
  out <- fetch_neogov_postings("ummissoula", "University of Montana", page_size = 100)
  expect_equal(nrow(out), 58)
  expect_equal(out$Pay_Text[grepl("/jobs/5533670/", out$Link)], "Hourly Staff Full-time - $22.53 Hourly")
  # Only the ten postings on the mocked first listing page get pay.
  expect_equal(sum(!is.na(out$Pay_Min)), 9)
})

test_that("fetch_neogov_postings keeps every posting when the schooljobs listing fails", {
  attract <- read_fixture("neogov_ummissoula_joblist_2026-10-30.html")
  httr2::local_mocked_responses(function(req) {
    if (grepl("attract.neoed.com", req$url, fixed = TRUE)) {
      return(httr2::response(200, headers = list("Content-Type" = "text/html"), body = charToRaw(attract)))
    }
    httr2::response(404)
  })
  out <- suppressMessages(fetch_neogov_postings("ummissoula", "University of Montana", page_size = 100))
  expect_equal(nrow(out), 58)
  expect_true(all(POSTED_PAY_COLUMNS %in% names(out)))
  expect_true(all(is.na(out$Pay_Min)))
})
