# Montana K-12 teacher salary data from the MT Dept. of Labor & Industry's
# "Teacher Compensation Report" -- the best available Montana analog of
# Wyoming's WSBA salary PDFs, but a genuinely different, weaker source (see
# RESEARCH_NOTES.md's "K-12 salary data -- no clean WSBA equivalent"
# section, confirmed unchanged 2026-08-06 finding this report):
#
# - Published as 9 separate REGIONAL PDFs (lmi.mt.gov/publications), not one
#   statewide document -- each covering a cluster of counties, not aligned
#   to district boundaries in any predictable way (confirmed live: this
#   project's 18 districts spread across 7 of the 9 regions, e.g. Helena and
#   Bozeman -- 100+ miles apart -- are both in "4 Rivers").
# - Reports AVERAGE salary and 10th/90th percentile bands, not a BA-step-1
#   contract base salary like WSBA -- a genuinely different metric, not
#   named Teacher_Base_Salary here to avoid implying equivalence.
# - No superintendent salary or contract-days figure exists anywhere in this
#   report (or any other public MT source found) -- a real, confirmed gap,
#   not a parsing omission. There is no Superintendent_Salary/
#   Superintendent_Contract_Days column in this file's output at all.
# - Small districts are suppressed as "ND" (non-disclosable) or "<5"
#   teachers -- left as genuine NA, not zero.
#
# Each PDF's own per-district table (page 2, "Salary Distribution for
# Public School Teachers in the <Region> Region") is real, usable, per-
# district data -- confirmed live for all 18 of this project's districts,
# just not the same metric WSBA gives Wyoming.

suppressMessages({
  library(httr2)
  library(pdftools)
})

DLI_TEACHER_COMP_BASE_URL <- "https://lmi.mt.gov/_docs/Publications/LMI-Pubs/teachercompreport"

# Filenames aren't a single regular pattern (some regions carry a trailing
# "1" after the year, some don't) -- hardcoded per-region rather than
# templated, confirmed against the live lmi.mt.gov/publications listing
# 2026-08-06 (original 7 regions) and 2026-08-07 (NorthEast/SouthEast,
# added once the 2026-08-07 K-12 registry expansion added districts that
# actually fall in them -- Sidney/Fairview/Poplar in NorthEast,
# Glendive/Colstrip in SouthEast). All 9 real MT DLI regions are covered
# now.
DLI_REGION_FILENAMES <- list(
  Central = "TeacherCompensation_Central_20241.pdf",
  `4Rivers` = "TeacherCompensation_4Rivers_2024.pdf",
  HiLine = "TeacherCompensation_HiLine_20241.pdf",
  NorthCentral = "TeacherCompensation_NorthCentral_20241.pdf",
  NorthWest = "TeacherCompensation_NorthWest_20241.pdf",
  SouthCentral = "TeacherCompensation_SouthCentral_20241.pdf",
  Western = "TeacherCompensation_Western_20241.pdf",
  NorthEast = "TeacherCompensation_NorthEast_2024.pdf",
  SouthEast = "TeacherCompensation_SouthEast_20241.pdf"
)

