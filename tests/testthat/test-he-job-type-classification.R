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

test_that("classify_he_faculty_category prevents precedence-order misclassifications", {
  # 1. Political Science and Social Science must not be stolen by Science
  expect_equal(classify_he_faculty_category("Assistant Professor of Political Science"), "Social Science")
  expect_equal(classify_he_faculty_category("Gen Ed - Social Sciences Non-Tenure Track Faculty"), "Social Science")

  # 2. Health Sciences must not be stolen by Science
  expect_equal(classify_he_faculty_category("Gen Ed – Health Sciences Non-Tenure Track Faculty"), "CTE - Health Sciences")
  expect_equal(classify_he_faculty_category("Instructor, General Health Sciences"), "CTE - Health Sciences")

  # 3. Zoology must land in Science, not Business & Computing
  expect_equal(classify_he_faculty_category("Asst Professor - Sensory Biology/Zoology & Physiology"), "Science")
  expect_equal(classify_he_faculty_category("Zoology/Biology Instructor"), "Science")

  # 4. Agricultural Economics must land in Business & Computing, not Trades & Engineering
  expect_equal(
    classify_he_faculty_category("Agricultural Economics & Economics Non-Tenure Track Faculty"),
    "CTE - Business & Computing"
  )

  # 5. Hospitality in College of Business must land in Culinary/Hospitality
  expect_equal(
    classify_he_faculty_category("Hospitality Instructors for the Jake Jabs College of Business"),
    "Culinary/Hospitality"
  )

  # 6. Languages and Humanities
  expect_equal(classify_he_faculty_category("Japanese Non-Tenure Track Faculty"), "Language")
  expect_equal(classify_he_faculty_category("Arabic Non-Tenure Track Faculty"), "Language")
  expect_equal(classify_he_faculty_category("Chinese Non-Tenure Track Faculty"), "Language")
  expect_equal(classify_he_faculty_category("Philosophy Instructor"), "Humanities")
  expect_equal(classify_he_faculty_category("Texts and Critics Instructor"), "Humanities")

  # 7. Trades & Architecture
  expect_equal(classify_he_faculty_category("Instructor of Architecture Non-Tenure Track Faculty"), "CTE - Trades & Engineering")
  expect_equal(classify_he_faculty_category("Commercial Driver's License Instructor"), "CTE - Trades & Engineering")
})
