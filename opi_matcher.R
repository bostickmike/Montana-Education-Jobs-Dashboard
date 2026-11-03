# Matching an OPI Jobs for Teachers posting to the same opening on a district's
# own job board (used by opi_reconcile.R). Deterministic, built and measured
# against hand-labeled real postings (2026-11-03; fixtures
# opi_match_labels_*.csv, test-opi-matcher.R):
#   1. opi_job_phrase(): the job the OPI posting is for, from its description
#      ("Position: X", "seeking a X", else its opening words), so boilerplate
#      ("reports to the principal", "coaching positions available") can't decide.
#   2. opi_match_score(): role/subject/level tokens (OPI_ROLE_LEXICON). Every role
#      the board title names must appear in the OPI posting; decisive roles
#      (SPED, sub vs long-term sub, counselor, principal ...) and grade level
#      must agree both ways; the school breaks ties.
#   3. Otherwise opi_word_sim(): weighted word overlap (rare words like
#      "visually", "colony", "charter" count most) under the same conflict checks.
# Untouched-test results before the last round of fixes: 17/18 same-job
# postings matched, 1 matched to the wrong posting, 2/15 not-on-board postings
# wrongly matched (claude-notes/2026-11-03_posting-level-dedup.md).

# Role lexicon: canonical token -> regex (lower-case text)
OPI_ROLE_LEXICON <- c(
  MATH = "\\bmath", SCI = "(?<!consumer )(?<!family consumer )\\bscience|physics|chemistry|biology|robotics", ENG = "\\benglish\\b|language arts|\\bela\\b",
  SS = "social studies|\\bhistory\\b|government|civics", MUSIC = "\\bmusic|\\bband\\b|choir|orchestra", PE = "physical ed|\\bp\\.?e\\.?\\b|health enhancement",
  ART = "\\bart\\b", LANG = "spanish|french|german|foreign language|world language|salish|nakoda|\\bcrow language",
  LIB = "librar|media specialist", COUNSEL = "counsel(or|ing)", PSYCH = "psycholog|\\bpsych\\b", SLP = "speech[- ]?(and )?language|\\bslp\\b|speech patholog",
  OT = "occupational therap", PT = "physical therap", DEAF = "deaf|hard of hearing", FCS = "family (and |& )?consumer|\\bfcs\\b",
  AG = "agricultur|vo-?ag|\\bffa\\b", BUSED = "business (ed|teacher|and marketing|education)", CTE = "industrial|technology education|tech ed|welding|\\bcte\\b|technical education",
  APRIN = "assistant principal|vice principal", ADMIN = "^administrative -|\\bdean\\b|\\badministrator\\b", CURRIC = "curriculum director|curriculum coordinator|director of curriculum", ACTDIR = "activities director|athletic director|activities coordinator|athletics and activities", PRIN = "(?<!assistant )(?<!vice )principal", SUPT = "superintendent", DIRECTOR = "director|coordinator",
  NURSE = "\\bnurse", SPED = "special ed|\\bsped\\b|^se - |life skills|resource teacher|behavior (teacher|specialist)", PARA = "para(professional|educator|-educator)?s?\\b|\\baide\\b",
  LTS = "long[- ]term sub|\\blts\\b|\\blta\\b|long[- ]term assignment|daily sub rate", SUB = "(?<!long-term )(?<!long term )\\bsubstitute", CLERK = "clerk|payroll|secretar|administrative assistant",
  INTERV = "intervention|title i\\b|reading specialist", EC = "early childhood|pre-?k\\b|preschool|head start", DRED = "driver'?s'? ed|traffic ed",
  COACH = "\\bcoach", CUST = "custod|janitor", COOK = "\\bcook|food service|kitchen", BUSDRV = "bus driver",
  ELEM = "elementary|kindergarten|\\bk-?[1-6]\\b|\\b[1-6](st|nd|rd|th)\\b.{0,12}grade|grade classroom|primary")
OPI_SPORTS <- c(FOOTBALL = "football", BASKETBALL = "basketball", VOLLEYBALL = "volleyball", WRESTLING = "wrestling", TRACK = "\\btrack|cross country",
  SOCCER = "soccer", SOFTBALL = "softball", BASEBALL = "baseball", GOLF = "\\bgolf", TENNIS = "tennis", SWIM = "swim", CHEER = "cheer|spirit squad",
  SPEECH = "speech (and|&) debate|forensics|debate|drama")
