
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
