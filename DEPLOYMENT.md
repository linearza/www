# Deployment Guide — linear.co.za

## 1. Create the GitHub repo

```bash
gh repo create linearza/www --public --source=. --remote=origin --push
```

## 2. VPS — nginx config

The SSL cert must exist before nginx can load an HTTPS block. Bootstrap in two steps.

**Step 2a — HTTP-only config to allow Certbot's ACME challenge:**

Create `/etc/nginx/sites-available/linear.co.za`:

```nginx
server {
    listen 80;
    server_name linear.co.za www.linear.co.za;
    root /var/www/linear;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

Enable and reload:

```bash
sudo mkdir -p /var/www/linear
sudo ln -s /etc/nginx/sites-available/linear.co.za /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

## 3. SSL certificate

Add the DNS A record in Cloudflare first (grey cloud, DNS-only), then:

```bash
sudo certbot --nginx -d linear.co.za -d www.linear.co.za
```

Certbot handles the ACME challenge over HTTP, issues the cert, and rewrites the nginx config to add the HTTPS block and HTTP→HTTPS redirect automatically. Reload nginx after:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

The resulting config will look roughly like:

```nginx
server {
    listen 80;
    server_name linear.co.za www.linear.co.za;
    return 301 https://linear.co.za$request_uri;
}

server {
    listen 443 ssl;
    server_name linear.co.za www.linear.co.za;

    ssl_certificate     /etc/letsencrypt/live/linear.co.za/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/linear.co.za/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    root /var/www/linear;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

## 4. SSH deploy key

Generate a dedicated key pair for this repo:

```bash
ssh-keygen -t ed25519 -C "deploy@linear.co.za-www" -f ~/.ssh/www_deploy_key -N ""
```

**Add the public key to the VPS** (as the deploy user, or via sudo):

```bash
cat ~/.ssh/www_deploy_key.pub
# Append that line to /home/ubuntu/.ssh/authorized_keys on the VPS
```

## 5. GitHub Actions secrets

In the `linearza/www` repo settings → Secrets and variables → Actions, add:

| Secret | Value |
|--------|-------|
| `WWW_DEPLOY_KEY` | Contents of `~/.ssh/www_deploy_key` (private key) |
| `VPS_HOST` | Your VPS IP or hostname |
| `VPS_USER` | Deploy user on the VPS |
| `WWW_PATH` | `/var/www/linear` |

## 6. Deploy user directory permissions

Ensure `/var/www/linear` is writable by the deploy user:

```bash
sudo chown -R ubuntu:ubuntu /var/www/linear
```

## 7. First deploy

Push to `master` — the Actions workflow triggers automatically. Check the run in the GitHub Actions tab. On success, `https://linear.co.za` serves the hero page.

## 8. GitHub API proxy

The site fetches `/api/repos` and `/api/stars` via a small Node.js proxy that attaches a GitHub token server-side. This keeps the token out of the browser and enables private repo access.

### 8a — Install Node.js (if not already present)

```bash
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### 8b — Create the token env file

Create `/etc/linear/env` (readable only by root and the deploy user):

```bash
sudo mkdir -p /etc/linear
sudo sh -c 'echo "GITHUB_TOKEN=ghp_your_token_here" > /etc/linear/env'
sudo chmod 640 /etc/linear/env
sudo chown root:ubuntu /etc/linear/env
```

Generate the token at GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens. Grant it **read-only** access to your repositories (Contents + Metadata).

### 8c — Install and enable the systemd service

```bash
sudo cp /var/www/linear/api/linear-api.service /etc/systemd/system/linear-api.service
# Edit User= in the service file if your deploy user differs from "ubuntu"
sudo systemctl daemon-reload
sudo systemctl enable linear-api
sudo systemctl start linear-api
sudo systemctl status linear-api
```

### 8d — Allow the deploy user to restart the service without a password

```bash
sudo visudo
```

Add this line:

```
ubuntu ALL=(ALL) NOPASSWD: /bin/systemctl restart linear-api
```

### 8e — Add the nginx proxy location

In the HTTPS server block (inside `/etc/nginx/sites-available/linear.co.za`), add before the closing `}`:

```nginx
location /api/ {
    proxy_pass http://127.0.0.1:47291/;
    proxy_set_header Host $host;
    proxy_read_timeout 10s;
}
```

Then reload nginx:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## Local development

No build step — open `index.html` directly from the repo root.

### Without the API proxy

The fetch calls to `/api/repos` and `/api/stars` will 404. The page degrades gracefully (shows "Projects not available." and "Stars not available."). This is fine for HTML/CSS work.

### With the API proxy

**Step 1 — Create a local env file:**

```bash
mkdir -p api
echo "GITHUB_TOKEN=ghp_your_token_here" > api/.env.local
```

**Step 2 — Start the proxy:**

```bash
PORT=47291 GITHUB_TOKEN=$(cat api/.env.local | cut -d= -f2) node api/server.js
```

Or export from your shell profile:

```bash
export GITHUB_TOKEN=ghp_your_token_here
node api/server.js
```

**Step 3 — Serve the static files** (browsers block fetch to a different port from `file://`):

```bash
npx serve . -l 3000
# or: python3 -m http.server 3000
```

Then open `http://localhost:3000`.

> **Note:** The proxy binds to `127.0.0.1:47291`. nginx on the VPS rewrites `/api/` → `http://127.0.0.1:47291/`. Locally you either proxy through the same path (e.g. configure nginx/caddy) or temporarily patch the fetch URLs to hit port 47291 directly. The `npx serve` approach does not auto-proxy — the easiest local workaround is a one-liner with `http-server` + a reverse proxy, or just use the VPS to test API behaviour.

---

## When promoting to the full profile site

1. Point the `linearza/profile` deploy target at `/var/www/linear` (update `VPS_PATH`)
2. Update `astro.config.mjs` site to `https://linear.co.za`
3. Update `<meta name="robots">` and `robots.txt` in the profile repo to allow indexing
4. Archive or redirect this repo
