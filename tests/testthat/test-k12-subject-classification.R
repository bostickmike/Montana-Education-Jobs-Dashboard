test_that("classify_k12_subject recognizes the literal 'Technical Education' phrase, not just 'Tech Ed'", {
  expect_equal(classify_k12_subject("Technical Education Teacher"), "Technical Education")
})

test_that("classify_k12_subject matches the plural 'Family and Consumer Sciences'", {
  expect_equal(
    classify_k12_subject("Rocky Boy School 7-12 Family and Consumer Sciences"),
    "Family and Consumer Science"
  )
})

test_that("classify_k12_subject recognizes 'Head Start' and hyphenated 'Pre-School' as Early Childhood", {
  expect_equal(
    classify_k12_subject(c("Head Start Teacher", "Pre-School Teacher")),
    c("Early Childhood Education", "Early Childhood Education")
  )
})

test_that("classify_k12_subject treats 'Guest Teacher' as substitute teaching", {
  expect_equal(classify_k12_subject("Guest Teacher"), "Substitute Teaching")
})

test_that("classify_k12_subject recognizes 'Vo/Ag' as Agriculture Education", {
  expect_equal(classify_k12_subject("RHS Teacher ~ Vo/Ag 2026-2027"), "Agriculture Education")
})

test_that("classify_k12_position routes clerical staff with department names to Staff rather than Teacher", {
  expect_equal(classify_k12_position("General Secretary - Library"), "Staff")
  expect_equal(classify_k12_position("Secretary - Coordinator of Language Arts"), "Staff")
  expect_equal(classify_k12_position("Library Media Specialist"), "Teacher")
})

test_that("classify_k12_subject recognizes Indigenous languages and EL titles as Language Education", {
  expect_equal(
    classify_k12_subject(c(
      "Shoshone Language Teacher",
      "RMS Teacher ~ Salish and/or Kootenai Language ~ 2026-27",
      "Salish Teacher",
      "Cree Enhancement Program-Project Coordinator/Teacher",
      "EL Teacher - Desert View / Overland"
    )),
    rep("Language Education", 5)
  )
})

test_that("classify_k12_subject recognizes SE - TEACHER variants as Special Education", {
  expect_equal(classify_k12_subject("SE - TEACHER"), "Special Education - General")
  expect_equal(classify_k12_subject("SE - TEACHER LS"), "Special Education - Resource/Life Skills")
  expect_equal(classify_k12_subject("Disabilities Educator"), "Special Education - General")
  expect_equal(classify_k12_subject("Sp Ed Extended Resource Teacher (K-2)"), "Special Education - Resource/Life Skills")
})

test_that("classify_k12_subject recognizes Pre-K, Toddler, and SACC titles as Early Childhood Education", {
  expect_equal(
    classify_k12_subject(c("Pre -K Teacher", "Toddler Teacher", "SACC Lead Teacher", "Daycare Lead Teacher")),
    rep("Early Childhood Education", 4)
  )
})

test_that("classify_k12_subject recognizes Title I and literacy roles as English Language Arts", {
  expect_equal(
    classify_k12_subject(c("Title I Teacher", "Title One Teacher", "Reading Recovery Teacher", "Secondary Literacy Teacher")),
    rep("English Language Arts Education", 4)
  )
})

test_that("classify_k12_subject recognizes Drivers Ed, Woodworking, and CNA roles", {
  expect_equal(classify_k12_subject("Drivers Education Teacher"), "Technical Education")
  expect_equal(classify_k12_subject("9-12 Woodworking Teacher"), "Technical Education")
  expect_equal(classify_k12_subject("Certified Nursing Assistant (CNA) Instructor"), "Health Science")
})
