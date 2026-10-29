# Honbako Originals external source

A first-party sample for the optional external-source beta (0.2.0 build 30). Source ID `en.honbako-originals`, version 1. No app rebuild is required.

- Source list: https://missingems.github.io/Honbako/sources/index.json
- Installation: https://missingems.github.io/Honbako/sources/
- Comic: https://missingems.github.io/Honbako/originals/bookshop/

The single story is an online edition of Honbako’s existing original six-page tutorial. The PNG files are exported unchanged by `HonbakoOriginalExternalSourceTests.testExportOriginalComicAssets` using the app’s native renderer. The public `assets.json` records the content origin and hashes. This source supplies no third-party catalogs, credentials, tracking, or unrestricted network capability.

## Build

Install the pinned authoring dependency with `npm install --ignore-scripts --no-audit --no-fund` in this directory, then run `python3 build.py`. Alternatively set `HONBAKO_WABT_MODULE` to an existing official `wabt` 1.0.39 package directory. Python 3 and Node.js are required; no compiler toolchain is added to the app. The resulting `.aix` archive is deterministic, contains only `Payload/source.json`, `Payload/main.wasm`, and `Payload/icon.png`, and is copied to `site/sources/packages/` and the test fixtures directory.

`build.py` serializes fixed metadata with the reader engine’s Postcard format and emits readable `source.wat`. `compile.mjs` uses the official WABT package to validate and compile it. The module imports only the engine’s input-buffer length/read functions; it returns static first-party HTTPS image URLs. Search accepts bounded case-insensitive ASCII substrings, with an empty result for later pages. Unknown identifiers and oversized requests fail. No JavaScript, cookie, file, or HTTP runtime imports are present.

`manifest.json` records the package and module hashes. The app’s native integration tests exercise package import, search, chapter/page decoding, repeated requests, persistence, and invalid inputs. A separate hosted integration test checks source-list installation and the live image hashes.

This sample does not change the collection-only App Store build or attest to rights for other providers. Build 30 remains prepared and unsubmitted until the owner asks to continue.
