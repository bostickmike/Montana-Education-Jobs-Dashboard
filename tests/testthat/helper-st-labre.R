# St. Labre's Trakstar board (edjobs::fetch_trakstar_postings(), 0.85.0): real list pages read 2026-11-23, 38 openings
# over two pages, a third page empty.
mock_st_labre_board <- function(env = parent.frame()) {
  pages <- vapply(c("trakstar_stlabre_p1_2026-11-23.html", "trakstar_stlabre_p2_2026-11-23.html",
                    "trakstar_stlabre_p3_empty_2026-11-23.html"),
                  function(f) paste(readLines(test_path("fixtures", f), warn = FALSE), collapse = "\n"), character(1))
  httr2::local_mocked_responses(function(req) {
    k <- if (grepl("p=3", req$url, fixed = TRUE)) 3 else if (grepl("p=2", req$url, fixed = TRUE)) 2 else 1
    httr2::response(200, url = req$url, body = charToRaw(pages[[k]]))
  }, env = env)
}
