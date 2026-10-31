# Corrected iPad library screenshots

All four native library-only UI tests passed on public build 76 / version 0.1.0, external/personal/import flags NO. Each fresh portrait screenshot is 2064×2752 with upright EXIF 1 pixels. No production app code changed. The complete licensed Apple portrait frame and native screenshot are uniformly scaled together into the 2064×2752 marketing composition; no UI was stretched, cropped, redrawn or generated. Each final locale image was inspected individually at full size.

Replace only AppStore/screenshots/{en-US,ja,zh-Hans,zh-Hant}/ipad/01-library.jpg. The other 32 final screenshot files remain byte-identical. Parent coordinates upload and saved-state preview verification.

Mixed native manifest: mixed-native-capture-manifest.json records 20 unchanged raw build 75 captures plus 4 fresh raw build 76 captures. Final screenshot provenance records the source build per image. Historical raw build 75 iPad library images are superseded and retain their original files for audit. The earlier build 75 verification does not validate the corrected four images; use screenshot-orientation-verification.json.

Four Passed native test summaries are retained in ipad-portrait-native/test-summaries.json; exported raw images and their hashes/preparation data are in AppStore/screenshot-captures/build76-dark. Transient result bundles and build log were removed after verification.
