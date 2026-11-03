# OPI Jobs for Teachers vs. this project's direct scrapes (Montana only).
#
# The rule (user's, 2026-11-02, refined 2026-11-03): the direct scrape is
# trusted; OPI fills gaps and serves as quality control. De-duplication is
# per posting, not per district: a district's board often lists only some of
# its jobs (37 districts post their teaching jobs only on OPI), so an OPI
# posting is dropped only when it is the same opening as a specific board
# posting. A missed match double counts that job; the matcher is measured
# against hand-labeled postings (test-opi-matcher.R).
#
#   1. OPI posting at a district we scrape that is the same opening as a
#      specific posting on its board (match_opi_postings(), opi_matcher.R)
#      -> not a separate row; the board posting is flagged Also_On_OPI.
#   2. OPI posting at a district we scrape with no matching board posting ->
#      counted (decided posting by posting, user's rule 2026-11-03: many
#      districts post certified jobs only on OPI); listed in the QC report.
#   OPI's own repeat listings of one job (same district, same description)
#   count once.
#   3. OPI posting at a real public district we don't scrape -> counted,
#      labeled with that district (one map entity per town), and listed as an
#      adoption candidate (a direct scrape to set up).
#   4. Our scrape of a district returned nothing this week -> its OPI
#      postings fill in (relabeled to the registry district) and are listed in
#      the QC report too (likely a broken scraper).
#   Employers outside CCD (private and tribal schools, co-ops) -> counted,
#      labeled with OPI's employer name, no map entity.
#
# Which district an OPI posting belongs to comes from its detail page's
# district name (OPI_District), which uses the same naming as NCES CCD's
# lea_name. build_mt_district_crosswalk() ties every CCD district to the
# registry district whose job board covers it, or to none. Rows without
# OPI_District (a failed detail fetch; raw archives before 2026-11-01) fall
# back to the town, conservatively: a town with any registry district counts
# as covered.

suppressMessages({
  library(dplyr)
})
# The posting-level matcher (opi_matcher.R).
if (!exists("match_opi_postings", mode = "function")) {
  source(if (file.exists("opi_matcher.R")) "opi_matcher.R" else here::here("opi_matcher.R"))
}

# Data_Coverage label of the OPI-only map entities (app.R shows it as the
# popup badge and in the District Summary's "Posting Data" column).
OPI_ONLY_COVERAGE <- "Postings via OPI's statewide board"
OPI_STATEWIDE_BOARD_URL <- "https://apps.opi.mt.gov/mtjobsforteachers/frmJobListingPublic.aspx"

# Board names OPI's detail pages use for public districts that CCD names
# differently (same pairs as opi_finance_scraper.R's OPI_DISTRICT_ALIASES,
# but pointing at CCD's lea_name).
OPI_CCD_ALIASES <- c(
  "Broadview K-12" = "Broadview H S",
  "Ophir K-12" = "Big Sky School K-12",
  "St. Ignatius HS" = "St Ignatius K-12 Schools",
  "Phillipsburg HS" = "Philipsburg K-12 Schools"
)

# District names reduced to the town/name part: "Bigfork H S", "Bigfork Elem"
# and "Bigfork School District 38" all -> "bigfork".
mt_district_stem <- function(x) {
  x <- tolower(as.character(x))
  x <- gsub("[^a-z0-9 ]+", " ", x)
  x <- gsub("\\b(elem|elementary|h s|hs|high|school|schools|schls|k 12|k12|public|pub|district|dist|co|county|unified|joint|sd|no|[0-9]+)\\b", " ", x)
  trimws(gsub("\\s+", " ", x))
}

is_high_school_lea <- function(x) grepl("\\bH ?S\\b|High School", x)

