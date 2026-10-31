# Original reviewer fixtures

Three real, pinned upstream servers with distinct original Honbako guides, plus a separate first-party Bookshop sample for the MCP exercise. No third-party manga, personal library, source account, or private MCP grant is included.

Current state: local-only preparation; no public hostname/tunnel has been created. All three real provider protocol probes pass. The opt-in native-adapter integration test has also passed for all three providers on the coordinated simulator run (1.491seconds): real auth/search/chapter enumeration, every original page hash, and cover decoding.

| Provider | Local endpoint | Original book | Access |
| --- | --- | --- | --- |
| Komga 1.29.2 | `http://127.0.0.1:39101` | Your Collections | Dedicated PAGE_STREAMING + USER account |
| Kavita 0.9.1.4 | `http://127.0.0.1:39102` | Read Your Way | Dedicated Pleb + Login + Read Only account |
| Suwayomi 2.4.2366 | `http://127.0.0.1:39104` | Search & Delete | Dedicated gateway credential; real backend on private port39103 |
| MCP exercise | Komga's separate original-sample library | The Bookshop Between Pages | Reviewer's own Apple-verified hosted workspace and OAuth consent |

Each guide has one real chapter with its original cover and four readable pages. Bookshop has its original cover and six story pages. Export uses unchanged `HonbakoGuideRenderer`, `HonbakoGuideBook`, `HonbakoJapanesePracticePage`, and the app's real English strings. Existing Bookshop assets retain their earlier provenance.

## Local preparation

1. Run `python3 Tools/reviewer-fixtures/download.py` once for missing upstream assets. Each asset must match its pinned release SHA256 before execution.
2. Export existing guide artwork with `export-guides.swift`, compiling it with the three renderer source files and installed Mac Catalyst UIKit frameworks. Output: `generated/assets`. This is a standalone native export, not an app build. Run `bash Tools/reviewer-fixtures/export-guides.sh` for the exact export command.
3. Run `python3 Tools/reviewer-fixtures/prepare.py` while the fixture servers are stopped. It packages original CBZs, configures only fixture directories, and creates private dedicated credentials.
4. Run `python3 Tools/reviewer-fixtures/run.py start --provider komga`, then likewise `kavita` and `suwayomi`.
5. Run `python3 Tools/reviewer-fixtures/bootstrap.py`, then `python3 Tools/reviewer-fixtures/run.py start --provider gateway`.
6. Run `python3 Tools/reviewer-fixtures/probe.py`. Inspect `AppStore/review/build73/reviewer-provider-probes.json`.
7. Coordinate a simulator build before adding `NativeProviderIntegrationTests.swift` to its test target. Set `HONBAKO_REVIEW_FIXTURE_ROOT` to this directory. It uses actual app source adapters, temporary uniquely named source preferences, restricted fixture accounts, exact page hashes, and image decoding. It does not install sources or modify CoreData.
8. Stop all owned fixture processes with `python3 Tools/reviewer-fixtures/run.py stop` when testing ends. Stops are graceful; no unrelated process or shared user database is touched.

`runtime/credentials.json` contains dedicated admin and reviewer credentials. It is ignored, mode0600, never printed by these scripts, and must never be committed. Admin credentials stay private. Only the dedicated reviewer values belong in App Store Connect's private review information after public hosting is approved and verified.

The ignored runtime currently retains approximately590MB of required official binaries/provider state; original exported assets and CBZs use approximately24MB. The Kavita download archive and throwaway exporter binary were removed. Do not remove the runtime while a review server is intended to remain available. It can be recreated from pinned releases after stopping it.

## Suwayomi scope

The gateway is explicit: it fronts real Suwayomi; it is not a substitute catalog or a mocked provider. Stable2.4.2366 exposes only single-admin authentication in its actual schema, despite newer multi-user wiki guidance. Therefore reviewers never receive its upstream credentials or JWT.

Only the exact five query templates in the current native source adapter are accepted. The gateway reconstructs its own trusted query and validates variables/known sample IDs; operation names alone grant nothing. Search/tag queries are additionally scoped to the sample manga. Only approved image paths are forwarded. Arbitrary GraphQL, a second operation, introspection, admin mutations, filesystem routes, unknown IDs, and upstream settings are rejected. HTTP workers, request sizes, response sizes, and request rates are bounded. No extension installation, server settings, filesystem browsing, or arbitrary forward proxy is available.

## Public hosting decision still required

These localhost addresses cannot be used by Apple remotely. Do not submit review notes with localhost or planned/unverified hostnames.

The user chose a separate AWS Free Plan VM; see `vm/AWS-checklist.md` for eligibility, credit expiry and the minimum4 GiB candidate. No public Mac tunnel will be created. See `vm/README.md`, `vm/cloud-init.yaml`, and the prepared installer/systemd/reverse-proxy configuration. A VM/account/IP is still required; none has been provisioned. Workers Free cannot execute the Java/.NET providers, and Cloudflare Containers requires Paid. Render Free sleeps and has ephemeral databases, so it is not the selected plan.

Before making public: reverify TLS, authentication, restricted accounts, every original cover/page, restart persistence, and denied privileged operations from outside this Mac. Then test the native app on cellular. Keep servers alive until review finishes; no pretend always-on claim.
