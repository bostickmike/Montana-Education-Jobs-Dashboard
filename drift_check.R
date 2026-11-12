# Detects when a source that reliably has real postings suddenly reports
# none -- ported from Wyoming's drift_check.R. build_historical_counts(),
# flag_drift(), check_salary_coverage(), check_salary_value_bounds(),
# check_salary_yoy_plausibility(), and score_page_text_for_job_signal() are
# all state-agnostic (pure functions operating on whatever data/thresholds
# they're given) and kept as-is. Only build_source_url_lookup() at the
# bottom is Montana-specific, and it's actually simpler here: Montana's
# job-postings sources are already consolidated into two registry files
# (k12_district_registry.csv, he_institution_registry.csv) rather than
# Wyoming's several separate per-platform CSVs plus a misc-district
# registry.
#
# Two tiers, kept as separate functions so each is independently testable:
#   1. flag_drift() -- cheap, no network calls. Compares this week's
#      per-source counts against each source's own trailing historical
#      baseline. Pure function, easy to unit test with synthetic history.
#   2. score_page_text_for_job_signal() -- the scoring half of the chromote
#      corroboration step (see .github/scripts/corroborate_drift.R for the
#      live-fetch half).

# Only snapshots from this date forward are valid drift-detection baseline
# candidates -- the date Montana's full pipeline (every K-12/HE platform,
# salary/staffing/Census sources) was completed and first produced real
# data across the board.
# the shared drift, title-lint, pay-coverage, salary and auto-fix helpers moved to the edjobs package in phase 2 (2026-11-11); attached here so
# every script that sources this file still has them.
suppressMessages(library(edjobs))
# The state's feed labels and drift baseline date (state_config.R), which the
# drift functions in edjobs read; loaded here unless the caller already did.
if (is.null(current_state_config())) source("state_config.R")

# --------------------------------------------------------------------------
# Tier 1: per-source historical drift detection
# --------------------------------------------------------------------------

# Tier-1 counts treat the OPI statewide feed as one source
# (edjobs::collapse_statewide_feed_names(), which reads the feed label from
# state_config.R): OPI gives a free-text location per posting, not a district.
OPI_STATEWIDE_SOURCE <- current_state_config()$feed$label
OPI_STATEWIDE_URL <- current_state_config()$feed$url

# --------------------------------------------------------------------------
# Posted-pay coverage
# --------------------------------------------------------------------------

# A pay source that breaks doesn't lose postings -- each one just comes
# back with Pay_* blank -- so flag_drift() above can't see it. This compares
# each source's share of postings with stated pay against its own history
# in the raw archives. Archives written before a source captured pay have
# no Pay_* column and are skipped, not counted as zero.





# --------------------------------------------------------------------------
# Tier 0: salary-source structural/coverage checks
# --------------------------------------------------------------------------


# --------------------------------------------------------------------------
# Tier 0b: salary VALUE plausibility (as opposed to coverage/row-count)
# --------------------------------------------------------------------------



# --------------------------------------------------------------------------
# Source name -> public URL lookup, for the chromote corroboration step
# --------------------------------------------------------------------------

# edjobs::build_source_url_lookup(): both registries' Job_Link plus the OPI feed's page.

# --------------------------------------------------------------------------
# Tier 2: chromote corroboration scoring (pure function half)
# --------------------------------------------------------------------------


# --------------------------------------------------------------------------
# Tier 2b: fold an LLM read of the page into the text-signal verdict
# --------------------------------------------------------------------------





# --------------------------------------------------------------------------
# Tier 2c: Central Safety Net status summary & report formatting
# --------------------------------------------------------------------------



# --------------------------------------------------------------------------
# Tier 3: per-source auto-fix issues (Copilot coding agent hand-off)
# --------------------------------------------------------------------------
#
# The rolling "Scraper drift check" issue stays the human-facing summary.
# On top of it, each "likely_broken" source -- the live page demonstrably
# has postings the scraper missed (Thompson Falls 2026-09-07, Hinsdale
# 2026-09-22: page markup changed, parser didn't) -- gets its own issue
# that .github/scripts/file_autofix_issues.R can assign to the Copilot
# coding agent. confirmed_broken (HTTP 429/520 etc.) and genuinely-empty
# verdicts are deliberately NOT eligible: those are site-side, and a code
# change "fixing" them is exactly the wrong move.
#
# The issue body carries an HTML-comment marker naming the source, so
# .github/scripts/live_check_autofix.R can find which scraper a PR claims
# to fix (via the PR's linked issue) and re-run just that scraper live.









# Scraper dispatch (resolve_scraper_call(), run_scraper_call()), the evidence
# helpers and build_autofix_issue_body() are in edjobs since 0.9.0; this
# state's platform specs and registries are in state_config.R.
SCRAPER_FILES <- current_state_config()$autofix$scraper_files

# --------------------------------------------------------------------------
# Title quality (classification safeguards items 5 and 6; run weekly by
# .github/scripts/check_title_quality.R, non-blocking)
# --------------------------------------------------------------------------

# A scraper that starts reading the wrong element still returns rows, and
# the row count looks fine to flag_drift(): what changes is what the "title"
# holds -- a schedule sentence, a summary paragraph, a level without its role.
# lint_title_shape() names the problem per title (NA when the title looks
# like a job title). Each rule was measured against every archived week in
# both states (2026-11-05): it flags the misreads found by hand in the
# 2026-11-01 classification audit and nothing that is merely an unusual but
# real title. Long real titles run to ~190 characters (UW, Goshen), so
# max_chars is 200. A start date a district writes into its own title
# ("beginning the 2026-27 school year.") isn't flagged; "- Open Until
# Filled." is (WY ledger: Fremont #21).










