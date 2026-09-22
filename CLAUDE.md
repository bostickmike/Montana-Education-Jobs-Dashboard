# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An R-based, weekly-updated Shiny dashboard of K-12 and higher-ed job openings in Montana, with salary/staffing/Census context. It's a port of the [Wyoming Education Jobs Dashboard](https://github.com/bostickmike/Wyoming-Education-Jobs-Dashboard) — much of the state-agnostic logic (classification, drift checks, history accumulation) was ported near-verbatim, while scraping targets and state-specific data sources were rebuilt for Montana. `RESEARCH_NOTES.md` documents the scoping research (district counts, ATS platform landscape, salary-source gaps) that shaped every structural decision in the port, and is worth reading before assuming Montana's data model mirrors Wyoming's.

## Commands

Install dependencies (no lockfile/package manager — plain `install.packages`):

```r
install.packages(c(
  "rmarkdown", "dplyr", "purrr", "readr", "readxl", "rvest",
  "stringr", "tidyverse", "writexl", "xml2", "jsonlite",
  "httr2", "lubridate", "chromote", "rsconnect", "testthat",
  "withr", "here", "pdftools", "tibble",
  "shiny", "shinydashboard", "shinyWidgets", "DT", "data.table",
  "leaflet", "plotly", "scales", "shinycssloaders"
))
```

Run the dashboard against data already committed in the repo (no scraping):

```r
shiny::runApp("Mt_Ed_Jobs")
```

Run the full scrape/build pipeline (hits every live source; needs a real headless Chrome for the Apptegy/CyberSchool scrapers — set `CHROMOTE_CHROME` if not auto-detected; needs `CENSUS_API_KEY` in `.Renviron` for the Census ACS/SAIPE chunk, everything else runs without it):

```r
rmarkdown::render("Mt_ED_Jobs.Rmd")
```

Run the full test suite:

```r
testthat::test_dir("tests/testthat")
```

Run a single test file:

```r
testthat::test_file("tests/testthat/test-k12-posting-identity.R")
```

