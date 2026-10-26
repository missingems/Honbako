# Aidoku

A free and open source manga reading application for iOS, iPadOS, and macOS.

<p>
	<img src="https://raw.githubusercontent.com/Aidoku/Website/refs/heads/main/static/images/library-noframe.png" width="25%" alt="Library">
	<img src="https://raw.githubusercontent.com/Aidoku/Website/refs/heads/main/static/images/source-noframe.png" width="25%" alt="Source">
	<img src="https://raw.githubusercontent.com/Aidoku/Website/refs/heads/main/static/images/reader-noframe.png" width="25%" alt="Reader">
</p>

## Features

- No ads
- Local file reading (CBZ)
- Built-in reading service providers (Komga, Kavita, Suwayomi)
- WASM external source system
- Downloads
- Tracker integration (AniList, MyAnimeList, etc.)
- OCR dictionary lookup

## Installation

For detailed installation instructions, check out [the website](https://aidoku.app).

### TestFlight

To join the TestFlight, you will need to join the [Aidoku Discord](https://discord.gg/kh2PYT8V8d).

### AltStore

We have an AltStore repo that contains the latest releases ipa. You can copy the [direct source URL](https://raw.githubusercontent.com/Aidoku/Aidoku/altstore/apps.json) and paste it into AltStore. Note that AltStore PAL is not supported.

### Manual Installation

The latest ipa file will always be available from the [releases page](https://github.com/Aidoku/Aidoku/releases). Nightly ipas are also built on each commit, but it's not recommended to use these since they may have in-progress changes that could cause issues when updating later.

## Contributing

### Sumi: a separate manga app

The shared **Sumi** scheme builds a separate iOS 26+ app alongside Aidoku, using Aidoku's source engine, library database, and reader. Build it with Xcode 27.1 or later. Its app identifier ends in `.Sumi`, its private iCloud container is `iCloud.<Sumi app identifier>`, and its library lives in its own sandbox. Select a signing team and enable automatic provisioning for the new app and iCloud container.

Sumi starts with a flat cover grid inside the native Library and Search tab bar’s adaptive safe area. The library and search use a plain white background. One cached white paper stock covers manga pages and their scrub previews; its transparent grain preserves solid black ink and carries through the 3D opening and page turns. Cover corners use the system concentric shape without a simulated binding or border. Search opens with its keyboard ready. The library fills with 100 distinct real manga, shuffles once, and caches that catalog order across launches. System typography and adaptive bars follow the available display space; books open directly without a description screen.

Tapping a cover lifts it above the dimmed grid without an animated cover shadow. The cover dims with a normal native large spinner directly on it, and both hover together until the reading page is ready. The cover brightens, then a temporary RealityKit stage opens the book to the left through nested spine and cover hinges. A measured orthographic camera follows the same critically damped motion as Mooligan’s binder; real current page textures stay opaque through the full swing and hand off to the native reader at the rendered endpoint with matching geometry. A leading-edge swipe reverses that path, predicts completion from travel and velocity, or springs back open without changing the selected page. Dismissal captures the current spread and tracks the cover’s current library position. Rendering stops after handoff; Reduce Motion uses a short native transition. Returning titles open their exact last-read chapter and page; completed chapters reopen at page 1. Unread titles start at their oldest readable chapter without a synthetic index. Missing bookmarks report an error instead of substituting another chapter. Canceling preparation cannot save progress or complete an unseen chapter.

MangaDex, Weeb Central, MANGA Plus, and WEBTOON source packages are bundled with their manifest, checksums, and license under `Aidoku/Features/Bookshelf/Resources/SumiSources`. First launch installs them locally without a source-selection screen. Search combines their results, ranks exact title matches first, and identifies each edition. Actual catalog and chapter availability still depends on the provider.

iCloud sync is enabled before the database opens and mirrors the library and reading progress. Sumi defaults to **Fit to Page in landscape** and **Fill Page in portrait**, with vertical scrolling for tall pages. Native Close, Chapters, and Fit controls animate in after opening; tapping the reader toggles them. A compact 48-point glass carousel uses native relative scrolling, coasting, and snapping beneath a fixed center lens. Its source artwork magnifies under a clear glare and rim, with curved ends and parting neighbors. Each slot contains the real current source page or two-page spread, with the page position above it. A preview lifts immediately during scrubbing, follows and leans with the finger, then returns to the lens after every destination leaf is ready; previews swap as complete spreads and the reader reveals its prepared destination atomically, without full-screen preview enlargement or crossfades. Canceled or interrupted work cannot leave a stale overlay. Preview groups follow the actual reader plan, including isolated wide images and the final odd page. Preview cache identity includes the canonical page position, including sources that return a default zero index for every page. Scrubbing previews actual pages; release commits the selected page and cancel restores the bookmark. Paper extends to every display edge, with white paper behind fitted artwork. Tools retain safe margins and avoid active fold and camera regions without resizing the artwork. Only landscape horizontal reading uses the custom interactive curl: one leaf bends through a cylinder mesh, including its curved binding edge, with front and back artwork on the same surface. Forward turns travel from left to right while preserving each source’s canonical page order. Short purposeful drags and flicks finish turns; small nudges and deliberate reverse drags cancel. Portrait and Reduce Motion use sliding page changes. Folding preserves the exact selected page, including the second page of a spread.

The Sumi scheme includes focused geometry, discovery, bookmark, page-loading, safe-margin, fit, scrubber, fold, and curl lifecycle tests. Current grid UI tests use `--sumi-grid-check` generated content with in-memory progress; production never uses those fixtures. Run landscape cases with Duo open and portrait cases with it closed. Touch tests cover loading, direct reading, chapter selection, scrubbing, and reopening the saved page. Earlier pile/detail prototypes remain available only through explicit debug launch modes.

### This checkout: iPhone Duo

Branch `codex/iphone-duo-ready` starts from `v0.9-4` (`ceee58b2`). Build with **Xcode 27.1 or later** so the app uses the iOS 27.1 SDK and system vertical bars. The iOS 15 deployment target is preserved; Duo reserved-region handling is availability guarded. The nightly runner must have Xcode 27.1 installed.

Simulator tests need normal ad hoc signing so the CloudKit account check receives its required entitlements. For Duo UI tests, capture and target the active app window: the main screen or application frame can still refer to the inactive outer display after opening the device.

This checkout fixes live resizing in the reader, text pagination, source grids and carousels, search dismissal, modal sizing, and incognito overlays. The reader's floating controls and dictionary popups avoid active fold/camera reserved regions.

The paged manga reader has a Page Sizing menu in its navigation bar and reader settings. **Fit Screen** shows the whole page or spread and resets manual zoom; **Fill Width** matches the page or spread to the available width, locks sideways panning and manual zoom, and allows vertical scrolling with native edge bounce for tall pages. Artwork uses a full-bounds viewport underneath the controls in both sizing modes. Showing or hiding controls preserves the image scale and reading position, including manual zoom. Fill Width extends through the home-indicator area. The choice is remembered and adapts when the reading area changes size.

In a landscape reading area, horizontal double-page manga uses independent leaves that curl around the center binding in the selected reading direction. The binding has curved paper edges and stays visible at the same seam throughout a turn. Its vector geometry is cached until the viewport changes. Each leaf keeps its own zoom or Fill Width vertical scroll position. Wide panels retain one continuous original image across two clipped halves and count as one page; blank cover and end leaves do not count toward progress. Explicit single-page layouts keep an edge curl. Portrait and narrow Split View areas keep scrolling transitions, while Reduce Motion replaces the curl with scrolling around the same live pages. Canceled flips do not advance progress.

Fill Width automatically skips verified white top and bottom page borders, retaining a small safety gutter around the artwork. Detection runs off the main thread and preserves faint marks, colored paper, large deliberate margins, original bitmaps, and text-recognition coordinates. Animated and rotated images retain all rows. Short artwork still retains the space required by its aspect ratio; trimming does not introduce extra zoom.

The app opts into ProMotion. On iOS 18 and later, native page turns request the attached display's highest frame rate up to 120 Hz through a passive `UIUpdateLink`; the request ends when the turn ends or the reader disappears. There are no continuous redraws or per-frame callbacks. Actual presentation cadence remains subject to the display and system scheduling, and must be measured on a physical device.

**Paper Texture**, available in the reader and global reader settings, adds neutral white-paper grain and visible fine fibers to manga pages and webtoons. Choose Light, Medium, or Strong intensity; existing enabled installations use Strong for more visible surface grain. Its point size stays consistent across display densities. It preserves the original image and OCR data and leaves text chapters unchanged.

Enable **New Chapter Notifications** in Library settings to receive alerts after successful library updates. Only new, readable chapters matching each title's language and scanlator filters qualify; the first chapter fetch establishes a baseline. Pending alerts survive restarts and retry delivery without duplicate chapter alerts. Daily background checks are enabled by default, cover all saved titles unless skip rules are set, and depend on iOS scheduling and the selected Wi-Fi rule.

**iCloud Sync** in Settings mirrors the library, categories, and reading progress through this build's private CloudKit container. Downloads remain local. Changing the switch requires restarting Aidoku; the page reports account availability, errors, and the last successful upload and download. Use the same Apple Account, app build, and source extensions on each device. This container is separate from the official Aidoku app's library. Imported duplicates preserve reading sessions and the most recent reading action, including deliberate rereads.

On first launch with network access, it adds the maintained [Aidoku community source catalog](https://github.com/Aidoku-Community/sources), installs MANGA Plus, MangaDex, WEBTOON, and Weeb Central, and pins them in Browse. Failed installs retry on a later launch; removing a successfully installed starter source keeps it removed. Existing installations also receive newly added starter sources once.

Before using a device build, select your signing team in Xcode. Validate both displays, open/book/closed poses, both rotations, Split View on either side, reader page continuity, and source search. Simulator checks do not replace testing on a physical Duo.

This local checkout has signing overrides in `Aidoku/LocalSigning.xcconfig` (ignored by Git), so future Xcode builds use the configured development team and `dev.jun.Aidoku` app identifier. The device build retains the app's original entitlements.

Known limitation: the optional split-wide-image mode caches already processed page halves, so those halves keep their original resolution after the window grows. Regular pages request a larger image variant as needed.

Aidoku is still in a beta phase, and there are a lot of planned features and fixes. If you're interested in contributing, I'd first recommend checking with me on [Discord](https://discord.gg/kh2PYT8V8d) in the app development channel.

This repo (excluding translations) is licensed under [GPLv3](https://github.com/Aidoku/Aidoku/blob/main/LICENSE), but contributors must also sign the project [CLA](https://gist.github.com/Skittyblock/893952ff23f0df0e5cd02abbaddc2be9). Essentially, this just gives me (Skittyblock) the ability to distribute Aidoku via TestFlight/the App Store, but others must obtain an exception from me in order to do the same. Otherwise, GPLv3 applies and this code can be used freely as long as the modified source code is made available.

### Translations

Interested in translating Aidoku? We use [Weblate](https://hosted.weblate.org/engage/aidoku/) to crowdsource translations, so anyone can create an account and contribute!

Translations are licensed separately from the app code, under [Apache 2.0](https://spdx.org/licenses/Apache-2.0.html).
