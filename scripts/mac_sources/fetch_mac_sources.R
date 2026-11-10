# Runs the sources that GitHub's servers can't reach from Mike's Mac and
# writes them for the `mac-sources` branch (see scrape_helpers.R, "Sources
# fetched from the Mac"). Run from the repo root:
#   Rscript scripts/mac_sources/fetch_mac_sources.R --out <mac-sources worktree>
# Writes <key>.csv (Title, Location, Posted_Date, Link) and updates the key's
# row in manifest.csv (Source, Fetched_At UTC, N_Rows). A source whose fetch
# fails keeps its previous files, so its Fetched_At ages and the pipeline
# stops using it after MAC_SNAPSHOT_MAX_AGE_DAYS. Exits 1 if any source failed.
suppressMessages({ library(httr2); library(rvest); library(dplyr) })
source("scrape_helpers.R")
source("misc_district_scrapers.R")

args <- commandArgs(trailingOnly = TRUE)
out <- if (length(i <- which(args == "--out")) == 1) args[i + 1] else stop("--out <dir> is required")
stopifnot(dir.exists(out))

registry <- read.csv("k12_district_registry.csv", stringsAsFactors = FALSE)
MAC_SOURCES <- list(
  arrowhead = function() fetch_arrowhead_postings(registry$Job_Link[registry$Platform == "ArrowheadHeuristic"][1])
)

manifest_path <- file.path(out, "manifest.csv")
manifest <- if (file.exists(manifest_path)) {
  read.csv(manifest_path, stringsAsFactors = FALSE, colClasses = "character")
} else {
  data.frame(Source = character(0), Fetched_At = character(0), N_Rows = character(0))
}

failed <- character(0)
for (key in names(MAC_SOURCES)) {
  res <- tryCatch(MAC_SOURCES[[key]](), error = function(e) e)
  if (inherits(res, "error")) {
    message(key, ": FAILED, keeping the previous copy: ", conditionMessage(res))
    failed <- c(failed, key)
    next
  }
  res <- as.data.frame(res)[, c("Title", "Location", "Posted_Date", "Link"), drop = FALSE]
  write.csv(res, file.path(out, paste0(key, ".csv")), row.names = FALSE, na = "")
  manifest <- manifest[manifest$Source != key, , drop = FALSE]
  manifest <- rbind(manifest, data.frame(Source = key,
                                         Fetched_At = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                                         N_Rows = as.character(nrow(res))))
  message(key, ": ", nrow(res), " posting(s)")
}
manifest <- manifest[order(manifest$Source), , drop = FALSE]
write.csv(manifest, manifest_path, row.names = FALSE)
if (length(failed) > 0) quit(status = 1)
