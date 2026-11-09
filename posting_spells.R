# Posting spells, rebuilt (posting-dates plan, step 5; spells trust audit
# 2026-11-02). One row per posting, from the raw archives, replacing "District +
# exact title, gone = filled" with:
#
# - Identity: the posting's Posting_ID under today's rules (stable per-posting
#   URL where there is one), with earlier title-identified rows bridged to the
#   job ID the same posting carries later (AppliTrack moved to job IDs on
#   2026-11-03) when the match is unique and the two never appear in one run.
# - Start: the board's own posted date when plausible (on or before the first
#   sighting, at most 365 days before it); otherwise the first sighting, which
#   is left-censored when it was that district's first week with postings from
#   that source (the posting may have been up for months already).
# - End: a posting last seen before the latest run ended "no longer listed" only
#   when its source was healthy the next run (coverage_calendar.csv; before the
#   calendar starts, "the district returned postings from that source"). An
#   error, empty board or missing log makes the end censored, not an ending.
#   SchoolSpring endings come from the posting's own record
#   (schoolspring_endings.csv): filled / canceled / review. An ending's date is
#   the midpoint between the last sighting and the next run.
# - Excluded from durations (kept in the table, flagged): OPI rows (their titles
#   are subject areas, not postings), standing ads and pools (substitute lists,
#   "always accepting", posted over a year before we first saw them), titles
#   shared by several postings in the district (can't be told apart), and
#   left-censored starts.
#
# Durations are summarized with Kaplan-Meier (open and censored postings count
# as censored), and a median is reported only with at least `min_events`
# endings.
POSTING_SPELL_EVENTS <- c("no longer listed", "closed (confirmed)", "filled", "canceled", "review")

# Relisted: a spell whose posting dropped off and a posting with the same
# title, at the same district and source, appears in the source's very next
# run. Usually the district re-advertising, but not always: of 23 WY
# SchoolSpring cases whose old record has a final status (2026-11-09), 8 were
# "filled", a new vacancy with the same title. So it is neither linked to the
# new posting nor counted as an ending: its outcome is unknown (censored at its
# last sighting), unless the platform itself says it was filled.
relisted_next_run <- function(district, source, title, first_seen, next_run) {
  key <- paste(district, source, tolower(gsub("\\s+", " ", trimws(title))), sep = "\u001f")
  starts <- paste(key, format(first_seen), sep = "\u001f")
  !is.na(next_run) & paste(key, format(next_run), sep = "\u001f") %in% starts
}
EVERGREEN_TITLE_PATTERN <- paste0(
  "\\bsub(stitute)?s?\\b|substitute|\\bpool\\b|on[- ]call|always accepting|accepting applications|",
  "ongoing|continuous|general application|interest (form|list)|^copy of\\b")

# A stated closing date (Close_Date): 2026-11-09, 11/9/2026, "Nov 9, 2026";
# "open until filled" and the like give none.
parse_stated_close_date <- function(x) {
  x <- trimws(as.character(x))
  d <- suppressWarnings(as.Date(substr(x, 1, 10), format = "%Y-%m-%d"))
  d[is.na(d)] <- suppressWarnings(as.Date(sub("^(\\d{1,2}/\\d{1,2}/\\d{4}).*$", "\\1", x[is.na(d)]), format = "%m/%d/%Y"))
  d[is.na(d)] <- suppressWarnings(as.Date(x[is.na(d)], format = "%b %d, %Y"))
  ifelse(is.na(d), NA_character_, format(d))
}

# Counted K-12 rows of every archive from `from` on, one per Posting_ID per
# run, under the current identity and OPI rules (as
# scripts/rebuild_k12_history_from_archive.R). MT's archives before 2026-08-18
# predate Posting_Source, so their postings get different IDs (44 false
# endings on 08-07); they are left out.
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
    # Same bucket as combinedclean.csv: OPI rows' descriptions refine it (build_k12_combinedclean()).
    dplyr::mutate(Role_Hint = ifelse(Is_OPI == "TRUE" & !is.na(OPI_Description) & nzchar(OPI_Description),
                                     k12_role_hint(OPI_Description), NA_character_)) %>%
    dplyr::transmute(Run_Date = Archive_Date, Posting_ID, Posting_Identity_Method,
                     District, title, date_posted, Close_Date = parse_stated_close_date(Close_Date), url,
                     Posting_Source = dplyr::coalesce(Posting_Source, ""),
                     Is_OPI = Is_OPI == "TRUE", Role_Hint,
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
                     Is_OPI = FALSE, position = classify_he_job_type(Title), Bridgeable)
}

