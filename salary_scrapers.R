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
  library(dplyr)
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
# Maps this project's canonical District name to (a) which regional PDF
# covers it and (b) the report's own school-system name for that district.
# Hand-maintained and confirmed against the live 9 regional DLI PDFs.
MT_DLI_DISTRICT_MAP <- list(
  "Alberton School District" = list(region = "Western", report_name = "Alberton K-12 Schools"),
  "Anaconda School District #10" = list(region = "4Rivers", report_name = "Anaconda Public Schools"),
  "Arlee Joint School District" = list(region = "Western", report_name = "Arlee Public Schools"),
  "Arrowhead Elementary School District #75" = list(region = "4Rivers", report_name = "Arrowhead Schools"),
  "Ashland Public School" = list(region = "SouthEast", report_name = "Ashland Elementary"),
  "Augusta School District #45" = list(region = "Western", report_name = "Augusta Public Schools"),
  "Baker Public Schools" = list(region = "SouthEast", report_name = "Baker K-12 Schools"),
  "Belfry Public Schools" = list(region = "SouthCentral", report_name = "Belfry K-12 Schools"),
  "Belgrade School District 44" = list(region = "4Rivers", report_name = "Belgrade Public Schools"),
  "Belt Public Schools" = list(region = "NorthCentral", report_name = "Belt Public Schools"),
  "Big Sandy Public Schools" = list(region = "NorthCentral", report_name = "Big Sandy Public Schools"),
  "Big Sky School District 72" = list(region = "4Rivers", report_name = "Big Sky K-12 Schools"),
  "Big Timber Grade School" = list(region = "4Rivers", report_name = "Big Timber Elementary"),
  "Bigfork School District 38" = list(region = "NorthWest", report_name = "Bigfork Public Schools"),
  "Billings Public Schools" = list(region = "SouthCentral", report_name = "Billings Public Schools"),
  "Bonner School District #14" = list(region = "Western", report_name = "Bonner Elementary"),
  "Boulder Elementary" = list(region = "4Rivers", report_name = "Boulder Elementary"),
  "Bozeman Public Schools" = list(region = "4Rivers", report_name = "Bozeman Public Schools"),
  "Bridger School District 2" = list(region = "SouthCentral", report_name = "Bridger K-12 Schools"),
  "Broadus Public Schools" = list(region = "SouthEast", report_name = "Broadus Public Schools"),
  "Broadview School District" = list(region = "SouthCentral", report_name = "Broadview Public Schools"),
  "Brockton School District" = list(region = "NorthEast", report_name = "Brockton Public Schools"),
  "Browning Public Schools" = list(region = "NorthCentral", report_name = "Browning Public Schools"),
  "Butte School District 1" = list(region = "4Rivers", report_name = "Butte Public Schools"),
  "Canyon Creek School District" = list(region = "SouthCentral", report_name = "Canyon Creek Elementary"),
  "Cardwell Elementary School" = list(region = "4Rivers", report_name = "Cardwell Elementary"),
  "Cascade Public Schools" = list(region = "NorthCentral", report_name = "Cascade Public Schools"),
  "Cayuse Prairie School District #10" = list(region = "NorthWest", report_name = "Cayuse Prairie Elementary"),
  "Centerville Public Schools" = list(region = "NorthCentral", report_name = "Centerville Public Schls"),
  "Charlo School District 7J" = list(region = "Western", report_name = "Charlo Public Schools"),
  "Chinook Public Schools" = list(region = "HiLine", report_name = "Chinook Public Schools"),
  "Choteau School District" = list(region = "NorthCentral", report_name = "Choteau Public Schools"),
  "Circle Public Schools" = list(region = "NorthEast", report_name = "Circle Public Schools"),
  "Clinton School District #32" = list(region = "Western", report_name = "Clinton Elementary"),
  "Colstrip Public Schools" = list(region = "SouthEast", report_name = "Colstrip Public Schools"),
  "Columbia Falls School District 6" = list(region = "NorthWest", report_name = "Columbia Falls Pub Schls"),
  "Columbus Public Schools" = list(region = "SouthCentral", report_name = "Columbus Public Schools"),
  "Conrad Public Schools" = list(region = "NorthCentral", report_name = "Conrad Public Schools"),
  "Corvallis School District #1" = list(region = "Western", report_name = "Corvallis K-12 Schools"),
  "Cottonwood School District #57" = list(region = "4Rivers", report_name = "Cottonwood Elementary"),
  "Creston School District" = list(region = "NorthWest", report_name = "Creston Elementary"),
  "Culbertson School District 17-C" = list(region = "NorthEast", report_name = "Culbertson Public Schools"),
  "Custer Public Schools" = list(region = "SouthCentral", report_name = "Custer K-12 Schools"),
  "Cut Bank School District #15" = list(region = "NorthCentral", report_name = "Cut Bank Public Schools"),
  "Darby School District 9" = list(region = "Western", report_name = "Darby K-12 Schools"),
  "Deer Lodge School District #1" = list(region = "Western", report_name = "Deer Lodge Elementary"),
  "Deer Park School District" = list(region = "NorthWest", report_name = "Deer Park Elementary"),
  "DeSmet Public School" = list(region = "Western", report_name = "DeSmet Elementary"),
  "Dillon School District 10" = list(region = "4Rivers", report_name = "Dillon Elementary"),
  "Dixon School District #9" = list(region = "Western", report_name = "Dixon Elementary"),
  "Drummond Public Schools" = list(region = "Western", report_name = "Drummond Public Schools"),
  "Dutton/Brady Public School District" = list(region = "NorthCentral", report_name = "Dutton/Brady K-12 Schools"),
  "East Glacier Park Grade School" = list(region = "NorthCentral", report_name = "East Glacier Park Elem"),
  "East Helena Public Schools" = list(region = "4Rivers", report_name = "East Helena Public Schools"),
  "Ekalaka Public Schools" = list(region = "SouthEast", report_name = "Ekalaka Public Schools"),
  "Elder Grove School District" = list(region = "SouthCentral", report_name = "Elder Grove Elementary"),
  "Elysian School District #23" = list(region = "SouthCentral", report_name = "Elysian Elementary"),
  "Ennis Schools" = list(region = "4Rivers", report_name = "Ennis K-12 Schools"),
  "Evergreen School District #50" = list(region = "NorthWest", report_name = "Evergreen Elementary"),
  "Fair-Mont-Egan Schools" = list(region = "NorthWest", report_name = "Fair-Mont-Egan Elementary"),
  "Fairview Public Schools" = list(region = "NorthEast", report_name = "Fairview Public Schools"),
  "Florence-Carlton School District 15-6" = list(region = "Western", report_name = "Florence-Carlton K-12 Schls"),
  "Forsyth Public Schools" = list(region = "SouthEast", report_name = "Forsyth Public Schools"),
  "Fort Benton School District 1" = list(region = "NorthCentral", report_name = "Fort Benton Public Schls"),
  "Frazer Public Schools" = list(region = "NorthEast", report_name = "Frazer Public Schools"),
  "Froid Public Schools" = list(region = "NorthEast", report_name = "Froid Public Schools"),
  "Fromberg Public Schools" = list(region = "SouthCentral", report_name = "Fromberg K-12"),
  "Gallatin Gateway School" = list(region = "4Rivers", report_name = "Gallatin Gateway Elem"),
  "Gardiner Public Schools" = list(region = "4Rivers", report_name = "Gardiner Public Schools"),
  "Geyser Public Schools" = list(region = "Central", report_name = "Geyser K-12 Schools"),
  "Glasgow School District 1-A" = list(region = "NorthEast", report_name = "Glasgow K-12 Schools"),
  "Glendive Public Schools" = list(region = "SouthEast", report_name = "Glendive Public Schools"),
  "Grass Range Public Schools" = list(region = "Central", report_name = "Grass Range Public Schls"),
  "Great Falls Public Schools" = list(region = "NorthCentral", report_name = "Great Falls Public Schls"),
  "Hamilton School District 3" = list(region = "Western", report_name = "Hamilton K-12 Schools"),
  "Hardin Public Schools" = list(region = "SouthCentral", report_name = "Hardin Public Schools"),
  "Harlem Public Schools" = list(region = "HiLine", report_name = "Harlem Public Schools"),
  "Havre Public Schools" = list(region = "HiLine", report_name = "Havre Public Schools"),
  "Hays-Lodge Pole School District" = list(region = "HiLine", report_name = "Hays-Lodge Pole K-12 Schls"),
  "Helena Flats School District #15" = list(region = "NorthWest", report_name = "Helena Flats Elementary"),
  "Helena Public Schools" = list(region = "4Rivers", report_name = "Helena Public Schools"),
  "Hellgate Elementary School District" = list(region = "Western", report_name = "Hellgate Elementary"),
  "Highwood Public Schools" = list(region = "NorthCentral", report_name = "Highwood Public Schools"),
  "Hinsdale Public Schools" = list(region = "NorthEast", report_name = "Hinsdale Public Schools"),
  "Hobson Public School" = list(region = "Central", report_name = "Hobson K-12 Schools"),
  "Hot Springs School District" = list(region = "Western", report_name = "Hot Springs K-12"),
  "Huntley Project School District" = list(region = "SouthCentral", report_name = "Huntley Project K-12 Schls"),
  "Hysham Public Schools" = list(region = "SouthCentral", report_name = "Hysham K-12 Schools"),
  "Independent School" = list(region = "SouthCentral", report_name = "Independent Elementary"),
  "Jefferson High School" = list(region = "4Rivers", report_name = "Jefferson High School"),
  "Joliet Public School District 86" = list(region = "SouthCentral", report_name = "Joliet Public Schools"),
  "Jordan Public Schools" = list(region = "SouthEast", report_name = "Jordan Public Schools"),
  "Judith Gap Schools" = list(region = "Central", report_name = "Judith Gap Public Schools"),
  "Kalispell Public Schools" = list(region = "NorthWest", report_name = "Kalispell Public Schools"),
  "Kila School District #20" = list(region = "NorthWest", report_name = "Kila Elementary"),
  "Lambert Public Schools" = list(region = "NorthEast", report_name = "Lambert Public Schools"),
  "Laurel Public Schools" = list(region = "SouthCentral", report_name = "Laurel Public Schools"),
  "Lavina Public Schools" = list(region = "SouthCentral", report_name = "Lavina K-12 Schools"),
  "Lewistown Public Schools" = list(region = "Central", report_name = "Lewistown Public Schools"),
  "Libby Public Schools" = list(region = "NorthWest", report_name = "Libby K-12 Schools"),
  "Lincoln School District #38" = list(region = "Western", report_name = "Lincoln K-12 Schools"),
  "Livingston Public Schools" = list(region = "4Rivers", report_name = "Livingston Public Schools"),
  "Lockwood Schools" = list(region = "SouthCentral", report_name = "Lockwood Public Schools"),
  "Lolo School District 7" = list(region = "Western", report_name = "Lolo Elementary"),
  "Lone Rock School District" = list(region = "Western", report_name = "Lone Rock Elementary"),
  "Lustre District 23" = list(region = "NorthEast", report_name = "Lustre Elementary"),
  "Luther School" = list(region = "SouthCentral", report_name = "Luther Elementary"),
  "Malta Public Schools" = list(region = "HiLine", report_name = "Malta K-12 Schools"),
  "Manhattan School District" = list(region = "4Rivers", report_name = "Manhattan Public Schools"),
  "Melstone Public Schools" = list(region = "SouthCentral", report_name = "Melstone Public Schools"),
  "Miami Elementary School District #31" = list(region = "NorthCentral", report_name = "Miami Elementary"),
  "Miles City Unified School District 1" = list(region = "SouthEast", report_name = "Miles City Public Schools"),
  "Missoula County Public Schools" = list(region = "Western", report_name = "Missoula Co Public Schls"),
  "Monforton School District #27" = list(region = "4Rivers", report_name = "Monforton Elementary"),
  "Moore Public Schools" = list(region = "Central", report_name = "Moore Public Schools"),
  "Nashua Public Schools" = list(region = "NorthEast", report_name = "Nashua K-12 Schools"),
  "North Star Public Schools" = list(region = "HiLine", report_name = "North Star Public Schools"),
  "Noxon Public Schools" = list(region = "NorthWest", report_name = "Noxon Public Schools"),
  "Opheim Public Schools" = list(region = "NorthEast", report_name = "Opheim K-12 Schools"),
  "Park City Schools" = list(region = "SouthCentral", report_name = "Park City Public Schools"),
  "Philipsburg School District" = list(region = "Western", report_name = "Philipsburg K-12 Schools"),
  "Pioneer Elementary School District #41" = list(region = "SouthCentral", report_name = "Pioneer Elementary"),
  "Plentywood Public Schools" = list(region = "NorthEast", report_name = "Plentywood K-12 Schools"),
  "Plevna School District #55" = list(region = "SouthEast", report_name = "Plevna K-12 Schools"),
  "Polson School District" = list(region = "NorthWest", report_name = "Polson Public Schools"),
  "Poplar Public Schools" = list(region = "NorthEast", report_name = "Poplar Public Schools"),
  "Potomac Elementary School District #11" = list(region = "Western", report_name = "Potomac Elementary"),
  "Power Public Schools" = list(region = "NorthCentral", report_name = "Power Public Schools"),
  "Pryor Public Schools" = list(region = "SouthCentral", report_name = "Pryor Public Schools"),
  "Ramsay School District #3" = list(region = "4Rivers", report_name = "Ramsay Elementary"),
  "Rapelje School District" = list(region = "SouthCentral", report_name = "Rapelje Public Schools"),
  "Red Lodge School District 1" = list(region = "SouthCentral", report_name = "Red Lodge Public Schools"),
  "Reed Point School District" = list(region = "SouthCentral", report_name = "Reed Point Public Schools"),
  "Richey Public Schools" = list(region = "NorthEast", report_name = "Richey Public Schools"),
  "Roberts Public School" = list(region = "SouthCentral", report_name = "Roberts K-12 Schools"),
  "Rocky Boy Public Schools" = list(region = "HiLine", report_name = "Rocky Boy Public Schools"),
  "Ronan Public Schools" = list(region = "Western", report_name = "Ronan Public Schools"),
  "Roundup School District" = list(region = "SouthCentral", report_name = "Roundup Public Schools"),
  "Roy School District 74" = list(region = "Central", report_name = "Roy K-12 Schools"),
  "Scobey Schools" = list(region = "NorthEast", report_name = "Scobey K-12 Schools"),
  "Seeley Lake Elementary #34" = list(region = "Western", report_name = "Seeley Lake Elementary"),
  "Shelby School District" = list(region = "NorthCentral", report_name = "Shelby Public Schools"),
  "Shepherd School District #37" = list(region = "SouthCentral", report_name = "Shepherd Public Schools"),
  "Sheridan Public Schools" = list(region = "4Rivers", report_name = "Sheridan Public Schools"),
  "Shields Valley Public Schools" = list(region = "4Rivers", report_name = "Shields Valley Pub Schls"),
  "Sidney Public Schools" = list(region = "NorthEast", report_name = "Sidney Public Schools"),
  "Smith Valley School District #8" = list(region = "NorthWest", report_name = "Smith Valley Elementary"),
  "St Regis School District" = list(region = "Western", report_name = "St Regis K-12 Schools"),
  "St. Ignatius School District" = list(region = "Western", report_name = "St Ignatius K-12 Schools"),
  "Stanford Public Schools" = list(region = "Central", report_name = "Stanford K-12 Schools"),
  "Stevensville Public Schools" = list(region = "Western", report_name = "Stevensville Public Schls"),
  "Sun River Valley School District #24" = list(region = "NorthCentral", report_name = "Sun River Valley Pub Schls"),
  "Sunburst Schools" = list(region = "NorthCentral", report_name = "Sunburst K-12 Schools"),
  "Superior School District" = list(region = "Western", report_name = "Superior K-12 Schools"),
  "Swan River School District #4" = list(region = "NorthWest", report_name = "Swan River Elementary"),
  "Swan Valley School District #3" = list(region = "Western", report_name = "Swan Valley Elementary"),
  "Sweet Grass County High School" = list(region = "4Rivers", report_name = "Sweet Grass County HS"),
  "Target Range School District" = list(region = "Western", report_name = "Target Range Elementary"),
  "Terry Public Schools" = list(region = "SouthEast", report_name = "Terry K-12 Schools"),
  "Thompson Falls Public Schools" = list(region = "Western", report_name = "Thompson Falls Pub Schls"),
  "Three Forks Public Schools" = list(region = "4Rivers", report_name = "Three Forks Public Schls"),
  "Townsend School District" = list(region = "4Rivers", report_name = "Townsend K-12 Schools"),
  "Trout Creek School District #6" = list(region = "NorthWest", report_name = "Trout Creek Elementary"),
  "Turner Public Schools" = list(region = "HiLine", report_name = "Turner Public Schools"),
  "Upper West Shore School District #33" = list(region = "NorthWest", report_name = "Upper West Shore Elem"),
  "Valier School District #18" = list(region = "NorthCentral", report_name = "Valier Public Schools"),
  "Vaughn Elementary School District #74" = list(region = "NorthCentral", report_name = "Vaughn Elementary"),
  "Victor School District" = list(region = "Western", report_name = "Victor K-12 Schools"),
  "West Glacier Elementary School District #8" = list(region = "NorthWest", report_name = "West Glacier Elementary"),
  "West Valley School District #1" = list(region = "NorthWest", report_name = "West Valley Elementary"),
  "West Yellowstone School District" = list(region = "4Rivers", report_name = "West Yellowstone K-12 Schls"),
  "Westby School District 3" = list(region = "NorthEast", report_name = "Westby K-12 Schools"),
  "White Sulphur Springs Schools" = list(region = "4Rivers", report_name = "White Sul Spgs Pub Schls"),
  "Whitefish School District" = list(region = "NorthWest", report_name = "Whitefish Public Schools"),
  "Whitehall Public Schools" = list(region = "4Rivers", report_name = "Whitehall Public Schools"),
  "Whitewater Public Schools" = list(region = "HiLine", report_name = "Whitewater K-12 Schools"),
  "Wibaux Public Schools" = list(region = "SouthEast", report_name = "Wibaux K-12 Schools"),
  "Winnett Public Schools" = list(region = "Central", report_name = "Winnett K-12 Schools"),
  "Wolf Point Public Schools" = list(region = "NorthEast", report_name = "Wolf Point Public Schools"),
  "Woodman Elementary School District #3" = list(region = "Western", report_name = "Woodman Elementary"),
  "Zurich Elementary School District #17" = list(region = "HiLine", report_name = "Zurich Elementary")
)


