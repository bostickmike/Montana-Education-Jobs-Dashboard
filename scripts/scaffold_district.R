#!/usr/bin/env Rscript
# scripts/scaffold_district.R
# Automates the boilerplate file edits across 6 coupled files for adopting a new
# heuristic district:
#   1. k12_district_registry.csv (adds registry row, checks for duplicates)
#   2. .github/copilot-allowlist.txt (adds domain and sorts alphabetically)
#   3. tests/testthat/test-salary-scrapers.R (adds district to unmapped setdiff)
#   4. Mt_ED_Jobs.Rmd (adds safe_scrape block, standardize_date, and bind_rows entry)
#   5. misc_district_scrapers.R (adds skeleton fetch_* and parse_* functions)
#   6. tests/testthat/test-misc-district-scrapers.R (adds unit test skeleton)
#
# Usage:
#   Rscript scripts/scaffold_district.R \
#     --district "District Name" \
#     --city "City" \
#     --county "County Name" \
#     --lat 48.1234 \
#     --lon -114.5678 \
#     --url "https://example.com/jobs" \
#     --slug "districtslug" \
#     [--platform "CustomHeuristic"]

suppressMessages({
  library(here)
})

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(key, default = NULL) {
  idx <- which(args == paste0("--", key))
  if (length(idx) == 1 && length(args) > idx) args[idx + 1] else default
}

district <- get_arg("district")
city <- get_arg("city")
county <- get_arg("county")
lat <- get_arg("lat")
lon <- get_arg("lon")
url <- get_arg("url")
slug <- get_arg("slug")
platform <- get_arg("platform")

if (is.null(district) || is.null(city) || is.null(county) || is.null(lat) || is.null(lon) || is.null(url) || is.null(slug)) {
  cat("Error: Missing required arguments.\n\n")
  cat("Usage:\n")
  cat("  Rscript scripts/scaffold_district.R \\\n")
  cat("    --district \"District Name\" \\\n")
  cat("    --city \"City\" \\\n")
  cat("    --county \"County Name\" \\\n")
  cat("    --lat <numeric> \\\n")
  cat("    --lon <numeric> \\\n")
  cat("    --url \"<Job_Link>\" \\\n")
  cat("    --slug \"<slug>\" \\\n")
  cat("    [--platform \"<Slug>Heuristic\"]\n")
  quit(status = 1)
}

# Clean slug
slug <- tolower(gsub("[^a-zA-Z0-9_]", "", slug))

# Default platform name if not provided
if (is.null(platform)) {
  # Capitalize words in slug
  cap_slug <- paste0(toupper(substr(slug, 1, 1)), substr(slug, 2, nchar(slug)))
  platform <- paste0(cap_slug, "Heuristic")
}

cat(sprintf("=== Scaffolding District: %s ===\n", district))
cat(sprintf("Slug:     %s\n", slug))
cat(sprintf("Platform: %s\n", platform))
cat(sprintf("City:     %s, %s\n", city, county))
cat(sprintf("Lat/Lon:  %s, %s\n", lat, lon))
cat(sprintf("Job Link: %s\n\n", url))

# ---------------------------------------------------------------------------
# 1. k12_district_registry.csv
# ---------------------------------------------------------------------------
reg_path <- here::here("k12_district_registry.csv")
reg_lines <- readLines(reg_path, warn = FALSE)
existing_reg <- read.csv(reg_path, stringsAsFactors = FALSE)

if (district %in% existing_reg$District) {
  cat(sprintf("[1/6] District '%s' already exists in k12_district_registry.csv\n", district))
} else {
  new_reg_row <- sprintf('"%s","%s","%s",%s,%s,"%s","","%s"',
                         district, city, county, lat, lon, platform, url)
  # Append row
  writeLines(c(reg_lines, new_reg_row), reg_path)
  cat(sprintf("[1/6] Updated k12_district_registry.csv (+1 row, total %d)\n", nrow(existing_reg) + 1))
}

# ---------------------------------------------------------------------------
# 2. .github/copilot-allowlist.txt
# ---------------------------------------------------------------------------
allow_path <- here::here(".github", "copilot-allowlist.txt")
allow_lines <- readLines(allow_path, warn = FALSE)

url_host <- tolower(sub("^https?://([^/:?#]+).*$", "\\1", url))
url_host <- sub("^www\\.", "", url_host)

