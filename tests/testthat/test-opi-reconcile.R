# opi_reconcile.R: which OPI Jobs for Teachers postings count next to our
# direct scrapes. Fixtures are real: CCD directory rows for towns with the
# tricky cases (2024, live 2026-11-02), OPI postings with their detail-page
# district (live 2026-11-02), direct postings from the committed 2026-10-27
# week, and the real registry.

xw_fixture <- function() {
  build_mt_district_crosswalk(
    read.csv(test_path("fixtures", "ccd_mt_directory_2024_crosswalk_towns.csv"), stringsAsFactors = FALSE),
    read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE),
    MT_CCD_LEA_MAP)
}
row_of <- function(xw, name) xw[xw$OPI_District == name, , drop = FALSE]

test_that("the crosswalk ties a town's other half to the registry district that covers it", {
  xw <- xw_fixture()
  # Registry stores Bigfork Elem's NCES id; Bigfork H S is the same board.
  expect_equal(row_of(xw, "Bigfork H S")$Registry_District, "Bigfork School District 38")
  expect_equal(row_of(xw, "Bigfork H S")$Match_Rule, "same town and name")
  # A county high school in a one-district town.
  expect_equal(row_of(xw, "Custer County H S")$Registry_District, "Miles City Unified School District 1")
  # Box Elder shares a mailing city with Rocky Boy, which has its own high
  # school: Box Elder's districts are not Rocky Boy's.
  expect_true(is.na(row_of(xw, "Box Elder H S")$Registry_District))
  expect_true(is.na(row_of(xw, "Box Elder Elem")$Registry_District))
  expect_equal(row_of(xw, "Box Elder H S")$Map_Entity, "Box Elder Elem / Box Elder H S")
  expect_equal(row_of(xw, "Box Elder Elem")$Map_Entity, "Box Elder Elem / Box Elder H S")
  # A separate elementary district in a scraped city stays its own entity.
  expect_true(is.na(row_of(xw, "Blue Creek Elem")$Registry_District))
  expect_equal(row_of(xw, "Blue Creek Elem")$Map_Entity, "Blue Creek Elem")
  # Only regular districts with schools (no co-ops, ranches, county offices).
  expect_false(any(c("Big Country Coop", "Yellowstone Boys & Girls Ranch", "Custer") %in% xw$OPI_District))
})

test_that("a district name CCD gives twice resolves to the registry district, never to an extra map dot", {
  xw <- xw_fixture()
  cw <- row_of(xw, "Cottonwood Elem")
  expect_equal(nrow(cw), 1)
  expect_equal(cw$Registry_District, "Cottonwood School District #57")
})

reconcile_fixture <- function(direct = read.csv(test_path("fixtures", "direct_postings_2026-10-27_reconcile.csv"),
                                                stringsAsFactors = FALSE),
                              today = as.Date("2026-11-02")) {
  opi <- read.csv(test_path("fixtures", "opi_postings_2026-11-02_reconcile.csv"), stringsAsFactors = FALSE)
  opi$District <- opi$location
  list(opi = opi, direct = direct,
       r = reconcile_opi_with_direct(opi, direct, xw_fixture(),
                                     read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE),
                                     today = today))
}

test_that("at a district we scrape, an OPI posting is dropped only when it matches a board posting", {
  f <- reconcile_fixture()
  active <- unique(f$direct$District)
  # Every OPI row is either counted or dropped, never both or neither.
  expect_equal(nrow(f$r$opi_keep) + nrow(f$r$opi_dropped), nrow(f$opi))
  # Each dropped row at an active district is a match, and flagged a board posting.
  at_active <- f$r$opi_dropped$District %in% active
  expect_true(all(f$r$opi_dropped$OPI_Drop_Reason[at_active] %in% c("same opening on district board", "OPI duplicate listing")))
  expect_gt(sum(f$r$direct_df$Also_On_OPI), 0)
  expect_lte(sum(f$r$direct_df$Also_On_OPI), sum(f$r$opi_dropped$OPI_Drop_Reason == "same opening on district board"))
  # Unmatched OPI postings at active districts count, under the registry district, and are in the QC report.
  kept_active <- f$r$opi_keep[f$r$opi_keep$District %in% active, ]
  expect_gt(nrow(kept_active), 0)
  expect_equal(sum(grepl("counted from OPI", f$r$qc$Discrepancy_Type)), nrow(kept_active))
  # An empty board's old OPI listings stay out (stale, dropped).
  inactive <- !at_active
  expect_true(all(f$r$opi_dropped$OPI_Drop_Reason[inactive] == "stale OPI listing, district board empty"))
})