# A posting's start is the earliest plausible posted date it ever showed:
# PeopleAdmin's feed date moves forward when a posting is re-published (one
# Great Falls pool by two years), and from 2026-11-04 the page's own open date
# replaces it (earlier). Applied after bridging, per posting.
use_earliest_posted_date <- function(panel) {
  posted <- suppressWarnings(as.Date(panel$date_posted))
  ok <- !is.na(posted) & posted <= panel$Run_Date
  earliest <- stats::ave(ifelse(ok, as.numeric(posted), NA_real_), panel$Posting_ID,
                         FUN = function(x) if (all(is.na(x))) NA_real_ else min(x, na.rm = TRUE))
  panel$date_posted <- ifelse(is.na(earliest), NA_character_, format(as.Date(earliest, origin = "1970-01-01")))
  panel
}

# Earlier title-identified rows of a posting that later carries a stable ID:
# same source, district, title (case-insensitive) and posted date, the key
# unique on both sides, and the two never listed in the same run.
bridge_posting_ids <- function(panel) {
  key <- paste(panel$Posting_Source, panel$District, tolower(panel$title), panel$date_posted, sep = "\u001f")
  stable <- grepl("^Stable", panel$Posting_Identity_Method)
  fallback <- grepl("^Source fallback", panel$Posting_Identity_Method)
  ids_by_key <- function(sel) {
    x <- unique(data.frame(key = key[sel], id = panel$Posting_ID[sel], stringsAsFactors = FALSE))
    x[!x$key %in% x$key[duplicated(x$key)], , drop = FALSE]   # unique key -> one ID
  }
  s <- ids_by_key(stable); f <- ids_by_key(fallback)
  m <- merge(f, s, by = "key", suffixes = c("_old", "_new"))
  if (nrow(m) == 0) return(bridge_adjacent_runs(panel))
  runs_of <- split(panel$Run_Date, panel$Posting_ID)
  ok <- vapply(seq_len(nrow(m)), function(i) {
    length(intersect(runs_of[[m$id_old[i]]], runs_of[[m$id_new[i]]])) == 0 &&
      max(runs_of[[m$id_old[i]]]) < min(runs_of[[m$id_new[i]]])
  }, logical(1))
  m <- m[ok, , drop = FALSE]
  hit <- match(panel$Posting_ID, m$id_old)
  panel$Bridged_From <- ifelse(is.na(hit), NA_character_, panel$Posting_ID)
  panel$Posting_ID[!is.na(hit)] <- m$id_new[hit[!is.na(hit)]]
  bridge_adjacent_runs(panel)
}

# Second pass, for an ID change between two consecutive runs that the key above
# misses because a parser fix changed the posted date (AppliTrack, 2026-11-03:
# 52 rows had none before): a posting last seen in one run and a posting first
# seen in the next, same source, district and title (case-insensitive), unique
# on both sides, and the old posted date blank or equal to the new one. A new
# posted date means a real repost (Billings "Custodian III", 08-04 then 08-18)
# and stays separate.
bridge_adjacent_runs <- function(panel) {
  runs <- sort(unique(panel$Run_Date))
  if (is.null(panel$Bridged_From)) panel$Bridged_From <- NA_character_
  for (k in seq_len(length(runs) - 1)) {
    span <- panel %>%
      dplyr::group_by(Posting_ID) %>%
      dplyr::summarize(first = min(Run_Date), last = max(Run_Date), Posting_Source = dplyr::last(Posting_Source),
                       District = dplyr::last(District), t = tolower(dplyr::last(title)),
                       posted = dplyr::last(date_posted), .groups = "drop")
    old <- span[span$last == runs[k], ]
    # HE: only document links and title fallbacks may change ID (Bridgeable).
    if (!is.null(panel$Bridgeable)) old <- old[old$Posting_ID %in% panel$Posting_ID[panel$Bridgeable], ]
    new <- span[span$first == runs[k + 1], ]
    keyf <- function(x) paste(x$Posting_Source, x$District, x$t, sep = "\u001f")
    old <- old[!keyf(old) %in% keyf(old)[duplicated(keyf(old))], ]
    new <- new[!keyf(new) %in% keyf(new)[duplicated(keyf(new))], ]
    m <- merge(transform(old, key = keyf(old)), transform(new, key = keyf(new)), by = "key", suffixes = c("_old", "_new"))
    m <- m[is.na(m$posted_old) | !nzchar(m$posted_old) | m$posted_old == m$posted_new, , drop = FALSE]
    if (nrow(m) == 0) next
    hit <- match(panel$Posting_ID, m$Posting_ID_old)
    panel$Bridged_From[!is.na(hit)] <- panel$Posting_ID[!is.na(hit)]
    panel$Posting_ID[!is.na(hit)] <- m$Posting_ID_new[hit[!is.na(hit)]]
  }
  panel
}