Rebuild accumulated K-12/HE history from the committed raw archives from scratch (disaster recovery, or to verify the incremental accumulator path hasn't drifted from a full rebuild):

```r
Rscript scripts/rebuild_k12_history_from_archive.R
Rscript scripts/rebuild_he_history_from_archive.R
```

## Architecture

**Pipeline vs. dashboard are separate R programs sharing derived CSVs.** `Mt_ED_Jobs.Rmd` is the single pipeline entry point — it scrapes every source, classifies/cleans postings, and appends this week's newly derived rows onto the accumulated datasets in `Mt_Ed_Jobs/`. `Mt_Ed_Jobs/app.R` is the Shiny dashboard that reads those same committed CSVs; it never scrapes anything itself. The weekly GitHub Actions workflow (`.github/workflows/weekly-scrape.yml`) runs the pipeline, and a commit+push of the changed CSVs is what triggers the Posit Connect Cloud redeploy of the dashboard — there is no build step connecting the two beyond that shared data.

**Scrapers are split by reliability, not by K-12/HE.** `direct_api_scrapers.R` holds scrapers against real platform APIs (AppliTrack, SchoolSpring, TedK12, Tyler Portico, Paycom, JazzHR, NEOGOV, ADP Workforce Now, isolved Hire, OPI's statewide feed) — both K-12 and HE. `misc_district_scrapers.R` / `misc_college_scrapers.R` hold heuristic scrapers (including the `chromote`-driven Apptegy/CyberSchool ones needing a real headless browser) for districts/institutions with no structured ATS, kept deliberately separate since they're a real but acknowledged-less-reliable source. `k12_district_registry.csv` / `he_institution_registry.csv` are the hand-maintained lists of every directly-scraped target, its platform, and its feed/job-board URL — adding a district or institution means adding a registry row plus (usually) a scraper.

**`llm_extract_scraper.R` is a third, quarantined scraper tier — a shadow pilot.** For district employment pages that publish openings as free-text prose with no structural marker a hand-written parser can key on (Grass Range, Rapelje — the "declined: unstructured prose" tail of the OPI-coverage work), it renders the page with `chromote`, sends `document.body.innerText` to the Google Gemini API (OpenAI-compatible endpoint, `GEMINI_API_KEY` free tier — GitHub Models was the original target but was retired 2026-07-30) with a JSON schema, then applies deterministic guardrails (every returned title must literally appear on the page; an implausible count drops the whole result; boilerplate is filtered). It is **not** wired into the K-12 combine: `fetch_all_llm_extracted_postings()` writes only `Mt_Ed_Jobs/llm_extract_shadow.csv`, pilot districts are **not** in `k12_district_registry.csv`, and nothing it produces touches the dashboard or the sanity/schema/drift checks. Targets live in `llm_extract_targets.csv`; the full lifecycle (add → watch the shadow file for weeks → promote by hand) is in `LLM_EXTRACT.md`. The one non-deterministic piece (`llm_extract_call()`) is isolated and swappable; `tests/testthat/test-llm-extract-scraper.R` covers the guardrails against a real captured fixture without a network call.

**Classification is centralized and shared.** `k12_he_classification.R` holds every `classify_*`/`canonicalize_*` function (position, subject, broad category, HE job type/faculty category, district/institution name canonicalization), sourced by both the K-12 and HE munge chunks in the pipeline and by any one-off rebuild script — this is deliberate, so "what the pipeline produces next run" and "what a rebuild-from-archive script produces now" can never silently diverge. `scrape_helpers.R` and `schema_check.R` (whose `REQUIRED_SCHEMAS` is enforced against real committed data by `tests/testthat/test-schema-check.R`) are sourced the same way.

**Accumulation, not rebuilding.** `history_accumulator.R`'s `append_weekly_rows()` takes only this week's freshly classified rows and appends them onto the existing accumulated CSV (idempotent — a same-day re-run replaces that day's rows rather than duplicating them), instead of reprocessing the full raw archive every run. `Archivek12_Data/` / `Archived_HE_Data/` still get one dated raw snapshot per week as the durable source of truth; the `scripts/rebuild_*_history_from_archive.R` scripts exist specifically to regenerate accumulated data from those archives when the incremental path needs to be checked or disaster-recovered.

**Posting identity is a specific contract, not just a dedup step** (`DATA_COOKBOOK.md`, "Posting identity"). A `Posting_ID` is assigned once, before any current count, vacancy numerator, weekly total, longitudinal aggregate, trend, or New This Week comparison. Structured sources use a real stable per-posting URL when available; a listing/board URL is never mistaken for one, since a single board holds many posts. Sources with no stable ID (including OPI, whose fallback uses title + raw location + posted date) get an explicit fallback tracked in `Posting_Identity_Method`, with a count-preserving occurrence suffix on equal fallback rows rather than silent deduplication. Any change touching posting counts/dedup logic should be checked against this contract and `tests/testthat/test-k12-posting-identity.R` / `test-opi-direct-deduplication.R`.

**The Map/District Summary intentionally show a narrower slice than the Jobs Table.** K-12 covers 128 directly-scraped districts (of Montana's ~398 nominal districts) plus OPI's statewide feed folded into the same current/history/aggregate files; HE covers 23 institutions. The Map, District Summary, and salary/staffing/vacancy-rate views only show the registry-backed 128/23, since those records can be joined to verified identity, coordinates, staffing, salary, and finance data — OPI-only rows stay in the Jobs Table (labeled by source) but are excluded from those other views because OPI exposes a raw location string, not a canonical district identifier. `salarymap2.csv`/`salarymap.csv` are the registry-keyed join targets for that narrower scope; several external staffing/salary/finance sources (`MT_CCD_LEA_MAP`, `MT_DLI_DISTRICT_MAP`, `MT_OPI_FINANCE_LEA_MAP`, `MT_IPEDS_UNITID_MAP`) cover only a subset of the 128/23 even within that scope — treat `NA` in those columns as a real, documented coverage gap or source-side suppression, not a bug, per `DATA_COOKBOOK.md`'s "Notes on the data model".

**Elementary/HS district splits are mapped three separate times.** Montana towns often run legally separate elementary and high-school districts sharing one job board (one registry entry, one scrape target) but different external-source naming. `MT_CCD_LEA_MAP` (`ccd_staff_scraper.R`), `MT_DLI_DISTRICT_MAP` (`salary_scrapers.R`), and `MT_SAIPE_DISTRICT_MAP` (`census_saipe_scraper.R`) each hand-map this project's combined districts to that source's own elementary/HS/unified naming independently — they are not shared, because each source's naming convention differs slightly from the others.

**CI does real work beyond "run tests."** `.github/workflows/weekly-scrape.yml` runs the full `testthat` suite first (aborts before touching real data if red), then the pipeline, then a sanity check (`.github/scripts/sanity_check.R`, refuses to commit if either side of the diff dropped more than half its postings), a schema check (`verify_schema.R`), and a data-quality invariant sweep re-run against the fresh output (`test-weekly-data-quality.R`, blocking), then several non-blocking (`continue-on-error`) monitoring steps: `check_drift.R` (per-source posting-count drift vs. history), `corroborate_drift.R` (live `chromote` render as corroboration before filing a GitHub Issue), `check_salary_drift.R` and `check_census_drift.R` (coverage/plausibility checks against each source's known-fixed or known-partial universe). A final step checks whether any monitoring step itself crashed (distinct from "ran fine, found nothing"), since `continue-on-error` alone would hide that distinction. When changing a scraper or a monitoring script, keep in mind these run against real fixture-backed tests first — see "Fixtures are real captured data" below.

**The test suite is tiered** (modelled on the LASSO project's `smoke → invariants` layering; see `mt-dashboard-test-suite-expansion` memory). Tier 0: `testthat` unit + fixture tests per source. Tier 1: `test-app-boot-smoke.R` boots the real `app.R` in headless Chrome via `shinytest2`, visits every tab, and asserts no Shiny error banner and that the leaflet/plotly/DT widgets actually render — the browser/JS/htmlwidget path that `test-app-reactives.R`'s `testServer()` structurally can't see (`NOT_CRAN=true` + Chrome required, else it skips). Tier 2: `test-weekly-data-quality.R` is a property sweep over the committed output CSVs — no NaN/Inf, range/sign bounds, referential integrity (Posting_ID uniqueness, salarymap2↔registry, category↔color↔collapse-map), enum coverage, temporal sanity — each assertion naming the bug it guards. Tier 3 (an LLM-as-judge anomaly monitor) is planned, not built.

**Fixtures are real captured data, not synthetic.** `tests/testthat/fixtures/` holds real scraped HTML, real downloaded PDFs, and real API responses per source — tests are written against these rather than hand-built synthetic payloads, so a scraper fix should generally come with an updated or added real fixture, not a synthetic one.

**One credential exists in the whole pipeline.** `census_acs_scraper.R` / `census_saipe_scraper.R` need a free `CENSUS_API_KEY` (Census Data API); every other source is a public, keyless API or plain web page. This key is shared with the sibling Wyoming project's own weekly workflow, which is why this project's schedule is deliberately Tuesdays rather than Wyoming's Friday (avoids both pipelines' Census calls landing at the same time).
