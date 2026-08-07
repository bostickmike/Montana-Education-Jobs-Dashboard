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

# This project's K-12/HE registries have each grown since these maps were
# first built (32 K-12 districts, 23 HE institutions as of 2026-08-07).
# MT_CCD_LEA_MAP and MT_OPI_FINANCE_LEA_MAP now cover all 32 K-12
# districts (Wolf Point/Plentywood's fast-follow gap closed 2026-08-07).
# MT_DLI_DISTRICT_MAP has a real, permanent gap of its own: Helena and
# Lockwood are genuinely "ND"-suppressed in their own regional PDF row
# despite real disclosed teacher counts, and Glendive is the same; Lame
# Deer and Lodge Grass don't appear as a row in ANY of MT DLI's 9
# regional PDFs at all -- confirmed live, not a lookup miss. 32 - 5 = 27
# is this source's real full-health ceiling, not 32.
#
# On the HE side, MT_IPEDS_UNITID_MAP covers 22 of the 23 registered
# institutions -- Missoula College is the one real, permanent exception
# (no independent unitid in the Urban Institute's directory at all, its
# figures are fully consolidated into University of Montana's own
# reporting). Of those 22, Highlands College has a real, permanent
# *partial* gap: no salary or Pell data reported under its own unitid
# (likely consolidated into Montana Tech's HR/financial-aid reporting),
# but real, separate fall-enrollment data -- so salary/Pell's real
# ceiling is 21, not 22, while enrollment/enrollment-trend's is the full
# 22.
flags <- rbind(
  check_salary_coverage("K-12 teacher avg salary (MT DLI)", sum(!is.na(k12$Teacher_Avg_Salary)), expected = 27L, min_ok = 25L),
  check_salary_coverage("K-12 teacher FTE (CCD)", sum(!is.na(k12$Teachers_Total_FTE)), expected = 32L),
  check_salary_coverage("K-12 General Fund expenditure (OPI Finance)", sum(!is.na(k12$Total_General_Fund_Expenditure)), expected = 32L),
  check_salary_coverage("HE avg faculty salary (IPEDS)", sum(!is.na(he$Faculty_Avg_Salary)), expected = 21L),
  check_salary_coverage("HE fall enrollment FTE (IPEDS)", sum(!is.na(he$Enrollment)), expected = 22L),
  check_salary_coverage("HE 5-year enrollment trend (IPEDS)", sum(!is.na(he$Enrollment_Change_Pct)), expected = 22L),
  check_salary_coverage("HE Pell Grant recipient share (FSA)", sum(!is.na(he$Pell_Recipient_Share)), expected = 21L)
)

if (!is.null(flags) && nrow(flags) > 0) print(flags)

coverage_lines <- if (is.null(flags) || nrow(flags) == 0) {
  character(0)
} else {
  lines <- c(
    paste0("Automated salary-source coverage check flagged ", nrow(flags), " source(s) as of ", Sys.Date(), "."),
    "",
    "Unlike the job-posting drift check above, these are hard assertions against a known, essentially-fixed universe (32 MT K-12 districts, 23 MT HE institutions currently registered -- MT DLI teacher salary and some HE sources only cover a subset, real permanent gaps, see the expected counts above) rather than a trailing statistical baseline -- salary data updates far less often (once a year at most, not weekly), so a genuine week-to-week dip isn't expected. A source landing below its expected count usually means the source changed its page/PDF/API layout and the parser is silently extracting less real data, not that Montana lost school districts or colleges.",
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
# data sits at $25.6k (Blackfeet CC, a real small tribal college with a
# heavily adjunct/part-time-weighted instructional staff, confirmed live
# 2026-08-07 -- not a parsing error) to $99k (HE faculty average); these
# bounds exist to catch a parser reading a location code or a stray digit
# into a dollar column, not to flag genuine, if unusual, salary growth
# over time or a real small institution's real low average.
# --------------------------------------------------------------------------
k12_avg <- setNames(k12$Teacher_Avg_Salary, k12$District)
k12_10th <- setNames(k12$Teacher_Salary_10th_Pctile, k12$District)
k12_90th <- setNames(k12$Teacher_Salary_90th_Pctile, k12$District)
k12_genfund <- setNames(k12$Total_General_Fund_Expenditure, k12$District)
he_current <- setNames(he$Faculty_Avg_Salary, he$Name)
he_y1ago <- setNames(he$Faculty_Avg_Salary_Y1Ago, he$Name)

plausibility_flags <- list(
  check_salary_value_bounds("K-12 teacher avg salary (MT DLI)", k12_avg, min_ok = 25000, max_ok = 150000),
  check_salary_value_bounds("K-12 teacher 10th pctile salary (MT DLI)", k12_10th, min_ok = 20000, max_ok = 150000),
  check_salary_value_bounds("K-12 teacher 90th pctile salary (MT DLI)", k12_90th, min_ok = 25000, max_ok = 175000),
  # Real range confirmed live 2026-08-07: Big Sandy ($2.1M, this project's
  # smallest registered district) to Billings ($134.2M, its largest) --
  # bounds set well outside that to catch a parser misread, not to flag
  # genuine size variation between a tiny and a large district.
  check_salary_value_bounds("K-12 General Fund expenditure (OPI Finance)", k12_genfund, min_ok = 500000, max_ok = 250000000),
  check_salary_value_bounds("HE avg faculty salary (IPEDS)", he_current, min_ok = 15000, max_ok = 150000),
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
