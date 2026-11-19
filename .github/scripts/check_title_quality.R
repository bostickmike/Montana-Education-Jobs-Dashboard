# Title quality (classification safeguards 5, 6, 9): title-shape lint, per-source Other share,
# keyword conflicts. Non-blocking; adds to /tmp/drift_report.md and writes the three /tmp tables.
# The check is edjobs::check_title_quality_step() (0.51.0).
source("drift_check.R")   # attaches edjobs; state_config.R
check_title_quality_step()
