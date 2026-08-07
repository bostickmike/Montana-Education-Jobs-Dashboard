# Real fixture: the actual Montana (fips=30) response from the Urban
# Institute's Education Data Portal
# college-university/ipeds/salaries-instructional-staff/2024 endpoint,
# captured 2026-08-06 -- trimmed to the 6 unitids MT_IPEDS_UNITID_MAP
# actually needs (all academic_rank x contract_length x sex combinations
# for each, real data not synthetic).

test_that("parse_ipeds_he_salaries extracts real overall + Professor-rank salaries for all 6 institutions", {
  df <- read.csv(test_path("fixtures", "ipeds_mt_salaries_2024.csv"))
  result <- parse_ipeds_he_salaries(df, 2024)

  expect_equal(nrow(result), 6)

  msu <- result[result$Name == "Montana State University", ]
  expect_equal(round(msu$Faculty_Avg_Salary), 99427)
  expect_equal(msu$Faculty_Count, 626)
  expect_equal(round(msu$Faculty_Avg_Salary_Professor), 131791)
  expect_equal(msu$Salary_Year, "2024")

  mtech <- result[result$Name == "Montana Tech", ]
  expect_equal(round(mtech$Faculty_Avg_Salary), 78730)
  expect_equal(mtech$Faculty_Count, 125)
})

test_that("parse_ipeds_he_salaries returns real NA for a unitid missing from that year's response", {
  df <- read.csv(test_path("fixtures", "ipeds_mt_salaries_2024.csv"))
  df_no_fvcc <- df[df$unitid != 180197, ]

  result <- parse_ipeds_he_salaries(df_no_fvcc, 2024)

  fvcc <- result[result$Name == "Flathead Valley Community College", ]
  expect_equal(nrow(fvcc), 1)
  expect_true(is.na(fvcc$Faculty_Avg_Salary))
})

test_that("parse_ipeds_he_salaries returns an empty, correctly-shaped frame when given no rows", {
  result <- parse_ipeds_he_salaries(data.frame(), 2024)
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Name", "Faculty_Avg_Salary", "Faculty_Avg_Salary_Professor",
                                 "Faculty_Count", "Salary_Year"))
})

test_that("clean_ipeds_value treats negative sentinel codes as real NA, not real values", {
  expect_true(is.na(clean_ipeds_value(-1)))
  expect_true(is.na(clean_ipeds_value(-2)))
  expect_true(is.na(clean_ipeds_value(-3)))
  expect_equal(clean_ipeds_value(50000), 50000)
})

test_that("parse_ipeds_salary_trend_year extracts just the headline overall figure per institution", {
  df <- read.csv(test_path("fixtures", "ipeds_mt_salaries_2024.csv"))
  result <- parse_ipeds_salary_trend_year(df, 2024)

  expect_equal(nrow(result), 6)
  expect_equal(names(result), c("Name", "Year", "Faculty_Avg_Salary"))
  msu <- result[result$Name == "Montana State University", ]
  expect_equal(round(msu$Faculty_Avg_Salary), 99427)
})

test_that("MT_IPEDS_UNITID_MAP covers a real subset of the registered institutions, with every entry a real registry institution", {
  # No longer an exact 1:1 match -- institutions added to
  # he_institution_registry.csv via a heuristic (non-platform-API) scraper,
  # like Miles Community College, don't automatically get IPEDS salary
  # coverage; that's a separate, deliberate fast-follow research pass, not
  # a requirement for an institution to be job-postings-eligible. This test
  # still catches the real regression that matters: a name in
  # MT_IPEDS_UNITID_MAP that ISN'T a real registered institution.
  registry <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
  expect_true(all(MT_IPEDS_UNITID_MAP$Name %in% registry$Institution))
  expect_gt(nrow(MT_IPEDS_UNITID_MAP), 0)
})
