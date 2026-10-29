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
| Rapelje School District #32 | Stillwater | `rapelje.k12.mt.us/job-listings` | ✅ **Adopted** (2026-10-21, Batch 10) -- ParentSquare CMS; 3 active positions (Bus Drivers, Preschool Teacher, Cooks Helper) |
| Grass Range Public Schools | Fergus | `grps.k12.mt.us/staff/open-positions` | ✅ **Adopted** (2026-10-21, Batch 11) -- custom CMS; 2 active positions (CDL Bus/Activity Driver, Substitutes in all areas) |
| Big Timber Grade School | Sweet Grass | `sites.google.com/a/bigtimber-gs.k12.mt.us/btgs/staff/employment` | ✅ **Adopted** (2026-10-21, Batch 11) -- Google Sites; 3 active positions (SPED Teacher, Substitute Teachers, SPED Case Manager) |
| Elder Grove School District | Yellowstone | `eldergrove.k12.mt.us/about-eg/employment/available-positions` | ✅ **Adopted** (2026-10-21, Batch 11) -- Finalsite CMS; 1 active position (Paraprofessionals) |
| Heart Butte K-12 Schools | Pondera | `heartbutte.k12.mt.us/employment/` | ✅ **Adopted** (2026-10-21, Batch 12) -- WordPress CMS; 8 active positions (Payroll Clerk, K-12 Counselor, Maintenance/Transportation Supervisor, Subs/Aides/Drivers/Custodians, 4 Coaches) |
| Noxon Public Schools | Sanders | `noxonschools.com/o/nps/page/certified-listings` | ✅ **Adopted** (2026-10-21, Batch 12) -- Apptegy CMS; 1 active position (7–12 Science Teacher) |
| Cayuse Prairie School District #10 | Flathead | `cayuseprairie.com/page/employment` | ✅ **Adopted** (2026-10-21, Batch 10) -- Apptegy custom notice; 2 active positions (Special Education Paraprofessional, 7th & 8th Grade Science Teacher) |
| Judith Gap Schools | Wheatland | `judithgap.k12.mt.us/District/Portal/Employment` | ✅ **Adopted** (2026-10-21, Batch 9) -- CyberSchool CMS jobs widget; 2 active positions (Custodian/Maint/Boiler Operator, School Cook) |
| Hellgate Elementary School District | Missoula | `hellgate.k12.mt.us/our-district/employment` | ✅ **Adopted** (2026-10-21, Batch 13) -- Finalsite CMS (#fsPageContent); 2 active positions (Substitute Teacher, Custodial substitutes) |
| ~~Power School District~~ | Teton | `power.k12.mt.us/District/Portal/Employment` | ❌ **removed** -- page rot: three "Date Posted: March 20, 2023" entries under one undated 2026 blurb. Stale-date filter drops the old ones; the one real item isn't cleanly titled. Recheck if the district cleans up the page. |

To verify and likely add:

| District | County | Page | Issue | Status |
|---|---|---|---|---|
| Condon / Swan Valley Elementary #3 | Missoula | `swanvalleyelementary.org` (NOT `swanvalleyschools.com` = Saginaw MI) | Weebly CMS; titles sit in `#wsite-content h2`; 1 active posting | ✅ **Adopted** (2026-10-21) |
| West Valley School District #1 | Flathead | `westvalleyschool.submittable.com/submit` | Submittable portal; titles sit in `.header-3.word-wrap a`; 1 active posting | ✅ **Adopted** (2026-10-21) |
| Frazer Public Schools | Valley | `frazer.k12.mt.us/District/Jobs/` | CyberSchool CMS; 26 active postings in `.listItem_bodyContent li` | ✅ **Adopted** (2026-10-21) |
| Lambert School District | Richland | `lambertschool.net/career-opportunities/employment-opportunities` | Finalsite CMS; 1 active posting in `#fsPageContent .fsContent ul li` | ✅ **Adopted** (2026-10-21) |
| Richey Public Schools | Dawson | `richey.k12.mt.us/currentopenings` | CyberSchool CMS; 1 active posting in `#maincontent .cs-html-widget strong` | ✅ **Adopted** (2026-10-21) |
| Charlo School District 7J | Lake | `charlo.k12.mt.us` | Custom CMS; 2 active positions (Bus Drivers, Paraprofessionals) in `.announcements__card-title` | ✅ **Adopted** (2026-10-21, Batch 13) |
| Helena Flats School District #15 | Flathead | `helenaflats.org/page/employment` | Apptegy CMS; 2 active positions (Special Education Paraprofessional, Substitutes Needed - all positions) in `window.clientWorkStateTemp` | ✅ **Adopted** (2026-10-22, Batch 14) |
| Woodman Elementary School District #3 | Missoula | `woodmanschool.org/district-information/employment-opportunities` | Google Sites; 1 active position (Substitute Teacher) | ✅ **Adopted** (2026-10-22, Batch 14) |
| Pryor Public Schools | Big Horn | `pryorwarriors.org/human-resources/` | Divi CMS; 2 active positions (Literacy Tutors, Bus Drivers) | ✅ **Adopted** (2026-10-22, Batch 16) |
| West Glacier Elementary School District #8 | Flathead | `westglacierelementary.org/opportunities/employment` | Google Sites; 2 active positions (Substitute Teacher, Part-Time Custodian / Maintenance Worker) | ✅ **Adopted** (2026-10-22, Batch 16) |
| Trout Creek School District #6 | Sanders | `troutcreekeagles.org/apps/pages/index.jsp?uREC_ID=4449487&type=d&pREC_ID=2698685` | Edlio CMS; 4 active positions (Teachers, Business Manager/Clerk, Substitute Teachers, Para-Professional) | ✅ **Adopted** (2026-10-22, Batch 16) |
| Power Public Schools | Teton | `power.k12.mt.us/District/Jobs/` | CyberSchool CMS (/District/Jobs/); 3 active positions (Substitute Teachers, Substitute After-School Custodians, Substitute Kitchen Aides) | ✅ **Adopted** (2026-10-22, Batch 17) |
| Kila School District #20 | Flathead | `docs.google.com/document/d/10u_uwKptqVgvrhCL83skDHtK2lGzPCjRCl88em-58O0/` | Google Sites with live Google Doc HTML table; 4 active positions (Custodian, Substitute Custodian, Substitute Para/Student Support, Substitute Teachers) | ✅ **Adopted** (2026-10-22, Batch 17) |
| Lavina Public Schools | Golden Valley | `lavinapublicschools.com/District/2269-Untitled.html` | CyberSchool CMS; 2 active positions (JH Assistant Volleyball Coach, JH Assistant Football Coach) | ✅ **Adopted** (2026-10-22, Batch 17) |

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
| Lockwood School District | Yellowstone | `lockwoodschool.org/apps/pages/index.jsp?uREC_ID=409277&type=d` | Covered via primary AppliTrack feed (`Lockwood Schools`, `lockwoodschool`); duplicate heuristic entry retired | ✅ **Covered** |
| Canyon Creek School | Yellowstone | `canyoncreekschool.org/apps/jobs/` | Edlio CMS (/apps/jobs/); 1 active position (Paraprofessional Pre-K (All Day Full-Time)) | ✅ **Adopted** (2026-10-21, Batch 13) |
| Pioneer School | Yellowstone | `pioneerschool.us/41034_2` | SchoolCMS; 1 active position (Substitute Teacher) | ✅ **Adopted** (2026-10-22, Batch 15) |
| Montana City Elementary School District #27 | Jefferson | `mtcityschool.net/District/Jobs/` | CyberSchool CMS (/District/Jobs/); extracts postings on demand | ✅ **Adopted** (2026-10-28, Batch 22) |
| Circle Public Schools | McCone | `circleschools.org/employment-opportunities.html` | Weebly CMS; generic personnel application links only; checked 2026-10-21 | RECHECK |
| Whitewater School District | Phillips | `whitewater.k12.mt.us/employment` | Finalsite CMS (#fsEl_3056); 3 active positions (substitutes, bus drivers, custodians) | ✅ **Adopted** (2026-10-21, Batch 9) |
| Geraldine Public Schools | Chouteau | `geraldine.k12.mt.us/o/geraldine-ps/page/employment` | Apptegy; generic Teacher/Classified application forms only; checked 2026-10-21 | TODO |
| Denton Public Schools | Fergus | `denton.k12.mt.us/District/Jobs/` | CyberSchool CMS (/District/Jobs/); extracts postings on demand | ✅ **Adopted** (2026-10-28, Batch 22) |
| Vaughn Elementary School District #74 | Cascade | `vaughnschool.com/District/Jobs/` | CyberSchool CMS; 1 active position (Substitutes Needed) | ✅ **Adopted** (2026-10-22, Batch 14) |
| Harlowton Public Schools | Wheatland | `harlowton.k12.mt.us/page/employment` | Apptegy site with salary schedule; 0 active job titles under Certified Positions; rechecked 2026-10-21 | TODO |
| Chester-Joplin-Inverness (CJI) | Liberty | `cji.k12.mt.us/page/employmentcji` | Apptegy site links live PDF vacancy notice; 5 active positions (Math Teacher, Activities Coord, Admin Assistant, Custodial/Teacher Subs) | ✅ **Adopted** (2026-10-28, Batch 23) |
| Clancy Elementary School District #1 | Jefferson | `clancyschool.org/District/Jobs/` | CyberSchool CMS (/District/Jobs/); extracts postings on demand | ✅ **Adopted** (2026-10-28, Batch 22) |
| Seeley Lake Elementary #34 | Missoula | `sleonline.org/page/join-our-team` | Apptegy site; 1 active position (Substitute (All Areas)); checked 2026-10-21 | ✅ **Adopted** (2026-10-21, Batch 12) |
| Winifred School District | Fergus | `winifred.k12.mt.us` | Apptegy site; links to generic blank application PDFs only (`5il.co/1dfyi`); checked 2026-10-21 | TODO |
| Plains (Plains K-12 #1) | Sanders | employment page exists | 4 evergreen "Application" PDFs + redirect to OPI; rechecked 2026-10-20 | TODO |
| Olney-Bissell School | Flathead | `olneybissellschool.com/o/obs/page/employment` | Apptegy; generic "Certified Application" link only | TODO |
| East Glacier Park Grade School | Glacier | `eastglacierschool.com/employment` | CyberSchool CMS; 1 active position (Licensed Teachers); checked 2026-10-21 | ✅ **Adopted** (2026-10-21, Batch 12) |
| Kila School District #20 | Flathead | `docs.google.com/document/d/10u_uwKptqVgvrhCL83skDHtK2lGzPCjRCl88em-58O0/` | Google Sites with live Google Doc HTML table; 4 active positions | ✅ **Adopted** (2026-10-22, Batch 17) |
| DeSmet School District #20 | Missoula | employment page | generic Certified/Classified application-form links | TODO |
| Gildford Colony School | Hill | employment page | "New Hire Packet" download links only | TODO |
| Fairfield (Greenfield #75) | Teton | `fairfield.k12.mt.us/o/district/browse/51027` | Apptegy documents page links only to generic blank PDFs (Classified, Substitute, Certified Applications); rechecked 2026-10-29 | DECLINED (Group 8) |
| Savage School District #7 (Savage Public Schools) | Richland | `savagepublicschool.com/page/employment` | Apptegy CMS (accordion pagebuilder decoded via `decode_apptegy_pagebuilder_nodes()`); 8 active positions (Elementary Teacher, 6-12 History, K-12 Music, K-12 Counselor, 2 Paras, 3 Coaches) | ✅ **Adopted** (2026-10-29, Batch 25) |
| Dodson School District | Phillips | `dodsonschool.com/page/employment` | Apptegy site with single sentence deferring to OPI; verified 2026-10-29 | Group 2 (Defers to OPI) |
| Monforton School District #27 | Gallatin | `monfortonschool.org/contact-us/job-openings/` | WordPress site with dedicated job buttons; 2 active positions (Business Manager, District Clerk) | ✅ **Adopted** (2026-10-21, Batch 11) |
| Jordan Public Schools | Garfield | `jordanpublicschools.org` | SchoolInSites CMS; 5 active positions in homepage announcement banners (Head of Maintenance, K-12 Music Teacher, JH Football Coach, JH Boys Basketball Coach, HS Boys Basketball Coach) | ✅ **Adopted** (2026-10-22, Batch 15) |
| Vida Elementary School | McCone | `vidaschool.k12.mt.us` | resources page has only generic application PDFs; checked 2026-10-21 | TODO |
| Frenchtown K-12 Schools | Missoula | `ftsd.org` | Apptegy site behind Fastly bot-gate; headless chromote extracts 6 active positions | ✅ **Adopted** (2026-10-28, Batch 24) |
| Lima School District #12 | Beaverhead | `limaschoolmt.org` | Apptegy site with job announcements in Thrillshare live feeds API; 3 active positions | ✅ **Adopted** (2026-10-28, Batch 24) |
| Fromberg Public Schools | Carbon | `frombergpublicschools.com/district-info/employment` | Finalsite CMS; 1 active position in Current Postings (Subs Music Teaching Position) | ✅ **Adopted** (2026-10-22, Batch 18) |
| Lavina Public Schools | Golden Valley | `lavinapublicschools.com/District/2269-Untitled.html` | CyberSchool CMS; 2 active positions (JH Assistant Volleyball/Football Coaches) | ✅ **Adopted** (2026-10-22, Batch 17) |
| Pleasant Valley School District #27 | Flathead | `pvsmt.org/employment-opportunities.html` | Weebly CMS; clean page marker ("No opening at this time"); extracts postings on demand | ✅ **Adopted** (2026-10-22, Batch 18) |
| Bainville K-12 Schools | Roosevelt | `bainvilleschool.com/page/employment` | Apptegy site links live Google Docs for certified/classified vacancies; 7 active positions (Art, History, Elem Teacher, Para, Subs) | ✅ **Adopted** (2026-10-28, Batch 23) |
| Twin Bridges K-12 Schools | Madison | `twinbridges.k12.mt.us/page/employment-opportunities` | Apptegy site; 0 positions listed under 2026-2027 vacancies; checked 2026-10-21 | TODO |
| Troy School District #1 | Lincoln | `troyk12.org/documents/about-our-district/employment/377243` | Apptegy site; "Vacancy Announcements" links directly to Google Drive folder (`1CdUiMRs63JU5xLbNkLaJ1r3HndXnnQpS`); rechecked 2026-10-29 | BLOCKED (Group 6) |
| Opheim Public Schools | Valley | `sites.google.com/site/opheimschool/office` | Google Sites; 3 active positions (Substitute Teacher, Substitute Bus Driver, Music Teacher) | ✅ **Adopted** (2026-10-22, Batch 15) |
| Anderson School District #41 | Gallatin | `andersonmt.org/careers` | ParentSquare CMS; recruiting prose copy only ("Come Work With Us"), no specific openings listed; checked 2026-10-28 | RECHECK |
| Marion School District #54 | Flathead | `sites.google.com/a/marionschoolmt.com/new-marion-school/district-information/employment` | Google Sites; extracts vacancies under VACANCIES; 1 active position (Guest Teacher / Pool of Substitutes) | ✅ **Adopted** (2026-10-28, Batch 23) |
| Fortine School District #14 | Lincoln | Apptegy | real header, empty / "Coming Soon" beneath; rechecked 2026-10-20 | TODO |
| Melville School District #16 | Sweet Grass | Apptegy | real header, empty beneath | TODO |
| Superior School District #3 | Mineral | `ssd3.us/page/employment` | Apptegy page links Google Doc job board (`1ujnHba2a-gWdThpUB-T43LoCZoR_ViXzxZKTEuq67_g`); 3 active positions (bus drivers, substitutes, paraprofessionals) | ✅ **Adopted** (2026-10-21, Batch 9) |
| Ashland Public School | Rosebud | `sites.google.com/ashlandpublicschool.com/aps-district-site/employment` | Published Google Sites; 7 active positions (Clerk, Specialists, Elementary Teacher, Para, SpEd Para, Counselor, Subs) | ✅ **Adopted** (2026-10-21, Batch 10) |
| Rosebud School District | Rosebud | `sites.google.com/site/rosebudhs12` | Google Sites; employment page redirects out to OPI statewide portal; checked 2026-10-21 | TODO |
| Absarokee School District | Stillwater | `absarokee.k12.mt.us` | Apptegy/Thrillshare site; all document folders and board notices link directly to Google Drive folders; rechecked 2026-10-29 | BLOCKED (Group 6) |
| Simms / Sun River Valley #24 | Cascade | `srvs.k12.mt.us/apps/jobs/` | Educational Networks / Edlio CMS; clean jobs widget; extracts show_job postings on demand | ✅ **Adopted** (2026-10-22, Batch 18) |
| Divide School District #4 | Silver Bow | `divideschool.org` | Squarespace "under construction" | TODO |
| McCormick School District #22 | Petroleum | district site | site under active rebuild, no employment nav | TODO |
| Forsyth School District #4 | Rosebud | `forsythpublicschools.org/bus-drivers-wanted/` | WordPress CMS; 1 active position (Bus Drivers Wanted!); links to training program PDF | ✅ **Adopted** (2026-10-22, Batch 19) |
| Circle Public Schools | McCone | `circleschools.org/employment-opportunities.html` | Weebly CMS; clean page marker; extracts postings on demand | ✅ **Adopted** (2026-10-22, Batch 19) |
| DeSmet Public School | Missoula | `desmetschool.org/available-employment-opportunities/` | WordPress / Divi CMS; clean application page; extracts postings on demand | ✅ **Adopted** (2026-10-22, Batch 19) |
| Fishtail School District #13 | Stillwater | `fishtailschool.org/job-openings/` | WordPress CMS; dedicated job openings page; extracts postings on demand | ✅ **Adopted** (2026-10-22, Batch 20) |
| Nye School District #31 | Stillwater | `nyeschooldistrict.org/job-openings/` | WordPress CMS; dedicated job openings page; extracts postings on demand | ✅ **Adopted** (2026-10-22, Batch 20) |
| Potomac Elementary School District #11 | Missoula | `potomacschoolmontana.us/general-9` | Wix CMS; dedicated Jobs page with application prompt; extracts postings on demand | ✅ **Adopted** (2026-10-22, Batch 20) |
| Frontier Elementary School | Roosevelt | `frontierk8.org/District/Jobs/` | CyberSchool CMS (/District/Jobs/); extracts postings on demand | ✅ **Adopted** (2026-10-27, Batch 21) |
| Saco Public Schools | Phillips | `sacoschools.k12.mt.us/District/Jobs/` | CyberSchool CMS (/District/Jobs/); extracts postings on demand | ✅ **Adopted** (2026-10-27, Batch 21) |
| Ulm Public Schools | Cascade | `ulmschools.com/forms--files.html` | Weebly CMS; dedicated forms & files page; extracts postings on demand | ✅ **Adopted** (2026-10-27, Batch 21) |
| Brockton School District | Roosevelt | `brockton.k12.mt.us/employment` | Plain HTML; migrated from SchoolInSites to district site; 3 active positions (Elementary Teacher, STEM Secondary, Humanities Secondary) | ✅ **Recovered** (2026-10-27, Batch 21) |

---

## Group 3 — Need the correct Montana URL

A same-named district in another state, or no real MT site found yet. Find the
real one (verify address/phone), then re-triage.

| District | County | Trap / status | Status |
|---|---|---|---|
| Joliet Public School District 86 | Carbon | Previous registry link was Illinois SD86 (`joliet86.tedk12.com`); real MT site is `jolietschools.org` (`table.employment-table`); 5 active positions (Bus Driver, Subs, 3 Coaches) | ✅ **Adopted** (2026-10-29, Batch 25) |
| Avon | Powell | `avon*` resolves to Avon-by-the-Sea, NJ; real MT school is Powell County District 29 (notices hosted on `powellcountymt.gov`; no standalone website) | DECLINED (Group 8) |
| Bynum | Teton | `bynumschool.org` → Midland, TX; real MT site is GoDaddy (`bynumsch.org` / `bynumschool.godaddysites.com`), 1-page site with calendar download links only | DECLINED (Group 8) |
| Luther School | Carbon | `lutherlions.org` → Luther, OK; real MT site is `lutherschool.org/index.php/documents` (Joomla); 2 active postings | ✅ **Adopted** (2026-10-21) |
| Pryor Public Schools | Big Horn | `pryorschools.org` → Pryor, OK; real MT site is `pryorwarriors.org` (Arrow Creek Elem / Plenty Coups HS); 2 active positions | ✅ **Adopted** (2026-10-22, Batch 16) |
| Pine Grove | Rosebud/Garfield | `pgasd.com` → Pennsylvania; real MT school is Garfield County District 19 (Brusett MT); 1-teacher 7-student rural school, no standalone website | DECLINED (Group 8) |
| Hawks Home | Carter/Powder River | `r-mschool.org` → Republic-Michigamme, MI; real MT school is Carter County District 78 (Hammond MT); tiny rural school (~5-12 students), no standalone website | DECLINED (Group 8) |
| Basin (Boulder area) | Jefferson | Real MT Basin School reopened April 2026; registered domain is `basin.k12.mt.us`; DNS pending / site under construction; notices covered via OPI statewide feed | DECLINED (Group 8) |
| Medicine Lake School District #10 | Sheridan | Real site is Apptegy (`medicinelake.k12.mt.us`); staff directory active, no open job board posted | RECHECK |
| Park City Schools | Stillwater | Real site is Apptegy (`parkcityschools.org`); 2 active postings | ✅ **Adopted** (earlier batch) |
| Elliston | Powell | Powell County District 27; notices hosted on `powellcountymt.gov`; no standalone website | DECLINED (Group 8) |
| Garrison | Powell | Powell County District 20; notices hosted on `powellcountymt.gov`; no standalone website | DECLINED (Group 8) |
| Dupuyer | Pondera | Pondera County District 2; no standalone website domain | DECLINED (Group 8) |

---

## Group 4 — Multi-page architecture

Real, substantial districts whose postings are split across several
category-specific subpages — needs one target/scraper row per subpage. Fine
for the LLM pilot (multiple rows, same District name); a bigger lift for a
direct scraper.

| District | County | Page | Note | Status |
|---|---|---|---|---|
| Hellgate Elementary School District | Missoula | `hellgate.k12.mt.us/our-district/employment` | Finalsite CMS (#fsPageContent); 2 active positions (Substitute Teacher, Custodial substitutes) | ✅ **Adopted** (2026-10-21, Batch 13) |

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
| Victor School District #7 | Ravalli | Apptegy page links Google Doc job board (`1hPjGJCP2_6t4nOMl9xx7oZlK061x5KWd`); 4 active positions (SpEd teacher, paraprofessional, track coach, substitute) | ✅ **Adopted** (2026-10-21, Batch 9) |
| Eureka (Lincoln County #13) | Lincoln | "Job Openings" link → unstructured Google Drive folder | BLOCKED |
| Troy School District #1 | Lincoln | "Vacancy Announcements" link → unstructured Google Drive folder (`1CdUiMRs63JU5xLbNkLaJ1r3HndXnnQpS`) | BLOCKED |
| Plains School District #1 | Sanders | `plainsschools.net/employment/` embeds an unstructured Google Drive folder (`1PLQRtQHAjWSZxlyn3kcWtEp1N7crZh-m`) | BLOCKED |
| Absarokee School District | Stillwater | Apptegy site (`absarokeesdmt.sites.thrillshare.com`); all district document folders and board notices link directly to Google Drive folders | BLOCKED |

---

## Group 7 — Stale / contradictory / broken pages

| District | County | Issue | Status |
|---|---|---|---|
| Kester School District #29 | Garfield | `kesterschool23.org/employment` banner explicitly states: "Kester School is no longer accepting applications for the 2025/2026 teaching position." Tiny 1-room rural district (~2-6 students), no active openings; checked 2026-10-28 | DECLINED (Group 8) |
| Fishtail School District #13 | Stillwater | `fishtailschool.org/job-openings/` | Clean job openings page without broken placeholders | ✅ **Adopted** (2026-10-22, Batch 20) |

---

## Group 8 — Likely genuine dead ends (tiny districts, no employment page)

Confirmed no employment page in nav/sitemap, or a "no employment nav item"
result. Very low priority — most are 1–2-room districts that don't maintain a
jobs page at all. Recheck only if one grows.

Ryegate, Highwood, Cardwell (~35 students), Kircher, LaMotte,
Rau, Somers Lakeside #29 (HR folder contains only CBAs and generic application link; 0 openings),
Blue Creek School (employment folders empty; 0 openings), Fairfield (only generic application form PDFs), Morin.

Long tail of tiny lone-elementary districts checked and declined the same way:
Alder, Alzada, Amsterdam, Ayers, Basin, Biddle, Birney, Brorson, Cleveland, Cohagen,
Cooke City, Davey, Deerfield, Golden Ridge, Grant, Greycliff, Hawks Home, Helmville, Kester, King Colony, Kinsey,
Knees, Liberty, Lindsay, Malmborg, Nye, Ovando, Pendroy, Pine Grove, Pioneer, Plenty
Coups, Polaris, Potomac, Reichle, Ross, Springhill, Sunset, Trinity,
West Glacier, Wisdom, Wise River, Yaak.

Also: Cottonwood School District #22 (Montessori K-5 near Bozeman — real,
separate from #57, no careers link found). Swan Lake-Salmon Prairie School District #73
(Salmon Prairie Elementary permanently closed at end of 2025-2026 school year).

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

**Triage status:** Golden Ridge and Grant were investigated and confirmed as 1-room rural elementary districts without standalone job boards, triaged to Group 8. (Dupuyer, Elliston, and Garrison were previously triaged to Group 8; Frontier was adopted in Batch 21). Low-yield towns remain cross-referenced against `k12_district_registry.csv` and Group 8.

---

## Group 11 — Platform Drift Recoveries

Districts previously registered on legacy platforms that migrated silently and have been recovered into active coverage:

| District | Previous Platform | New Platform & URL | Restored Openings | Date Recovered |
|---|---|---|---|---|
| Brockton School District | SchoolInSites | Direct HTML (`brockton.k12.mt.us/employment`) | 3 active positions | 2026-10-27 |
| Columbia Falls School District 6 | SchoolSpring (`sd6.schoolspring.com` returning 0) | RedRover (`https://jobs.redroverk12.com/org/sd659912`) | 25 active positions | 2026-10-28 |
| Townsend School District | Apptegy (`townsend.k12.mt.us/page/employment`) | Layout drift recovery (hyphen header & retired ATHLETIC DIRECTOR marker) | 4 active positions | 2026-10-28 |
| Bozeman Public Schools | AppliTrack (HTTP 500 server error) | Tyler Portico (`https://bozemanschooldistrict7mt.tylerportico.com/tess/citizen/jobs/job-list/jobs`) | 46 active positions | 2026-10-29 |
| Polson School District | SchoolSpring (`polson.schoolspring.com` returning 0) | Tyler Portico (`https://polsonschooldistrict23mt.tylerportico.com/tess/citizen/jobs/job-list/jobs`) | 3 active positions | 2026-10-29 |
| Arrowhead Elementary School District #75 | ArrowheadHeuristic (Cloudflare HTTP 520 server error) | Cloudflare user-agent recovery (retired obsolete Windows Chrome UA header) | 3 active positions | 2026-10-29 |
| Manhattan School District | TylerPortico (endpoint redirect) | Verified live endpoint (`manhattanpublicschoolsmt.employeeaccess.tylerapp.com`) | Clean empty array (0 vacancies) | 2026-10-29 |