test_that("OPI's repeat listings of one job count once", {
  opi <- data.frame(title = c("Special Education", "Special Education", "Music"), date_posted = "10/25/2026", location = "Richey",
                    District = "Richey", url = OPI_STATEWIDE_BOARD_URL, Posting_Source = "OPI Jobs for Teachers (statewide)",
                    OPI_District = c("Richey Elem", "Richey H S", "Richey Elem"),
                    OPI_Description = c(rep("Richey Public Schools is seeking a K-12 Special Education teacher for the 2026-27 school year.", 2),
                                        "Richey Public Schools is seeking a K-12 Music teacher for the 2026-27 school year."),
                    stringsAsFactors = FALSE)
  reg <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  dir <- data.frame(title = "2026-27 Assistant Cook / Custodian", date_posted = NA, location = "Richey", url = "https://example.org/a",
                    District = "Richey Public Schools", Posting_Source = "Richey district site (direct board)", stringsAsFactors = FALSE)
  xw <- data.frame(LEAID = c("1", "2"), OPI_District = c("Richey Elem", "Richey H S"), City = "Richey", County = "Dawson County",
                   Latitude = 47.6, Longitude = -105.1, Registry_District = "Richey Public Schools", Match_Rule = "registry NCES id",
                   Map_Entity = "Richey Public Schools", stringsAsFactors = FALSE)
  r <- reconcile_opi_with_direct(opi, dir, xw, reg, today = as.Date("2026-11-03"))
  # Richey's board lists only a cook/custodian: its two teaching jobs count, the repeat SPED listing doesn't.
  expect_equal(sort(r$opi_keep$title), c("Music", "Special Education"))
  expect_equal(r$opi_dropped$OPI_Drop_Reason, "OPI duplicate listing")
  expect_true(all(r$opi_keep$District == "Richey Public Schools"))
})

test_that("districts we don't scrape count, under their map entity, and are listed for adoption", {
  f <- reconcile_fixture()
  box <- f$r$opi_keep[f$r$opi_keep$OPI_District %in% c("Box Elder Elem", "Box Elder H S"), ]
  expect_equal(nrow(box), 7)
  expect_true(all(box$District == "Box Elder Elem / Box Elder H S"))
  expect_true("Box Elder Elem / Box Elder H S" %in% f$r$adoption$Map_Entity)
  expect_equal(f$r$adoption$Postings[f$r$adoption$Map_Entity == "Box Elder Elem / Box Elder H S"], 7)
  expect_true(all(f$r$opi_keep$District[f$r$opi_keep$OPI_District == "Blue Creek Elem"] == "Blue Creek Elem"))
  # Employers outside CCD keep OPI's name and are not adoption candidates.
  expect_true(all(f$r$opi_keep$District[f$r$opi_keep$OPI_District == "St Labre Indian H S"] == "St Labre Indian H S"))
  expect_false("St Labre Indian H S" %in% f$r$adoption$Map_Entity)
})

test_that("a registry district whose scrape returned nothing is filled from OPI's recent postings and reported", {
  # Cottonwood #57 has no direct rows in the fixture week; its two OPI
  # postings are dated 2026-05-31 and 2026-06-08. A run in mid-July uses them.
  f <- reconcile_fixture(today = as.Date("2026-07-15"))
  cw <- f$r$opi_keep[f$r$opi_keep$OPI_District == "Cottonwood Elem", ]
  expect_equal(nrow(cw), 2)
  expect_true(all(cw$District == "Cottonwood School District #57"))
  expect_equal(sum(f$r$qc$District == "Cottonwood School District #57" &
                     grepl("returned no postings", f$r$qc$Discrepancy_Type)), 2)
  # Same for Billings if its scrape had come back empty: its two June 1
  # postings fill in; the two May 13 ones are 63 days old by July 15.
  g <- reconcile_fixture(direct = read.csv(test_path("fixtures", "direct_postings_2026-10-27_reconcile.csv"),
                                           stringsAsFactors = FALSE) %>%
                           dplyr::filter(District != "Billings Public Schools"),
                         today = as.Date("2026-07-15"))
  expect_equal(sum(g$r$opi_keep$District == "Billings Public Schools"), 2)
})

test_that("an empty scrape is not filled with OPI listings over 60 days old", {
  # Seeley Lake, 2026-11-02: no openings on its page, three May-June OPI
  # listings. At the fixture's run date Cottonwood's are 5 months old.
  f <- reconcile_fixture()
  expect_false(any(f$r$opi_keep$OPI_District == "Cottonwood Elem"))
  expect_equal(sum(f$r$opi_dropped$OPI_District == "Cottonwood Elem"), 2)
  cw_qc <- f$r$qc[f$r$qc$District == "Cottonwood School District #57", ]
  expect_equal(nrow(cw_qc), 2)
  expect_true(all(grepl("ghost", cw_qc$Discrepancy_Type)))
  expect_false(any(grepl("returned no postings", cw_qc$Discrepancy_Type)))
  # Dates in either format; unknown dates are not stale.
  expect_equal(opi_listing_is_stale(c("2026-08-01", "08/01/2026", "2026-10-01", NA, ""), as.Date("2026-11-02")),
               c(TRUE, TRUE, FALSE, FALSE, FALSE))
})

