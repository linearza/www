#!/usr/bin/env bash
# Pre-deploy checks for the static site: privacy, indexing and local references.
# Optional extra denylist (one case-insensitive term per line) comes from
# $PRIVACY_DENYLIST (CI secret) or an untracked .privacy-denylist file.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
err() { echo "FAIL: $*"; fail=1; }

pages=$(ls *.html)

for f in $pages; do
  grep -q '<meta name="robots" content="noindex">' "$f" || err "$f is missing the noindex meta tag"
done
grep -qx 'Disallow: /' robots.txt || err "robots.txt must disallow all crawlers"

# No plaintext email addresses or phone numbers in published files
grep -nE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}' $pages robots.txt && err "plaintext email address found"
grep -nE '(\+27|\b0)[0-9 ]{9,12}\b' $pages && err "phone number found"

# Local src/href targets must exist
for f in $pages; do
  for ref in $(grep -oE '(src|href)="[^"#:]+"' "$f" | sed -E 's/^(src|href)="//; s/"$//; s/[?].*$//'); do
    [ -e "$ref" ] || err "$f references missing file: $ref"
  done
done

deny="${PRIVACY_DENYLIST:-}"
[ -z "$deny" ] && [ -f .privacy-denylist ] && deny=$(cat .privacy-denylist)
if [ -n "$deny" ]; then
  while IFS= read -r term; do
    [ -z "$term" ] && continue
    grep -qiF -- "$term" $pages && err "denylisted term found (line $(grep -niF -- "$term" $pages | head -1 | cut -d: -f1-2 | sed -E "s/:[^:]*$//"))"
  done <<< "$deny"
else
  echo "note: no privacy denylist configured; skipped name checks"
fi

[ "$fail" -eq 0 ] && echo "All checks passed."
exit "$fail"
