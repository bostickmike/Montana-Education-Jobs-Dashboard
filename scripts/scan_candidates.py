#!/usr/bin/env python3
"""
scripts/scan_candidates.py
Fast candidate district scanner and triage tool.
Probes candidate school websites, follows redirects, detects bot-gates (Fastly/Cloudflare),
identifies CMS platforms (Weebly, WordPress, Edlio, Apptegy, Google Sites, CyberSchool),
locates employment subpages, and generates ready-to-run CLI commands.

Usage:
  python3 scripts/scan_candidates.py <url_or_domain> [<url_or_domain> ...]
  python3 scripts/scan_candidates.py --urls "https://example1.com" "https://example2.com"
"""

import sys
import re
import urllib.request
import urllib.error
import ssl
from urllib.parse import urljoin, urlparse

# Avoid SSL verification issues on older Mac root cert stores
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

def probe_url(url, timeout=7):
    if not url.startswith("http://") and not url.startswith("https://"):
        url = "https://" + url

    result = {
        "initial_url": url,
        "final_url": url,
        "status": None,
        "error": None,
        "bot_gate": False,
        "bot_gate_reason": None,
        "cms": "generic",
        "cms_detail": "Generic HTML",
        "job_links": [],
        "best_job_url": url,
        "slug": ""
    }

    try:
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            result["status"] = resp.status
            result["final_url"] = resp.geturl()
            raw_bytes = resp.read()
            html = raw_bytes.decode('utf-8', errors='ignore')
    except urllib.error.HTTPError as e:
        result["status"] = e.code
        result["error"] = f"HTTP {e.code}"
        try:
            html = e.read().decode('utf-8', errors='ignore')
        except Exception:
            html = ""
    except Exception as e:
        result["error"] = str(e)
        return result

    # Check for bot-gate
    if result["status"] == 403:
        result["bot_gate"] = True
        result["bot_gate_reason"] = "HTTP 403 Forbidden"
    elif re.search(r'_fs-ch-|Client Challenge|Fastly Client Challenge', html, re.IGNORECASE):
        result["bot_gate"] = True
        result["bot_gate_reason"] = "Apptegy Fastly Client Challenge JS bot-gate"
    elif ("cf-browser-verification" in html or "challenge-platform" in html) and result["status"] >= 400:
        result["bot_gate"] = True
        result["bot_gate_reason"] = "Cloudflare Challenge"

    # Fingerprint CMS
    if "wsite-" in html or "weebly.com" in html:
        result["cms"] = "weebly"
        result["cms_detail"] = "Weebly"
    elif "edliocdn" in html or "uREC_ID=" in html or "/apps/jobs/" in html or "show_job.jsp" in html:
        result["cms"] = "edlio"
        result["cms_detail"] = "Edlio"
    elif "wp-content" in html or "wp-includes" in html or re.search(r'\bdivi\b|et_pb_', html, re.IGNORECASE):
        result["cms"] = "wordpress"
        result["cms_detail"] = "WordPress / Divi"
    elif "sites.google.com" in html or "sites-layout-tile" in html:
        result["cms"] = "google_sites"
        result["cms_detail"] = "Google Sites"
    elif "finalsite" in html or "fsPageContent" in html:
        result["cms"] = "finalsite"
        result["cms_detail"] = "Finalsite"
    elif "cyberschool" in html or "cs2.chat" in html:
        result["cms"] = "cyberschool"
        result["cms_detail"] = "CyberSchool 2.0"
    elif "apptegy" in html or "5il.co" in html or "aptg.co" in html:
        result["cms"] = "apptegy"
        result["cms_detail"] = "Apptegy"

    # Search for employment links
    link_matches = re.findall(r'<a\s+[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', html, re.DOTALL | re.IGNORECASE)
    job_kw = re.compile(r'(employment|job|career|vacanc|opening|hiring|work-with-us)', re.IGNORECASE)
    seen_urls = set()
    for href, text in link_matches:
        clean_text = re.sub(r'<[^>]+>', '', text).strip()
        full_href = urljoin(result["final_url"], href)
        if job_kw.search(full_href) or job_kw.search(clean_text):
            if full_href not in seen_urls and not full_href.endswith(('.jpg', '.png', '.css', '.js')):
                seen_urls.add(full_href)
                result["job_links"].append((clean_text or "Link", full_href))

    # Pick best candidate job URL
    if result["job_links"]:
        result["best_job_url"] = result["job_links"][0][1]

    # Generate slug from host
    parsed = urlparse(result["final_url"])
    host = parsed.netloc.lower().replace("www.", "")
    slug = re.sub(r'[^a-zA-Z0-9]', '', host.split('.')[0])
    result["slug"] = slug

    return result

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print("Usage: python3 scripts/scan_candidates.py <url_or_domain> [<url_or_domain> ...]")
        sys.exit(1)

    print("=" * 80)
    print(f" SCANNING {len(args)} CANDIDATE DISTRICT(S)")
    print("=" * 80)

    results = []
    for u in args:
        print(f"Probing: {u} ...", end=" ", flush=True)
        res = probe_url(u)
        status_str = f"HTTP {res['status']}" if res['status'] else "FAILED"
        if res['bot_gate']:
            print(f"[{status_str} - BOT GATED: {res['bot_gate_reason']}]")
        elif res['error']:
            print(f"[{status_str} - {res['error']}]")
        else:
            print(f"[{status_str} - {res['cms_detail']}]")
        results.append(res)

    print("\n" + "=" * 80)
    print(" CANDIDATE ASSESSMENT SUMMARY")
    print("=" * 80)
    header = f"{'Domain/URL':<35} | {'Status':<10} | {'Bot-Gate':<10} | {'Platform':<15} | {'Job Page'}"
    print(header)
    print("-" * 80)

    for r in results:
        host = urlparse(r['final_url']).netloc or r['initial_url']
        status = f"HTTP {r['status']}" if r['status'] else "ERR"
        bg = "BLOCKED" if r['bot_gate'] else "PASS"
        job_note = "Found Subpage" if r['job_links'] else ("Same URL" if r['status'] == 200 else "None")
        print(f"{host[:35]:<35} | {status:<10} | {bg:<10} | {r['cms_detail'][:15]:<15} | {job_note}")

    # Generate suggested commands for viable candidates
    viable = [r for r in results if r['status'] == 200 and not r['bot_gate']]
    if viable:
        print("\n" + "=" * 80)
        print(" READY-TO-USE TOOL COMMANDS FOR VIABLE CANDIDATES")
        print("=" * 80)
        for r in viable:
            print(f"\n# District: {r['slug']}")
            print(f"Rscript scripts/capture_fixture.R --url \"{r['best_job_url']}\" --slug \"{r['slug']}\"")
            print(f"Rscript scripts/scaffold_district.R --district \"<District Name>\" --city \"<City>\" --county \"<County>\" --lat <lat> --lon <lon> --url \"{r['best_job_url']}\" --slug \"{r['slug']}\" --cms \"{r['cms']}\"")

if __name__ == "__main__":
    main()
