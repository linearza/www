#!/usr/bin/env bash
# Converges the linear.co.za VPS config. Runs on every deploy, piped over SSH
# (`ssh host 'bash -s' < deploy/converge.sh`), so it is never published.
# Safe to rerun — checks existing state before making any change.
set -euo pipefail

NGINX_CONF=/etc/nginx/sites-available/linear.co.za
WWW_ROOT=${WWW_ROOT:-/var/www/linear}

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC}  $1"; }
info() { echo -e "${YELLOW}→${NC}  $1"; }
die()  { echo -e "${RED}✗${NC}  $1" >&2; exit 1; }

[ -f "$NGINX_CONF" ] || die "nginx config not found: $NGINX_CONF"
NGINX_CHANGED=false

# ── 1. Remove the retired GitHub API proxy ────────────────────────────────────
if sudo test -f /etc/systemd/system/linear-api.service; then
  sudo systemctl disable --now linear-api 2>/dev/null || true
  sudo rm -f /etc/systemd/system/linear-api.service
  sudo systemctl daemon-reload
  ok "linear-api service stopped and removed"
else
  ok "linear-api service already absent"
fi

for f in /etc/sudoers.d/linear-api /etc/linear/env; do
  if sudo test -e "$f"; then sudo rm -f "$f"; ok "Removed $f"; fi
done
sudo rmdir /etc/linear 2>/dev/null || true

API_RESULT=$(sudo python3 - "$NGINX_CONF" <<'PYEOF'
import re, sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

new = re.sub(r'\n[ \t]*location /api/ \{[^{}]*proxy_pass http://127\.0\.0\.1:47291/;[^{}]*\}[ \t]*(?=\n)', '', content)

if new != content:
    with open(path, 'w') as f:
        f.write(new)
    print("changed")
else:
    print("ok")
PYEOF
)
if [ "$API_RESULT" = "changed" ]; then
  NGINX_CHANGED=true
  ok "nginx /api/ proxy block removed"
else
  ok "nginx /api/ proxy block already absent"
fi

# Files from earlier deploys that rsync no longer manages (*.md is excluded)
if [ -e "$WWW_ROOT/DEPLOYMENT.md" ]; then
  rm -f "$WWW_ROOT/DEPLOYMENT.md"
  ok "Removed stale $WWW_ROOT/DEPLOYMENT.md"
fi

# ── 2. www → non-www redirect ─────────────────────────────────────────────────
# Fixes the server_name and appends the redirect block only when needed,
# regardless of directive order inside the server block.
WWW_RESULT=$(sudo python3 - "$NGINX_CONF" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

def server_blocks(text):
    """Yield (start, end) for each top-level server { } block."""
    i = 0
    while True:
        m = re.search(r'\bserver\s*\{', text[i:])
        if not m:
            break
        start = i + m.start()
        depth, j = 0, start
        while j < len(text):
            if text[j] == '{': depth += 1
            elif text[j] == '}':
                depth -= 1
                if depth == 0:
                    yield start, j + 1
                    i = j + 1
                    break
            j += 1
        else:
            break

parts, prev, changed = [], 0, False

for start, end in server_blocks(content):
    block = content[start:end]
    # Target the HTTPS content block: has :443, has www, is not itself a redirect
    if ':443' in block and 'www.linear.co.za' in block and 'return 301' not in block:
        new_block = re.sub(r'(\bserver_name\b[^;]*?)\s+www\.linear\.co\.za\b', r'\1', block)
        if new_block != block:
            block, changed = new_block, True
    parts += [content[prev:start], block]
    prev = end

parts.append(content[prev:])
content = ''.join(parts)

www_block = (
    "\nserver {\n"
    "    listen 443 ssl; # www-redirect\n"
    "    server_name www.linear.co.za;\n"
    "    ssl_certificate     /etc/letsencrypt/live/linear.co.za/fullchain.pem;\n"
    "    ssl_certificate_key /etc/letsencrypt/live/linear.co.za/privkey.pem;\n"
    "    include             /etc/letsencrypt/options-ssl-nginx.conf;\n"
    "    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;\n"
    "    return 301 https://linear.co.za$request_uri;\n"
    "}\n"
)

if '# www-redirect' not in content:
    content += www_block
    changed = True

if changed:
    with open(path, 'w') as f:
        f.write(content)
    print("changed")
else:
    print("ok")
PYEOF
)

if [ "$WWW_RESULT" = "changed" ]; then
  NGINX_CHANGED=true
  ok "www → non-www redirect configured"
else
  ok "www → non-www redirect already configured"
fi

# ── 3. Reload nginx once ──────────────────────────────────────────────────────
if $NGINX_CHANGED; then
  sudo nginx -t || die "nginx config test failed — check $NGINX_CONF"
  sudo systemctl reload nginx
  ok "nginx reloaded"
fi

# ── Smoke test ─────────────────────────────────────────────────────────────────
echo
info "Smoke test → https://linear.co.za/api/repos must not be served"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" --resolve linear.co.za:443:127.0.0.1 https://linear.co.za/api/repos || true)
[ "$STATUS" = "200" ] && die "/api/repos still returns HTTP 200"
ok "/api/repos returns HTTP $STATUS"

echo
ok "Converge complete"
