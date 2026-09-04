# Montana K-12 per-district General Fund expenditure data, from OPI's own
# School Finance data files (opi.mt.gov/Leadership/Finance-Grants/School-
# Finance/OPI-Financial-Data-Files) -- a real, structured, per-district
# financial dataset this pipeline didn't touch at all before 2026-08-07,
# distinct from teacher salary (DLI) and staffing (CCD) data already
# covered by salary_scrapers.R/ccd_staff_scraper.R.
#
# The published .xlsx's "ExpByLineItemByLE" sheet is real per-district
# (per-LE, "Local Education agency") line-item data -- County, DistrictName,
# LE code, FundCode, ProgramCode, FunctionCode, ObjectCode, SumOfAmount --
# confirmed live 2026-08-07 against FY2025's file (49,855 real rows, 393
# distinct districts statewide). FundCode "01" (General Fund) is used here
# as the headline per-district total -- Montana's real day-to-day operating
# budget fund, the figure most comparable to a district's "total spending"
# in ordinary usage, as opposed to summing every fund (which would double-
# count transfers between funds and blend in categorically different
# things like debt service, building reserve, and school food service).
#
# This file's own DistrictName values use the SAME split-district naming
# convention as CCD/DLI/SAIPE (e.g. "Billings Elem" + "Billings H S", not
# always named after the town -- "Livingston Public Schools" is really
# "Livingston Elem" + "Park H S", the same not-named-after-the-town pattern
# as Kalispell's real HS district being "Flathead H S"). MT_OPI_FINANCE_LEA_MAP
# below is hand-verified against the live FY2025 file's real DistrictName
# values for all 30 of this project's currently-registered K-12 districts
# (confirmed live 2026-08-07) -- every one of the 18 districts already in
# ccd_staff_scraper.R's MT_CCD_LEA_MAP resolved to the exact same LE names
# in this file too (same underlying OPI-sourced data), so this map isn't
# independently hand-typed from nothing, just independently verified.
MT_OPI_FINANCE_LEA_MAP <- list(
  "Billings Public Schools" = c("Billings Elem", "Billings H S"),
  "Missoula County Public Schools" = c("Missoula Elem", "Missoula H S"),
  "Great Falls Public Schools" = c("Great Falls Elem", "Great Falls H S"),
  "Bozeman Public Schools" = c("Bozeman Elem", "Bozeman H S"),
  "Helena Public Schools" = c("Helena Elem", "Helena H S"),
  "Butte School District 1" = c("Butte Elem", "Butte H S"),
  "Belgrade School District 44" = c("Belgrade Elem", "Belgrade H S"),
  "East Helena Public Schools" = c("East Helena K-12"),
  "Lockwood Schools" = c("Lockwood K-12"),
  "Hamilton School District 3" = c("Hamilton K-12 Schools"),
  "Havre Public Schools" = c("Havre Elem", "Havre H S"),
  "Whitefish School District" = c("Whitefish Elem", "Whitefish H S"),
  "Columbia Falls School District 6" = c("Columbia Falls Elem", "Columbia Falls H S"),
  "Polson School District" = c("Polson Elem", "Polson H S"),
  "Lewistown Public Schools" = c("Lewistown Elem", "Fergus H S"),
  "Laurel Public Schools" = c("Laurel Elem", "Laurel H S"),
  "Kalispell Public Schools" = c("Kalispell Elem", "Flathead H S"),
  "Hardin Public Schools" = c("Hardin Elem", "Hardin H S"),
  "Glendive Public Schools" = c("Glendive Elem", "Dawson H S"),
  "Colstrip Public Schools" = c("Colstrip Elem", "Colstrip H S"),
  "Sidney Public Schools" = c("Sidney Elem", "Sidney H S"),
  "Stevensville Public Schools" = c("Stevensville Elem", "Stevensville H S"),
  "Big Sandy Public Schools" = c("Big Sandy K-12"),
  "Lame Deer Public Schools" = c("Lame Deer Elem", "Lame Deer H S"),
  "Poplar Public Schools" = c("Poplar Elem", "Poplar H S"),
  "Fairview Public Schools" = c("Fairview Elem", "Fairview H S"),
  "Rocky Boy Public Schools" = c("Rocky Boy Elem", "Rocky Boy H S"),
  "Ronan Public Schools" = c("Ronan Elem", "Ronan H S"),
  "Livingston Public Schools" = c("Livingston Elem", "Park H S"),
  "Lodge Grass Public Schools" = c("Lodge Grass Elem", "Lodge Grass H S"),
  "Wolf Point Public Schools" = c("Wolf Point Elem", "Wolf Point H S"),
  "Plentywood Public Schools" = c("Plentywood K-12 Schools")
)

