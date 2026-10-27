# Adopting a verified district or institution

You only get here once you've seen real current postings on the live page and know its platform (see `discovery.md`). Adoption touches several files that have to agree with each other. The state reference has the exact list for that repo, and the test suite enforces most of it.

## Steps (Automated Workflow)

1. **Probe the live URL**:
   ```bash
   Rscript scripts/probe_district.R "<url>"
   ```
   Confirms live postings exist and flags bot-gate status / platform before downloading.

2. **Capture fixture with automatic secret sanitization**:
   ```bash
   Rscript scripts/capture_fixture.R --url "<url>" --slug "<slug>"
   ```
   Saves to `tests/testthat/fixtures/<slug>_jobs.html` with all `AIza...` Google API tokens automatically redacted.

3. **Scaffold mechanical changes across 6 coupled files**:
   ```bash
   Rscript scripts/scaffold_district.R \
     --district "Full District Name" \
     --city "City" \
     --county "County Name" \
     --lat 48.1234 \
     --lon -114.5678 \
     --url "https://..." \
     --slug "<slug>"
   ```

4. **Implement parser selector & update test assertions**:
   - Write selector logic in `parse_<slug>_postings` inside `misc_district_scrapers.R`.
   - Update `tests/testthat/test-misc-district-scrapers.R` with expected titles from the fixture.

5. **Verify the batch**:
   ```bash
   Rscript scripts/verify_batch.R
   ```
   Runs all allowlist, salary setdiff, schema check, data integrity, deduplication, and unit tests, and guards against committing Claude autofix experiment files.

6. **Verify live scraper execution**:
   ```bash
   Rscript scripts/repro_scraper.R "<new registry name>"
   ```

7. **Commit per batch** of 2–4 districts.

## Sanity checks that have caught real mistakes

- The live count you report in the commit is what the scraper returned, not what you eyeballed.
- Titles look like jobs: no "Apply Now", "Employment Application", "Substitute Application" (unless that source counts subs), or nav text.
- `Location` is the district/town, not the state or a blank.
- `Link` is a per-posting URL when the site has one. If not, it's the board URL, and the posting-identity fallback handles it. Don't invent anchors.