OPI_LEVELS <- c(JH = "junior high|middle school|\\bms\\b|\\bjh\\b|7-8|7th|8th|5-8|6-8", HS = "high school|\\bhs\\b|9-12|7-12|6-12|secondary")
# Tokens that must agree: present on one side's job, absent on the other -> different job
OPI_DECISIVE <- c("SPED", "PARA", "LTS", "SUB", "APRIN", "PRIN", "SUPT", "COUNSEL", "PSYCH", "SLP", "OT", "PT", "DEAF", "LIB", "NURSE", "CLERK", "EC", "COACH", "CURRIC", "ACTDIR", "INTERV", "ADMIN")
opi_tokens <- function(txt, lex) { t <- tolower(txt); names(lex)[vapply(lex, function(r) grepl(r, t, perl = TRUE), logical(1))] }

# The job the OPI posting is for, from its description: the words after
# "Position:", "Title:", "seeking a ..." etc., else its opening words. Role
# and level decisions use only this phrase (plus OPI's category title when
# the phrase is empty), so boilerplate ("reports to the principal", "video
# from the superintendent", "coaching positions available") can't decide.
opi_job_phrase <- function(desc, title = rep("", length(desc))) {
  d <- gsub("\\s+", " ", as.character(desc)); d[is.na(d)] <- ""
  # Boilerplate first, so it can't become "the job" (Libby: "Coaching
  # Opportunities Available NATURE OF POSITION ...").
  d <- trimws(gsub("(?i)^(coaching (opportunities|positions?) (may be |are )?available|announcement of vacancy[^:]*)\\s*", "", d, perl = TRUE))
  cut <- function(x) sub("(?i)(\\s(for|beginning|starting|to join|who|that|at|location|salary)\\s|[!*;:]|\\.(?!\\d)|\\s20\\d\\d).*$", "", substr(x, 1, 90), perl = TRUE)
  has_role <- function(x) length(opi_tokens(x, c(OPI_ROLE_LEXICON, OPI_LEVELS))) > 0
  vapply(seq_along(d), function(i) {
    x <- d[i]
    m <- regexpr("(?i)(job title|position|title)\\s*:\\s*(the position\\s*:\\s*)?|(?i)(seeking|looking for|hiring|accepting applications for|opening for|searching for|inviting)\\s+(applications for\\s+|qualified applicants for\\s+)?((a|an)\\s+)?((?!applications)\\w+,?\\s+){0,4}?(?=[A-Z0-9.])", x, perl = TRUE)
    cand <- if (m > 0) cut(substr(x, m + attr(m, "match.length"), nchar(x))) else ""
    if (has_role(cand)) return(trimws(cand))
    opening <- cut(x)
    if (has_role(opening)) return(trimws(opening))
    ""
  }, character(1))
}
opi_clean_desc <- function(desc) gsub("(?i)reports? to:?\\s*[^.:]{0,40}|video from [^.]{0,40}|coaching positions? (may be |are )?available[^.]*", " ", desc, perl = TRUE)

