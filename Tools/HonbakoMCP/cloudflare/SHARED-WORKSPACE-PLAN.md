# One AI connection for all your devices (plan)

Status: built, not deployed. Decisions 1–4 were approved as recommended (A, own workspace, per account, reconnect is fine). Server, app and Help/Privacy text are done; step 7 (deploy and device test) is Jun's. Applies to remote MCP (`mcp.honbako.xyz`, `test-mcp.honbako.xyz`). Local Mac mode keeps its pairing codes but drops the "choose a device" requirement (see the last section).

**Pending:** step 3, the sandbox Family Sharing check. `entitlement.js` follows Apple's documented `inAppOwnershipType` values: only an explicit `PURCHASED` joins the purchaser's workspace, and anything else (`FAMILY_SHARED`, missing, unknown) gets a per-installation workspace (at most five per purchase). Confirm the live values with a sandbox family purchase before production.

As built:
- `remote/purchases.js`: the broker maps `purchase:<hash>` to `{workspaceId, legacy}`. An old five-ID array becomes the legacy list. The mapping is bound only after the workspace accepts the device; if the mapped workspace has since moved to another purchase, it is unbound and a new one starts.
- `remote/workspace.js`: `remote-owners` (one per device) plus `remote-workspace` `{id, purchaseHash, familyShared}`. The old single `remote-owner` migrates on load. New device endpoints: `GET /api/device/workspace`, `POST /api/device/permissions`, `POST /api/device/remove`, `POST /api/device/disconnect-all`. Each `GET /api/device/jobs` also returns `workspace` (devices and account permissions) and `handled` (approvals another device answered in the last hour).
- `src/store.js`: the current device is the last one to report an open reader (polling never moves it). Jobs without a `deviceId` belong to the workspace. Searches and reads go to one device at a time (60-second turn). The first `approvalGranted` claims a change, and any other device's answer gets 409 `already_handled`. Permissions are enforced as account AND device.
- Disconnect All Devices wipes the workspace in place but keeps the purchase mapping, so a device that hasn't migrated yet still retires its old workspace when it joins.

## Decisions needed before building

