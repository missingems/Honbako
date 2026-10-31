# Honbako MCP on this Mac

A local companion service connects MCP-capable clients to an explicitly paired Honbako device. It can read a shared library snapshot and a spoiler-bounded reading position, search catalogs already connected to the app, and queue selected books for approval on the phone.

It does **not** call an AI model, use an AI subscription, fetch comic page text, translate pages, install new sources, or create a public endpoint. A client such as Claude, ChatGPT, Grok, Muse or Dot can use it only if that particular client supports the required MCP connection type and authentication. A cloud-hosted client cannot reach this Mac’s localhost or private LAN by itself.

## Start and pair

Requires Node.js 22 or later. Verified with Node 26.8.1. From this folder:

```sh
npm ci --ignore-scripts
node src/cli.js serve --host 0.0.0.0
```

The explicit host option makes the phone API available on this Mac’s network interfaces. Use a trusted local network. Without it, the default is loopback-only (`127.0.0.1`) for local clients and simulator testing.

Keep that process running. In another terminal, from this folder:

```sh
node src/cli.js pair
```

The command prints a fresh, one-time six-digit code, its ten-minute expiry, and this Mac’s possible LAN addresses. In Honbako’s AI Connections settings, enter the Mac address and the code. A new code invalidates the previous code; successful pairing consumes it.

State and credentials live in `~/Library/Application Support/HonbakoMCP`, **outside the repository**. An isolated location or another port can be selected with `--state-dir PATH` and `--port NUMBER`; use the same state directory for every command. No launch agent or background service is installed. Stop the service with Control-C.

## Connect a client

The server writes two private configuration files under the state directory:

| File | Purpose |
| --- | --- |
| `client-configs/claude-desktop.json` | A local stdio launcher. Merge its `honbako` entry into a desktop MCP client’s existing configuration. The launcher reads its credential file and proxies requests to the **same running HTTP service**. |
| `client-configs/http-client.json` | The Streamable HTTP URL and bearer header for clients that support custom bearer authentication. This file contains a secret; import it privately. |

`node src/cli.js configure` regenerates these files and prints only their locations. It never prints the bearer credential. The stdio configuration contains a credential-file location through the state-directory argument, not a token in its arguments or environment.

Desktop clients that support stdio can use the local launcher. Desktop HTTP clients need Streamable HTTP and custom bearer-header support. Cloud-only connectors need a reachable HTTPS service and whatever authorization that client requires; the hosted bearer-authenticated service is documented in [cloudflare/README.md](cloudflare/README.md). OAuth remains a later phase; ChatGPT’s custom connector cannot use this service’s fixed bearer key directly. This implementation does not claim that every named client currently supports these options.

The MCP URL is `http://127.0.0.1:43187/mcp` by default. It is a stateless Streamable HTTP endpoint; legacy SSE-only clients are unsupported. The app’s phone API and MCP endpoint share a port, but **use different credentials**.

## Grok Build on this Mac

The installed Grok Build CLI was connected locally through stdio on 29 October 2026. Its targeted connection check completed the MCP handshake and discovered all eight Honbako tools. The bridge remains on the Mac; no public tunnel or model request was used for this check.

For another installation, use Grok Build's `mcp add` command with the local Node executable, this folder's `src/cli.js` and the `proxy` argument. Its `mcp doctor honbako` command checks only this connection. The user-scoped entry can be used outside the repository as a reading companion.

