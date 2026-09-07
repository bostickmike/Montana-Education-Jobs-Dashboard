# LLM-assisted extraction for K-12 district employment pages that publish
# their openings as free-text prose with no structural marker a hand-written
# parser can key on -- the "declined: genuinely unstructured prose" tail of
# the full-OPI-coverage work (Grass Range, Rapelje, ... -- pages where a
# person can see the openings but there is no heading, list marker, table,
# or repeatable sentence to anchor a regex on).
#
# This is DELIBERATELY the least-reliable tier in this project: it puts a
# non-deterministic model in the extraction step. It is quarantined to a
# SHADOW pipeline -- fetch_all_llm_extracted_postings() writes only
# Mt_Ed_Jobs/llm_extract_shadow.csv, which nothing the live dashboard reads
# ever touches (not combinedclean.csv, not the map, not the weekly totals,
# not the drift checks). A district's shadow output is meant to be eyeballed
# against its live page for several weeks and promoted into the real
# pipeline by hand only once it has proven stable. See LLM_EXTRACT.md.
#
# Mechanism (this is NOT Selenium):
#   1. chromote renders the page -- the same headless-Chrome path the
#      Apptegy scrapers already use -- and we take document.body.innerText
#      (the visible text a human would see, no HTML/JS/CSS).
#   2. One HTTPS call to GitHub Models (OpenAI-compatible chat/completions,
#      auth'd with GITHUB_TOKEN, covered by a GitHub Copilot subscription)
#      with a strict JSON schema. The model only ever sees already-extracted
#      plain text -- it cannot browse, click, or fetch anything.
#   3. Deterministic guardrails (parse_llm_extracted_postings) -- the model's
#      titles must literally appear on the page, the count must be plausible,
#      and known boilerplate ("Certified Job Application", "W-4 Form") is
#      dropped. This is the part the test suite covers.
#
# The one swappable piece is llm_extract_call(): replace it with
# ellmer::chat_github(), or point it at a different provider, without
# touching the render step, the guardrails, or the pipeline wiring.

suppressMessages({
  library(httr2)
  library(jsonlite)
})

# --- configuration (env-overridable so the endpoint/model can be corrected
#     without a code change while the pilot is still in shadow mode) --------

# GitHub Models' current inference endpoint. The older Azure-hosted form
# (https://models.inference.ai.azure.com/chat/completions, model "gpt-4o-mini"
# without the "openai/" prefix) also works -- set LLM_EXTRACT_ENDPOINT /
# LLM_EXTRACT_MODEL if GitHub changes it.
llm_extract_endpoint <- function() {
  v <- Sys.getenv("LLM_EXTRACT_ENDPOINT")
  if (nzchar(v)) v else "https://models.github.ai/inference/chat/completions"
}
llm_extract_model <- function() {
  v <- Sys.getenv("LLM_EXTRACT_MODEL")
  if (nzchar(v)) v else "openai/gpt-4o-mini"
}

# GitHub Models has a tighter input cap than the first-party APIs; ~12k
# chars of visible text is well under it and covers every real district
# employment page seen so far.
LLM_EXTRACT_MAX_CHARS <- 12000L

# A tiny rural district reporting more than this many simultaneous openings
# almost certainly means the model scraped a navigation menu or looped --
# the whole result for that district is treated as untrustworthy and dropped.
LLM_EXTRACT_MAX_PLAUSIBLE <- 25L

LLM_EXTRACT_SYSTEM_PROMPT <- paste(
  "You extract currently-open job postings from the visible text of a single",
  "US K-12 school district employment page.",
  "",
  "Rules:",
  "- Return ONLY genuine, currently-open positions with a real job title",
  "  (e.g. 'Head Volleyball Coach', '3rd Grade Teacher', 'Bus Driver',",
  "  'Assistant Cook', 'Special Education Paraprofessional').",
  "- NEVER return application forms, tax forms (W-4, I-9, W-2), employee",
  "  handbooks, policies, non-discrimination statements, or generic",
  "  'apply here' / 'application available in the office' links.",
  "- Copy the job title EXACTLY as it is written on the page. Do not",
  "  paraphrase it, expand abbreviations, or append words like 'Coach' or",
  "  'Position' that are not literally in the title text.",
  "- If a section says it has no openings ('None at this time', 'no current",
  "  openings', 'no vacancies'), return nothing for that section.",
  "- location: the specific building or school if the page names one for the",
  "  posting; otherwise the district name.",
  "- posted_date: the date the page shows for that posting, in YYYY-MM-DD",
  "  form, if and only if a date is clearly shown; otherwise an empty string.",
  "- If the page has no open postings, or you are not confident an item is a",
  "  real current job posting, return an empty list. Never guess.",
  sep = "\n"
)