# One row per regular CCD district (agency_type 1, with schools). Columns:
# LEAID, OPI_District (CCD lea_name = OPI's naming), City, County, Latitude,
# Longitude, Teachers_Total_FTE, Enrollment, Registry_District (NA = we don't
# scrape it), Match_Rule, Map_Entity (registry name, or the OPI-only town
# group's name).
build_mt_district_crosswalk <- function(ccd_df, registry, split_map) {
  ccd <- ccd_df %>%
    filter(agency_type == 1, !is.na(number_of_schools), number_of_schools >= 1) %>%
    transmute(LEAID = as.character(leaid), OPI_District = trimws(lea_name),
              City = trimws(city_location), County = trimws(county_name),
              Latitude = as.numeric(latitude), Longitude = as.numeric(longitude),
              Teachers_Total_FTE = ifelse(is.na(teachers_total_fte) | teachers_total_fte < 0, NA_real_, teachers_total_fte),
              Enrollment = ifelse(is.na(enrollment) | enrollment < 0, NA_real_, enrollment))

  claim <- rbind(
    data.frame(OPI_District = ccd$OPI_District[match(as.character(registry$NCES_LEAID), ccd$LEAID)],
               Registry_District = registry$District, stringsAsFactors = FALSE),
    data.frame(OPI_District = unlist(split_map, use.names = FALSE),
               Registry_District = rep(names(split_map), lengths(split_map)), stringsAsFactors = FALSE)
  )
  claim <- unique(claim[!is.na(claim$OPI_District), , drop = FALSE])
  claim$City <- tolower(ccd$City[match(claim$OPI_District, ccd$OPI_District)])
  claim$Stem <- mt_district_stem(claim$OPI_District)

  ccd$Registry_District <- claim$Registry_District[match(ccd$OPI_District, claim$OPI_District)]
  ccd$Match_Rule <- ifelse(is.na(ccd$Registry_District), NA_character_, "registry NCES id")
  for (i in which(is.na(ccd$Registry_District))) {
    same_city <- claim[claim$City %in% tolower(ccd$City[i]), , drop = FALSE]
    if (nrow(same_city) == 0) next
    stem <- mt_district_stem(ccd$OPI_District[i])
    hit <- same_city[nzchar(stem) & same_city$Stem == stem, , drop = FALSE]
    if (nrow(hit) > 0 && length(unique(hit$Registry_District)) == 1) {
      ccd$Registry_District[i] <- hit$Registry_District[1]
      ccd$Match_Rule[i] <- "same town and name"
      next
    }
    # A county/district high school in a town whose one registry district has
    # no high school of its own ("Custer County H S" with Miles City). A town
    # whose registry district already has one (Box Elder: Rocky Boy H S) is
    # left alone.
    if (is_high_school_lea(ccd$OPI_District[i]) && length(unique(same_city$Registry_District)) == 1 &&
        !any(is_high_school_lea(same_city$OPI_District))) {
      ccd$Registry_District[i] <- same_city$Registry_District[1]
      ccd$Match_Rule[i] <- "high school in a scraped town"
    }
  }

  # Districts we don't scrape: one map entity per town and name ("Box Elder
  # Elem" + "Box Elder H S" -> "Box Elder Elem / Box Elder H S").
  ccd$Map_Entity <- ccd$Registry_District
  free <- is.na(ccd$Registry_District)
  group_key <- paste(tolower(ccd$City), mt_district_stem(ccd$OPI_District))
  for (g in unique(group_key[free])) {
    idx <- which(free & group_key == g)
    ccd$Map_Entity[idx] <- paste(sort(ccd$OPI_District[idx]), collapse = " / ")
  }
  # A name CCD gives two districts ("Cottonwood Elem", Gallatin and Hill)
  # can't identify one from OPI's name alone. Keep the registry district's
  # row when there is one (so its OPI postings count as covered and are
  # never added next to our own scrape); otherwise drop the name.
  ambiguous <- ccd$OPI_District %in% ccd$OPI_District[duplicated(ccd$OPI_District)]
  keep_claimed <- ambiguous & !is.na(ccd$Registry_District) & ccd$Match_Rule == "registry NCES id"
  ccd <- ccd[!ambiguous | keep_claimed, , drop = FALSE]
  ccd <- ccd[!duplicated(ccd$OPI_District), , drop = FALSE]
  ccd[order(ccd$OPI_District), , drop = FALSE]
}

