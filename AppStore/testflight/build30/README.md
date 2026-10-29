# External-sources TestFlight beta

Version **0.2.0 (30)** is uploaded, processed and **Ready to Submit** in TestFlight. The separate App Store candidate remains **0.1.0 (29)**, selected in the app draft and collection-only. The build-29 archive has not changed.

This beta explicitly enables `HONBAKO_EXTERNAL_SOURCES=YES` at compilation. Normal builds default to NO. The variant restores Source Lists, individual source installation, compatible .aix imports, native descriptors and stored-source loading. The external Info.plist registers .aix document handling; the default Info.plist does not. Both variants keep private Pro access and automatic manga import OFF. No provider lists or manga are preinstalled.

Both configurations passed focused tests: **41 executed checks** for collection-only isolation, **47 executed checks** for the external beta. Swift Testing reports44/51 total including3/4 variant-specific skipped tests. Exact skips, signed flags, source document types and toolchain proof are in `verification.json`. Connector requests use fixtures; no live third-party content rights or arbitrary source-package behavior is established by these tests.

The beta description, private review notes and approved tester-feedback address are saved and verified after reload. The feedback address is deliberately omitted from this repository. `description.txt`, `review-notes.txt` and `what-to-test.txt` contain the beta copy. Build-specific What to Test is saved and verified after reload.

An empty `Honbako Internal` group exists with automatic distribution OFF. An empty `External Sources Beta` group exists. No testers were invited and no public link was created. Adding a first external build may trigger beta review, so this preparation does not claim that build30 is approved, publicly available or attached to that group.

The owner selected our own first-party sample and explicitly asked to **keep build 30 prepared for now**. Honbako Originals version 1 is published at https://missingems.github.io/Honbako/sources/index.json. It serves an online edition of the existing original six-page tutorial; no credentials or third-party catalog are needed. Installation instructions: https://missingems.github.io/Honbako/sources/. Source code and deterministic package authoring files are in `ExternalSources/HonbakoOriginals/`.

Native tests passed for .aix import, search, chapter/page decoding, repeated requests, source persistence and rejected invalid inputs. The live integration test added the hosted list, checked that adding did not auto-install, installed the selected package, searched Bookshop and downloaded the cover and all six original PNG pages with verified hashes. Eight offline tests and one live test passed. See `original-source-verification.json` and `original-source-test-results.txt`. These tests establish this first-party package's behavior; they do not establish rights for other providers.

Build 30 remains unattached to any group, unsubmitted for beta review, with zero testers and no public link. Continue only after a new owner instruction. A prior automatic review rejection of the group wizard is retained as history in verification.json; that wizard was canceled. The App Store content-rights declaration remains unresolved and unchanged.

Reproduce the variant using the normal Honbako scheme and the existing shared DerivedData path, with explicit build overrides:

```sh
DEVELOPER_DIR="/Applications/Xcode 27.1 Public.app/Contents/Developer" xcodebuild archive -project Aidoku.xcodeproj -scheme Honbako -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/Aidoku-Codex" \
  -archivePath /path/to/final-beta.xcarchive \
  MARKETING_VERSION=0.2.0 CURRENT_PROJECT_VERSION=30 \
  HONBAKO_EXTERNAL_SOURCES=YES HONBAKO_PERSONAL_FEATURES=NO HONBAKO_IMPORT_ENGLISH_50=NO
```

Use a new build number for a subsequent upload. Retain only final archives and small verification artifacts; do not create per-experiment DerivedData folders.
