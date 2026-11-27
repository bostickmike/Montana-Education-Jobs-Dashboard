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
- **When:** every board is read twice a week, Mondays and Thursdays (weekly before 2026-11-17). Each reading is an
  *update*, and every file records its date (`Archive_Date`).
- **Since:** August 2026.

## One posting, one ID

Each posting gets a `Posting_ID` that stays the same in every update it appears in, so counts, "new this week" and
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
   at all (Ulm, Lodge Grass, Potomac, Forsyth) is not "empty": all its OPI postings count. The same 60-day limit
   applies to an OPI posting missing from a board checked to list every opening the employer has (St. Labre's,
   Billings' and Shields Valley's, each checked by reading the board and what became of the employer's old OPI
   postings).
5. OPI lists some jobs twice (under an elementary and a high-school district, say); a repeat with the same district
   and description counts once.
6. OPI postings at districts the dashboard doesn't read count under that district and put it on the map, marked
   "Postings via OPI's statewide board". Co-ops, private and tribal schools and other employers outside the public
   district list appear in the Jobs table only. St. Labre's three Catholic schools (St. Labre in Ashland, St. Charles
   Mission in Pryor, Pretty Eagle Catholic Academy in Saint Xavier) are read from their own shared board, and St.
   Labre's OPI postings are compared with it as in 1.

From September 1, OPI postings dated before the July 1 that began the school year are marked "may be filled" in
the Jobs table: OPI still lists them, but they are the likeliest to be filled. They still count. OPI is a statewide board, not a census of vacancies:
its rules for what gets posted aren't published, and a job missing from the dashboard is not evidence that no
vacancy exists.

## Old board ads

A job board can keep an ad listed, and keep taking applications through it, until the district takes it down,
whatever dates the ad shows: AppliTrack's closing date is a note the district types, not a deadline the board
enforces. A few districts leave ads from past school years up and post their current openings on OPI. A
district board posting (AppliTrack, SchoolSpring, Tyler Portico, Red Rover, TedK12 or a dated
district page) whose posted date, or stated closing date, is before the July 1 that began the previous school year
(July 1, 2025 during the 2026-27 school year) doesn't count. Two kinds of ads count whatever their dates: standing
pools (substitutes), and jobs districts advertise all year and fill again and again (bus drivers and bus aides,
paraprofessionals and aides, custodians and maintenance staff, food service, athletic coaches). An OPI posting is
never matched to one of these old ads, so the district's current OPI posting of the job counts. The raw postings
keep the old ads, each with its reason (`Stale_Reason`); the counts and the Jobs table leave them out. On the
November 23, 2026 postings the rule would have set aside 43 of 1,164 board postings (2 of them account-creation
templates that already didn't count), and 5 OPI postings matched to them would have counted instead. A date can't
show which old ads are still real openings: a specialist post a district has struggled to fill (a speech
pathologist, a school psychologist) may be one. The rule began with the November 26, 2026 update, and the same day
the whole history, back to August 2026, was recomputed under it (see "Files and history"): each earlier update's ads
are judged by that update's own date, and an OPI posting that update left out only because it matched one of them
counts. Every earlier week is 8 to 38 postings lower (1% to 4%), 2 to 21 of them teaching postings.

## Postings a public record shows as filled

Some ads stay up after the job is filled: on a district's own page, or on OPI. When a district's own public record
(posted board minutes or agendas, a personnel report) shows the hire for a posting that is still listed, that posting
doesn't count, from the end of November 2026. Each one is listed in `filled_postings_record.csv` with what the record
says (no names), its address and date, and an end date (the end of the school year), so the same job advertised again
later counts. This is done one posting at a time, only where the record names the same job; it isn't a rule. The first
check (November 26, 2026, of the 83 OPI postings first posted in May and June) found 3 such jobs still counting:
Custer's PE and Vo-Ag jobs (on its own page and on OPI) and Big Timber's junior high history job (on OPI).

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

The Listing Duration tab lists each posting with the first and last update that showed it (`job_duration_spells.csv`,
`he_job_duration_spells.csv`). Days listed is the span from the first to the last sighting, plus 7 days; a posting
that disappears for more than 21 days and comes back under the same title starts a new row. It starts at the
first sighting, which is often after the posting went up, and "no longer listed" means only that it stopped
appearing.

Days listed is not time to fill: filled jobs can stay posted, and open jobs get reposted. For that reason the tab
shows the table only, without medians or charts, until a more careful measure has been checked.

That measure is built and published at the repository root (`posting_spells_k12.csv`, `posting_durations_k12.csv`
and their HE counterparts), not yet on the dashboard:

- **Start:** the board's posted date when plausible (on or before the first sighting, at most a year earlier);
  otherwise the first update that found it. A posting already listed the first time the dashboard read its board has
  an unknown start (*left-censored*).
- **End:** a posting counts as ended only when its board was read successfully in the next update and it was gone. If
  the board failed or moved, the end is unknown (*censored*).
- **Left out of the medians, but kept in the files:** standing ads and pools ("Substitute Teachers", always
  hiring), boards that stopped changing (frozen), same-title postings that can't be told apart, unknown starts, and
  OPI postings.
- Medians use the Kaplan-Meier method, so postings still listed count for as long as they've been up. The mechanics,
  with a worked example, are in the edjobs package's [posting spells vignette](https://github.com/bostickmike/edjobs/blob/main/vignettes/posting-spells.Rmd).

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
skipped it. When a source fails in a update, the previous update's values are kept rather than blanked.

## Files and history

- `combinedclean.csv`, `hedata.xlsx`, `allnow.csv` and `allnow_he.csv` hold the latest update only. The other files
  grow by one update at a time.
- Every update also saves the raw postings (`Archivek12_Data/`, `Archived_HE_Data/`). The history files can be rebuilt
  from them exactly, and every update checks that they are.
- A change to a counting rule applies from the next update on; earlier updates keep the counts they had, unless the
  history is recomputed from the raw files, which the dashboard notes where it shows (as under the K-12 multi-year
  chart, for OPI postings before 2026-11-03).

---

This page replaced `DATA_COOKBOOK.md` on 2026-11-23. The cookbook's engineering notes (dates, platform details,
how each rule was measured) are in that file's git history.
