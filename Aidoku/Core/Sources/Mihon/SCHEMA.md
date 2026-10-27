# Mihon repository catalog protocol

Independent metadata parser written for Honbako on 27 October 2026. It parses catalogs; it does not install packages, authenticate a repository, or execute Android/Java extensions. No repository is preloaded or added to the app by these files.

## Verified primary definitions

- TachiyomiX index schema at revision `40d17ab3a2e70ee755f0f7b8d879ef1175391fd0`: [index/index.proto](https://github.com/mihonapp/tachiyomix/blob/40d17ab3a2e70ee755f0f7b8d879ef1175391fd0/index/index.proto). Upstream publishes [Apache](https://github.com/mihonapp/tachiyomix/blob/40d17ab3a2e70ee755f0f7b8d879ef1175391fd0/LICENSE-APACHE) and [MPL](https://github.com/mihonapp/tachiyomix/blob/40d17ab3a2e70ee755f0f7b8d879ef1175391fd0/LICENSE-MPL) license files. No upstream implementation or generated binding is copied here.
- Mihon revision `e588e04359fe1058206a2cbac1b01018ad787359`: [modern JSON/Protobuf mappings](https://github.com/mihonapp/mihon/blob/e588e04359fe1058206a2cbac1b01018ad787359/data/src/main/java/mihon/data/extension/model/NetworkExtensionStore.kt), [legacy JSON fields and resource paths](https://github.com/mihonapp/mihon/blob/e588e04359fe1058206a2cbac1b01018ad787359/data/src/main/java/mihon/data/extension/model/NetworkLegacyExtension.kt), and [store fetching/gzip behavior](https://github.com/mihonapp/mihon/blob/e588e04359fe1058206a2cbac1b01018ad787359/data/src/main/java/mihon/data/extension/service/ExtensionStoreService.kt). Mihon is [Apache-2.0](https://github.com/mihonapp/mihon/blob/e588e04359fe1058206a2cbac1b01018ad787359/LICENSE).
- Keiyoushi revision `6768cbc2049c5e07d67ea1ac667af73f9737596a`: [schema divergence](https://github.com/keiyoushi/extensions-source/blob/6768cbc2049c5e07d67ea1ac667af73f9737596a/.github/scripts/index.proto), adding `Resources.jarUrl` at field **501**. Its [publisher](https://github.com/keiyoushi/extensions-source/blob/6768cbc2049c5e07d67ea1ac667af73f9737596a/.github/scripts/publish-repo.py) emits JSON with `MessageToJson(always_print_fields_with_no_presence=False, preserving_proto_field_name=True)`: proto3 scalar/repeated defaults are omitted and signed-int64 values are strings. The parser accepts those defaults and numeric or quoted int64 values while still rejecting incomplete package names, API versions, build versions and artifact sets. That repository is [Apache-2.0](https://github.com/keiyoushi/extensions-source/blob/6768cbc2049c5e07d67ea1ac667af73f9737596a/LICENSE). No complete catalog, provider artwork, APK, or JAR is bundled in these parser tests.

Tests use synthetic `example.invalid` metadata and original wire fixtures following the published protocol. Parsing an APK URL or JAR URL is not a statement that either runtime is supported. Content-warning values from the catalog are metadata, and future unknown values remain unknown. A repository's signing-key string remains an unverified claim until a later installer authenticates actual packages and enforces key continuity.

## Supported metadata

- Legacy `index.min.json` arrays, with package name/version/language and per-source signed-int64 IDs, language, optional base URL and version ID.
- Modern JSON indexes and binary Protobuf `Index`, including inline `ExtensionList` and explicit follow-up `extensionListUrl`.
- Separate JSON or Protobuf `ExtensionList` resources through `parseExtensionList`.
- Optional gzip wrapping, validated by Apple's system zlib with both compressed and expanded payloads bounded to 16 MiB. Trailing/concatenated members are rejected.
- Unknown protobuf fields of varint, fixed64, bytes, and fixed32 wire types; malformed lengths, overflowing varints, invalid UTF-8 and unsupported group wire types fail instead of returning partial results.
- Exact signed 64-bit source IDs represented as decimal strings throughout; package versions and extension-library versions retain their separate meanings.
- Distinct APK and JAR resource descriptors. Legacy APK filenames resolve below `apk/` and icons below `icon/`; modern relative URLs resolve against the document that contains them.

Index, icon, artifact and extension-list URL resolution accepts HTTPS, plus HTTP on numeric IPv4 loopback, IPv6 loopback or `localhost` for local development. It rejects credentials, fragments, control characters and non-network schemes. Source home/mirror and human contact metadata may also use plain HTTP and anchors; preserving that metadata does not fetch it. A remote `extensionListUrl` is returned as a follow-up descriptor, never fetched automatically by the parser. A future network layer must bound redirects/requests, avoid sending repository credentials to another origin, verify HTTP success, and handle cancellation.

## Deliberate boundaries

Legacy `repo.json` metadata and its `index_v2` redirect are not fetched or migrated here. A future network/import flow must obtain that repository identity separately before asking users to trust or install a legacy package. A legacy catalog without `sources` retains an empty source array rather than inventing a runtime source ID.

There is no runtime-compatibility flag, install button, SourceManager mutation, persisted source-ID migration, or connection to the current library in this parser. The existing source engine compatibility check must not be used to infer Mihon extension-library compatibility. The separate native experiment has verified the published Komga JAR on a physical iPad mini; that evidence does not make every parsed catalog package compatible.
