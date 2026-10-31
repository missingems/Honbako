# Current public screenshot set — native capture builds 75 and 76

The verified set contains 24 genuine native UI captures and 36 framed marketing
images across English, Japanese, Simplified Chinese and Traditional Chinese:

- Required medium iPhone: 12 images in `LOCALE/iphone-medium/`, 1206×2622.
- Required 13-inch iPad: 12 images in `LOCALE/ipad/`, 2064×2752.
- Optional large iPhone: 12 images in `LOCALE/iphone/`, 1320×2868.

Apple's Required device sizes paragraph and the live App Store Connect media
manager require medium iPhone and 13-inch iPad. Do not leave the medium slot
empty and assume it inherits the optional large set.

Four iPad library images were genuinely recaptured upright in portrait on public
build 76 after an orientation error was found in the earlier build 75 exports.
All four library-only native UI tests passed. Each new raw capture has upright
2064×2752 pixels and EXIF1; each framed locale image was individually inspected.
The other 20 native captures remain build 75, and the other 32 final JPEG files
remain byte-identical. Never relabel their capture build. Source build per image,
native and final hashes, dimensions and frame hashes are recorded in
`capture-provenance.json` and `../review/build76/mixed-native-capture-manifest.json`.
The compact test evidence and final orientation checks are in
`../review/build76/screenshot-orientation-verification.json`.

The medium canvas contains the genuine Large capture in its complete matching
Apple Pro Max frame, uniformly scaled together. iPad uses the complete matching
Apple portrait frame. No independent UI stretch, crop, repainting or new image
generation is used. Existing original portfolio artwork retains its earlier
generation provenance. Library contains 50 genuine local one-page original-art
portfolios and five original guides; portfolios are sample artwork, not full
manga stories or preinstalled public content.

Public build 76 changes unavailable-chapter fallback and source-settings copy;
the remaining build 75 available-chapter screenshots still represent those
unchanged screens. App Store upload and saved-state preview verification are
separate parent release steps and are not claimed by this file. For the four
corrected iPad slots, upload each locale's ordered `01-library`, `02-reader`,
`03-chapters` triplet; only the first file has new image bytes. Earlier build 75
orientation claims are superseded by the build 76 orientation verification.

# Historical build69 screenshot refresh

The complete build69 refresh is captured, rendered and verified:24 current
listing JPEGs across four locales and iPhone/iPad. All eight native UI capture
tests passed. Raw and final SHA256 hashes and dimensions match their manifests.
Both contact sheets were visually reviewed. App Store upload is a separate
parent release step and is not claimed by this capture workflow.

The current workflow captures 24 genuine dark-mode UI states: Library, Reader,
and Chapters for en-US, Japanese, Simplified Chinese and Traditional Chinese,
on iPhone and iPad. The Reader uses the native manga title and chapter subtitle;
the Chapters capture verifies the current chapter is selected and visible.
Library uses 50 real local one-page original-cover portfolios plus the five
bundled original guides. Portfolios are sample artwork books, not full manga
stories or preinstalled public content. No new image generation or UI fabrication
is used in this refresh.

Use the shared DerivedData directory and build the normal Honbako UI-test runner
once with build69, external sources enabled, and personal features/bulk import
disabled. The capture devices are disposable simulators only:

- iPhone18Pro: `04492D57-7FB3-47FD-8A03-75CE5A4A40FE` (1206×2622).
- iPad13M5: `2894F317-56AD-47E0-965E-62D57B74D995` (library2752×2064;
  reader/chapters2064×2752).

Run this sequence for each locale and each device. Do not prepare a simulator
while another test is using its installed Honbako app. Preparation explicitly
uninstalls only the allowlisted disposable app, initializes its original guides,
then imports the bounded original-art local library while the app is stopped.
The preparation flag is required to prevent accidental data replacement.

```sh
python3 scripts/prepare_honbako_screenshot_library.py iphone en-US --build 69 --replace-disposable-app
# Parent release runner: test-without-building, normal Honbako scheme,
# -only-testing:SumiUITests/HonbakoSubmissionScreenshotTests/testEnglish
# -parallel-testing-enabled NO -collect-test-diagnostics never
python3 scripts/collect_honbako_screenshots.py --build 69 --device iphone --locale en-US --result /absolute/path/to/result.xcresult
```

The corresponding methods are testJapanese, testSimplifiedChinese and
testTraditionalChinese. Prepare a fresh screenshot library before each locale
so native stored chapter-language filters match the requested language.

Collection only accepts passed native UI-test results and copies their JPEG
attachments unchanged. It records dimensions, app metadata, source hashes and
preparation provenance under `../screenshot-captures/build69-dark/`. After all24
captures exist and validate, render all four locales in one step:

```sh
python3 scripts/design_honbako_store_screenshots.py --build 69
```

Rendering refuses to overwrite the final listing from a stale, incomplete or
modified capture set. It uses the existing licensed official Apple iPhone and
iPad frames with the full device visible; no screenshot UI pixels are redrawn.
Final hashes are in capture-provenance.json. Contact sheets are saved under
`../review/build69/screenshot-proofs/`. App Store upload is a separate final
step; these scripts do not mark images as uploaded or publish anything.

# Earlier screenshot sets

Original source captures from builds26 and28 remain archived under
`../screenshot-captures/`. The current listing images use build69 only. Previous
upload status does not imply that this refreshed set has been uploaded. The
original-art cover provenance remains under `../original-covers/manifest.json`.
