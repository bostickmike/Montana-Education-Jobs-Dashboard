# he_campus_departments.csv (edjobs 0.34.0 place_he_postings(campus_departments =)): a department that is a fixed
# off-campus site -> its town. Each row needs a registry institution, a Census place in places.csv that is not a
# name two places share (those are never placed), and a source.
test_that("he_campus_departments.csv rows name a registry institution, a placeable town and a source", {
  dep <- read.csv(here::here("he_campus_departments.csv"), stringsAsFactors = FALSE)
  reg <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
  places <- read.csv(here::here("places.csv"), stringsAsFactors = FALSE)
  expect_named(dep, c("Institution", "Location", "Town", "Source"))
  expect_true(all(dep$Institution %in% reg$Institution))
  shared <- places$Town[duplicated(tolower(places$Town))]
  expect_true(all(dep$Town %in% places$Town & !dep$Town %in% shared))
  expect_true(all(nzchar(trimws(dep$Source))))
  expect_false(any(duplicated(dep[, c("Institution", "Location")])))
})