# Health of a posting's source in a run: the coverage calendar where it
# covers the run (Entity = District, or the OPI feed for OPI rows); before it
# starts, whether the district returned any postings from that source.
source_health <- function(panel, calendar, district, source, is_opi, run) {
  if (is.na(run)) return(NA_character_)
  run_chr <- format(run)
  if (!is.null(calendar) && nrow(calendar) > 0 && run_chr >= min(calendar$Run_Date)) {
    entity <- if (is_opi) "OPI statewide feed" else district
    st <- calendar$Status[calendar$Run_Date == run_chr & calendar$Entity == entity]
    if (length(st) == 0) return(if (any(calendar$Run_Date == run_chr)) "not_logged" else "no_calendar")
    return(st[1])
  }
  if (any(panel$Run_Date == run & panel$District == district & panel$Posting_Source == source)) "ok_proxy" else "no_rows"
}

# `shared_titles = "fallback only"` (HE) flags a shared title only on postings
# identified by title: two "Adjunct Instructor" postings with their own
# PeopleAdmin numbers can be told apart.
# `statuses`: posting_status.csv (posting_status.R), what each posting's own
# page said after it dropped off its board (from 2026-11-10).
build_posting_spells <- function(panel, calendar = NULL, endings = NULL, shared_titles = c("all", "fallback only"),
                                 statuses = NULL) {
  shared_titles <- match.arg(shared_titles)
  if (is.null(panel$Close_Date)) panel$Close_Date <- NA_character_
  runs <- sort(unique(panel$Run_Date))
  latest <- max(runs)
  # Titles held by more than one posting in a district in any run.
  dup <- panel %>%
    dplyr::group_by(Run_Date, District, t = tolower(title)) %>%
    dplyr::filter(dplyr::n_distinct(Posting_ID) > 1) %>%
    dplyr::ungroup()
  first_source_run <- panel %>%
    dplyr::group_by(District, Posting_Source) %>%
    dplyr::summarize(Source_First_Run = min(Run_Date), .groups = "drop")

  if (!"Role_Hint" %in% names(panel)) panel$Role_Hint <- NA_character_
  sp <- panel %>%
    dplyr::arrange(Run_Date) %>%
    dplyr::group_by(Posting_ID) %>%
    dplyr::summarize(District = dplyr::last(District), Title = dplyr::last(title),
                     Position = dplyr::last(position), Role_Hint = dplyr::last(Role_Hint),
                     Posting_Source = dplyr::last(Posting_Source),
                     Identity = dplyr::last(Posting_Identity_Method), Is_OPI = any(Is_OPI),
                     Posted_Date = dplyr::first(date_posted[!is.na(date_posted) & nzchar(date_posted)], default = NA_character_),
                     URL = dplyr::last(url), First_Seen = min(Run_Date), Last_Seen = max(Run_Date),
                     Stated_Close_Date = dplyr::last(Close_Date[!is.na(Close_Date)], default = NA_character_),
                     Runs_Seen = dplyr::n_distinct(Run_Date), .groups = "drop") %>%
    dplyr::left_join(first_source_run, by = c("District", "Posting_Source"))
  sp$Shared_Title <- sp$Posting_ID %in% dup$Posting_ID
  if (shared_titles == "fallback only") sp$Shared_Title <- sp$Shared_Title & !grepl("^Stable", sp$Identity)
  sp$Runs_Spanned <- match(sp$Last_Seen, runs) - match(sp$First_Seen, runs) + 1L
  sp$Next_Run <- runs[match(sp$Last_Seen, runs) + 1L]

  sp$Next_Run_Source_Status <- vapply(seq_len(nrow(sp)), function(i)
    source_health(panel, calendar, sp$District[i], sp$Posting_Source[i], sp$Is_OPI[i], sp$Next_Run[i]), character(1))
  ss_status <- NA_character_
  if (!is.null(endings) && nrow(endings) > 0) {
    id <- ifelse(grepl("schoolspring\\.com/jobs/\\d+$", sp$URL), sub("^.*/jobs/", "", sp$URL), NA_character_)
    ss_status <- endings$Job_Status[match(id, endings$job_id)]
  }
  # The posting's own page, checked after it dropped off: closed is a
  # confirmed ending; still open means the scrape missed it (censored).
  page <- data.frame(Status = rep(NA_character_, nrow(sp)), Close = NA_character_, Checked = NA_character_,
                     stringsAsFactors = FALSE)
  if (!is.null(statuses) && nrow(statuses) > 0 && exists("posting_status_check_url")) {
    hit <- match(posting_status_check_url(sp$URL), statuses$Check_URL)
    page <- data.frame(Status = statuses$Status[hit], Close = statuses$Stated_Close_Date[hit],
                       Checked = statuses$Last_Checked[hit], stringsAsFactors = FALSE)
    page$Status[is.na(page$Checked) | page$Checked <= format(sp$Last_Seen)] <- NA_character_
  }
  sp$Page_Status <- page$Status
  sp$Stated_Close_Date <- dplyr::coalesce(sp$Stated_Close_Date, page$Close)
  sp$Ending <- dplyr::case_when(
    sp$Last_Seen == latest ~ "still listed",
    !is.na(ss_status) ~ ss_status,
    sp$Page_Status %in% "closed" ~ "closed (confirmed)",
    sp$Page_Status %in% "open" ~ "censored: still open on its page",
    sp$Next_Run_Source_Status %in% c("ok", "ok_proxy") ~ "no longer listed",
    TRUE ~ paste0("censored: source ", sp$Next_Run_Source_Status))
  relisted <- relisted_next_run(sp$District, sp$Posting_Source, sp$Title, sp$First_Seen, sp$Next_Run)
  sp$Ending[relisted & sp$Ending %in% setdiff(POSTING_SPELL_EVENTS, "filled")] <- "censored: relisted next run"
  sp$Event <- sp$Ending %in% POSTING_SPELL_EVENTS

  posted <- suppressWarnings(as.Date(substr(sp$Posted_Date, 1, 10)))
  lag <- as.numeric(sp$First_Seen - posted)
  sp$Start_Basis <- ifelse(!is.na(lag) & lag >= 0 & lag <= 365, "board posted date", "first sighting")
  sp$Start_Date <- as.Date(ifelse(sp$Start_Basis == "board posted date", posted, sp$First_Seen), origin = "1970-01-01")
  sp$Left_Censored <- sp$Start_Basis == "first sighting" & sp$First_Seen == sp$Source_First_Run
  sp$Evergreen <- grepl(EVERGREEN_TITLE_PATTERN, sp$Title, ignore.case = TRUE) | (!is.na(lag) & lag > 365)
  # The stated closing date when the posting closed on it (after the last
  # sighting, by the next run); otherwise the midpoint to the next run.
  close <- suppressWarnings(as.Date(sp$Stated_Close_Date))
  on_close <- sp$Event & !is.na(close) & !is.na(sp$Next_Run) & close >= sp$Last_Seen & close <= sp$Next_Run
  sp$End_Basis <- ifelse(on_close, "stated closing date", ifelse(sp$Event, "midpoint to next run", "censored"))
  sp$End_Date <- as.Date(ifelse(on_close, close,
                                ifelse(sp$Event, sp$Last_Seen + as.numeric(sp$Next_Run - sp$Last_Seen) / 2, sp$Last_Seen)),
                         origin = "1970-01-01")
  sp$Days_Listed <- as.numeric(sp$End_Date - sp$Start_Date)
  # Advertised application window: start to the stated closing date (needs no
  # ending); a date a year or more out is a board default, not a deadline.
  sp$Advertised_Days <- as.numeric(close - sp$Start_Date)
  sp$Advertised_Days[is.na(sp$Advertised_Days) | sp$Advertised_Days < 0 | sp$Advertised_Days > 365] <- NA
  # Age when we first saw it: a posting up since April that we first saw in
  # August is only at risk of "ending under our eyes" from then on (delayed
  # entry). Without this, long-lived postings are over-represented.
  sp$Days_Before_First_Seen <- as.numeric(sp$First_Seen - sp$Start_Date)
  sp$In_Durations <- !sp$Is_OPI & !sp$Evergreen & !sp$Shared_Title & !sp$Left_Censored
  sp %>%
    dplyr::mutate(dplyr::across(c(First_Seen, Last_Seen, Next_Run, Source_First_Run, Start_Date, End_Date), format)) %>%
    dplyr::select(Posting_ID, District, Title, Position, Role_Hint, Posting_Source, Identity, Is_OPI, URL, Posted_Date,
                  First_Seen, Last_Seen, Runs_Seen, Runs_Spanned, Next_Run, Next_Run_Source_Status, Page_Status, Ending, Event,
                  Start_Basis, Start_Date, Left_Censored, Days_Before_First_Seen, Stated_Close_Date, End_Basis, End_Date,
                  Days_Listed, Advertised_Days, Evergreen, Shared_Title, In_Durations) %>%
    dplyr::arrange(District, First_Seen, Title)
}