# Maps this project's canonical District name to (a) which regional PDF
# covers it and (b) the report's own school-system name for that district
# -- the two don't always match this project's naming (e.g. "Belgrade
# Public Schools" here vs. "Belgrade School District 44" in this project;
# "Missoula Co Public Schls" here vs. "Missoula County Public Schools").
# Hand-maintained and confirmed against the live PDFs' real table rows
# 2026-08-06, the same way MT_CCD_LEA_MAP in ccd_staff_scraper.R is.
MT_DLI_DISTRICT_MAP <- list(
  "Billings Public Schools" = list(region = "SouthCentral", report_name = "Billings Public Schools"),
  "Missoula County Public Schools" = list(region = "Western", report_name = "Missoula Co Public Schls"),
  "Great Falls Public Schools" = list(region = "NorthCentral", report_name = "Great Falls Public Schls"),
  "Bozeman Public Schools" = list(region = "4Rivers", report_name = "Bozeman Public Schools"),
  "Helena Public Schools" = list(region = "4Rivers", report_name = "Helena Public Schools"),
  "Butte School District 1" = list(region = "4Rivers", report_name = "Butte Public Schools"),
  "Belgrade School District 44" = list(region = "4Rivers", report_name = "Belgrade Public Schools"),
  "East Helena Public Schools" = list(region = "4Rivers", report_name = "East Helena Public Schools"),
  "Lockwood Schools" = list(region = "SouthCentral", report_name = "Lockwood Public Schools"),
  "Hamilton School District 3" = list(region = "Western", report_name = "Hamilton K-12 Schools"),
  "Havre Public Schools" = list(region = "HiLine", report_name = "Havre Public Schools"),
  "Whitefish School District" = list(region = "NorthWest", report_name = "Whitefish Public Schools"),
  "Columbia Falls School District 6" = list(region = "NorthWest", report_name = "Columbia Falls Pub Schls"),
  "Polson School District" = list(region = "NorthWest", report_name = "Polson Public Schools"),
  "Lewistown Public Schools" = list(region = "Central", report_name = "Lewistown Public Schools"),
  "Laurel Public Schools" = list(region = "SouthCentral", report_name = "Laurel Public Schools"),
  "Kalispell Public Schools" = list(region = "NorthWest", report_name = "Kalispell Public Schools"),
  "Hardin Public Schools" = list(region = "SouthCentral", report_name = "Hardin Public Schools"),
  # Added 2026-08-07 -- each real report_name confirmed live against its
  # region's actual page-2 table row, not assumed from the registry name
  # (Stevensville's real report_name is abbreviated "Public Schls", not
  # "Public Schools", the only one of these 10 that differs). Lame Deer
  # and Lodge Grass (also added to the registry the same session) are
  # deliberately NOT in this map -- confirmed absent from all 9 real
  # regional PDFs (not suppressed as "ND" within a listed row, genuinely
  # not listed as a row at all), a real gap in DLI's own source data, not
  # a search miss -- so both correctly show real NA here rather than a
  # wrong region guess.
  "Sidney Public Schools" = list(region = "NorthEast", report_name = "Sidney Public Schools"),
  "Fairview Public Schools" = list(region = "NorthEast", report_name = "Fairview Public Schools"),
  "Poplar Public Schools" = list(region = "NorthEast", report_name = "Poplar Public Schools"),
  "Glendive Public Schools" = list(region = "SouthEast", report_name = "Glendive Public Schools"),
  "Colstrip Public Schools" = list(region = "SouthEast", report_name = "Colstrip Public Schools"),
  "Livingston Public Schools" = list(region = "4Rivers", report_name = "Livingston Public Schools"),
  "Rocky Boy Public Schools" = list(region = "HiLine", report_name = "Rocky Boy Public Schools"),
  "Big Sandy Public Schools" = list(region = "NorthCentral", report_name = "Big Sandy Public Schools"),
  "Ronan Public Schools" = list(region = "Western", report_name = "Ronan Public Schools"),
  "Stevensville Public Schools" = list(region = "Western", report_name = "Stevensville Public Schls")
)

fetch_dli_region_pdf_text <- function(region) {
  url <- paste0(DLI_TEACHER_COMP_BASE_URL, "/", DLI_REGION_FILENAMES[[region]])
  resp <- request(url) %>% req_perform()
  tmp <- tempfile(fileext = ".pdf")
  writeBin(resp_body_raw(resp), tmp)
  # Page 2 is always the per-district salary table -- confirmed on all 9
  # regional PDFs (every one is exactly 2 pages: page 1 is the infographic
  # summary, page 2 the table).
  pdftools::pdf_text(tmp)[2]
}

