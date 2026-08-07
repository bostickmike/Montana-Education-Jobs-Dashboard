# append_weekly_rows()/check_total_matches_parts() unit tests. Ported from
# the Wyoming Education Jobs Dashboard's test-history-accumulator.R --
# these 8 are pure and state-agnostic (synthetic data, no real archive
# needed), so they port directly. Wyoming's file also has two equivalence
# tests proving the incremental-append path reproduces a full from-scratch
# archive rebuild (rebuild_k12_history_from_archive.R /
# rebuild_he_history_from_archive.R) -- not ported yet, since that needs at
# least 2 real archived weeks on disk to compare against and Montana's
# pipeline hasn't produced any archive history yet. Add those two tests
# (and the rebuild scripts they check against) once Archivek12_Data/ and
# Archived_HE_Data/ have real accumulated weeks.

test_that("append_weekly_rows bootstraps from a missing file", {
  new_rows <- data.frame(District = c("A", "B"), Archive_Date = "2026-08-06", n = c(1, 2))
  tmp <- withr::local_tempfile()
  expect_false(file.exists(tmp))

  result <- append_weekly_rows(tmp, new_rows)
  expect_equal(nrow(result), 2)
  expect_equal(result$Archive_Date, c("2026-08-06", "2026-08-06"))
})

test_that("append_weekly_rows appends onto an existing file without disturbing prior weeks", {
  tmp <- withr::local_tempfile()
  existing <- data.frame(District = c("A", "B"), Archive_Date = "2026-07-30", n = c(5, 6))
  write.csv(existing, tmp, row.names = FALSE)

  new_rows <- data.frame(District = c("A", "B"), Archive_Date = "2026-08-06", n = c(1, 2))
  result <- append_weekly_rows(tmp, new_rows)

  expect_equal(nrow(result), 4)
  expect_setequal(unique(result$Archive_Date), c("2026-07-30", "2026-08-06"))
  expect_equal(result$n[result$Archive_Date == "2026-07-30" & result$District == "A"], 5)
})

test_that("append_weekly_rows is idempotent -- a same-day re-run replaces, not duplicates, that day", {
  tmp <- withr::local_tempfile()
  existing <- data.frame(District = c("A", "B"), Archive_Date = c("2026-07-30", "2026-08-06"), n = c(5, 1))
  write.csv(existing, tmp, row.names = FALSE)

  rerun_rows <- data.frame(District = "A", Archive_Date = "2026-08-06", n = 99)
  result <- append_weekly_rows(tmp, rerun_rows)

  expect_equal(nrow(result), 2)
  expect_equal(result$n[result$Archive_Date == "2026-08-06"], 99)
  expect_equal(result$n[result$Archive_Date == "2026-07-30"], 5)
})

test_that("append_weekly_rows refuses to append rows with more than one Archive_Date", {
  new_rows <- data.frame(District = c("A", "B"), Archive_Date = c("2026-08-06", "2026-08-07"), n = c(1, 2))
  expect_error(append_weekly_rows(withr::local_tempfile(), new_rows), "exactly one")
})

test_that("append_weekly_rows fails loudly on a column mismatch instead of writing a jagged file", {
  tmp <- withr::local_tempfile()
  write.csv(data.frame(District = "A", Archive_Date = "2026-07-30", n = 5), tmp, row.names = FALSE)

  new_rows <- data.frame(District = "A", Archive_Date = "2026-08-06", Category = "Math", n = 1)
  expect_error(append_weekly_rows(tmp, new_rows), "column mismatch")
})

test_that("append_weekly_rows handles a genuinely empty new-rows data frame without erroring", {
  tmp <- withr::local_tempfile()
  write.csv(data.frame(District = "A", Archive_Date = "2026-07-30", n = 5), tmp, row.names = FALSE)

  empty <- data.frame(District = character(0), Archive_Date = character(0), n = numeric(0))
  result <- append_weekly_rows(tmp, empty)
  expect_equal(nrow(result), 1)
})

test_that("check_total_matches_parts passes when the Total genuinely equals the sum of parts", {
  total <- data.frame(Broad_Category = "Math", Archive_Date = "2026-08-06", District = "Total", sum = 5)
  parts <- data.frame(Broad_Category = "Math", Archive_Date = "2026-08-06",
                       District = c("A", "B"), sum = c(2, 3))
  expect_true(check_total_matches_parts(total, parts, group_cols = c("Broad_Category", "Archive_Date")))
})

test_that("check_total_matches_parts stops when the Total doesn't equal the sum of parts", {
  total <- data.frame(Broad_Category = "Math", Archive_Date = "2026-08-06", District = "Total", sum = 999)
  parts <- data.frame(Broad_Category = "Math", Archive_Date = "2026-08-06",
                       District = c("A", "B"), sum = c(2, 3))
  expect_error(check_total_matches_parts(total, parts, group_cols = c("Broad_Category", "Archive_Date")),
               "don't equal the sum")
})
