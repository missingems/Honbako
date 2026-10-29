# Honbako App Store submission status

Updated 28 October 2026. Version 0.1.0 **build 28** was archived and uploaded successfully with the genuine public Xcode 27.1 toolchain, build **27A9275**, and `HONBAKO_PERSONAL_FEATURES=NO` / `HONBAKO_IMPORT_ENGLISH_50=NO`. Strict signature verification passed. The user reauthenticated App Store Connect. Apple offered build 28 in the eligible build list, and it is now **selected and saved** in the app draft. The updated **3,114-character review notes are saved**. Actual Add for Review validation for build 28 now reports **only the missing content-rights declaration**; the beta-toolchain and privacy-policy URL errors are resolved. The subscription and subscription group are staged in the existing draft, which has two ready items. The app version could not be added because content rights remain missing; final submission has not occurred.

Build 27's beta-toolchain rejection is historical; build 28 supersedes it as the current candidate. Build 26 remains the separate private Pro-unlocked beta. Content-rights, engine distribution/licensing and export-compliance owner confirmations remain unresolved.

The app is free in 175 storefronts, with future expansion manual. The 18+ override is saved. The owner-approved **Data Not Collected** privacy declaration is published, and privacy-policy URLs are saved in all four locales. [Support](https://missingems.github.io/Honbako/support/) and [Privacy Policy](https://missingems.github.io/Honbako/privacy/) are published; public support and privacy questions use [GitHub issues](https://github.com/missingems/Honbako/issues). Apple's review contact is saved privately in App Store Connect and omitted from this repository.

## Files and local checks

- `assets/AppIcon-1024.png`: the 1024 × 1024 opaque app icon.
- `metadata/en-US`, `ja`, `zh-Hans`, `zh-Hant`: the four uploaded listings, version copy, TestFlight information and screenshot captions.
- `screenshots.json`, `screenshots/` and `screenshots/capture-provenance.json`: native capture requirements, final listing images and raw-capture provenance. `scripts/design_honbako_store_screenshots.py` at the repository root creates the final compositions.
- `submission.json`: current candidate, subscription, privacy and review state. Unresolved `false` owner confirmations must remain incomplete until confirmed.
- `review/build28-verification.json`: compact archive/upload/toolchain/test evidence and the explicitly pending native/review checks, without private contacts or home-directory paths.
- `review/Honbako-Pro-Build28.jpg` is the saved private product-review image: native Light appearance, default text size 3 and the real US$1.99 product; its HTTPS image source persisted after reload. The build-27 image is historical. `review/gui-build28/ui-verification.json` records 11 native captures and exact pass/limit evidence. The blocked Dark product-image attempt and capture-simulator cleanup are recorded in `review/Honbako-Pro-Build28-Dark-attempt.json` and `screenshot-captures/build28-dark/capture-cleanup.json`.
- `review-notes.txt`: clearly separated App Review draft and internal status. `review-test-plan.txt`: stepwise manual checklist, current evidence and a shorter reviewer draft.
- `ExportOptions-AppStore.plist`: App Store Connect export settings; its destination is **export**, rather than upload. Registered-device Ad Hoc IPAs cannot be used for TestFlight.
- `permission-strings`: localized system prompts. The Sumi-only resource phase installs en/ja/zh-Hans/zh-Hant interface tables and English plurals, preserving the legacy target.
- `privacy-review.md`: data-flow audit. `web-drafts/` contains historical drafts; `site/support/` and `site/privacy/` contain the current published public text.

Run `python3 scripts/validate_honbako_submission.py` from the repository root to check local assets and metadata. Use `--allow-pending-screenshots` only during capture preparation. `--require-submission-ready` must continue to report incomplete while rights, licensing and export confirmations remain false. The validator checks local records, rather than proving upload state or App Review eligibility.

Metadata limits checked by the validator are 30 characters for names/subtitles, 170 for promotional text, 4000 for descriptions and 100 UTF-8 bytes for keywords. [Apple platform metadata](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).

## Listing screenshots

All **24 Dark build-28 screenshots are uploaded**: three iPhone and three iPad images for each of four locales. Root verified **3 of 10** after every one of the eight uploads; the page autosaved with Save disabled, and the final English/iPhone browser proof is retained as `app-store-dark-proof.png` in the task artifacts. The verification was recorded at **2026-10-28 11:25:55 UTC**. These replace the earlier Light v3/build-26 designs.

The current images are genuine build-28 Debug simulator captures with public flags NO/NO under `screenshot-captures/build28-dark`. Native/output dimensions and hashes, all eight per-device proofs and primary/independent all-locale visual review passed. `screenshots/capture-provenance.json` links the aggregate `screenshot-captures/build28-dark/capture-manifest.json` and records the upload verification.

The designs preserve complete official silver Apple frames under the owner-accepted license, larger subtitles and no extra Honbako branding above the composition. No additional image generation or UI recoloring was used. The library shows original cover-art portfolios imported as real local CBZ files; reader/chapter screens show the original six-page tutorial, The Bookshop Between Pages. Demonstration portfolios are not bundled with the app. Native sizes/formats are recorded in `screenshots.json`; images have no alpha channel. [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

## Collection guide, Free and Pro

Build 28 includes the expanded existing **Getting Started** guide and **Free/Pro comparison** in English, Japanese, Simplified Chinese and Traditional Chinese. The guide explains local CBZ/ZIP imports, Komga/Kavita/Suwayomi connections, provider lists and compatible .aix files, then enabling search and saving books. It reuses the existing local comic importer.

Both plans are ad-free. Free supports reading/organizing the collection and using imported files locally. Pro adds chapter downloads, chapter notifications and iCloud library/progress sync. The price and purchase/restore controls precede the comparison rows.

`com.missingems.honbaku.pro` is a one-month auto-renewable subscription: Apple product **6827839648**, group **22521322**, U.S. base price **US$1.99**, four product/group localizations and 175 storefronts, with future expansion manual. Billing Grace Period is off. The paywall uses StoreKit localized pricing and retains Subscribe, Restore Purchases, Manage Subscription, Terms of Use and Privacy Policy. [Apple subscription presentation requirements](https://developer.apple.com/app-store/subscriptions/).

The private product review image is now the verified native **build-28 Light** page at default text size 3, showing the real Apple product at US$1.99, its Free/Pro sections and standard controls. It replaced build 27, saved automatically and retained an HTTPS image source after reload. The bounded attempt to capture a Dark Pro page was blocked by native input routing; no Dark private image was created. All 24 public marketing screenshots remain Dark. The US$0.99 local StoreKit fixture is used only for automated tests.

## Verification and remaining work

The public-toolchain iOS run passed **14 tests in four suites**: **9 self-host connection regressions, 4 Pro policy/entitlement tests and 1 local StoreKit integration test**. The run ends in `TEST SUCCEEDED`; archive/upload logs end in `ARCHIVE SUCCEEDED` and `EXPORT SUCCEEDED` / `Upload succeeded.` References are recorded in `review/build28-verification.json`.

The self-host tests cover URL/proxy handling and authentication/error regressions, including rejecting a simple-login error page with a cookie. The StoreKit test verifies the monthly fixture, verified entitlement unlock, cached access and refund removal. The 14 tests do not cover reader pagination, native purchase/restore button execution or a genuine sandbox-account purchase.

Native build-28 verification now has 11 preserved captures. Genuine Komga wrong/correct authentication, enabled connection, search/catalog, Add to Shelf, first-page PNG streaming and three distinct previews passed. Getting Started → Local Files setup → Files picker → cancel/close passed; completing a comic-file import is not claimed. On iPad, a semantic Page 2 action committed the original tutorial to its distinct second page, and closing saved the shelf position. Remote page advance, resume and bookmarks remain unverified. No reader defect was identified: compact Device Hub drag/scroll delivery also failed in Settings, while semantic iPad page selection worked. The disposable Komga service was stopped gracefully; 126 MB of temporary data and Desktop raw duplicates were removed.

Use `HonbakoStoreKitTests` with both public flags `NO` for the local StoreKit integration suite. Its explicit Debug argument initializes `SKTestSession` before the real store. The main `Honbako` scheme retains normal Run/Archive behavior; skip `SumiTests/HonbakoStoreKitIntegrationTests` when running the other suites through it. Future Billing Grace Period support requires corresponding entitlement handling and tests.

The build-28 product review image and Pro notes are saved and verified after reload; the exact notes are retained at `review/Honbako-Pro-Build28-review-notes.txt`. Both the **Honbako Pro Monthly subscription and Honbako Pro subscription group are Ready for Review** and were added to the existing iOS draft. Its **Items Ready to Submit (2)** list contains those two items. The draft's disabled Submit button reports: “To submit your items for review, add an app version for the selected platform.”

The selected build-28 app version remains **Prepare for Submission**. Root retried its Add for Review after the image replacement and product/group staging; Apple's only error remains missing **Content Rights Information**. The app version is not staged and **final Submit was not clicked**. The account-name-free blocker proof is retained at `review/AppStore-Build28-Content-Rights-Blocker.png`; the two-item draft proof `app-store-pro-ready-proof.png` remains in the task artifacts because it displays the owner's account name.

Pending: obtain an accurate owner content-rights declaration with supporting evidence, then add the app version to the existing draft. Content rights, engine distribution/licensing and export-compliance owner confirmations remain false. No clearance is inferred from tests, upload, privacy, screenshots or IAP staging. The two disposable capture apps/data were removed and their simulators shut down after restoring keyboard capture off and text size 3; final captures/proofs were preserved. See the [release and rights notes](../docs/RELEASE_AND_RIGHTS.md) and [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

Relevant Apple references: [App privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/), [export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance), [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) and [test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/).
