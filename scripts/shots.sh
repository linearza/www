#!/usr/bin/env bash
# Capture side-project thumbnails into img/projects/<name>.webp.
# Usage: scripts/shots.sh <name> <url> [<name> <url> ...]
#   e.g. scripts/shots.sh sitter https://sitter.linear.co.za
# Needs Node, Google Chrome and cwebp (brew install webp).
set -euo pipefail
cd "$(dirname "$0")/.."

out=img/projects
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

[ $(( $# % 2 )) -eq 0 ] && [ $# -gt 0 ] || { echo "usage: $0 <name> <url> [...]"; exit 1; }

while [ $# -gt 0 ]; do
  name=$1 url=$2; shift 2
  # 1280x720 viewport, given 4s to settle (fonts, client-side rendering, WebGL)
  npx -y playwright@1.56.1 screenshot --channel chrome --viewport-size=1280,720 \
    --wait-for-timeout=4000 "$url" "$tmp/$name.png" >/dev/null
  cwebp -quiet -q 82 -resize 1200 675 "$tmp/$name.png" -o "$out/$name.webp"
  echo "$out/$name.webp"
done
