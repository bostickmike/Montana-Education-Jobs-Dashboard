test_that("remove_opi_direct_duplicates removes only exact direct-board overlaps", {
  registry <- data.frame(
    District = c("Billings Public Schools", "East Helena Public Schools"),
    City = c("Billings", "East Helena"),
    stringsAsFactors = FALSE
  )
  direct_df <- data.frame(
    title = c("Elementary Teacher", "Math Teacher"),
    date_posted = as.Date(c("2026-08-01", "2026-08-02")),
    District = c("Billings Public Schools", "East Helena Public Schools"),
    stringsAsFactors = FALSE
  )
  opi_df <- data.frame(
    title = c(
      "ELEMENTARY teacher",
      "Elementary Teacher",
      "Science Teacher",
      "Math Teacher",
      "Elementary Teacher"
    ),
    date_posted = as.Date(c(
      "2026-08-01",
      "2026-08-02",
      "2026-08-01",
      "2026-08-02",
      "2026-08-01"
    )),
    location = c(
      "Billings",
      "Billings - Billings Christian School",
      "Billings - Billings Christian School",
      "East Helena, MT",
      "Butte"
    ),
    stringsAsFactors = FALSE
  )

  result <- remove_opi_direct_duplicates(opi_df, direct_df, registry)

  expect_equal(nrow(result), 3)
  expect_equal(
    result$location,
    c("Billings - Billings Christian School", "Billings - Billings Christian School", "Butte")
  )
})

test_that("remove_opi_direct_duplicates retains rows without a posted date", {
  registry <- data.frame(District = "Billings Public Schools", City = "Billings")
  direct_df <- data.frame(
    title = "Elementary Teacher",
    date_posted = as.Date("2026-08-01"),
    District = "Billings Public Schools"
  )
  opi_df <- data.frame(
    title = "Elementary Teacher",
    date_posted = as.Date(NA),
    location = "Billings"
  )

  expect_equal(nrow(remove_opi_direct_duplicates(opi_df, direct_df, registry)), 1)
})

test_that("generate_opi_discrepancy_report categorizes ghosts, unmatched jobs, and ignores uncovered cities", {
  registry <- data.frame(
    District = c("Billings Public Schools", "East Helena Public Schools"),
    City = c("Billings", "East Helena"),
    stringsAsFactors = FALSE
  )
  direct_df <- data.frame(
    title = c("Elementary Teacher", "Math Teacher"),
    date_posted = as.character(c(Sys.Date() - 5, Sys.Date() - 5)),
    District = c("Billings Public Schools", "East Helena Public Schools"),
    stringsAsFactors = FALSE
  )
  opi_df <- data.frame(
    title = c(
      "ELEMENTARY teacher",   # Duplicate for Billings (excluded from report)
      "Special Education",    # Unmatched, recent (<60d) for Billings (discrepancy)
      "Custodian",            # Unmatched, stale (>60d) for Billings (ghost job)
      "Night Lead",           # Unmatched, no date for East Helena
      "Art Teacher"           # Butte (uncovered district - excluded from report)
    ),
    date_posted = c(
      as.character(Sys.Date() - 5),
      as.character(Sys.Date() - 10),
      as.character(Sys.Date() - 90),
      NA,
      as.character(Sys.Date() - 5)
    ),
    location = c(
      "Billings",
      "Billings Public Schools",
      "Billings",
      "East Helena, MT",
      "Butte"
    ),
    url = c(
      "https://opi.mt.gov/1",
      "https://opi.mt.gov/2",
      "https://opi.mt.gov/3",
      "https://opi.mt.gov/4",
      "https://opi.mt.gov/5"
    ),
    stringsAsFactors = FALSE
  )

  report <- generate_opi_discrepancy_report(opi_df, direct_df, registry)

  expect_equal(nrow(report), 3)
  expect_equal(report$Title, c("Special Education", "Custodian", "Night Lead"))
  expect_equal(report$District, c("Billings Public Schools", "Billings Public Schools", "East Helena Public Schools"))
  expect_equal(unique(report$Source), "OPI")
  expect_true(grepl("investigate ATS drift", report$Discrepancy_Type[1]))
  expect_true(grepl("Potential ghost posting on OPI", report$Discrepancy_Type[2]))
  expect_equal(report$Discrepancy_Type[3], "Unmatched on direct scraper (no date)")
  expect_equal(report$Detected_Date[1], as.character(Sys.Date()))

  # Verify report_path writes out the file during deduplication
  tmp <- tempfile(fileext = ".csv")
  deduped <- remove_opi_direct_duplicates(opi_df, direct_df, registry, report_path = tmp)
  expect_true(file.exists(tmp))
  read_back <- read.csv(tmp, stringsAsFactors = FALSE)
  expect_equal(nrow(read_back), 3)
  expect_equal(nrow(deduped), 4) # 1 duplicate dropped, 4 survived (including Butte)
  unlink(tmp)
})

