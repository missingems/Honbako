# Honbako native sources

## Independent MangaDex connector

Honbako build 6 introduces the first independently written native source: **MangaDex**, identified by honbako.mangadex. It uses Foundation HTTP/JSON requests against MangaDex's [public OpenAPI specification](https://api.mangadex.org/docs/api.yaml), currently version 5.13.1. It does not download a source executable or scrape the website.

The connector code is in Aidoku/Core/Sources/BuiltIn/HonbakoMangaDex/. It adapts the existing reader's Runner interface; the reader engine and previously imported connectors have not been rewritten by this change. Existing source IDs, saved manga, bookmarks and reading progress remain intact. Other connectors should be replaced only after independent implementations are tested.

## Catalog and installation

The first-party catalog is [sources/honbako.json](../sources/honbako.json). All its links point to Honbako's repository or MangaDex's official website/API.

The catalog entry contains nativeRunner: honbako.mangadex.rest.v1. The installer accepts only that exact runner ID, source ID honbako.mangadex, and supported descriptor version 1. It enables code already included in the app. A remote catalog cannot choose a class, executable or API host. Executable source packages cannot use the reserved honbako. namespace.

Adding a source list does not enable its sources automatically. Users choose Add for the source they want. Fresh installations remain empty. Older source catalogs are kept separately for compatibility with older app builds.

Native source configuration is persisted using a new custom-source discriminator; the existing discriminators and imported source storage are preserved. This is an additive source, not an automatic migration of existing manga.

## Reading behavior

- Search requests include author, artist, cover, publication year and status metadata.
- A separate one-chapter feed request confirms that a search result has a currently readable chapter in the chosen source languages. The probe is never stored as a complete chapter list.
- Feeds exclude empty-page, external-only, unavailable and future chapters. The client also checks returned records.
- Opening a title fetches its full filtered chapter collection with pagination. Excessive or inconsistent pagination raises an error rather than silently truncating a chapter collection.
- The Long Strip format tag selects vertical reading; ordinary manga uses right-to-left paging.
- Language switches use explicit request parameters without changing another reader's source preferences. Per-title translated-language metadata is authoritative and may contain codes beyond the catalog's reviewed language coverage.
- MangaDex language aliases are normalized for the interface and converted back for API calls, including Latin-American Spanish and simplified/traditional Chinese.
- Page resolution uses the public at-home endpoint and preserves the returned page order. HTTPS delivery and safe path components are required.
- Requests are paced at no more than four starts per second per connector instance. Rate-limit, permission and network failures are surfaced without automatic retry loops.

The API's language contract is a code grammar, not a finite enumerated list. A provider-wide language list does not establish that a particular title has that translation. This connector does not generate machine translations.

## Verification

The native unit suite covers complete search metadata with a separate real-chapter probe, metadata/probe caching, null language entries, regional aliases, explicit language isolation, unreadable chapter rejection, pagination, ordered secure page URLs, descriptor allowlisting, persisted native configuration, vertical-format routing and title-reported languages outside the reviewed catalog.

On 27 October 2026, the exact public search parameters used by the connector returned 20 English-language metadata results for a bounded test query, including creator and publication details. A filtered limit=1 feed returned one real English chapter with nine served pages; its at-home response supplied nine HTTPS image filenames. No chapter images were downloaded for this protocol check.

Source availability and translation coverage can change. This verification is not a promise that every series has readable chapters or every translation.

## Provider terms

An independently written connector does not grant rights to third-party manga, artwork or downloads. This implementation is a personal-client development feature. Review current provider terms before monetizing, distributing source-specific paid features or expanding its use.
