# K-12 district coverage backlog

A working checklist of Montana K-12 districts **not yet covered** by a direct
scraper, with the specific problem each one hit and the path forward. Compiled
2026-09-06 from the session memory (`mt-dashboard-district-expansion`,
`mt-dashboard-full-opi-coverage-goal`) and `misc_district_scrapers.R`'s own
comments.

**Some of these URLs may be wrong** — several districts have same-named
districts in other states, and a few pages weren't previewable without a real
browser. Verify the real Montana site (address / phone on the page itself)
before spending time on any one.

**How to work this list:** pick one district, open its real employment page,
and decide:

- **Direct scraper** — the page has a genuine, repeatable structural marker
  (a heading, a list, a table, a fixed sentence). Add a registry row + a
  `fetch_*` function + a fixture test. Always check `fetch_schoolspring_postings("<slug>.schoolspring.com")`
  first — several districts needed zero new code.
- **LLM shadow pilot** — real named openings, but published as prose with no
  marker. Add a row to `llm_extract_targets.csv` (see `LLM_EXTRACT.md`). No
  code, no test per district.
- **Recheck later** — real page, but right now only generic application
  forms / "coming soon". Note the date; try again in a month.
- **Dead end** — no employment page anywhere, or content behind a login /
  Google Drive folder / an image. Leave it; OPI's statewide feed still
  surfaces the district's teacher postings.

Update the **Status** column as you go.

---

## Group 1 — LLM shadow pilot (real prose openings, no marker)

Already in `llm_extract_targets.csv` as of this PR:

| District | County | Page | Note | Status |
|---|---|---|---|---|
First live extraction 2026-09-07 (Gemini). All titles verified against the
live pages -- nothing fabricated.

| District | County | Page | Live-run result 2026-09-07 |
|---|---|---|---|
| Rapelje School District #32 | Stillwater | `rapelje.k12.mt.us/job-listings` | ✅ 3/3 (Bus Drivers, Preschool Teacher, Cook's Helper) |
| Grass Range Public Schools | Fergus | `grps.k12.mt.us/staff/open-positions` | ✅ 3/3 after the "standing-JD list ≠ current openings" prompt rule |
| Cayuse Prairie School District #10 | Flathead | `cayuseprairie.com/page/employment` | ✅ 1/1 (SpEd Paraprofessional -- the page really does only have one) |
| Judith Gap Schools | Wheatland | `judithgap.k12.mt.us/District/Portal/Employment` | ✅ 2 (Custodian/Maint/Boiler Operator, School Cook) -- **URL corrected** from `/employment/job-openings`, which was a shell |
| Hellgate Elementary School District | Missoula | `hellgate.k12.mt.us/our-district/employment` | ✅ 4 on the main page (School Nurse, paras, Sub Teacher, Custodial Subs). Add subpage rows if content is missed. |
| ~~Power School District~~ | Teton | `power.k12.mt.us/District/Portal/Employment` | ❌ **removed** -- page rot: three "Date Posted: March 20, 2023" entries under one undated 2026 blurb. Stale-date filter drops the old ones; the one real item isn't cleanly titled. Recheck if the district cleans up the page. |

To verify and likely add:

| District | County | Page | Issue | Status |
|---|---|---|---|---|
| Condon / Swan Valley Elementary #3 | Missoula | `swanvalleyelementary.org` (NOT `swanvalleyschools.com` = Saginaw MI) | Weebly CMS; titles sit in `#wsite-content h2`; 1 active posting | ✅ **Adopted** (2026-10-21) |
| West Valley School District #1 | Flathead | `westvalleyschool.submittable.com/submit` | Submittable portal; titles sit in `.header-3.word-wrap a`; 1 active posting | ✅ **Adopted** (2026-10-21) |
| Frazer Public Schools | Valley | `frazer.k12.mt.us/District/Jobs/` | CyberSchool CMS; 26 active postings in `.listItem_bodyContent li` | ✅ **Adopted** (2026-10-21) |
| Lambert School District | Richland | `lambertschool.net/career-opportunities/employment-opportunities` | Finalsite CMS; 1 active posting in `#fsPageContent .fsContent ul li` | ✅ **Adopted** (2026-10-21) |
| Richey Public Schools | Dawson | `richey.k12.mt.us/currentopenings` | CyberSchool CMS; 1 active posting in `#maincontent .cs-html-widget strong` | ✅ **Adopted** (2026-10-21) |

---

## Group 2 — Recheck later (real page, currently generic forms only or empty)

The platform is real; postings often appear later. Recheck monthly. If real
named titles show up with a marker → direct scraper; without a marker → LLM.

