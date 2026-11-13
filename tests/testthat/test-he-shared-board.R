# UM's NEOGOV board carries other institutions' postings; he_institution_registry.csv's
# SharesBoard rows split it by Location (edjobs::assign_shared_board_institutions(),
# 0.11.0). The split runs outside safe_scrape(), so a bad pattern would stop the
# render (2026-11-13 review).
reg <- read.csv(here::here("he_institution_registry.csv"), stringsAsFactors = FALSE)
shared <- reg[reg$Platform == "SharesBoard" & !is.na(reg$Location_Pattern) & nzchar(reg$Location_Pattern), ]

test_that("every Location_Pattern is a valid regular expression", {
  expect_gt(nrow(shared), 0)
  for (p in shared$Location_Pattern) expect_silent(grepl(p, "x"))
})

test_that("every SharesBoard row names a board some institution owns", {
  boards <- reg$Feed_URL[reg$Platform != "SharesBoard"]
  expect_true(all(reg$Feed_URL[reg$Platform == "SharesBoard"] %in% boards))
})

test_that("on UM's real board page, no Location matches two institutions' patterns", {
  html <- paste(readLines(test_path("fixtures", "schooljobs_ummissoula_joblist_2026-10-30.html"), warn = FALSE), collapse = "\n")
  loc <- unique(stats::na.omit(parse_neogov_html(html, "https://www.schooljobs.com")$Location))
  expect_gt(length(loc), 0)
  on_board <- shared[shared$Feed_URL == "ummissoula", ]
  n_hits <- vapply(loc, function(l) sum(vapply(on_board$Location_Pattern, grepl, logical(1), x = l)), integer(1))
  expect_true(all(n_hits <= 1), info = paste(loc[n_hits > 1], collapse = "; "))
  expect_true(any(grepl(on_board$Location_Pattern[on_board$Institution == "Helena College"], loc)))
})
