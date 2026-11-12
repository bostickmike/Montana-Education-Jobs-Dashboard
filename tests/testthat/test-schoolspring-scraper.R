# Real detail records captured 2026-11-03 from api.schoolspring.com/api/Jobs/<jobId>.
ss_job_fixture <- function(id) {
  paste(readLines(test_path("fixtures", paste0("schoolspring_job_", id, ".json")), warn = FALSE), collapse = "\n")
}

test_that("add_schoolspring_details joins detail fields by job ID and leaves failed ones NA", {
  postings <- data.frame(Title = c("Coach", "Teacher"), Location = "Ronan, Montana",
                         Posted_Date = "2026-06-01",
                         Link = c("https://ronan.schoolspring.com/jobs/5732320",
                                  "https://ronan.schoolspring.com/jobs/1"),
                         stringsAsFactors = FALSE)
  httr2::local_mocked_responses(function(req) {
    if (grepl("/5732320$", req$url)) {
      httr2::response(200, headers = list("Content-Type" = "application/json"), body = charToRaw(ss_job_fixture(5732320)))
    } else {
      httr2::response(404)
    }
  })
  r <- add_schoolspring_details(postings, delay = 0)
  expect_equal(nrow(r), 2)
  expect_equal(r$Close_Date, c("2026-11-13", NA))
  expect_equal(r$Pay_Unit, c("stipend", NA))
  expect_equal(r$Title, postings$Title)
})

# How postings ended (posting-dates plan step 4). Statuses below mirror real
# lookups of 2026-11-04 (MT: 99 postings that left the board, 62 filled,
# 17 canceled, 20 review); the lookup itself is faked so no request is made.
ss_archive <- function(dir, date, ids, titles = paste("Job", ids)) {
  d <- data.frame(title = c(titles, "Para"), date_posted = "2026-09-01", url = c(
    paste0("https://example.schoolspring.com/jobs/", ids), "https://example.applitrack.com/x/default.aspx?AppliTrackJobId=9"),
    District = "Example SD", stringsAsFactors = FALSE)
  utils::write.csv(d, file.path(dir, paste0("combined_", date, ".csv")), row.names = FALSE)
}
fake_status <- function(status) function(ids) {
  s <- status[ids]
  data.frame(job_id = ids[!is.na(s)], Job_Status = unname(s[!is.na(s)]), stringsAsFactors = FALSE)
}
