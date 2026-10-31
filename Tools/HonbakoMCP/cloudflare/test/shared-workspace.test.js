import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
import { AppleProVerifier, BUNDLE, PRODUCT, LEASE_MS } from '../remote/entitlement.js';
import { RemoteWorkspace } from '../remote/workspace.js';
import { PurchaseRegistry, routeEnrollment } from '../remote/purchases.js';
import { secret, tokenParts } from '../remote/oauth.js';
import { SqliteBridgeStore } from '../storage.js';
const BASE = 'https://honbako.example/remote', ROUTE_KEY = 'K'.repeat(43), at = Date.now();
function store(clock) {
  const db = new DatabaseSync(':memory:');
  const storage = { sql: { exec(s, ...args) { const p = db.prepare(s); return p.columns().length ? p.all(...args) : (p.run(...args), []); } },
    transactionSync(f) { db.exec('BEGIN'); try { const r = f(); db.exec('COMMIT'); return r; } catch (e) { db.exec('ROLLBACK'); throw e; } } };
  return new SqliteBridgeStore(storage, 'P'.repeat(43), { clock });
}
// Mirrors remote/worker.js: one broker, one workspace per name, tokens routed by their embedded ID.
function cloud() {
  let now = at;
  const clock = () => now, registry = new PurchaseRegistry(store(clock)), stores = new Map(), spaces = new Map();
  const lease = (purchaseHash = 'purchase', familyShared = false) => ({ originalTransactionId: '12345', purchaseHash, familyShared, expiresAt: now + 86400000, leaseUntil: now + LEASE_MS });
  const open = id => {
    if (!spaces.has(id)) {
      if (!stores.has(id)) stores.set(id, store(clock));
      spaces.set(id, new RemoteWorkspace(stores.get(id), { base: BASE, routeKey: ROUTE_KEY, clock,
        verifier: { async current() { return lease(); } }, release: async (hash, owner) => registry.releaseFamily(hash, owner) }));
    }
    return spaces.get(id);
  };
  const enroll = (identity, granted = lease()) => routeEnrollment({ purchases: registry, workspace: open }, identity, granted, BASE);
  const route = token => open(tokenParts(token)[2]);
  const call = (token, path, body, method = body === undefined ? 'GET' : 'POST') => route(token).fetch(new Request(`${BASE}${path}`, { method,
    headers: { accept: 'application/json, text/event-stream', 'content-type': 'application/json', authorization: `Bearer ${token}` }, ...(method === 'GET' ? {} : { body: JSON.stringify(body) }) }));
  // Restart one workspace from its saved storage, as a deploy would.
  const restart = id => { spaces.delete(id); return open(id); };
  return { registry, stores, open, enroll, route, call, restart, lease, advance: ms => { now += ms; } };
}
const device = (name = 'iPhone') => ({ installationId: randomUUID(), deviceSecret: secret(), name, signedTransaction: 'x'.repeat(100) });
const tools = { jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} };
const state = (overrides = {}) => ({ schemaVersion: 1, generatedAt: new Date(at).toISOString(), library: [{ sourceId: 'owned', mangaId: 'one', title: 'One' }],
  sources: [{ id: 'owned', name: 'Owned', supportsSearch: true }], readingHistoryAccess: true, automationCapabilities: ['reading.history', 'sources.manage', 'library.remove'], ...overrides });

