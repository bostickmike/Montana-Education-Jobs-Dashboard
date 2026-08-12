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

test_that("no known name typos survive into the committed summary data", {
  # Unlike Wyoming -- whose canonicalize_k12_district()/
  # canonicalize_he_institution() fix several confirmed real-data
  # misspellings (e.g. "Commmunity", "Lanugage", "Distrcit") -- Montana's
  # versions in k12_he_classification.R are still empty pass-throughs as of
  # this writing: no district/institution name typo has been confirmed in
  # Montana's own scraped data yet (see that file's comments). Asserting
  # against WY-specific typo strings here would test nothing real for
  # Montana. Skipping with an explicit reason rather than inventing a
  # placeholder assertion; add a real one here (and a matching canonicalize_*
  # entry) the moment an actual scraped-data typo turns up.
  skip(paste(
    "canonicalize_k12_district()/canonicalize_he_institution() are still",
    "empty pass-throughs -- no confirmed Montana name typo to test yet"
  ))
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
