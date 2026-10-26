# Honbako

A personal manga library and reader for iPhone and iPad. Bundle identifier: `com.missingems.honbaku`.

Honbako starts with an empty library and no installed source lists. Add your own files, connect a personal library server, or explicitly configure a provider you are authorized to use. Recommendations are discovery metadata and official publisher links; they do not install sources or add books to the library.

## Development

Open `Aidoku.xcodeproj` and select the **Honbako** scheme. The internal reader target/module remains `Sumi` while the app identity is Honbako. Supply your Apple development team locally in the ignored `Aidoku/LocalSigning.xcconfig`; signing credentials are not part of this repository.

Use one shared DerivedData directory per checkout. Do not put build caches in this repository or temporary directories.

## Recommendations

The bundled first list contains 19 editorial recommendations curated by GPT-6.1 Sol in the existing development session, without a model API call. A scheduled GitHub Action validates and publishes the static feed. Optional low-volume popularity observations and an explicitly requested Sonnet rerank have separate activation requirements. See [recommendation setup](docs/RECOMMENDATIONS.md).

## Pro

Pro is designed for offline storage, chapter notifications, and iCloud progress sync. StoreKit transactions must be verified before Pro is enabled. App Store Connect must configure `com.missingems.honbaku.pro`; no prices or purchase success are fabricated. Background chapter checks are opportunistic: iOS controls execution and delivery timing. A newly enabled CloudKit store takes effect on the next app launch.

## Licensing and release status

This implementation is a derivative of [Aidoku](https://github.com/Aidoku/Aidoku), used under GPLv3. Original copyright notices and the [full license](LICENSE) are retained; [UPSTREAM_README.md](UPSTREAM_README.md) records the upstream project. Honbako-specific changes began in October 2026. The app is not affiliated with or endorsed by Aidoku, Apple, or the publishers linked by recommendations.

An App Store or paid release is **not legally cleared** by this development build. Resolve the engine’s GPL distribution obligations, third-party package policies, and content/provider rights before distribution. See [release and rights notes](docs/RELEASE_AND_RIGHTS.md).
