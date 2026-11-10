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
#
# Apptegy districts (--cms apptegy, or auto-detected when
# tests/testthat/fixtures/apptegy_<slug>_pagedata_YYYY-MM-DD.html exists) are
# wired differently: they ride the shared chromote session, so instead of an
# Rmd scrape block and a heuristic fetch, this mode writes
#   - registry Platform "Apptegy";
#   - parse_<slug>_postings()/fetch_<slug>_postings(chromote_session, url)
#     before the shared dispatcher, plus the APPTEGY_DISTRICT_SCRAPERS entry;
#   - the district's name in Mt_ED_Jobs.Rmd's Apptegy safe_scrape() label;
#   - unit tests on the fixture (exact titles the new parser returns), a
#     fake-chromote fetch test, and the district in the
#     fetch_apptegy_k12_postings dispatcher test (fixture, URL routing,
#     total and per-district counts).
# The fixture must be captured first (the rendered outerHTML, AIza keys
# redacted; see the jobs-dash-scraper skill's adopt-new-source.md).
#   --node text   (default) title = bold text of each CONTENT_NODE_TEXT block
#   --node panel  titles = lines of the text block inside each
#                 CONTENT_NODE_PANEL whose heading matches --panel-match
#                 (default "Positions")
#   --label "..." name added to the Rmd's Apptegy label (default --district)

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
  cat("    [--cms \"<weebly|wordpress|edlio|google_sites|cyberschool|apptegy|generic>\"] \\\n")
  cat("    [--node text|panel] [--panel-match \"Positions\"] [--label \"<name>\"]   (apptegy only)\n")
  quit(status = 1)
}

# Clean slug
slug <- tolower(gsub("[^a-zA-Z0-9_]", "", slug))

# Determine CMS template
fixture_file <- here::here("tests", "testthat", "fixtures", paste0(slug, "_jobs.html"))
apptegy_fixtures <- sort(Sys.glob(here::here("tests", "testthat", "fixtures",
                                             paste0("apptegy_", slug, "_pagedata_*.html"))))
