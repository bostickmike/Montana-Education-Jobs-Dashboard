# scrape_with_mac_fallback() / read_mac_snapshot() (scrape_helpers.R): a source
# GitHub's servers can't reach (Arrowhead #75) uses the Mac's copy from the
# mac-sources branch only when the live fetch fails and the copy is fresh.
# Fixture: the real first copy the Mac job wrote, 2026-11-10T01:35:17Z.
source(test_path("..", "..", "scrape_helpers.R"))

snap_dir <- test_path("fixtures", "mac_sources_2026-11-10")
fetched <- as.POSIXct("2026-11-10 01:35:17", tz = "UTC")
cols <- c("Title", "Location", "Posted_Date", "Link")
http_403 <- function() stop("HTTP 403 Forbidden.")
read_log <- function(path) utils::read.csv(path, stringsAsFactors = FALSE)

test_that("a working live fetch is used as is, and the Mac copy is ignored", {
  log <- tempfile()
  live <- data.frame(Title = "Live Posting", Location = "Pray", Posted_Date = NA, Link = "u")
  result <- scrape_with_mac_fallback("Arrowhead", function() live, "arrowhead", cols,
                                     snapshot_dir = snap_dir, log_path = log, now = fetched)
  expect_equal(result$Title, "Live Posting")
  l <- read_log(log)
  expect_equal(l$status, "ok")
  expect_true(is.na(l$error_message))
})

test_that("a failed live fetch uses a fresh Mac copy and the log says so", {
  log <- tempfile()
  result <- scrape_with_mac_fallback("Arrowhead", http_403, "arrowhead", cols,
                                     snapshot_dir = snap_dir, log_path = log, now = fetched + 3 * 86400)
  expect_equal(result$Title, c("Substitute Employment", "Special Education Paraprofessional", "Certified Teachers"))
  expect_equal(names(result), cols)
  l <- read_log(log)
  expect_equal(nrow(l), 1)
  expect_equal(l$status, "ok")
  expect_equal(l$n_rows, 3)
  expect_match(l$error_message, "HTTP 403.*Mac copy fetched 2026-11-10T01:35:17Z")
})

test_that("the Mac copy gives the same rows as the live parser (posting identity stays the same)", {
  html <- paste(readLines(test_path("fixtures", "arrowhead_careers.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  source(test_path("..", "..", "misc_district_scrapers.R"))
  live <- parse_arrowhead_postings(html, "https://arrowheadk8.com/careers/")
  snap <- read_mac_snapshot("arrowhead", snap_dir, now = fetched)$df
  expect_equal(snap$Title, live$Title)
  expect_equal(snap$Location, live$Location)
  expect_true(all(is.na(snap$Posted_Date)) && all(is.na(live$Posted_Date)))
})

test_that("a Mac copy older than the limit is not used", {
  log <- tempfile()
  result <- scrape_with_mac_fallback("Arrowhead", http_403, "arrowhead", cols,
                                     snapshot_dir = snap_dir, log_path = log,
                                     now = fetched + (MAC_SNAPSHOT_MAX_AGE_DAYS + 1) * 86400)
  expect_equal(nrow(result), 0)
  l <- read_log(log)
  expect_equal(l$status, "error")
  expect_match(l$error_message, "HTTP 403.*Mac copy too old")
})

test_that("no Mac copy, or one whose row count disagrees with its manifest, is an error", {
  log <- tempfile()
  expect_equal(nrow(scrape_with_mac_fallback("Arrowhead", http_403, "arrowhead", cols,
                                             snapshot_dir = tempfile(), log_path = log, now = fetched)), 0)
  expect_match(read_log(log)$error_message, "no Mac copy")

  bad <- tempfile(); dir.create(bad)
  file.copy(file.path(snap_dir, "manifest.csv"), bad)
  rows <- utils::read.csv(file.path(snap_dir, "arrowhead.csv"))
  utils::write.csv(rows[1:2, ], file.path(bad, "arrowhead.csv"), row.names = FALSE)
  expect_match(read_mac_snapshot("arrowhead", bad, now = fetched)$problem, "incomplete")
})