# The crosswalk row for each OPI posting: by its detail page's district
# (aliases applied), else by town. Returns Registry_District, Map_Entity,
# In_CCD and Assign_Method per row.
assign_opi_districts <- function(opi_df, crosswalk, registry) {
  n <- nrow(opi_df)
  name <- if ("OPI_District" %in% names(opi_df)) trimws(as.character(opi_df$OPI_District)) else rep(NA_character_, n)
  name[!is.na(name) & !nzchar(name)] <- NA_character_
  aliased <- ifelse(!is.na(name) & name %in% names(OPI_CCD_ALIASES), OPI_CCD_ALIASES[name], name)
  hit <- match(aliased, crosswalk$OPI_District)

  out <- data.frame(Registry_District = crosswalk$Registry_District[hit],
                    Map_Entity = crosswalk$Map_Entity[hit],
                    In_CCD = !is.na(hit),
                    Assign_Method = ifelse(!is.na(hit), "OPI district",
                                           ifelse(!is.na(name), "OPI district (not a CCD district)", NA_character_)),
                    stringsAsFactors = FALSE)

  # No detail-page district: fall back to the town. Conservative on purpose:
  # a town with any registry district counts as that district's (so an OPI
  # posting can't be counted next to it), and a town with several resolves
  # to the most specific registry City match.
  town_rows <- which(is.na(name))
  if (length(town_rows) > 0) {
    norm <- function(x) trimws(gsub("[^a-z0-9]+", " ", tolower(as.character(x))))
    reg_city <- norm(registry$City)
    xw_city <- norm(crosswalk$City)
    for (i in town_rows) {
      loc <- paste0(" ", norm(sub(",.*$", "", opi_df$location[i])), " ")
      reg_hits <- which(nzchar(reg_city) & vapply(reg_city, function(c) grepl(paste0(" ", c, " "), loc, fixed = TRUE), logical(1)))
      if (length(reg_hits) > 0) {
        reg_hits <- reg_hits[nchar(reg_city[reg_hits]) == max(nchar(reg_city[reg_hits]))]
        out$Registry_District[i] <- registry$District[reg_hits[1]]
        out$Map_Entity[i] <- registry$District[reg_hits[1]]
        out$In_CCD[i] <- TRUE
        out$Assign_Method[i] <- "town"
        next
      }
      xw_hits <- which(nzchar(xw_city) & vapply(xw_city, function(c) grepl(paste0(" ", c, " "), loc, fixed = TRUE), logical(1)))
      entities <- unique(crosswalk$Map_Entity[xw_hits])
      if (length(entities) == 1) {
        out$Map_Entity[i] <- entities
        out$In_CCD[i] <- TRUE
        out$Assign_Method[i] <- "town"
      } else {
        out$In_CCD[i] <- FALSE
        out$Assign_Method[i] <- "unresolved town"
      }
    }
  }
  out
}

# TRUE where a posted date (ISO or OPI's m/d/Y) is more than 60 days before
# `today`; unknown dates are not stale.
opi_listing_is_stale <- function(date_posted, today, days = 60) {
  x <- trimws(as.character(date_posted))
  d <- suppressWarnings(as.Date(x, format = "%Y-%m-%d"))
  d2 <- suppressWarnings(as.Date(x, format = "%m/%d/%Y"))
  d[is.na(d)] <- d2[is.na(d)]
  !is.na(d) & d < (as.Date(today) - days)
}

# TRUE for an OPI row that repeats an earlier row's job: same entity (district /
# map entity / employer) and the same description (first 300 characters of
# its letters and digits). Rows without a description (archives before
# 2026-11-03) are never collapsed, since two real openings can share a title
# and date.
opi_duplicate_listing <- function(opi_df, entity) {
  d <- if ("OPI_Description" %in% names(opi_df)) as.character(opi_df$OPI_Description) else rep(NA_character_, nrow(opi_df))
  # Letters and digits only: OPI's repeat listings differ in stray
  # punctuation ("PE teacher. We may" vs "PE teacher We may", Richey).
  key <- substr(gsub(" +", " ", trimws(gsub("[^a-z0-9]+", " ", tolower(d)))), 1, 300)
  has <- !is.na(d) & nchar(key) >= 40
  out <- rep(FALSE, nrow(opi_df))
  out[has] <- duplicated(paste(entity, key)[has])
  out
}


