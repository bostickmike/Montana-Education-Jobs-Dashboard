# extract_posted_pay(): the pay a posting itself states. Unit tests use
# wording copied from real AppliTrack postings (Great Falls, Billings, MCPS,
# Helena, Sweetwater); the parser test uses a real captured Output.asp page.

test_that("extract_posted_pay reads amounts, ranges and units as written", {
  p <- extract_posted_pay(c(
    "LOCATION: Great Falls High School SALARY: $15.14 per hour (25/26 Salary Schedule)",
    "EMPLOYMENT: 2026/2027 SALARY: $48,300-$73,957 (2026/2027 salary schedule)",
    "7.5 hrs/day$21.46 to $22.81 per hour, depending on experience",
    "Starts: August 2026Stipend: $3,548.00Required Coaches Certificates",
    "Long Term Substitutes are paid at $250.00 per day and issued a contract.",
    "Salary: $160.00/Whole Day, $80.00/Half Day",
    "6:00am - 2:30pm $20.60* - $21.95*/hr depending on experience",
    "Part Time, at most 29 hours per weekSalary: P-V, $25.69",
    "BEA Salary Schedule; Full Benefits",
    NA
  ))
  expect_equal(p$Pay_Min, c(15.14, 48300, 21.46, 3548, 250, 160, 20.60, 25.69, NA, NA))
  expect_equal(p$Pay_Max, c(15.14, 73957, 22.81, 3548, 250, 160, 21.95, 25.69, NA, NA))
  expect_equal(p$Pay_Unit, c("hour", "year", "hour", "stipend", "day", "day", "hour", "hour", NA, NA))
  expect_true(all(is.na(p$Pay_Text) == is.na(p$Pay_Min)))
})

test_that("extract_posted_pay ignores bonuses, fees and differentials", {
  p <- extract_posted_pay(c(
    "*We offer a one-time $1,000 signing bonus. Starting salary will be a minimum of $46,225 to max of $86,400 DOE",
    "*Includes a $0.50 per hour differential. Pay: $20.60 per hour",
    "Application fee of $25 required."
  ))
  expect_equal(p$Pay_Min, c(46225, 20.60, NA))
  expect_equal(p$Pay_Max, c(86400, 20.60, NA))
})

test_that("parse_applitrack_output carries each posting's stated pay", {
  path <- test_path("fixtures", "applitrack_output_mcps_pay.bin")
  js <- iconv(readChar(path, file.size(path), useBytes = TRUE), "WINDOWS-1252", "UTF-8")
  out <- parse_applitrack_output(js)
  expect_true(all(c("Pay_Min", "Pay_Max", "Pay_Unit", "Pay_Text") %in% names(out)))
  expect_gt(nrow(out), 0)
  expect_gte(mean(!is.na(out$Pay_Min)), 0.9)
  ok <- !is.na(out$Pay_Min)
  expect_true(all(out$Pay_Min[ok] <= out$Pay_Max[ok]))
  expect_true(all(out$Pay_Unit[ok] %in% c("hour", "day", "month", "year", "credit hour", "stipend", NA)))
  expect_true(all(mapply(function(txt, v) grepl(format(v, big.mark = ",", nsmall = 0, scientific = FALSE), gsub("\\.00\\b", "", txt), fixed = TRUE) || grepl(sprintf("%.2f", v), txt, fixed = TRUE),
                         out$Pay_Text[ok], out$Pay_Min[ok])))
  expect_equal(ncol(parse_applitrack_output("")), ncol(out))
})

test_that("extract_posted_pay skips a benefits package value and a $0.00 blank pay field", {
  # Real FVCC (Paycom) and LCCC (NEOGOV) wording, 2026-10-30.
  p <- extract_posted_pay(c(
    "Benefits eligible Unlock Exceptional Benefits at FVCC (Worth ~$25K) Our employees",
    "Adjunct - $0.00 Hourly",
    "Full-time, benefits eligible, $45,000 per year",
    "Salary: $52,000 plus benefits"
  ))
  expect_equal(p$Pay_Min, c(NA, NA, 45000, 52000))
  expect_equal(p$Pay_Unit, c(NA, NA, "year", "year"))
})

test_that("ensure_posted_pay_columns pads a zero-row frame", {
  out <- ensure_posted_pay_columns(data.frame(Title = character(0)))
  expect_equal(names(out), c("Title", "Pay_Min", "Pay_Max", "Pay_Unit", "Pay_Text"))
  expect_equal(nrow(out), 0)
  expect_type(out$Pay_Min, "double")
})

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

test_that("parse_neogov_card_pay reads each schooljobs card's pay line by job ID", {
  pay <- parse_neogov_card_pay(read_fixture("schooljobs_ummissoula_joblist_2026-10-30.html"))
  expect_equal(nrow(pay), 10)
  expect_equal(pay$Job_ID[1], "5533670")
  expect_equal(pay$Pay_Text[1], "Hourly Staff Full-time - $22.53 Hourly")
  expect_equal(pay$Pay_Unit[5], "year")
  expect_equal(c(pay$Pay_Min[5], pay$Pay_Max[5]), c(60000, 70000))
  # "Faculty Part-time - See Position Description": no figure stated.
  expect_true(is.na(pay$Pay_Min[8]))
  expect_equal(nrow(parse_neogov_card_pay("<html></html>")), 0)
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
