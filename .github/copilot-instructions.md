# Copilot instructions — Montana Education Jobs Dashboard

R project: a weekly scrape pipeline (`Mt_ED_Jobs.Rmd`) feeding a Shiny dashboard (`Mt_Ed_Jobs/app.R`) of Montana K-12 and higher-ed job postings. There is no package structure; files are `source()`d. Your environment (R, packages, headless Chrome) is set up by `.github/workflows/copilot-setup-steps.yml`.

## Most tasks here: fixing one scraper

Issues labeled `scraper-autofix` are filed automatically by the weekly drift check when a source's live page has postings its scraper no longer finds. The issue body names the source, live URL, registry platform and scraper entry point. Usual cause: the site's markup changed.

1. **Capture a real fixture, in the form the parser consumes.** Fetch the live page the same way the scraper does and save it under `tests/testthat/fixtures/` with a dated name (e.g. `hinsdale_untitled_2026-09-22.html`). Most chromote scrapers (Apptegy etc.) parse `document.body.innerText`, so their fixture is that text, saved as `.txt` like the existing `apptegy_*_content_*.txt` / `*_rendered.txt` files. **Never hand-write or edit a fixture.** Tests in this repo run against real captured data only.
2. **Keep the old fixture and its tests passing.** Sites flip between layouts, so the parser must handle both.
3. **Make the smallest change that works** in the existing `parse_*` function, in the file's existing style. Update the comment above the function to say what changed on the site and when.
4. **Add a regression test** in the matching `tests/testthat/test-*.R` file that asserts the exact titles in the new fixture.
5. **Run the full suite:** `Rscript -e 'testthat::test_dir("tests/testthat")'`. It must be green.
6. Reference the issue in the PR body with `Fixes #<n>`. CI uses that link to re-run the fixed scraper against the live site.

### Your sandbox is not the real site
You work behind a firewall; CI and the weekly scrape don't. Before blaming the site, rule out your sandbox:
- **The drift check already rendered this page in CI** with chromote and `document.body.innerText`. That's where the issue's title list came from. If your render shows none of those titles, your sandbox is the likelier culprit. Check the firewall's blocked-host warning. Asset CDNs (e.g. Apptegy's `apptegy.net`, `5il.co`) are needed for the page to hydrate.
- The firewall intercepts TLS, so headless Chrome may reject certificates. In your own session only, `chromote::set_chrome_args(c(chromote::get_chrome_args(), "--ignore-certificate-errors"))` before creating a session. Never commit that flag.
- **Don't change how a scraper fetches the page** (e.g. innerText → parsing embedded JSON or `outerHTML`) to work around your sandbox. If you can't get a render that matches what the drift check saw, say so in the PR and stop. A human will capture the fixture.

### Keep the parser's existing scope
Only restore what the parser used to find. The issue's title list is what an LLM read off the whole page, so it can include things this source deliberately excludes. Read the comment above the `parse_*` function and the existing tests. Some sources (Lone Rock, for one) exclude a standing substitute-recruiting list as not being openings. Others (Elysian, St. Regis) count substitute postings. Follow that source's convention. If the page gained a genuinely new category, mention it in the PR rather than adding it.

The fixture tests only show that the parser handles the fixture. The PR's live check shows the scraper works against the real site, so before opening the PR, check that your fixture matches what the site serves.

### Stop and say so instead of forcing a fix when:
- The page genuinely lists no postings.
- The source moved to a different platform/ATS or URL. Changing the platform or URL is a registry change, which a human does.
- The site is returning errors (HTTP 429/5xx) rather than changed markup.

## Never touch
- `k12_district_registry.csv`, `he_institution_registry.csv`, `llm_extract_targets.csv`
- Anything under `Mt_Ed_Jobs/` (accumulated data the dashboard ships), `Archivek12_Data/`, `Archived_HE_Data/`
- `.github/workflows/*`, or the `REQUIRED_SCHEMAS` in `schema_check.R`

## Useful context
- Scraper tiers: `direct_api_scrapers.R` (real ATS APIs), `misc_district_scrapers.R` / `misc_college_scrapers.R` (heuristic HTML/chromote scrapers). `APPTEGY_DISTRICT_SCRAPERS` in `misc_district_scrapers.R` maps each Apptegy/Red Rover district to its scraper.
- `Mt_ED_Jobs.Rmd` shows how each scraper is called from its registry row.
- Every scraper returns a data frame with columns `Title`, `Location`, `Posted_Date`, `Link`.
- HTTP goes through `perform_with_retry()` in `scrape_helpers.R`, not bare `req_perform()`.
