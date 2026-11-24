# Mt_ED_Jobs.Rmd reads most direct boards with edjobs::scrape_registry_platforms() over MT_DIRECT_BOARD_PLATFORMS
# (state_config.R, 2026-11-24). A registry platform in neither that list nor a block of its own would be skipped
# with no error, so every platform must be in exactly one place.

test_that("every registry platform is read once: by scrape_registry_platforms() or by its own block", {
  registry <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  own_block <- c("AppliTrack", "SchoolSpring", "TylerPortico", "TedK12", "RedRoverK12",   # their own blocks
                 "Apptegy", "ApptegyPageBuilder", "ApptegyBespoke",                      # the Apptegy batch
                 "OPIOnly")                                                              # OPI's feed only
  listed <- unlist(MT_DIRECT_BOARD_PLATFORMS, use.names = FALSE)
  expect_false(anyDuplicated(listed) > 0)
  expect_length(intersect(listed, own_block), 0)
  expect_setequal(setdiff(unique(registry$Platform), own_block), listed)
})

test_that("each listed platform resolves to a scraper call for every one of its registry rows", {
  registry <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  rows <- registry[registry$Platform %in% unlist(MT_DIRECT_BOARD_PLATFORMS), ]
  for (d in rows$District) expect_false(is.null(resolve_scraper_call(d)), info = d)
})

test_that("Lima's live check reads the Thrillshare feed (the function's default), not its home page", {
  call <- resolve_scraper_call("Lima School District #12")
  expect_identical(call$fn, "fetch_lima_postings")
  expect_length(call$args, 0)
})
