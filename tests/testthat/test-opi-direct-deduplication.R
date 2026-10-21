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