opi_match_score <- function(opi_title, phrase, opi_full, school, d_title, d_loc) {
  opi_title <- sub("(?i)^cte\\s*[-\u2013]\\s*", "", opi_title, perl = TRUE)
  focus <- if (nzchar(trimws(phrase))) phrase else opi_title
  ot <- opi_tokens(focus, OPI_ROLE_LEXICON)
  # The phrase names only a school or grade ("Rocky Boy Elementary School is
  # inviting ..."): OPI's category title supplies the role.
  if (!length(setdiff(ot, "ELEM"))) {
    tt <- opi_tokens(opi_title, OPI_ROLE_LEXICON)
    # ...but not its level: a phrase that states a grade band keeps it.
    if (length(opi_tokens(focus, OPI_LEVELS))) tt <- setdiff(tt, "ELEM")
    ot <- union(ot, tt)
  }
  of <- opi_tokens(paste(opi_title, phrase, substr(opi_clean_desc(opi_full), 1, 300)), OPI_ROLE_LEXICON)
  dt <- opi_tokens(d_title, OPI_ROLE_LEXICON)
  ol <- opi_tokens(paste(focus), OPI_LEVELS); dl <- opi_tokens(paste(d_title, d_loc), OPI_LEVELS)
  # Grade level must agree both ways, elementary included.
  lo <- union(ol, intersect(ot, "ELEM")); ld <- union(dl, intersect(dt, "ELEM"))
  if (length(lo) && length(ld) && !length(intersect(lo, ld))) return(-Inf)
  if (length(dt) == 0) {                                   # role-less board title ("Junior High 7-8")
    if (length(intersect(ot, OPI_DECISIVE)) == 0 && length(ol) && length(intersect(ol, dl))) return(0.5) else return(-Inf)
  }
  rel <- c("PT", "OT", "SLP", "PSYCH", "DEAF")
  dt_need <- if (any(rel %in% dt)) setdiff(dt, "SPED") else dt
  if (!all(dt_need %in% of)) return(-Inf)                  # every role the board names appears in the OPI posting
  if ("COACH" %in% dt) {                                   # coaches: the sport must agree
    ds <- opi_tokens(d_title, OPI_SPORTS); os <- opi_tokens(paste(opi_title, phrase), OPI_SPORTS)
    if (length(ds) && length(os) && !length(intersect(ds, os))) return(-Inf)
  }
  # Related services (therapists, psychologists, SLPs, deaf/HH) are special
  # education by nature: a board's "SE -" department prefix doesn't make
  # them a different job.
  dec_d <- intersect(dt, OPI_DECISIVE); dec_o <- intersect(ot, OPI_DECISIVE)
  if (any(rel %in% dt) || any(rel %in% ot)) { dec_d <- setdiff(dec_d, "SPED"); dec_o <- setdiff(dec_o, "SPED") }
  # OPI's "Administrative - ..." category is met by any administrative role.
  if ("ADMIN" %in% dec_o && any(c("PRIN", "APRIN", "SUPT", "DIRECTOR", "CURRIC", "ACTDIR") %in% dt)) dec_o <- setdiff(dec_o, "ADMIN")
  if (length(setdiff(dec_o, dt)) || length(setdiff(dec_d, of))) return(-Inf)
  if ("ELEM" %in% ot && !"ELEM" %in% dt && !length(intersect(dt, ot))) return(-Inf)
  s <- 2 * length(intersect(dt, ot)) + length(intersect(dt, setdiff(of, ot))) + length(intersect(ol, dl))
  s <- s + 0.5 * length(intersect(opi_tokens(school, OPI_LEVELS), dl))   # the posting's school breaks ties
  sch <- setdiff(strsplit(tolower(gsub("[^a-z ]", " ", school)), " +")[[1]], c("", "school", "district", "wide", "elementary", "high", "middle", "elem", "public", "schools"))
  if (length(sch) && any(vapply(sch, function(w) grepl(paste0("\\b", w), tolower(paste(d_title, d_loc))), logical(1)))) s <- s + 1
  s
}

# ---- v3: lexicon-free word similarity + the v2 conflict checks ----
OPI_STOPWORDS <- c("teacher","teachers","teaching","position","positions","school","schools","district","public","the","a","an","and","of","for","to","in","at",
  "with","or","is","our","we","fte","full","time","part","year","years","sy","opening","openings","job","jobs","certified","classified","staff",
  "grade","grades","level","new","current","immediate","position","seeking","looking","applicants","applications","opportunity","k","1","2","3",
  "4","5","6","7","8","9","10","11","12","20","25","26","27","2025","2026","2027","0","dynamic","enthusiastic","motivated","dedicated")
