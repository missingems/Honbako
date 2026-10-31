# Honbako App Store preparation

Updated 28 October 2026. Version 0.1.0, **build 29**, is uploaded, processed, selected and saved in App Store Connect. It was archived with public Xcode 27.1 **27A9275**, flags `HONBAKO_PERSONAL_FEATURES=NO` / `HONBAKO_IMPORT_ENGLISH_50=NO`, and a valid strict signature.

This release is for personal collections: the original tutorial, imported local comic files, and user-configured Komga, Kavita or Suwayomi servers. Settings/onboarding source-list and package-installation routes are removed. Source-list links, package imports, stored external catalog/demo configurations and external catalog metadata enrichment cannot activate those sources. Existing user library records and files are retained. Unavailable sources cannot fetch remote cover fallbacks.

**38 tests in eight suites passed**, including five collection-scope regressions, self-hosted transport, Pro policy/entitlement, local StoreKit, bootstrap, cover and search preparation. Native viewer input still did not reach Settings, so build-29 Settings GUI verification is not claimed. Earlier build-28 Komga and reader GUI evidence remains historical.

All four listing descriptions and the exact **3,062-character app review notes** are saved. The support/privacy scope updates are deployed and verified live. All **24 Dark** marketing screenshots remain uploaded; their native build-28 library/reader UI is unchanged in build 29. The saved private Pro image remains the verified build-28 Light capture of the same $1.99 paywall; the updated product notes disclose that capture version.

Pro and its subscription group are both **Ready for Review**, together as two items in the existing draft. The app version is **Prepare for Submission**: adding build 29 to review reports only **missing Content Rights Information**. The declaration remains unresolved. No final Submit was clicked, and nothing is submitted for review.

## Evidence

- `review/build29-verification.json`: archive, tests, upload, selected build, exact saved copy and validation status.
- `review/build29-source-hashes.json`: app source hashes, checked unchanged after archiving.
- `review/Honbako-Build29-review-notes.txt` and `review/Honbako-Pro-Build29-review-notes.txt`: exact saved review copy.
- `review/build29-site-publication.json`: two-file GitHub publication, successful deployment and live HTTP checks.
- `review/build29-cleanup.json`: owned simulator cleanup; final archive and small test result retained, temporary export removed.
- `review/AppStore-Build29-Content-Rights-Blocker.png`: account-contact-free app validation proof.
- `review/build28-before-collection-only/`: predecessor submission notes, checklist and status snapshots.
- `screenshots/capture-provenance.json`: the verified 24-image Dark upload record.

Support: https://missingems.github.io/Honbako/support/
Privacy: https://missingems.github.io/Honbako/privacy/

Run `python3 scripts/validate_honbako_submission.py` for local asset/metadata checks. `--require-submission-ready` must remain incomplete while the content-rights, engine-distribution licensing and export owner confirmations remain false. Local validation does not establish App Review approval.

## External-source TestFlight variant

Version **0.2.0 (30)** is prepared separately, uploaded and processed. It enables external sources explicitly while the default App Store mode remains collection-only. Beta description, review notes, approved feedback address and What to Test are saved. The empty external group is prepared, but the build is not attached, no review was submitted, no testers were invited and no public link is enabled. Authorized provider/source-list details and continuation approval remain pending after automatic approval review rejected the group-wizard handoff. See `testflight/build30/README.md` and `testflight/build30/verification.json`. App Store build29 remains selected with its unchanged3062-character notes.
