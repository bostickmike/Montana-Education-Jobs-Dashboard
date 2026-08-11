test_that("classify_he_job_type separates full-time faculty from adjunct and part-time roles", {
  expect_equal(
    classify_he_job_type(c(
      "Assistant Professor of Biology",
      "Adjunct Instructor, Biology",
      "Part-Time Mathematics Instructor"
    )),
    c(
      "Instructor/Teacher/Faculty",
      "Adjunct/Part-Time Faculty",
      "Adjunct/Part-Time Faculty"
    )
  )
})
