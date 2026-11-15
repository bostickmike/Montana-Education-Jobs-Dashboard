# Montana's IPEDS unitid map: the dashboard's institution names and their
# IPEDS unit ids, passed to the edjobs federal HE fetchers
# (fetch_ipeds_he_salaries(), fetch_ipeds_he_enrollment(),
# fetch_ipeds_he_enrollment_trend(), fetch_ipeds_he_pell_share(); package
# phase 5, 2026-11-15; the fetch/parse code that lived in
# ipeds_salary_scraper.R, ipeds_enrollment_scraper.R and fsa_pell_scraper.R
# is in edjobs now).
#
# The map covers exactly the institutions this project job-scrapes
# (he_institution_registry.csv; tests/testthat/test-ipeds-unitids.R checks
# it). Highlands College has its own unitid (180081) separate from Montana
# Tech's (180416), so no institution here needs a Salary_Note.
#
# Extended 2026-08-07 from the original 6 to the 7 HE institutions added to
# the registry since (Blackfeet CC, Carroll College, Dawson CC, Miles CC,
# Rocky Mountain College, University of Montana, University of Providence),
# each unitid confirmed live against the Urban Institute's college directory
# and its own 2024 salary response. Blackfeet, Dawson and Miles have no
# academic_rank 1 (Professor) record in 2024 (a real absence), so
# Faculty_Avg_Salary_Professor is NA for them.

IPEDS_UNITID_MAP <- tibble::tribble(
  ~unitid, ~Name,
  180461L, "Montana State University",
  180179L, "Montana State University Billings",
  180522L, "Montana State University-Northern",
  180249L, "Great Falls College MSU",
  180416L, "Montana Tech",
  180197L, "Flathead Valley Community College",
  180373L, "Miles Community College",
  180151L, "Dawson Community College",
  180054L, "Blackfeet Community College",
  180489L, "University of Montana",
  180106L, "Carroll College",
  180595L, "Rocky Mountain College",
  180258L, "University of Providence",
  # Added 2026-08-07, confirmed live against the Urban Institute's own
  # college directory endpoint (college-university/ipeds/directory/2023)
  # for the 4 tribal colleges added to the registry since -- Stone Child's
  # unitid (366340) doesn't follow the 1804xx/1802xx pattern the rest of
  # this map does, which is why it wasn't guessed at.
  180212L, "Fort Peck Community College",
  180328L, "Little Big Horn College",
  180647L, "Salish Kootenai College",
  366340L, "Stone Child College",
  # Added 2026-08-07 alongside their new heuristic scrapers
  # (misc_college_scrapers.R) -- confirmed live against the Urban
  # Institute's college directory and real 2024 salary response.
  180203L, "Aaniiih Nakoda College",
  180160L, "Chief Dull Knife College",
  # Highlands College (180081) -- added 2026-08-07 once its postings were
  # split out from Montana Tech's on direct_api_scrapers.R's JazzHR side.
  # Real, permanent gap unlike every entry above: confirmed live across
  # 2020-2024, IPEDS's salaries-instructional-staff and FSA's grants
  # endpoints have ZERO rows for this unitid in any year checked -- not
  # missing a rank tier like Blackfeet/Dawson/Miles/the tribal colleges
  # above, genuinely no HR-survey or Pell data reported under its own
  # unitid at all (almost certainly consolidated into Montana Tech's own
  # HR/financial-aid reporting, since they share physical
  # administration). Faculty_Avg_Salary/Pell_Recipient_Share are real NA
  # for Highlands College every run. Fall-enrollment IS reported
  # separately (3 real rows confirmed live for 2023), so Enrollment/
  # Enrollment_Change_Pct/Students_Per_Teacher work normally.
  180081L, "Highlands College",
  # Helena College and University of Montana Western (180276, 180692) --
  # added 2026-08-07 once their postings were split out from University
  # of Montana's on the NEOGOV side (now the SharesBoard rows of
  # he_institution_registry.csv, applied by edjobs::assign_shared_board_institutions()). Unlike Highlands College above, both
  # report salary/enrollment/Pell data normally under their own real
  # unitids -- confirmed live (48 and 120 salary rows, 5 Pell grant rows
  # each for 2024/2021 respectively).
  #
  # Missoula College deliberately has NO entry here, a real permanent gap
  # unlike every institution above: confirmed live it has no independent
  # unitid in the Urban Institute's IPEDS directory for Montana at all
  # (not a branch/8-digit ID either -- checked and ruled out), so its
  # salary/enrollment/Pell figures are fully consolidated into University
  # of Montana's own reporting with no separately-fetchable source, the
  # same "no independent UNITID at all" structural case RESEARCH_NOTES
  # already documented for Bitterroot College and Gallatin College MSU.
  180276L, "Helena College",
  180692L, "University of Montana Western"
)