test('Devices proving the same purchase share one workspace and its AI connections; another purchase cannot join', async () => {
  const c = cloud(), phone = device('iPhone'), pad = device('iPad'), stranger = device('Stranger');
  const first = await c.enroll(phone);
  assert.equal(first.workspaceId, phone.installationId); assert.equal(first.joinedOtherDevices, false);
  const ai = await c.open(first.workspaceId).issue('client');
  const second = await c.enroll(pad);
  assert.deepEqual([second.workspaceId, second.deviceId, second.joinedOtherDevices], [first.workspaceId, pad.installationId, true]);
  assert.equal(tokenParts(second.deviceToken)[2], first.workspaceId);
  assert.equal((await c.call(second.deviceToken, '/api/device/jobs')).status, 200);
  assert.equal((await c.call(ai.access_token, '/mcp', tools)).status, 200);
  const info = (await (await c.call(second.deviceToken, '/api/device/jobs')).json()).workspace;
  assert.deepEqual(info.devices.map(d => [d.name, d.thisDevice]).sort(), [['iPad', true], ['iPhone', false]]);
  // Another purchase gets its own workspace, and the shared one refuses it even when addressed directly.
  const other = await c.enroll(stranger, c.lease('another-purchase'));
  assert.notEqual(other.workspaceId, first.workspaceId);
  await assert.rejects(c.open(first.workspaceId).enroll(device(), c.lease('another-purchase'), BASE, first.workspaceId), { status: 409, code: 'purchase_mismatch' });
  assert.equal((await c.call(other.deviceToken, '/api/device/jobs')).status, 200);
  assert.equal((await c.open(first.workspaceId).fetch(new Request(`${BASE}/api/device/jobs`, { headers: { authorization: `Bearer ${other.deviceToken}` } }))).status, 401);
  // A device can only re-enroll with its own secret, never take over another's record.
  await assert.rejects(c.enroll({ ...pad, deviceSecret: secret() }), { status: 401 });
});

test('A removed device’s token stops working while the others and the AI connection keep going; the last one ends it', async () => {
  const c = cloud(), phone = await c.enroll(device('iPhone')), pad = await c.enroll(device('iPad'));
  const ai = await c.open(phone.workspaceId).issue('client');
  assert.equal((await c.call(phone.deviceToken, '/api/device/remove', { deviceId: pad.deviceId })).status, 200);
  assert.equal((await c.call(pad.deviceToken, '/api/device/jobs')).status, 401);
  assert.equal((await c.call(pad.deviceToken, '/api/device/state', state())).status, 401);
  assert.equal((await c.call(phone.deviceToken, '/api/device/jobs')).status, 200);
  assert.equal((await c.call(ai.access_token, '/mcp', tools)).status, 200);
  assert.equal((await c.call(phone.deviceToken, '/api/device/remove', { deviceId: pad.deviceId })).status, 404);
  assert.equal((await c.call(phone.deviceToken, '/api/device/disconnect', {})).status, 200);
  assert.equal((await c.call(phone.deviceToken, '/api/device/jobs')).status, 401);
  assert.equal((await c.call(ai.access_token, '/mcp', tools)).status, 401);
});

test('Disconnect All Devices revokes every device and AI connection and wipes the shared workspace', async () => {
  const c = cloud(), phone = await c.enroll(device('iPhone')), pad = await c.enroll(device('iPad'));
  const w = c.open(phone.workspaceId), ai = await w.issue('client');
  await c.call(pad.deviceToken, '/api/device/state', state());
  await c.call(pad.deviceToken, '/api/device/permissions', { permissions: { pageRead: false } });
  assert.equal((await c.call(pad.deviceToken, '/api/device/disconnect-all', {})).status, 200);
  for (const token of [phone.deviceToken, pad.deviceToken]) assert.equal((await c.call(token, '/api/device/jobs')).status, 401);
  assert.equal((await c.call(ai.access_token, '/mcp', tools)).status, 401);
  assert.deepEqual([w.store.data.devices.length, w.store.data.jobs.length, w.grants().length, w.store.control('account-permissions')], [0, 0, 0, null]);
  // The same devices can connect again with a fresh receipt, starting empty.
  const again = await c.enroll(device('iPhone'));
  assert.equal(again.workspaceId, phone.workspaceId); assert.equal(again.joinedOtherDevices, false);
});

test('Five devices per workspace; turning one off frees its place', async () => {
  const c = cloud(), joined = [];
  for (let i = 0; i < 5; i++) joined.push(await c.enroll(device(`Device ${i}`)));
  const sixth = device('Sixth');
  await assert.rejects(c.enroll(sixth), { status: 429, code: 'device_limit' });
  assert.equal((await c.call(joined[4].deviceToken, '/api/device/disconnect', {})).status, 200);
  assert.equal((await c.enroll(sixth)).workspaceId, joined[0].workspaceId);
});

