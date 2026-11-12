# Posting spells: MT's panels and rules. The spells themselves (bridging,
# endings, starts, flags, durations, the first-seen lookup) are built by the
# edjobs package (R/posting_spells.R, moved in phase 4, 2026-11-11); this file
# keeps what is Montana's own: reading MT's archives into a panel, the HE
# posting identity, and the rules MT's spells are built under.
library(edjobs)

# MT's rules differ from the package defaults (the WY spells trust audit's)
# where MT hasn't adopted a change yet; each is a decision, measured in
# claude-notes/2026-11-11_spells-convergence.md.
# - OPI rows are the feed; their titles are subject areas, not postings, so
#   they stay out of durations.
# - Shared titles: any title two postings hold in a district in a run (K-12);
#   only title-identified postings (HE: two "Adjunct Instructor" postings with
#   their own PeopleAdmin numbers can be told apart).
# - No partial-run or moved-boards censoring, no left-censoring after a gap.
# - Pools count as standing ads (one pattern), not a flag of their own.
MT_EVERGREEN_TITLE_PATTERN <- paste0(
  "\\bsub(stitute)?s?\\b|substitute|\\bpool\\b|on[- ]call|always accepting|accepting applications|",
  "ongoing|continuous|general application|interest (form|list)|^copy of\\b")
mt_spell_rules <- function(shared_titles) {
  spell_rules(feed_entity = "OPI statewide feed", feed_in_durations = FALSE, shared_titles = shared_titles,
              partial_min_previous = Inf, moved_boards = FALSE, left_censor_after_gap = FALSE,
              evergreen_pattern = MT_EVERGREEN_TITLE_PATTERN, pool_pattern = NA_character_)
}
MT_K12_SPELL_RULES <- mt_spell_rules("all")
MT_HE_SPELL_RULES <- mt_spell_rules("fallback only")

# Counted K-12 rows of every archive from `from` on, one per Posting_ID per
# run, under the current identity and OPI rules (as
# scripts/rebuild_k12_history_from_archive.R). MT's archives before 2026-08-18
# predate Posting_Source, so their postings get different IDs (44 false
# endings on 08-07); they are left out. Every K-12 row's ID may be bridged
# across consecutive runs (`Bridgeable`): AppliTrack's move to job IDs on
# 2026-11-03 changed stable IDs too.
k12_posting_panel <- function(archive_dir = "Archivek12_Data", crosswalk, registry, from = as.Date("2026-08-18")) {
  files <- list.files(archive_dir, "^combined_\\d{4}-\\d{2}-\\d{2}\\.csv$", full.names = TRUE)
  files <- files[as.Date(sub("^combined_(.*)\\.csv$", "\\1", basename(files))) >= from]
  # One file at a time (read_counted_archive_week(), opi_reconcile.R): binding
  # the archives first left older weeks with an all-NA OPI_Counted column, so
  # their OPI rows skipped reconciliation (all counted, under their raw town).
  d <- dplyr::bind_rows(lapply(files, function(f) {
    w <- read_counted_archive_week(f, crosswalk, registry)
    w[] <- lapply(w, as.character)
    w
  })) %>%
    dplyr::mutate(Archive_Date = as.Date(Archive_Date))
  if (!"Close_Date" %in% names(d)) d$Close_Date <- NA_character_
  if (!"OPI_Description" %in% names(d)) d$OPI_Description <- NA_character_
  d %>%
    dplyr::filter(!is_placeholder_posting(title)) %>%
    # Same bucket as combinedclean.csv: OPI rows' descriptions refine it (edjobs::build_k12_combinedclean()).
    dplyr::mutate(Role_Hint = ifelse(Is_OPI == "TRUE" & !is.na(OPI_Description) & nzchar(OPI_Description),
                                     k12_role_hint(OPI_Description), NA_character_)) %>%
    dplyr::transmute(Run_Date = Archive_Date, Posting_ID, Posting_Identity_Method,
                     District, title, date_posted, Close_Date = parse_stated_close_date(Close_Date), url,
                     Posting_Source = dplyr::coalesce(Posting_Source, ""),
                     Is_Feed = Is_OPI == "TRUE", Role_Hint, Bridgeable = TRUE,
                     position = classify_k12_position(title, Role_Hint))
}