| District | County | Page | What's there now | Status |
|---|---|---|---|---|
| Sweet Grass County High School | Sweet Grass | `sgchs.com/page/employment` | Apptegy; 5 positions under Open Coaching/Bus Driving/Teaching headers | ✅ **Adopted** (2026-10-20) |
| Harlem Public Schools | Blaine | `applitrack.com/harlemhs/onlineapp/` | Frontline / AppliTrack (`harlemhs`); 8 active postings | ✅ **Adopted** (2026-10-20) |
| Belfry Public Schools | Carbon | `belfrybats.org/index.php/our-school/employment` | Table (`table.uk-table`); 2 active postings | ✅ **Adopted** (2026-10-20) |
| Nashua Public Schools | Valley | `nashua.k12.mt.us/District/Jobs/` | Category headers (CyberSchool CMS); 7 active postings | ✅ **Adopted** (2026-10-21) |
| Whitehall Public Schools | Jefferson | `whitehallschools.org/apps/jobs/` | Edlio CMS (`.list-item`); 4 active postings | ✅ **Adopted** (2026-10-21) |
| Broadus Public Schools | Powder River | `broadus.net/job-openings` | Published Google Sites (`h3`); 4 active postings | ✅ **Adopted** (2026-10-21) |
| Wibaux Public Schools | Wibaux | `wibauxschools.net/employment` | Wix CMS button links; 1 active posting | ✅ **Adopted** (2026-10-21) |
| Hot Springs School District | Sanders | `hssdmt.org/page/district-employment` | Apptegy; 8 active postings under ALL-CAPS headers | ✅ **Adopted** (2026-10-21) |
| Highwood Public Schools | Chouteau | `highwood.k12.mt.us/District/Jobs/` | CyberSchool CMS; 4 active postings (drivers, janitorial, subs) | ✅ **Adopted** (2026-10-21) |
| Smith Valley School District #8 | Flathead | `smithvalleyschool.org/employment-opportunities` | Published Google Sites; 2 active postings (coach, sub) | ✅ **Adopted** (2026-10-21) |
| Moore Public Schools | Fergus | `mooreschoolmt.com/employment.html` | Weebly CMS; 1 active posting (custodial) | ✅ **Adopted** (2026-10-21) |
| Cardwell Elementary School | Jefferson | `sites.google.com/cardwellschool.org/cougars/join-cardwell` | Published Google Sites; 1 active posting (1st/2nd teacher) | ✅ **Adopted** (2026-10-21) |
| Boulder Elementary School District #7 | Jefferson | `bgs.k12.mt.us/employment` | SchoolCMS / html widget; 2 active postings (coach, after school) | ✅ **Adopted** (2026-10-21) |
| Jefferson High School District #1 | Jefferson | `jhs.k12.mt.us/EmploymentOpportunities.aspx` | eSchoolView CMS; 6 active postings (cheer, football, volleyball, teachers, paras) | ✅ **Adopted** (2026-10-21) |
| Sheridan Public Schools | Madison | `sheridan.k12.mt.us/district/employment` | Google Sites; 4 active postings (coaches, subs, drivers) | ✅ **Adopted** (2026-10-21) |
| Lockwood School District | Yellowstone | `lockwoodschool.org/apps/pages/index.jsp?uREC_ID=409277&type=d` | Edlio CMS; 8 active postings (teachers, paras, coaches, subs, crosswalk) | ✅ **Adopted** (2026-10-21) |
| Canyon Creek School | Yellowstone | `canyoncreekschool.org/apps/pages/index.jsp?uREC_ID=532741&type=d` | Edlio CMS; 2 generic printable application PDFs only; checked 2026-10-21 | RECHECK |
| Pioneer School | Yellowstone | `pioneerschool.us/41034_2` | SchoolCMS; single standing substitute notice only; checked 2026-10-21 | RECHECK |
| Montana City ESD 27 | Jefferson | `mtcityschool.net/District/Jobs/` | CyberSchool CMS; current jobs list empty; checked 2026-10-21 | RECHECK |
| Circle Public Schools | McCone | `circleschools.org/employment-opportunities.html` | Weebly CMS; generic personnel application links only; checked 2026-10-21 | RECHECK |
| Whitewater School District | Phillips | `whitewater.k12.mt.us/employment` | Plain HTML; "currently fully staffed for 2025-2026"; checked 2026-10-21 | RECHECK |
| Geraldine Public Schools | Chouteau | `geraldine.k12.mt.us/page/employment` | Apptegy; generic Teacher/Classified application forms only; checked 2026-10-21 | TODO |
| Denton Public Schools | Fergus | `denton.k12.mt.us/employment` | CyberSchool; 0 active postings listed; checked 2026-10-21 | TODO |
| Vaughn Elementary | Cascade | `vaughnschool.com/District/Jobs/` | CyberSchool; standing substitute notice only; checked 2026-10-21 | TODO |
| Harlowton Public Schools | Wheatland | `harlowton.k12.mt.us/page/employment` | Apptegy site with salary schedule; 0 active job titles under Certified Positions; rechecked 2026-10-21 | TODO |
| Chester-Joplin-Inverness (CJI) | Liberty | `cji.k12.mt.us/page/employmentcji` | Apptegy site; real page found via menu drawer; currently has a single combined PDF vacancy notice | RECHECK |
| Clancy School District | Jefferson | `clancyschool.org/page/employment` | CyberSchool CMS page is empty shell with empty placeholders; checked 2026-10-21 | TODO |
| Seeley Lake Elementary #34 | Missoula | `sleonline.org` | Apptegy site, /page/employment 404s, no jobs nav; checked 2026-10-20 | TODO |
| Winifred School District | Fergus | `winifred.k12.mt.us` | Apptegy site, /page/employment 404s, no jobs nav; checked 2026-10-20 | TODO |
| Plains (Plains K-12 #1) | Sanders | employment page exists | 4 evergreen "Application" PDFs + redirect to OPI; rechecked 2026-10-20 | TODO |
| Olney-Bissell School | Flathead | `olneybissellschool.com/o/obs/page/employment` | Apptegy; generic "Certified Application" link only | TODO |
| East Glacier Park Grade School | Glacier | `eastglacierschool.com/employment` | "Certified/Classified Staff Application" links only; rechecked 2026-10-20 | TODO |
| Kila School District #20 | Flathead | "Open Positions" page | generic application-packet links only | TODO |
| DeSmet School District #20 | Missoula | employment page | generic Certified/Classified application-form links | TODO |
| Gildford Colony School | Hill | employment page | "New Hire Packet" download links only | TODO |
| Fairfield (Greenfield #75) | Teton | Apptegy "Employment Applications" page + `greenfieldschool.wixsite.com` | generic forms only / Wix with no Jobs nav | TODO |
| Savage School District #7 | Richland | Apptegy | 3 bare category labels, no title text | TODO |
| Dodson School District | Phillips | Apptegy | single sentence deferring to OPI | TODO |
| Monforton School District #27 | Gallatin | district site | Certified → OPI listing; Classified → embedded Indeed widget; rechecked 2026-10-20 | TODO |
| Anderson School District #41 | Gallatin | district site | "Come Work With Us" recruiting copy, no titles | TODO |
| Marion School District #54 | Flathead | real MT Marion is a Google Sites page (`marionschools.org` = Jasper TN) | boilerplate application PDFs + one generic substitute sentence | TODO |
| Fortine School District #14 | Lincoln | Apptegy | real header, empty / "Coming Soon" beneath; rechecked 2026-10-20 | TODO |
| Melville School District #16 | Sweet Grass | Apptegy | real header, empty beneath | TODO |
| Superior School District #3 | Mineral | Apptegy | "Current Open Positions" heading with nothing under it + Wufoo form; rechecked 2026-10-20 | TODO |
| Absarokee School District | Stillwater | `absarokee.k12.mt.us` | Apptegy site, /page/employment 404s, no jobs page; checked 2026-10-20 | TODO |
| Simms / Sun River Valley #24 | Cascade | "Educational Networks" CMS | job page currently empty | TODO |
| Divide School District #4 | Silver Bow | `divideschool.org` | Squarespace "under construction" | TODO |
| McCormick School District #22 | Petroleum | district site | site under active rebuild, no employment nav | TODO |
| Forsyth School District #4 | Rosebud | district site | single combined "Vacancy Announcement" PDF (not one PDF per role) | TODO |

---

## Group 3 — Need the correct Montana URL

A same-named district in another state, or no real MT site found yet. Find the
real one (verify address/phone), then re-triage.

| District | County | Trap / status | Status |
|---|---|---|---|
| Avon | Powell | `avon*` resolves to Avon-by-the-Sea, NJ; real MT school is `avon.k12.mt.us` | TODO |
| Bynum | Teton | `bynumschool.org` → Midland, TX; real MT school is `bynum.k12.mt.us` | TODO |
| Luther School | Carbon | `lutherlions.org` → Luther, OK; real MT site is `lutherschool.org/index.php/documents` (Joomla); 2 active postings | ✅ **Adopted** (2026-10-21) |
| Pine Grove | Rosebud | `pgasd.com` → Pennsylvania | TODO |
| Hawks Home | Powder River | `r-mschool.org` → Republic-Michigamme, MI | TODO |
| Basin (Boulder area) | Jefferson | Real MT Basin School reopened April 2026; registered domain is `basin.k12.mt.us`; DNS pending / site under construction; `basinschools.net` = Idaho City, ID | RECHECK |
| Medicine Lake School District #10 | Sheridan | Real site is Apptegy (`medicinelake.k12.mt.us`); staff directory active, no open job board posted | RECHECK |
| Park City Schools | Stillwater | Real site is Apptegy (`parkcityschools.org`); 2 active postings | ✅ **Adopted** (earlier batch) |

---

## Group 4 — Multi-page architecture

Real, substantial districts whose postings are split across several
category-specific subpages — needs one target/scraper row per subpage. Fine
for the LLM pilot (multiple rows, same District name); a bigger lift for a
direct scraper.

| District | County | Page | Note | Status |
|---|---|---|---|---|
| Hellgate Elementary School District | Missoula | `hellgate.k12.mt.us/our-district/employment` + `/para-professional-positions` + ~4 more | main page is in the pilot; capture the subpage URLs and add them | IN PROGRESS |

---

## Group 5 — OCR needed

The employment info is an image, not text — needs `tesseract` (offline,
keyless) or an LLM vision call, not the text-extraction path.

| District | County | Page | Note | Status |
|---|---|---|---|---|
| Box Elder Public Schools #13 | Hill | district site | real, separate district; employment "page" is a static flyer image with no real text | DEFERRED (not worth OCR for one district yet) |

---

## Group 6 — Content behind a login / Drive folder

Dead end unless the district changes how it hosts postings. OPI's feed still
covers their teacher postings.

| District | County | Issue | Status |
|---|---|---|---|
| Victor School District #7 | Ravalli | Apptegy behind the Client Challenge gate; real postings in a sign-in-walled Google Doc | BLOCKED |
| Eureka (Lincoln County #13) | Lincoln | "Job Openings" link → unstructured Google Drive folder | BLOCKED |
| Troy School District #1 | Lincoln | "Vacancy Announcements" link → unstructured Google Drive folder | BLOCKED |
| Plains School District #1 | Sanders | `plainsschools.net/employment/` embeds an unstructured Google Drive folder (`1PLQRtQHAjWSZxlyn3kcWtEp1N7crZh-m`) | BLOCKED |

---

## Group 7 — Stale / contradictory / broken pages

| District | County | Issue | Status |
|---|---|---|---|
| Kester School District #29 | Fallon | banner says "no longer accepting applications" while the body still describes the position in present tense | TODO (recheck) |
| Fishtail School District #16 | Stillwater | "Job Openings" page is a broken template with literal `sample@email.com` placeholder text | TODO (recheck) |

---

## Group 8 — Likely genuine dead ends (tiny districts, no employment page)

Confirmed no employment page in nav/sitemap, or a "no employment nav item"
result. Very low priority — most are 1–2-room districts that don't maintain a
jobs page at all. Recheck only if one grows.

Denton, Saco, Ryegate, Highwood, Cardwell (~35 students), Kircher, LaMotte,
Rau, Somers Lakeside #29, Morin.

Long tail of tiny lone-elementary districts checked and declined the same way:
Alder, Alzada, Amsterdam, Ayers, Biddle, Birney, Brorson, Cleveland, Cohagen,
Cooke City, Davey, Deerfield, Greycliff, Helmville, King Colony, Kinsey,
Knees, Liberty, Lindsay, Malmborg, Nye, Ovando, Pendroy, Pioneer, Plenty
Coups, Polaris, Potomac, Reichle, Ross, Springhill, Sunset, Trinity, Vaughn,
West Glacier, Wisdom, Wise River, Woodman, Yaak.

Also: Cottonwood School District #22 (Montessori K-5 near Bozeman — real,
separate from #57, no careers link found).

---

## Group 9 — Out of scope

Consistent with `RESEARCH_NOTES.md`'s original K-12 scoping decision.

| Entity | Why |
|---|---|
| Busby (Northern Cheyenne Tribal School) | BIE-funded tribal school |
| Billings Christian School, other private schools | private |
| Bear Paw, Yellowstone Academy (YWCCSSC) | special-education cooperatives, not independent LEAs |
| OPI codes ≥ 4000 in the district dropdown | Head Start, co-ops, colleges, associations — never a real K-12 LEA |

---

## Group 10 — Not yet investigated

The ~89 lower-yield lone-elementary towns from the OPI master list were never
fully worked (the expansion sessions stopped at a search-budget cap). The
authoritative artifacts are in the session memory directory:

- `opi_full_master_target_list.csv` — the cleaned 120-town target list, with a
  `has_hs_pair` column flagging the higher-yield rows
- `opi_raw_district_dropdown_2026-08-24.csv` — the raw 602-row OPI dropdown

**Resume by checking:** Dupuyer, Elliston, Frontier, Garrison, Golden Ridge,
Grant — then re-diff the low-yield rows against `k12_district_registry.csv` +
Group 8 above to catch anything skipped.
