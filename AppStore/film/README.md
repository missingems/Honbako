# Honbako film

A 45-second film for Honbako on iPhone Duo, drawn frame by frame on one HTML canvas and encoded with ffmpeg. It sits on the app's own paper (the seeded grain from `HonbakoPaperStock`, ported in `src/paper.js`), in the app's dune palette and Apple's system font. Each section leads with the genuine app UI on the device, a plain headline and a line or two of supporting copy. The Honbako app icon is the mark on the title page and the end card. There is no frame, running head, section numbering, registration grid, dimension callout or scale bar.

- A title page.
- Four sections, each with a headline and short supporting copy:
  - 01 Library: local files, personal servers, extensions.
  - 02 Your AI: your own AI app, through Honbako's MCP server.
  - 03 Japanese: romaji and Read This Phrase.
  - 04 iPhone Duo: page turns, cover display, the Resume widget.
- An end card.

Earlier cuts are kept: the branded editorial cut (app palette, Baskerville and Courier labels, frame and callouts) in `src/brand-aligned/` and `renders/brand-aligned/`, and the monochrome cut (cool #ECEAE3 paper, vermilion seal) in `src/treatise-mono/` and `renders/treatise-mono/`. The motion stays calm on purpose, with eased camera moves and crossfades, and no handheld shake or glitch effects. The earlier product-style cut is kept in `src/product-cut/` (source and shot list) and `renders/product-cut/` (renders). To render it again, copy its `film.js` and `index.html` over `src/` (its asset paths are relative to `src/`).

| Output | File |
|---|---|
| Landscape, 1920 × 1080, 60 fps | `renders/honbako-film-1920x1080.mp4` |
| Portrait, 1080 × 1920, 60 fps | `renders/honbako-film-1080x1920.mp4` |
| Poster frames | `renders/poster-1920x1080.png`, `renders/poster-1080x1920.png` |
| Storyboard (one frame per shot) | `renders/storyboard.jpg` |
| Shot list, copy and timings | `shots.json` |

`renders/`, `review/` and `assets/` are git-ignored, because they hold manga pages and large binaries. Everything below rebuilds them.

## How it works

- `src/film.js` draws the film on a canvas from `t` alone: it reads no clock and uses no unseeded randomness. `?format=portrait` recomposes the same timeline for 1080 × 1920. Each frame takes two steps:
  - `prepareFrame(t)` returns the device's pose and, when it changed, the inner screen painted at the capture's full 2853 × 2007.
  - `renderFrame(t, layer)` composites the device layer under the text.
- The headlines, labels and timings are in `shots.json`. The type is the system font: SF Pro Display for headlines (semibold) and copy, SF Pro Text for small text, and Hiragino Sans for Japanese.
- The paper is the app's: `src/paper.js` ports `ReaderPaperTexture.tileData(strength: .light)` (seed 0xA1D02026), `SumiPaperSurface`'s alpha remap and `HonbakoPaperStock`'s base colour and 0.6 blend. Its grain matches the Swift code byte for byte. The 256 px tile is drawn one tile pixel per film pixel, as on a 2× display. Cards use the card stock (#FFFCF6).
- The device is Apple's own iPhone Duo model, `V68.usdz`, which ships inside Xcode 27.1's DeviceHub plugin (`DeviceKit.framework/…/CoreDevicePopDeviceKitExtension.devicekitplugin`). It is not copied into this repo.
  - `tools/duo-render` (Swift, RealityKit's offscreen `RealityRenderer`) loads it, poses the hinge with the model's own `book_close` clip, turns it, puts the screen images on its displays and renders each frame's device layer. The layer is supersampled 2×, in the Dark finish (set `DUO_FINISH=Light` for the other).
  - `tools/duo-render/Sources/DuoModel` is SpatialSim's `Client/DeviceModel/Sources` (commit bfc9945), copied unchanged. It holds the measured rig, screen UVs and fold clip.
  - The open device is 960 px wide in both formats (5.83 px per mm).
  - Requests can also tilt the device (`pitch`) and lift the inner screen off the body (`explode`, in mm). Section 01 uses `pitch` for a tilted view; `explode` is not used in this cut.
  - `project()` in `film.js` repeats duo-render's camera maths, so the leader from the AI's answer lands on the panel it marked on the rendered screen.
- The simulator shades a few pixels along the fold in its inner-display screenshots, though the app draws nothing there. `tools/clean-fold.py` removes that shading from the captures and clip frames, but only where it is shading and not real content such as a manga gutter.
- Every screen inside the device is a genuine capture or screen recording of Honbako in the Xcode 27.1 iPhone Duo simulator.
  - The page annotation is the real output of `honbako_annotate_page`, called through Honbako's MCP server against that exact page.
  - The AI chat text in section 02 was written for the film and is labelled “Illustrative demonstration” on screen.
- The music is `tools/music.py`, a procedural, seeded score. Single felt-piano notes play over a quiet pad in D major at 72 BPM, with one chord per feature and a low octave on the title page and under the end-card icon. It's about −16 LUFS, with no sound effects.
- `tools/render.mjs` serves the project over local HTTP and drives headless Chromium through `playwright-core`. It pipes 2,700 JPEG frames per format into ffmpeg (x264 at CRF 14, BT.709, AAC 256 kb/s, faststart).

## Website demo

`node tools/website-demo.mjs` writes a silent, looping 8-second iPhone Duo clip and its poster to `exports/website/`, for honbako.xyz. The clip is the real device model with a genuine recording of Honbako's native page turn on its screen. It's 1600 × 1200 at 60 fps, on the app's paper (#F5F0E6). The recording, `assets/source/recordings/sample-curl.mov`, uses only the original sample story 星を待つ駅 (character art by Wataobi), not Black Jack. `exports/website/brand.json` holds the shared brand notes for the website session.

`node tools/cover-demo.mjs` writes the cover-mode loop: the same model part-folded like a book (hinge 118°), turning from the reading spread to the outer display's cover and back, 7.6 s at 1600 × 1200, silent, with a poster and two stills. The inner screen is the same genuine recording. The outer screen is a reconstruction of `HonbakoCoverDisplayView`'s drawing from the sample's own cover, because the outer display stayed black under the capture fixture. `exports/website/honbako-duo-cover-mode.json` records the pose, sources and timings.

## Requirements

- Xcode 27.1 at `/Applications/Xcode 27.1.app` (or set `DEVELOPER_DIR`) on macOS 27. It supplies the model and the Swift toolchain. Build the renderer once with `npm run duo`.
- Node 20 or newer, then `npm install`. This installs `playwright-core`. Run `npx playwright install chromium` once, or set `CHROMIUM=/path/to/chrome`.
- `ffmpeg` on `PATH`.
- Python 3 with `numpy` (for the score) and Pillow (for `clean-fold.py`).
- The SF Pro Display and SF Pro Text fonts in `/Library/Fonts` (from Apple's developer fonts download), and Hiragino Sans from macOS. The earlier cuts also use Baskerville, Courier New and Hiragino Mincho.

## Rebuild

```bash
npm install
```

```bash
npm run duo
```

```bash
CAPTURE_DIR=assets/source/captures RECORDING_DIR=assets/source/recordings npm run assets
```

```bash
npm run music
```

```bash
npm run stills
```

```bash
npm run render
```

The sources used for this cut are kept, git-ignored, in `assets/source/`. `npm run stills` writes review PNGs at every cut and midpoint into `review/landscape` and `review/portrait`. For specific times, run `node tools/render.mjs --stills --at 20.6,29.8`. A full render takes a few minutes per format.

### Captures (`CAPTURE_DIR`)

Inner-display PNGs are 2853 × 2007. The outer-display PNG is 1398 × 2034. All come from `xcrun simctl io <udid> screenshot --display=…` with the device open, in light appearance, with sample data only and no personal library or account.

| File | Screen |
|---|---|
| `library-bj-inner.png` | Library with the Black Jack volumes imported from CBZ |
| `personal-server-inner.png` | Settings → Personal Server (Komga, Kavita, Suwayomi), no server added |
| `extensions-bj-inner.png` | Settings → Extensions, no repository added |
| `mcp-permissions-before-inner.png`, `…-after-inner.png` | Settings → MCP Server permissions |
| `en23-plain-inner.png`, `en23-annotated-inner.png` | English Vol. 1, pp. 23–24, before and after `honbako_annotate_page` |
| `ja7-spread-inner.png`, `ja7-romaji-on-inner.png`, `ja7-phrase-inner.png` | Japanese Vol. 7 spread: plain, with romaji, and with the Read This Phrase panel |
| `cover-en-outer.png` | Outer display in cover mode while reading Vol. 1 |

The Resume widget comes from `AppStore/review/build68/widgets-light.png`, and the icon from `AppStore/assets/AppIcon-1024.png`. The ChatGPT, Claude and Grok icons are their App Store icons from `AppStore/design-assets/provider-icons/` (provenance in its `sources.json`), copied to `assets/captures/provider-*.png`.

### Recordings (`RECORDING_DIR`)

| File | What it shows | How it's used |
|---|---|---|
| `curl.mov` | A page curl in the reader | Recorded with `simctl io recordVideo`; seconds 38.9–40.8 are used |
| `permission-toggle.mov` | The Read Reading History and Progress switch turning on | The whole recording is used |

Both are resampled to constant 60 fps frames in `assets/video/`.

## Copy and claims

- Pro features are tagged on screen with a “Honbako Pro” capsule: Japanese reading help, the Duo cover display, and the Remote MCP server that cloud AI apps need. The local MCP server, iCloud sync and the Resume widget are free (`HonbakoPlanComparisonView`), so they carry no tag.
- Section 02 shows the ChatGPT, Claude and Grok icons, the AI apps the app's own MCP client guide covers, with “Names and icons belong to their owners. Honbako isn’t affiliated with them.” The illustrative chat card keeps a neutral “Your AI” mark, so no provider appears to have written the film's text.
- The AI chat is marked “Illustrative demonstration”. The panel the AI marks in section 02 is real `honbako_annotate_page` output.
- The end card says: “Some features require Honbako Pro. Compatible AI-provider account required.” Section 02 adds that the AI-provider account is separate from Honbako.
- Section 01 says Honbako doesn't provide manga, and that sources and their content are the user's responsibility. No extension or source is named.
- Nothing in the film suggests the AI can reach Honbako while the app is closed (“Requests sync while Honbako is open”), and there are no page-turn sound effects.
- The manga is ブラックジャックによろしく by 佐藤秀峰 (Give My Regards to Black Jack, Shuho Sato). It is used under the author's free secondary-use terms at https://densho810.com/free/, and is credited on screen throughout and on the end card.
