# Hosted Honbako companion

This adapter hosts the existing eight metadata tools plus two explicitly enabled page-coaching tools and paired-phone API in one SQLite-backed Cloudflare Durable Object. The phone talks directly to hosted HTTPS; the Mac is not required after cutover. Honbako still syncs and processes jobs only while the app is open in the foreground. Offline reading metadata is explicitly last known. Public hosting alone does not grant an agent page access. Pairing with Reading Access enabled shares the current manga page automatically. No per-book confirmation or sharing timer is required. No model subscription, new manga source, or unapproved import is supplied.

No deployment is performed by the test suite or these files. Use only an existing Workers Free account and SQLite-backed Durable Objects for this setup. Do not accept an upgrade or enable paid features. Availability and quota must be verified in the account before deployment; a successful login or dry run does not prove the account is on a free plan. Workers Free quota exhaustion should fail requests rather than authorize spending.

## Current deployment checkpoint — 30 October 2026

The isolated managed Sandbox beta is now active at `https://honbako-mcp-pro-preview.jun-19c.workers.dev/remote`; its AI endpoint is `/remote/mcp`. Explicit Sandbox build60 is installed and the owner confirmed the Duo connected. Production paid enrollment remains disabled. See the activated-beta checkpoint below for the verified versions and credential separation.

The public service is deployed at `https://honbako-mcp.jun-19c.workers.dev`; AI clients use `/mcp`, while the phone uses the base address. The signed-in account’s dashboard confirmed Workers Free before deployment, with no plan upgrade. The private admin Worker has no public route.

The stopped Mac companion’s final snapshot was imported and compared exactly: two existing device identities, 68 jobs, and no pending jobs. The original Grok credential hash and absolute expiry were restored unchanged. The user reported updating Grok’s endpoint. **The phone cutover remains unverified:** its hosted snapshot still predates import, and the phone reported that destination verification failed. Keep the original pairing and old local writer stopped while diagnosing; do not disconnect/re-pair or overwrite hosted state with the old backup. Build 52 adds sanitized HTTP/network diagnostics to identify the failure.

## Configuration and secrets

The public Worker configuration is `wrangler.jsonc`. Set `PUBLIC_ORIGIN` to the reviewed HTTPS origin before deployment. Keep `OWNER_NAME` stable: changing it selects a different, empty owner object. Use the same name in the private admin configuration. The checked-in origin matches the current deployed public service.

Provision two independent, random, owner-controlled secrets through Cloudflare's secret store, never Git, shell arguments, logs, screenshots or the public connector:

- `PAIRING_KEY`: stable random32-byte base64url key for hashing one-time pairing codes. Device credentials are independently random, hashed in SQLite and retained on the phone in Keychain.
- `ADMIN_KEY`: different random32-byte base64url key for private administrative RPC. The public HTTP router never accepts this key for MCP or device operations.

A Grok grant is a third independent random credential issued through the private admin channel. During the approved cutover, its existing token hash and original times can instead be restored through the private `restore-grant` action; the plaintext credential is never sent to this action. Only its SHA256 hash is retained by the server. Grants expire at the recorded absolute time, at most24hours after issuance, including across restarts. Issuing a new grant invalidates the old one immediately. Revocation blocks later requests; it does not undo jobs already submitted or phone-approved imports. The phone never receives the Grok key and Grok never receives the phone or administrator key.

`observability.enabled` is false to avoid request logging. Do not enable header/body logging or log private admin responses. The adapter returns sanitized errors. Last device snapshots remain until the owner forgets/disconnects that device. Terminal job metadata is capped at2000 jobs; pending jobs are retained until completed, rejected or cancelled. No time-based pruning was introduced.

## Public and private routes

Public HTTPS permits only authenticated `POST /mcp`, one-time-code `POST /api/pair`, and the exact existing paired-device state/job/disconnect routes. All `/api/admin/*`, health/admin aliases and arbitrary paths return404, including requests with the owner key. Wrong methods fail, browser Origin headers are rejected, query credentials are not accepted, and JSON bodies/responses are bounded. Pairing has durable limits of10attempts/IP/10minutes and30attempts globally/10minutes; general requests also have bounded IP/global limits, counted in memory (see Surge protection below).