# Applies the rule above to one week. Returns:
#   opi_keep  -- OPI rows that count (cases 3, 4, non-district employers),
#                District set to the registry district / map entity / OPI's
#                employer name
#   opi_dropped -- OPI rows at districts we scrape (cases 1, 2), District set
#                to that registry district; kept in the raw archive with
#                OPI_Counted = FALSE, never counted
#   direct_df -- direct rows, with Also_On_OPI
#   qc        -- OPI rows at districts we scrape that didn't match a direct
#                posting, plus fallback rows (cases 2 and 4)
#   adoption  -- OPI-only districts this week (case 3), with posting counts
reconcile_opi_with_direct <- function(opi_df, direct_df, crosswalk, registry, today = Sys.Date(),
                                      stale_fallback = TRUE) {
  direct_df$Also_On_OPI <- rep(FALSE, nrow(direct_df))
  empty_qc <- data.frame(District = character(0), OPI_District = character(0), Title = character(0),
                         Date_Posted = character(0), Location = character(0), Discrepancy_Type = character(0),
                         Detected_Date = character(0), stringsAsFactors = FALSE)
  empty_adoption <- data.frame(Map_Entity = character(0), OPI_Districts = character(0), City = character(0),
                               County = character(0), Postings = integer(0), stringsAsFactors = FALSE)
  if (nrow(opi_df) == 0) {
    return(list(opi_keep = opi_df, opi_dropped = opi_df, direct_df = direct_df, qc = empty_qc,
                adoption = empty_adoption))
  }

  a <- assign_opi_districts(opi_df, crosswalk, registry)
  scraped <- !is.na(a$Registry_District)
  direct_active <- unique(direct_df$District[!is.na(direct_df$District)])
  # Listed on OPI over 60 days before the run: likely a stale listing.
  stale <- opi_listing_is_stale(opi_df$date_posted, today)
  # Our scrape returned nothing: OPI fills in, but only with recent postings
  # -- a correct zero (a district with no openings) shouldn't be replaced by
  # OPI listings nobody took down (Seeley Lake, 2026-11-02). Off for archived
  # weeks (stale_fallback = FALSE, opi_rule_for_archive()): judged against
  # today's registry, an old week's "empty scrape" is mostly a district not
  # adopted yet, whose spring postings were still open in August.
  active <- scraped & a$Registry_District %in% direct_active
  empty_board <- scraped & !active
  # OPI lists one job more than once (elementary and high-school district,
  # two schools): same district, same description -> one posting.
  dup <- opi_duplicate_listing(opi_df, ifelse(!is.na(a$Map_Entity), a$Map_Entity, as.character(opi_df$District)))

  # Posting by posting (user's rule, 2026-11-03): at a district whose board
  # returned postings, an OPI posting is dropped only when it is the same
  # opening as a specific board posting (match_opi_postings(),
  # opi_matcher.R); every other OPI posting counts.
  m <- rep(NA_integer_, nrow(opi_df))
  if (any(active & !dup)) {
    idx <- which(active & !dup)
    m[idx] <- match_opi_postings(opi_df[idx, , drop = FALSE], a$Registry_District[idx], direct_df)
  }
  direct_df$Also_On_OPI[m[!is.na(m)]] <- TRUE
  matched <- !is.na(m)
  stale_empty <- empty_board & stale & stale_fallback
  covered <- dup | matched | stale_empty          # not counted
  fallback <- empty_board & !covered               # counted: the board was empty
  unmatched <- active & !covered                   # counted: not on the district's board

  qc_rows <- unmatched | fallback | stale_empty
  qc <- if (any(qc_rows)) {
    data.frame(District = a$Registry_District[qc_rows],
               OPI_District = if ("OPI_District" %in% names(opi_df)) as.character(opi_df$OPI_District[qc_rows]) else NA_character_,
               Title = as.character(opi_df$title[qc_rows]),
               Date_Posted = as.character(opi_df$date_posted[qc_rows]),
               Location = as.character(opi_df$location[qc_rows]),
               Discrepancy_Type = ifelse(fallback[qc_rows],
                                         "Direct scrape returned no postings; OPI used instead (check the scraper)",
                                         ifelse(stale_empty[qc_rows],
                                                "Potential ghost posting on OPI (posted over 60 days ago; our scrape returned nothing, not used)",
                                                ifelse(stale[qc_rows],
                                                       "On OPI, not on our scrape, counted from OPI (posted over 60 days ago)",
                                                       "On OPI, not on our scrape, counted from OPI (scraper miss or posted only on OPI)"))),
               Detected_Date = as.character(today), stringsAsFactors = FALSE)
  } else empty_qc

  keep <- !covered
  opi_dropped <- opi_df[covered, , drop = FALSE]
  opi_dropped$District <- ifelse(!is.na(a$Registry_District), a$Registry_District,
                                 ifelse(!is.na(a$Map_Entity), a$Map_Entity, as.character(opi_df$District)))[covered]
  opi_dropped$OPI_Drop_Reason <- ifelse(dup, "OPI duplicate listing", ifelse(matched, "same opening on district board",
                                        "stale OPI listing, district board empty"))[covered]
  opi_dropped$Also_On_OPI <- rep(FALSE, nrow(opi_dropped))
  opi_keep <- opi_df[keep, , drop = FALSE]
  label <- ifelse(!is.na(a$Registry_District), a$Registry_District, ifelse(!is.na(a$Map_Entity), a$Map_Entity,
                  ifelse("OPI_District" %in% names(opi_df) & !is.na(a$Assign_Method) & a$Assign_Method == "OPI district (not a CCD district)",
                         if ("OPI_District" %in% names(opi_df)) trimws(as.character(opi_df$OPI_District)) else NA_character_,
                         as.character(opi_df$District))))
  opi_keep$District <- label[keep]
  opi_keep$Also_On_OPI <- rep(FALSE, nrow(opi_keep))

  only <- !scraped & !is.na(a$Map_Entity)
  adoption <- if (any(only)) {
    data.frame(Map_Entity = a$Map_Entity[only],
               OPI_District = if ("OPI_District" %in% names(opi_df)) as.character(opi_df$OPI_District[only]) else NA_character_,
               stringsAsFactors = FALSE) %>%
      group_by(Map_Entity) %>%
      summarize(OPI_Districts = paste(sort(unique(na.omit(OPI_District))), collapse = " / "),
                Postings = n(), .groups = "drop") %>%
      mutate(City = crosswalk$City[match(Map_Entity, crosswalk$Map_Entity)],
             County = crosswalk$County[match(Map_Entity, crosswalk$Map_Entity)]) %>%
      select(Map_Entity, OPI_Districts, City, County, Postings) %>%
      arrange(desc(Postings), Map_Entity) %>%
      as.data.frame()
  } else empty_adoption

  list(opi_keep = opi_keep, opi_dropped = opi_dropped, direct_df = direct_df, qc = qc, adoption = adoption)
}