test('The first device to approve a change wins; the others see who handled it and cannot fail or reject it', async () => {
  const c = cloud(), phone = await c.enroll(device('iPhone')), pad = await c.enroll(device('iPad'));
  const w = c.open(phone.workspaceId);
  for (const token of [phone.deviceToken, pad.deviceToken]) assert.equal((await c.call(token, '/api/device/state', state())).status, 200);
  const job = await w.store.removeFromLibrary({ items: [{ sourceId: 'owned', mangaId: 'one' }], idempotencyKey: 'remove-one' });
  assert.equal(job.deviceId, null);
  const jobs = async token => (await (await c.call(token, '/api/device/jobs')).json());
  for (const token of [phone.deviceToken, pad.deviceToken]) {
    assert.deepEqual((await jobs(token)).jobs.map(j => j.id), [job.id]);
    assert.equal((await c.call(token, `/api/device/jobs/${job.id}/status`, { status: 'awaitingApproval' })).status, 200);
  }
  assert.equal((await c.call(pad.deviceToken, `/api/device/jobs/${job.id}/status`, { status: 'awaitingApproval', approvalGranted: true })).status, 200);
  const late = await c.call(phone.deviceToken, `/api/device/jobs/${job.id}/status`, { status: 'awaitingApproval', approvalGranted: true });
  assert.deepEqual([late.status, (await late.json()).error.code], [409, 'already_handled']);
  for (const status of ['rejected', 'failed']) assert.equal((await c.call(phone.deviceToken, `/api/device/jobs/${job.id}/status`, { status, error: 'Too late' })).status, 409);
  const elsewhere = await jobs(phone.deviceToken);
  assert.deepEqual(elsewhere.jobs, []);
  assert.deepEqual(elsewhere.handled, [{ id: job.id, status: 'awaitingApproval', handledBy: 'iPad' }]);
  const result = { removed: [{ sourceId: 'owned', mangaId: 'one' }], notPresent: [] };
  assert.equal((await c.call(phone.deviceToken, `/api/device/jobs/${job.id}/status`, { status: 'completed', result })).status, 409);
  assert.equal((await c.call(pad.deviceToken, `/api/device/jobs/${job.id}/status`, { status: 'completed', result })).status, 200);
  assert.equal(w.store.job({ jobId: job.id }).status, 'completed');
  assert.equal((await jobs(phone.deviceToken)).handled[0].status, 'completed');
  // A rejection is final for every device too.
  const second = await w.store.removeFromLibrary({ items: [{ sourceId: 'owned', mangaId: 'one' }], idempotencyKey: 'remove-again' });
  assert.equal((await c.call(phone.deviceToken, `/api/device/jobs/${second.id}/status`, { status: 'rejected' })).status, 200);
  assert.equal((await c.call(pad.deviceToken, `/api/device/jobs/${second.id}/status`, { status: 'awaitingApproval', approvalGranted: true })).status, 409);
});

