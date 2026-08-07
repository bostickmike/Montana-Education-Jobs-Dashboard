# Real fixture: the actual Montana (fips=30) response from the Urban
# Institute's Education Data Portal school-districts/ccd/directory/2022
# endpoint, captured 2026-08-06 -- trimmed to the 32 LEA records
# MT_CCD_LEA_MAP actually needs (elementary + high-school pairs, or one
# unified K-12 record, for each of the 18 districts this project scrapes
# directly) plus a handful of real noise rows (agency_type != 1 coops/
# county-level placeholder entries with 0 schools) to prove the filter
# excludes them correctly.

test_that("parse_ccd_teacher_fte sums an elementary+HS pair into one combined District", {
  df <- read.csv(test_path("fixtures", "ccd_mt_directory_2022.csv"))
  result <- parse_ccd_teacher_fte(df)

  billings <- result[result$District == "Billings Public Schools", ]
  expect_equal(nrow(billings), 1)
  expect_equal(billings$Teachers_Total_FTE, 729 + 323)
  expect_equal(billings$Enrollment, 10988 + 5610)
})

test_that("parse_ccd_teacher_fte handles a county-named HS district (Lewistown -> Fergus H S)", {
  df <- read.csv(test_path("fixtures", "ccd_mt_directory_2022.csv"))
  result <- parse_ccd_teacher_fte(df)

  lewistown <- result[result$District == "Lewistown Public Schools", ]
  expect_equal(nrow(lewistown), 1)
  expect_equal(lewistown$Teachers_Total_FTE, 63 + 25)
  expect_equal(lewistown$Enrollment, 888 + 356)
})

test_that("parse_ccd_teacher_fte passes through an already-unified K-12 record as-is", {
  df <- read.csv(test_path("fixtures", "ccd_mt_directory_2022.csv"))
  result <- parse_ccd_teacher_fte(df)

  east_helena <- result[result$District == "East Helena Public Schools", ]
  expect_equal(nrow(east_helena), 1)
  expect_equal(east_helena$Teachers_Total_FTE, 115)
  expect_equal(east_helena$Enrollment, 1952)
})

test_that("parse_ccd_teacher_fte produces exactly the 18 registry districts, no more no less", {
  df <- read.csv(test_path("fixtures", "ccd_mt_directory_2022.csv"))
  result <- parse_ccd_teacher_fte(df)

  expect_equal(nrow(result), length(MT_CCD_LEA_MAP))
  expect_setequal(result$District, names(MT_CCD_LEA_MAP))

  # Regression: the coop/county-level placeholder noise rows (agency_type
  # != 1, or 0 schools) must not leak into the result or get summed into a
  # real district's FTE.
  expect_false(any(grepl("Coop|Joint Service", result$District)))
})

test_that("parse_ccd_teacher_fte returns NA (not an error) for a district whose LEA rows are entirely absent this run", {
  df <- read.csv(test_path("fixtures", "ccd_mt_directory_2022.csv"))
  df_missing_billings <- df[!grepl("^Billings", df$lea_name), ]

  result <- parse_ccd_teacher_fte(df_missing_billings)

  billings <- result[result$District == "Billings Public Schools", ]
  expect_equal(nrow(billings), 1)
  expect_true(is.na(billings$Teachers_Total_FTE))
})

test_that("parse_ccd_teacher_fte returns an empty, correctly-shaped frame when given no rows", {
  result <- parse_ccd_teacher_fte(data.frame())
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("District", "Teachers_Total_FTE", "Enrollment"))
})