# ---------------------------------------------------------------------------
# Higher ed. The raw HE archives (Archived_HE_Data/hedata_<date>.xlsx) carry no
# Posting_ID, so identity is set here:
# - A per-posting link is the ID: PeopleAdmin /postings/<n>, schooljobs,
#   Paycom, isolved, ADP (is_stable_posting_url()), applytojob /apply/<key>/,
#   Rocky's /employment/opportunities/<slug>/, and posting documents (PDF, DOCX,
#   Dawson's file_download, Aaniiih Nakoda's _files/ugd). A link held by two
#   titles in one run is a board page, never an ID.
# - Otherwise (Carroll, Miles, Salish Kootenai, Stone Child post every opening
#   on one employment page) institution + title, with an occurrence suffix.
# Only document links and title fallbacks may be bridged across consecutive
# runs: a college re-uploading the same PDF under a new name (Aaniiih Nakoda,
# 09-29/10-06) is the same posting, but a new PeopleAdmin or schooljobs number
# is a new requisition.
# ---------------------------------------------------------------------------
HE_POSTING_URL_PATTERN <- paste0(
  "/postings/\\d+|/apply/[A-Za-z0-9]+/|/employment/opportunities/[^/]+/?$|",
  "\\.(pdf|docx?)$|/file_download/|/_files/ugd/")
HE_DOCUMENT_URL_PATTERN <- "\\.(pdf|docx?)$|/file_download/|/_files/ugd/|/uploads/|/files/"

add_he_posting_identity <- function(d) {
  url <- normalize_posting_text(d$Link)
  inst <- normalize_posting_identity_component(d$Institution)
  title <- normalize_posting_identity_component(d$Title)
  shaped <- !is.na(url) & nzchar(url) &
    (is_stable_posting_url(url) | grepl(HE_POSTING_URL_PATTERN, url, ignore.case = TRUE, perl = TRUE))
  # A link shared by different titles in any run is a board page.
  shared <- stats::ave(title, inst, d$Archive_Date, tolower(url), FUN = function(x) length(unique(x)) > 1) == "TRUE"
  board_link <- tolower(url) %in% unique(tolower(url[shared]))
  stable <- shaped & !board_link
  base <- paste("he-fallback", inst, title, sep = "\u001f")
  occ <- stats::ave(seq_along(base), base, d$Archive_Date, FUN = seq_along)
  d$Posting_ID <- ifelse(stable, paste0("url:", tolower(url)), paste0("fallback:", base, "#", occ))
  d$Posting_Identity_Method <- ifelse(stable, "Stable per-posting URL",
                                      "Source fallback: institution + title (no stable posting URL)")
  d$Bridgeable <- !stable | grepl(HE_DOCUMENT_URL_PATTERN, url, ignore.case = TRUE, perl = TRUE)
  d
}

# Every HE archive from `from` on (2026-08-11 is the first run that covers
# every institution; 08-06/08-07 ran only a few), one row per Posting_ID per
# run, in the shape build_posting_spells() takes (District = Institution,
# position = HE job type, Posting_Source = Institution: each college is its own
# source in the coverage calendar).
he_posting_panel <- function(archive_dir = "Archived_HE_Data", from = as.Date("2026-08-11")) {
  files <- list.files(archive_dir, "^hedata_\\d{4}-\\d{2}-\\d{2}\\.xlsx$", full.names = TRUE)
  files <- files[as.Date(sub("^hedata_(.*)\\.xlsx$", "\\1", basename(files))) >= from]
  d <- dplyr::bind_rows(lapply(files, function(f) {
    x <- as.data.frame(readxl::read_excel(f, col_types = "text"))
    x$Archive_Date <- sub("^hedata_(.*)\\.xlsx$", "\\1", basename(f))
    x[, intersect(c("Title", "Location", "Posted_Date", "Institution", "Link", "Close_Date", "Archive_Date"), names(x))]
  }))
  # Zero-width characters (Aaniiih Nakoda's "Facilities Manager\u200b") would split one posting in two.
  d$Title <- trimws(gsub("[\u200b-\u200d\ufeff]", "", normalize_posting_text(d$Title), perl = TRUE))
  d$Institution <- canonicalize_he_institution(normalize_posting_text(d$Institution))
  d <- d[!is.na(d$Title) & nzchar(d$Title) & !is_placeholder_posting(d$Title), , drop = FALSE]
  d <- add_he_posting_identity(d)
  d %>%
    dplyr::mutate(Run_Date = as.Date(Archive_Date)) %>%
    dplyr::distinct(Posting_ID, Run_Date, .keep_all = TRUE) %>%
    dplyr::transmute(Run_Date, Posting_ID, Posting_Identity_Method, District = Institution, title = Title,
                     date_posted = substr(Posted_Date, 1, 10),
                     Close_Date = if ("Close_Date" %in% names(d)) parse_stated_close_date(Close_Date) else NA_character_,
                     url = Link, Posting_Source = Institution,
                     Is_Feed = FALSE, position = classify_he_job_type(Title), Bridgeable)
}