if (is.null(cms)) {
  if (length(apptegy_fixtures) > 0) {
    cms <- "apptegy"
    cat(sprintf("CMS:      %s (auto-detected from %s)\n", cms, basename(tail(apptegy_fixtures, 1))))
  } else if (file.exists(fixture_file)) {
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
  known_cms <- c("weebly", "wordpress", "edlio", "google_sites", "cyberschool", "apptegy", "generic")
  if (!cms %in% known_cms) {
    cat(sprintf("Error: unknown --cms \"%s\" (one of: %s).\n", cms, paste(known_cms, collapse = ", ")))
    quit(status = 1)
  }
  cat(sprintf("CMS:      %s (specified)\n", cms))
}
apptegy_mode <- identical(cms, "apptegy")

# Default platform name if not provided
if (is.null(platform)) {
  if (apptegy_mode) {
    platform <- "Apptegy"
  } else {
    cap_slug <- paste0(toupper(substr(slug, 1, 1)), substr(slug, 2, nchar(slug)))
    platform <- paste0(cap_slug, "Heuristic")
  }
}

# ---------------------------------------------------------------------------
# Apptegy mode: checks (before any file is touched) and the code templates
# ---------------------------------------------------------------------------
if (apptegy_mode) {
  if (platform != "Apptegy") {
    cat("Error: --cms apptegy needs registry Platform \"Apptegy\" (the dispatcher cross-check test requires it).\n")
    quit(status = 1)
  }
  apptegy_node <- tolower(get_arg("node", "text"))
  apptegy_panel_match <- get_arg("panel-match", "Positions")
  apptegy_label <- get_arg("label", district)
  if (!apptegy_node %in% c("text", "panel")) {
    cat("Error: --node must be \"text\" or \"panel\".\n")
    quit(status = 1)
  }
  if (length(apptegy_fixtures) == 0) {
    cat(sprintf("Error: no fixture tests/testthat/fixtures/apptegy_%s_pagedata_YYYY-MM-DD.html.\n", slug))
    cat("Capture the rendered page first (chromote: Page$navigate, wait, document.documentElement.outerHTML),\n")
    cat("redact any AIza... key, and save it under that name.\n")
    quit(status = 1)
  }
  apptegy_fixture <- basename(tail(apptegy_fixtures, 1))
  fixture_txt <- paste(readLines(tail(apptegy_fixtures, 1), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (grepl("AIza[0-9A-Za-z_-]{20,}", fixture_txt)) {
    cat(sprintf("Error: %s still holds an AIza... API key; redact it before committing the fixture.\n", apptegy_fixture))
    quit(status = 1)
  }
  cat(sprintf("Node:     %s%s\n", apptegy_node,
              if (apptegy_node == "panel") sprintf(" (panels matching \"%s\")", apptegy_panel_match) else ""))
  cat(sprintf("Fixture:  %s\n", apptegy_fixture))

  # Literal splice: sub()/gsub() would eat the backslashes in the inserted
  # code (its regexes carry \\b), even with fixed = TRUE.
  replace_first <- function(x, old, new) {
    pos <- regexpr(old, x, fixed = TRUE)
    if (pos < 0) return(x)
    paste0(substr(x, 1, pos - 1), new, substr(x, pos + attr(pos, "match.length"), nchar(x)))
  }
  # Fill {{key}} placeholders; values are inserted as written, so string
  # values are passed through dq() first (a deparsed R string literal).
  fill <- function(template, ...) {
    vals <- list(...)
    for (k in names(vals)) {
      key <- paste0("{{", k, "}}")
      while (grepl(key, template, fixed = TRUE)) template <- replace_first(template, key, vals[[k]])
    }
    template
  }
  dq <- function(x) deparse(x)
  url_key <- sub("\\..*$", "", sub("^www\\.", "", tolower(sub("^https?://([^/:?#]+).*$", "\\1", url))))

  apptegy_text_parser <- r"(parse_{{slug}}_postings <- function(html_text, url = {{url}}) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  nodes <- decode_apptegy_pagebuilder_nodes(html_text)
  if (is.null(nodes)) return(empty)

  text_nodes <- find_all_apptegy_nodes(nodes, function(n) {
    !is.null(n$type) && n$type == "CONTENT_NODE_TEXT" && !is.null(n$content$html)
  })
  titles <- unlist(lapply(text_nodes, function(n) {
    frag <- n$content$html
    if (!nzchar(frag)) return(character(0))
    rvest::html_text2(rvest::html_elements(xml2::read_html(paste0("<div>", frag, "</div>")), "strong"))
  }), use.names = FALSE)
  titles <- trimws(gsub("[[:space:]]+", " ", titles))
  titles <- titles[nzchar(titles)]
  # Not postings: application-form labels, instructions, and bold notices a
  # page shows when nothing is open ("No positions are open at this time").
  titles <- titles[!grepl(paste0("application$|^please\\b|^apply\\b|\\bno (current |open )?(openings|positions|vacancies|jobs)\\b|",
                                 "^(deadline|questions|contact|note|closing date)\\b"), titles, ignore.case = TRUE)]
  titles <- unique(titles)
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = {{city}}, Posted_Date = NA_character_,
             Link = url, stringsAsFactors = FALSE)
})"

  apptegy_panel_parser <- r"(parse_{{slug}}_postings <- function(html_text, url = {{url}}) {
  empty <- data.frame(Title = character(0), Location = character(0),
                       Posted_Date = character(0), Link = character(0),
                       stringsAsFactors = FALSE)
  if (is.null(html_text) || !nzchar(trimws(html_text))) return(empty)

  nodes <- decode_apptegy_pagebuilder_nodes(html_text)
  if (is.null(nodes)) return(empty)

  panels <- find_all_apptegy_nodes(nodes, function(n) {
    !is.null(n$type) && n$type == "CONTENT_NODE_PANEL" &&
      !is.null(n$properties$text) && grepl({{panel_match}}, n$properties$text, ignore.case = TRUE)
  })
  if (length(panels) == 0) return(empty)

  titles <- unlist(lapply(panels, function(panel) {
    text_node <- find_apptegy_node(panel$nodes, function(n) !is.null(n$type) && n$type == "CONTENT_NODE_TEXT")
    if (is.null(text_node)) return(character(0))
    apptegy_html_fragment_to_lines(text_node$content$html)
  }), use.names = FALSE)
  titles <- trimws(gsub("[[:space:]]+", " ", titles))
  titles <- titles[nzchar(titles)]
  titles <- titles[!grepl(paste0("application$|^please\\b|^apply\\b|\\bno (current |open )?(openings|positions|vacancies|jobs)\\b|",
                                 "^(deadline|questions|contact|note|closing date)\\b"), titles, ignore.case = TRUE)]
  if (length(titles) == 0) return(empty)

  data.frame(Title = titles, Location = {{city}}, Posted_Date = NA_character_,
             Link = url, stringsAsFactors = FALSE)
})"

  apptegy_scraper_block <- r"(# {{district_comment}} ({{host}}, {{county}}, scaffolded {{date}}).