# The same rule for one raw archive week (Archivek12_Data/combined_*.csv,
# identity fields already added by add_k12_posting_identity()): returns
# Posting_ID, Is_OPI, Counted and District (the label a counted row carries;
# the registry district for an uncounted OPI row), one row per archive row.
# Archives written since this rule shipped carry OPI_Counted and their
# Districts already; older ones are reconciled here (by town before
# 2026-11-01, when OPI_District started).
opi_rule_for_archive <- function(archive_df, crosswalk, registry, recompute = FALSE) {
  is_opi <- if ("Posting_Source" %in% names(archive_df)) {
    grepl("^OPI ", archive_df$Posting_Source) | is_opi_statewide_posting(archive_df$url)
  } else {
    is_opi_statewide_posting(archive_df$url)
  }
  is_opi[is.na(is_opi)] <- FALSE
  out <- data.frame(Posting_ID = archive_df$Posting_ID, Is_OPI = is_opi, Counted = TRUE,
                    District = as.character(archive_df$District), stringsAsFactors = FALSE)
  if ("OPI_Counted" %in% names(archive_df) && !recompute) {
    out$Counted <- !(archive_df$OPI_Counted %in% c(FALSE, "FALSE"))
    return(out)
  }
  if (!any(is_opi)) return(out)
  direct <- archive_df[!is_opi, , drop = FALSE]
  direct$District <- canonicalize_k12_district(direct$District)
  opi <- archive_df[is_opi, , drop = FALSE]
  week_date <- suppressWarnings(as.Date(as.character(archive_df$Archive_Date[1]), tryFormats = c("%Y-%m-%d", "%m/%d/%Y"),
                                        optional = TRUE))
  r <- reconcile_opi_with_direct(opi, direct, crosswalk, registry,
                                 today = if (is.na(week_date)) Sys.Date() else week_date,
                                 stale_fallback = FALSE)
  opi_idx <- which(is_opi)
  dropped <- opi$Posting_ID %in% r$opi_dropped$Posting_ID
  out$Counted[opi_idx[dropped]] <- FALSE
  out$District[opi_idx[dropped]] <- r$opi_dropped$District[match(opi$Posting_ID[dropped], r$opi_dropped$Posting_ID)]
  kept <- !dropped
  out$District[opi_idx[kept]] <- r$opi_keep$District[match(opi$Posting_ID[kept], r$opi_keep$Posting_ID)]
  out
}