The admin Worker in `wrangler.admin.jsonc` has no routes, workers.dev URL or preview URL. It binds the public Worker's Durable Object class and accepts administrative operations only through an account-owned service binding plus the administrator key. Do not add a public admin route as a shortcut.

For operator access, run the local facade with the reviewed Wrangler installation:

```sh
wrangler dev --config cloudflare/wrangler.local-admin.jsonc
```

Its service binding targets the deployed nonpublic admin Worker with `remote: true`; Wrangler uses the operator's authenticated Cloudflare account. The facade binds127.0.0.1:8789 and rejects remote hosts and browser Origin headers. Cloudflare Durable Object bindings themselves must not use `remote: true`; the remote service binding is the supported bridge.

Create an owner-only credential file outside the repository containing the `adminKey` field. Invoke `cloudflare/admin-cli.js status --credential-file /private/path/admin.json` to inspect nonsecret status. `pair`, `grant` and `export` require `--output` pointing to a new private file. The CLI never prints pairing codes or grant tokens. `grant --lifetime-seconds 3600` requests a shorter one-hour grant; the maximum is86400seconds. `revoke` invalidates the current Grok grant. For cutover, `restore-grant --input /private/path/grant-hash.json` accepts only `tokenHash`, `createdAt`, `expiresAt`, and optional `revokedAt`. It requires a currently unexpired original lifetime of at most24hours and an empty grant or an identical existing record. It cannot extend expiry, rotate a different existing grant, or undo revocation. Imported/exported state files are private even though phone credentials are hashes rather than plaintext.

## Preserving pending work during cutover

Fixture tests cover two unclaimed approval jobs containing20and10 books. The deployed migration currently has no pending jobs. Any migration must preserve device IDs, device token hashes, job IDs, source/book IDs, statuses and idempotency keys. Re-pairing the phone creates a new device ID and clears its local receipts, so re-pairing is unsuitable for this cutover.

1. Prepare and validate the phone's endpoint-change update. It must retain its current Keychain device ID/token and pending receipt/outbox state, and verify the hosted server recognizes that identity before committing the new endpoint. Do not disconnect or re-pair.
2. Stop/quiesce the local writer and its public gateway/tunnel as a coordinated, owner-approved cutover. Do not copy state into two writable live companions. Keep a private rollback copy.
3. After the old writer is stopped, create the final migration snapshot with `node cloudflare/admin-cli.js export-local --state-dir /private/path/HonbakoMCP --output /private/path/migration.json`. This verifies the source writer lock is absent or its recorded process has stopped, reads the existing atomic state file, validates it, clears any obsolete one-time pairing code, and writes a new0600 file. It does not copy the owner's local MCP key or Grok grant. The CLI refuses export while the source writer is running.
4. Through the private Wrangler facade, import into a new empty hosted owner object with `node cloudflare/admin-cli.js import --credential-file /private/path/admin.json --input /private/path/migration.json`. The import validates checksum/schema/identities, rejects executing claimed work, and commits the state and migration record in one SQLite transaction. It never reclaims or approves an import. Repeat import is rejected instead of overwriting newer hosted state. If the response is lost after commit, the CLI queries the private status and recognizes the same immutable migration checksum without repeating or overwriting the import.
5. Verify the hosted owner reports both devices, the exact job IDs, any unclaimed batches present in the final export, and that the current phone token still authenticates. Switch the phone's endpoint while preserving its identity. Confirm a fresh hosted snapshot and the same pending approvals.
6. Restore only the existing Grok credential hash and its unchanged original absolute expiry through the private admin channel, then update only the connector endpoint. Never copy the local owner MCP key. If the grant has already expired, issue a new short-lived grant instead and use the secure credential field. Verify the actual ten-tool list/status and approval queue. Approve remaining books on the phone only after their exact IDs are reviewed.
7. Keep the old companion stopped. A rollback after the hosted server has accepted writes requires a fresh consistent hosted export, not an old local backup. Never run both authorities with the same phone identity.