# Check if covered
covered <- any(sapply(allow_lines, function(al) {
  al == url_host || (nzchar(al) && !startsWith(al, "#") && endsWith(url_host, paste0(".", al)))
}))

if (!covered) {
  clean_lines <- allow_lines[nzchar(trimws(allow_lines)) & !startsWith(trimws(allow_lines), "#")]
  updated_allow <- sort(unique(c(clean_lines, url_host)))
  writeLines(updated_allow, allow_path)
  cat(sprintf("[2/6] Updated .github/copilot-allowlist.txt (added %s)\n", url_host))
} else {
  cat(sprintf("[2/6] Host %s already covered in .github/copilot-allowlist.txt\n", url_host))
}

# ---------------------------------------------------------------------------
# 3. tests/testthat/test-salary-scrapers.R
# ---------------------------------------------------------------------------
sal_path <- here::here("tests", "testthat", "test-salary-scrapers.R")
sal_content <- paste(readLines(sal_path, warn = FALSE), collapse = "\n")

if (grepl(sprintf('"%s"', district), sal_content, fixed = TRUE)) {
  cat("[3/6] District already present in test-salary-scrapers.R\n")
} else {
  # Match the last quoted district inside the unmapped setdiff expect_setequal block
  pattern <- '("[^"]+")\\)\\)\\s*\\n\\}\\)'
  if (grepl(pattern, sal_content)) {
    replacement <- sprintf('\\1,\n                     "%s"))\n})', district)
    sal_content <- sub(pattern, replacement, sal_content)
    writeLines(sal_content, sal_path)
    cat(sprintf("[3/6] Updated test-salary-scrapers.R (added '%s' to unmapped setdiff)\n", district))
  } else {
    cat("[WARNING] Could not automatically update test-salary-scrapers.R unmapped list. Please add manually.\n")
  }
}

# ---------------------------------------------------------------------------
# 4. Mt_ED_Jobs.Rmd
# ---------------------------------------------------------------------------
rmd_path <- here::here("Mt_ED_Jobs.Rmd")
rmd_content <- paste(readLines(rmd_path, warn = FALSE), collapse = "\n")

if (grepl(sprintf("%s_df <-", slug), rmd_content, fixed = TRUE)) {
  cat(sprintf("[4/6] District slug '%s' already wired in Mt_ED_Jobs.Rmd\n", slug))
} else {
  # A. Insert scraper block right before Lincoln School District block
  scrape_block <- sprintf('
# %s (%s, found %s)
%s_districts <- registry[registry$Platform == "%s", ]
%s_results <- lapply(seq_len(nrow(%s_districts)), function(i) {
  row <- %s_districts[i, ]
  df <- safe_scrape(
    row$District,
    scrape_fn = function() fetch_%s_postings(row$Job_Link),
    expected_cols = c("Title", "Location", "Posted_Date", "Link")
  )
  if (nrow(df) > 0) df$District <- row$District
  df
})
%s_df <- bind_rows(%s_results)
if (nrow(%s_df) > 0) {
  %s_df <- %s_df %%%%
    transmute(title = Title, date_posted = Posted_Date, position = NA_character_,
              location = Location, url = Link, District,
              Posting_Source = "%s site (direct board)")
} else {
  %s_df <- data.frame(title = character(0), date_posted = character(0), position = character(0),
                      location = character(0), url = character(0), District = character(0),
                      Posting_Source = character(0))
}
', district, url_host, Sys.Date(),
     slug, platform,
     slug, slug,
     slug,
     slug,
     slug, slug,
     slug,
     slug, slug,
     district,
     slug)

  lincoln_marker <- "# Lincoln School District #38"
  if (grepl(lincoln_marker, rmd_content, fixed = TRUE)) {
    rmd_content <- sub(lincoln_marker, paste0(trimws(scrape_block), "\n\n", lincoln_marker), rmd_content, fixed = TRUE)
  } else {
    cat("[WARNING] Could not find Lincoln School District marker in Mt_ED_Jobs.Rmd\n")
  }

  # B. Insert date standardization line
  date_line <- sprintf("%s_df <- %s_df %%%% mutate(date_posted = standardize_date(date_posted))\napptegy_df <- apptegy_df", slug, slug)
  rmd_content <- sub("apptegy_df <- apptegy_df %%%% mutate(date_posted = standardize_date(date_posted))",
                     date_line, rmd_content, fixed = TRUE)

  # C. Insert into direct_df bind_rows
  # Insert before swanriver_df,
  bind_marker <- "swanriver_df,"
  if (grepl(bind_marker, rmd_content, fixed = TRUE)) {
    rmd_content <- sub(bind_marker, sprintf("%s_df,\n                       %s", slug, bind_marker), rmd_content, fixed = TRUE)
  } else {
    cat("[WARNING] Could not find swanriver_df in Mt_ED_Jobs.Rmd direct_df bind_rows\n")
  }

  writeLines(rmd_content, rmd_path)
  cat("[4/6] Updated Mt_ED_Jobs.Rmd (scraper block, standardize_date, direct_df)\n")
}

