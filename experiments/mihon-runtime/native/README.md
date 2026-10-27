# Experimental Java executor

`HBJavaExtensionExecutor` owns one Java VM on one serial, persistent `NSThread`
with an 8 MiB stack. Its Swift name is `JavaExtensionExecutor`. The public API is
`sharedExecutor()`, `execute(json:completion:)`, and `image(json:completion:)`.
Every completion is delivered asynchronously on the main queue. The executor
does not create UI, change the idle timer, or destroy the VM between requests.

The binary image completion contains `JavaImagePayload`: `data`, optional
`mediaType`, and optional `sha256`. Java supplies
`ExtensionBridge.image(String) -> ExtensionBridge.ImageResult`, whose public
fields are `byte[] data`, `String mediaType`, and `String sha256`. This entry
point is resolved lazily, so it is not required for JSON execution.

Request strings are limited to 524,288 UTF-16 code units, response strings to
4,194,304 units, images to 32 MiB, and the pending FIFO to 32 normal jobs. Diagnostic
cleanup has one reserved slot and coalesces up to 32 completion callbacks. Request and
response JSON must be objects. Limits are checked before allocating JNI strings,
copying returned strings, or allocating native image storage. Every operation
uses a JNI local frame; Java exception text is capped and secondary exceptions
are cleared. Startup failure is retained and future requests fail closed. An
already-existing VM is rejected instead of adopting an unknown configuration.

## Bundle contract

The executor accepts no VM options, classpath, resource-root URL, or remote
runtime inputs from callers. It uses only main-bundle resources and fixed VM
options. The consuming app must package:

- The verified combined JIMAGE at `lib/lib/modules`.
- The recorded portable time-zone database at `lib/lib/tzdb.dat`.
- Selected configuration at `lib/conf`.
- `honbako-extension-bridge.jar` and `komga-proof-dependencies.jar` at the bundle
  resource root. The first name is a bundle alias of the verified
  `honbako-extension-bridge-v2.jar`, not the historical baseline bridge.

The consuming executable must set `ENABLE_DEBUG_DYLIB=NO`. The static library's
CMake target exports its built-in JNI retention and symbol-export linker flags
as interface requirements, so they reach the executable. The Java module finder
fast path is disabled because the unchanged base image's generated graph covers
only `java.base`. The VM resolves `java.logging` and `java.xml` from the combined
image. No external module path or `java.home` override is used.

## Isolated diagnostics

`HONBAKO_JAVA_RUNTIME_DIAGNOSTICS=ON` exposes
`runBundledProof(completion:)` and adds the fixed `RuntimeProbe.jar` to the
classpath. It runs `RuntimeProbe.run()` and
`KomgaDeviceProbe.run(mainBundleResourcePath)` on the same VM worker. That probe
also requires its published Komga extension JAR and four original fixture images
as prepared by the parent experiment. The diagnostic method and extra classpath
entry are absent when the flag is off.

Diagnostics also set the fixed `honbako.probe.keepFixture=true` option so the
probe can retain its loopback fixture for subsequent calls to the public JSON
and binary image methods. Call `endBundledProof(completion:)` after those checks,
including on failure. It invokes only `KomgaDeviceProbe.closeRetainedFixture()`
on the owning worker; the VM remains alive.

The consuming diagnostic app has verified this wrapper on a physical iPad mini:
three direct page-byte transfers, one cover transfer, two repeated JSON calls,
fixture cleanup, and auto-lock restoration all pass. Evidence is in
`../proofs/ios-native-executor-result.json`. The production source registry and
public networking are still separate integration work.
