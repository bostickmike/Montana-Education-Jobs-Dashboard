#!/bin/zsh
# Daily job on Mike's Mac (launchd: edu.montana.jobsdash.mac-sources.plist).
# Fetches the Mac-run sources and pushes them to the `mac-sources` branch.
# Never touches main (a push to main redeploys the dashboard).
set -uo pipefail
REPO="${JOBS_DASH_MT_REPO:-$HOME/repos/Jobs_Dash_repos/Montana-Education-Jobs-Dashboard}"
OUT="${JOBS_DASH_MAC_SOURCES_DIR:-$HOME/.jobs-dash-mac-sources/mt}"
echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) mac-sources run"
git -C "$OUT" pull -q --rebase origin mac-sources || echo "pull failed; continuing with the local copy"
cd "$REPO" || exit 1
Rscript scripts/mac_sources/fetch_mac_sources.R --out "$OUT"
fetch_status=$?
git -C "$OUT" add -A
if git -C "$OUT" diff --cached --quiet; then
  echo "nothing to commit"
else
  git -C "$OUT" commit -q -m "Mac sources $(date -u +%Y-%m-%dT%H:%MZ)" && \
    git -C "$OUT" push -q origin mac-sources && echo "pushed"
fi
exit $fetch_status
