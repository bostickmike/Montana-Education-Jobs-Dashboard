
test_that("HE faculty category substring misfires stay fixed", {
  # "latin" inside "Gallatin College"
  expect_equal(classify_he_faculty_category("Aviation Non-Tenure Track Faculty - Gallatin College (Applicant Pool)"), "CTE - Trades & Engineering")
  expect_equal(classify_he_faculty_category("Latin Instructor"), "Language")
  # "ems" inside "Systems"
  expect_equal(classify_he_faculty_category("Information Systems Instructor"), "CTE - Business & Computing")
  expect_equal(classify_he_faculty_category("Adjunct Faculty - EMS (Workforce)"), "CTE - Health Sciences")
  # Criminal Justice ahead of bare "law"
  expect_equal(classify_he_faculty_category("Law Enforcement Academy, Non-Tenure Track Faculty"), "Criminal Justice")
  expect_equal(classify_he_faculty_category("Assistant Professor - Zoology & Physiology"), "Science")
  expect_equal(classify_he_faculty_category("Instructional Design Librarian"), "Education")
})

test_that("HE job type keeps staff and child-center aides out of faculty", {
  expect_equal(classify_he_job_type("Classroom Aide/Substitute Teacher (Part-Time)"), "Support Services")
  expect_equal(classify_he_job_type("Academic Instructional Technologist"), "Professional")
  expect_equal(classify_he_job_type("Instructional Professor, Assistant - Organizational Behavior"), "Instructor/Teacher/Faculty")
  expect_equal(classify_he_job_type("Postdoctoral Researcher"), "Instructor/Teacher/Faculty")
  expect_equal(classify_he_job_type("Livestock Judging Coach/Recruiter"), "Coaching or Athletics")
  expect_equal(classify_he_job_type("Academic Support Center (ASC) Assistant Director"), "Management")
  expect_equal(classify_he_job_type("Student Assistant, Music"), "Student Positions")
  expect_equal(classify_he_job_type("Barista, Café 1968 (Part-Time)"), "Culinary")
})