# "ND" (non-disclosable, MTDLI's own suppression marker) and "<5" (a
# suppressed small teacher count) both become genuine NA -- not zero, not a
# parsing failure.
parse_dli_numeric_field <- function(x) {
  x <- gsub(",", "", x)
  ifelse(x %in% c("ND", "<5"), NA_real_, suppressWarnings(as.numeric(x)))
}

# Finds report_name's own row in one region's already-extracted page-2 text
# and pulls its trailing four whitespace-separated fields (Teachers,
# Lowest 10%, Average Salary, Highest 10%) -- the class-code column (AA/A/
# B/C) some rows carry isn't captured, since MT_DLI_DISTRICT_MAP already
# looks a district up directly by name rather than needing to track which
# class group it's in.
parse_dli_teacher_compensation <- function(page2_text, report_name) {
  empty <- data.frame(Teacher_Count = NA_real_, Teacher_Salary_10th_Pctile = NA_real_,
                       Teacher_Avg_Salary = NA_real_, Teacher_Salary_90th_Pctile = NA_real_,
                       stringsAsFactors = FALSE)[0, ]

  lines <- strsplit(page2_text, "\n")[[1]]
  matching_lines <- lines[grepl(report_name, lines, fixed = TRUE)]
  if (length(matching_lines) == 0) return(empty)

  line <- matching_lines[1]
  m <- regmatches(line, regexec(
    "(<5|[0-9][0-9,]*)\\s+(ND|<5|[0-9][0-9,]*)\\s+(ND|<5|[0-9][0-9,]*)\\s+(ND|<5|[0-9][0-9,]*)\\s*$",
    line
  ))[[1]]
  if (length(m) != 5) return(empty)

  data.frame(
    Teacher_Count = parse_dli_numeric_field(m[2]),
    Teacher_Salary_10th_Pctile = parse_dli_numeric_field(m[3]),
    Teacher_Avg_Salary = parse_dli_numeric_field(m[4]),
    Teacher_Salary_90th_Pctile = parse_dli_numeric_field(m[5]),
    stringsAsFactors = FALSE
  )
}

# The report's own "Source: OPI GEMS <year>" footer, e.g. "2022-23" -- the
# real underlying school-year the salary figures describe (distinct from
# the report's own publication/edition year baked into the PDF filenames).
# Extracted dynamically so a future annual edition's real coverage year is
# picked up automatically rather than needing a code change.
extract_dli_salary_year <- function(page2_text) {
  m <- regmatches(page2_text, regexpr("OPI GEMS [0-9]{4}-[0-9]{2}", page2_text))
  if (length(m) == 0) return(NA_character_)
  sub("OPI GEMS ", "", m)
}

fetch_dli_teacher_compensation_all_districts <- function() {
  regions_needed <- unique(vapply(MT_DLI_DISTRICT_MAP, function(x) x$region, character(1)))
  region_text <- stats::setNames(
    lapply(regions_needed, fetch_dli_region_pdf_text),
    regions_needed
  )

  rows <- lapply(names(MT_DLI_DISTRICT_MAP), function(district) {
    info <- MT_DLI_DISTRICT_MAP[[district]]
    result <- parse_dli_teacher_compensation(region_text[[info$region]], info$report_name)
    if (nrow(result) == 0) {
      result <- data.frame(Teacher_Count = NA_real_, Teacher_Salary_10th_Pctile = NA_real_,
                            Teacher_Avg_Salary = NA_real_, Teacher_Salary_90th_Pctile = NA_real_,
                            stringsAsFactors = FALSE)
    }
    result$District <- district
    result
  })

  combined <- dplyr::bind_rows(rows)
  combined$Salary_Year <- extract_dli_salary_year(region_text[[1]])
  combined[, c("District", "Teacher_Count", "Teacher_Salary_10th_Pctile",
               "Teacher_Avg_Salary", "Teacher_Salary_90th_Pctile", "Salary_Year")]
}
