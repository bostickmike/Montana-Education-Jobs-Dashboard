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
