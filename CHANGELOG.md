# Changelog

## 2.0.0 — 2026-10-02

- Replaced the homepage with the "Ledger" design: sticky wordmark over animated contour lines, with capabilities, experience, founded products and contact in a scrolling column.
- Content matches the current CV without personal details: brand only, employers described by sector, no metrics.
- Removed the theme picker, GitHub repo and star feeds, `style.css` and `canvas.js`. The page no longer calls `/api`.
- New favicon to match the design.
- Added `scripts/check.sh` (noindex, robots, no plaintext email or phone numbers, local references, optional privacy denylist) and run it in CI on pull requests and before deploy.
