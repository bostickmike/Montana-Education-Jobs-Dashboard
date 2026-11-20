# Salary-source coverage, value plausibility and the pay estimates' reference tables. Non-blocking; flags go to
# /tmp/drift_report.md. edjobs::salary_drift_step() (0.57.0): each source in state_config(salary_checks = ) is
# compared with last run's committed salarymap2.csv / salarymap.csv.
source("state_config.R")
salary_drift_step()
