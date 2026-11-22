# University of Montana's faculty jobs on Interfolio (direct_api_scrapers.R).
# Real fixture captured 2026-11-21 from
# https://logic.interfolio.com/byc-search/53871/public_job_boards?page=1
# (unaltered: all 19 open positions, total_count 19).

interfolio_fixture <- function() {
  paste(readLines(test_path("fixtures", "interfolio_um_2026-11-21.json"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}
# The real response split into pages, or with its total changed: for paging.
interfolio_page <- function(rows, total = NULL) {
  j <- jsonlite::fromJSON(interfolio_fixture(), simplifyVector = FALSE)
  j$results <- j$results[rows]
  if (!is.null(total)) j$total_count <- total
  httr2::response(200, headers = list("Content-Type" = "application/json"),
                  body = charToRaw(as.character(jsonlite::toJSON(j, auto_unbox = TRUE, null = "null"))))
}

test_that("parse_interfolio_postings reads every real UM faculty position", {
  r <- parse_interfolio_postings(interfolio_fixture())
  expect_equal(nrow(r), 19)
  expect_equal(names(r), c("Title", "Location", "Posted_Date", "Link", "Close_Date", "Unit", POSTED_PAY_COLUMNS))
  mis <- r[r$Link == "https://apply.interfolio.com/196348", ]
  expect_equal(mis$Title, "Assistant Professor of Management Information Systems, College of Business")
  expect_equal(mis$Location, "Missoula, MT")
  expect_equal(mis$Posted_Date, "2026-11-13")
  expect_equal(mis$Close_Date, "2027-01-19")
  expect_equal(mis$Unit, "Management Information Systems")
  expect_equal(c(mis$Pay_Min, mis$Pay_Max), c(120000, 130000))
  expect_equal(mis$Pay_Unit, "year")
  # No close date: NA, not "".
  expect_true(is.na(r$Close_Date[r$Link == "https://apply.interfolio.com/193510"]))
  # "Montana, United States" -> "Montana"; the bio station keeps its name (he_campus_departments.csv places it).
  expect_true("Montana" %in% r$Location)
  expect_true("Flathead Lake Biological Station" %in% r$Location)
  # The bio station's "$1M Jessie Bierman endowment" is not its director's pay.
  expect_true(is.na(r$Pay_Min[r$Location == "Flathead Lake Biological Station"]))
  expect_false(anyNA(r$Title) || anyNA(r$Posted_Date) || anyDuplicated(r$Link) > 0)
})

test_that("parse_interfolio_postings returns zero rows (not an error) for an empty board", {
  r <- parse_interfolio_postings('{"limit":25,"page":1,"total_count":0,"results":[]}')
  expect_equal(nrow(r), 0)
  expect_equal(names(r), c("Title", "Location", "Posted_Date", "Link", "Close_Date", "Unit", POSTED_PAY_COLUMNS))
})

test_that("fetch_interfolio_postings reads one page when it holds the whole board", {
  httr2::local_mocked_responses(list(interfolio_page(1:19)))
  expect_equal(nrow(fetch_interfolio_postings("53871")), 19)
})

test_that("fetch_interfolio_postings pages until it has total_count positions", {
  httr2::local_mocked_responses(list(interfolio_page(1:10), interfolio_page(11:19)))
  r <- fetch_interfolio_postings("53871")
  expect_equal(nrow(r), 19)
  expect_equal(anyDuplicated(r$Link), 0)
})

test_that("fetch_interfolio_postings fails on a short read instead of returning part of the board", {
  # total_count says 25; the next page comes back empty.
  httr2::local_mocked_responses(list(interfolio_page(1:19, total = 25), interfolio_page(integer(0), total = 25)))
  expect_error(fetch_interfolio_postings("53871"), "read 19 of 25 positions")
})

test_that("a faculty posting whose unit is a UM-board campus goes to that institution", {
  r <- parse_interfolio_postings(interfolio_fixture())
  r$Unit[1] <- "Missoula College"            # as a Missoula College search would carry it
  r$Unit[2] <- "Helena College"
  r$Institution <- "University of Montana"
  he <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
  out <- assign_shared_board_institutions(r, "ummissoula", he, location_col = "Unit")
  expect_equal(out$Institution[1:3], c("Missoula College", "Helena College", "University of Montana"))
  expect_equal(sum(out$Institution == "University of Montana"), 17)
})
