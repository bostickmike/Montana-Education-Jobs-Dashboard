test_that("parse_neogov_postings extracts real University of Montana posting fields", {
  # Real fixture captured 2026-08-07 from
  # https://ummissoula.attract.neoed.com/JobList?layoutId=Jobs-1&websiteUrl=...
  # (page 1, pageSize 50, unaltered real response -- 44 real postings).
  fixture <- paste(readLines(test_path("fixtures", "neogov_ummissoula_joblist.html"), warn = FALSE), collapse = "\n")

  result <- parse_neogov_postings(fixture, "University of Montana")

  expect_equal(nrow(result), 44)
  expect_equal(result$Title[1], "Academic Advisor II, College of Humanities and Social Sciences and the College of Science")
  expect_equal(result$Location[1], "32 Campus Dr, Missoula, MT 59801, USA")
  expect_equal(result$Institution[1], "University of Montana")
  # Helena College UM, Missoula College UM, and UM Western postings all
  # surface on this same board (confirmed by real street addresses in the
  # fixture) -- Institution (2026-08-07) attributes each posting to its
  # real branch campus instead of lumping everything into University of
  # Montana; none of the three needs its own scrape target, just its own
  # registry row for map/salary reference data.
  helena <- result[grepl("Helena, MT", result$Location), ]
  expect_true(nrow(helena) > 0)
  expect_true(all(helena$Institution == "Helena College"))

  missoula_college <- result[grepl("1205 E Broadway St", result$Location), ]
  expect_true(nrow(missoula_college) > 0)
  expect_true(all(missoula_college$Institution == "Missoula College"))

  um_western <- result[grepl("Dillon, MT", result$Location), ]
  expect_true(nrow(um_western) > 0)
  expect_true(all(um_western$Institution == "University of Montana Western"))

  # A real remote/out-of-state posting with no MT branch-campus address
  # (confirmed live, a research-center field position) falls back to
  # University of Montana, the umbrella board owner -- not misattributed
  # to any branch campus.
  remote <- result[grepl("St. Clair County, IL", result$Location), ]
  expect_true(nrow(remote) > 0)
  expect_true(all(remote$Institution == "University of Montana"))

  # Session query params (visitor/session) are stripped -- confirmed live
  # that reusing another session's params 500s, while the bare URL 200s.
  expect_false(grepl("[?&]", result$Link[1]))
  expect_true(grepl("^https://www\\.schooljobs\\.com/careers/ummissoula/jobs/", result$Link[1]))
  # No posted-date field exists anywhere in the real fragment -- a genuine
  # absence, same pattern as JazzHR/Paycom's missing Posted_Date.
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("neogov_location_to_institution maps each real branch-campus address, falling back otherwise", {
  expect_equal(neogov_location_to_institution("1205 E Broadway St, Missoula, MT 59802, USA", "University of Montana"), "Missoula College")
  expect_equal(neogov_location_to_institution("1115 N Roberts St, Helena, MT 59601, USA", "University of Montana"), "Helena College")
  expect_equal(neogov_location_to_institution("2300 Airport Rd, Helena, MT 59601, USA", "University of Montana"), "Helena College")
  expect_equal(neogov_location_to_institution("710 S Atlantic St, Dillon, MT 59725, USA", "University of Montana"), "University of Montana Western")
  expect_equal(neogov_location_to_institution("32 Campus Dr, Missoula, MT 59801, USA", "University of Montana"), "University of Montana")
  expect_equal(neogov_location_to_institution("St. Clair County, IL, USA", "University of Montana"), "University of Montana")
})

test_that("parse_neogov_postings returns zero rows (not an error) for a genuinely empty board", {
  empty_fragment <- '<div class="wrapper__body"></div>'

  result <- parse_neogov_postings(empty_fragment, "University of Montana")

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link", "Institution"))
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