test_that("without OPI_District a posting falls back to its town, conservatively", {
  f <- reconcile_fixture()
  opi <- f$opi
  opi$OPI_District <- NA
  r <- reconcile_opi_with_direct(opi, f$direct, xw_fixture(),
                                 read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE))
  # Blue Creek's Billings address reads as Billings, not as an extra map dot;
  # counted there only if no Billings board posting is the same opening.
  expect_false(any(r$opi_keep$District == "Blue Creek Elem"))
  blue <- f$opi$OPI_District == "Blue Creek Elem"
  expect_true(all(c(r$opi_keep$District, r$opi_dropped$District)[match(f$opi$title[blue], c(r$opi_keep$title, r$opi_dropped$title))] ==
                  "Billings Public Schools"))
})

test_that("an archive written with OPI_Counted is taken as written", {
  xw <- xw_fixture()
  reg <- read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE)
  wk <- data.frame(title = c("Mathematics", "HS Math Teacher"), url = c(OPI_STATEWIDE_BOARD_URL, "https://example.org/1"),
                   District = c("Bigfork School District 38", "Bigfork School District 38"),
                   Posting_Source = c("OPI Jobs for Teachers (statewide)", "Apptegy district site (direct board)"),
                   Posting_ID = c("a", "b"), OPI_Counted = c(FALSE, TRUE), stringsAsFactors = FALSE)
  r <- opi_rule_for_archive(wk, xw, reg)
  expect_equal(r$Counted, c(FALSE, TRUE))
  expect_equal(r$Is_OPI, c(TRUE, FALSE))
})

test_that("every DLI school system is read, so districts we don't scrape get teacher pay", {
  dli <- parse_dli_all_systems(readLines(test_path("fixtures", "dli_northeast_page2.txt")) |> paste(collapse = "\n"))
  expect_equal(dli$Teacher_Avg_Salary[dli$DLI_Name == "Frontier Elementary"], 51400)
  expect_equal(dli$Teacher_Avg_Salary[dli$DLI_Name == "Savage Public Schools"], 48600)
  expect_true(is.na(dli$Teacher_Avg_Salary[dli$DLI_Name == "Frazer Public Schools"]))   # ND
  expect_false(any(grepl("School System Name", dli$DLI_Name)))
})

test_that("opi_only_districts.csv has the same columns every week, even with no rows", {
  e <- complete_opi_only_columns(NULL)
  expect_equal(nrow(e), 0)
  expect_equal(names(e), OPI_ONLY_DISTRICT_COLUMNS)
  xw <- xw_fixture()
  o <- build_opi_only_districts(xw, c("Box Elder Elem / Box Elder H S", "Blue Creek Elem"))
  expect_equal(names(o), OPI_ONLY_DISTRICT_COLUMNS)
  expect_equal(sort(o$District), c("Blue Creek Elem", "Box Elder Elem / Box Elder H S"))
  expect_true(all(o$Data_Coverage == OPI_ONLY_COVERAGE))
  expect_false(any(is.na(o$Latitude)))
})

test_that("the weekly OPI cross-check lists misses by district, empty scrapes, and adoption candidates", {
  f <- reconcile_fixture(today = as.Date("2026-07-15"))
  backlog <- readLines(here::here("DISTRICT_BACKLOG.md"))
  md <- build_opi_crosscheck_markdown(f$r$qc, f$r$adoption, backlog)
  expect_true(any(grepl("^### OPI cross-check", md)))
  expect_true(any(grepl("Cottonwood School District #57\\*\\*: 2 OPI postings used", md)))
  box <- md[grepl("Box Elder Elem / Box Elder H S", md)]
  expect_length(box, 1)
  # Box Elder's own backlog row, not a line that merely mentions Hill County.
  expect_match(box, "Box Elder Public Schools #13", fixed = TRUE)
  expect_length(build_opi_crosscheck_markdown(NULL, NULL, backlog), 0)
})

test_that("archived weeks keep their old OPI fill-ins: the 60-day limit applies only to new runs", {
  # Judged against today's registry, an old week's "empty scrape" is mostly a
  # district not adopted yet; its months-old OPI postings still counted then.
  opi <- read.csv(test_path("fixtures", "opi_postings_2026-11-02_reconcile.csv"), stringsAsFactors = FALSE)
  direct <- read.csv(test_path("fixtures", "direct_postings_2026-10-27_reconcile.csv"), stringsAsFactors = FALSE)
  wk <- dplyr::bind_rows(opi %>% dplyr::mutate(District = location), direct)
  wk$Archive_Date <- "2026-11-02"
  wk$Posting_ID <- paste0("id", seq_len(nrow(wk)))
  r <- opi_rule_for_archive(wk, xw_fixture(), read.csv(here::here("k12_district_registry.csv"), stringsAsFactors = FALSE))
  cw <- wk$OPI_District %in% "Cottonwood Elem"
  expect_true(all(r$Counted[cw]))
  expect_true(all(r$District[cw] == "Cottonwood School District #57"))
})
