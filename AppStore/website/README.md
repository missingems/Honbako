# honbako.xyz (draft)

A static, single-page site in the spirit of aidoku.app: icon, name, one line, two buttons, then the app itself. No build step; serve this folder as is.

- `index.html`, `styles.css`: the page. System font, the app's paper (#F5F0E6) and dune accent (#806344).
- `assets/paper.png`: the app's own paper grain, written from `AppStore/film/src/paper.js` (a byte-exact port of `ReaderPaperTexture` / `SumiPaperSurface` / `HonbakoPaperStock`).
- `assets/honbako-duo-page-turn.*`, `assets/honbako-duo-cover-mode.*` and the two posters: copied from `AppStore/film/exports/website/` (provenance there). They are 2D renders; no 3D device model is shipped.
- `assets/duo-ai-recap.webp`, `ai-recap-detail.webp`: a **composed** Split View, since the simulator's Split View can't be driven for capture. The left half (Honbako) is a genuine inner-display capture (2853 × 2007) of the reader on page 3 of the sample story 星を待つ駅 (character art by Wataobi), from the Honbako Capture duo simulator with `--sumi-grid-check --sumi-grid-reading-mode=rtl --honbako-licensed-marketing-sample`, cut at the fold. The right half is an illustration: a generic "Your AI" chat (no provider's design), written in HTML and rendered at 3× in headless Chrome, with a 14 px black divider on the fold. The capture's status bar sits under the chat half, so the image has none. The recap describes pages 1–2 only, from the dialogue on those pages, so the page labels it "Example conversation". Rendered on Apple's Duo model with `AppStore/film/tools/duo-stills.mjs` (Dark finish, nothing added). The detail is a crop of the chat half, shown only at phone widths.
- `assets/duo-library.webp`, `duo-coaching.webp`, `duo-japanese.webp`: genuine inner-display captures (2853 × 2007) from the Honbako Capture duo simulator (E10C41ED…), built from the current source with `--sumi-grid-check --honbako-licensed-marketing-sample` (plus `--honbako-page-access-check` or `--honbako-japanese-guide-check`), rendered on Apple's Duo model with `AppStore/film/tools/duo-stills.mjs`. `duo-coaching.webp` is no longer used by the page; it was replaced by the recap split above.
- `assets/japanese-detail.webp`: an unscaled crop of the same page with romaji on, from the build 77 iPhone capture (`AppStore/screenshot-captures/build77-features/en-US/iphone/japanese.png`); the Duo simulator's Romaji on Page switch didn't respond during capture.
- `assets/provider-*.png`: the ChatGPT, Claude and Grok App Store icons from `AppStore/design-assets/provider-icons/` (provenance in its `sources.json`), at 96 px.
- `assets/icon.png`, `favicon.png`, `apple-touch-icon.png`: resized from `AppStore/assets/AppIcon-1024.png`.

Only Honbako's original sample stories appear (character art by Wataobi). Help and Privacy link to the existing pages at missingems.github.io/Honbako.

Preview locally:

```bash
python3 -m http.server 4317 --bind 127.0.0.1 --directory AppStore/website
```
