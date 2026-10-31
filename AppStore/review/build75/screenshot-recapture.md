# Screenshot workflow — 24 genuine captures, 36 marketing compositions

Completed: all eight public build75 native capture tests passed; their24 source
JPEGs and36 final compositions are verified. No capture is relabeled as build76.
The final76 changes unavailable-chapter recovery and settings copy; these displayed
available-chapter states remain unchanged.

Apple's current Required device sizes paragraph explicitly requires **medium
Dynamic Island iPhone and13-inch iPad**. Large iPhone is optional. The earlier
Large-only interpretation omitted that paragraph and is superseded here:
https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/

The native source devices are disposable iPhone18ProMax
`5BA61F93-11A7-4F62-9E6A-0A513C557E08` (1320×2868) and iPad13M5
`2894F317-56AD-47E0-965E-62D57B74D995` (library2752×2064, reader/Chapters2064×2752).
The renderer preserves each matching Apple frame and its native screenshot as one
whole product. It uniformly scales that product onto each marketing canvas:

| Output directory | Canvas | Requirement |
| --- | --- | --- |
| `LOCALE/iphone-medium` |1206×2622| Required medium iPhone |
| `LOCALE/ipad` |2064×2752| Required13-inch iPad |
| `LOCALE/iphone` |1320×2868| Optional large iPhone |

The medium set does not pretend to be a native Medium capture. Provenance records
its Large native source, matching full Pro Max bezel and composition method. Native
UI is never independently stretched, cropped, replaced or repainted. Existing Large
and iPad outputs remain byte-identical after adding Medium.

For a future coordinated recapture, first finish any shared DerivedData build.
Build the public simulator app/test runner once, with the correct public version
and build and all three external/personal/bulk-import flagsNO. Then run:

```sh
python3 scripts/capture_honbako_submission.py --build 75 \
  --app "$HOME/Library/Developer/Xcode/DerivedData/Aidoku-Codex/Build/Products/Debug-iphonesimulator/Sumi.app" \
  --xctestrun /absolute/path/to/public75.xctestrun \
  --run-id UNIQUE-safe-run-label
```

The wrapper verifies exact app/manifest paths and version/flags, prepares only
allowlisted disposable simulators, runs four locales on each device sequentially,
collects passed native JPEG attachments, then renders all36 compositions. It never
builds or uploads. The eight native methods are testEnglish, testJapanese,
testSimplifiedChinese and testTraditionalChinese in
SumiUITests/HonbakoSubmissionScreenshotTests, once per source device.

Rendering alone, from the already complete verified source set:

```sh
python3 scripts/design_honbako_store_screenshots.py --build 75
```

All36finals must be RGB JPEG with correct dimensions, matching raw and frame hashes,
whole frames and safe typography. Inspect the required Medium+iPad contact sheet
and the all36contact sheet under review/build75/screenshot-proofs. See
screenshot-verification.json and asc-screenshot-upload-order.txt before uploading.
No extra Honbako marketing label or new image generation is used; existing cover-art
assets retain their earlier generation provenance.

The IAP review images are separate from these marketing screenshots. Use the native
StoreKit capture test and inspect selected monthly/annual prices/trials and the
renewal CTA. The release coordinator owns all App Store Connect mutations and final
submission; these scripts never claim upload or submission.