# Kaplan-Meier median days listed per group, over In_Durations spells, with
# delayed entry (each posting enters at its age when first seen). A posting
# seen once and still listed adds half a day of exposure so it stays valid.
summarize_posting_durations <- function(spells, group = NULL, min_events = 20) {
  s <- spells[spells$In_Durations & !is.na(spells$Days_Listed) & spells$Days_Listed >= 0, , drop = FALSE]
  groups <- if (is.null(group)) list(All = s) else split(s, s[[group]])
  dplyr::bind_rows(lapply(names(groups), function(g) {
    x <- groups[[g]]
    if (nrow(x) == 0) return(NULL)
    entry <- pmax(0, x$Days_Before_First_Seen)
    exit <- pmax(x$Days_Listed, entry + 0.5)
    fit <- survival::survfit(survival::Surv(entry, exit, x$Event) ~ 1)
    tab <- summary(fit)$table
    enough <- sum(x$Event) >= min_events
    data.frame(Group = g, Postings = nrow(x), Endings = sum(x$Event),
               Median_Days = if (enough) unname(tab["median"]) else NA_real_,
               Lower_95 = if (enough) unname(tab["0.95LCL"]) else NA_real_,
               Upper_95 = if (enough) unname(tab["0.95UCL"]) else NA_real_,
               Note = if (enough) "" else paste("fewer than", min_events, "endings"), stringsAsFactors = FALSE)
  }))
}

