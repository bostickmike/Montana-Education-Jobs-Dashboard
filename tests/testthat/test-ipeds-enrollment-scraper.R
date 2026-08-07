# Real fixtures: the actual Montana (fips=30) responses from the Urban
# Institute's Education Data Portal college-university/ipeds/fall-enrollment
# endpoint -- the original 6 unitids captured 2026-08-06 for 2023 (latest
# available) and 2018 (5 years prior, for the trend test), the 7 added
# when MT_IPEDS_UNITID_MAP was extended captured 2026-08-07, the 4
# tribal colleges (Fort Peck CC, Little Big Horn College, Salish Kootenai
# College, Stone Child College) appended the same day when their own
# fast-follow gap closed, and Aaniiih Nakoda College / Chief Dull Knife
# College appended once their own new heuristic scrapers
# (misc_college_scrapers.R) went live.

test_that("parse_ipeds_he_enrollment sums FTE across every level_of_study for all 19 institutions", {
  df <- read.csv(test_path("fixtures", "ipeds_mt_fall_enrollment_2023.csv"))
  result <- parse_ipeds_he_enrollment(df, 2023)

  expect_equal(nrow(result), 19)
  msu <- result[result$Name == "Montana State University", ]
  expect_equal(msu$Enrollment, 15586)
  expect_equal(msu$Enrollment_Year, "2023")

  fvcc <- result[result$Name == "Flathead Valley Community College", ]
  expect_equal(fvcc$Enrollment, 1208)

  um <- result[result$Name == "University of Montana", ]
  expect_equal(um$Enrollment, 16888)

  skc <- result[result$Name == "Salish Kootenai College", ]
  expect_equal(skc$Enrollment, 1078)
})

test_that("parse_ipeds_he_enrollment returns an empty, correctly-shaped frame when given no rows", {
  result <- parse_ipeds_he_enrollment(data.frame(), 2023)
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Name", "Enrollment", "Enrollment_Year"))
})

test_that("compute_enrollment_change computes a real 5-year trend from real 2018 vs 2023 data", {
  current_raw <- read.csv(test_path("fixtures", "ipeds_mt_fall_enrollment_2023.csv"))
  prior_raw <- read.csv(test_path("fixtures", "ipeds_mt_fall_enrollment_2018.csv"))
  current <- parse_ipeds_he_enrollment(current_raw, 2023)
  prior <- parse_ipeds_he_enrollment(prior_raw, 2018)

  result <- compute_enrollment_change(current, prior)

  msu <- result[result$Name == "Montana State University", ]
  # Real 2018->2023 change: (15586 - 15327) / 15327
  expect_equal(msu$Enrollment_Change_Pct, (15586 - 15327) / 15327, tolerance = 1e-6)

  # Real data confirms a mix, not a uniform trend -- Montana Tech shrank
  # over this window while MSU grew.
  mtech <- result[result$Name == "Montana Tech", ]
  expect_true(mtech$Enrollment_Change_Pct < 0)

  # Same real mix among the tribal colleges: Fort Peck CC grew while
  # Salish Kootenai College shrank over this window.
  fpcc <- result[result$Name == "Fort Peck Community College", ]
  expect_true(fpcc$Enrollment_Change_Pct > 0)
  skc <- result[result$Name == "Salish Kootenai College", ]
  expect_true(skc$Enrollment_Change_Pct < 0)
})

test_that("compute_enrollment_change returns an empty frame when either side has no rows", {
  result <- compute_enrollment_change(data.frame(), data.frame(Name = "X", Enrollment = 1))
  expect_equal(nrow(result), 0)
})
