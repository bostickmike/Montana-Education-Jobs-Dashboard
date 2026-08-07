# Real fixtures: actual Montana (fips=30) responses from the Census Data
# API's SAIPE School District endpoint, captured 2026-08-06 (2022 data),
# across all three geography types (unified/elementary/secondary).

test_that("parse_census_saipe_child_poverty averages a real elementary+HS pair (Billings)", {
  unified <- parse_saipe_json(paste(readLines(test_path("fixtures", "saipe_mt_unified_2022.json"), warn = FALSE), collapse = "\n"))
  elem <- parse_saipe_json(paste(readLines(test_path("fixtures", "saipe_mt_elementary_2022.json"), warn = FALSE), collapse = "\n"))
  sec <- parse_saipe_json(paste(readLines(test_path("fixtures", "saipe_mt_secondary_2022.json"), warn = FALSE), collapse = "\n"))

  result <- parse_census_saipe_child_poverty(unified, elem, sec, 2022)

  expect_equal(nrow(result), length(MT_SAIPE_DISTRICT_MAP))
  billings <- result[result$District == "Billings Public Schools", ]
  # Real rates: Billings Elementary School District 10.6%, Billings High
  # School District 7.5% -- plain average, see this file's source header.
  expect_equal(round(billings$Child_Poverty_Rate, 5), round(mean(c(10.6, 7.5)) / 100, 5))
  expect_equal(billings$SAIPE_Year, 2022)
})

test_that("parse_census_saipe_child_poverty passes through an already-unified district's single real rate", {
  unified <- parse_saipe_json(paste(readLines(test_path("fixtures", "saipe_mt_unified_2022.json"), warn = FALSE), collapse = "\n"))
  elem <- parse_saipe_json(paste(readLines(test_path("fixtures", "saipe_mt_elementary_2022.json"), warn = FALSE), collapse = "\n"))
  sec <- parse_saipe_json(paste(readLines(test_path("fixtures", "saipe_mt_secondary_2022.json"), warn = FALSE), collapse = "\n"))

  result <- parse_census_saipe_child_poverty(unified, elem, sec, 2022)

  east_helena <- result[result$District == "East Helena Public Schools", ]
  expect_equal(east_helena$Child_Poverty_Rate, 7.0 / 100)
})

test_that("parse_census_saipe_child_poverty handles a county-named HS district (Lewistown -> Fergus High School District)", {
  unified <- parse_saipe_json(paste(readLines(test_path("fixtures", "saipe_mt_unified_2022.json"), warn = FALSE), collapse = "\n"))
  elem <- parse_saipe_json(paste(readLines(test_path("fixtures", "saipe_mt_elementary_2022.json"), warn = FALSE), collapse = "\n"))
  sec <- parse_saipe_json(paste(readLines(test_path("fixtures", "saipe_mt_secondary_2022.json"), warn = FALSE), collapse = "\n"))

  result <- parse_census_saipe_child_poverty(unified, elem, sec, 2022)

  lewistown <- result[result$District == "Lewistown Public Schools", ]
  expect_equal(round(lewistown$Child_Poverty_Rate, 5), round(mean(c(14.2, 10.7)) / 100, 5))
})

test_that("parse_census_saipe_child_poverty returns real NA for a district entirely missing this run", {
  elem <- parse_saipe_json(paste(readLines(test_path("fixtures", "saipe_mt_elementary_2022.json"), warn = FALSE), collapse = "\n"))
  sec <- parse_saipe_json(paste(readLines(test_path("fixtures", "saipe_mt_secondary_2022.json"), warn = FALSE), collapse = "\n"))
  elem_no_billings <- elem[!grepl("^Billings", elem$SD_NAME), ]
  sec_no_billings <- sec[!grepl("^Billings", sec$SD_NAME), ]

  result <- parse_census_saipe_child_poverty(data.frame(), elem_no_billings, sec_no_billings, 2022)

  billings <- result[result$District == "Billings Public Schools", ]
  expect_true(is.na(billings$Child_Poverty_Rate))
})

test_that("parse_census_saipe_child_poverty returns an empty, correctly-shaped frame when given no rows", {
  result <- parse_census_saipe_child_poverty(data.frame(), data.frame(), data.frame(), 2022)
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("District", "Child_Poverty_Rate", "SAIPE_Year"))
})

test_that("parse_saipe_json returns an empty data frame for a header-only response", {
  expect_equal(nrow(parse_saipe_json('[["SD_NAME","SAEPOVRAT5_17RV_PT"]]')), 0)
})