# --------------------------------------------------------------------------
# First seen, for the dashboard's "Posted / listed" column
# --------------------------------------------------------------------------
# Many boards give no posted date (MT: 546 of 1,380 K-12 postings on
# 2026-11-03, mostly Apptegy district sites). For those the app shows the
# first weekly run that found the posting instead. The app reads only its own
# folder and the posting IDs differ between files, so this writes a small
# lookup keyed on what the app shows: district/institution, title, link.
# Left_Censored = the posting was already up the first time we scraped that
# board, so its real start is earlier ("On the board since at least").
# Identical in the MT and WY repos; the app has its own copy of the key.
first_seen_key <- function(district, title, url) {
  sq <- function(x) tolower(gsub("\\s+", " ", trimws(as.character(x))))
  paste(sq(district), sq(title), trimws(as.character(url)), sep = " | ")
}
first_seen_lookup <- function(panel, spells, segment) {
  latest <- max(panel$Run_Date)
  cur <- panel[panel$Run_Date == latest, c("Posting_ID", "District", "title", "url"), drop = FALSE]
  cur <- merge(cur, spells[, c("Posting_ID", "First_Seen", "Left_Censored")], by = "Posting_ID")
  cur$Key <- first_seen_key(cur$District, cur$title, cur$url)
  cur <- cur[order(cur$Key, as.character(cur$First_Seen)), , drop = FALSE]
  cur <- cur[!duplicated(cur$Key), , drop = FALSE]
  data.frame(Segment = rep(segment, nrow(cur)), Key = cur$Key, First_Seen = as.character(cur$First_Seen),
             Left_Censored = as.logical(cur$Left_Censored), stringsAsFactors = FALSE)
}
