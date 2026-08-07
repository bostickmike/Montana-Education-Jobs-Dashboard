# Real fixtures: the actual Montana (fips=30) responses from the Urban
# Institute's Education Data Portal college-university/fsa/grants/2021 and
# college-university/ipeds/fall-enrollment/2021 endpoints -- the original 6
# unitids captured 2026-08-06, the 7 added when MT_IPEDS_UNITID_MAP was
# extended captured 2026-08-07, the 4 tribal colleges appended the
# same day when their own fast-follow gap closed, and Aaniiih Nakoda
# College / Chief Dull Knife College appended once their own new
# heuristic scrapers (misc_college_scrapers.R) went live. Both from the SAME year
# (2021) on purpose -- Pell share must be computed against enrollment from
# the same year as the grants data (see this file's source header), not
# the separately-fixtured 2023 "latest" enrollment used elsewhere.

test_that("parse_ipeds_he_pell_share computes a real recipients-over-enrollment ratio for all 19 institutions", {
  grants <- read.csv(test_path("fixtures", "fsa_mt_grants_2021.csv"))
  enrollment_raw <- read.csv(test_path("fixtures", "ipeds_mt_fall_enrollment_2021.csv"))
  enrollment <- parse_ipeds_he_enrollment(enrollment_raw, 2021)

  result <- parse_ipeds_he_pell_share(grants, enrollment, 2021)

  expect_equal(nrow(result), 19)
  msu <- result[result$Name == "Montana State University", ]
  expect_equal(msu$Pell_Recipient_Share, 2852 / 15083, tolerance = 1e-6)
  expect_equal(msu$Pell_Year, "2021")

  um <- result[result$Name == "University of Montana", ]
  expect_true(um$Pell_Recipient_Share > 0 && um$Pell_Recipient_Share < 1)

  skc <- result[result$Name == "Salish Kootenai College", ]
  expect_true(skc$Pell_Recipient_Share > 0 && skc$Pell_Recipient_Share < 1)
})

test_that("parse_ipeds_he_pell_share returns real NA when enrollment for that institution is missing or zero", {
  grants <- read.csv(test_path("fixtures", "fsa_mt_grants_2021.csv"))
  enrollment <- data.frame(Name = "Montana State University", Enrollment = 0, stringsAsFactors = FALSE)

  result <- parse_ipeds_he_pell_share(grants, enrollment, 2021)

  msu <- result[result$Name == "Montana State University", ]
  expect_true(is.na(msu$Pell_Recipient_Share))
})

test_that("parse_ipeds_he_pell_share returns an empty, correctly-shaped frame when given no rows", {
  result <- parse_ipeds_he_pell_share(data.frame(), data.frame(), 2021)
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("Name", "Pell_Recipient_Share", "Pell_Year"))
})

test_that("clean_fsa_value treats negative sentinel codes as real NA", {
  expect_true(is.na(clean_fsa_value(-1)))
  expect_equal(clean_fsa_value(500), 500)
})