The Grok website and mobile custom connector use a different connection route: the [official Grok guide](https://docs.x.ai/grok/connectors) requires a publicly reachable MCP address. That route needs a separate authenticated tunnel or hosted service. It is not enabled by the local stdio configuration.

## Grok Bot

Grok Bot is a separate client from Grok Build. Its default persistent computer runs in the cloud, so the local Build entry and this Mac’s private LAN address do not connect a Bot conversation. A command connector runs on the Bot conversation’s computer. The documented desktop traffic-routing option does not by itself make private-network addresses reachable. See the official [computer and apps guide](https://docs.x.ai/grok-bot/computer-and-apps) and [private-network guide](https://docs.x.ai/grok-bot/private-networks).

The owner’s hosted service is `https://honbako-mcp.jun-19c.workers.dev/mcp`, using the existing private Grok credential and its original expiry. The user reported updating the Bot connector; the phone endpoint move remains under verification. See the [hosted deployment checkpoint](cloudflare/README.md#current-deployment-checkpoint--30-october-2026). A separately configured local companion still needs a reachable HTTPS MCP endpoint with authentication. Publish only the MCP route through a separately secured gateway; do not tunnel the entire companion port, because it also contains pairing, device and owner-administration routes.

### Prepared local MCP-only gateway

The separate gateway is ready for local testing. Start the existing companion first, then run from this folder:

```sh
node src/cli.js gateway
```

It binds **only** `127.0.0.1:43188`; it does not install or start a tunnel, expose a public address, or change the companion's listener. It forwards only exact `POST /mcp` requests to the existing loopback companion. Pairing, device, owner-administration and health routes, query strings, encoded/traversal paths, other methods, browser Origin requests and CORS preflights are rejected. Only the validated MCP protocol-version header is passed through; cookies, forwarded addresses and the incoming authorization header are not forwarded.

The gateway creates a **different** random Grok credential in private `grok-gateway-credential.json` under the state directory. It never gives the companion's owner credential or a phone credential to Grok. The credential expires **24 hours after creation**, is rejected after expiry, and restarting does not extend it. The private `client-configs/grok-bot-gateway.json` contains the local URL, the new bearer header and its expiry. `gateway.json` contains only non-secret listener metadata and the expiry. The state/config directories are `0700`, and credential/config files are `0600`. The CLI prints file locations and expiry, never credential values.

A separately approved HTTPS tunnel must point to **port 43188, never port 43187**, and rewrite its upstream HTTP Host header to `127.0.0.1:43188`. For Cloudflare's official CLI, the relevant option is `--http-host-header 127.0.0.1:43188` alongside a loopback gateway URL; see its [origin-header documentation](https://developers.cloudflare.com/tunnel/reference/origin-parameters/) and [official CLI flag source](https://github.com/cloudflare/cloudflared/blob/master/cmd/cloudflared/tunnel/cmd.go). This repository does not start that command or install Cloudflare. The gateway rejects browser Origin headers rather than providing a CORS bypass; Grok Bot's server-to-server connector must support a private fixed `Authorization: Bearer …` header. Enter that value only in the connector's private credential field, never in a chat, URL, query parameter or public file. Substitute the approved HTTPS `/mcp` URL for the local URL when configuring Grok Bot.

Defaults bound request bodies to 1 MiB, responses to 2 MiB, request-body and upstream waits to 12 seconds each, traffic to 300 requests per minute, and concurrent work to eight requests. A failed upstream POST is **never retried** by the gateway. Library jobs still retain their original phone-approval and idempotency rules.

Revoke Grok's credential locally at any time:

```sh
node src/cli.js gateway-revoke
```

Revocation removes only the gateway credential and its private client config. A running gateway checks the credential file before forwarding, so subsequent requests are rejected immediately; the companion, phone pairing and owner credential are unchanged. Already forwarded requests or queued library work are not undone. Stop any separately started tunnel as well when disconnecting remote access. To reconnect after revocation or expiry, stop/restart the gateway and privately update Grok with the newly generated credential. Control-C stops the gateway and removes only its listener/lock metadata; the credential otherwise persists until its original expiry.

The app’s Japanese reading overlays are independent of this bridge. Its on-device recognition, pronunciation and explicit Apple system translation do not send page images or recognized text through MCP. The existing reading-context tool still exports only the approved title, chapter and page metadata. Connecting with Reading Access enabled automatically shares one canonical visible manga page at a time and allows removable assistant annotations. There is no separate Start/Stop control or sharing timer. The latest shared page remains available after closing the book or backgrounding the app; disabling Reading Access, private reading, or disconnecting revokes it. It is never automatic screen access.

## What the tools do

| Tool | Behaviour |
| --- | --- |
| `honbako_get_status` | Paired device names, freshness, snapshot availability and pending jobs. |
| `honbako_get_reading_context` | Shared title, chapter, canonical reading page and a reported spoiler boundary. No full text or page images. |
| `honbako_search_library` | Searches the last synced saved-library snapshot by title. |
| `honbako_list_sources` | Lists catalogs already connected to the device. |
| `honbako_search_catalog` | Queues a search in up to 20 existing connected sources. Returns a job, not immediate matches. |
| `honbako_add_to_library` | Queues exact IDs previously returned by a catalog search for approval on the phone. Requires a stable idempotency key. |
| `honbako_get_job` | Reports queued, approval, completed, rejected, failed or cancelled status and available results. |
| `honbako_cancel_job` | Cancels work before approved execution is claimed. After the phone claims execution, cancellation returns “too late.” |
| `honbako_get_coaching_page` | The connected device’s current or last-shared manga page, with exact identity, capture time and spoiler boundary. Requires the paired connection’s Reading Access. |
| `honbako_annotate_page` | Removable normalized boxes, arrows, labels or strokes on that exact shared page; stale generations/revisions are rejected. |

Open Honbako to sync snapshots and process jobs. If the app is closed or suspended, work stays queued. “Queued” and “awaiting approval” never mean a book has already been added. The client should poll `get_job` and report the actual outcome. A failed batch may have made partial progress; refresh the library instead of assuming it changed nothing.

A source search returns up to 20 exact matches. An add batch contains up to 20 identities, with source IDs from the current snapshot and manga IDs from a completed search (or an already saved title). Recommendations are suggestions; only matching, connected catalog items can be queued. The bridge does not add sources or silently replace a missing recommendation with a different title.

With more than one paired device, reading context and the shared page come from the device that last reported an open reader, and library tools use the freshest library; `deviceId` is optional and only targets one device. Jobs created without a `deviceId` belong to every device: searches and reads run on one device at a time, and the first device to approve a library or source change claims it (`already_handled` for the rest). A snapshot older than 30 seconds is reported as **last known**, even if job polling keeps the connection alive. Reading is “current” only when a fresh snapshot says it is active. Recaps must not reveal events after the returned chapter and last visible page; metadata alone is not proof that a model knows the contents.

## Native HTTP contract

All requests are JSON, bounded to 1 MiB. Unknown snapshot fields are discarded rather than retained. Titles/names are bounded to 512 characters, source IDs to 256, manga/chapter IDs to 2,048, library snapshots to 2,000 titles and source snapshots to 100 entries. IDs reject control characters, URL user information, query strings and fragments. Truncation is explicit through `libraryTruncated` / `sourcesTruncated`.

- `POST /api/pair` — `{code,name}` → `{deviceId,deviceToken}`. No bearer; one-time code and rate limiting are required.
- `POST /api/device/state` — device bearer plus `{schemaVersion:1,generatedAt,library,sources,reading,...}`. Replaces the previous snapshot; an older `generatedAt` is a no-op with `accepted:false` and cannot refresh freshness. `reading:null` clears reading context; empty arrays clear library/source metadata. Returns `{ok:true,receivedAt}`.
- `GET /api/device/jobs` — device bearer; returns its queued and awaiting-approval jobs only.
- `POST /api/device/jobs/<id>/status` — device bearer plus `{status,result?,error?,approvalGranted?}`. Status is `awaitingApproval`, `completed`, `failed` or `rejected`.
- `POST /api/device/disconnect` — device bearer plus `{}`. Atomically removes the device, its stored snapshots/jobs and its bearer authorization.

For an addition, the app first reports `awaitingApproval` to display the approval prompt. On the user’s approval, it posts `{status:"awaitingApproval",approvalGranted:true}` **before** adding anything. This atomic claim detects cancellation and prevents a later client cancellation from falsely claiming to stop work already executing. Only a claimed addition can report `completed`.

Catalog completion results are `{matches:[{sourceId,mangaId,title,author?}],errors?:[]}`. Addition results are `{added:[{sourceId,mangaId,title?}],alreadyPresent:[...]}`. Results are restricted to the requested sources/identities. Credentials and provider response bodies do not belong in these fields.

The reading snapshot includes `sourceId`, `mangaId`, `title`, `chapterId`, `chapterTitle`, optional chapter/volume numbers, one-based `page`, optional `lastVisiblePage` / `totalPages`, `updatedAt` and `active`. The visible range must be ordered and within `totalPages` when supplied.

## Local administration and storage

```sh
node src/cli.js status
node src/cli.js forget --device-id DEVICE_UUID
```

`forget` is available for an offline or replaced phone. Disconnection on the phone should revoke the server credential before forgetting its local token. If the Mac is unreachable, revocation cannot be claimed as complete; reconnect and retry or use the Mac’s `forget` command.

The state directory is mode `0700`; JSON state, credential and configuration files are `0600`. Pairing codes are stored only as keyed hashes, device tokens only as hashes, and the personal MCP token separately in `mcp-token`. Writes are serialized and atomic. The CLI prevents two server processes from owning the same state directory. The service does not log request bodies, bearer credentials or pairing requests.

Native snapshots should use monotonically increasing fractional-second timestamps. A device clock rollback can require disconnecting and pairing again in this first version.

Pending work is durable across restarts. The most recent 2,000 terminal jobs retain their results and idempotency keys; older terminal metadata may be pruned. Reusing a retained idempotency key returns the same job and rejects different identities. The native add path additionally checks whether a book is already present, so a later deliberate retry cannot create duplicate library entries.

This is local personal storage, not developer analytics. It retains the snapshots and job metadata the owner enables until replaced or disconnected. The latest shared manga image and drawing draft remain in memory while reading access is connected, and are excluded from snapshots, jobs and migration exports. A Node restart loses image bytes; an open connected reader automatically republishes its current page. The optional hosted implementation stores one current image separately until access is revoked; it has not been deployed. MCP does not supply background phone execution, a voice call, an in-app Ask AI queue or model billing.

## Verification and SDK sources

```sh
npm run check
npm test
npm audit --omit=dev
```

Tests use temporary isolated state and fake phones. They exercise real official HTTP and stdio MCP clients, pairing replay/expiry/rate limits, private permissions, durable snapshots, stale reading, approval claims, idempotent additions, cancellation, request validation, cross-device isolation and token revocation. Gateway checks also exercise route isolation, separate credentials, expiry/revocation, Host/Origin rejection, body/time/rate/concurrency limits, sanitized upstream failures and graceful CLI shutdown. No real library or owner device is used.

The lockfile pins the current official v2 packages verified on 29 October 2026: [`@modelcontextprotocol/server` 2.4.0](https://www.npmjs.com/package/@modelcontextprotocol/server), [`@modelcontextprotocol/client` 2.4.0](https://www.npmjs.com/package/@modelcontextprotocol/client) and [`@modelcontextprotocol/node` 2.1.2](https://www.npmjs.com/package/@modelcontextprotocol/node). The [official TypeScript SDK repository](https://github.com/modelcontextprotocol/typescript-sdk) owns these packages. The older monolithic `@modelcontextprotocol/sdk` is its v1 maintenance line and is not used here.

The page-coaching wire contract, image bounds, expiry/revocation rules, and cached/background semantics are documented in [cloudflare/README.md](cloudflare/README.md#temporary-page-coaching-wire-contract). No voice call or model subscription is supplied by MCP itself; a connected agent must invoke the tools. On 29 October 2026, the registered Grok Bot connector correctly inspected an owned shape-and-number image and returned a box and label, independently verified through the device API. The temporary fixture device was then removed. This verifies image ingestion and annotation tool use; the voice-call path remains untested.