opi_norm_words <- function(x) {
  x <- tolower(x); x <- gsub("title 1\\b", "title i", x); x <- gsub("[^a-z ]+", " ", x)
  w <- unique(strsplit(x, " +")[[1]]); w <- w[nzchar(w) & !w %in% OPI_STOPWORDS & nchar(w) > 1]
  sub("(ies)$", "y", sub("([^s])s$", "\\1", w))       # crude singular
}
opi_match_conflict <- function(opi_title, phrase, opi_full, d_title, d_loc) {
  opi_title <- sub("(?i)^cte\\s*[-\u2013]\\s*", "", opi_title, perl = TRUE)
  ds <- opi_tokens(d_title, OPI_SPORTS); os <- opi_tokens(paste(opi_title, phrase), OPI_SPORTS)
  if (length(ds) && length(os) && !length(intersect(ds, os))) return(TRUE)
  focus <- if (nzchar(trimws(phrase))) phrase else opi_title
  ot <- opi_tokens(focus, OPI_ROLE_LEXICON)
  if (!length(setdiff(ot, "ELEM"))) { tt <- opi_tokens(opi_title, OPI_ROLE_LEXICON); if (length(opi_tokens(focus, OPI_LEVELS))) tt <- setdiff(tt, "ELEM"); ot <- union(ot, tt) }
  of <- opi_tokens(paste(opi_title, phrase, substr(opi_clean_desc(opi_full), 1, 300)), OPI_ROLE_LEXICON); dt <- opi_tokens(d_title, OPI_ROLE_LEXICON)
  ol <- opi_tokens(focus, OPI_LEVELS); dl <- opi_tokens(paste(d_title, d_loc), OPI_LEVELS)
  lo <- union(ol, intersect(ot, "ELEM")); ld <- union(dl, intersect(dt, "ELEM"))
  if (length(lo) && length(ld) && !length(intersect(lo, ld))) return(TRUE)
  rel <- c("PT", "OT", "SLP", "PSYCH", "DEAF"); dec_d <- intersect(dt, OPI_DECISIVE); dec_o <- intersect(ot, OPI_DECISIVE)
  if (any(rel %in% dt) || any(rel %in% ot)) { dec_d <- setdiff(dec_d, "SPED"); dec_o <- setdiff(dec_o, "SPED") }
  if ("ADMIN" %in% dec_o && any(c("PRIN", "APRIN", "SUPT", "DIRECTOR", "CURRIC", "ACTDIR") %in% dt)) dec_o <- setdiff(dec_o, "ADMIN")
  length(setdiff(dec_o, dt)) > 0 || length(setdiff(dec_d, of)) > 0
}
opi_title_idf <- function(titles) { w <- unlist(lapply(titles, opi_norm_words)); tb <- table(w); idf <- log(length(titles) / as.numeric(tb)); names(idf) <- names(tb); idf }
opi_word_sim <- function(phrase_words, d_words, idf) {
  if (!length(d_words)) return(0)
  wt <- function(w) ifelse(w %in% names(idf), idf[w], max(idf))
  shared <- intersect(phrase_words, d_words)
  if (!length(shared)) return(0)
  sum(wt(shared)) / sum(wt(d_words))                  # share of the board title's (weighted) words the OPI posting explains
}

# For each OPI row, the index in direct_df of the same opening on its
# registry district's board, or NA. registry_district: the district each OPI
# row belongs to (NA = not a scraped district). Several OPI listings may match
# one board posting (OPI often lists one job twice); undercounting a second
# real opening is the safer error than double counting.
match_opi_postings <- function(opi_df, registry_district, direct_df, sim_threshold = 0.6) {
  out <- rep(NA_integer_, nrow(opi_df))
  if (nrow(opi_df) == 0 || nrow(direct_df) == 0) return(out)
  idf <- opi_title_idf(direct_df$title)
  col <- function(nm) if (nm %in% names(opi_df)) { v <- as.character(opi_df[[nm]]); v[is.na(v)] <- ""; v } else rep("", nrow(opi_df))
  title <- col("title"); desc <- col("OPI_Description"); school <- col("OPI_School")
  dloc <- as.character(direct_df$location); dloc[is.na(dloc)] <- ""
  for (i in seq_len(nrow(opi_df))) {
    if (is.na(registry_district[i])) next
    cand <- which(direct_df$District == registry_district[i]); if (!length(cand)) next
    ph <- opi_job_phrase(desc[i], title[i])
    sc <- vapply(cand, function(j) opi_match_score(title[i], ph, desc[i], school[i], direct_df$title[j], dloc[j]), numeric(1))
    if (max(sc) > -Inf) { out[i] <- cand[which.max(sc)]; next }
    pw <- opi_norm_words(paste(ph, title[i], substr(opi_clean_desc(desc[i]), 1, 200)))
    ws <- vapply(cand, function(j) if (opi_match_conflict(title[i], ph, desc[i], direct_df$title[j], dloc[j])) 0 else
                   opi_word_sim(pw, opi_norm_words(direct_df$title[j]), idf), numeric(1))
    if (max(ws) >= sim_threshold) out[i] <- cand[which.max(ws)]
  }
  out
}
