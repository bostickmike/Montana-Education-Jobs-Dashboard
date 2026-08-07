# Real fixtures: actual Montana (fips=30) responses from the Census Data
# API's ACS 5-Year Estimates endpoints, captured 2026-08-06 (2022 detail +
# subject tables, plus 2017 detail for the 5-year population trend). All 56
# counties, real data.

test_that("parse_census_income_rent_population strips the state suffix so County matches the registry format", {
  json <- paste(readLines(test_path("fixtures", "acs_mt_detail_2022.json"), warn = FALSE), collapse = "\n")
  raw <- parse_acs_json(json)
  result <- parse_census_income_rent_population(raw, 2022)

  expect_equal(nrow(result), 56)
  yellowstone <- result[result$County == "Yellowstone County", ]
  expect_equal(nrow(yellowstone), 1)
  expect_equal(yellowstone$Median_Household_Income, 72300)
  expect_equal(yellowstone$Median_Gross_Rent, 1055)
  expect_equal(yellowstone$Population, 165524)
  expect_equal(yellowstone$ACS_Year, 2022)
})

test_that("parse_census_mining_employment_share computes a real share and shows real county-to-county spread", {
  json <- paste(readLines(test_path("fixtures", "acs_mt_subject_2022.json"), warn = FALSE), collapse = "\n")
  raw <- parse_acs_json(json)
  result <- parse_census_mining_employment_share(raw)

  yellowstone <- result[result$County == "Yellowstone County", ]
  expect_equal(round(yellowstone$Mining_Employment_Share, 6), round(1192 / 84122, 6))

  # Real data confirms meaningful county-to-county variation, not noise --
  # same spirit as Wyoming's Sublette/Campbell vs. Teton spread.
  expect_true(max(result$Mining_Employment_Share, na.rm = TRUE) > 0.02)
})

test_that("compute_population_change computes a real 5-year trend from real 2017 vs 2022 data", {
  json_2022 <- paste(readLines(test_path("fixtures", "acs_mt_detail_2022.json"), warn = FALSE), collapse = "\n")
  json_2017 <- paste(readLines(test_path("fixtures", "acs_mt_detail_2017.json"), warn = FALSE), collapse = "\n")
  current <- parse_census_income_rent_population(parse_acs_json(json_2022), 2022)
  prior <- parse_census_income_rent_population(parse_acs_json(json_2017), 2017)

  result <- compute_population_change(current, prior)

  yellowstone <- result[result$County == "Yellowstone County", ]
  expect_equal(nrow(yellowstone), 1)
  expect_true(!is.na(yellowstone$Population_Change_Pct))
})

test_that("parse_acs_json returns an empty data frame for a header-only or empty response", {
  expect_equal(nrow(parse_acs_json('[["NAME","B19013_001E"]]')), 0)
})

test_that("clean_acs_value treats negative sentinel codes as real NA", {
  expect_true(is.na(clean_acs_value(-666666666)))
  expect_equal(clean_acs_value(50000), 50000)
})

test_that("strip_state_suffix removes the trailing state name but leaves other text alone", {
  expect_equal(strip_state_suffix("Yellowstone County, Montana"), "Yellowstone County")
  expect_equal(strip_state_suffix("Not A State Suffix"), "Not A State Suffix")
})
