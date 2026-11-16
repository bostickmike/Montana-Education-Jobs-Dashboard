# IPEDS_UNITID_MAP (ipeds_unitids.R) is state data for the edjobs federal HE
# fetchers; their own tests, with this map's fixtures, are in edjobs
# (tests/testthat/test-federal-he-acs-mt.R).

test_that("IPEDS_UNITID_MAP covers every registered institution except Missoula College's real permanent gap", {
  # Missoula College has no independent unitid in the Urban Institute's IPEDS
  # directory for Montana (not even a branch id); its figures are part of
  # University of Montana's reporting. Highlands College is in the map (its
  # salary and Pell are NA; enrollment is reported).
  registry <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
  expect_setequal(setdiff(registry$Institution, IPEDS_UNITID_MAP$Name), "Missoula College")
  expect_true(all(IPEDS_UNITID_MAP$Name %in% registry$Institution))
  expect_false(anyDuplicated(IPEDS_UNITID_MAP$Name) > 0)
  expect_type(IPEDS_UNITID_MAP$unitid, "integer")
})