# OpenAI-style response_format payload forcing a {postings: [...]} object.
LLM_EXTRACT_RESPONSE_FORMAT <- list(
  type = "json_schema",
  json_schema = list(
    name = "job_postings",
    strict = TRUE,
    schema = list(
      type = "object",
      additionalProperties = FALSE,
      required = list("postings"),
      properties = list(
        postings = list(
          type = "array",
          items = list(
            type = "object",
            additionalProperties = FALSE,
            required = list("title", "location", "posted_date"),
            properties = list(
              title       = list(type = "string"),
              location    = list(type = "string"),
              posted_date = list(type = "string")
            )
          )
        )
      )
    )
  )
)

llm_extract_empty <- function() {
  data.frame(Title = character(0), Location = character(0),
             Posted_Date = character(0), Link = character(0),
             stringsAsFactors = FALSE)
}

# --- 1. render the page (chromote) -----------------------------------------

llm_extract_render_text <- function(chromote_session, url, settle_seconds = 4) {
  chromote_session$Page$navigate(url)
  chromote_session$Page$loadEventFired(wait_ = TRUE, timeout_ = 30)
  Sys.sleep(settle_seconds)
  txt <- chromote_session$Runtime$evaluate("document.body.innerText")$result$value
  if (is.null(txt)) "" else as.character(txt)
}

# --- 2. the model call (the one swappable piece) --------------------------
# Returns a list of {title, location, posted_date} lists, or NULL when the
# token is missing / the page text is blank / the response can't be parsed.
# A real HTTP error (401 bad token, 400 bad request, a persistent 5xx after
# retries) is allowed to throw -- safe_scrape() upstream turns that into an
# "error" row in scrape_log.csv, exactly like any other scraper.
llm_extract_call <- function(page_text,
                             model = llm_extract_model(),
                             endpoint = llm_extract_endpoint(),
                             token = Sys.getenv("GITHUB_TOKEN"),
                             max_tries = 3) {
  if (!nzchar(token) || !nzchar(trimws(page_text))) return(NULL)

  body <- list(
    model = model,
    temperature = 0,
    messages = list(
      list(role = "system", content = LLM_EXTRACT_SYSTEM_PROMPT),
      list(role = "user", content = page_text)
    ),
    response_format = LLM_EXTRACT_RESPONSE_FORMAT
  )

  resp <- request(endpoint) |>
    req_headers(Authorization = paste("Bearer", token),
                Accept = "application/json") |>
    req_body_json(body) |>
    req_retry(max_tries = max_tries, backoff = function(i) 2^i) |>
    req_perform()

  content <- tryCatch(
    resp_body_json(resp)$choices[[1]]$message$content,
    error = function(e) NULL
  )
  if (is.null(content) || !nzchar(content)) return(NULL)

  parsed <- tryCatch(jsonlite::fromJSON(content, simplifyVector = FALSE),
                     error = function(e) NULL)
  parsed$postings
}

# --- 3. guardrails (pure & deterministic -- the tested core) --------------

# Does (a leading chunk of) each title literally appear in the page text?
# The single strongest anti-hallucination check: the model can only return
# a title that a person could have read off the page.
llm_extract_title_on_page <- function(titles, page_text, probe_len = 20L) {
  page_norm <- tolower(gsub("[[:space:]]+", " ", page_text))
  vapply(titles, function(t) {
    probe <- tolower(gsub("[[:space:]]+", " ", trimws(as.character(t))))
    probe <- substr(probe, 1L, probe_len)
    nzchar(probe) && grepl(probe, page_norm, fixed = TRUE)
  }, logical(1), USE.NAMES = FALSE)
}

# Is the title just a form/policy name rather than a job? Anchored so a real
# title that merely *mentions* a form -- e.g. Apptegy's
# "Assistant Cook | Classified Application | 2026-2027" -- is kept (the
# "| ..." suffix is stripped before matching).
llm_extract_looks_boilerplate <- function(titles) {
  core <- trimws(sub("\\s*\\|.*$", "", as.character(titles)))
  is_form <- grepl(
    paste0("^(the\\s+)?(certified|classified|substitute|coaching|general|",
           "staff|employment|volunteer|new\\s+hire)?\\s*",
           "(staff|job|teacher|teaching|employment|substitute)?\\s*",
           "applications?(\\s+(form|packet))?$"),
    core, ignore.case = TRUE)
  is_tax    <- grepl("^(w-?4|i-?9|w-?2|1099)(\\s+form)?$", core, ignore.case = TRUE)
  is_hbk    <- grepl("^(employee\\s+)?(handbook|manual)$", core, ignore.case = TRUE)
  is_policy <- grepl("polic(y|ies)$|non-?discrimination|\\bEEO\\b|\\bFMLA\\b|title\\s+ix",
                     core, ignore.case = TRUE)
  is_form | is_tax | is_hbk | is_policy
}

