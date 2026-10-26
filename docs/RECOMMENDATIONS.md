# Recommendation feed

Honbako ships a 19-title editorial seed curated with **GPT-6.1 Sol**, with **zero paid API calls**. Titles and creator credits were checked against the official VIZ series URLs embedded in `recommendations/seed.json` on 2026-10-26. The short recommendation notes are original editorial writing, not copied publisher synopses. The initial order is editorial, not a popularity chart. Unknown publication years and serialization states are explicitly `null` / `unknown`.

`recommendations/public/recommendations.json` is the deployable feed. The app should bundle `recommendations/seed.json` and use it when a validated remote feed is unavailable. The expected unauthenticated endpoint is:

```
https://missingems.github.io/Honbako/recommendations.json
```

The repository may remain private. GitHub Pages publishes only `recommendations/public/`, not the repository. **Never embed a GitHub token, Anthropic key, or private GitHub raw-file URL in the app.** If the Pages endpoint requires authentication, the app must fall back to its bundled seed.

## What is fetched

The optional updater makes one bounded Open Library Search API request per run: `q=subject:manga`, `sort=trending`, `limit=100`, requesting only `key,title,author_name,trending_z_score`. There are no automatic retries, pagination, chapter requests, cover downloads, scans, or user reading-history requests. The daily workflow caches the resulting feed in the repository and publishes that same file for all app users.

Only series already in the reviewed seed may be selected. Matching requires a normalized series title (or a limited volume-number suffix) plus a matching creator name. Multiple volumes collapse into one series, retaining the first matching upstream rank. Unreviewed titles, adult entries outside the catalog, malformed records, nonpositive scores, and unsupported title suffixes are ignored. This narrow catalog avoids relying on Open Library subject tags as an adult-content filter. The seed includes teen action and romance; it is not a child-age-rating certification. Publisher age ratings and regional availability still apply.

An observed `popularity.rank` is the result position in that one bounded Open Library manga query, **not** a worldwide manga sales rank. `popularity.value` is the actual observed `trending_z_score`; it is never fabricated. The score measures changes in Open Library interest, including page views and reading-log events. It does not measure legal availability, chapter freshness, sales, or quality. Unmatched seed entries keep their editorial provenance. If no reviewed titles have positive observed scores, the prior feed and its timestamp are retained.

The publisher series links are manually reviewed; neither Open Library nor the optional model can supply new destination URLs. The current catalog includes no cover images. Using factual metadata or linking a publisher is not a license to reproduce its artwork or chapters.

## Provider terms and activation

Open Library says catalog contributions are requested under CC0 and donated catalog data is in the public domain, while its licensing page cautions that pre-existing rights may exist in particular contributions or jurisdictions. Its current API guidelines prioritize human-facing, low-volume discovery, require efficient caching, and disallow using it as high-traffic commercial infrastructure. This implementation is an opt-in, one-request daily metadata cache, not a claim of blanket commercial clearance.

Before enabling fetching for a commercial product, review the current usage guidelines and register/contact Open Library as appropriate. Keep fetching disabled if the intended use is outside those guidelines; a licensed metadata provider can replace it later without changing the app schema. MangaDex is deliberately **not** integrated because its API policy restricts paid services and ads, which conflicts with Honbako's planned Pro features.

Repository Settings → Secrets and variables → Actions → **Variables**:

| Name | Value | Default behavior |
| --- | --- | --- |
| `OPEN_LIBRARY_ENABLED` | Exact string `true`, after provider-use review | Unset: validate and republish the existing editorial feed; no metadata API calls |
| `OPEN_LIBRARY_CONTACT` | A real maintainer contact email | Required when fetching; sent as User-Agent contact and `email` header |
| `ANTHROPIC_MODEL` | Explicit supported Claude Sonnet model ID | Unset: keep deterministic order |

The updater does not invent a contact address. API errors keep the last validated feed. Schema violations fail the run without replacing the existing file.

## Optional Sonnet curation

Add repository Actions **secret** `ANTHROPIC_API_KEY` when ready. Adding the secret alone makes no paid requests. Run **Refresh recommendations** manually on `main`, explicitly checking **Permit one paid Sonnet reorder**. Scheduled runs never call Sonnet.

The optional request uses the Anthropic Messages API with a JSON-schema output of `{ "ids": [ ... ] }`. It sends only the reviewed public catalog, original reasons and observed signals; it sends no app user data. The response must contain every candidate ID exactly once and no extra fields. Only ordering can change: titles, authors, links, reasons and observed scores are taken unchanged from the validated candidates. Refusals, truncation, malformed JSON, unknown/duplicate/missing IDs, API errors and missing keys fall back to deterministic order. At most one paid request is attempted, with a fixed output-token limit and no retries. `--dry-run` always disables Sonnet even when a key and flag are present.

Choose a currently supported model ID from Anthropic's documentation rather than assuming an alias will remain available. The first seed remains attributed to Sol; subsequent successful Sonnet reranks add their actual configured model to curation provenance. No live Sonnet request was made while implementing this feature.

## GitHub Actions and Pages

