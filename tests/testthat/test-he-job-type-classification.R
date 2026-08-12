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

test_that("a bare 'Part-Time' with no faculty-role word doesn't get counted as adjunct faculty", {
  # Regression: the Adjunct/Part-Time rule used to match on "Part-Time"
  # alone, so real non-faculty postings like a part-time custodian or a
  # part-time development officer were miscounted into the faculty pool.
  # It should still fall through to whatever role the title actually names.
  expect_equal(
    classify_he_job_type(c(
      "Custodian 1-Part-Time",
      "Major Gift Officer – Part-time",
      "Part-Time Clinical Resource Registered Nurse (CRRN)",
      "Part Time Faculty"
    )),
    c(
      "Support Services",
      "Professional",
      "Healthcare",
      "Adjunct/Part-Time Faculty"
    )
  )
})
