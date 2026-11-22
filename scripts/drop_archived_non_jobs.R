# Removes archived K-12 rows that were never job postings (page text a scraper misread as a title). Each removal
# is one row of scripts/archived_non_jobs.csv: the Posting_Source, the exact title and the reason, so every removed
# row is named and reviewable; nothing is matched by pattern.
#
# First use (2026-11-21): Ulm's scraper read the district's "Forms & Files" page (the site has no jobs page), and a
# Title I parent notice passed its keyword filter as a posting in the 11-03 to 11-19 archives.
#
# Run from the repository root:
#   Rscript scripts/drop_archived_non_jobs.R            # dry run: lists the rows it would remove
#   Rscript scripts/drop_archived_non_jobs.R --apply    # rewrites the affected archive files
# Then rebuild what is built from the archives (scripts/rebuild_k12_history_from_archive.R, the posting spells)
# and check the diff: an archive file should show deleted lines only (`git diff --numstat Archivek12_Data`), and
# the derived files should change only where the removed rows were. Git keeps the before-state.
apply <- "--apply" %in% commandArgs(trailingOnly = TRUE)

drops <- read.csv("scripts/archived_non_jobs.csv", stringsAsFactors = FALSE, encoding = "UTF-8")
stopifnot(all(c("Posting_Source", "Title", "Reason") %in% names(drops)), nrow(drops) > 0)
key <- function(source, title) paste(source, title, sep = "\r")

# The end of the CSV record that starts at character `start` of `txt` (a newline outside quotes ends it).
record_end <- function(chars, start) {
  inq <- FALSE
  for (i in start:length(chars)) {
    ch <- chars[i]
    if (ch == "\"") inq <- !inq else if (ch == "\n" && !inq) return(i)
  }
  length(chars)
}

files <- list.files("Archivek12_Data", pattern = "^combined_.*\\.csv$", full.names = TRUE)
found <- character(0)
total <- 0L
for (f in files) {
  w <- read.csv(f, stringsAsFactors = FALSE, check.names = FALSE, encoding = "UTF-8")
  if (!"Posting_Source" %in% names(w)) next
  hit <- key(w$Posting_Source, w$title) %in% key(drops$Posting_Source, drops$Title)
  if (!any(hit)) next
  found <- union(found, key(w$Posting_Source, w$title)[hit])
  cat(sprintf("%s: %d row(s)\n", basename(f), sum(hit)))
  for (t in unique(w$title[hit])) cat("   ", substr(gsub("\\s+", " ", t), 1, 100), "\n")
  total <- total + sum(hit)
  if (!apply) next
  # Delete the records from the file's own text, so every other line stays byte for byte as the pipeline wrote it.
  txt <- readChar(f, file.size(f), useBytes = TRUE)
  Encoding(txt) <- "UTF-8"
  chars <- strsplit(txt, "")[[1]]
  header_end <- record_end(chars, 1)
  header <- paste(chars[1:header_end], collapse = "")
  keep <- rep(TRUE, length(chars))
  for (t in unique(w$title[hit])) {
    needle <- paste0("\n\"", gsub("\"", "\"\"", t, fixed = TRUE), "\",")
    pos <- gregexpr(needle, txt, fixed = TRUE)[[1]]
    stopifnot(pos[1] > 0)
    for (p in pos) {
      s <- nchar(substr(txt, 1, p))  # p is a character position of the "\n" before the record
      e <- record_end(chars, s + 1)
      rec <- read.csv(text = paste0(header, paste(chars[(s + 1):e], collapse = "")), stringsAsFactors = FALSE,
                      check.names = FALSE)
      # Only a record that is exactly a listed row is removed.
      if (nrow(rec) == 1 && key(rec$Posting_Source, rec$title) %in% key(drops$Posting_Source, drops$Title)) keep[(s + 1):e] <- FALSE
    }
  }
  out <- paste(chars[keep], collapse = "")
  after <- read.csv(text = out, stringsAsFactors = FALSE, check.names = FALSE)
  stopifnot(nrow(after) == nrow(w) - sum(hit), identical(after, w[!hit, , drop = FALSE], ignore.environment = TRUE) ||
              isTRUE(all.equal(after, w[!hit, , drop = FALSE], check.attributes = FALSE)))
  con <- file(f, "wb"); writeChar(out, con, eos = NULL, useBytes = TRUE); close(con)
}
cat(sprintf("%s %d row(s) across the %d archive files.\n", if (apply) "Removed" else "Would remove", total, length(files)))
missing <- setdiff(key(drops$Posting_Source, drops$Title), found)
if (length(missing) > 0) cat(length(missing), "listed row(s) not found in any archive (already removed?).\n")
