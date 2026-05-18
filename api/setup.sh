#!/usr/bin/env bash
# VPS setup for the linear.co.za API proxy.
# Safe to rerun — checks existing state before making any change.
set -euo pipefail

NGINX_CONF=/etc/nginx/sites-available/linear.co.za
SERVICE_SRC="$(cd "$(dirname "$0")" && pwd)/linear-api.service"
SERVICE_DEST=/etc/systemd/system/linear-api.service
ENV_FILE=/etc/linear/env
SUDOERS_FILE=/etc/sudoers.d/linear-api

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC}  $1"; }
info() { echo -e "${YELLOW}→${NC}  $1"; }
die()  { echo -e "${RED}✗${NC}  $1" >&2; exit 1; }

# ── 1. GITHUB_TOKEN ────────────────────────────────────────────────────────────
if sudo test -f "$ENV_FILE" && sudo grep -q "^GITHUB_TOKEN=." "$ENV_FILE"; then
  ok "GITHUB_TOKEN already set in $ENV_FILE"
else
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    read -rsp "GITHUB_TOKEN (input hidden): " GITHUB_TOKEN
    echo
  fi
  [ -n "$GITHUB_TOKEN" ] || die "GITHUB_TOKEN is required"
  sudo mkdir -p /etc/linear
  printf 'GITHUB_TOKEN=%s\n' "$GITHUB_TOKEN" | sudo tee "$ENV_FILE" > /dev/null
  sudo chmod 640 "$ENV_FILE"
  sudo chown root:ubuntu "$ENV_FILE"
  ok "Written $ENV_FILE"
fi

# ── 2. Node.js ─────────────────────────────────────────────────────────────────
if command -v node &>/dev/null; then
  ok "Node.js $(node -v) already installed"
else
  info "Installing Node.js LTS..."
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - 2>&1 | tail -3
  sudo apt-get install -y nodejs 2>&1 | tail -3
  ok "Node.js $(node -v) installed"
fi

# ── 3. systemd service ─────────────────────────────────────────────────────────
[ -f "$SERVICE_SRC" ] || die "Service file not found: $SERVICE_SRC"

NEEDS_DAEMON_RELOAD=false
if [ -f "$SERVICE_DEST" ] && sudo diff -q "$SERVICE_SRC" "$SERVICE_DEST" &>/dev/null; then
  ok "Service file already up to date"
else
  sudo cp "$SERVICE_SRC" "$SERVICE_DEST"
  NEEDS_DAEMON_RELOAD=true
  ok "Service file installed/updated"
fi

$NEEDS_DAEMON_RELOAD && sudo systemctl daemon-reload

if sudo systemctl is-enabled --quiet linear-api; then
  ok "linear-api already enabled"
else
  sudo systemctl enable linear-api
  ok "linear-api enabled"
fi

if sudo systemctl is-active --quiet linear-api; then
  if $NEEDS_DAEMON_RELOAD; then
    sudo systemctl restart linear-api
    ok "linear-api restarted (service file changed)"
  else
    ok "linear-api already running"
  fi
else
  sudo systemctl start linear-api
  ok "linear-api started"
fi

# Verify it came up
sleep 1
sudo systemctl is-active --quiet linear-api || die "linear-api failed to start — check: journalctl -u linear-api -n 20"

# ── 4. nginx /api/ proxy ───────────────────────────────────────────────────────
[ -f "$NGINX_CONF" ] || die "nginx config not found: $NGINX_CONF"

if grep -q "proxy_pass http://127.0.0.1:47291" "$NGINX_CONF"; then
  ok "nginx /api/ proxy already configured"
else
  info "Adding /api/ location block to nginx config..."
  # Insert the location block before the final closing } of the file
  sudo python3 - "$NGINX_CONF" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

block = (
    "\n"
    "    location /api/ {\n"
    "        proxy_pass http://127.0.0.1:47291/;\n"
    "        proxy_set_header Host $host;\n"
    "        proxy_read_timeout 10s;\n"
    "    }\n"
)

# Insert before the last closing brace (end of the HTTPS server block)
idx = content.rfind("\n}")
if idx == -1:
    sys.exit("ERROR: could not find closing } in nginx config")

with open(path, "w") as f:
    f.write(content[:idx] + block + content[idx:])
PYEOF

  sudo nginx -t || die "nginx config test failed — check $NGINX_CONF"
  sudo systemctl reload nginx
  ok "nginx /api/ proxy block added and nginx reloaded"
fi

# ── 5. www → non-www redirect ─────────────────────────────────────────────────
# The script is idempotent: it fixes the server_name and appends the redirect
# block only when needed, regardless of directive order inside the server block.
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
  sudo nginx -t || die "nginx config test failed — check $NGINX_CONF"
  sudo systemctl reload nginx
  ok "www → non-www redirect configured and nginx reloaded"
else
  ok "www → non-www redirect already configured"
fi

# ── 6. sudoers (passwordless service restart for deploy) ──────────────────────
SUDOERS_LINE="ubuntu ALL=(ALL) NOPASSWD: /bin/systemctl restart linear-api"

if [ -f "$SUDOERS_FILE" ] && sudo grep -qF "$SUDOERS_LINE" "$SUDOERS_FILE"; then
  ok "sudoers entry already present"
else
  echo "$SUDOERS_LINE" | sudo tee "$SUDOERS_FILE" > /dev/null
  sudo chmod 440 "$SUDOERS_FILE"
  # Validate before leaving a broken sudoers
  sudo visudo -cf "$SUDOERS_FILE" || { sudo rm -f "$SUDOERS_FILE"; die "sudoers syntax error — file removed"; }
  ok "sudoers entry added"
fi

# ── Smoke test ─────────────────────────────────────────────────────────────────
echo
info "Smoke test → curl http://127.0.0.1:47291/repos"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:47291/repos)
if [ "$STATUS" = "200" ]; then
  ok "API responding (HTTP 200)"
else
  die "API returned HTTP $STATUS — check: journalctl -u linear-api -n 20"
fi

echo
ok "Setup complete — https://linear.co.za/api/repos is live"
