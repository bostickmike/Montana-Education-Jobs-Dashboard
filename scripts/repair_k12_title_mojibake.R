# Repairs historical K-12 title mojibake caused by fix_title_encoding()'s
# original bug (called normalize_posting_text() after 2fcdb98): it
# unconditionally treated every scraped title as Windows-1252, so genuine
# UTF-8 punctuation (curly quotes, en/em dashes, ellipsis) that had already
# been correctly decoded got double-encoded into garbage -- an en dash in a
# job title like "Special Education Teacher - High School" became
# "Special Education Teacher â€“ High School". Fixed for all FUTURE
# scrapes (normalize_posting_text() now only repairs strings that actually
# fail a UTF-8 round-trip), but that fix can't retroactively detect titles
# already corrupted and archived before it landed, since the corruption is
# technically valid UTF-8 now -- just semantically wrong. This is
# deliberately a narrow migration: it only reverses double-encoding it can
# PROVE explains the observed bytes (see repair_mojibake()'s own header).
#
# Run from the repository root:
#   Rscript scripts/repair_k12_title_mojibake.R --dry-run
#   Rscript scripts/repair_k12_title_mojibake.R --apply
#
# --apply rewrites the affected Archivek12_Data/*.csv snapshots, then
# rebuilds combinedclean.csv/k12jobanalysis.csv/allsum.csv/allnow.csv/
# k12_district_weekly_totals.csv from the repaired archive via
# rebuild_k12_history_from_archive() -- unlike Wyoming's copy of this
# script, Montana's rebuild already regenerates combinedclean.csv itself
# (as the latest archived week), so no separate current-snapshot patch is
# needed here. Git retains the before-state for review/reversion; inspect
# git diff before committing.
#
# HE titles were checked and confirmed NOT affected -- Mt_ED_Jobs.Rmd never
# applies normalize_posting_text() to Higher Ed Title at all, so
# hedata.xlsx/Archived_HE_Data/ were never exposed to this bug.

# Reverses CP1252-as-UTF8 mojibake: text that was genuine UTF-8, got wrongly
# decoded as WINDOWS-1252 (one Unicode char per original byte), then
# re-encoded as UTF-8. Reversal: re-encode the corrupted string AS
# WINDOWS-1252 to recover the original raw bytes, then decode those bytes
# as UTF-8.
#
# Only accepted when re-simulating the SAME corruption mechanism on the
# reversed text exactly reproduces the observed corrupted string
# byte-for-byte. That exactness check -- not a guessed signature pattern --
# is the real safety net: it's what proves a given reversal is the one true
# explanation for the observed bytes, not a coincidence, and it's why
# genuinely-correct accented text (e.g. a real "e"-acute in a name) that
# happens to contain a non-ASCII byte is left untouched -- reversing
# never-corrupted text either fails to decode as valid UTF-8 at all, or
# round-trips to something that doesn't match the original, and both cases
# are rejected.
#
# Candidates are prescreened to strings containing any non-ASCII byte
# (cheap, and correct without needing to enumerate WINDOWS-1252's own
# printable remappings of the 0x80-0x9F byte range, which differ from
# Latin-1/ISO-8859-1 in that range and would be easy to get subtly wrong by
# hand) -- pure-ASCII strings can never be mojibake of this kind and skip
# the iconv round-trip entirely.
repair_mojibake <- function(x) {
  x <- as.character(x)
  has_non_ascii <- !is.na(x) & grepl("[^\x01-\x7f]", x, useBytes = FALSE)
  out <- x
  changed <- rep(FALSE, length(x))
  if (!any(has_non_ascii)) return(list(repaired = out, changed = changed))

  idx <- which(has_non_ascii)
  step1 <- iconv(x[idx], from = "UTF-8", to = "WINDOWS-1252")
  reversed <- suppressWarnings(iconv(step1, from = "UTF-8", to = "UTF-8", sub = NA_character_))
  reproduced <- rep(NA_character_, length(idx))
  has_reversed <- !is.na(reversed)
  reproduced[has_reversed] <- suppressWarnings(
    iconv(reversed[has_reversed], from = "WINDOWS-1252", to = "UTF-8", sub = "byte")
  )
  safe <- has_reversed & !is.na(reproduced) & reproduced == x[idx]

  out[idx[safe]] <- reversed[safe]
  changed[idx[safe]] <- TRUE
  list(repaired = out, changed = changed)
}

