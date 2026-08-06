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
})

test_that("parse_applitrack_output returns zero rows (not an error) when there's no postingsList content", {
  result <- parse_applitrack_output("document.write('<div>No postings here</div>');")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("title", "position", "position2", "date_posted", "location", "closing_date"))
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