# DLI Teacher Compensation rows for every school system on the 9 regional
# page-2 texts (name, teacher count, 10th pct, average, 90th pct).
parse_dli_all_systems <- function(page2_texts) {
  rx <- "^\\s*(?:AA|A|B|C)?\\s+(\\S.*?\\S)\\s{2,}(<5|[0-9][0-9,]*)\\s+(ND|<5|[0-9][0-9,]*)\\s+(ND|<5|[0-9][0-9,]*)\\s+(ND|<5|[0-9][0-9,]*)\\s*$"
  rows <- list()
  for (txt in page2_texts) {
    for (ln in strsplit(txt, "\n")[[1]]) {
      m <- regmatches(ln, regexec(rx, ln, perl = TRUE))[[1]]
      if (length(m) == 6 && !grepl("School System Name|Region", m[2])) {
        rows[[length(rows) + 1]] <- data.frame(DLI_Name = m[2], Teacher_Count = parse_dli_numeric_field(m[3]),
                                               Teacher_Salary_10th_Pctile = parse_dli_numeric_field(m[4]),
                                               Teacher_Avg_Salary = parse_dli_numeric_field(m[5]),
                                               Teacher_Salary_90th_Pctile = parse_dli_numeric_field(m[6]),
                                               stringsAsFactors = FALSE)
      }
    }
  }
  out <- dplyr::bind_rows(rows)
  if (nrow(out) == 0) return(out)
  for (col in c("Teacher_Salary_10th_Pctile", "Teacher_Avg_Salary", "Teacher_Salary_90th_Pctile")) {
    out[[col]][!is.na(out[[col]]) & out[[col]] < 15000] <- NA_real_
  }
  out
}

# Context rows for the OPI-only map entities, in salarymap2.csv's columns
# where a source covers them: CCD location/staffing (summed over the
# entity's districts), DLI teacher pay (school system matched by name stem,
# only when exactly one system matches), SAIPE child poverty and OPI finance
# (by district), county ACS context copied from any registry district in
# the same county.
OPI_ONLY_DISTRICT_COLUMNS <- c(
  "District", "County", "City", "Latitude", "Longitude", "Teachers_Total_FTE", "Enrollment",
  "OPI_Districts", "LEAIDs", "Data_Coverage", "Job_Link",
  "Teacher_Count", "Teacher_Salary_10th_Pctile", "Teacher_Avg_Salary", "Teacher_Salary_90th_Pctile",
  "DLI_Name", "Salary_Year", "Salary_Source", "Child_Poverty_Rate", "SAIPE_Year",
  "Total_General_Fund_Expenditure", "Finance_FY", "Finance_Source",
  "Median_Household_Income", "Median_Gross_Rent", "Population", "ACS_Year",
  "Mining_Employment_Share", "Population_Change_Pct", "CCD_Year")

# The same columns every week, whichever sources answered (NA where one
# didn't), in OPI_ONLY_DISTRICT_COLUMNS order; zero rows when no OPI-only
# district posted.
complete_opi_only_columns <- function(df) {
  if (is.null(df) || ncol(df) == 0) df <- data.frame(District = character(0), stringsAsFactors = FALSE)
  for (col in setdiff(OPI_ONLY_DISTRICT_COLUMNS, names(df))) df[[col]] <- rep(NA, nrow(df))
  df[, OPI_ONLY_DISTRICT_COLUMNS, drop = FALSE]
}