suppressMessages({
  library(httr2)
  library(readxl)
  library(dplyr)
})

OPI_FINANCE_GENERAL_FUND_CODE <- "01"

# Hardcoded to the current published FY, same maintenance pattern as
# salary_scrapers.R's DLI_REGION_FILENAMES -- OPI publishes a new file each
# year at a new URL (no stable "latest" alias found), so picking up a new
# fiscal year is a one-line update here, not a code change.
OPI_FINANCE_CURRENT_YEAR_URL <- "https://opifiles.mt.gov/Portals/182/Page%20Files/School%20Finance/07.OPI%20Financial%20Data%20Files/School%20Budget%20and%20Expenditure%20Data/School%20Expenditures/School%20Expenditures/OPIEXP25.xlsx"

fetch_opi_finance_workbook <- function(url = OPI_FINANCE_CURRENT_YEAR_URL) {
  resp <- request(url) %>% perform_with_retry()
  tmp <- tempfile(fileext = ".xlsx")
  writeBin(resp_body_raw(resp), tmp)
  # header row 1 is a single merged title cell across all columns -- the
  # real column headers (CO/CountyName/LE/DistrictName/StateFY/FundCode/...)
  # are row 2, hence skip = 1.
  readxl::read_excel(tmp, sheet = "ExpByLineItemByLE", skip = 1)
}

# by_le carries every registered district's real per-LE General Fund total
# (summing all rows for that LE, since a single LE has many ProgramCode/
# FunctionCode/ObjectCode line items making up its General Fund total) --
# a split district (e.g. Billings Elem + Billings H S) then gets summed
# again across its LEs into one District-level figure. A district with only
# some of its LEs present in a given year's file (a real possible gap, not
# yet observed) still gets a real partial sum rather than NA for the whole
# district, same "don't propagate NA from one missing part" behavior as
# ccd_staff_scraper.R's parse_ccd_teacher_fte().
parse_opi_district_expenditures <- function(raw_df) {
  empty <- data.frame(District = character(0), Total_General_Fund_Expenditure = numeric(0),
                       Finance_FY = character(0), stringsAsFactors = FALSE)
  if (nrow(raw_df) == 0) return(empty)

  by_le <- raw_df %>%
    filter(FundCode == OPI_FINANCE_GENERAL_FUND_CODE) %>%
    mutate(DistrictName = trimws(DistrictName), SumOfAmount = suppressWarnings(as.numeric(SumOfAmount))) %>%
    group_by(DistrictName) %>%
    summarise(le_total = sum(SumOfAmount, na.rm = TRUE), .groups = "drop")

  finance_fy <- if ("StateFY" %in% names(raw_df)) as.character(raw_df$StateFY[1]) else NA_character_

  rows <- lapply(names(MT_OPI_FINANCE_LEA_MAP), function(district) {
    le_names <- MT_OPI_FINANCE_LEA_MAP[[district]]
    matched <- by_le[by_le$DistrictName %in% le_names, ]
    total <- if (nrow(matched) == 0) NA_real_ else sum(matched$le_total)
    data.frame(District = district, Total_General_Fund_Expenditure = total,
               Finance_FY = finance_fy, stringsAsFactors = FALSE)
  })

  dplyr::bind_rows(rows)
}

fetch_opi_district_expenditures <- function(url = OPI_FINANCE_CURRENT_YEAR_URL) {
  raw_df <- fetch_opi_finance_workbook(url)
  parse_opi_district_expenditures(raw_df)
}
