test_that("parse_applitrack_output un-escapes document.write literals and parses real Montana posting fields", {
  # Real fixture captured 2026-08-06 from
  # https://www.applitrack.com/ehps/onlineapp/jobpostings/Output.asp?all=1
  # (East Helena Public Schools) -- the endpoint default.aspx's own inline
  # script injects into the page via document.write() rather than being
  # server-rendered directly.
  fixture <- paste(readLines(test_path("fixtures", "applitrack_output_mt.txt"), warn = FALSE), collapse = "\n")

  result <- parse_applitrack_output(fixture)

  expect_equal(nrow(result), 12)
  expect_equal(result$title[1:4], c(
    "Assistant Wrestling Coaches",
    "Math Teacher",
    "Middle School Teacher-Intervention Specialist",
    "Paraprofessional"
  ))
  # Regression (carried over from the Wyoming port): "Position Type:"
  # consumes TWO values (category + subcategory) only when the next value
  # isn't itself another label's value -- getting this wrong shifts every
  # subsequent field by one position for every row after the first
  # mismatch. Row 1 here exercises the two-value case for real
  # ("Athletics/Activities/" + "Coaching").
  expect_equal(result$position[1:4], c(
    "Athletics/Activities/", "District Wide/", "District Wide/", "District Wide/"
  ))
  expect_equal(result$position2[1:4], c(
    "Coaching", "ELEMENTARY TEACHER", "ELEMENTARY TEACHER", "Paraprofessional"
  ))
  expect_equal(result$location[1:4], c(
    "East Helena High School", "District Wide", "East Valley Middle School", "District Wide"
  ))
  # This district's real postings carry no "Closing Date:" label at all --
  # confirmed real absence, not a parsing gap.
  expect_true(all(is.na(result$closing_date)))
  # Every posting carries AppliTrack's own job ID (block id "p<ID>_").
  expect_true(all(grepl("^[0-9]+$", result$job_id)))
  expect_equal(anyDuplicated(result$job_id), 0)
})

test_that("AppliTrack postings get their own per-posting link and closing date", {
  # Real MCPS fixture (2026-10-30): 25 postings, each block "p<JobID>_" with
  # "JobID: <n>" beside the title; most say "open until filled".
  path <- test_path("fixtures", "applitrack_output_mcps_pay.bin")
  js <- iconv(readChar(path, file.size(path), useBytes = TRUE), "WINDOWS-1252", "UTF-8")
  out <- parse_applitrack_output(js)
  expect_equal(nrow(out), 25)
  expect_equal(out$job_id[1], "2138")
  expect_equal(out$title[1], "Bookkeeper - Sentinel High School")
  expect_equal(out$closing_date[1], "open until filled")
  expect_equal(anyDuplicated(out$job_id), 0)
  expect_true("job_id" %in% names(parse_applitrack_output("")))

  url <- applitrack_posting_url("mcpsmt", out$job_id)
  expect_equal(url[1], "https://www.applitrack.com/mcpsmt/onlineapp/default.aspx?AppliTrackLayoutMode=detail&AppliTrackJobId=2138")
  expect_true(is.na(applitrack_posting_url("mcpsmt", NA_character_)))
  # The link is a stable posting identity, so two postings with the same
  # title stay two postings; the board URL alone still isn't one.
  expect_true(all(is_stable_posting_url(url)))
  expect_false(is_stable_posting_url("https://www.applitrack.com/mcpsmt/onlineapp/default.aspx"))
  ids <- add_k12_posting_identity(data.frame(
    title = c("Paraprofessional", "Paraprofessional"), location = "District Wide",
    date_posted = "2026-10-01", url = applitrack_posting_url("mcpsmt", c("1", "2")),
    District = "Missoula County Public Schools", Posting_Source = "AppliTrack (direct district board)"))
  expect_equal(ids$Posting_Identity_Method, rep("Stable per-posting URL", 2))
  expect_equal(ids$Posting_ID[1], paste0("url:", tolower(applitrack_posting_url("mcpsmt", "1"))))
})

test_that("parse_applitrack_output returns zero rows (not an error) when there's no postingsList content", {
  result <- parse_applitrack_output("document.write('<div>No postings here</div>');")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("title", "position", "position2", "date_posted", "location", "closing_date", "job_id",
                                "Pay_Min", "Pay_Max", "Pay_Unit", "Pay_Text"))
})

test_that("fetch_applitrack_postings decodes Windows-1252 bytes instead of silently dropping them as NA", {
  # Regression: Applitrack serves Windows-1252 with no charset in
  # Content-Type. httr2 guesses UTF-8 by default; if a posting contains a
  # non-ASCII Windows-1252 byte (e.g. an en-dash, 0x96), UTF-8 decoding
  # fails and resp_body_string() returns NA rather than erroring -- which
  # parse_applitrack_output() then silently turns into zero rows,
  # indistinguishable from a district with genuinely no openings. Confirmed
  # as a real bug in the Wyoming port (10 of 25 WY districts were affected,
  # one hiding 69 real postings), so it's tested here from the start rather
  # than waiting to rediscover it in Montana's own data. This fixture is
  # the real applitrack_output_mt.txt fixture with an en-dash injected into
  # the first title and re-encoded as raw Windows-1252 bytes, exactly
  # mirroring what the live endpoint sends.
  raw_bytes <- readBin(
    test_path("fixtures", "applitrack_output_mt_windows1252.bin"),
    "raw",
    file.info(test_path("fixtures", "applitrack_output_mt_windows1252.bin"))$size
  )
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "text/javascript"), body = raw_bytes))
  )

  result <- fetch_applitrack_postings("ehps")

  expect_equal(nrow(result), 12)
  expect_equal(result$title[1], "Assistant Wrestling Coaches – JV/Varsity")
})

test_that("parse_applitrack_output reads each field from its own <li> (one-value Position Type)", {
  # Real fixture captured 2026-11-03 from Teton County SD1 (WY)
  # https://www.applitrack.com/tcsd/onlineapp/jobpostings/Output.asp?all=1 .
  # JobID 836 has a one-value "Position Type:" followed by "Date Posted:
  # 10/26/2026". The old running-index parser took the date as a second
  # Position Type value, so the posting got date_posted "TCSD Schools" and
  # location "10/26/2026".
  path <- test_path("fixtures", "applitrack_output_wy_teton_single_position_type.bin")
  js <- iconv(readChar(path, file.size(path), useBytes = TRUE), "WINDOWS-1252", "UTF-8")
  out <- parse_applitrack_output(js)
  expect_equal(nrow(out), 14)
  expect_true(all(grepl("^\\d{1,2}/\\d{1,2}/\\d{4}$", out$date_posted)))
  p <- out[out$job_id == "836", ]
  expect_equal(p$title, "K-5 Special Education Teacher, Life Skills")
  expect_equal(p$position, "Student Support Services")
  expect_true(is.na(p$position2))
  expect_equal(p$date_posted, "10/26/2026")
  expect_equal(p$location, "TCSD Schools")
})