build_opi_only_districts <- function(crosswalk, entities, dli_systems = NULL, saipe = NULL,
                                     finance = NULL, county_context = NULL) {
  xw <- crosswalk[is.na(crosswalk$Registry_District) & crosswalk$Map_Entity %in% entities, , drop = FALSE]
  if (nrow(xw) == 0) return(complete_opi_only_columns(NULL))
  out <- xw %>%
    group_by(Map_Entity) %>%
    summarize(County = first(County), City = first(City),
              Latitude = mean(Latitude, na.rm = TRUE), Longitude = mean(Longitude, na.rm = TRUE),
              Teachers_Total_FTE = if (all(is.na(Teachers_Total_FTE))) NA_real_ else sum(Teachers_Total_FTE, na.rm = TRUE),
              Enrollment = if (all(is.na(Enrollment))) NA_real_ else sum(Enrollment, na.rm = TRUE),
              OPI_Districts = paste(sort(OPI_District), collapse = " / "),
              LEAIDs = paste(sort(LEAID), collapse = ";"), .groups = "drop") %>%
    rename(District = Map_Entity) %>%
    mutate(County = ifelse(grepl("County$", County), County, paste(County, "County")),
           Data_Coverage = OPI_ONLY_COVERAGE,
           Job_Link = OPI_STATEWIDE_BOARD_URL) %>%
    as.data.frame()

  if (!is.null(dli_systems) && nrow(dli_systems) > 0) {
    dli_stem <- mt_district_stem(dli_systems$DLI_Name)
    pick <- vapply(seq_len(nrow(out)), function(i) {
      stems <- unique(mt_district_stem(strsplit(out$OPI_Districts[i], " / ", fixed = TRUE)[[1]]))
      hits <- which(dli_stem %in% stems[nzchar(stems)])
      if (length(hits) == 1) hits else NA_integer_
    }, integer(1))
    for (col in c("Teacher_Count", "Teacher_Salary_10th_Pctile", "Teacher_Avg_Salary", "Teacher_Salary_90th_Pctile")) {
      out[[col]] <- dli_systems[[col]][pick]
    }
    out$DLI_Name <- dli_systems$DLI_Name[pick]
  }
  if (!is.null(saipe) && nrow(saipe) > 0) {
    # saipe: LEAID, Child_Poverty_Rate, SAIPE_Year. Entities with two
    # districts take the first one that has a rate.
    out$Child_Poverty_Rate <- vapply(strsplit(out$LEAIDs, ";", fixed = TRUE), function(ids) {
      r <- saipe$Child_Poverty_Rate[match(ids, saipe$LEAID)]
      r <- r[!is.na(r)]
      if (length(r)) r[1] else NA_real_
    }, numeric(1))
    out$SAIPE_Year <- saipe$SAIPE_Year[1]
  }
  if (!is.null(finance) && nrow(finance) > 0) {
    # finance: OPI_District, Total_General_Fund_Expenditure, Finance_FY
    out$Total_General_Fund_Expenditure <- vapply(strsplit(out$OPI_Districts, " / ", fixed = TRUE), function(nm) {
      v <- finance$Total_General_Fund_Expenditure[match(nm, finance$OPI_District)]
      if (all(is.na(v))) NA_real_ else sum(v, na.rm = TRUE)
    }, numeric(1))
    out$Finance_FY <- as.character(finance$Finance_FY[1])
  }
  if (!is.null(county_context) && nrow(county_context) > 0) {
    cc <- county_context[!duplicated(county_context$County), , drop = FALSE]
    for (col in setdiff(names(cc), "County")) out[[col]] <- cc[[col]][match(out$County, cc$County)]
  }
  complete_opi_only_columns(out)
}

# ---- Fetchers for the OPI-only districts' context (statewide sources, keyed
# by NCES id or OPI's naming rather than the registry's hand maps) ----

# Every school system on all 9 DLI regional reports, plus the report's year.
fetch_dli_all_systems <- function() {
  texts <- lapply(names(DLI_REGION_FILENAMES), fetch_dli_region_pdf_text)
  out <- parse_dli_all_systems(texts)
  if (nrow(out) > 0) out$Salary_Year <- extract_dli_salary_year(texts[[1]])
  out
}

# SAIPE 5-17 child poverty rate per district, keyed by NCES id: the API's
# school-district code is the LEA code, so LEAID = state FIPS "30" + code.
fetch_saipe_by_leaid <- function(year = NULL, api_key = census_api_key()) {
  year <- year %||% latest_saipe_year(api_key = api_key)
  rows <- lapply(c("unified", "elementary", "secondary"), function(geocat) {
    df <- fetch_saipe_geography(geocat, year, api_key)
    code_col <- paste0("school district (", geocat, ")")
    if (nrow(df) == 0 || !code_col %in% names(df)) return(NULL)
    data.frame(LEAID = paste0(MT_STATE_FIPS, df[[code_col]]),
               Child_Poverty_Rate = clean_acs_value(suppressWarnings(as.numeric(df$SAEPOVRAT5_17RV_PT))) / 100,
               stringsAsFactors = FALSE)
  })
  out <- dplyr::bind_rows(rows)
  if (nrow(out) > 0) out$SAIPE_Year <- year
  out
}

# General Fund expenditure per district in OPI's own naming (the same
# workbook and fund as parse_opi_district_expenditures()).
opi_finance_by_district <- function(raw_df) {
  if (nrow(raw_df) == 0) return(data.frame())
  raw_df %>%
    filter(FundCode == OPI_FINANCE_GENERAL_FUND_CODE) %>%
    mutate(OPI_District = trimws(DistrictName), SumOfAmount = suppressWarnings(as.numeric(SumOfAmount))) %>%
    group_by(OPI_District) %>%
    summarize(Total_General_Fund_Expenditure = sum(SumOfAmount, na.rm = TRUE), .groups = "drop") %>%
    mutate(Finance_FY = if ("StateFY" %in% names(raw_df)) as.character(raw_df$StateFY[1]) else NA_character_) %>%
    as.data.frame()
}

