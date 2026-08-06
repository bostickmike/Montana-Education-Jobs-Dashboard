test_that("parse_peopleadmin_atom extracts real Montana posting fields, preferring author over location_fallback", {
  # Real fixture captured 2026-08-06 from
  # https://jobs.gfcmsu.edu/postings/search.atom (Great Falls College MSU).
  fixture <- paste(readLines(test_path("fixtures", "peopleadmin_atom_mt.xml"), warn = FALSE), collapse = "\n")

  result <- parse_peopleadmin_atom(fixture, location_fallback = "Great Falls College MSU")

  expect_equal(nrow(result), 9)
  expect_equal(result$Title[1:3], c(
    "Early Learning Center Teachers",
    "Director of Workforce Operations",
    "Health Sciences Program Site Coordinator"
  ))
  # Regression: every entry in Montana's PeopleAdmin feeds carries a real
  # <author><name> department -- this should always win over
  # location_fallback, unlike Wyoming's single-campus PeopleAdmin colleges
  # where location_fallback was the only signal available.
  expect_equal(result$Location[1:3], c(
    "Office of Administration & Finance", "CTE/Health Sciences", "Dental Hygiene"
  ))
  expect_true(!any(result$Location == "Great Falls College MSU"))
  expect_equal(result$Posted_Date[1], "2026-08-06")
  expect_equal(result$Link[1], "https://jobs.gfcmsu.edu/postings/2546")
})

test_that("parse_peopleadmin_atom falls back to location_fallback when an entry has no author", {
  xml_no_author <- '<?xml version="1.0" encoding="UTF-8"?>
<feed xml:lang="en-US" xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>https://jobs.example.edu/postings/1</id>
    <published>2026-08-01T00:00:00-06:00</published>
    <link rel="alternate" type="text/html" href="https://jobs.example.edu/postings/1"/>
    <title>Some Position</title>
  </entry>
</feed>'

  result <- parse_peopleadmin_atom(xml_no_author, location_fallback = "Fallback Institution")

  expect_equal(nrow(result), 1)
  expect_equal(result$Location, "Fallback Institution")
})

test_that("parse_peopleadmin_atom returns zero rows (not an error) when the feed has no entries", {
  xml_empty <- '<?xml version="1.0" encoding="UTF-8"?>
<feed xml:lang="en-US" xmlns="http://www.w3.org/2005/Atom">
  <title>Empty Feed</title>
</feed>'

  result <- parse_peopleadmin_atom(xml_empty, location_fallback = "Some Institution")

  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})

test_that("fetch_peopleadmin_atom fetches and parses a live-shaped response", {
  fixture <- paste(readLines(test_path("fixtures", "peopleadmin_atom_mt.xml"), warn = FALSE), collapse = "\n")
  httr2::local_mocked_responses(
    list(httr2::response(200, headers = list("Content-Type" = "application/atom+xml; charset=utf-8"), body = charToRaw(fixture)))
  )

  result <- fetch_peopleadmin_atom("https://jobs.gfcmsu.edu/postings/search.atom", location_fallback = "Great Falls College MSU")

  expect_equal(nrow(result), 9)
  expect_equal(result$Title[1], "Early Learning Center Teachers")
})
