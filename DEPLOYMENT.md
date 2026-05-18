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
# Append that line to /home/deployuser/.ssh/authorized_keys on the VPS
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
sudo chown -R deployuser:deployuser /var/www/linear
```

## 7. First deploy

Push to `master` — the Actions workflow triggers automatically. Check the run in the GitHub Actions tab. On success, `https://linear.co.za` serves the hero page.

## When promoting to the full profile site

1. Point the `linearza/profile` deploy target at `/var/www/linear` (update `VPS_PATH`)
2. Update `astro.config.mjs` site to `https://linear.co.za`
3. Update `<meta name="robots">` and `robots.txt` in the profile repo to allow indexing
4. Archive or redirect this repo
