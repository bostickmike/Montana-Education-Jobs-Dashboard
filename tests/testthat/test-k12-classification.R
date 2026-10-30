
test_that("classify_k12_position doesn't let the precedence overhaul swallow real roles", {
  # Bare "Intern" matched inside "Internal Applicants Only".
  expect_equal(classify_k12_position("Special Education Teacher - Internal Applicants"), "Teacher")
  expect_equal(classify_k12_position("Bus Driver (Internal Candidates Only)"), "Transportation")
  expect_equal(classify_k12_position("Technology Intern"), "Support Services")
  expect_equal(classify_k12_position("Casper Mountain Science Program Intern"), "Support Services")
  # "Technician" was checked ahead of Custodial/Transportation/Food Services.
  expect_equal(classify_k12_position("Dean Morgan Cafeteria Technician"), "Food Services")
  expect_equal(classify_k12_position("Maintenance- HVAC Technician"), "Custodial/Maintenance")
  expect_equal(classify_k12_position("Facility Technician - Carpenter [TS07]"), "Custodial/Maintenance")
  expect_equal(classify_k12_position("Transportation Parts Technician"), "Transportation")
  expect_equal(classify_k12_position("Seasonal Database Technician - Districtwide"), "Support Services")
  # Ensemble directors and Drivers Ed are teaching jobs.
  expect_equal(classify_k12_position("Middle School Band Teacher / Band Director"), "Teacher")
  expect_equal(classify_k12_position("Choir Director"), "Teacher")
  expect_equal(classify_k12_position("Drivers Education Teacher"), "Teacher")
  expect_equal(classify_k12_position("Athletic Director"), "Administration")
})