# Apptegy CMS behind Fastly (a plain request gets the "Client Challenge"
# page), read through the shared chromote session.
# {{node_note}}
# TODO: say what the page holds and how the titles were confirmed live.
{{parser}}

fetch_{{slug}}_postings <- function(chromote_session, url = {{url}}) {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(4)
  html <- chromote_session$Runtime$evaluate("document.documentElement.outerHTML")$result$value
  parse_{{slug}}_postings(html, url)
})"

  apptegy_unit_tests <- r"(# Real fixture: document.documentElement.outerHTML captured via a live
# chromote session from {{host}} (Apptegy; postings live in the page-builder
# JSON embedded in the page). Titles below are what the scaffolded parser
# returned on {{date}}; check them against the live page.

test_that("parse_{{slug}}_postings returns the fixture's real postings, not instructions or application links", {
  html <- paste(readLines(test_path("fixtures", {{fixture}}), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  result <- parse_{{slug}}_postings(html, "url")

  expect_equal(nrow(result), {{n}})
  expect_equal(result$Title, {{titles}})
  expect_true(all(result$Location == {{city}}))
  expect_false(any(grepl("Application$|^Please|^Apply", result$Title)))
})

test_that("parse_{{slug}}_postings returns zero rows (not an error) for a page with no page-builder data", {
  result <- parse_{{slug}}_postings("<html><body>Nothing here</body></html>", "url")
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Title", "Location", "Posted_Date", "Link"))
  expect_equal(nrow(parse_{{slug}}_postings("", "url")), 0)
})

test_that("fetch_{{slug}}_postings drives a chromote session and parses its real rendered HTML", {
  html <- paste(readLines(test_path("fixtures", {{fixture}}), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  session <- fake_chromote_session(html)

  result <- fetch_{{slug}}_postings(session)

  expect_equal(nrow(result), {{n}})
}))"
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
  # Insert in place, leaving every existing line where it is (re-sorting the
  # whole file with the locale's sort() reordered hosts it didn't touch).
  is_host <- nzchar(trimws(allow_lines)) & !startsWith(trimws(allow_lines), "#")
  after_host <- which(is_host & allow_lines > url_host)
  updated_allow <- if (length(after_host) > 0) {
    append(allow_lines, url_host, after = after_host[1] - 1)
  } else {
    c(allow_lines, url_host)
  }
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

if (apptegy_mode) {
  # Only the label's "Apptegy/chromote K-12 districts" prefix is matched
  # anywhere; the name list is for people reading the scrape log.
  label_rx <- '("Apptegy/chromote K-12 districts \\()([^"]*)(\\)",)'
  label_m <- regmatches(rmd_content, regexec(label_rx, rmd_content))[[1]]
  if (length(label_m) == 0) {
    cat("[WARNING] Could not find the Apptegy safe_scrape() label in Mt_ED_Jobs.Rmd. Add the district's name by hand.\n")
  } else if (apptegy_label %in% trimws(strsplit(label_m[3], ",")[[1]])) {
    cat(sprintf("[4/8] '%s' already in Mt_ED_Jobs.Rmd's Apptegy label\n", apptegy_label))
  } else {
    rmd_content <- sub(label_rx, paste0("\\1\\2, ", gsub("\\\\", "\\\\\\\\", apptegy_label), "\\3"), rmd_content)
    writeLines(rmd_content, rmd_path)
    cat(sprintf("[4/8] Updated Mt_ED_Jobs.Rmd (added '%s' to the Apptegy safe_scrape() label)\n", apptegy_label))
  }
} else if (grepl(sprintf("%s_df <-", slug), rmd_content, fixed = TRUE)) {
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

if (apptegy_mode) {
  map_entry_rx <- sprintf('\n  "%s" = fetch_', district)
  if (grepl(sprintf("fetch_%s_postings <-", slug), misc_content, fixed = TRUE)) {
    cat(sprintf("[5/8] fetch_%s_postings already exists in misc_district_scrapers.R\n", slug))
  } else {
    parser <- fill(if (apptegy_node == "text") apptegy_text_parser else apptegy_panel_parser,
                   slug = slug, url = dq(url), city = dq(city), panel_match = dq(apptegy_panel_match))
    block <- fill(apptegy_scraper_block,
                  district_comment = gsub("\n", " ", district), host = url_host, county = county,
                  date = as.character(Sys.Date()),
                  node_note = if (apptegy_node == "text") {
                    "Each posting is a page-builder text block whose bold (<strong>) text is the title."
                  } else {
                    sprintf("Postings are lines inside the accordion panels whose heading matches \"%s\".", apptegy_panel_match)
                  },
                  parser = parser, slug = slug, url = dq(url))
    dispatcher_marker <- "\n# Fetches all "
    if (!grepl(dispatcher_marker, misc_content, fixed = TRUE)) {
      cat("[ERROR] Could not find the '# Fetches all ...' comment above APPTEGY_DISTRICT_SCRAPERS in misc_district_scrapers.R\n")
      quit(status = 1)
    }
    misc_content <- replace_first(misc_content, dispatcher_marker, paste0("\n", block, "\n", dispatcher_marker))
    cat(sprintf("[5/8] Added parse_%s_postings (%s blocks) and fetch_%s_postings to misc_district_scrapers.R\n",
                slug, apptegy_node, slug))
  }
  if (grepl(map_entry_rx, misc_content, fixed = TRUE)) {
    cat(sprintf("[5/8] '%s' already in APPTEGY_DISTRICT_SCRAPERS\n", district))
  } else {
    map_end_rx <- "(\n  \"[^\"]+\" = fetch_[a-z0-9_]+_postings)\n\\)\n\nfetch_apptegy_k12_postings <- function\\("
    if (!grepl(map_end_rx, misc_content)) {
      cat("[ERROR] Could not find the end of APPTEGY_DISTRICT_SCRAPERS in misc_district_scrapers.R\n")
      quit(status = 1)
    }
    misc_content <- sub(map_end_rx,
                        paste0("\\1,\n  ", gsub("\\\\", "\\\\\\\\", dq(district)), " = fetch_", slug,
                               "_postings\n)\n\nfetch_apptegy_k12_postings <- function("),
                        misc_content)
    cat(sprintf("[5/8] Added '%s' to APPTEGY_DISTRICT_SCRAPERS\n", district))
  }
  writeLines(misc_content, misc_path)

  # What the new parser returns on the fixture: the tests below assert it.
  scraper_env <- new.env()
  parsed <- tryCatch({
    suppressMessages(sys.source(misc_path, envir = scraper_env))
    scraper_env[[paste0("parse_", slug, "_postings")]](fixture_txt, url)
  }, error = function(e) {
    cat(sprintf("[ERROR] Running parse_%s_postings on the fixture failed: %s\n", slug, conditionMessage(e)))
    quit(status = 1)
  })
  map_size <- length(scraper_env$APPTEGY_DISTRICT_SCRAPERS)
  cat(sprintf("\nThe parser returns %d posting(s) from %s:\n", nrow(parsed), apptegy_fixture))
  if (nrow(parsed) > 0) cat(paste0("  - ", parsed$Title, collapse = "\n"), "\n")
  if (nrow(parsed) == 0) {
    cat("[WARNING] Zero postings. If the page shows openings, try --node panel (or the other node type),\n")
    cat("          or write the parser by hand; the tests below will assert zero until you do.\n")
  }
  cat("Check these against the live page before committing.\n\n")
} else if (grepl(sprintf("fetch_%s_postings", slug), misc_content, fixed = TRUE)) {
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

if (apptegy_mode) {
  test_lines <- readLines(test_path, warn = FALSE)
  n_parsed <- nrow(parsed)

  # A. The shared-session dispatcher test: fixture, URL routing, counts.
  start <- grep('^test_that\\("fetch_apptegy_k12_postings shares one session across all [0-9]+ districts', test_lines)
  if (length(start) != 1) {
    cat("[ERROR] Could not find the fetch_apptegy_k12_postings dispatcher test in test-misc-district-scrapers.R\n")
    quit(status = 1)
  }
  end <- start - 1 + which(test_lines[start:length(test_lines)] == "})")[1]
  blk <- start:end
  if (any(grepl(sprintf("District == %s)", dq(district)), test_lines[blk], fixed = TRUE))) {
    cat(sprintf("[6/8] '%s' already in the dispatcher test\n", district))
  } else {
    i_fix <- blk[grepl("^  # Same fake session serves every district", test_lines[blk])][1]
    i_else <- blk[test_lines[blk] == '          else ""'][1]
    i_n <- blk[grepl("^  expect_equal\\(nrow\\(result\\), .*\\)$", test_lines[blk])][1]
    i_sum <- tail(blk[grepl("^  expect_equal\\(sum\\(result\\$District == ", test_lines[blk])], 1)
    if (any(is.na(c(i_fix, i_else, i_n))) || length(i_sum) == 0) {
      cat("[ERROR] The dispatcher test's layout changed (fixture block, else \"\" routing line, nrow or per-district lines); edit it by hand.\n")
      quit(status = 1)
    }
    # An earlier routing branch whose pattern matches this URL would serve
    # another district's fixture to this one.
    pats <- regmatches(test_lines[blk], regexpr('grepl\\("[^"]+", navigated_url\\)', test_lines[blk]))
    pats <- sub('^grepl\\("([^"]+)".*$', "\\1", pats)
    clash <- pats[vapply(pats, function(p) grepl(p, url), logical(1))]
    if (length(clash) > 0) {
      cat(sprintf("[WARNING] Routing pattern(s) %s already match %s; the dispatcher test will route this district to the wrong fixture. Fix the routing by hand.\n",
                  paste(dq(clash), collapse = ", "), url))
    }
    var <- paste0(slug, "_html")
    fixture_line <- sprintf('  %s <- paste(readLines(test_path("fixtures", %s), warn = FALSE, encoding = "UTF-8"), collapse = "\\n")',
                            var, dq(apptegy_fixture))
    route_line <- sprintf("          else if (grepl(%s, navigated_url)) %s", dq(url_key), var)
    sum_line <- sprintf("  expect_equal(sum(result$District == %s), %d)", dq(district), n_parsed)
    test_lines[i_n] <- sub("\\)$", sprintf(" + %d)", n_parsed), test_lines[i_n])
    test_lines[start] <- sub("across all [0-9]+ districts", sprintf("across all %d districts", map_size), test_lines[start])
    # Insert bottom-up so earlier indices stay valid; the fixture line goes
    # after the last fixture read (before the blank line above the comment).
    test_lines <- append(test_lines, sum_line, after = i_sum)
    test_lines <- append(test_lines, route_line, after = i_else - 1)
    test_lines <- append(test_lines, fixture_line, after = i_fix - 2)
    cat(sprintf("[6/8] Updated the dispatcher test (fixture, routing on \"%s\", +%d total, per-district count, %d districts)\n",
                url_key, n_parsed, map_size))
  }

  # B. Unit tests for the new parser and fetch, at the end of the file.
  if (any(grepl(sprintf("parse_%s_postings(html", slug), test_lines, fixed = TRUE))) {
    cat(sprintf("[6/8] parse_%s_postings unit tests already exist\n", slug))
  } else {
    unit <- fill(apptegy_unit_tests, slug = slug, host = url_host, date = as.character(Sys.Date()),
                 fixture = dq(apptegy_fixture), n = as.character(n_parsed),
                 titles = paste(deparse(parsed$Title, width.cutoff = 500L), collapse = ""),
                 city = dq(city))
    test_lines <- c(test_lines, "", strsplit(unit, "\n", fixed = TRUE)[[1]])
    cat(sprintf("[6/8] Added unit tests for parse_%s_postings / fetch_%s_postings\n", slug, slug))
  }
  writeLines(test_lines, test_path)
} else if (grepl(sprintf("parse_%s_postings", slug), test_content, fixed = TRUE)) {
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
if (apptegy_mode) {
  cat("Next steps:\n")
  cat(sprintf("  1. Check the titles above against the live page; fill in the TODO comment above parse_%s_postings().\n", slug))
  cat("  2. testthat::test_file(\"tests/testthat/test-misc-district-scrapers.R\") and test-salary-scrapers.R\n")
  cat(sprintf("  3. Rscript scripts/repro_scraper.R \"%s\" for the live run; then DLI map, DISTRICT_BACKLOG.md, CLAUDE.md count, the repo's Copilot internet-access setting.\n", district))
} else {
  cat(sprintf("Next step: Implement parser selector logic in parse_%s_postings() in misc_district_scrapers.R\n", slug))
}
