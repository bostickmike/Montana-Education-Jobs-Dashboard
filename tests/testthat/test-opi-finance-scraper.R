# Real fixture: rows for all 30 registered districts' real LE names,
# trimmed from the actual FY2025 OPIEXP25.xlsx ("ExpByLineItemByLE" sheet,
# captured 2026-08-07) -- every General Fund (FundCode "01") row plus a
# 20-row sample of non-General-Fund rows (to exercise the fund filter),
# preserving the file's real 2-row header structure (merged title row,
# then real column names) so it round-trips through the same skip=1 read
# path the live fetch uses.

test_that("parse_opi_district_expenditures computes real General Fund totals for split and unified districts", {
  raw <- readxl::read_excel(test_path("fixtures", "opi_finance_fy2025_trimmed.xlsx"),
                             sheet = "ExpByLineItemByLE", skip = 1)

  result <- parse_opi_district_expenditures(raw)

  expect_equal(nrow(result), 30)

  # Billings Elem + Billings H S summed -- a real split district.
  billings <- result[result$District == "Billings Public Schools", ]
  expect_equal(billings$Total_General_Fund_Expenditure, 134234664)

  # East Helena K-12 -- a real unified (non-split) district, single LE.
  east_helena <- result[result$District == "East Helena Public Schools", ]
  expect_true(east_helena$Total_General_Fund_Expenditure > 0)

  # Livingston's real HS district is "Park H S", not "Livingston H S" --
  # the same not-named-after-the-town pattern as Kalispell/"Flathead H S".
  livingston <- result[result$District == "Livingston Public Schools", ]
  expect_equal(livingston$Total_General_Fund_Expenditure, 11404797)

  expect_true(all(result$Finance_FY == "2025"))
  expect_false(any(is.na(result$Total_General_Fund_Expenditure)))
})

test_that("parse_opi_district_expenditures excludes non-General-Fund rows from the total", {
  raw <- readxl::read_excel(test_path("fixtures", "opi_finance_fy2025_trimmed.xlsx"),
                             sheet = "ExpByLineItemByLE", skip = 1)
  general_fund_only <- raw[raw$FundCode == "01", ]

  result_full <- parse_opi_district_expenditures(raw)
  result_general_only <- parse_opi_district_expenditures(general_fund_only)

  # Identical totals whether or not the non-General-Fund sample rows are
  # present -- proves they're being filtered out, not silently summed in.
  expect_equal(result_full$Total_General_Fund_Expenditure, result_general_only$Total_General_Fund_Expenditure)
})

test_that("parse_opi_district_expenditures returns real NA for a district with zero matching rows, not an error", {
  raw <- readxl::read_excel(test_path("fixtures", "opi_finance_fy2025_trimmed.xlsx"),
                             sheet = "ExpByLineItemByLE", skip = 1)
  raw_missing_billings <- raw[!(raw$DistrictName %in% c("Billings Elem", "Billings H S")), ]

  result <- parse_opi_district_expenditures(raw_missing_billings)

  billings <- result[result$District == "Billings Public Schools", ]
  expect_true(is.na(billings$Total_General_Fund_Expenditure))
  # Every other district is untouched by Billings' absence.
  expect_false(any(is.na(result$Total_General_Fund_Expenditure[result$District != "Billings Public Schools"])))
})

test_that("parse_opi_district_expenditures returns an empty, correctly-shaped frame when given no rows", {
  result <- parse_opi_district_expenditures(data.frame())
  expect_equal(nrow(result), 0)
  expect_equal(names(result), c("District", "Total_General_Fund_Expenditure", "Finance_FY"))
})

test_that("MT_OPI_FINANCE_LEA_MAP covers a real subset of the registered districts, with every entry a real registry district", {
  # Was an exact 1:1 match until Wolf Point and Plentywood were added to
  # the registry (2026-08-07, the Apptegy/chromote build) -- same
  # deliberate "salary/finance coverage is a separate fast-follow" gap
  # already established for MT_DLI_DISTRICT_MAP's own 2 real gaps.
  registry <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  expect_true(all(names(MT_OPI_FINANCE_LEA_MAP) %in% registry$District))
  expect_setequal(setdiff(registry$District, names(MT_OPI_FINANCE_LEA_MAP)),
                   c("Wolf Point Public Schools", "Plentywood Public Schools"))
})

test_that("fetch_opi_district_expenditures downloads the workbook and parses it", {
  fixture_bytes <- readBin(test_path("fixtures", "opi_finance_fy2025_trimmed.xlsx"), "raw",
                            file.info(test_path("fixtures", "opi_finance_fy2025_trimmed.xlsx"))$size)
  httr2::local_mocked_responses(
    list(httr2::response(200,
      headers = list("Content-Type" = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
      body = fixture_bytes))
  )

  result <- fetch_opi_district_expenditures()

  expect_equal(nrow(result), 30)
  expect_equal(result$Total_General_Fund_Expenditure[result$District == "Billings Public Schools"], 134234664)
})
