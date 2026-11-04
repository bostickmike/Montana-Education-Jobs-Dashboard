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
POSTING_SPELL_EVENTS <- c("no longer listed", "filled", "canceled", "review")
EVERGREEN_TITLE_PATTERN <- paste0(
  "\\bsub(stitute)?s?\\b|substitute|\\bpool\\b|on[- ]call|always accepting|accepting applications|",
  "ongoing|continuous|general application|interest (form|list)|^copy of\\b")

# Counted K-12 rows of every archive from `from` on, one per Posting_ID per
# run, under the current identity and OPI rules (as
# scripts/rebuild_k12_history_from_archive.R). MT's archives before 2026-08-18
# predate Posting_Source, so their postings get different IDs (44 false
# endings on 08-07); they are left out.
k12_posting_panel <- function(archive_dir = "Archivek12_Data", crosswalk, registry, from = as.Date("2026-08-18")) {
  files <- list.files(archive_dir, "^combined_\\d{4}-\\d{2}-\\d{2}\\.csv$", full.names = TRUE)
  files <- files[as.Date(sub("^combined_(.*)\\.csv$", "\\1", basename(files))) >= from]
  d <- dplyr::bind_rows(lapply(files, function(f) {
    x <- utils::read.csv(f, colClasses = "character", check.names = FALSE)
    x$Archive_Date <- sub("^combined_(.*)\\.csv$", "\\1", basename(f))
    x
  })) %>%
    dplyr::select(-dplyr::any_of(c("X", "Posting_ID", "Posting_Identity_Method"))) %>%
    dplyr::mutate(Archive_Date = as.Date(Archive_Date),
                  dplyr::across(dplyr::any_of(c("title", "position", "location", "url", "District", "Posting_Source")),
                                normalize_posting_text)) %>%
    add_k12_posting_identity() %>%
    dplyr::distinct(Posting_ID, Archive_Date, .keep_all = TRUE)
  d <- dplyr::bind_rows(lapply(split(d, d$Archive_Date), function(week) {
    rule <- opi_rule_for_archive(week, crosswalk, registry)
    week$District <- rule$District
    week[rule$Counted, , drop = FALSE]
  }))
  d %>%
    dplyr::filter(!is_placeholder_posting(title)) %>%
    dplyr::transmute(Run_Date = Archive_Date, Posting_ID, Posting_Identity_Method,
                     District = canonicalize_k12_district(District), title, date_posted, url,
                     Posting_Source = dplyr::coalesce(Posting_Source, ""),
                     Is_OPI = is_opi_statewide_posting(url) | Posting_Source == "OPI Jobs for Teachers (statewide)",
                     position = classify_k12_position(title))
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

build_posting_spells <- function(panel, calendar = NULL, endings = NULL) {
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

  sp <- panel %>%
    dplyr::arrange(Run_Date) %>%
    dplyr::group_by(Posting_ID) %>%
    dplyr::summarize(District = dplyr::last(District), Title = dplyr::last(title),
                     Position = dplyr::last(position), Posting_Source = dplyr::last(Posting_Source),
                     Identity = dplyr::last(Posting_Identity_Method), Is_OPI = any(Is_OPI),
                     Posted_Date = dplyr::first(date_posted[!is.na(date_posted) & nzchar(date_posted)], default = NA_character_),
                     URL = dplyr::last(url), First_Seen = min(Run_Date), Last_Seen = max(Run_Date),
                     Runs_Seen = dplyr::n_distinct(Run_Date), .groups = "drop") %>%
    dplyr::left_join(first_source_run, by = c("District", "Posting_Source"))
  sp$Shared_Title <- sp$Posting_ID %in% dup$Posting_ID
  sp$Runs_Spanned <- match(sp$Last_Seen, runs) - match(sp$First_Seen, runs) + 1L
  sp$Next_Run <- runs[match(sp$Last_Seen, runs) + 1L]

  sp$Next_Run_Source_Status <- vapply(seq_len(nrow(sp)), function(i)
    source_health(panel, calendar, sp$District[i], sp$Posting_Source[i], sp$Is_OPI[i], sp$Next_Run[i]), character(1))
  ss_status <- NA_character_
  if (!is.null(endings) && nrow(endings) > 0) {
    id <- ifelse(grepl("schoolspring\\.com/jobs/\\d+$", sp$URL), sub("^.*/jobs/", "", sp$URL), NA_character_)
    ss_status <- endings$Job_Status[match(id, endings$job_id)]
  }
  sp$Ending <- dplyr::case_when(
    sp$Last_Seen == latest ~ "still listed",
    !is.na(ss_status) ~ ss_status,
    sp$Next_Run_Source_Status %in% c("ok", "ok_proxy") ~ "no longer listed",
    TRUE ~ paste0("censored: source ", sp$Next_Run_Source_Status))
  sp$Event <- sp$Ending %in% POSTING_SPELL_EVENTS

  posted <- suppressWarnings(as.Date(substr(sp$Posted_Date, 1, 10)))
  lag <- as.numeric(sp$First_Seen - posted)
  sp$Start_Basis <- ifelse(!is.na(lag) & lag >= 0 & lag <= 365, "board posted date", "first sighting")
  sp$Start_Date <- as.Date(ifelse(sp$Start_Basis == "board posted date", posted, sp$First_Seen), origin = "1970-01-01")
  sp$Left_Censored <- sp$Start_Basis == "first sighting" & sp$First_Seen == sp$Source_First_Run
  sp$Evergreen <- grepl(EVERGREEN_TITLE_PATTERN, sp$Title, ignore.case = TRUE) | (!is.na(lag) & lag > 365)
  sp$End_Date <- as.Date(ifelse(sp$Event, sp$Last_Seen + as.numeric(sp$Next_Run - sp$Last_Seen) / 2, sp$Last_Seen),
                         origin = "1970-01-01")
  sp$Days_Listed <- as.numeric(sp$End_Date - sp$Start_Date)
  # Age when we first saw it: a posting up since April that we first saw in
  # August is only at risk of "ending under our eyes" from then on (delayed
  # entry). Without this, long-lived postings are over-represented.
  sp$Days_Before_First_Seen <- as.numeric(sp$First_Seen - sp$Start_Date)
  sp$In_Durations <- !sp$Is_OPI & !sp$Evergreen & !sp$Shared_Title & !sp$Left_Censored
  sp %>%
    dplyr::mutate(dplyr::across(c(First_Seen, Last_Seen, Next_Run, Source_First_Run, Start_Date, End_Date), format)) %>%
    dplyr::select(Posting_ID, District, Title, Position, Posting_Source, Identity, Is_OPI, URL, Posted_Date,
                  First_Seen, Last_Seen, Runs_Seen, Runs_Spanned, Next_Run, Next_Run_Source_Status, Ending, Event,
                  Start_Basis, Start_Date, Left_Censored, Days_Before_First_Seen, End_Date, Days_Listed, Evergreen, Shared_Title, In_Durations) %>%
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
