# linear.co.za

Static single-page site: everything (markup, CSS, JS) lives in `index.html`. No build step. `scripts/check.sh` must pass (CI runs it on PRs and before deploy). Deploy is a push to `master` (rsync to the VPS, see `DEPLOYMENT.md`). Log user-visible changes in `CHANGELOG.md`.

## Adding a side project

Projects are cards in `<ul class="sp-list">` under `#projects` in `index.html`, newest first. The grid lays out any number of cards on its own; don't touch the CSS to add one.

1. **Find out what it is.** Read the project's README and `package.json` (projects live in `~/Projects/<name>`) and look at the live site. Ask the user for the order if it isn't obvious.
2. **Screenshot it** (public projects only):
   ```sh
   scripts/shots.sh <slug> https://<sub>.linear.co.za
   ```
   This writes `img/projects/<slug>.webp` (1200×675, 16:9). Better still, ask the user for their own screenshot of the most interesting screen (they can drop it in the git-ignored `img/projects/incoming/`); convert it with `magick in.png -resize 1200x -quality 82 img/projects/<slug>.webp`. Open the image and check it: no personal data (names, emails, financial info), not a blank or loading screen. Mention anything doubtful to the user.
3. **Add the card**, copying an existing one:
   ```html
   <li class="sp">
     <a class="shot" href="https://x.linear.co.za" rel="noopener" tabindex="-1" aria-hidden="true"><img src="img/projects/x.webp" alt="" width="1200" height="675" loading="lazy" decoding="async"></a>
     <div class="hd"><h3>Name</h3><span class="meta"><a class="dom" href="https://x.linear.co.za" rel="noopener">x.linear.co.za ↗</a></span></div>
     <p>Two or three plain sentences: what it does, then one interesting engineering detail.</p>
     <span class="stk">Framework · Language · Storage · Notable libs</span>
   </li>
   ```
   - **Private project** (no public URL): replace the `<a class="shot">` with `<div class="shot locked" aria-hidden="true"><b>Name</b><i>No screenshots</i></div>`, drop the domain link and add `<span class="tag">Private</span>` in `.meta`. Never screenshot private projects yourself. If the user supplies a screenshot (demo data only), use `<div class="shot" aria-hidden="true"><img …></div>` instead of the placeholder: same frame, no link.
   - **Restricted access**: keep the link and add a tag, e.g. `<span class="tag">Invite only</span>`.
   - **Mobile-first app** (a desktop capture is a thin column): drive it in Playwright at 390×844, `deviceScaleFactor: 3`, through to its best screens (demo name like "Alex", plausible numbers), then place three phone screens side by side with rounded corners on a 16:9 canvas a shade darker than the app background. Gains (`img/projects/gains.webp`) is the example.
   - **No hosted site, public repo**: link the GitHub repo with `GitHub ↗` as the link text. For the thumbnail, a repo's own banner or social preview often beats a screenshot; crop it to 16:9 and save it as 1200×675 WebP (`magick in.png -gravity center -crop <w>x<h>+0+0 +repage -resize 1200x675 out.webp`, plus `-filter point` for pixel art).
4. **Copy rules**: no metrics, employer names or personal details; the site is brand-only. Plain, specific sentences, no marketing words.
5. Run `scripts/check.sh`, view the page at desktop and phone widths, add a `CHANGELOG.md` entry, and open a PR.
