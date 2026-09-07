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
2. **Extract** — one HTTPS call to the **Google Gemini API** via its
   OpenAI-compatible `chat/completions` endpoint, auth'd with
   `GEMINI_API_KEY` (free tier), with a JSON schema. The model only ever
   sees the already-extracted plain text — it cannot browse or fetch.
   *(GitHub Models was the original plan — it was retired 2026-07-30.)*
3. **Guardrails** (`parse_llm_extracted_postings`, fully unit-tested):
   - every returned title must **literally appear on the page** (leading
     20 chars, case/space-insensitive) — the anti-hallucination check;
   - an implausible count (`> LLM_EXTRACT_MAX_PLAUSIBLE`, default 25) means
     the model scraped a nav menu or looped — the **whole** result is dropped;
   - known boilerplate (`Certified Job Application`, `W-4 Form`, handbooks,
     policies) is filtered, the same as the hand-written parsers do.
4. Any failure — missing key, model refusal, HTTP error, empty page,
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

`llm_extract_shadow.csv` is committed by the weekly workflow (staged only if
it exists), so the weekly diff on that file **is** the review surface.

## Running a district through the pilot

1. **Verify the page by hand** (the project's standing convention):
   confirm the real district site (address/phone, not a same-named district
   elsewhere), confirm it actually lists openings in prose, confirm a
   hand-written parser genuinely can't do it.
2. **Add a row to `llm_extract_targets.csv`:**
   ```
   District,Job_Link,County,Notes
   Grass Range Public Schools,https://grps.k12.mt.us/staff/open-positions,Fergus,"unstructured prose; standing-JD list is a decoy"
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

**Get a key:** [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
— free, no credit card.

> **Free-tier caveat:** on Gemini's free tier your prompts and the model's
> outputs *may be used to improve Google's models*. That's the price of
> "free." Non-issue for this pilot — the input is public school-district
> job pages. Pay-as-you-go opts you out if that ever matters.

**CI:** add the key as a repository secret named **`GEMINI_API_KEY`**
(repo → Settings → Secrets and variables → Actions → New repository
secret). `.github/workflows/weekly-scrape.yml` already passes it through.
If the secret is absent the scraper logs `skipped_no_key` and the rest of
the pipeline is unaffected.

**Local runs:** put it in `~/.Renviron`:

```
GEMINI_API_KEY=AIza...
```

**Changing endpoint / model / provider:** three env vars —
`LLM_EXTRACT_ENDPOINT`, `LLM_EXTRACT_MODEL`, `LLM_EXTRACT_KEY_ENV` (the name
of the env var that holds the key). Defaults:
`https://generativelanguage.googleapis.com/v1beta/openai/chat/completions`,
`gemini-3.1-flash-lite`, `GEMINI_API_KEY`. To move to OpenAI: set the
endpoint to `https://api.openai.com/v1/chat/completions`, the model to
`gpt-4o-mini`, and `LLM_EXTRACT_KEY_ENV` to `OPENAI_API_KEY` — no code
change. `llm_extract_call()` is the only function that talks to an API;
an `ellmer::chat_*()` drop-in is also a one-function change.

## Cost & limits

~1 model call per pilot district per week. Gemini's free tier is 10 req/min
and 1,500 req/day — this uses well under 1% of it. If Gemini changes or has
an outage, the affected districts log `error`/`empty` for that week and
everything else is unaffected.

*(The original plan used GitHub Models — free, `GITHUB_TOKEN`-auth'd, no
secret. GitHub retired that service on 2026-07-30, so this moved to Gemini:
one secret to add, otherwise the same shape.)*
