# Unit tests for scrape_helpers.R's retry predicate. (The retry loop itself
# isn't exercised here: httr2 1.0.0 returns mocked responses before its
# retry loop runs, so a mock can't simulate "520, then 200".)

test_that("is_transient_gateway_error retries rate limits and gateway/Cloudflare 5xx, not real failures", {
  status_is_transient <- function(code) is_transient_gateway_error(httr2::response(status_code = code))
  for (code in c(429, 502, 503, 504, 520, 521, 522, 523, 524)) {
    expect_true(status_is_transient(code), info = code)
  }
  for (code in c(200, 403, 404, 500)) {
    expect_false(status_is_transient(code), info = code)
  }
})