`.github/workflows/recommendations.yml` runs daily at **01:17 UTC** and supports manual dispatch. It only runs against `main`, runs offline checks, optionally refreshes the metadata, validates the feed, commits changes to `main`, and checks Pages configuration. It deploys only the `recommendations/public` directory when Pages is enabled with `build_type=workflow`.

1. Enable Actions for this repository and allow its workflow token to write repository contents. Branch protections must permit the workflow's feed commit, or change the commit step to a reviewed PR process.
2. Confirm the GitHub account plan supports Pages for private repositories. GitHub documents private-repository Pages for Pro, Team and Enterprise plans. Keep the repository private if the current plan does not support it; the app's bundled seed still works.
3. Repository Settings → Pages → Build and deployment → Source: **GitHub Actions**. Enable the `github-pages` environment and allow `main` deployments.
4. Dispatch **Refresh recommendations** with the Sonnet box unchecked. Confirm the deployment and open the public feed URL without GitHub authentication.
5. Enable the optional provider variables only after the usage review above.

When Pages is absent, unsupported, or configured for branch builds, the workflow records a notice and skips deployment while retaining the committed feed. It does not automatically change repository visibility, billing, Pages access rules, branch protections or API secrets. GitHub's normal schedule timing can vary, and scheduled workflows may be disabled by GitHub after prolonged repository inactivity.

## Schema v1

The root contains `schemaVersion` (integer `1`), `generatedAt` (UTC ISO-8601), `source` (`name`, `url`, `attribution`), `curation` (`method`, provenance fields, `sourceURLs`) and `items` (maximum 25). Unknown optional values are represented as `null` or omitted where documented.

Each item has:

| Field | Type / meaning |
| --- | --- |
| `id` | Stable `honbako:<series-slug>` string; stable across volumes and reranks |
| `title` | Reviewed series title |
| `authors` | Array of credited creators, including artists when applicable |
| `year` | Integer or `null`; series start year only when verified |
| `status` | `unknown`, `ongoing`, `completed`, `hiatus`, `cancelled` |
| `coverURL` | `null` in v1; artwork reuse rights have not been obtained |
| `officialURL` | Reviewed HTTPS publisher series page |
| `searchQuery` | Plain series title for searching the app's installed sources |
| `reason` | Original short editorial recommendation |
| `popularity.source` | `Honbako editorial seed` or `Open Library` |
| `popularity.metric` | `editorial-selection` or `trending_z_score` |
| `popularity.rank` | Observed upstream bounded-query result position, or `null` |
| `popularity.observedAt` | UTC time of observation, or `null` for editorial picks |
| `popularity.value` | Optional finite observed trending score |
| `popularity.sourceURL` | Optional Open Library work metadata page; never a reader URL |

Clients should ignore unknown root/provenance fields, reject unsupported schema versions, limit downloads, validate URLs, and retain the previous cached or bundled feed when a remote response fails validation. Recommendation entries are discovery metadata, not installed source IDs or a promise that a particular source carries a title.

## Local verification

From the repository root, with Python 3.10 or newer:

```sh
python3 -m unittest discover -s scripts -p 'test_recommendations.py' -v
python3 scripts/update_recommendations.py --fixture scripts/fixtures/open_library.json --dry-run
python3 scripts/update_recommendations.py --validate-only
```

The fixture is synthetic and makes no real popularity claim. Tests mock the paid API and verify opt-in gating, strict reordering, malformed-response fallback, title/author matching, deduplication, unreviewed-content rejection, and forbidden image/chapter URLs. No third-party packages are required. `--dry-run` does not write files; omit `--fetch-open-library` for completely offline operation.

Implementation verification on 2026-10-26: all nine offline checks passed; fixture dry-run and public-feed validation passed. A bounded live Open Library metadata response was also checked against the parser: the response format and positive-score matching worked, with one reviewed series matched in that snapshot. The initial seed remains editorial and does not inherit those temporary observations. GitHub Actions execution and public Pages deployment are checked separately after the initial push.

Repository configuration on 2026-10-26: the maintainer supplied a public request contact, metadata polling is enabled, Pages uses GitHub Actions, and the optional Anthropic key is stored only as an Actions secret. `ANTHROPIC_MODEL` is `claude-sonnet-5-5`, verified against the [official Sonnet model page](https://platform.claude.com/docs/en/models/sonnet-5-5/overview). No paid inference request has been made; scheduled refreshes continue to use deterministic ordering.

## Primary references checked 2026-10-26

- [Open Library catalog ownership and CC0 contributions](https://openlibrary.org/help/faq/using)
- [Open Library licensing caveats](https://openlibrary.org/developers/licensing)
- [Open Library API usage guidelines and request limits](https://openlibrary.org/developers/api)
- [Open Library Search API](https://openlibrary.org/dev/docs/api/search)
- [Open Library's trending algorithm and supported search sort](https://blog.openlibrary.org/2025/08/06/whats-trending-on-open-library/)
- [MangaDex's own published API policy](https://gitlab.com/mangadex-pub/mangadex-api-docs/-/blob/main/index.md)
- [Anthropic structured-output request and response format](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)
- [GitHub Pages private-repository plan availability](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)
- [GitHub Pages custom workflow requirements](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)

Each seed item carries its verified official VIZ series page as its factual metadata reference. Publisher pages were read for verification during curation; they are not automatically scraped by the updater.