# ---------------------------------------------------------------------------
# 5. misc_district_scrapers.R
# ---------------------------------------------------------------------------
misc_path <- here::here("misc_district_scrapers.R")
misc_content <- paste(readLines(misc_path, warn = FALSE), collapse = "\n")

if (grepl(sprintf("fetch_%s_postings", slug), misc_content, fixed = TRUE)) {
  cat(sprintf("[5/6] fetch_%s_postings already exists in misc_district_scrapers.R\n", slug))
} else {
  scraper_scaffold <- sprintf('
# ---------------------------------------------------------------------------
# %s
# ---------------------------------------------------------------------------
fetch_%s_postings <- function(url) {
  resp <- request(url) %%%%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %%%%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_%s_postings(html, url)
}

parse_%s_postings <- function(html, url) {
  empty <- data.frame(
    Title = character(0),
    Location = character(0),
    Posted_Date = character(0),
    Link = character(0),
    stringsAsFactors = FALSE
  )
  if (!nzchar(html)) return(empty)

  doc <- tryCatch(read_html(html), error = function(e) NULL)
  if (is.null(doc)) return(empty)

  # TODO: Implement selector logic
  empty
}
', district, slug, slug, slug)

  misc_marker <- "# District-level data-completeness classification"
  if (grepl(misc_marker, misc_content, fixed = TRUE)) {
    misc_content <- sub(misc_marker, paste0(trimws(scraper_scaffold), "\n\n", misc_marker), misc_content, fixed = TRUE)
    writeLines(misc_content, misc_path)
    cat(sprintf("[5/6] Updated misc_district_scrapers.R (added skeleton fetch_%s_postings and parse_%s_postings)\n", slug, slug))
  } else {
    cat("[WARNING] Could not find tier classification marker in misc_district_scrapers.R\n")
  }
}

# ---------------------------------------------------------------------------
# 6. tests/testthat/test-misc-district-scrapers.R
# ---------------------------------------------------------------------------
test_path <- here::here("tests", "testthat", "test-misc-district-scrapers.R")
test_content <- paste(readLines(test_path, warn = FALSE), collapse = "\n")

if (grepl(sprintf("parse_%s_postings", slug), test_content, fixed = TRUE)) {
  cat(sprintf("[6/6] parse_%s_postings test already exists in test-misc-district-scrapers.R\n", slug))
} else {
  test_scaffold <- sprintf('
test_that("parse_%s_postings extracts real positions from captured fixture", {
  fixture <- paste(readLines(test_path("fixtures", "%s_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\\n")
  url <- "%s"

  result <- parse_%s_postings(fixture, url)

  expect_true(nrow(result) > 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_true(all(result$Location == "%s"))
  expect_true(all(is.na(result$Posted_Date)))
})

test_that("parse_%s_postings returns zero rows on empty or non-matching HTML", {
  result <- parse_%s_postings("<html><body><p>No jobs</p></body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
})
', slug, slug, url, slug, city, slug, slug)

  test_marker <- 'test_that("k12_district_coverage_tiers labels non-direct-API-platform districts'
  if (grepl(test_marker, test_content, fixed = TRUE)) {
    test_content <- sub(test_marker, paste0(trimws(test_scaffold), "\n\n", test_marker), test_content, fixed = TRUE)
    writeLines(test_content, test_path)
    cat(sprintf("[6/6] Updated test-misc-district-scrapers.R (added unit test templates for parse_%s_postings)\n", slug))
  } else {
    cat("[WARNING] Could not find test marker in test-misc-district-scrapers.R\n")
  }
}

cat("\n=== Scaffolding Complete! ===\n")
cat(sprintf("Next step: Implement parser selector logic in parse_%s_postings() in misc_district_scrapers.R\n", slug))
