# Changelog

## 2.0.2 — 2026-10-02

- New favicon matching the wordmark: heavy "L" with the green square full stop on paper, with a dark-mode variant. The link is cache-busted (`?v=2`).
- `scripts/check.sh` ignores query strings when checking local references.

## 2.0.1 — 2026-10-02

- Removed the GitHub API proxy (`api/`) and `dev.js`. It served repository listings, including private ones, at `/api/repos`.
- Replaced `api/setup.sh` with `deploy/converge.sh`, which the deploy copies to the VPS, runs and deletes. It tears down the proxy service, its sudoers entry, token file and nginx location, removes the stale `DEPLOYMENT.md` from the web root, keeps the www redirect, and fails the deploy if `/api/repos` still returns 200.

## 2.0.0 — 2026-10-02

- Replaced the homepage with the "Ledger" design: sticky wordmark over animated contour lines, with capabilities, experience, founded products and contact in a scrolling column.
- Content matches the current CV without personal details: brand only, employers described by sector, no metrics.
- Removed the theme picker, GitHub repo and star feeds, `style.css` and `canvas.js`. The page no longer calls `/api`.
- New favicon to match the design.
- Added `scripts/check.sh` (noindex, robots, no plaintext email or phone numbers, local references, optional privacy denylist) and run it in CI on pull requests and before deploy.
