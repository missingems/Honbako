# Honbako

A personal manga library and reader for iPhone and iPad. Bundle identifier: `com.missingems.honbaku`.

Honbako starts with **Your First Chapter**, an original, fully bundled manga that teaches the reader's controls. It appears first while unfinished and stays removed if you choose to remove it. No external source lists or third-party manga are installed by default. Add your own files, connect a personal library server, or explicitly configure a provider you are authorized to use.

## Install the development build

Open the [Honbako download page](https://missingems.github.io/Honbako/install/) in Safari on a registered iPhone or iPad. It includes the Ad Hoc installer, direct IPA download, and an explicit **Add Source List** link. A fresh install includes only the original tutorial book; source installation remains an explicit choice.

The source catalog is available as a [raw JSON download](https://gist.githubusercontent.com/missingems/20e91aa1e2a3cbef0c61114801507196/raw/honbako.json). Add it in **Settings → Source Lists**, open **Honbako Sources**, then choose which sources to install.

## Development

Open `Aidoku.xcodeproj` and select the **Honbako** scheme. The internal reader target/module remains `Sumi` while the app identity is Honbako. Supply your Apple development team locally in the ignored `Aidoku/LocalSigning.xcconfig`; signing credentials are not part of this repository.

Use one shared DerivedData directory per checkout. Do not put build caches in this repository or temporary directories.

Source-package compatibility uses `SourceEngineVersion` (currently `0.9.0`) independently of Honbako's product version. Preserve that boundary when updating the reader engine.

The [Honbako Sources catalog](https://gist.github.com/missingems/20e91aa1e2a3cbef0c61114801507196), mirrored as `sources/honbako.json`, enables an independently written native MangaDex REST connector included in build 6 or later. It points only to Honbako and the provider's official API. It installs no downloaded executable and is enabled only after the user chooses **Add**. The native connector supports readable-chapter checks, author and publication metadata, translations, chapter pagination, ordered page lists, and vertical reading for Long Strip titles. Existing installed connectors keep their own source identities and reading records.

The older personal-device package catalog remains archived in `sources/personal.json` for compatibility with prior builds. Its packages are third-party implementations and are not represented as a native rewrite.

## Library and Search

The library shows saved books in Reading and Finished sections, omitting empty sections. Red glass badges show available unread chapters in the selected translation, without double-counting duplicate editions or locked chapters. Reading places the unfinished tutorial first, then prioritizes unread updates while keeping equal-priority books in their saved order. Finished books show their finished-reading dates. The automatic Popular section has been removed.

Search publishes complete, readable results as providers respond, grouped under pinned source headers. Each row puts its Ongoing or Finished publication status above the title, with available publication date, author, translation information, and saved reading position. Publication status is distinct from whether you have finished reading the book. Repeated queries reuse short-lived provider and metadata caches. A title from each provider keeps that provider's identity and reading progress.

The interface and bundled tutorial support English, Japanese, Simplified Chinese, and Traditional Chinese. Source-provided manga translations remain dependent on each title's available chapters.

There are no recommendation or Popular feeds, bundled suggestion lists, or scheduled catalog polls. The installer website is deployed separately from `site/`.

## Pro

Pro is designed for offline storage, chapter notifications, and iCloud progress sync. StoreKit transactions must be verified before Pro is enabled. App Store Connect must configure `com.missingems.honbaku.pro`; no prices or purchase success are fabricated. Background chapter checks are opportunistic: iOS controls execution and delivery timing. A newly enabled CloudKit store takes effect on the next app launch.

## Licensing and release status

The current app includes a GPLv3 reader engine. Required copyright, license, and provenance notices are retained in [LICENSE](LICENSE), [NOTICE](NOTICE), and the archived upstream documentation. The new native MangaDex connector was written independently against the provider's public REST schema; its catalog contains no extension executable. Honbako-specific changes began in October 2026. Honbako is not affiliated with Apple, its configured providers, or manga publishers.

An App Store or paid release is **not legally cleared** by this development build. Resolve the engine’s GPL distribution obligations, third-party package policies, and content/provider rights before distribution. See [release and rights notes](docs/RELEASE_AND_RIGHTS.md).
