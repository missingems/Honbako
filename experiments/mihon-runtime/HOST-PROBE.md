# Real Komga extension host proof

This experiment executes the **unmodified, published Komga extension 1.6.74** through its real `SourceFactory` and source methods. It is a host-JVM proof. It is not evidence that these dependencies run on iOS, that arbitrary Android extensions work, or that a production source import is ready.

`java/com/missingems/honbako/runtime/ExtensionBridge.java` exposes a JSON string boundary usable from a command line or JNI:

```java
String response = ExtensionBridge.execute(requestJSON);
```

The request specifies a local `extensionPath`, `operation`, and optional string `preferences`. Operations are `discover`, `search`, `details`, `chapters`, `pages`, `image`, and `cover`. All source IDs cross the JSON boundary as decimal **strings**, preserving their full 64-bit values. `search` takes `sourceId`, `query`, and `page`; `details` and `chapters` take `sourceId` and the manga record returned by search; `pages` takes `sourceId` and the chapter record returned by the chapter operation. `image` takes `sourceId` and a page record. A missing `imageUrl` invokes the actual source's `getImageUrl(page)` before its `getImage(page)` request and response hooks. `cover` takes `sourceId` and an absolute `url`, using the selected source's headers and HTTP client. Replies are `{ "ok": true, "result": ... }` or `{ "ok": false, "errorType": ..., "error": ... }`.

The v2 binary boundary is `ExtensionBridge.image(String) -> ExtensionBridge.ImageResult`; its public final fields are `byte[] data`, `String mediaType`, and `String sha256`. The native executor copies those bytes directly. Images are bounded to 32 MiB while reading the response, including unknown-length streams. Legacy JSON image replies can include base64 only below the separate JSON response budget; larger images require the binary method. Requests and JSON responses are bounded to 5 MiB and 8 MiB, with strict duplicate-field, depth and token checks. Optional `packageSHA256`, `packageName`, `versionName`, and `extensionLibrary` expectations are checked against the file/manifest before class initialization, including cached lookups. This scoped backend accepts extension library **1.6**. File hashes and manifest checks do not authenticate a package signer.

The bridge parses `AndroidManifest.xml` from the actual JAR with external entities and DTDs disabled, loads its declared entry class, and calls the extension API. There is no native Komga source substituted for the extension, and Suwayomi Server's main function is never invoked.

## Reproduce

Use a JDK 21 or newer compiler/runtime. The currently verified host is Homebrew OpenJDK 27; the default paths in the scripts point to it. All downloaded artifacts and class files must live **outside this checkout**:

```sh
python3 experiments/mihon-runtime/prepare_host_runtime.py \
  --runtime-root /absolute/path/outside/checkout/runtime17 \
  --java-home /opt/homebrew/opt/openjdk@27
```

The script pins URLs and SHA-256 values, compiles only the six bridge/host-service source files, runs the real extension against a loopback-only HTTP fixture, creates a reduced reference dependency JAR, emits **`honbako-extension-bridge-v2.jar`**, runs both host proofs, and removes the 183 MB reference JAR even after a failed subprocess. `--keep-reference` retains that temporary JAR for debugging. The reduced JAR retains complete Kotlin/coroutine/HTTP/JSON libraries because a single execution trace does not cover every coroutine scheduling path. The bridge also contains the real `HttpSource` default `RequestsKt` helper, which Komga's override does not exercise. Other reference classes are the measured test subset.

This source-only preparation does not depend on the historical `honbako-extension-bridge.jar`, APK conversion output, or the original binary's checksum. It rebuilds current generated outputs; preserve an existing recorded artifact set before rerunning preparation. It does not overwrite the historical baseline JAR. Packaging metadata/toolchain differences can change a rebuilt JAR digest, so use the new generated provenance and passing host proof when staging that build rather than copying a historical proof's digest.

To rerun the v2 tests without rebuilding or replacing the bridge/dependency JARs:

```sh
python3 experiments/mihon-runtime/probe_bridge_v2.py \
  --runtime-root /absolute/path/outside/checkout/runtime17 \
  --java-home /opt/homebrew/opt/openjdk@27
```

Its original first-party `HttpSource` fixture separately proves lazy image resolution, source headers, client/page hooks, known/unknown-length oversize rejection, pre-constructor identity rejection, and source/named-preference isolation. It does not claim those fixture-specific behaviors were supplied by Komga. The compile-only test dependency JAR and original fixture JAR are never bundled in the native app.

