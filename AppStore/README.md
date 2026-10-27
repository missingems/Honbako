# Honbako submission preparation

Prepared on 27 October 2026. This folder contains assets and review material, not a submission receipt. Nothing here uploads a build, accepts agreements, publishes privacy declarations, or clears distribution rights.

## Prepared

- `assets/AppIcon-1024.png`: unchanged 1024 × 1024 opaque app icon.
- `metadata/en-US`, `ja`, `zh-Hans`, `zh-Hant`: name, subtitle, promotional text, description, keywords, version copy, TestFlight description/testing copy, and screenshot captions.
- `screenshots.json`: native capture sizes and a three-image story. Actual captures belong in `screenshots/<locale>/<device>/`.
- `submission.json`: monthly Pro configuration and owner fields that remain unresolved. `null` and `false` values must not be treated as completed declarations.
- `ExportOptions-AppStore.plist`: local App Store Connect export configuration. Its destination is **export**, not upload. Registered-device Ad Hoc IPAs cannot be used for TestFlight.
- `permission-strings`: target-specific localized system prompts. The Sumi-only resource phase also compiles only en/ja/zh-Hans/zh-Hant interface tables and English plurals, preserving the legacy target.
- `privacy-review.md`, `web-drafts`, and `review-notes.txt`: factual data-flow audit and drafts requiring owner review.

## Screenshots

Apple currently requires an iPhone Dynamic Island medium set and, for this universal app, an iPad 13-inch set. Suggested native captures are 1206 × 2622 and 2064 × 2752; landscape reversals and the alternatives in the manifest are accepted. Supply 1–10 JPEG/PNG images per size, without alpha. Duo outer 1398 × 2034 and inner 2007 × 2853 sets are optional now; Apple states they become required from April 2027 for iOS 27.1 SDK apps. Use original tutorial artwork or content whose marketing rights are documented. Screenshots must show the actual app, not fabricated interfaces. [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

Run `python3 scripts/validate_honbako_submission.py --allow-pending-screenshots` while preparing. Run it without that option after final captures are present.

## Monthly Pro

The user selected a monthly auto-renewable subscription. The product identifier in code is `com.missingems.honbaku.pro`; the owner selected US$1.99 per month for the U.S. base storefront. The real product record, subscription group, and localized storefront prices still require App Store Connect configuration. The app accepts only a one-month auto-renewable product, displays StoreKit's localized price, and has restore/manage controls. The simulator fixture remains US$0.99 and is explicitly test-only; it is not the selected production price. The runtime paywall always displays StoreKit pricing. Confirm the real product's availability, tax/banking agreements, purchase, renewal, cancellation, refund, and restore before distribution. If enabling Billing Grace Period, verify the app preserves access throughout that configured grace period. The owner must publish an accurate privacy policy and supply its URL; the in-app Privacy Information sheet is not proof that this external requirement is complete. [Apple subscription presentation requirements](https://developer.apple.com/app-store/subscriptions/).

## Required owner decisions before submission

1. Resolve the GPLv3 reader-engine distribution obligations and provider/content rights described in [release and rights notes](../docs/RELEASE_AND_RIGHTS.md). Do not remove notices or present a renamed fork as an independently licensed reader engine.
2. Review imported executable `.aix`/WASM sources against Apple's downloadable-code/plugin requirements. Renaming the feature or leaving setup to users does not settle this review question. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
3. Provide a real public support URL/contact, privacy-policy URL, review contact name/email/international phone, feedback email, copyright holder, and the existing App Store Connect app record ID. The user-authorized public feedback/support contact is prefilled as itchymail@icloud.com; legal review-contact identity and other unverified fields remain unset.
4. Confirm the privacy answers using the final archive and all SDK manifests, export-compliance answers, age-rating questionnaire (including configurable external content), pricing, territories, and accessibility claims. No blanket “Data Not Collected” answer has been submitted. [App privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/), [export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance).
5. Validate the final archive with App Store Connect signing and its production iCloud container. Upload only when authorized, wait for Apple's processing, and complete TestFlight test/review information. External TestFlight testing may require review; it is not a way around review rules. [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/), [test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/).

Metadata limits checked by the validator: names/subtitles 30 characters, promotional text 170 characters, descriptions 4000 characters, keywords 100 UTF-8 bytes. Contact and rights fields remain explicit blockers. [Apple platform metadata](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).