# ---- Weekly OPI cross-check section of the drift issue ----
# qc: mt_discrepancy_report.csv; adoption: opi_adoption_candidates.csv;
# backlog_text: DISTRICT_BACKLOG.md (an adoption candidate already there was
# checked before, and the line says what was found). Empty when nothing to say.
build_opi_crosscheck_markdown <- function(qc, adoption, backlog_text = character(0), max_districts = 15) {
  md <- character(0)
  if (!is.null(qc) && nrow(qc) > 0) {
    fallback <- qc[grepl("returned no postings", qc$Discrepancy_Type), , drop = FALSE]
    unmatched <- qc[grepl("counted from OPI", qc$Discrepancy_Type) & !grepl("over 60 days", qc$Discrepancy_Type), , drop = FALSE]
    ghosts <- qc[grepl("ghost", qc$Discrepancy_Type), , drop = FALSE]
    if (nrow(fallback) > 0) {
      fb <- sort(table(fallback$District), decreasing = TRUE)
      md <- c(md, "#### Our scrape came back empty; OPI filled in (check these scrapers)", "",
              sprintf("- **%s**: %d OPI posting%s used", names(fb), as.integer(fb), ifelse(fb == 1, "", "s")), "")
    }
    if (nrow(unmatched) > 0) {
      by_d <- sort(table(unmatched$District), decreasing = TRUE)
      shown <- head(by_d, max_districts)
      md <- c(md, "#### On OPI but not on our scrape (counted from OPI; possible scraper misses)", "",
              sprintf("%d OPI posting%s at %d district%s we scrape matched no posting on that district's own board, so %s counted from OPI. A district that keeps appearing here either posts some jobs only on OPI or has a scraper missing postings. Districts with the most:",
                      nrow(unmatched), ifelse(nrow(unmatched) == 1, "", "s"), length(by_d), ifelse(length(by_d) == 1, "", "s"),
                      ifelse(nrow(unmatched) == 1, "it was", "they were")), "")
      for (d in names(shown)) {
        titles <- unique(unmatched$Title[unmatched$District == d])
        md <- c(md, sprintf("- **%s** (%d): %s%s", d, as.integer(shown[[d]]), paste(head(titles, 4), collapse = "; "),
                            if (length(titles) > 4) "; ..." else ""))
      }
      if (length(by_d) > max_districts) md <- c(md, sprintf("- ... and %d more districts", length(by_d) - max_districts))
      old <- sum(grepl("counted from OPI", qc$Discrepancy_Type) & grepl("over 60 days", qc$Discrepancy_Type))
      if (old > 0) md <- c(md, "", sprintf("(%d more, also counted, were posted on OPI over 60 days ago.)", old))
      if (nrow(ghosts) > 0) md <- c(md, sprintf("(%d old OPI listings at districts whose board was empty were not used.)", nrow(ghosts)))
      md <- c(md, "")
    }
  }
  if (!is.null(adoption) && nrow(adoption) > 0) {
    in_backlog <- vapply(adoption$Map_Entity, function(e) {
      stem <- mt_district_stem(strsplit(e, " / ", fixed = TRUE)[[1]][1])
      if (!nzchar(stem)) return("not in DISTRICT_BACKLOG.md yet")
      word <- paste0("\\b", gsub("([.()])", "\\\\\\1", stem), "\\b")
      lower <- tolower(backlog_text)
      # The district's own row: a table row whose first cell names it, or a
      # comma list of names; not a county column or a word inside another.
      name_cell <- sub("^\\|\\s*([^|]*)\\|.*$", "\\1", lower)
      hit <- backlog_text[grepl("^\\|", lower) & grepl(word, name_cell, perl = TRUE)]
      if (!length(hit)) hit <- backlog_text[!grepl("^\\|", lower) & grepl(word, lower, perl = TRUE)]
      if (length(hit)) paste0("in DISTRICT_BACKLOG.md: ", substr(trimws(gsub("\\s+", " ", hit[1])), 1, 110)) else "not in DISTRICT_BACKLOG.md yet"
    }, character(1))
    site <- if ("Website" %in% names(adoption)) ifelse(is.na(adoption$Website) | !nzchar(adoption$Website), "no website on OPI", adoption$Website) else "no website on OPI"
    md <- c(md, "#### Districts we don't scrape that posted on OPI (adoption candidates)", "",
            "Counted from OPI and on the map; a direct scrape would make them first-class.", "",
            sprintf("- **%s** (%s, %d posting%s) -- %s -- %s", adoption$Map_Entity, adoption$County,
                    as.integer(adoption$Postings), ifelse(adoption$Postings == 1, "", "s"), site, in_backlog), "")
  }
  if (length(md) == 0) return(character(0))
  c("", "---", "", "### OPI cross-check", "", md)
}