The fixture serves only Honbako's original tutorial artwork. It verifies source discovery, search metadata, details, chapter date/order, three distinct ordered page images fetched through the extension's own image method, an empty result, unknown-source rejection, and denial of non-loopback network requests. The HTTP server and JVM stop cleanly afterward.

Generated evidence:

- `komga-host-proof.json`: actual operations, requests, source identities, and image hashes.
- `komga-proof-classpath.json`: source artifact pins and selected reference classes.
- `komga-proof-dependencies.jar`: a measured dependency subset for this experiment.
- `bridge-v2-classes/` and `honbako-extension-bridge-v2.jar`: the current bridge and diagnostic fixture classes, without APK conversion or host-test classes.
- `bridge-v2-build.json`: source/reference/dependency hashes for the current v2 build.
- `bridge-compile-dependencies.jar`: compile-only actual API classes for the original test subclass; excluded from the native runtime.
- `bridge-v2-host-proof.json`: binary page/cover hashes and the bounded-image, lazy-resolver, input and preference checks.
- `komga-device-probe-host.json`: the same self-contained in-process fixture class intended for the native JNI experiment, verified on the host.

The verified HTTP proof needs exactly `java.base`, `java.xml`, and `java.logging` with `--limit-modules`; it passes without `java.desktop`, `java.sql`, or other optional modules. This does not establish which crypto modules a public HTTPS source will need.

`KomgaDeviceProbe.run(String bundleRoot)` runs its own bounded `ServerSocket` fixture and calls the bridge in-process. It expects the verified extension JAR in `bundleRoot` and `fixture/cover.png`, `fixture/page-1.png`, `fixture/page-2.png`, and `fixture/page-3.png`. It uses no Mac-hosted service or public provider. By default its `finally` path closes sockets, fixture workers, URL class loaders, and the one-shot OkHttp session. The native reusable-executor diagnostic opts into `-Dhonbako.probe.keepFixture=true`: a successful proof returns `fixtureRetained: true` and `fixtureBaseURL`, keeping the fixture/session alive for subsequent binary calls. It must call `KomgaDeviceProbe.closeRetainedFixture()` in its completion/finally path. Failed proofs clean up without retaining a session.

**The current native probe requires v2.** Select `-DHONBAKO_BRIDGE_JAR=<runtime-root>/honbako-extension-bridge-v2.jar` when configuring CMake; it copies those bytes to the fixed application classpath resource name `honbako-extension-bridge.jar`. That bundle alias does not mean the baseline binary is compatible. The baseline lacks `image(String)`, `ImageResult`, and retained-fixture cleanup, and cannot satisfy the current `runBundledProof` diagnostic. `prepare_ios_runtime.py` requires the current v2 JAR to match its passing host proof before recording native staging inputs.

## Experimental host services

The bridge supplies in-memory Android preferences scoped by package path, selected source ID, configuration and preference namespace, a serial callback dispatcher, and an OkHttp host client. These preferences are not persistent credential storage. Network requests are restricted to `127.0.0.1`; redirects are disabled. The required Cloudflare interceptor slot is a loopback-only placeholder and implements **no** challenge handling. These classes are explicit test host services, not a complete Android API or a production iOS dispatcher.

The reference classes come from the published Suwayomi Server artifact, used strictly as a dependency archive. No server instance, database, native browser, or background service is started. The reduced dependency JAR is not a redistributable general extension runtime. Preserve and audit the included dependency notices before any distribution; no licensing or App Store clearance is asserted by this proof.

## Primary references

- [Komga's official Mihon integration](https://komga.org/docs/guides/mihon/).
- [Current published extension index](https://github.com/keiyoushi/extensions/blob/repo/repo.json).
- [Komga extension source](https://github.com/keiyoushi/extensions-source/tree/main/src/all/komga).
- [Suwayomi extension package implementation](https://github.com/Suwayomi/Suwayomi-Server/blob/master/server/src/main/kotlin/suwayomi/tachidesk/manga/impl/extension/Extension.kt).
- [OpenJDK Mobile native runtime](https://github.com/openjdk/mobile).

Native iOS embedding is a separate experiment in `ios/`; a successful host proof must not be described as successful iPhone execution.
