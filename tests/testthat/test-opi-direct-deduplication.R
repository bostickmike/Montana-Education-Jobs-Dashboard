test_that("remove_opi_direct_duplicates removes only exact direct-board overlaps", {
  registry <- data.frame(
    District = c("Billings Public Schools", "East Helena Public Schools"),
    City = c("Billings", "East Helena"),
    stringsAsFactors = FALSE
  )
  direct_df <- data.frame(
    title = c("Elementary Teacher", "Math Teacher"),
    date_posted = as.Date(c("2026-08-01", "2026-08-02")),
    District = c("Billings Public Schools", "East Helena Public Schools"),
    stringsAsFactors = FALSE
  )
  opi_df <- data.frame(
    title = c(
      "ELEMENTARY teacher",
      "Elementary Teacher",
      "Science Teacher",
      "Math Teacher",
      "Elementary Teacher"
    ),
    date_posted = as.Date(c(
      "2026-08-01",
      "2026-08-02",
      "2026-08-01",
      "2026-08-02",
      "2026-08-01"
    )),
    location = c(
      "Billings",
      "Billings - Billings Christian School",
      "Billings - Billings Christian School",
      "East Helena, MT",
      "Butte"
    ),
    stringsAsFactors = FALSE
  )

  result <- remove_opi_direct_duplicates(opi_df, direct_df, registry)

  expect_equal(nrow(result), 3)
  expect_equal(
    result$location,
    c("Billings - Billings Christian School", "Billings - Billings Christian School", "Butte")
  )
})

test_that("remove_opi_direct_duplicates retains rows without a posted date", {
  registry <- data.frame(District = "Billings Public Schools", City = "Billings")
  direct_df <- data.frame(
    title = "Elementary Teacher",
    date_posted = as.Date("2026-08-01"),
    District = "Billings Public Schools"
  )
  opi_df <- data.frame(
    title = "Elementary Teacher",
    date_posted = as.Date(NA),
    location = "Billings"
  )

  expect_equal(nrow(remove_opi_direct_duplicates(opi_df, direct_df, registry)), 1)
})
