
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

test_that("OPI-style subject-only titles are teaching jobs with the right subject", {
  titles <- c("Elementary Curriculum", "Special Education", "Music", "Physical Ed", "Social Studies (Broadfield)",
              "World Languages", "Health Enhancement", "Reading", "Psychology", "K - 12 Librarian")
  expect_equal(unname(classify_k12_position(titles)), rep("Teacher", length(titles)))
  expect_equal(unname(classify_k12_subject(c("Physical Ed", "Health Enhancement", "Reading", "World Languages", "Psychology"))),
               c("Physical Education", "Physical Education", "English Language Arts Education", "Language Education", "Social Studies Education"))
  # Subject words alone don't make an advisor/assistant/builder role a teacher.
  expect_false(classify_k12_position("FFA Advisor") == "Teacher")
  expect_false(classify_k12_position("Lego League/ Robotics Activity") == "Teacher")
  expect_false(classify_k12_position("GRHS Theater Set Design Builder") == "Teacher")
  expect_equal(classify_k12_position("Special Education Case Manager"), "Teacher")
})

test_that("CTE-prefixed subjects reach their specific subject, not Technical Education", {
  expect_equal(classify_k12_subject("CTE – Agricultural Education"), "Agriculture Education")
  expect_equal(classify_k12_subject("CTE – Business and Marketing Education"), "Business and Economics")
  expect_equal(classify_k12_subject("CTE – Family and Consumer Sciences"), "Family and Consumer Science")
  expect_equal(classify_k12_subject("CTE – Industrial Technology Education"), "Technical Education")
  expect_equal(classify_k12_subject("CTE Teacher"), "CTE Teacher")
  expect_equal(classify_k12_subject("Special Educaiton Teacher"), "Special Education - General")
})

test_that("classify_k12_position routes common non-teaching roles out of Other", {
  expect_equal(classify_k12_position("Special Programs Education Assistant"), "Paraprofessional")
  expect_equal(classify_k12_position("Crossing Guard"), "Support Services")
  expect_equal(classify_k12_position("School Nurse"), "Support Services")
  expect_equal(classify_k12_position("Nurse Educator"), "Teacher")
  expect_equal(classify_k12_position("General Secretary- Counseling"), "Staff")
  expect_equal(classify_k12_position("Seasonal Grounds Worker"), "Custodial/Maintenance")
  expect_equal(classify_k12_position("Superintendent"), "Administration")
  expect_equal(classify_k12_position("Dean Morgan Cafeteria Technician"), "Food Services")
  expect_equal(classify_k12_position("STIPEND - SWIMMING ASSISTANT JV"), "Athletics")
  expect_equal(classify_k12_position("Substiture Buffalo Bus Route Driver"), "Substitute")
  expect_equal(classify_k12_position("Substance Abuse/Mental Health Services Grant Coordinator"), "Administration")
  expect_equal(classify_k12_position("Test Preparation Teacher"), "Teacher")
})

test_that("is_placeholder_posting drops non-jobs but keeps standing applicant pools", {
  expect_true(all(is_placeholder_posting(c("Sample Certified Position", "Future Classified Positions",
    "Use This Template to Create An Account For Future Certified Openings", "Student Teaching Opportunities",
    "No open positions at this time", "Job Title", "No Jobs"))))
  expect_false(any(is_placeholder_posting(c("Applicant Pool - Substitute Teacher", "MS Science Teacher Job Description",
    "Elementary Teacher", NA))))
})
