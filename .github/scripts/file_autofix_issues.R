# Tier 3 of the drift-alert system: one issue per "likely_broken" source in /tmp/drift_results.csv (written by
# corroborate_drift.R), handed to Claude (claude-autofix.yml, the default) or the Copilot coding agent, picked by
# the AUTOFIX_ENGINE repo variable; follow-ups, the Claude fallback and recovery closes. edjobs::
# file_autofix_issues_step() (0.54.0; what it does each run is in its help page). GH_TOKEN does the issue work;
# COPILOT_TOKEN assigns to Copilot (and covers edjobs); AUTOFIX_CLAUDE_FALLBACK=true allows the Claude fallback.
source("drift_check.R")
file_autofix_issues_step()
