# Ported from the Wyoming Education Jobs Dashboard's test-data-integrity.R.
# These tests read the actual committed summary CSVs (not fixtures), so they
# double as a data-contract check on whatever was last regenerated. They're
# expected to keep passing as real postings come and go -- what they guard
# against is a structural regression in *how* the summaries are built. This
# file is almost entirely state-agnostic and applies to Montana unchanged,
# pointed at Mt_Ed_Jobs/ instead of Wy_Ed_Jobs/.

read_summary <- function(name) {
  path <- here::here("Mt_Ed_Jobs", name)
  skip_if_not(file.exists(path), paste(name, "not found -- skipping"))
  df <- read.csv(path)
  # Drop write.csv()'s row-index column -- it's unique per row, so leaving
  # it in would make every "group" a single row and defeat the whole point
  # of grouping by the real category/date columns below.
  df[, setdiff(names(df), "X"), drop = FALSE]
}

expect_total_matches_sum_of_parts <- function(df, group_col, value_col = "sum") {
  # Regression for the HE longitudinal double-counting bug (originally found
  # in Wyoming, structurally possible here too): the pre-aggregated "Total"
  # row for each (category, date, ...) must equal the sum of that same
  # combination's individual institution/district rows, not some other
  # value. This alone doesn't catch a consumer (like app.R) summing Total
  # together with the individual rows -- that's covered by
  # test-app-reactives.R -- but it does catch the aggregation step itself
  # ever producing a Total row that's out of sync with its parts.
  by_cols <- setdiff(names(df), c(group_col, value_col))
  mismatches <- df %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(by_cols))) %>%
    dplyr::summarize(
      total_row = sum(.data[[value_col]][.data[[group_col]] == "Total"]),
      parts_sum = sum(.data[[value_col]][.data[[group_col]] != "Total"]),
      .groups = "drop"
    ) %>%
    dplyr::filter(total_row != parts_sum)
  expect_equal(nrow(mismatches), 0)
}

test_that("allsum_he.csv: Total row equals sum of individual institutions", {
  d <- read_summary("allsum_he.csv")
  expect_total_matches_sum_of_parts(d, "Institution")
})

test_that("allnow_he.csv: Total row equals sum of individual institutions", {
  d <- read_summary("allnow_he.csv")
  expect_total_matches_sum_of_parts(d, "Institution", value_col = "Sum")
})

test_that("allsum.csv: Total row equals sum of individual districts", {
  d <- read_summary("allsum.csv")
  expect_total_matches_sum_of_parts(d, "District")
})

test_that("allnow.csv: Total row equals sum of individual districts", {
  d <- read_summary("allnow.csv")
  expect_total_matches_sum_of_parts(d, "District", value_col = "Sum")
})

test_that("OPI's Pray/Emigrant label carries Arrowhead's name, in the function and the committed data", {
  # Before 2026-11-01 OPI rows were matched to a district by town through the registry. Arrowhead #75's row was
  # taken out 2026-11-23, so a rebuild left its OPI postings of 08-06 to 08-25 under "Pray/Emigrant" while its
  # 09-01 board rows kept the district's name: one district under two names in the weekly totals.
  expect_equal(canonicalize_k12_district(c("Pray/Emigrant", "PRAY/EMIGRANT, MT", "Billings Public Schools")),
               c("Arrowhead Elementary School District #75", "Arrowhead Elementary School District #75",
                 "Billings Public Schools"))
  totals <- read_summary("k12_district_weekly_totals.csv")
  expect_false(any(totals$District == "Pray/Emigrant"))
})

# Regression for the encoding bug (originally found in Wyoming) where
# fix_title_encoding() only fixed a private copy of the title used inside
# classify_k12_position()/classify_k12_subject(), never the title actually
# shipped to the app -- a title with a raw Windows-1252 byte (e.g. an en
# dash) from any non-Applitrack source would classify fine but still display
# mangled. Checking the committed CSVs directly (rather than just
# unit-testing fix_title_encoding() in isolation) is what actually catches a
# future call site forgetting to apply the fix, the same way the typo checks
# above catch a canonicalization call site being skipped.
test_that("combinedclean.csv titles have no invalid-encoding or mojibake characters", {
  d <- read_summary("combinedclean.csv")
  expect_true(all(validEnc(d$title)))
  expect_false(any(grepl("�", d$title)))
})

test_that("k12jobanalysis.csv titles have no invalid-encoding or mojibake characters", {
  d <- read_summary("k12jobanalysis.csv")
  expect_true(all(validEnc(d$title)))
  expect_false(any(grepl("�", d$title)))
})