The private migration mechanism rejects imports into a nonempty host and any still-executing claimed job. It does not remotely stop a Mac process; the operator must perform and verify step2 before the final export/import. The administrator key can export personal reading/library metadata, so keep the local facade and its credential file private, and remove private snapshot/code/grant files after their use.

## Validation

From `Tools/HonbakoMCP`, run:

```sh
npm run check
npm test
node --test --test-concurrency=1 cloudflare/test/*.test.js
```

The focused tests use Node's actual in-memory SQLite database and the installed MCP SDK. They cover state survival after reopening the store, transactional rollback, exact8-tool compatibility, all credential boundaries, grant expiry/revocation/restoration, durable pairing limits, public admin rejection, stopped-source export and lost-response recovery, and migration of30unclaimed books. A Wrangler dry run and local workerd integration must also pass before deployment. Neither local tests nor dry runs authorize a production deployment or paid account changes. The standalone `integration-workerd.js` harness runs public and private dry-run bundles in actual local workerd, exercises the private admin service binding and official MCP client, imports fixture approval batches, and disposes/reopens the persisted runtime. Set `HONBAKO_WRANGLER_ROOT` to an existing official Wrangler package directory before running it; it installs no dependencies and deploys nothing. It uses only fixture secrets/state and removes its temporary bundle and SQLite folders in `finally`. The cached Miniflare5 beta requires inline bundle contents and the current `resourcePersistencePath` option; its legacy scriptPath/persistence conversion was insufficient. The passing integration covers8tools, asynchronous search/approval/import, idempotent retry, restart survival, and30remaining fixture books with unchanged device/job IDs.

Primary platform documentation:

