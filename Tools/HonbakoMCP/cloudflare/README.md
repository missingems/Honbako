# Hosted Honbako companion

This adapter hosts the existing eight metadata tools plus two explicitly enabled page-coaching tools and paired-phone API in one SQLite-backed Cloudflare Durable Object. The phone talks directly to hosted HTTPS; the Mac is not required after cutover. Honbako still syncs and processes jobs only while the app is open in the foreground. Offline reading metadata is explicitly last known. Public hosting alone does not grant an agent page access. Pairing with Reading Access enabled shares the current manga page automatically. No per-book confirmation or sharing timer is required. No model subscription, new manga source, or unapproved import is supplied.

No deployment is performed by the test suite or these files. Use only an existing Workers Free account and SQLite-backed Durable Objects for this setup. Do not accept an upgrade or enable paid features. Availability and quota must be verified in the account before deployment; a successful login or dry run does not prove the account is on a free plan. Workers Free quota exhaustion should fail requests rather than authorize spending.

## Current deployment checkpoint — 30 October 2026

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

Public HTTPS permits only authenticated `POST /mcp`, one-time-code `POST /api/pair`, and the exact existing paired-device state/job/disconnect routes. All `/api/admin/*`, health/admin aliases and arbitrary paths return404, including requests with the owner key. Wrong methods fail, browser Origin headers are rejected, query credentials are not accepted, and JSON bodies/responses are bounded. Pairing has durable limits of10attempts/IP/10minutes and30attempts globally/10minutes; general requests also have bounded durable IP/global limits.

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
