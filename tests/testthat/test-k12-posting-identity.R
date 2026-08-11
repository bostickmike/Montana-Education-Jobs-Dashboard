test_that("normalize_posting_text preserves UTF-8 and repairs only invalid CP1252", {
  cp1252_title <- rawToChar(as.raw(c(
    0x4d, 0x61, 0x74, 0x68, 0x20, 0x96, 0x20,
    0x54, 0x65, 0x61, 0x63, 0x68, 0x65, 0x72
  )))
  valid_utf8_title <- "  Café — Teacher\r\n"

  expect_equal(normalize_posting_text(cp1252_title), "Math – Teacher")
  expect_equal(normalize_posting_text(valid_utf8_title), "Café — Teacher")
  expect_equal(
    normalize_posting_text(normalize_posting_text(valid_utf8_title)),
    normalize_posting_text(valid_utf8_title)
  )
  expect_equal(classify_k12_position(cp1252_title), "Teacher")
})

test_that("K-12 posting identities retain distinct postings and collapse stable repeats", {
  rows <- data.frame(
    title = rep("Math Teacher", 3),
    location = rep("Example High School", 3),
    date_posted = rep("2026-08-11", 3),
    url = c(
      "https://example.schoolspring.com/jobs/101",
      "https://example.schoolspring.com/jobs/102",
      "https://example.schoolspring.com/jobs/101"
    ),
    District = rep("Example Public Schools", 3),
    Posting_Source = rep("SchoolSpring (direct district board)", 3),
    stringsAsFactors = FALSE
  ) %>%
    add_k12_posting_identity()

  expect_equal(n_distinct(rows$Posting_ID), 2)
  expect_equal(rows$Posting_ID[1], rows$Posting_ID[3])
  expect_true(all(rows$Posting_Identity_Method == "Stable per-posting URL"))
})

test_that("OPI fallback identities keep indistinguishable observed rows explicit", {
  rows <- data.frame(
    title = rep("Elementary Teacher", 2),
    location = rep("Example City", 2),
    date_posted = rep("2026-08-11", 2),
    url = rep("https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx", 2),
    District = rep("Example City", 2),
    Posting_Source = rep("OPI Jobs for Teachers (statewide)", 2),
    stringsAsFactors = FALSE
  ) %>%
    add_k12_posting_identity()

  expect_equal(n_distinct(rows$Posting_ID), 2)
  expect_true(all(grepl("^fallback:opi-fallback", rows$Posting_ID)))
  expect_true(all(grepl("^OPI fallback:", rows$Posting_Identity_Method)))
})

test_that("K-12 aggregates and New This Week use posting identity", {
  current <- data.frame(
    title = rep("Science Teacher", 3),
    location = rep("Example High School", 3),
    date_posted = rep("2026-08-11", 3),
    url = c(
      "https://example.schoolspring.com/jobs/201",
      "https://example.schoolspring.com/jobs/202",
      "https://example.schoolspring.com/jobs/201"
    ),
    District = rep("Example Public Schools", 3),
    Posting_Source = rep("SchoolSpring (direct district board)", 3),
    Archive_Date = as.Date("2026-08-11"),
    position = "Teacher",
    Category = "Science Education",
    Broad_Category = "Science",
    stringsAsFactors = FALSE
  ) %>%
    add_k12_posting_identity()

  totals <- summarize_k12_posting_counts(current)
  expect_equal(totals$sum, 2)

  prior <- current[1, ]
  prior$Archive_Date <- as.Date("2026-08-04")
  new_rows <- find_k12_new_postings(bind_rows(prior, current))

  expect_equal(nrow(new_rows), 1)
  expect_equal(new_rows$Posting_ID, current$Posting_ID[2])
})