test('Searches run on one device at a time, reading context follows the last open reader, and permissions are shared', async () => {
  const c = cloud(), phone = await c.enroll(device('iPhone')), pad = await c.enroll(device('iPad'));
  const w = c.open(phone.workspaceId);
  const reading = { sourceId: 'owned', mangaId: 'one', title: 'One', chapterId: 'c1', chapterTitle: 'One', page: 3, updatedAt: new Date(at).toISOString(), active: true };
  await c.call(phone.deviceToken, '/api/device/state', state({ reading: { ...reading, title: 'Read on iPhone' } }));
  c.advance(1000);
  await c.call(pad.deviceToken, '/api/device/state', state({ reading: { ...reading, title: 'Read on iPad' } }));
  c.advance(1000);
  await c.call(phone.deviceToken, '/api/device/state', state({ generatedAt: new Date(at + 2000).toISOString(), reading: { ...reading, title: 'Read on iPhone', active: false } }));
  assert.equal(w.store.readingContext({}).reading.title, 'Read on iPad');
  assert.equal(w.store.readingContext({ deviceId: phone.deviceId }).reading.title, 'Read on iPhone');
  const search = await w.store.searchCatalog({ query: 'Moon', limit: 5 });
  const jobs = async token => (await (await c.call(token, '/api/device/jobs')).json());
  assert.deepEqual((await jobs(pad.deviceToken)).jobs.map(j => j.id), [search.id]);
  assert.deepEqual((await jobs(phone.deviceToken)).jobs, [], 'the iPad is already running it');
  c.advance(61000);
  assert.deepEqual((await jobs(phone.deviceToken)).jobs.map(j => j.id), [search.id], 'a quiet runner loses its turn');
  // One set of switches for the account, enforced on every device.
  const set = await (await c.call(pad.deviceToken, '/api/device/permissions', { permissions: { libraryRead: false } })).json();
  assert.equal(set.permissions.revision, 1);
  assert.equal((await jobs(phone.deviceToken)).workspace.permissions.values.libraryRead, false);
  assert.throws(() => w.store.librarySearch({ query: '', limit: 5, deviceId: phone.deviceId }), { code: 'permission_disabled' });
  assert.equal(w.store.data.jobs.some(job => job.id === search.id), false, 'queued searches end with Read Library');
  assert.equal((await c.call(phone.deviceToken, '/api/device/permissions', { permissions: { libraryRead: 'yes' } })).status, 400);
  assert.equal((await c.call(phone.deviceToken, '/api/device/permissions', { permissions: { libraryRead: true } })).status, 200);
  assert.equal(w.store.librarySearch({ query: '', limit: 5 }).matches.length, 1);
});

test('A family-shared purchase gets its own workspace and never lands in the purchaser’s', async () => {
  const c = cloud(), owner = await c.enroll(device('iPhone')), family = device('Family iPad');
  const shared = await c.enroll(family, c.lease('purchase', true));
  assert.equal(shared.workspaceId, family.installationId);
  assert.notEqual(shared.workspaceId, owner.workspaceId);
  assert.equal(c.open(owner.workspaceId).info(owner.deviceId).devices.length, 1);
  await assert.rejects(c.open(owner.workspaceId).enroll(device(), c.lease('purchase', true), BASE, owner.workspaceId), { status: 409, code: 'purchase_mismatch' });
  await assert.rejects(c.open(family.installationId).enroll(device(), c.lease(), BASE, family.installationId), { status: 409, code: 'purchase_mismatch' });
  assert.deepEqual(c.registry.store.control('family:purchase'), [family.installationId]);
  assert.equal((await c.call(shared.deviceToken, '/api/device/disconnect', {})).status, 200);
  assert.deepEqual(c.registry.store.control('family:purchase'), []);
});

test('Apple’s ownership type decides Family Sharing; only an explicit PURCHASED joins the purchaser', async () => {
  const transaction = ownership => ({ bundleId: BUNDLE, productId: PRODUCT, type: 'Auto-Renewable Subscription', environment: 'Production', originalTransactionId: '12345', expiresDate: at + 86400000, ...(ownership ? { inAppOwnershipType: ownership } : {}) });
  const verify = (device, status = device) => new AppleProVerifier({}, { clock: () => at, signedVerifier: { calls: 0, async verifyAndDecodeTransaction() { return this.calls++ ? status : device; } },
    api: { async getAllSubscriptionStatuses() { return { data: [{ lastTransactions: [{ status: 1, signedTransactionInfo: 'signed' }] }] }; } } }).enroll('x'.repeat(100));
  assert.equal((await verify(transaction('PURCHASED'))).familyShared, false);
  assert.equal((await verify(transaction('FAMILY_SHARED'))).familyShared, true);
  assert.equal((await verify(transaction(undefined))).familyShared, true, 'a missing value fails safe');
  assert.equal((await verify(transaction('PURCHASED'), transaction('FAMILY_SHARED'))).familyShared, true);
  assert.equal((await verify(transaction('FAMILY_SHARED'), transaction('PURCHASED'))).familyShared, true);
});

