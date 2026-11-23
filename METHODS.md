# Methods: how the Montana dashboard's numbers are made

This page explains what the [Montana Education Jobs Dashboard](https://bostickmike-montana-education-jobs-dashboard.share.connect.posit.cloud)
counts and how. Every column of every file is defined in [DATA_DICTIONARY.md](DATA_DICTIONARY.md); this page
covers the choices behind them and their limits.

## What is counted

- **Postings, not vacancies.** A posting is one job advertisement listed on a board when the dashboard read it. A
  district can advertise one job twice, or keep an ad up after the job is filled; a vacancy can go unadvertised.
- **K-12:** the job boards of 200 Montana public school districts, read directly, plus the Office of Public
  Instruction's statewide board, [Jobs for Teachers](https://apps.opi.mt.gov/mtjobsforteachers/). Montana has about 398 districts; many small ones have no job
  board of their own and post only on OPI.
- **Higher education:** the job boards of 23 colleges and universities. Four of them (Highlands College, Helena
  College, University of Montana Western, Missoula College) share a parent institution's board; their postings are
  credited to them one by one.
- **When:** every board is read twice a week, Mondays and Thursdays (weekly before 2026-11-17). Each reading is a
  *run*, and every file records the run's date (`Archive_Date`).
- **Since:** August 2026.

## One posting, one ID

Each posting gets a `Posting_ID` that stays the same in every run it appears in, so counts, "new this week" and
listing durations follow the posting rather than the row. Where a board gives each posting its own address or job
number (AppliTrack, SchoolSpring, Tyler Portico, TedK12), the ID is built from that. Where it doesn't, the ID is
built from the board, district, title, location and posted date (`Posting_Identity_Method` says which). OPI's board
gives no per-posting address, so its postings are identified by title, location and posted date; two OPI postings
identical in all three are kept as two rows, not merged.

## OPI postings: when they count

Many districts list the same teaching job on their own board and on OPI's. The dashboard counts it once:

1. Each OPI posting's page names its district. If the dashboard reads that district's board, the posting is
   compared with the board's postings, using the OPI description. When it is the same opening, the district's
   posting counts and is marked "also on OPI"; the OPI copy doesn't count.
2. An OPI posting that doesn't match anything on the district's board counts: many districts post teaching jobs
   only on OPI.
3. Once matched, an OPI posting stops counting when the district takes its own copy down, even if OPI still lists
   it: applications go through the district.
4. When the district's board lists nothing, or only standing substitute pools, OPI postings more than 60 days old
   don't count (OPI keeps ads up after jobs are filled). Newer ones do. A district whose site has no job board
   at all (Ulm, Lodge Grass, Potomac, Forsyth) is not "empty": all its OPI postings count.
5. OPI lists some jobs twice (under an elementary and a high-school district, say); a repeat with the same district
   and description counts once.
6. OPI postings at districts the dashboard doesn't read count under that district and put it on the map, marked
   "Postings via OPI's statewide board". Co-ops, private and tribal schools and other employers outside the public
   district list appear in the Jobs table only.

From September 1, OPI postings dated before the July 1 that began the school year are marked "may be filled" in
the Jobs table: OPI still lists them, but they are the likeliest to be filled. They still count. OPI is a statewide board, not a census of vacancies:
its rules for what gets posted aren't published, and a job missing from the dashboard is not evidence that no
vacancy exists.

## Categories

- **K-12 position** (`position`), from the title: Teacher, Substitute, Paraprofessional, Athletics, Support Services,
  Transportation, Custodial/Maintenance, Administration, Food Services, Part-Time Teacher,
  Activities/Extracurricular, Staff, Other.
- **Teaching subject** (`Category`, grouped in `Broad_Category`): for teaching postings, from the title and, for OPI
  postings, OPI's subject.
- **College job type** (`Job_Type`): Instructor/Teacher/Faculty, Adjunct/Part-Time Faculty, and staff types
  (Professional, Management, Research & Science, Technical, and others); faculty postings also get a discipline.

The rules are written by hand and checked against a hand-labeled set of real titles. The category files
(`allsum.csv`, `k12jobanalysis.csv` and their college counterparts) cover teaching or faculty postings only.

## Pay

- **Posted pay** (`Pay_Min`, `Pay_Max`, `Pay_Unit`, `Pay_Text`): only what the posting itself states, in its own
  unit, never converted. The text it came from is kept. An amount implausible for its unit is left blank.
- **Typical pay (BLS est.)**, K-12, where the posting states no pay: the Bureau of Labor Statistics' median pay for
  the role in the posting's region ([OEWS](https://www.bls.gov/oes/)), across all employers. A regional estimate, not this job's offer.
- **College pay estimate**, salaried staff postings: the college's average salary for full-time staff in the
  matching [IPEDS](https://nces.ed.gov/ipeds/) category, shown even when the posting states pay. A college-wide average, not this job's offer.
- **Teacher salary** (Districts tab): the Montana Department of Labor & Industry's Teacher Compensation Report
  ([Labor Market Information publications](https://lmi.mt.gov/Publications)),
  average and 10th-90th percentile by district. DLI keeps no archive, so `k12_salary_history.csv` holds each
  edition the dashboard has captured.

## Vacancy rate

Current teaching postings divided by the district's full-time-equivalent teachers ([NCES Common Core of
Data](https://nces.ed.gov/ccd/)), or
current faculty postings divided by the college's full-time instructional staff (IPEDS). It is left blank under
10 FTE, where a few postings would give a misleading rate.

## Listing duration

The Listing Duration tab and the spells files follow each posting from its start to the run it was no longer
listed.

- **Start:** the board's posted date when plausible (on or before the first sighting, at most a year earlier);
  otherwise the first run that found it. A posting already listed the first time the dashboard read its board has
  an unknown start (*left-censored*).
- **End:** a posting counts as ended only when its board was read successfully in the next run and it was gone. If
  the board failed or moved, the end is unknown (*censored*).
- **Left out of the medians, but kept in the files:** standing ads and pools ("Substitute Teachers", always
  hiring), boards that stopped changing (frozen), same-title postings that can't be told apart, unknown starts, and
  OPI postings.
- Medians use the Kaplan-Meier method, so postings still listed count for as long as they've been up.

Days listed is not time to fill: filled jobs can stay posted, and open jobs get reposted. The mechanics, with a
worked example, are in the edjobs package's [posting spells vignette](https://github.com/bostickmike/edjobs/blob/main/vignettes/posting-spells.Rmd).

## Context data

District and college context comes from public sources, joined by NCES or IPEDS id:

- [NCES Common Core of Data](https://nces.ed.gov/ccd/): staff, enrollment, free and reduced-price lunch.
- [OPI school finance](https://opi.mt.gov/Leadership/Finance-Grants/School-Finance): General Fund expenditure.
- [Census American Community Survey](https://www.census.gov/programs-surveys/acs) (5-year): county income, rent,
  mining and energy jobs, population change, with margins of error.
- [Census SAIPE](https://www.census.gov/programs-surveys/saipe.html): child poverty by district, with its range.
- [IPEDS](https://nces.ed.gov/ipeds/): faculty pay and count, enrollment, staff pay; Federal Student Aid: Pell share.
- BLS [OEWS](https://www.bls.gov/oes/) and [QCEW](https://www.bls.gov/cew/): regional pay by role, county school pay.

CCD, IPEDS and Federal Student Aid figures come through the
[Urban Institute Education Data Portal](https://educationdata.urban.org). The Data tab lists when each was last retrieved.

A blank means the source has no figure (suppressed for small districts, or not reported), not that the dashboard
skipped it. When a source fails in a run, the previous run's values are kept rather than blanked.

## Files and history

- `combinedclean.csv`, `hedata.xlsx`, `allnow.csv` and `allnow_he.csv` hold the latest run only. The other files
  grow by one run at a time.
- Every run also saves the raw postings (`Archivek12_Data/`, `Archived_HE_Data/`). The history files can be rebuilt
  from them exactly, and the weekly run checks that they are.
- A change to a counting rule applies from the next run on; earlier runs keep the counts they had, unless the
  history is recomputed from the raw files, which the dashboard notes where it shows (as under the K-12 multi-year
  chart, for OPI postings before 2026-11-03).

---

This page replaced `DATA_COOKBOOK.md` on 2026-11-23. The cookbook's engineering notes (dates, platform details,
how each rule was measured) are in that file's git history.
