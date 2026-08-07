test_that("parse_neogov_postings extracts real University of Montana posting fields", {
  # Real fixture captured 2026-08-07 from
  # https://ummissoula.attract.neoed.com/JobList?layoutId=Jobs-1&websiteUrl=...
  # (page 1, pageSize 50, unaltered real response -- 44 real postings).
  fixture <- paste(readLines(test_path("fixtures", "neogov_ummissoula_joblist.html"), warn = FALSE), collapse = "\n")

  result <- parse_neogov_postings(fixture, "University of Montana")

  expect_equal(nrow(result), 44)
  expect_equal(result$Title[1], "Academic Advisor II, College of Humanities and Social Sciences and the College of Science")
  expect_equal(result$Location[1], "32 Campus Dr, Missoula, MT 59801, USA")
  # Helena College UM and Missoula College UM postings both surface on this
  # same board (confirmed by real Helena, MT addresses in the fixture) --
  # neither branch campus needs its own registry row.
  expect_true(any(grepl("Helena, MT", result$Location)))
  # Session query params (visitor/session) are stripped -- confirmed live
  # that reusing another session's params 500s, while the bare URL 200s.
  expect_false(grepl("[?&]", result$Link[1]))
  expect_true(grepl("^https://www\\.schooljobs\\.com/careers/ummissoula/jobs/", result$Link[1]))
  # No posted-date field exists anywhere in the real fragment -- a genuine
  # absence, same pattern as JazzHR/Paycom's missing Posted_Date.
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_neogov_postings returns zero rows (not an error) for a genuinely empty board", {
  empty_fragment <- '<div class="wrapper__body"></div>'

  result <- parse_neogov_postings(empty_fragment, "University of Montana")

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_neogov_postings requests the XMLHttpRequest-gated endpoint and stops paging on a short page", {
  fixture <- paste(readLines(test_path("fixtures", "neogov_ummissoula_joblist.html"), warn = FALSE), collapse = "\n")

  httr2::local_mocked_responses(list(
    httr2::response(200, headers = list("Content-Type" = "text/html; charset=utf-8"), body = charToRaw(fixture))
  ))

  result <- fetch_neogov_postings("ummissoula", "University of Montana", page_size = 50)

  expect_equal(nrow(result), 44)
  expect_equal(result$Title[1], "Academic Advisor II, College of Humanities and Social Sciences and the College of Science")
})
