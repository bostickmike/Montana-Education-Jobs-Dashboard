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
| Condon / Swan Valley Elementary #3 | Missoula | `swanvalleyelementary.org` (NOT `swanvalleyschools.com` = Saginaw MI) | one real posting, free-flowing prose, no title/heading/list marker | TODO |

---

## Group 2 — Recheck later (real page, currently generic forms only or empty)

The platform is real; postings often appear later. Recheck monthly. If real
named titles show up with a marker → direct scraper; without a marker → LLM.

| District | County | Page | What's there now | Status |
|---|---|---|---|---|
| Plains (Plains K-12 #1) | Sanders | employment page exists | 4 evergreen "Application" PDFs + redirect to OPI; no named titles | TODO |
| Olney-Bissell School | Flathead | `olneybissellschool.com/o/obs/page/employment` | Apptegy; generic "Certified Application" link only | TODO |
| East Glacier Park Grade School | Glacier | `eastglacierschool.com/employment` | "Certified/Classified Staff Application" links only | TODO |
| Kila School District #20 | Flathead | "Open Positions" page | generic application-packet links only | TODO |
| DeSmet School District #20 | Missoula | employment page | generic Certified/Classified application-form links | TODO |
| Gildford Colony School | Hill | employment page | "New Hire Packet" download links only | TODO |
| Fairfield (Greenfield #75) | Teton | Apptegy "Employment Applications" page + `greenfieldschool.wixsite.com` | generic forms only / Wix with no Jobs nav | TODO |
| Savage School District #7 | Richland | Apptegy | 3 bare category labels, no title text | TODO |
| Dodson School District | Phillips | Apptegy | single sentence deferring to OPI | TODO |
| Monforton School District #27 | Gallatin | district site | Certified → OPI listing; Classified → embedded Indeed widget | TODO |
| Anderson School District #41 | Gallatin | district site | "Come Work With Us" recruiting copy, no titles | TODO |
| Marion School District #54 | Flathead | real MT Marion is a Google Sites page (`marionschools.org` = Jasper TN) | boilerplate application PDFs + one generic substitute sentence | TODO |
| Fortine School District #14 | Lincoln | Apptegy | real header, empty / "Coming Soon" beneath | TODO |
| Melville School District #16 | Sweet Grass | Apptegy | real header, empty beneath | TODO |
| Superior School District #3 | Mineral | Apptegy | "Current Open Positions" heading with nothing under it + Wufoo form | TODO |
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
| Avon | Powell | `avon*` resolves to Avon-by-the-Sea, NJ | TODO |
| Bynum | Teton | `bynumschool.org` → Midland, TX | TODO |
| Luther | Carbon | `lutherlions.org` → Luther, OK | TODO |
| Pine Grove | Rosebud | `pgasd.com` → Pennsylvania | TODO |
| Hawks Home | Powder River | `r-mschool.org` → Republic-Michigamme, MI | TODO |
| Basin (Boulder area) | Jefferson | real MT Basin School **reopened April 2026** — recheck for a new site; `basinschools.net` = Idaho City, ID | RECHECK |
| Medicine Lake School District #10 | Sheridan | searched, no MT-specific site found — needs a targeted search | TODO |
| Park City (MT) | Stillwater | searched, no MT-specific site found — needs a targeted search | TODO |

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
