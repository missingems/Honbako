# Current IAP review screenshot plan — not executed

Existing UI tests are insufficient for two precise monthly/annual review images:
Welcome tests capture native plan rows but do not establish StoreKit test products;
JapaneseGuideInteractionTests establishes an actual no-charge SKTestSession but
captures only the top of a feature-triggered paywall. Do not present an unavailable
price state or old build28/29 image as a current subscription offering.

`HonbakoPublicPaywallScreenshotTests.swift` is installed in SumiUITests, with a
matching reference copy here. Rebuild once using the HonbakoStoreKitTests scheme
in the existing shared DerivedData, preserving the final public app's version/build
and all three public flagsNO. This scheme supplies the actual application's
StoreKit launch configuration; the UI runner also establishes its SKTestSession.
Do not run the capture under a manifest from the regular Honbako scheme.

1. Build the public simulator test bundle once, with the
   HonbakoStoreKitTests scheme and the final public build flags.
2. Run only the new native test on the disposable large iPhone:

```sh
DEVELOPER_DIR="/Applications/Xcode 27.1 Public.app/Contents/Developer" \
  xcrun xcodebuild test-without-building \
  -xctestrun /absolute/path/to/final-public.xctestrun \
  -destination 'platform=iOS Simulator,id=5BA61F93-11A7-4F62-9E6A-0A513C557E08' \
  -parallel-testing-enabled NO \
  -only-testing:SumiUITests/HonbakoPublicPaywallScreenshotTests/testPublicMonthlyAndAnnualPaywallScreenshots \
  -collect-test-diagnostics never \
  -resultBundlePath /absolute/path/to/UNIQUE-paywall.xcresult
```

3. Export only passed native screenshot attachments via xcresulttool. Expect
   `Public paywall — monthly selected — native StoreKit prices and trial` and
   its annual counterpart. Preserve native pixels and record final archive build,
   capture build, raw SHA256, dimensions and fixture provenance. Visually inspect
   prices, both trial rows, selected plan, restoration action and pinned renewal
   CTA before using the corresponding image for each IAP.

The test uses Apple's SKTestSession API with the existing bundled USA/en_US
StoreKit configuration. The original configuration and subscription group are unchanged. The test first
validates their JSON metadata, then verifies the actual application displays fetched
StoreKit prices of $2.99/month and $28.49/year, 20% annual savings, eligible one-week
and one-month trials, and the corresponding selected-plan renewal CTA. Product.products
is not called from the separate UI-runner bundle. Real Product metadata checks belong
in the existing app-hosted HonbakoStoreKitIntegrationTests suite. It creates NO purchase/entitlement and submits no payment.
The screen itself is the genuine public app's normal onboarding paywall, not a
redrawn interface. Its --sumi fixture flags and disabled iCloud prevent simulated
setup from being published to the owner's iCloud account.

This is valid local StoreKit/UI evidence, not proof of an Apple Sandbox-account
purchase or live App Store product configuration. Check the actual App Store
Connect prices/offers still match before uploading IAP review images. Existing
StoreKit product setup was owner-approved; never change billing just for a picture.

If final public build76 contains only the new unavailable-page fallback while
these same plan screens are unchanged, preserve whichever build actually produced
each capture in its provenance. Never relabel75 screenshots as76.