- [SQLite Durable Object storage and transactions](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/)
- [Durable Object initialization/concurrency](https://developers.cloudflare.com/durable-objects/api/state/)
- [Workers local development and remote service bindings](https://developers.cloudflare.com/workers/local-development/)
- [SQLite Durable Object limits and Free availability](https://developers.cloudflare.com/durable-objects/platform/limits/)
- [Workers filesystem is temporary memory storage](https://developers.cloudflare.com/workers/runtime-apis/nodejs/fs/)

The adapter does not use filesystem persistence in Workers. Each device/job is stored in a separate bounded SQLite row, so growing job history does not hit the per-row limit for a single whole-state JSON value.

## Temporary page coaching wire contract

Permission follows the paired MCP connection and its Reading Access setting. The phone publishes the original current canonical manga page while its reader is foregrounded; no Start/Stop action or sharing timer is involved. It never captures the whole phone window, another app, camera content, or future/offscreen pages. Closing a book or suspending the app leaves the last shared page available, explicitly labelled last_shared. Private reading, Reading Access off, and disconnection revoke the page stream. An open connected reader can automatically publish again after a bridge restart.

Phone APIs use the existing paired-device bearer; Grok/administrator credentials cannot call them:

- `POST /api/device/coaching`: `{sessionId: UUID, pageGeneration: Int>=1, accessMode: "connection", page: {...}, image: {...}}`. `page` requires `pageId: UUID`, `contentHash: lowercase SHA256 of the actual JPEG bytes`, `sourceId`, `mangaId`, `title`, `chapterId`, `chapterTitle`, `page: Int>=1`, and `capturedAt: ISO`; optional `chapterNumber` (number/string), `totalPages`, `lastVisiblePage`. `image` is `{mimeType: "image/jpeg", data: standard-base64, width: Int1...4096, height: Int1...4096}`; decoded bytes are at most350KiB. A new connection page stream begins at pageGeneration1. Each page change uses a new pageId and higher generation. Equal-generation heartbeats can only refresh capturedAt for exactly the same page/image. Older generations and equal-generation changed pixels/identity are409. Connection streams return accessMode:"connection" and expiresAt:null; they remain available until revoked or disconnected. Older clients may still send only an explicit expiresAt and retain their original fixed ten-minute consent; an existing stream cannot change modes.
- `GET /api/device/coaching`: returns `{active, sessionId?, pageGeneration?, pageId?, contentHash?, capturedAt?, expiresAt?, observation:"last_shared", page?, annotationRevision, annotations, lastAnnotator?, spoilerBoundary?}`. `active` means an unexpired sharing grant, not a live phone screen. Responses include device freshness when available. Poll only during the user-started session while the reader is foregrounded. Apply marks only to the exact current session/generation/page/hash and a newer annotationRevision.
- `POST /api/device/coaching/pause {sessionId,pageGeneration,pageId?}`: mark background/pause without erasing an already approved cached page. The expected generation/page must still match; a late pause is409. Resuming with a higher generation on the exact same page/image preserves background drawings and their revision; a different page/image clears them. There is no background capture.
- `POST /api/device/coaching/revoke {sessionId}`: immediately erase pixels/page metadata/drafts, retaining only a small closed-session tombstone. This blocks a late in-flight publish from resurrecting revoked access. Clear local access immediately even if the network is unavailable; when the companion cannot be reached, report that remote removal has not been confirmed.

Agent tools:

- `honbako_get_coaching_page({deviceId?})` returns one MCP `ImageContent` block plus structured exact page/session/generation/hash, capturedAt, fixed expiry, revision, and a spoiler boundary restricted to that shared page. It labels pixels `last_shared` even if recently captured. An approved cached page remains available while the phone is backgrounded/offline until revoke/expiry. It returns `page_not_shared` when no approved image exists.
- `honbako_annotate_page({deviceId?,sessionId,pageGeneration,pageId,contentHash,baseRevision,annotations})` replaces the temporary draft atomically. Every identity must match and baseRevision must equal the current revision; stale replies are409. At most24 uniquely identified annotations. Supported normalized finite0...1 shapes: `box {rect:{x,y,width,height}}`, `arrow {from:{x,y},to:{x,y}}`, `label {rect,text<=280characters}`, and `stroke {points:[{x,y},...]}` (2...128points). Every shape has `id` (1...64ASCII letters/digits/underscore/hyphen) and optional color `yellow|blue|green|pink`. Rectangles must remain inside the page. Labels render as plain text; no HTML, JavaScript, external URLs, or remote image overlays are accepted.

Local page bytes never enter state.json, snapshots, library jobs, or migration exports. A separate0600 coaching-tombstones.json contains only closed session UUID metadata, so a Mac bridge restart loses images and returns reason restart; old in-flight publishes cannot reopen that consent. The connected foreground reader automatically opens a new stream after a restart. Hosted bytes use a separate bounded SQLite table, one current image per device and at most8 active images per owner; Connection streams have no sharing expiry; disconnection or revocation erases their image and drafts. Durable Object alarms retain fixed-expiry cleanup for older timed clients. Closed-session tombstones contain no image or title. Forgetting a device clears its coaching row too. Existing Grok credential expiry/revocation still gates both tools.

MCP carries tool calls and results, not a voice call or an LLM subscription. The connected voice agent must actually invoke the image/drawing tools. The protocol and local official SDK tests support image blocks; Grok Bot voice-mode ingestion of those blocks must be verified separately with an owned fixture before promising hands-free visual coaching.


## Per-user remote MCP with Pro — deployed, enrollment disabled

The new `/remote` routes are separate from the existing private owner pilot. They remain disabled unless `REMOTE_MCP_ENABLED=YES` and the required bindings/secrets are configured. Existing owner state, Grok grant and original expiry are unchanged. The prepared production config adds the per-user storage bindings with public enrollment explicitly disabled; that code/storage deployment was approved and completed on 30 October 2026, with public enrollment still disabled. `wrangler.remote.jsonc` is the separate Sandbox beta configuration described below; do not use it as a production migration command.

The iOS flow is **Enable MCP Server → Connect Your AI → approve access**. The app creates a private installation identity in Keychain and sends a verified StoreKit JWS to the fixed Honbako service. No server-address or pairing-code fields are used for managed remote enrollment. Local Mac connections remain free through the existing companion screen; their setup is not automatic in this change.

The server uses Apple’s official App Store Server Library 3.1.0 with Apple Root CA G3, certificate/signature/online revocation verification, the exact bundle/product/environment and a fresh App Store Server API subscription status. A locally cached `hasPro`, personal-build flag, test receipt, expired purchase or revoked purchase cannot grant production hosting. Subscription checks are cached for at most 15 minutes and never beyond purchase expiry. Apple service outages fail closed when that verification lease expires. Production and Sandbox must be separate deployments/identities; never switch a production namespace to Sandbox.

Required deployment secrets are `APP_STORE_PRIVATE_KEY`, `APP_STORE_KEY_ID`, `APP_STORE_ISSUER_ID` (an authorized Apple In-App Purchase/App Store Server API key) and an independent random `REMOTE_ROUTING_KEY`. The default environment is Production. Do not put credentials in the repository, app bundle, logs or browser/chat text. Apple’s dependency initializes randomness on import, so the server imports it lazily inside a request handler for Workers compatibility.

A private workspace belongs to a Pro purchase, proven with Apple's signed transaction, never to a client-supplied account ID or a shared secret. Up to five of the purchaser's devices share it, each with its own installation credential; a Family Sharing member gets a separate workspace of their own (see `SHARED-WORKSPACE-PLAN.md`). Different purchases are never merged. The private keychain identity survives normal disconnect/reconnect. Rotating the routing secret requires re-enrollment with the same installation identity and valid purchase proof. Existing workspace data remains isolated.

AI clients use OAuth authorization-code flow with exact registered HTTPS callbacks, `resource` audience checking, S256 PKCE, a five-minute pending request, an original-browser cookie, explicit phone approval, single-use codes, 15-minute access tokens and rotating refresh tokens. Reuse of a recently spent refresh token revokes its token family. Route MACs reject arbitrary namespace IDs before allocating objects. Each workspace allows up to 16 AI connections and 2,000 MCP calls per UTC day / 120 per minute. Ordinary HTTP/phone limits and body/response bounds still apply. This is a personal-use service, not unlimited model hosting.

Connected assistants retain no access after a successful phone disconnect. The disconnect removes shared snapshots, jobs, images and annotations; minimal hashed installation/purchase binding records remain to prevent takeover and excessive registrations. Failed offline disconnects cannot confirm server deletion. There is no automatic 30-day deletion policy in this implementation. Before public release, complete reliable offline deletion/revocation recovery and user-facing connection management, update App Store privacy disclosures for hosted retention, configure real Apple credentials, verify a real purchase and refund, and test each provider’s actual OAuth connector. Unit/local-runtime tests are not a claim that Grok voice has consumed an image or that ChatGPT/Claude provider approval has completed.

The current phone transport still polls jobs and annotations; it has not been load-tested for 10,000 active users. Replace idle polling with event-driven delivery and measure CPU, row writes and concurrency before assigning a 10,000-user hosting budget. The user’s existing free-only hosting constraint remains in force; no paid plan or App Store subscription price was changed.

Verification: `npm test`, `npm run check`, and the local-only `integration-remote-workerd.js` using the same installed Wrangler path as `integration-workerd.js`. The integration harness creates fixture-only identities in local workerd, checks OAuth + all ten tools + isolation + restart + refresh + disconnect, and removes its own temporary runtime files. Its fixture entry is generated only in a temporary directory and is never a deployed entrypoint.


### Apple credential setup — 30 October 2026

The owner-supplied replacement purchase key is securely backed up outside the repository with owner-only permissions. Its private key, key ID, issuer ID and a separate routing secret are configured as encrypted secrets on the existing `honbako-mcp` worker. The temporary upload file was removed. No private key is in the app, repository, command arguments or logs.

A bounded, read-only TEST-notification history query authenticated successfully against Apple Sandbox (HTTP 200). Production returns HTTP 401. App Store Connect confirms Honbako 0.1.0 is `PREPARE_FOR_SUBMISSION`; Apple's commerce engineer states production API access remains locked until a production release: https://developer.apple.com/forums/thread/806452 . No sandbox fallback was added to the production paid-access gate.

Automatic approval review rejected deploying the prepared code and new storage bindings to the existing live worker because this production change could disrupt the private pilot without explicit deployment approval. Secret configuration succeeded, but the new code/storage deployment and private cloud-side verification remain pending. Public managed enrollment remains off. Existing device identities, migration fingerprint and original Grok expiry/revocation were checked before and after secret configuration and remained unchanged. The private local admin facade was stopped afterward. Workers remains on Free; no price, billing upgrade or new assistant grant was made.

The prepared `verify-apple` action is reachable only through the account-owned private admin binding plus the existing owner credential; it has no public HTTP route. It returns sanitized authentication status only. Local workerd tests verify wrong-owner rejection, missing-key failure and preservation of the original bridge workflow. `verify-apple-key.js` is a local read-only preflight that never prints keys, signed authorization tokens or notification contents.


### Approved deployment verification — 30 October 2026

After explicit deployment approval, the production worker and private admin update were deployed. The current main worker version is `49a77e49-9b5b-4102-8325-1ac1985a3f7b`; the private admin version is `fd9a9cfa-06c7-4066-805e-2e4f5852d1d8`. The existing owner namespace remains intact and two additive per-user namespaces are bound. `REMOTE_MCP_ENABLED` remains `NO`.

Live private checks from Cloudflare authenticate successfully with Apple Sandbox (HTTP 200). Production returns the expected pre-release HTTP 401. The official Apple SDK retains all certificate, signature and OCSP verification. Its `node-fetch` dependency is mapped to a small native Workers transport for compatibility, with bounded requests, manual redirect rejection, and the legacy binary `buffer()` interface needed by OCSP. No certificate check was disabled. Local workerd fixtures verify signed outbound Apple requests and binary OCSP transport in addition to OAuth/tenant isolation; 70 Node checks pass.

After deployment, the same two device identities, migration fingerprint, Grok expiry and revocation state were preserved. The existing authenticated MCP client successfully initializes, lists all ten tools and reads its two-device status without receiving a new credential. Public enrollment returns 503, unauthenticated MCP returns 401 and public administrator routes remain 404. The private admin service still has no public route. The temporary local admin facade was stopped after verification. Workers remains on Free, and no subscription price or billing plan was changed.


### Isolated remote beta prepared — 30 October 2026

Apple’s read-only test-history preflight still authenticates in Sandbox (200), while Production returns401 and Honbako remains Prepare for Submission. The deployed production endpoint still returns503 because its enrollment switch remains off.

The separate `wrangler.remote.jsonc` now prepares `honbako-mcp-pro-preview` with Sandbox verification and fresh SQLite workspace/OAuth namespaces. It has no owner-pilot binding and exposes no legacy pairing, legacy MCP, or administrator routes. `remote-beta.js` fails closed unless the configured Apple environment is exactly Sandbox. This is a prepared deployment, not evidence that it has been published or enabled.

Builds explicitly setting `HONBAKO_REMOTE_MCP_ENVIRONMENT=Sandbox` select the fixed beta origin and an independent Keychain installation identity. Other builds default to the production origin and preserve its original identity account. Beta and production transactions are never accepted interchangeably. A real Apple-verified active Sandbox Pro transaction is still required; a personal-build flag, Xcode test transaction, or cached entitlement cannot grant hosting.

Cloudflare’s dashboard was rechecked: Workers Free is the current plan. Activating the separate beta and uploading its four server secrets require the final activation approval; do not modify the existing production worker, production routing key, owner state, or Grok grant. The beta uses the existing Apple verification key and a new independent routing key. Do not add a production-to-Sandbox fallback.

To build the prepared phone beta, use the existing Honbako scheme and shared DerivedData with `HONBAKO_REMOTE_MCP_ENVIRONMENT=Sandbox`, `HONBAKO_PERSONAL_FEATURES=NO`, and build60. After approved activation, verify capability discovery, OAuth metadata, public-admin rejection, unsigned purchase rejection, and a real Apple Sandbox subscription on the phone. Local-runtime fixtures are not proof of a real purchase or a completed Grok connection.


### Isolated beta activated with approval — 30 October 2026

After the owner explicitly approved beta activation, `honbako-mcp-pro-preview` was deployed and its four secrets were configured through encrypted Workers secrets. Its active version is `d1ed1c64-59f7-4fb3-b8ea-494eb2033f83` at100%. It accepts Sandbox only, has separate SQLite namespaces and a separate routing key, and has no owner-pilot binding. The original production worker remains on `49a77e49-9b5b-4102-8325-1ac1985a3f7b` at100%, with managed production enrollment still off. Workers Free was reverified in the dashboard; no plan upgrade or price change was made.

Live checks: beta capabilities200, OAuth discovery200 with S256 PKCE, unauthenticated MCP401 with the beta resource metadata URL, public admin404, legacy MCP404, unsigned purchase enrollment402, and original production enrollment503. The checked-in beta entry exposes no fixture or admin endpoints. The owner confirmed successful Enable MCP Server enrollment on Duo after signed build60 was installed and launched. No receipt, installation credential or purchase identity was read into chat or printed by the Mac assistant. An actual AI connector authorization remains a separate phone-approved step; no assistant grant was created or extended during deployment.

Recovery details are stored outside the repository under the owner's private HonbakoMCP hosted/beta directory. Reuse its routing credential on redeployments; never rotate it, move beta storage into production, or migrate a namespace between Sandbox and Production as an incidental update.

## Surge protection on Workers Free

Workers Free has hard daily limits shared by every Worker on the account, production and test alike: 100,000 Worker requests, 100,000 Durable Object requests, 100,000 SQLite rows written and 13,000 GB-s, reset at 00:00 UTC. Rows written run out first, so a surge or a looping token would otherwise switch the AI features off for everyone until the reset.

- **In the Worker, before any Durable Object.** Three Rate Limiting bindings, keyed without any token or secret: `DEVICE_RATE_LIMITER` (150 a minute per device, keyed by a digest of the device's secret), `AI_RATE_LIMITER` (120 a minute per workspace, across its AI connections) and `SETUP_RATE_LIMITER` (20 a minute per address, for `/remote/enroll` and `/remote/oauth/*`). Over the limit is 429 `rate_limited` with `Retry-After: 60`. Forged tokens fail the route MAC and get 401 before any limiter or object. A missing or failing binding falls through to the limits below.
- **In each Durable Object, in memory.** Per-device, per-workspace AI, per-address and global counters live in memory: an object stays warm while it is polled, and eviction resetting them is acceptable. Only pairing-code guesses keep saved counters. A poll saves the device's last-seen time at most every 30 s.
- **A daily budget per workspace.** `WORKSPACE_DAILY_REQUEST_BUDGET` (20,000) device and AI requests per UTC day, counted in memory and saved every 30 s or 100 requests. Over it, every request except removing devices gets 429 with `Retry-After` set to 00:00 UTC. Disconnect All Devices does not reset it.
- **In the app.** Any 429 other than the five-device limit pauses polling and page sharing until `Retry-After`, or 3 s doubling to 5 minutes without one, and MCP settings says when the connection resumes.

Each Worker config uses its own `namespace_id`s (production 4101–4103, test 4201–4203), since both share the account. Cloudflare does not document whether the Rate Limiting binding is available on Workers Free; confirm it on the test Worker first.

`surge-probe.js` floods a runtime and reports status counts, the first 429, `Retry-After` values, where each 429 came from and latency. By default it runs five scenarios against local workerd (set `HONBAKO_WRANGLER_ROOT`; add `--no-bindings` for the fallback): junk tokens, setup and registration floods, one device at five times the reading pace, two minutes at the reading pace, and a workspace over its budget. `--live https://test-mcp.honbako.xyz` runs only the first two, at most 60 requests in total, refuses the production hosts, and tells Cloudflare WAF 429s (HTML or `cf-mitigated`) from the Worker's own JSON `rate_limited`. Do not add Bot Fight Mode or another challenge to the MCP hosts; it would block the AI providers' servers.