// The workspace saved by the previous release: one owner, named by its installation ID.
async function legacy(c, identity, purchaseHash = 'purchase') {
  const w = c.open(identity.installationId), enrolled = await w.enroll(identity, c.lease(purchaseHash));
  await c.call(enrolled.deviceToken, '/api/device/state', state({ library: [{ sourceId: 'owned', mangaId: identity.name, title: identity.name }] }));
  const ai = await w.issue('client');
  const owner = w.owners()[0];
  w.store.setControl('remote-owner', { id: owner.id, tokenHash: owner.tokenHash, identityHash: owner.identityHash, purchaseHash });
  w.store.setControl('remote-owners', null); w.store.setControl('remote-workspace', null);
  return { identity, enrolled, ai };
}
test('Migration: the first device to reconnect becomes the shared workspace; the others join it and their old workspaces close', async () => {
  const c = cloud(), phone = await legacy(c, device('iPhone')), pad = await legacy(c, device('iPad'));
  c.registry.store.setControl('purchase:purchase', [phone.identity.installationId, pad.identity.installationId]);
  // Deploy: both legacy workspaces restart and convert their single owner.
  for (const id of [phone.identity.installationId, pad.identity.installationId]) c.restart(id);
  assert.equal(c.open(phone.identity.installationId).owners().length, 1);
  assert.equal((await c.call(phone.enrolled.deviceToken, '/api/device/jobs')).status, 200, 'old tokens keep working until a device re-enrolls');
  // The iPhone reconnects first: same workspace, same token, its AI connection keeps working.
  const first = await c.enroll(phone.identity);
  assert.deepEqual([first.workspaceId, first.deviceToken, first.joinedOtherDevices], [phone.identity.installationId, phone.enrolled.deviceToken, false]);
  assert.deepEqual(c.registry.store.control('purchase:purchase'), { workspaceId: phone.identity.installationId, legacy: [pad.identity.installationId] });
  assert.equal((await c.call(phone.ai.access_token, '/mcp', tools)).status, 200);
  // The iPad joins it. Its old workspace closes, including the AI connection made there (decision 4).
  const joined = await c.enroll(pad.identity);
  assert.deepEqual([joined.workspaceId, joined.joinedOtherDevices], [phone.identity.installationId, true]);
  assert.equal((await c.call(pad.enrolled.deviceToken, '/api/device/jobs')).status, 401);
  assert.equal((await c.call(pad.ai.access_token, '/mcp', tools)).status, 401);
  assert.deepEqual(c.open(pad.identity.installationId).store.data.devices, []);
  assert.equal((await c.call(joined.deviceToken, '/api/device/jobs')).status, 200);
  assert.deepEqual(c.registry.store.control('purchase:purchase').legacy, []);
  // Re-enrolling again is a no-op for both, and nothing else can close the shared workspace.
  assert.equal((await c.enroll(pad.identity)).deviceToken, joined.deviceToken);
  await assert.rejects(c.open(phone.identity.installationId).retire({ installationId: phone.identity.installationId, deviceSecret: secret() }), { status: 401 });
  assert.equal(c.open(phone.identity.installationId).info(phone.identity.installationId).devices.length, 2);
});

test('Migration: a legacy workspace whose device left can move to another purchase without stranding the first', async () => {
  const c = cloud(), phone = device('iPhone'), pad = device('iPad');
  const first = await c.enroll(phone);
  assert.equal((await c.call(first.deviceToken, '/api/device/disconnect', {})).status, 200);
  // The iPhone signs in with another Apple Account; its emptied workspace moves with it.
  const moved = await c.enroll(phone, c.lease('another-purchase'));
  assert.equal(moved.workspaceId, phone.installationId);
  // The original purchase's next device starts a new shared workspace instead of being refused.
  const fresh = await c.enroll(pad);
  assert.equal(fresh.workspaceId, pad.installationId);
  assert.equal(c.registry.store.control('purchase:purchase').workspaceId, pad.installationId);
  // Its own workspace keeps the other purchase while active.
  await assert.rejects(c.open(phone.installationId).enroll(phone, c.lease(), BASE, phone.installationId), { status: 409, code: 'purchase_mismatch' });
  // Signing back in to the original purchase joins that purchase's devices.
  assert.equal((await c.enroll(phone)).workspaceId, pad.installationId);
});
