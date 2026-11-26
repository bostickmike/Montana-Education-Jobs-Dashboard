# Tier 1 of the drift-alert system: each source's posting count against its own baseline.
# Non-blocking. Writes /tmp/drift_flagged.csv (header only when nothing is flagged).
# The check is edjobs::check_drift_step() (0.51.0; the source naming, floor and registry are in state_config.R).
source("drift_check.R")   # attaches edjobs; state_config.R
# OPIOnly districts have no board of their own, so they are left out (Lodge Grass filed #156 on 11-26; edjobs 0.102.0).
check_drift_step(skip_platforms = "OPIOnly")