# Repairs a genuinely-invalid UTF-8 byte as CP1252, the narrow slice of
# normalize_posting_text()'s behavior this script needs -- NOT its full
# behavior, which also strips CRs and trims whitespace. Applying that
# broader normalization retroactively to historical archives is a real,
# separate cleanup (MT's OPI-sourced fields are known to carry raw CRs from
# before 2fcdb98's fix), but bundling it into this mojibake-only repair
# would silently touch hundreds of rows that were never mojibake-corrupted
# at all -- confirmed empirically: using the full normalize_posting_text()
# here inflated MT's repair count from 151 (genuine mojibake) to 776 (mojibake
# plus every CR/whitespace difference in the archive). Kept out of scope.
repair_invalid_utf8_bytes <- function(x) {
  x <- as.character(x)
  missing <- is.na(x)
  valid_utf8 <- iconv(x, from = "UTF-8", to = "UTF-8", sub = NA_character_)
  needs_repair <- !missing & is.na(valid_utf8)
  out <- x
  out[needs_repair] <- iconv(x[needs_repair], from = "WINDOWS-1252", to = "UTF-8", sub = "byte")
  out[missing] <- NA_character_
  out
}

# Repairs one text column of a data frame in place: first pass repairs any
# genuinely-invalid UTF-8 byte (handles rows written before any encoding
# fix existed in the pipeline at all), second pass reverses
# already-valid-but-wrong mojibake double-encoding that an invalid-byte
# check alone can't detect.
repair_title_column <- function(df, column, source_name = "<data>") {
  if (!column %in% names(df)) {
    stop("repair_title_column(): ", source_name, " is missing column: ", column)
  }
  original <- df[[column]]
  step1 <- repair_invalid_utf8_bytes(original)
  mojibake_result <- repair_mojibake(step1)
  repaired <- mojibake_result$repaired

  changed <- !is.na(original) & !is.na(repaired) & original != repaired
  df[[column]] <- repaired
  list(
    data = df,
    report = data.frame(
      file = rep(source_name, sum(changed)),
      original = original[changed],
      repaired = repaired[changed],
      stringsAsFactors = FALSE
    )
  )
}

empty_mojibake_report <- function() {
  data.frame(file = character(0), original = character(0), repaired = character(0),
             stringsAsFactors = FALSE)
}

repair_k12_title_mojibake <- function(archive_dir = "Archivek12_Data", write = FALSE) {
  archive_files <- sort(list.files(archive_dir, pattern = "\\.csv$", full.names = TRUE))
  if (length(archive_files) == 0) {
    stop("repair_k12_title_mojibake(): no K-12 archive snapshots found in ", archive_dir)
  }

  reports <- list()
  for (f in archive_files) {
    d <- read.csv(f, colClasses = c("Archive_Date" = "character"), stringsAsFactors = FALSE)
    if (!"title" %in% names(d)) next
    result <- repair_title_column(d, "title", f)
    if (nrow(result$report) > 0) {
      reports[[length(reports) + 1]] <- result$report
      if (write) write.csv(result$data, f, row.names = FALSE)
    }
  }

  report <- if (length(reports) == 0) empty_mojibake_report() else do.call(rbind, reports)
  list(report = report)
}

if (sys.nframe() == 0) {
  source("k12_he_classification.R")
  source(file.path("scripts", "rebuild_k12_history_from_archive.R"))

  args <- commandArgs(trailingOnly = TRUE)
  if (!all(args %in% c("--dry-run", "--apply")) || length(args) != 1) {
    stop("Usage: Rscript scripts/repair_k12_title_mojibake.R --dry-run|--apply")
  }

  result <- repair_k12_title_mojibake(write = identical(args, "--apply"))
  if (nrow(result$report) == 0) {
    cat("No repairable title mojibake found; no files changed.\n")
  } else {
    cat(
      if (identical(args, "--apply")) "Repaired " else "Would repair ",
      nrow(result$report), " title(s) across ",
      length(unique(result$report$file)), " file(s).\n", sep = ""
    )
    print(result$report, row.names = FALSE)
    if (identical(args, "--apply")) {
      rebuild <- rebuild_k12_history_from_archive()
      write.csv(rebuild$combinedclean, file.path("Mt_Ed_Jobs", "combinedclean.csv"), row.names = FALSE)
      write.csv(rebuild$k12jobs, file.path("Mt_Ed_Jobs", "k12jobanalysis.csv"), row.names = FALSE)
      write.csv(rebuild$allsum, file.path("Mt_Ed_Jobs", "allsum.csv"), row.names = FALSE)
      write.csv(rebuild$allnow, file.path("Mt_Ed_Jobs", "allnow.csv"), row.names = FALSE)
      write.csv(rebuild$k12_district_weekly_totals,
                file.path("Mt_Ed_Jobs", "k12_district_weekly_totals.csv"), row.names = FALSE)
      cat("Rebuilt combinedclean.csv/k12jobanalysis.csv/allsum.csv/allnow.csv/k12_district_weekly_totals.csv from the repaired archive.\n")
    } else {
      cat("Run again with --apply to write the repaired snapshots and rebuild derived datasets.\n")
    }
  }
}