test_that("apply_opi_district_fallback maps single-district cities to canonical names when direct scraper is empty", {
  registry <- data.frame(
    District = c("Bozeman Public Schools", "Livingston Public Schools", "Whitefish School District"),
    City = c("Bozeman", "Livingston", "Whitefish"),
    stringsAsFactors = FALSE
  )
  # Direct scraper errored or returned 0 rows for Bozeman & Livingston
  direct_df <- data.frame(
    title = "High School Science",
    date_posted = as.Date("2026-10-28"),
    District = "Whitefish School District",
    stringsAsFactors = FALSE
  )
  opi_df <- data.frame(
    title = c("Middle School Math", "Elementary Teacher"),
    location = c("Bozeman, MT", "Livingston"),
    date_posted = as.Date(c("2026-10-28", "2026-10-29")),
    District = c("Bozeman, MT", "Livingston"),
    stringsAsFactors = FALSE
  )

  result <- apply_opi_district_fallback(opi_df, registry, direct_df)

  expect_equal(nrow(result), 2)
  expect_equal(result$District, c("Bozeman Public Schools", "Livingston Public Schools"))
})

test_that("apply_opi_district_fallback resolves multi-district cities and specific keywords cleanly", {
  registry <- data.frame(
    District = c("Bozeman Public Schools", "Monforton School District #27", "Missoula County Public Schools", "Hellgate Elementary School District"),
    City = c("Bozeman", "Bozeman", "Missoula", "Missoula"),
    stringsAsFactors = FALSE
  )
  direct_df <- data.frame(
    title = character(0),
    date_posted = as.Date(character(0)),
    District = character(0),
    stringsAsFactors = FALSE
  )
  opi_df <- data.frame(
    title = c("Elementary Teacher", "Middle School Science", "High School English", "K-5 Teacher"),
    location = c("Bozeman", "Monforton School", "Missoula", "Hellgate"),
    date_posted = as.Date(c("2026-10-28", "2026-10-28", "2026-10-29", "2026-10-29")),
    District = c("Bozeman", "Monforton School", "Missoula", "Hellgate"),
    stringsAsFactors = FALSE
  )

  result <- apply_opi_district_fallback(opi_df, registry, direct_df)

  expect_equal(nrow(result), 4)
  expect_equal(result$District, c("Bozeman Public Schools", "Monforton School District #27", "Missoula County Public Schools", "Hellgate Elementary School District"))
})

test_that("apply_opi_district_fallback retains raw location for unregistered rural or private schools", {
  registry <- data.frame(
    District = c("Billings Public Schools"),
    City = c("Billings"),
    stringsAsFactors = FALSE
  )
  opi_df <- data.frame(
    title = c("Teacher", "Itinerant SLP"),
    location = c("Busby", "Itinerant"),
    date_posted = as.Date(c("2026-10-28", "2026-10-29")),
    District = c("Busby", "Itinerant"),
    stringsAsFactors = FALSE
  )

  result <- apply_opi_district_fallback(opi_df, registry)

  expect_equal(nrow(result), 2)
  expect_equal(result$District, c("Busby", "Itinerant"))
})

test_that("apply_opi_district_fallback leaves OPI rows raw for districts whose direct scrape returned rows", {
  registry <- data.frame(
    District = c("Bozeman Public Schools", "Livingston Public Schools"),
    City = c("Bozeman", "Livingston"),
    stringsAsFactors = FALSE
  )
  direct_df <- data.frame(title = "Math Teacher", date_posted = as.Date("2026-10-28"),
                          District = "Bozeman Public Schools", stringsAsFactors = FALSE)
  opi_df <- data.frame(title = c("Science Teacher", "Elementary Teacher"),
                       location = c("Bozeman", "Livingston"),
                       District = c("Bozeman", "Livingston"), stringsAsFactors = FALSE)

  result <- apply_opi_district_fallback(opi_df, registry, direct_df)

  expect_equal(result$District, c("Bozeman", "Livingston Public Schools"))
})

test_that("apply_opi_district_fallback prefers the longest district name and never guesses a same-city district", {
  registry <- data.frame(
    District = c("Helena Public Schools", "East Helena Public Schools", "Billings Public Schools",
                 "Independent School", "Missoula County Public Schools", "DeSmet Public School"),
    City = c("Helena", "East Helena", "Billings", "Billings", "Missoula", "Missoula"),
    stringsAsFactors = FALSE
  )
  direct_df <- data.frame(title = "Teacher", date_posted = as.Date("2026-10-28"),
                          District = "Missoula County Public Schools", stringsAsFactors = FALSE)
  opi_df <- data.frame(title = c("Teacher", "Teacher", "Teacher"),
                       location = c("East Helena", "Independent School - Billings", "Missoula"),
                       District = c("East Helena", "Independent School - Billings", "Missoula"),
                       stringsAsFactors = FALSE)

  result <- apply_opi_district_fallback(opi_df, registry, direct_df)

  # Missoula's primary district (MCPS) scraped fine, so its OPI row stays raw
  # rather than being handed to DeSmet just because DeSmet had no direct rows.
  expect_equal(result$District, c("East Helena Public Schools", "Independent School", "Missoula"))
})
