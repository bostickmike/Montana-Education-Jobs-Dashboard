# Real fixture: the actual Montana (fips=30) response from the Urban
# Institute's Education Data Portal
# college-university/ipeds/salaries-instructional-staff/2024 endpoint --
# the original 6 unitids captured 2026-08-06, the 7 added when
# MT_IPEDS_UNITID_MAP was extended to cover the rest of the registry
# captured 2026-08-07, the 4 tribal colleges (Fort Peck CC, Little Big Horn
# College, Salish Kootenai College, Stone Child College) appended the same
# day when their own fast-follow gap closed, and Aaniiih Nakoda College /
# Chief Dull Knife College appended once their own new heuristic scrapers
# (misc_college_scrapers.R) went live -- all trimmed to just the unitids
# MT_IPEDS_UNITID_MAP actually needs (all academic_rank x contract_length
# x sex combinations for each, real data not synthetic).

test_that("parse_ipeds_he_salaries extracts real overall + Professor-rank salaries for all 20 institutions", {
  df <- read.csv(test_path("fixtures", "ipeds_mt_salaries_2024.csv"))
  result <- parse_ipeds_he_salaries(df, 2024)

  expect_equal(nrow(result), 20)

  msu <- result[result$Name == "Montana State University", ]
  expect_equal(round(msu$Faculty_Avg_Salary), 99427)
  expect_equal(msu$Faculty_Count, 626)
  expect_equal(round(msu$Faculty_Avg_Salary_Professor), 131791)
  expect_equal(msu$Salary_Year, "2024")

  mtech <- result[result$Name == "Montana Tech", ]
  expect_equal(round(mtech$Faculty_Avg_Salary), 78730)
  expect_equal(mtech$Faculty_Count, 125)

  um <- result[result$Name == "University of Montana", ]
  expect_equal(round(um$Faculty_Avg_Salary), 93938)
  expect_equal(um$Faculty_Count, 442)

  # Blackfeet CC, Dawson CC, and Miles CC (all small 2-year colleges) have
  # genuinely no academic_rank=1 "Professor" record in the real 2024 data
  # -- confirmed live, not a fixture-trimming artifact -- so
  # Faculty_Avg_Salary_Professor must be real NA for all three, not 0 or
  # a silently-wrong fallback.
  blackfeet <- result[result$Name == "Blackfeet Community College", ]
  expect_equal(round(blackfeet$Faculty_Avg_Salary), 25621)
  expect_equal(blackfeet$Faculty_Count, 53)
  expect_true(is.na(blackfeet$Faculty_Avg_Salary_Professor))

  # The 4 tribal colleges also have no academic_rank=1 "Professor" record
  # in the real 2024 data -- same real absence as Blackfeet/Dawson/Miles
  # above, not a fixture-trimming artifact.
  skc <- result[result$Name == "Salish Kootenai College", ]
  expect_equal(round(skc$Faculty_Avg_Salary), 54230)
  expect_equal(skc$Faculty_Count, 69)
  expect_true(is.na(skc$Faculty_Avg_Salary_Professor))

  stone_child <- result[result$Name == "Stone Child College", ]
  expect_equal(round(stone_child$Faculty_Avg_Salary), 58915)
  expect_equal(stone_child$Faculty_Count, 12)
  expect_true(is.na(stone_child$Faculty_Avg_Salary_Professor))

  # Highlands College has a real, permanent gap unlike every institution
  # above: confirmed live across 2020-2024, IPEDS's salaries-instructional-
  # staff endpoint has zero rows for its unitid in any year -- not a
  # missing rank tier, no salary data reported under its own unitid at
  # all (see MT_IPEDS_UNITID_MAP's own comment in ipeds_salary_scraper.R).
  highlands <- result[result$Name == "Highlands College", ]
  expect_equal(nrow(highlands), 1)
  expect_true(is.na(highlands$Faculty_Avg_Salary))
  expect_true(is.na(highlands$Faculty_Avg_Salary_Professor))
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

  expect_equal(nrow(result), 20)
  expect_equal(names(result), c("Name", "Year", "Faculty_Avg_Salary"))
  msu <- result[result$Name == "Montana State University", ]
  expect_equal(round(msu$Faculty_Avg_Salary), 99427)
})

test_that("MT_IPEDS_UNITID_MAP covers every registered institution exactly, with every entry a real registry institution", {
  # Back to an exact 1:1 match as of 2026-08-07: Salish Kootenai College,
  # Little Big Horn College, Fort Peck Community College, and Stone Child
  # College (all added to the registry via heuristic, non-platform-API
  # scrapers) had their own real unitids confirmed live against the Urban
  # Institute's college directory and folded in, closing the fast-follow
  # gap.
  registry <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
  expect_setequal(MT_IPEDS_UNITID_MAP$Name, registry$Institution)
})
