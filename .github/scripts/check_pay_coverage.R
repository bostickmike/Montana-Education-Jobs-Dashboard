# Posted-pay coverage: a source whose postings still arrive but lost the pay they carried,
# and the posted amounts drop_implausible_pay() blanked today. Non-blocking; adds to /tmp/drift_report.md.
# The check is edjobs::check_pay_coverage_step() (0.51.0).
source("drift_check.R")   # attaches edjobs; state_config.R
check_pay_coverage_step()
