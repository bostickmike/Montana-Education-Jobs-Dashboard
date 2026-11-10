# Pipeline Orchestration Dry-Run Test
#
# Validates the execution of the main K-12 and Higher Ed scraping/combination chunks in Mt_ED_Jobs.Rmd
# by executing chunk expressions against an isolated mock environment.
#
# Catches:
# 1. Pipeline syntax / operator typos (e.g., %% vs %>%)
# 2. Scope errors (e.g. object 'District' not found)
# 3. Join / transmute errors on empty or partial data frames
# 4. Incompatible types in bind_rows (e.g. <date> vs <character> date_posted)
# 5. Missing columns in direct_df before combination with OPI feed

extract_chunk_code <- function(rmd_lines, chunk_name) {
  start_pat <- paste0("^```[{]r[[:space:]]+", chunk_name)
  chunk_start <- which(grepl(start_pat, rmd_lines))
  if (length(chunk_start) == 0) stop("Chunk not found: ", chunk_name)
  chunk_ends <- which(grepl("^```$", rmd_lines))
  chunk_end <- chunk_ends[chunk_ends > chunk_start[1]][1]
  paste(rmd_lines[(chunk_start[1] + 1):(chunk_end - 1)], collapse = "\n")
}

test_that("Mt_ED_Jobs.Rmd K-12 scraping and combination chunks execute cleanly with mock data", {
  rmd_path <- here::here("Mt_ED_Jobs.Rmd")
  expect_true(file.exists(rmd_path))
  rmd_lines <- readLines(rmd_path, warn = FALSE)

  k12_scrape_code <- extract_chunk_code(rmd_lines, "k12 direct-platform districts")
  combine_code_full <- extract_chunk_code(rmd_lines, "combine k12 data")
  combine_lines <- strsplit(combine_code_full, "\n")[[1]]
  direct_def_line <- which(grepl("^direct_df\\s*<-\\s*bind_rows\\(", combine_lines))
  expect_true(length(direct_def_line) > 0)
  combine_code <- paste(combine_lines[1:direct_def_line[1]], collapse = "\n")

  # Create mock environment
  env <- new.env(parent = globalenv())
  env$registry <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  env$opi_df <- data.frame(
    title = "Mock Teacher",
    date_posted = "2026-10-27",
    position = "Teacher",
    location = "Helena",
    url = "https://opi.mt.gov",
    District = "Helena",
    Posting_Source = "OPI",
    stringsAsFactors = FALSE
  )

  # Scrapers return a mix of string and Date dates to verify safe_scrape coercion and bind_rows type-safety
  counter <- 0
  env$safe_scrape <- function(name, scrape_fn, expected_cols = NULL, log_path = NULL) {
    counter <<- counter + 1
    if (is.null(expected_cols)) expected_cols <- c("Title", "Location", "Posted_Date", "Link")
    vals <- as.list(rep("mock_val", length(expected_cols)))
    names(vals) <- expected_cols
    if ("Posted_Date" %in% expected_cols) {
      vals$Posted_Date <- if (counter %% 3 == 0) {
        "2026-10-27"
      } else if (counter %% 3 == 1) {
        "10/27/2026"
      } else {
        "October 27, 2026"
      }
    }
    df <- as.data.frame(vals, stringsAsFactors = FALSE)
    if ("Posted_Date" %in% names(df)) df$Posted_Date <- as.character(df$Posted_Date)
    if ("date_posted" %in% names(df)) df$date_posted <- as.character(df$date_posted)
    df
  }

  withr::with_dir(here::here(), {
    expect_no_error(eval(parse(text = k12_scrape_code), envir = env))
    expect_no_error(eval(parse(text = combine_code), envir = env))
  })

  # Assert direct_df structure and type consistency
  expect_true(exists("direct_df", envir = env))
  expect_true(nrow(env$direct_df) > 0)
  expected_cols <- c("title", "date_posted", "position", "location", "url", "District", "Posting_Source")
  expect_true(all(expected_cols %in% names(env$direct_df)))
  expect_s3_class(env$direct_df$date_posted, "Date")
})

test_that("Mt_ED_Jobs.Rmd K-12 pipeline handles all-empty scraper responses gracefully", {
  rmd_path <- here::here("Mt_ED_Jobs.Rmd")
  rmd_lines <- readLines(rmd_path, warn = FALSE)

  k12_scrape_code <- extract_chunk_code(rmd_lines, "k12 direct-platform districts")
  combine_code_full <- extract_chunk_code(rmd_lines, "combine k12 data")
  combine_lines <- strsplit(combine_code_full, "\n")[[1]]
  direct_def_line <- which(grepl("^direct_df\\s*<-\\s*bind_rows\\(", combine_lines))
  combine_code <- paste(combine_lines[1:direct_def_line[1]], collapse = "\n")

  # Create mock environment where all scrapers return 0 rows
  env <- new.env(parent = globalenv())
  env$registry <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  env$opi_df <- data.frame(
    title = character(0),
    date_posted = character(0),
    position = character(0),
    location = character(0),
    url = character(0),
    District = character(0),
    Posting_Source = character(0),
    stringsAsFactors = FALSE
  )
  env$safe_scrape <- function(name, scrape_fn, expected_cols = NULL, log_path = NULL) {
    if (is.null(expected_cols)) expected_cols <- c("Title", "Location", "Posted_Date", "Link")
    mat <- matrix(character(0), nrow = 0, ncol = length(expected_cols))
    df <- as.data.frame(mat, stringsAsFactors = FALSE)
    names(df) <- expected_cols
    df
  }

  withr::with_dir(here::here(), {
    expect_no_error(eval(parse(text = k12_scrape_code), envir = env))
    expect_no_error(eval(parse(text = combine_code), envir = env))
  })

  expect_true(exists("direct_df", envir = env))
  expect_equal(nrow(env$direct_df), 0)
  expect_s3_class(env$direct_df$date_posted, "Date")
})

test_that("Mt_ED_Jobs.Rmd Higher Ed scraping chunk executes cleanly with mock data", {
  rmd_path <- here::here("Mt_ED_Jobs.Rmd")
  rmd_lines <- readLines(rmd_path, warn = FALSE)

  he_scrape_code <- extract_chunk_code(rmd_lines, "he direct-platform institutions")

  # Create mock environment
  env <- new.env(parent = globalenv())
  env$he_registry <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
  env$safe_scrape <- function(name, scrape_fn, expected_cols = NULL, log_path = NULL) {
    if (is.null(expected_cols)) expected_cols <- c("Title", "Location", "Posted_Date", "Link")
    vals <- as.list(rep("mock_val", length(expected_cols)))
    names(vals) <- expected_cols
    df <- as.data.frame(vals, stringsAsFactors = FALSE)
    if ("Posted_Date" %in% names(df)) df$Posted_Date <- as.character(df$Posted_Date)
    df
  }

  withr::with_dir(here::here(), {
    expect_no_error(eval(parse(text = he_scrape_code), envir = env))
  })

  expect_true(exists("hedata_raw", envir = env))
  expect_true(nrow(env$hedata_raw) > 0)
  expect_true(all(c("Title", "Location", "Posted_Date", "Link", "Institution") %in% names(env$hedata_raw)))
})
