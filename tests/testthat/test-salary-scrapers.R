# Real fixtures: page 2 text extracted via pdftools from MT DLI's real
# "Teacher Compensation Report" regional PDFs -- South Central (Billings/
# Lockwood/Laurel/Hardin) and 4 Rivers (Bozeman/Helena/Butte/Belgrade/East
# Helena, including Helena's real all-ND row -- a genuinely non-
# disclosable district in the live report, not a synthetic edge case)
# captured 2026-08-06; North East (Sidney/Fairview/Poplar) and South East
# (Glendive/Colstrip) captured 2026-08-07 when MT_DLI_DISTRICT_MAP was
# extended -- the first time either region was needed, since none of the
# original 18 districts fell in them.

test_that("parse_dli_teacher_compensation extracts a real fully-disclosed district row", {
  page2 <- paste(readLines(test_path("fixtures", "dli_southcentral_page2.txt"), warn = FALSE), collapse = "\n")

  result <- parse_dli_teacher_compensation(page2, "Billings Public Schools")

  expect_equal(nrow(result), 1)
  expect_equal(result$Teacher_Count, 852)
  expect_equal(result$Teacher_Salary_10th_Pctile, 45400)
  expect_equal(result$Teacher_Avg_Salary, 66100)
  expect_equal(result$Teacher_Salary_90th_Pctile, 82600)
})

test_that("parse_dli_teacher_compensation returns real NA (not zero) for an all-ND-suppressed district", {
  # Real row: "Lockwood Public Schools   98   ND   ND   ND" -- a district
  # with a real disclosed teacher count but suppressed salary figures.
  page2 <- paste(readLines(test_path("fixtures", "dli_southcentral_page2.txt"), warn = FALSE), collapse = "\n")

  result <- parse_dli_teacher_compensation(page2, "Lockwood Public Schools")

  expect_equal(result$Teacher_Count, 98)
  expect_true(is.na(result$Teacher_Salary_10th_Pctile))
  expect_true(is.na(result$Teacher_Avg_Salary))
  expect_true(is.na(result$Teacher_Salary_90th_Pctile))
})

test_that("parse_dli_teacher_compensation handles Helena's real fully-suppressed row from the 4 Rivers region", {
  # Real row: "Helena Public Schools   423   ND   ND   ND" -- Montana's
  # second-largest district, genuinely non-disclosable in this report
  # despite its size (MTDLI's suppression rule isn't purely about district
  # size -- not something this scraper can second-guess).
  page2 <- paste(readLines(test_path("fixtures", "dli_4rivers_page2.txt"), warn = FALSE), collapse = "\n")

  result <- parse_dli_teacher_compensation(page2, "Helena Public Schools")

  expect_equal(result$Teacher_Count, 423)
  expect_true(is.na(result$Teacher_Avg_Salary))
})

test_that("parse_dli_teacher_compensation distinguishes East Helena from Helena on the same page", {
  # Regression: "Helena Public Schools" is a substring of nothing else here,
  # but East Helena's own row must not accidentally match a Helena lookup
  # or vice versa -- both real rows are on this same page.
  page2 <- paste(readLines(test_path("fixtures", "dli_4rivers_page2.txt"), warn = FALSE), collapse = "\n")

  east_helena <- parse_dli_teacher_compensation(page2, "East Helena Public Schools")
  expect_equal(east_helena$Teacher_Count, 103)
  expect_equal(east_helena$Teacher_Avg_Salary, 54900)
})

test_that("parse_dli_teacher_compensation returns zero rows (not an error) for a district not on this page", {
  page2 <- paste(readLines(test_path("fixtures", "dli_southcentral_page2.txt"), warn = FALSE), collapse = "\n")

  result <- parse_dli_teacher_compensation(page2, "Not A Real District")

  expect_equal(nrow(result), 0)
})

test_that("extract_dli_salary_year reads the real OPI GEMS source year from the page footer", {
  page2 <- paste(readLines(test_path("fixtures", "dli_southcentral_page2.txt"), warn = FALSE), collapse = "\n")
  expect_equal(extract_dli_salary_year(page2), "2022-23")
})

test_that("parse_dli_numeric_field converts ND and <5 to real NA, and strips commas from real numbers", {
  expect_true(is.na(parse_dli_numeric_field("ND")))
  expect_true(is.na(parse_dli_numeric_field("<5")))
  expect_equal(parse_dli_numeric_field("45,400"), 45400)
  expect_equal(parse_dli_numeric_field("852"), 852)
})

test_that("parse_dli_teacher_compensation extracts real North East and South East district rows", {
  ne_page2 <- paste(readLines(test_path("fixtures", "dli_northeast_page2.txt"), warn = FALSE), collapse = "\n")
  se_page2 <- paste(readLines(test_path("fixtures", "dli_southeast_page2.txt"), warn = FALSE), collapse = "\n")

  sidney <- parse_dli_teacher_compensation(ne_page2, "Sidney Public Schools")
  expect_equal(sidney$Teacher_Count, 74)
  expect_equal(sidney$Teacher_Avg_Salary, 56200)

  # Real row: "Glendive Public Schools   73   ND   ND   ND" -- fully
  # suppressed, same real pattern as Helena/Lockwood above, just in a
  # region this project didn't need until the 2026-08-07 K-12 expansion.
  glendive <- parse_dli_teacher_compensation(se_page2, "Glendive Public Schools")
  expect_equal(glendive$Teacher_Count, 73)
  expect_true(is.na(glendive$Teacher_Avg_Salary))
})

test_that("MT_DLI_DISTRICT_MAP covers a real subset of the registered districts, with every entry a real registry district", {
  # Not an exact 1:1 match, on purpose: Lame Deer Public Schools and Lodge
  # Grass Public Schools (both in the registry) are deliberately absent
  # from this map -- confirmed live 2026-08-07 that neither appears as a
  # row in ANY of MT DLI's 9 real regional PDFs (not suppressed as "ND"
  # within a listed row -- genuinely not listed at all), a real gap in
  # DLI's own source data, not a missed region guess. This test still
  # catches the real regression that matters: a name in
  # MT_DLI_DISTRICT_MAP that ISN'T a real registered district (a typo, a
  # stale entry after a rename) would silently never get looked up anywhere.
  registry <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  expect_true(all(names(MT_DLI_DISTRICT_MAP) %in% registry$District))
  expect_setequal(setdiff(registry$District, names(MT_DLI_DISTRICT_MAP)),
                   c("Lame Deer Public Schools", "Lodge Grass Public Schools"))
})
