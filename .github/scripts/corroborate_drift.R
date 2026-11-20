# Tier 2 of the drift-alert system: renders each source check_drift.R flagged and scores its live page (skipped for a
# source whose scrape logged a real error), with the LLM title read when GEMINI_API_KEY is set. Writes
# /tmp/drift_results.csv (always; file_autofix_issues.R reads it) and /tmp/drift_report.md when something needs a
# human look. edjobs::corroborate_drift_step() (0.55.0); names, feed and URLs come from state_config.R.
source("drift_check.R")
corroborate_drift_step()