# llm_postings: the list returned by llm_extract_call() (or NULL).
# Returns the standard 4-column scraper frame (Title, Location, Posted_Date,
# Link). Any failure mode -> a 0-row frame; never a fabricated row.
parse_llm_extracted_postings <- function(page_text, llm_postings, url,
                                         location_fallback = NA_character_,
                                         max_plausible = LLM_EXTRACT_MAX_PLAUSIBLE) {
  if (is.null(llm_postings) || length(llm_postings) == 0) return(llm_extract_empty())

  field <- function(p, k) {
    v <- p[[k]]
    if (is.null(v) || length(v) != 1 || is.na(v)) return(NA_character_)
    trimws(as.character(v))
  }
  df <- data.frame(
    Title       = vapply(llm_postings, field, character(1), "title"),
    Location    = vapply(llm_postings, field, character(1), "location"),
    Posted_Date = vapply(llm_postings, field, character(1), "posted_date"),
    Link        = url,
    stringsAsFactors = FALSE
  )

  df <- df[!is.na(df$Title) & nzchar(df$Title), , drop = FALSE]
  if (nrow(df) == 0) return(llm_extract_empty())

  # plausibility ceiling: an implausible count means the whole extraction is
  # suspect, so drop all of it rather than trying to keep "the good ones".
  if (nrow(df) > max_plausible) return(llm_extract_empty())

  df <- df[!llm_extract_looks_boilerplate(df$Title), , drop = FALSE]
  if (nrow(df) == 0) return(llm_extract_empty())

  df <- df[llm_extract_title_on_page(df$Title, page_text), , drop = FALSE]
  if (nrow(df) == 0) return(llm_extract_empty())

  df$Posted_Date[is.na(df$Posted_Date) | !nzchar(df$Posted_Date)] <- NA_character_
  blank_loc <- is.na(df$Location) | !nzchar(df$Location)
  df$Location[blank_loc] <- location_fallback

  rownames(df) <- NULL
  df
}

# --- 4. one district: render -> call -> parse -----------------------------

fetch_llm_extracted_postings <- function(chromote_session, url,
                                         location_fallback = NA_character_,
                                         model = llm_extract_model()) {
  page_text <- llm_extract_render_text(chromote_session, url)
  page_text <- substr(page_text, 1L, LLM_EXTRACT_MAX_CHARS)
  postings <- llm_extract_call(page_text, model = model)
  parse_llm_extracted_postings(page_text, postings, url, location_fallback)
}

# --- 5. all shadow-pilot districts, one shared chromote session ----------
# Mirrors fetch_apptegy_k12_postings(): one browser session, safe_scrape()
# per district so one bad page doesn't lose the rest, returns the 5-column
# shape (adds District). Reads its target list from targets_path, NOT
# k12_district_registry.csv -- shadow-pilot districts stay out of the
# registry (and therefore off the map and out of the salary/staffing joins)
# until they are promoted.

LLM_EXTRACT_TARGETS_PATH <- "llm_extract_targets.csv"

read_llm_extract_targets <- function(path = LLM_EXTRACT_TARGETS_PATH) {
  empty <- data.frame(District = character(0), Job_Link = character(0),
                      County = character(0), Notes = character(0),
                      stringsAsFactors = FALSE)
  if (!file.exists(path)) return(empty)
  t <- utils::read.csv(path, stringsAsFactors = FALSE)
  if (!all(c("District", "Job_Link") %in% names(t))) return(empty)
  t[!is.na(t$Job_Link) & nzchar(trimws(t$Job_Link)) &
    !is.na(t$District) & nzchar(trimws(t$District)), , drop = FALSE]
}

fetch_all_llm_extracted_postings <- function(chromote_session_factory = NULL,
                                             targets = read_llm_extract_targets(),
                                             model = llm_extract_model(),
                                             token = Sys.getenv("GITHUB_TOKEN"),
                                             log_path = "scrape_log.csv") {
  empty5 <- cbind(llm_extract_empty(), District = character(0))

  if (nrow(targets) == 0)             return(empty5)
  if (is.null(chromote_session_factory)) return(empty5)
  if (!nzchar(token)) {
    log_scrape_result("LLMExtract shadow pilot (all districts)",
                      status = "skipped_no_key", n_rows = 0L,
                      error_message = "GITHUB_TOKEN not set", log_path = log_path)
    return(empty5)
  }

  session <- chromote_session_factory()
  on.exit(tryCatch(session$close(), error = function(e) NULL), add = TRUE)

  dplyr::bind_rows(lapply(seq_len(nrow(targets)), function(i) {
    row <- targets[i, ]
    df <- safe_scrape(
      paste0("LLMExtract: ", row$District),
      scrape_fn = function() fetch_llm_extracted_postings(
        session, row$Job_Link,
        location_fallback = row$District, model = model),
      expected_cols = c("Title", "Location", "Posted_Date", "Link"),
      log_path = log_path
    )
    df$District <- rep(row$District, nrow(df))
    df
  }))
}
