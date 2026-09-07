# LLM-extraction shadow pilot

`llm_extract_scraper.R` reads job postings off K-12 district employment
pages that publish their openings as **free-text prose with no structural
marker** a hand-written parser can key on — the "declined: genuinely
unstructured prose" tail of the full-OPI-coverage work (`memory`:
`mt-dashboard-full-opi-coverage-goal`). Grass Range and Rapelje are the
canonical examples: a person can see the openings, but there is no heading,
list item, table, or repeatable sentence to anchor a regex on.

It is **deliberately the least-reliable tier in the project** — it puts a
non-deterministic model in the extraction step — so it runs in a
**quarantined shadow pipeline** until each district has proven itself.

## How it works (this is not Selenium)

1. **Render** — `chromote` loads the page in headless Chrome (the same path
   the Apptegy scrapers use) and takes `document.body.innerText`: the
   visible text a human would see, no HTML/JS/CSS.
2. **Extract** — one HTTPS call to **GitHub Models** (OpenAI-compatible
   `chat/completions`, auth'd with `GITHUB_TOKEN`, covered by a GitHub
   Copilot subscription) with a strict JSON schema. The model only ever
   sees the already-extracted plain text — it cannot browse or fetch.
3. **Guardrails** (`parse_llm_extracted_postings`, fully unit-tested):
   - every returned title must **literally appear on the page** (leading
     20 chars, case/space-insensitive) — the anti-hallucination check;
   - an implausible count (`> LLM_EXTRACT_MAX_PLAUSIBLE`, default 25) means
     the model scraped a nav menu or looped — the **whole** result is dropped;
   - known boilerplate (`Certified Job Application`, `W-4 Form`, handbooks,
     policies) is filtered, the same as the hand-written parsers do.
4. Any failure — missing token, model refusal, HTTP error, empty page,
   malformed JSON — yields **zero rows, never a fabricated row**.

## What "shadow" means

`fetch_all_llm_extracted_postings()` writes **only**
`Mt_Ed_Jobs/llm_extract_shadow.csv` (accumulated weekly, one dated batch per
run). Nothing it produces reaches `combinedclean.csv`, `hedata.xlsx`, the
map, the district/institution summaries, the weekly totals, or any drift /
sanity / schema check. The pilot districts are **not** in
`k12_district_registry.csv`, so they never appear on the map or in the
salary/staffing joins either.

Per-district outcomes are still written to `scrape_log.csv` as
`LLMExtract: <district>` (`ok` / `empty` / `error` / `skipped_no_key`), the
same as every other source.

## Running a district through the pilot

1. **Verify the page by hand** (the project's standing convention):
   confirm the real district site (address/phone, not a same-named district
   elsewhere), confirm it actually lists openings in prose, confirm a
   hand-written parser genuinely can't do it.
2. **Add a row to `llm_extract_targets.csv`:**
   ```
   District,Job_Link,County,Notes
   Grass Range School,https://grassrange.k12.mt.us/employment,Fergus,unstructured prose
   ```
   `District` and `Job_Link` are required; `County`/`Notes` are for your
   own reference.
3. It now runs every weekly pipeline. After each run, **diff
   `Mt_Ed_Jobs/llm_extract_shadow.csv` against the live page** — is the
   extraction complete and correct? Watch for 3–4 consecutive weeks.
4. **Promote** a district that has held up: move it into
   `k12_district_registry.csv` with real `Latitude`/`Longitude`, wire it
   into the K-12 combine chunk of `Mt_ED_Jobs.Rmd` alongside the other
   scrapers, and add a fixture-backed test. (This step is its own PR.)

## Setup

**Local runs:** put a GitHub personal access token with the **`models`**
permission (fine-grained) or `read:models` in `~/.Renviron`:

```
GITHUB_TOKEN=github_pat_...
```

Without it the scraper logs `skipped_no_key` and returns nothing — a local
pipeline run is otherwise unaffected.

**CI:** `.github/workflows/weekly-scrape.yml` grants `permissions: models:
read` and passes the built-in `GITHUB_TOKEN` — **no secret to configure**.

**If GitHub changes the endpoint/model:** set `LLM_EXTRACT_ENDPOINT` and/or
`LLM_EXTRACT_MODEL` (env vars). Defaults:
`https://models.github.ai/inference/chat/completions` and
`openai/gpt-4o-mini`. The older Azure-hosted form
(`https://models.inference.ai.azure.com/chat/completions`, model
`gpt-4o-mini`) also works.

**Swapping the model provider entirely:** replace `llm_extract_call()` —
it's the only function that talks to an API. `ellmer::chat_github()` /
`ellmer::chat_anthropic()` / `ellmer::chat_openai()` would each drop in
with a one-function change; the render step and every guardrail stay put.

## Cost & limits

~1 model call per pilot district per week. `gpt-4o-mini` at that volume is
effectively free and well within GitHub Models' rate limits (Copilot raises
them further). GitHub Models is a **preview product** — if it changes or
has an outage, the affected districts log `error`/`empty` for that week and
everything else is unaffected.
