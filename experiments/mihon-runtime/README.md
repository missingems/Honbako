# Mihon extension compatibility experiment

This is an isolated implementation spike, not a finished source backend. The released Honbako app does not link OpenJDK, advertise APK/JAR execution, preload a repository, or migrate existing reading records.

## Implemented and verified

- The independent Swift catalog parser in `Aidoku/Core/Sources/Mihon` reads legacy JSON, modern JSON, Protobuf and bounded gzip, preserving exact 64-bit source IDs and separate APK/JAR artifacts. The current published catalog was decoded successfully; 12 focused iOS unit tests pass.
- `ExtensionBridge.execute(String)` executes the unmodified, checksum-pinned Komga 1.6.74 JAR. The host proof covers its factory sources, remote-catalog search, details, chapters, pages, actual `HttpSource.getImage` processing, three distinct original images, empty results, rejected unknown source IDs, and denied external network access.
- `KomgaDeviceProbe.run(String bundleRoot)` hosts the original-content fixture inside the JVM. The same proof passes on the host without starting Suwayomi Server or requiring an external content server.
- The separate UIKit iOS probe compiles for simulator and device. It uses a scene-owned window and a dedicated worker thread. Its bundle ID is `com.missingems.honbaku.runtimeprobe`, so installing it does not replace Honbako.
- The physical iPad mini probe starts the static, interpreted Java 27 Zero VM and executes the published Komga JAR through discovery, search, details, chapters, page metadata, three image fetches, and an empty search. All three original page hashes match. The fixture runs inside the same iPad process; no Mac-hosted content server is used. Evidence is in `proofs/ios-komga.json` and `proofs/ios-runtime.txt`.
- The Runner adapter, reviewed JSON transport, reader/webtoon image path, scrub/preload request path, offline byte storage, generic/library/search cover loading, and reviewed package store pass the focused checks. The full Honbako unit suite passes **408 tests**. Package storage does not register or execute an extension, and a checksum is not signing authentication.
- The reusable native executor also passes on the physical iPad mini: three raw page-byte transfers, a raw cover transfer, repeated metadata requests, fixture cleanup, and auto-lock restoration. `proofs/ios-native-executor-result.json` records the checks; no base64 transfer is used in the native image path. A fresh host preparation from an empty directory passes independently.
- `build_matching_modules.py` compiles all `java.logging` and `java.xml` Java sources against the exact extracted mobile `java.base`, with `--system none`. It uses the pinned official `ModuleInfoExtender` to add complete `ModulePackages` metadata, including concealed packages such as `jdk.xml.internal`. Reading each descriptor without a directory package finder verifies the full package set. Its host smoke test verifies the rebuilt logging/localization, secure DOM, XPath, transform, and StAX classes.
- `build_mobile_image.py` uses the pinned official March image writer to combine the three modules in JIMAGE format 1.0. Extraction verifies every runtime file against its input hash, including all unchanged mobile `java.base` files.

## Native gates still open

