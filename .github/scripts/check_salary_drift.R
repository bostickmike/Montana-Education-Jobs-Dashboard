# Salary-source coverage check, run after the Rmd render against the
# just-regenerated salarymap2.csv (K-12/DLI+CCD) and salarymap.csv (HE/
# IPEDS). Unlike check_drift.R (job postings, trailing statistical
# baseline), this checks against a known-fixed universe size -- see
# drift_check.R's check_salary_coverage() for why that's the right shape
# of check here. Diagnostic-only: never blocks the pipeline (see
# weekly-scrape.yml's continue-on-error on this step).
#
# No Sheridan/Gillette-style merged-entity split-watch section here --
# Montana has no equivalent case (see ipeds_salary_scraper.R's header).
# No K-12 year-over-year plausibility check either -- unlike WSBA (which
# reports current + prior year base salary in the same scrape), the MT DLI
# Teacher Compensation Report has only ever had one published edition
# (Salary_Year "2022-23"), so there's no prior-year figure in
# salarymap2.csv to compare against yet.

source("drift_check.R")

k12 <- read.csv(file.path("Mt_Ed_Jobs", "salarymap2.csv"), stringsAsFactors = FALSE)
he <- read.csv(file.path("Mt_Ed_Jobs", "salarymap.csv"), stringsAsFactors = FALSE)

# This project directly scrapes 18 K-12 districts and 6 HE institutions --
# both counts are hardcoded in k12_district_registry.csv/
# he_institution_registry.csv respectively, so salarymap2.csv/salarymap.csv
# always have that many rows regardless of whether a given run's API/PDF
# fetch actually matched real data. The meaningful signal is coverage of
# the headline salary field.
flags <- rbind(
  check_salary_coverage("K-12 teacher avg salary (MT DLI)", sum(!is.na(k12$Teacher_Avg_Salary)), expected = 18L, min_ok = 16L),
  check_salary_coverage("K-12 teacher FTE (CCD)", sum(!is.na(k12$Teachers_Total_FTE)), expected = 18L),
  check_salary_coverage("HE avg faculty salary (IPEDS)", sum(!is.na(he$Faculty_Avg_Salary)), expected = 6L),
  check_salary_coverage("HE fall enrollment FTE (IPEDS)", sum(!is.na(he$Enrollment)), expected = 6L),
  check_salary_coverage("HE 5-year enrollment trend (IPEDS)", sum(!is.na(he$Enrollment_Change_Pct)), expected = 6L),
  check_salary_coverage("HE Pell Grant recipient share (FSA)", sum(!is.na(he$Pell_Recipient_Share)), expected = 6L)
)

if (!is.null(flags) && nrow(flags) > 0) print(flags)

coverage_lines <- if (is.null(flags) || nrow(flags) == 0) {
  character(0)
} else {
  lines <- c(
    paste0("Automated salary-source coverage check flagged ", nrow(flags), " source(s) as of ", Sys.Date(), "."),
    "",
    "Unlike the job-posting drift check above, these are hard assertions against a known, essentially-fixed universe (18 MT districts, 6 MT public HE institutions) rather than a trailing statistical baseline -- salary data updates far less often (once a year at most, not weekly), so a genuine week-to-week dip isn't expected. A source landing below its expected count usually means the source changed its page/PDF/API layout and the parser is silently extracting less real data, not that Montana lost school districts or colleges.",
    ""
  )
  for (i in seq_len(nrow(flags))) {
    r <- flags[i, ]
    lines <- c(lines, sprintf("- **%s**: expected >= %d, got %d", r$name, r$expected, r$actual))
  }
  c(lines, "")
}

# --------------------------------------------------------------------------
# Value plausibility -- catches a source that returns the RIGHT ROW COUNT
# but the WRONG VALUES. Bounds are deliberately generous -- real MT
# 2022-23 DLI data sits at $52k-$67k (teacher average), real 2024 IPEDS
# data sits at $62k-$99k (HE faculty average); these bounds exist to catch
# a parser reading a location code or a stray digit into a dollar column,
# not to flag genuine, if unusual, salary growth over time.
# --------------------------------------------------------------------------
k12_avg <- setNames(k12$Teacher_Avg_Salary, k12$District)
k12_10th <- setNames(k12$Teacher_Salary_10th_Pctile, k12$District)
k12_90th <- setNames(k12$Teacher_Salary_90th_Pctile, k12$District)
he_current <- setNames(he$Faculty_Avg_Salary, he$Name)
he_y1ago <- setNames(he$Faculty_Avg_Salary_Y1Ago, he$Name)

plausibility_flags <- list(
  check_salary_value_bounds("K-12 teacher avg salary (MT DLI)", k12_avg, min_ok = 25000, max_ok = 150000),
  check_salary_value_bounds("K-12 teacher 10th pctile salary (MT DLI)", k12_10th, min_ok = 20000, max_ok = 150000),
  check_salary_value_bounds("K-12 teacher 90th pctile salary (MT DLI)", k12_90th, min_ok = 25000, max_ok = 175000),
  check_salary_value_bounds("HE avg faculty salary (IPEDS)", he_current, min_ok = 30000, max_ok = 150000),
  check_salary_yoy_plausibility(he_current, he_y1ago)
)
plausibility_flags <- plausibility_flags[!vapply(plausibility_flags, is.null, logical(1))]

if (length(plausibility_flags) > 0) for (f in plausibility_flags) print(f)

plausibility_lines <- if (length(plausibility_flags) == 0) {
  character(0)
} else {
  lines <- c(
    "Automated salary VALUE plausibility check flagged something worth a human look.",
    "",
    "Unlike the coverage check above (which only checks row counts), this checks whether the dollar figures themselves look sane -- either outside a generous real-world range, or (for HE) a year-over-year change that's a statistical outlier against every other institution's change this same run. Usually means a source's page/PDF/API layout shifted just enough to misparse values while still returning a plausible row count, not that the underlying number is really this different.",
    ""
  )
  for (f in plausibility_flags) {
    if ("min_ok" %in% names(f)) {
      for (i in seq_len(nrow(f))) {
        r <- f[i, ]
        lines <- c(lines, sprintf("- **%s** (%s): $%s is outside the expected $%s-$%s range", r$name, r$entity,
                                   format(r$value, big.mark = ","), format(r$min_ok, big.mark = ","), format(r$max_ok, big.mark = ",")))
      }
    } else {
      for (i in seq_len(nrow(f))) {
        r <- f[i, ]
        lines <- c(lines, sprintf("- **%s**: $%s -> $%s (%+.1f%%), a real outlier vs. every other entity's change this run",
                                   r$name, format(r$prior, big.mark = ","), format(r$current, big.mark = ","), r$pct_change * 100))
      }
    }
  }
  c(lines, "")
}

if (length(coverage_lines) == 0 && length(plausibility_lines) == 0) {
  cat("Salary source coverage and value plausibility look healthy.\n")
  quit(status = 0, save = "no")
}

report_lines <- c(coverage_lines, plausibility_lines)

# Appends to the same report the job-posting drift check may have already
# started, so both land in one GitHub Issue/comment instead of two separate
# threads.
if (file.exists("/tmp/drift_report.md")) {
  write(c("", "---", "", report_lines), file = "/tmp/drift_report.md", append = TRUE)
} else {
  writeLines(report_lines, "/tmp/drift_report.md")
}
cat("Flagged items written to /tmp/drift_report.md\n")
