# Keeps .github/copilot-allowlist.txt in sync with every host a scraper
# actually hits. The Copilot cloud agent (scraper auto-fix issues -- see
# drift_check.R's Tier 3) works behind a firewall; a host missing from
# the allowlist means it can't fetch the live page it's been asked to fix.

read_allowlist <- function() {
  lines <- trimws(readLines(here::here(".github", "copilot-allowlist.txt"), warn = FALSE))
  tolower(lines[nzchar(lines) & !startsWith(lines, "#")])
}

url_hosts <- function(urls) {
  urls <- urls[!is.na(urls) & grepl("^https?://", urls)]
  unique(sub("^www[.]", "", tolower(sub("^https?://([^/:?#]+).*$", "\\1", urls))))
}

covered_by <- function(host, allowlist) {
  any(host == allowlist | endsWith(host, paste0(".", allowlist)))
}

test_that("every registry Job_Link/Feed_URL host is on the Copilot allowlist", {
  k12 <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  he <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
  allow <- read_allowlist()
  hosts <- url_hosts(c(k12$Job_Link, he$Job_Link, he$Feed_URL, OPI_STATEWIDE_URL))
  missing <- hosts[!vapply(hosts, covered_by, logical(1), allowlist = allow)]
  expect_equal(missing, character(0),
               info = "add these to .github/copilot-allowlist.txt AND the repo's Copilot firewall settings")
})

test_that("every URL hardcoded in a scraper file is on the Copilot allowlist", {
  files <- here::here(c("direct_api_scrapers.R", "misc_district_scrapers.R", "misc_college_scrapers.R"))
  text <- unlist(lapply(files, readLines, warn = FALSE))
  urls <- unlist(regmatches(text, gregexpr("https?://[A-Za-z0-9.-]+", text)))
  # w3.org only appears in XML namespace strings, never fetched.
  hosts <- setdiff(url_hosts(urls), "w3.org")
  allow <- read_allowlist()
  missing <- hosts[!vapply(hosts, covered_by, logical(1), allowlist = allow)]
  expect_equal(missing, character(0),
               info = "add these to .github/copilot-allowlist.txt AND the repo's Copilot firewall settings")
})

test_that("covered_by matches subdomains but not look-alike suffixes", {
  expect_true(covered_by("bridger.schoolspring.com", "schoolspring.com"))
  expect_true(covered_by("schoolspring.com", "schoolspring.com"))
  expect_false(covered_by("evilschoolspring.com", "schoolspring.com"))
})