The downloaded simulator VM fails during startup with the upstream [CodeCache issue](https://github.com/openjdk-mobile/ios-tools/issues/51). Actual extension execution is verified on the physical iPad mini. This proves the tested JAR and dependency set; general Android API compatibility and legacy APK execution on iOS remain unverified.

The March 15 native framework is paired with the exact `java.base` from the March 15 `java_bundle-device` runtime image. The older February `java.base-device.zip` is deliberately not used. The public snapshot provides only `java.base`. The two additional pure-Java modules are rebuilt from official OpenJDK Mobile revision [`1606564e`](https://github.com/openjdk/mobile/tree/1606564eddfd17f74015e219cd5b754ec35bf0c8), the latest commit before the release build time, against that exact mobile base. The release does **not** publish its source SHA, so source identity with the release is not established. These are experimental inputs; a production runtime needs an established common source revision and complete license/source audit.

Desktop module files are unsuitable here: their macOS platform stamp conflicts with the iOS base, and boot-loader modules such as `java.logging` cannot load from either the application module path or the upgrade module path. The original [module bootstrap checks](https://github.com/openjdk/mobile/blob/1606564eddfd17f74015e219cd5b754ec35bf0c8/src/java.base/share/classes/jdk/internal/module/ModuleBootstrap.java#L413-L426) require them in the runtime image. The combined image contains the original `/modules` and `/packages` lookup trees. It preserves all runtime class bytes; no descriptors are downgraded and no host module classes are copied into it.

Remaining production work includes registering the native transport in the shipping app, public HTTPS/cookie handling, persistent credentials/preferences, cancellation of active Java/HTTP work, real repository/package signature authentication, controlled updates, broader API compatibility checks, and the user-facing install path. The package store records explicit review and continuity evidence without claiming unimplemented cryptographic authentication. A real APK has passed host conversion/execution, recorded in `proofs/host-apk.json`; it has not passed native conversion or signing verification. The measured Komga dependency subset is not a general Android API implementation. The fixture’s OkHttp loopback restriction is not a security sandbox for arbitrary Java bytecode. Existing sources, history, bookmarks and downloads coexist unchanged; the old destructive migration helper must not be used as a lossless migration.

## Reproduce the host proof

See [HOST-PROBE.md](HOST-PROBE.md). Runtime downloads and build products belong outside the checkout; the preparation script removes the large reference JAR after producing and testing the reduced proof classpath.

## Prepare the native probe

Requires the approved OpenJDK runtime, CMake, Xcode, a host JDK 27, and a JDK 17 `jimage` tool. `OPENJDK-SNAPSHOT.json` records the official artifact IDs and SHA-256 digests; `fetch_ios_runtime.py` verifies every download. Runtime binary files and the sparse upstream source checkout are kept outside the repository.

1. Run `prepare_host_runtime.py` and its host checks as documented. This produces `honbako-extension-bridge-v2.jar` and the v2 proof from current sources; historical baseline/APK artifacts are not needed. CMake copies the v2 JAR under the executor's fixed bundle name, `honbako-extension-bridge.jar`.
2. Run `fetch_ios_runtime.py --runtime-root <outside-checkout-directory>`.
3. Extract the exact image's module classes with JDK 17 `jimage`, then run the two reproducible build scripts below. `--fetch-source` creates or extends only the pinned sparse official source checkout. It can be omitted on subsequent offline rebuilds.

   ```sh
   HONBAKO_RUNTIME_ROOT=/path/outside/checkout/runtime17
   HONBAKO_JDK27=/path/to/jdk27/Contents/Home
   HONBAKO_JDK17=/path/to/jdk17/Contents/Home

   "$HONBAKO_JDK17/bin/jimage" extract \
     --dir "$HONBAKO_RUNTIME_ROOT/java.base-matched-device" \
     "$HONBAKO_RUNTIME_ROOT/java_bundle-device/lib/modules"

   python3 experiments/mihon-runtime/build_matching_modules.py \
     --runtime-root "$HONBAKO_RUNTIME_ROOT" \
     --java-home "$HONBAKO_JDK27" --fetch-source

   python3 experiments/mihon-runtime/build_mobile_image.py \
     --runtime-root "$HONBAKO_RUNTIME_ROOT" \
     --java-home "$HONBAKO_JDK27" \
     --jimage "$HONBAKO_JDK17/bin/jimage" --fetch-source
   ```

   Outputs are `java-extra-matched`, `java-extra-matched-conf`, `java-extra-matched-legal`, and `combinedimage/lib/modules`. The module and image provenance JSON files record source revisions, tool inputs, hashes, and verification. The image script requires the complete-package verification and removes its full extraction after comparing every file. Concealed packages must be recorded in `ModulePackages`: an image module finder cannot infer them by scanning an exploded directory as host patch-module tests do. Host JDK 27 writes format 1.1 by default; the pinned March writer and header are necessary to produce the mobile runtime's format 1.0.
4. Run `prepare_ios_runtime.py --runtime-root <same-directory> --java-home <JDK27-home>`. It verifies rebuilt module/image hashes, clears stale configuration, prepares the first-party diagnostic JAR and four original artwork files, and records hashes for selected non-secret diagnostic configuration and the portable time-zone database. The module-specific configuration comes from the pinned sources. Host network/security configuration remains diagnostic-only; no host trust store or credentials are copied.
5. Configure `ios/CMakeLists.txt` with the Xcode generator, `CMAKE_SYSTEM_NAME=iOS`, the device SDK, explicit Xcode compiler paths when needed, `CMAKE_OSX_ARCHITECTURES=arm64`, and `HONBAKO_RUNTIME_ARTIFACTS=<same-directory>`.
6. Build the generated `HonbakoRuntimeProbe` scheme with a valid existing development team/profile. Use the repository's shared DerivedData path. Install only the separate probe app.
7. Launch for the reusable executor proof. It runs the core checks, real extension operations, direct native image/cover transfers and repeated requests, then closes the retained fixture and restores auto-lock. Results are written to the probe's Documents directory: `runtime-core-result.txt`, `runtime-result.txt`, `extension-proof.json`, and `native-executor-result.json`. The earlier core-only evidence is retained in `proofs/ios-core.txt`; the current app runs the full workflow.

The static iOS VM expects the image at **`<app>/lib/lib/modules`**, time-zone data at `<app>/lib/lib/tzdb.dat`, configuration at `<app>/lib/conf`, and Xcode `ENABLE_DEBUG_DYLIB=NO`. Retain and export the five built-in `JNI_OnLoad_…` library entry points as shown in CMake; otherwise dynamic built-in lookup fails despite the native code being in the archive. Do not set `-Djava.home`; let the native runtime establish its paths. The probe sets `-Djdk.system.module.finder.disableFastPath=true` because the preserved base contains a precomputed graph for `java.base` alone. This selects the official [module-descriptor parsing path](https://github.com/openjdk/mobile/blob/1606564eddfd17f74015e219cd5b754ec35bf0c8/src/java.base/share/classes/jdk/internal/module/SystemModuleFinders.java#L73-L100) and discovers all three modules from the image. Full mode adds `java.logging,java.xml` as roots; core-only mode limits resolution to `java.base`.

A successful physical-device run must contain `ok: true`, all real extension operations, and three distinct image hashes. It is still a prototype, not proof of general APK compatibility, persistence, or a complete production source workflow.

## Provenance

- [OpenJDK Mobile architecture](https://openjdk-mobile.github.io/architecture/) and [iOS JNI embedding example](https://github.com/openjdk-mobile/ios-tools/blob/main/docs/helloworld.md).
- [OpenJDK licensing](https://github.com/openjdk/mobile/blob/master/ADDITIONAL_LICENSE_INFO): preserve exact GPLv2 notices and the exceptions applicable to the linked files; do not label the entire runtime permissive.
- The extension and measured API/dependency classpath provenance, fixed hashes, and limits are in `HOST-PROBE.md` and the preparation script. The proof does not copy Tachimanga's private implementation.
- Only Honbako's original tutorial artwork is used for fixture pages. No third-party manga is bundled in the experiment.