1. **How a new device joins.**
   - **A. Automatic by Pro purchase (recommended).** Any device that proves the same Pro subscription (Apple's signed receipt) joins the same workspace. No extra steps.
   - **B. Approve on a device you already have.** The new iPad shows "Waiting for approval", and you tap Allow on your iPhone. Safer if your App Store account and iCloud account ever differ, but one extra step per device.
2. **Family Sharing members** (if Pro is ever shared with family): give each of them their own workspace (recommended), or don't offer them remote MCP. They must never land in the purchaser's workspace.
3. **Permissions:** one set for the whole account (recommended; it's one connection), or separate switches on each device.
4. **One-time reconnect.** Today each device has its own workspace. After the update, the first device to reconnect becomes the shared workspace and its AI connections keep working. AI connections made on your *other* devices stop and need connecting once more. Fine for TestFlight?

## Why "same purchase" rather than "same iCloud"

The server can't check which iCloud account a device uses: the app could only claim one, and a claim can be faked. The one thing the server can verify is Apple's signed App Store receipt. So "your devices" in practice means "devices that prove the same Pro purchase". For almost everyone this is the same Apple account. The exception is someone signed into the App Store and iCloud with different Apple accounts, which is why option B exists.

## How it works today

- Each installation has its own private workspace, a Cloudflare Durable Object named by the installation ID (`worker.js`: `workspace(env, installationId)`).
- A workspace has exactly one owner (`remote-owner` in `workspace.js`), and its tokens embed that ID: `d_<installationId>_…` for the phone and `a_<installationId>_…` for the AI.
- The OAuth approval on the phone binds an AI connection to that one workspace.
- The broker keeps up to five installation IDs per purchase (`allocatePurchase`).
- Inside a workspace the store already supports several devices (`data.devices`), but `device()` throws `choose_device` when there's more than one, and the AI instructions tell the AI to make you pick a `deviceId`.

## The change

### Server

1. **Workspace per purchase.**
   - The broker maps `purchaseHash → workspaceId`. This replaces the list of five installation IDs.
   - The first installation to enrol after the update gives its existing ID as the workspace ID. Because AI tokens embed that ID, its current AI connections keep working.
   - Workspace IDs stay UUIDs, as `tokenParts` requires.
2. **Several owners per workspace.**
   - `remote-owner` becomes a record per device: `id`, `tokenHash`, `identityHash`, `disabled`.
   - A device proves its own `deviceSecret` against its own record only, and can never overwrite another device's record.
   - Joining needs a fresh, valid receipt for the same purchase (option A) or an approval from an existing device (option B).
   - Device tokens stay per device: `d_<workspaceId>_…`, plus the device ID inside the record lookup.
3. **Five devices per workspace**, enforced inside the workspace. Turning MCP off on one device removes just that device. A new "Disconnect All Devices" deletes the workspace and revokes every AI connection.
4. **No more "choose a device".**
   - Library, sources and search use the freshest snapshot. iCloud keeps the devices' libraries in sync.
   - Reading context and the shared page come from the device you used most recently. The workspace keeps a "current device" pointer, updated when a device reports an active reader. Page-sharing records stay per device, so the AI only ever sees the current device's page.
   - Requests (search, add, remove, sources, history) belong to the workspace, not one device. Any of your devices can pick them up; the first to approve wins, using the existing atomic `executionClaimed` claim. The others show "Handled on iPad". Capability and permission checks apply to the device that runs the request.
   - `deviceId` stays optional in the AI tools for anyone who wants to target a device, but it's never required. The AI instructions drop "require the user to select a deviceId".
5. **Family Sharing.**
   - `entitlement.js` doesn't read `inAppOwnershipType` today. Add the check, and key only `PURCHASED` transactions by purchase. A family-shared transaction gets its own per-installation workspace (or is refused, per decision 2).
   - Confirm the actual field values with a sandbox family purchase before building.
6. **Migration of existing workspaces.**
   - Secondary devices that already have their own workspace move into the shared one on their next launch.
   - Their old workspace is deleted and its AI connections revoked (decision 4).
   - Their library data needs no copying: each device re-uploads its snapshot.

### App

- **Settings → MCP Server:** a "Devices" list showing name, last active and "This device", with a swipe to remove, plus "Disconnect All Devices".
- The consent prompt mentions that the connection covers your other devices on the same account.
- Pending approvals appear on every device. When one device approves, the others drop the request.
- A new device that joins shows "Connected with your other devices" instead of asking to connect an AI again.
- Permissions follow decision 3. Per account means the switches sync through the workspace, and every device shows the same values.

### Website (must ship together)

- The Privacy page currently says remote MCP uses "a private workspace for each installation", and that disconnecting "releases that installation's device slot". Both change. Update Privacy and Help in the same release as the server deploy.

## Order of work

1. Commit the current uncommitted work (App Review fixes and AI book removal) first. This plan touches the same files: `store.js`, `workspace.js`, `worker.js` and `HonbakoAutomationService.swift`.
2. Decide 1–4.
3. Sandbox check of Family Sharing receipt fields.
4. Server: broker mapping, multi-owner enrolment, workspace-level jobs, current-device pointer, Disconnect All, migration path. Tests for each, including "another purchase can't join" and "a removed device's token stops working".
5. App: devices list, consent wording, approvals across devices.
6. Help and Privacy text.
7. Deploy to `test-mcp.honbako.xyz`, try with an iPhone and the iPad mini on one TestFlight account, then production.

## Not in scope / known issues

- **Local Mac mode** keeps its one-time pairing code per device. Each device pairs to the same Mac, and the Mac already serves them all from one place. Dropping the "choose a device" requirement (step 4 above) applies there too, since it's the same store code.
- **Hosted import** (`cloudflare/migration.js`) only understands search and add requests, so a workspace holding other pending requests can't be imported. That's already true today; more devices make it more likely. Worth fixing separately.
