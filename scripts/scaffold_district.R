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
cms <- get_arg("cms")
leaid <- get_arg("leaid")

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
  cat("    [--platform \"<Slug>Heuristic\"] \\\n")
  cat("    [--cms \"<weebly|wordpress|edlio|google_sites|generic>\"]\n")
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

# Determine CMS template
fixture_file <- here::here("tests", "testthat", "fixtures", paste0(slug, "_jobs.html"))
if (is.null(cms)) {
  if (file.exists(fixture_file)) {
    fix_txt <- paste(readLines(fixture_file, warn = FALSE), collapse = " ")
    if (grepl("wsite-content|weebly\\.com", fix_txt, ignore.case = TRUE)) {
      cms <- "weebly"
    } else if (grepl("wp-content|wp-includes|\\bdivi\\b", fix_txt, ignore.case = TRUE)) {
      cms <- "wordpress"
    } else if (grepl("cyberschool|cs2\\.chat|District/Jobs", fix_txt, ignore.case = TRUE)) {
      cms <- "cyberschool"
    } else if (grepl("edliocdn|uREC_ID=|/apps/jobs/|show_job\\.jsp", fix_txt, ignore.case = TRUE)) {
      cms <- "edlio"
    } else if (grepl("sites\\.google\\.com|sites-layout-tile", fix_txt, ignore.case = TRUE)) {
      cms <- "google_sites"
    } else {
      cms <- "generic"
    }
    cat(sprintf("CMS:      %s (auto-detected from fixture)\n", cms))
  } else {
    cms <- "generic"
    cat(sprintf("CMS:      %s (default)\n", cms))
  }
} else {
  cms <- tolower(cms)
  cat(sprintf("CMS:      %s (specified)\n", cms))
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
old_count <- nrow(existing_reg)
new_count <- old_count

if (district %in% existing_reg$District) {
  cat(sprintf("[1/8] District '%s' already exists in k12_district_registry.csv\n", district))
} else {
  new_count <- old_count + 1
  leaid_val <- if (!is.null(leaid) && nzchar(leaid)) leaid else ""
  new_reg_row <- sprintf('"%s",%s,"%s","%s",%s,%s,"%s","","%s"',
                         district, leaid_val, city, county, lat, lon, platform, url)
  # Append row
  writeLines(c(reg_lines, new_reg_row), reg_path)
  cat(sprintf("[1/8] Updated k12_district_registry.csv (+1 row, total %d)\n", new_count))
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
  cat(sprintf("[2/8] Updated .github/copilot-allowlist.txt (added %s)\n", url_host))
} else {
  cat(sprintf("[2/8] Host %s already covered in .github/copilot-allowlist.txt\n", url_host))
}

# ---------------------------------------------------------------------------
# 3. tests/testthat/test-salary-scrapers.R
# ---------------------------------------------------------------------------
sal_path <- here::here("tests", "testthat", "test-salary-scrapers.R")
sal_content <- paste(readLines(sal_path, warn = FALSE), collapse = "\n")

if (grepl(sprintf('"%s"', district), sal_content, fixed = TRUE)) {
  cat("[3/8] District already present in test-salary-scrapers.R\n")
} else {
  # Match the last quoted district inside the unmapped setdiff expect_setequal block
  pattern <- '("[^"]+")\\)\\)\\s*\\n\\}\\)'
  if (grepl(pattern, sal_content)) {
    replacement <- sprintf('\\1,\n                     "%s"))\n})', district)
    sal_content <- sub(pattern, replacement, sal_content)
    writeLines(sal_content, sal_path)
    cat(sprintf("[3/8] Updated test-salary-scrapers.R (added '%s' to unmapped setdiff)\n", district))
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
  cat(sprintf("[4/8] District slug '%s' already wired in Mt_ED_Jobs.Rmd\n", slug))
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
  %s_df <- %s_df %%>%%
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
  date_line <- sprintf("%s_df <- %s_df %%>%% mutate(date_posted = standardize_date(date_posted))\napptegy_df <- apptegy_df", slug, slug)
  rmd_content <- sub("apptegy_df <- apptegy_df %>% mutate(date_posted = standardize_date(date_posted))",
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
  cat("[4/8] Updated Mt_ED_Jobs.Rmd (scraper block, standardize_date, direct_df)\n")
}

# ---------------------------------------------------------------------------
# 5. misc_district_scrapers.R
# ---------------------------------------------------------------------------
misc_path <- here::here("misc_district_scrapers.R")
misc_content <- paste(readLines(misc_path, warn = FALSE), collapse = "\n")

if (grepl(sprintf("fetch_%s_postings", slug), misc_content, fixed = TRUE)) {
  cat(sprintf("[5/8] fetch_%s_postings already exists in misc_district_scrapers.R\n", slug))
} else {
  parser_body <- if (cms == "weebly") {
    sprintf('parse_%s_postings <- function(html, url) {
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

  content <- html_element(doc, "#wsite-content")
  if (is.null(content)) return(empty)

  elements <- html_elements(content, "h2.wsite-content-title, .wsite-content-title, .paragraph, p, li")
  if (length(elements) == 0) return(empty)

  raw_texts <- trimws(html_text2(elements))
  raw_texts <- raw_texts[nzchar(raw_texts)]

  clean_titles <- raw_texts[!grepl("^(Employment Opportunities|Certified Salary|Click here|Classified Personnel|Certified Personnel|Coaching Personnel|NOTE:|No opening|Equal Opportunity|Application Form)", raw_texts, ignore.case = TRUE) &
                            grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position|substitute", raw_texts, ignore.case = TRUE)]

  if (length(clean_titles) == 0) return(empty)

  df <- data.frame(
    Title = clean_titles,
    Location = rep("%s", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(url, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}', slug, city)
  } else if (cms == "wordpress") {
    sprintf('parse_%s_postings <- function(html, url) {
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

  content <- html_elements(doc, ".entry-content, article, #main-content, main")
  if (length(content) == 0) content <- doc

  elements <- html_elements(content, "h1, h2, h3, h4, li, a, p")
  texts <- trimws(html_text2(elements))
  texts <- texts[nzchar(texts)]

  clean_titles <- texts[!grepl("^(Available Employment Opportunities|Employment Opportunities|Job Opportunities|Application Form|Staff Application|ADA Web Accessibility|Click here|Download)", texts, ignore.case = TRUE) &
                        grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position|substitute|wanted", texts, ignore.case = TRUE)]

  if (length(clean_titles) == 0) return(empty)

  pdf_links <- html_attr(html_elements(content, "a[href*=\\\".pdf\\\"]"), "href")
  link_out <- if (length(pdf_links) > 0 && nzchar(pdf_links[1])) xml2::url_absolute(pdf_links[1], url) else url

  df <- data.frame(
    Title = clean_titles,
    Location = rep("%s", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(link_out, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}', slug, city)
  } else if (cms == "edlio") {
    sprintf('parse_%s_postings <- function(html, url) {
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

  job_links <- html_elements(doc, "a[href*=\\\"show_job.jsp\\\"], a[href*=\\\"/apps/jobs/show_job\\\"], .job-title a, .list-item a")
  if (length(job_links) == 0) return(empty)

  titles <- trimws(html_text2(job_links))
  hrefs <- html_attr(job_links, "href")

  valid_idx <- nzchar(titles) & !grepl("^(Application|Certified Application|Classified Application|Equal Opportunity)", titles, ignore.case = TRUE)
  titles <- titles[valid_idx]
  hrefs <- hrefs[valid_idx]

  if (length(titles) == 0) return(empty)

  df <- data.frame(
    Title = titles,
    Location = rep("%s", length(titles)),
    Posted_Date = rep(NA_character_, length(titles)),
    Link = xml2::url_absolute(hrefs, url),
    stringsAsFactors = FALSE
  )
  unique(df)
}', slug, city)
  } else if (cms == "google_sites") {
    sprintf('parse_%s_postings <- function(html, url) {
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

  content <- html_elements(doc, "[role=\\\"main\\\"], .sites-layout-tile, .sites-tile-name-content-1")
  if (length(content) == 0) content <- doc

  elements <- html_elements(content, "h1, h2, h3, h4, p, li")
  texts <- trimws(html_text2(elements))
  texts <- texts[nzchar(texts)]

  clean_titles <- texts[!grepl("^(Employment Opportunities|Job Openings|Office Staff|Contact Us|Home|Download|Application)", texts, ignore.case = TRUE) &
                        grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position|substitute", texts, ignore.case = TRUE)]

  if (length(clean_titles) == 0) return(empty)

  df <- data.frame(
    Title = clean_titles,
    Location = rep("%s", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(url, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}', slug, city)
  } else if (cms == "cyberschool") {
    sprintf('parse_%s_postings <- function(html, url) {
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

  container <- html_elements(doc, ".listItem_bodyContent, #maincontent, .cs-html-widget, main, #content")
  if (length(container) == 0) container <- doc

  elements <- html_elements(container, "li, p, .listItem_holder, strong, h2, h3, h4")
  if (length(elements) == 0) return(empty)

  raw_titles <- trimws(html_text2(elements))
  raw_titles <- raw_titles[nzchar(raw_titles)]

  exclude_patterns <- "^(Applications?|Click Here|Download|None|Equal Opportunity|Back to|Current Jobs|Archive Jobs|View Jobs|Site Map|Skip To|Share|Alert|Login|Subscribe|Views)"
  clean_titles <- raw_titles[!grepl(exclude_patterns, raw_titles, ignore.case = TRUE) &
                             grepl("teacher|aide|driver|custodian|coach|specialist|para|clerk|opening|position|substitute|kitchen", raw_titles, ignore.case = TRUE)]
  clean_titles <- clean_titles[nchar(clean_titles) < 90]

  if (length(clean_titles) == 0) return(empty)

  df <- data.frame(
    Title = clean_titles,
    Location = rep("%s", length(clean_titles)),
    Posted_Date = rep(NA_character_, length(clean_titles)),
    Link = rep(url, length(clean_titles)),
    stringsAsFactors = FALSE
  )
  unique(df)
}', slug, city)
  } else {
    sprintf('parse_%s_postings <- function(html, url) {
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
}', slug)
  }

  scraper_scaffold <- sprintf('
# ---------------------------------------------------------------------------
# %s
# ---------------------------------------------------------------------------
fetch_%s_postings <- function(url) {
  resp <- request(url) %%>%%
    req_headers("User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36") %%>%%
    perform_with_retry()
  html <- resp_body_string(resp)
  parse_%s_postings(html, url)
}

%s
', district, slug, slug, parser_body)

  misc_marker <- "# District-level data-completeness classification"
  if (grepl(misc_marker, misc_content, fixed = TRUE)) {
    misc_content <- sub(misc_marker, paste0(trimws(scraper_scaffold), "\n\n", misc_marker), misc_content, fixed = TRUE)
    writeLines(misc_content, misc_path)
    cat(sprintf("[5/8] Updated misc_district_scrapers.R (added %s fetch_%s_postings and parse_%s_postings)\n", cms, slug, slug))
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
  cat(sprintf("[6/8] parse_%s_postings test already exists in test-misc-district-scrapers.R\n", slug))
} else {
  test_scaffold <- sprintf('
test_that("parse_%s_postings extracts real positions or returns empty cleanly", {
  fixture <- paste(readLines(test_path("fixtures", "%s_jobs.html"), warn = FALSE, encoding = "UTF-8"), collapse = "\\n")
  url <- "%s"

  result <- parse_%s_postings(fixture, url)

  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  if (nrow(result) > 0) {
    expect_true(all(result$Location == "%s"))
    expect_true(all(is.na(result$Posted_Date) | nzchar(result$Posted_Date)))
    expect_true(all(nzchar(result$Link)))
  }
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
    cat(sprintf("[6/8] Updated test-misc-district-scrapers.R (added unit test templates for parse_%s_postings)\n", slug))
  } else {
    cat("[WARNING] Could not find test marker in test-misc-district-scrapers.R\n")
  }
}

# ---------------------------------------------------------------------------
# 7. README.md & DATA_COOKBOOK.md (District count sync)
# ---------------------------------------------------------------------------
if (new_count > old_count) {
  readme_path <- here::here("README.md")
  if (file.exists(readme_path)) {
    rm_content <- paste(readLines(readme_path, warn = FALSE), collapse = "\n")
    rm_content <- gsub(sprintf("K-12 covers %d directly-scraped districts", old_count),
                       sprintf("K-12 covers %d directly-scraped districts", new_count),
                       rm_content)
    writeLines(rm_content, readme_path)
    cat(sprintf("[7/8] Updated README.md (count %d -> %d)\n", old_count, new_count))
  }

  cookbook_path <- here::here("DATA_COOKBOOK.md")
  if (file.exists(cookbook_path)) {
    cb_content <- paste(readLines(cookbook_path, warn = FALSE), collapse = "\n")
    cb_content <- gsub(sprintf("scraping scope (%d K-12 districts", old_count),
                       sprintf("scraping scope (%d K-12 districts", new_count),
                       cb_content, fixed = TRUE)
    cb_content <- gsub(sprintf("Within that %d/23 scope", old_count),
                       sprintf("Within that %d/23 scope", new_count),
                       cb_content, fixed = TRUE)
    cb_content <- gsub(sprintf("cover 32 of the %d K-12 districts", old_count),
                       sprintf("cover 32 of the %d K-12 districts", new_count),
                       cb_content, fixed = TRUE)
    writeLines(cb_content, cookbook_path)
    cat(sprintf("[8/8] Updated DATA_COOKBOOK.md (count %d -> %d)\n", old_count, new_count))
  }
} else {
  cat("[7/8] README.md already at current count\n")
  cat("[8/8] DATA_COOKBOOK.md already at current count\n")
}

cat("\n=== Scaffolding Complete! ===\n")
cat(sprintf("Next step: Implement parser selector logic in parse_%s_postings() in misc_district_scrapers.R\n", slug))
