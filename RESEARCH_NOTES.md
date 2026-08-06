# Montana Port — Research Notes

Findings from the initial research pass, before any scraper code was written. This
documents *why* the Montana version's scope and architecture will differ from
Wyoming's in specific places, so those differences don't look like unexamined
copy-paste later. Supersedes nothing yet — no code exists — but should inform
`DATA_COOKBOOK.md` and `README.md` once the port starts producing real files.

## K-12 landscape

- Montana has **~398 nominal school districts** (NCES CCD) vs. Wyoming's 48 — but
  this is a structural artifact, not 8x more real school systems. Most Montana towns
  run **legally separate elementary and high-school districts** (e.g. "Billings
  Elementary" + "Billings High School") that share one HR office and **one job-board
  URL** in practice. The real scraping surface is much closer to Wyoming's than the
  raw district count suggests — but the data model needs an explicit
  district-pair → single-scrape-target mapping, since OPI/NCES count them as two.
- The rest of the long tail is mostly **self-administered single-school districts**
  (one-room/one-building rural schools with no modern ATS) — out of scope for a
  first pass, same call Wyoming implicitly made by only covering districts with
  real job boards.
- **Top ~20 districts by enrollment** cluster onto two ATS vendor families:
  **Frontline/AppliTrack** (Billings, Missoula/MCPS, Great Falls, Bozeman, Helena,
  Butte, Belgrade, Havre, East Helena, Lockwood, Hamilton — ~11 districts, one
  reusable scraper template) and **PowerSchool/SchoolSpring+TedK12** (Whitefish,
  Columbia Falls, Polson, Lewistown, Laurel — ~5 districts, another reusable
  template). **Kalispell** (a top-6 district) is on Tyler Portico, a one-off.
  Frenchtown and Hardin show no identifiable third-party ATS and need direct-site
  handling. Full platform table is in the agent findings below.
- **Statewide fallback feed exists and is stronger than expected**: Montana OPI runs
  **"Jobs for Teachers"** (`apps.opi.mt.gov/mtjobsforteachers/`), a free, state-run
  centralized board that already surfaces postings from both large districts
  (Billings, Missoula, Helena, Bozeman, Kalispell, Frenchtown) and tiny rural ones.
  This is a stronger, more centralized analog to Wyoming's WSBA feed than expected —
  worth scraping from day one, not just as a last resort.
- MTSBA (superintendent/admin searches only) and SAM (School Administrators of
  Montana) exist but are narrower, administrator-only boards — not general
  substitutes for the OPI feed.
- Montana has multiple BIE-funded/tribally-controlled K-12 schools on its 7
  reservations, outside normal OPI district structure and state ATS platforms.
  Out of scope for v1, consistent with Wyoming's scope.

## Higher ed

- **Montana University System (MUS): 16 named campuses**, but only **9 distinct
  job-board endpoints** and **14 distinct IPEDS UNITIDs** — several branch campuses
  share a parent institution's HR system *and* IPEDS reporting:
  - **Bitterroot College** (under UM) and **Gallatin College MSU** (under MSU
    Bozeman) have **no independent UNITID at all** — fully merged into the parent's
    IPEDS reporting. This is the direct Montana analog of Wyoming's
    Sheridan/Gillette shared-reporting case, and the existing `IPEDS_UNITID_MAP`
    pattern from `ipeds_salary_scraper.R` should generalize to it.
  - **Missoula College** (`18048901`) and **City College at MSU Billings**
    (`18017901`) get their own IPEDS "branch" UNITIDs (8-digit, parent-ID + suffix)
    rather than fully independent 6-digit ones — needs a probe against the Urban
    Institute API to confirm these branch IDs are queryable before assuming
    coverage.
  - **Highlands College** (Montana Tech) is the outlier: shares Montana Tech's job
    board but has a normal standalone 6-digit UNITID (180081).
- **7 tribal colleges** exist outside MUS governance, each with its own UNITID.
  6 are IPEDS-`public`; **Blackfeet Community College is IPEDS-`private
  not-for-profit`** — would silently drop out of a `control=public` filter and
  needs explicit manual inclusion if tribal colleges are in scope. Most tribal
  colleges have no modern ATS (PDF/paper applications) rather than a scrapable
  job board, so including them means a different scraping approach (static
  page/PDF parsing) than the MUS institutions.
- Live-tested against `fips=30`: **31 total Title-IV institutions** in Montana,
  **18 public-control**, vs. Wyoming's 9 — the port needs an explicit inclusion
  filter (MUS-only vs. all public Title-IV) rather than assuming a short list.

## K-12 salary data — no clean WSBA equivalent

This is the one area where Montana genuinely lacks a Wyoming-equivalent source, not
just a differently-shaped one:

- **MTSBA**: does labor-relations consulting for districts, not a public salary
  publication.
- **OPI** holds the real per-district data (via MAEFAIRS/GEMS) but only exposes it
  through statewide/grouped aggregates publicly, or a manual data request — not a
  scrapable artifact.
- **Best available: Montana Dept. of Labor & Industry's annual "Teacher
  Compensation Report"** (`lmi.mt.gov/publications`), teacher salary only, built
  from OPI/GEMS payroll matched against DLI's UI wage records. Published as
  **8 regional PDFs** (not one document like WSBA), each with a real per-district
  table (school system, teacher count, 10th percentile / average / 90th percentile
  salary) — confirmed by direct fetch. Caveats: percentile bands rather than a
  BA-step-1 base salary figure (a different metric than WSBA's), small districts
  suppressed (`<5` teachers → `ND`), only one edition (Dec 2024, covering 2022-23)
  found so far — annual cadence unconfirmed, ~1.5 year lag.
- **No superintendent salary or contract-days source exists publicly at all** —
  those figures are public record but scattered across ~393 individual district
  board minutes/contracts, no statewide clearinghouse. Options: omit this field
  for Montana, or fall back to an unofficial aggregator (govsalaries.com,
  openthebooks.com) with a clear "unofficial, unverified" label — not a WSBA-grade
  source either way.

## Federal/national data sources — confirmed working for Montana

Live-tested (not just docs review) against `educationdata.urban.org` and
`api.census.gov` with Montana's state FIPS `30`:

- **CCD** (K-12 staffing) and **IPEDS** (HE salary/staffing/enrollment/FSA Pell) via
  Urban Institute Education Data Portal: confirmed working, same endpoint patterns
  as Wyoming, just swap `fips=56` → `fips=30`. Fall-enrollment endpoint needs a
  disaggregation path segment (e.g. `undergraduate/race/sex/`), not just a bare
  year — a minor shape difference worth noting in the scraper.
- **SAIPE** (district child poverty) and **ACS 5-Year + Subject Tables** (county
  context): confirmed working via geography-metadata + live query shape (both
  correctly 302-redirect to `missing_key.html` without `CENSUS_API_KEY`, same
  requirement as Wyoming — no Montana-specific restriction).
- **Structural quirk**: Montana's CCD district (LEA) directory returns **486
  districts** for 2020 vs. Wyoming's 60 — same elementary/HS fragmentation noted
  above, meaning ~8x more, smaller join targets and more small-number/privacy
  suppression in CCD and SAIPE district-level data.
- **BIE/tribal school reporting is unreliable in CCD** — the
  `bureau_indian_education` field is essentially unpopulated nationally (0 records
  in a 2020 test query). Montana has more BIE/tribal-grant K-12 schools than
  Wyoming (which only has Wind River), so this surfaces more here — don't rely on
  that field; cross-reference a known tribal-school list if BIE coverage ever
  matters.

### Montana county FIPS codes (56 counties, state FIPS 30)

| FIPS | County | FIPS | County |
|---|---|---|---|
| 001 | Beaverhead | 057 | Madison |
| 003 | Big Horn | 059 | Meagher |
| 005 | Blaine | 061 | Mineral |
| 007 | Broadwater | 063 | Missoula |
| 009 | Carbon | 065 | Musselshell |
| 011 | Carter | 067 | Park |
| 013 | Cascade | 069 | Petroleum |
| 015 | Chouteau | 071 | Phillips |
| 017 | Custer | 073 | Pondera |
| 019 | Daniels | 075 | Powder River |
| 021 | Dawson | 077 | Powell |
| 023 | Deer Lodge | 079 | Prairie |
| 025 | Fallon | 081 | Ravalli |
| 027 | Fergus | 083 | Richland |
| 029 | Flathead | 085 | Roosevelt |
| 031 | Gallatin | 087 | Rosebud |
| 033 | Garfield | 089 | Sanders |
| 035 | Glacier | 091 | Sheridan |
| 037 | Golden Valley | 093 | Silver Bow |
| 039 | Granite | 095 | Stillwater |
| 041 | Hill | 097 | Sweet Grass |
| 043 | Jefferson | 099 | Teton |
| 045 | Judith Basin | 101 | Toole |
| 047 | Lake | 103 | Treasure |
| 049 | Lewis and Clark | 105 | Valley |
| 051 | Liberty | 107 | Wheatland |
| 053 | Lincoln | 109 | Wibaux |
| 055 | McCone | 111 | Yellowstone |

Full 5-digit FIPS = `30` + county code (e.g. Yellowstone County = `30111`).

## Scoping decisions (resolved 2026-08-06)

1. **Sequencing**: mirror Wyoming's own build order (confirmed via `git log
   --reverse` on the WY repo — job postings were stable and tested ~36 commits in
   before WSBA/IPEDS salary data was added around commit 64 of 107, well after the
   map/tables/pipeline already worked). Build the K-12 + HE **job-postings**
   pipeline first; salary, staffing (vacancy rate), and Census context are
   explicitly deferred to a later pass, not this one.
2. **K-12 first-pass district list**: top ~15-20 by enrollment, scraped directly
   (Frontline/AppliTrack cluster, PowerSchool/SchoolSpring cluster, Kalispell's
   Tyler Portico one-off), plus Montana OPI's **"Jobs for Teachers"** feed
   (`apps.opi.mt.gov/mtjobsforteachers/`) as the statewide fallback for every
   district not scraped directly. Mirrors Wyoming's 48-districts + WSBA-feed
   pattern.
3. **Higher-ed scope**: **all 16 targets** — the 9 MUS job-board endpoints plus the
   7 tribal colleges. Tribal colleges mostly lack a structured ATS (PDF/paper
   applications instead), so this pass needs two distinct scraping approaches
   (platform-API/HTML scraping for MUS, PDF/static-page parsing for tribal
   colleges) rather than one uniform pattern.
4. **K-12 salary**: deferred per decision #1. The DLI Teacher Compensation Report
   gap analysis above stays as reference for whenever that pass happens.
5. **Elementary/HS district pairs**: treat as one combined scrape target per
   shared HR office/job-board URL (e.g. "Billings" representing both the
   elementary and high-school legal districts), matching how the job boards
   themselves are actually organized — confirmed, not still open.
