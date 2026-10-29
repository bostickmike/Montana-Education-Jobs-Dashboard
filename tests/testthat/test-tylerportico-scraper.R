test_that("parse_tylerportico_positions extracts real Kalispell posting fields, falling back to institution_name for location", {
  # Real fixture captured 2026-08-06 from
  # https://kalispellpublicschoolsmt.tylerportico.com/tess/citizen/api/Positions
  # (Kalispell Public Schools, SD5) -- description/additionalDescriptions/
  # descriptionDocument fields stripped to keep the fixture readable, since
  # parse_tylerportico_positions doesn't read them; every field the parser
  # does use (id, title, postingStartDate, locationDescription) is untouched
  # real data.
  fixture <- paste(readLines(test_path("fixtures", "tylerportico_kalispell.json"), warn = FALSE), collapse = "\n")

  result <- parse_tylerportico_positions(
    fixture,
    institution_name = "Kalispell Public Schools",
    base_url = "https://kalispellpublicschoolsmt.tylerportico.com/tess/citizen"
  )

  expect_equal(nrow(result), 49)
  expect_equal(result$Title[1:3], c("BUS - DRIVER", "BUS MONITOR", "CENTRAL OFFICE STUDENT INTERN"))
  expect_equal(result$Posted_Date[1:3], c("2026-06-29", "2025-07-30", "2026-08-06"))
  # Every real posting checked live has locationDescription: null -- confirms
  # the fallback fires for all of them here too, not just in a synthetic case.
  expect_true(all(result$Location == "Kalispell Public Schools"))
  # Link reconstruction confirmed live via chromote: clicking the "BUS -
  # DRIVER" row in the real Angular app navigated to exactly this URL.
  expect_equal(result$Link[1], "https://kalispellpublicschoolsmt.tylerportico.com/tess/citizen/jobs/job-list/a76ba87a-ff37-4194-9f9d-b47800b87221")
})

test_that("parse_tylerportico_positions prefers a real locationDescription over institution_name when present", {
  json_with_location <- '[{"id":"abc-123","title":"Some Position","postingStartDate":"2026-01-15T00:00:00","postingEndDate":null,"locationDescription":"Glacier High School"}]'

  result <- parse_tylerportico_positions(
    json_with_location,
    institution_name = "Kalispell Public Schools",
    base_url = "https://kalispellpublicschoolsmt.tylerportico.com/tess/citizen"
  )

  expect_equal(result$Location, "Glacier High School")
})

test_that("parse_tylerportico_positions returns zero rows (not an error) for an empty postings array", {
  result <- parse_tylerportico_positions(
    "[]",
    institution_name = "Kalispell Public Schools",
    base_url = "https://kalispellpublicschoolsmt.tylerportico.com/tess/citizen"
  )

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_tylerportico_postings fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "tylerportico_kalispell.json"), warn = FALSE), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "application/json; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_tylerportico_postings("kalispellpublicschoolsmt", "Kalispell Public Schools")

  expect_equal(nrow(result), 49)
  expect_equal(result$Title[1], "BUS - DRIVER")
})

test_that("fetch_tylerportico_postings works for migrated districts (Bozeman, Polson)", {
  fixture <- '[{"id":"pos-1","title":"Teacher","postingStartDate":"2026-10-01T00:00:00","postingEndDate":null,"locationDescription":"High School"}]'
  httr2::local_mocked_responses(
    list(
      httr2::response(200, headers = list("Content-Type" = "application/json; charset=utf-8"), body = charToRaw(fixture)),
      httr2::response(200, headers = list("Content-Type" = "application/json; charset=utf-8"), body = charToRaw(fixture))
    )
  )

  res_bozeman <- fetch_tylerportico_postings("bozemanschooldistrict7mt", "Bozeman Public Schools")
  expect_equal(nrow(res_bozeman), 1)
  expect_equal(res_bozeman$Title, "Teacher")
  expect_equal(res_bozeman$Link, "https://bozemanschooldistrict7mt.tylerportico.com/tess/citizen/jobs/job-list/pos-1")

  res_polson <- fetch_tylerportico_postings("polsonschooldistrict23mt", "Polson School District")
  expect_equal(nrow(res_polson), 1)
  expect_equal(res_polson$Title, "Teacher")
  expect_equal(res_polson$Link, "https://polsonschooldistrict23mt.tylerportico.com/tess/citizen/jobs/job-list/pos-1")
})
