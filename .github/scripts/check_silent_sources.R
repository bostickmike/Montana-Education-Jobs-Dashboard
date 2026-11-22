# Registry sources with no rows in any of their last 4 weekly runs (edjobs 0.74.0, test-kit plan item 1).
# Non-blocking; adds to /tmp/drift_report.md. Known-empty sources: silent_sources_acknowledged.csv.
# OPIOnly districts have no board of their own, so they are left out.
source("drift_check.R")   # attaches edjobs; state_config.R
check_silent_sources_step(skip_platforms = "OPIOnly")
