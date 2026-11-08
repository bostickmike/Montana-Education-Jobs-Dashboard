#!/usr/bin/env Rscript
# Weekly OPI cross-check (non-blocking): appends to /tmp/drift_report.md the
# districts where OPI lists postings our scrape didn't find, the scrapes that
# came back empty (OPI filled in), and the districts we don't scrape that
# posted on OPI (adoption candidates). Inputs are written by the pipeline's
# combine step (opi_reconcile.R).
suppressMessages(library(dplyr))
source("opi_reconcile.R")

read_if <- function(p) if (file.exists(p)) read.csv(p, stringsAsFactors = FALSE) else NULL
qc <- read_if("mt_discrepancy_report.csv")
adoption <- read_if("opi_adoption_candidates.csv")
backlog <- if (file.exists("DISTRICT_BACKLOG.md")) readLines("DISTRICT_BACKLOG.md", warn = FALSE) else character(0)

opi_primary <- read_if("opi_primary_districts.csv")
md <- build_opi_crosscheck_markdown(qc, adoption, backlog, opi_primary = opi_primary)
cat(sprintf("OPI cross-check: %d QC rows, %d adoption candidates.\n",
            if (is.null(qc)) 0L else nrow(qc), if (is.null(adoption)) 0L else nrow(adoption)))
if (length(md) > 0) {
  cat(md, file = "/tmp/drift_report.md", sep = "\n", append = TRUE)
  cat("Appended the OPI cross-check to /tmp/drift_report.md\n")
}