fetch_dli_region_pdf_text <- function(region) {
  url <- paste0(DLI_TEACHER_COMP_BASE_URL, "/", DLI_REGION_FILENAMES[[region]])
  resp <- request(url) %>% perform_with_retry()
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

  p10 <- parse_dli_numeric_field(m[3])
  avg <- parse_dli_numeric_field(m[4])
  p90 <- parse_dli_numeric_field(m[5])
  # Sanity check: annual salary figure < $15k is an OCR/data-entry anomaly
  if (!is.na(p10) && p10 < 15000) p10 <- NA_real_
  if (!is.na(avg) && avg < 15000) avg <- NA_real_
  if (!is.na(p90) && p90 < 15000) p90 <- NA_real_

  data.frame(
    Teacher_Count = parse_dli_numeric_field(m[2]),
    Teacher_Salary_10th_Pctile = p10,
    Teacher_Avg_Salary = avg,
    Teacher_Salary_90th_Pctile = p90,
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

# ---------------------------------------------------------------------------
# K-12 salary history archive
# ---------------------------------------------------------------------------
#
# Ported from the Wyoming Education Jobs Dashboard's own
# archive_k12_salary_snapshot()/needs_k12_salary_archive_update() -- same
# real underlying problem: MT DLI's Teacher Compensation Report has no
# public historical archive of its own (only the current edition's PDFs
# are ever published, confirmed live), and (unlike IPEDS, queryable by
# year indefinitely -- see ipeds_salary_scraper.R's
# fetch_ipeds_he_salary_trend()) has had only one published edition found
# so far ("2022-23"). So a multi-year K-12 salary trend can only be built
# by starting to capture this project's own snapshot now and letting it
# accumulate as DLI republishes future editions -- a complete repeat is a
# no-op, while a partial prior write is backfilled by missing district/year
# pair. The archive therefore stays one row per district per year, not 52
# duplicate rows for the same year. Columns are MT's own DLI shape
# (Teacher_Count/10th/Avg/90th percentile), not Wyoming's WSBA-shaped
# Teacher_Base_Salary/Superintendent_Salary -- MT genuinely has neither
# of those (see this file's own header and RESEARCH_NOTES.md for why).
# Not currently read by app.R -- exists to grow into a real trend as more
# Salary_Years accumulate, same as Wyoming's own version.

# Pure decision logic, testable without file I/O: given the archive's
# existing recorded years and this run's salary year, does a new
# snapshot need to be appended?
needs_k12_salary_archive_update <- function(existing_years, current_year) {
  !is.na(current_year) && !(current_year %in% existing_years)
}

# Return only district/year pairs the archive does not already contain. This
# also repairs an interrupted prior run that wrote only part of a salary year.
missing_k12_salary_snapshot_rows <- function(existing, snapshot) {
  snapshot <- snapshot %>% distinct(District, Salary_Year, .keep_all = TRUE)
  existing_keys <- paste(existing$District, existing$Salary_Year, sep = "\r")
  snapshot_keys <- paste(snapshot$District, snapshot$Salary_Year, sep = "\r")
  snapshot[!(snapshot_keys %in% existing_keys), , drop = FALSE]
}

archive_k12_salary_snapshot <- function(salarymap2, history_path) {
  current_year <- unique(stats::na.omit(salarymap2$Salary_Year))
  if (length(current_year) != 1) {
    message("K-12 salary archive: Salary_Year isn't a single consistent value this run, skipping archive.")
    return(invisible(FALSE))
  }
  current_year <- current_year[1]

  existing <- if (file.exists(history_path)) {
    read.csv(history_path, stringsAsFactors = FALSE)
  } else {
    data.frame(District = character(0), Salary_Year = character(0),
               Teacher_Count = numeric(0), Teacher_Salary_10th_Pctile = numeric(0),
               Teacher_Avg_Salary = numeric(0), Teacher_Salary_90th_Pctile = numeric(0),
               stringsAsFactors = FALSE)
  }

  snapshot <- salarymap2 %>%
    filter(Salary_Year == current_year) %>%
    select(District, Salary_Year, Teacher_Count, Teacher_Salary_10th_Pctile,
           Teacher_Avg_Salary, Teacher_Salary_90th_Pctile) %>%
    distinct(District, Salary_Year, .keep_all = TRUE)

  missing_snapshot <- missing_k12_salary_snapshot_rows(existing, snapshot)
  if (nrow(missing_snapshot) == 0) {
    message("K-12 salary archive: every district/year pair for ", current_year,
            " is already recorded, no snapshot update needed.")
    return(invisible(FALSE))
  }

  updated <- bind_rows(existing, missing_snapshot)
  write.csv(updated, history_path, row.names = FALSE)
  message("K-12 salary archive: appended ", nrow(missing_snapshot),
          " missing district snapshot(s) for ", current_year, ".")
  invisible(TRUE)
}
