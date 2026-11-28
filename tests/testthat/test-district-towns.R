# The districts' CCD towns (Mt_Ed_Jobs/district_towns.csv, edjobs refresh_district_towns(), 2026-11-28): every
# registry district with an NCES id has its row, so fill_k12_locations() can place its postings.

test_that("every registry district with an NCES id has a district-towns row", {
  towns <- read_district_towns(here::here("Mt_Ed_Jobs", "district_towns.csv"))
  reg <- read_k12_registry(here::here("k12_district_registry.csv"))
  ids <- reg$NCES_LEAID[nzchar(reg$NCES_LEAID)]
  expect_length(setdiff(ids, towns$NCES_LEAID), 0)
  expect_equal(names(towns), c("NCES_LEAID", "Office_Town", "School_Towns", "CCD_Year"))
  expect_false(anyNA(towns$Office_Town))
})

test_that("the two blank places of 2026-11-26 get their one-town districts' towns; a given place is kept", {
  towns <- read_district_towns(here::here("Mt_Ed_Jobs", "district_towns.csv"))
  reg <- read_k12_registry(here::here("k12_district_registry.csv"))
  ids <- setNames(reg$NCES_LEAID, reg$District)
  # The two blank rows in Archivek12_Data/combined_2026-11-26.csv (AppliTrack), and an OPI row whose town is kept.
  df <- data.frame(District = c("Big Sandy Public Schools", "Fort Benton School District 1", "Ronan Public Schools"),
                   location = c(NA, "", "Ronan"), stringsAsFactors = FALSE)
  out <- fill_k12_locations(df, towns, ids)
  expect_equal(out$location, c("Big Sandy", "Fort Benton", "Ronan"))
  expect_equal(attr(out, "location_changes")[["filled"]], 2L)
})
