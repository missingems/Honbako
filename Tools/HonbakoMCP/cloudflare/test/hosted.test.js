import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
import { SqliteBridgeStore } from '../storage.js';
import { HostedBridgeCore, boundedBytes } from '../core.js';
import { stateDigest, validateMigration } from '../migration.js';
import { digest } from '../../src/store.js';
import adminWorker from '../admin-worker.js';
import localAdmin from '../local-admin.js';
const ADMIN = 'A'.repeat(43), PAIRING = 'P'.repeat(43), DEVICE = 'D'.repeat(43), ORIGIN = 'https://honbako.example';
function storage(database = new DatabaseSync(':memory:')) {
  return { database, sql: { exec(statement, ...args) { const p = database.prepare(statement); return p.columns().length ? p.all(...args) : (p.run(...args), []); } }, transactionSync(change) {
    database.exec('BEGIN'); try { const result = change(); database.exec('COMMIT'); return result; } catch (error) { database.exec('ROLLBACK'); throw error; }
  } };
}
function fixture() {
  const db = storage(); let now = Date.parse('2026-10-29T12:00:00Z');
  const open = () => new HostedBridgeCore(new SqliteBridgeStore(db, PAIRING, { clock: () => now }), { publicOrigin: ORIGIN, adminKey: ADMIN, clock: () => now });
  return { db, open, advance(ms) { now += ms; }, core: open() };
}
function request(path, { token, method = 'POST', body = {}, ip = '203.0.113.1', headers = {}, origin = ORIGIN } = {}) {
  return new Request(`${origin}${path}`, { method, headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream', 'cf-connecting-ip': ip,
    ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers }, ...(method === 'GET' ? {} : { body: typeof body === 'string' ? body : JSON.stringify(body) }) });
}
async function grant(core, params) { return (await core.admin('grant', params, ADMIN)).token; }
async function pair(core) {
  const { code } = await core.admin('pair-code', {}, ADMIN), r = await core.fetch(request('/api/pair', { body: { code, name: 'Owned phone' } }));
  assert.equal(r.status, 200); return r.json();
}
function migrationState() {
  const deviceId = randomUUID(), at = '2026-10-29T10:10:44.000Z', items = Array.from({ length: 30 }, (_, i) => ({ sourceId: 'owned.catalog', mangaId: `book-${i}` }));
  return { version: 1, pairing: { hash: 'old-invalidated-code', expiresAt: '2026-10-29T12:10:00Z' },
    devices: [{ id: deviceId, name: 'Owned phone', tokenHash: digest(DEVICE), createdAt: at, lastSeen: at, snapshotReceivedAt: at,
      snapshot: { schemaVersion: 1, generatedAt: at, library: [], sources: [{ id: 'owned.catalog', name: 'Owned catalog', supportsSearch: true }] } }],
    jobs: [items.slice(0, 20), items.slice(20)].map((batch, i) => ({ id: randomUUID(), deviceId, kind: 'library.add', payload: { items: batch, idempotencyKey: `migration-${i}` },
      idempotencyKey: `migration-${i}`, status: 'awaitingApproval', executionClaimed: false, createdAt: at, updatedAt: at })) };
}
test('SQLite pairing and snapshot survive restart without filesystem state', async () => {
  const { core, open } = fixture(), phone = await pair(core);
  assert.equal((await core.fetch(request('/api/device/state', { token: phone.deviceToken, body: { schemaVersion: 1, generatedAt: '2026-10-29T12:00:00Z', library: [{ sourceId: 'owned', mangaId: 'one', title: 'One' }], sources: [] } }))).status, 200);
  const restarted = open(); assert.equal(restarted.store.authenticateDevice(phone.deviceToken), phone.deviceId);
  assert.equal(restarted.store.status().devices[0].libraryCount, 1); assert.equal(restarted.store.directory, null);
});
test('administrator/arbitrary paths are 404 even for owner; HTTPS/origin/method policy fails closed', async () => {
  const { core } = fixture();
  for (const path of ['/api/admin/status', '/api/admin/pair-code', '/api/admin/devices/anything', '/health', '/pair', '/mcp?token=secret', '/api/device/other', '/%6dcp'])
    assert.equal((await core.fetch(request(path, { token: ADMIN }))).status, 404, path);
  for (const path of ['/mcp', '/api/pair', '/api/device/state']) {
    assert.equal((await core.fetch(request(path, { method: 'GET', token: ADMIN }))).status, 405);
    assert.equal((await core.fetch(request(path, { token: ADMIN, headers: { origin: ORIGIN } }))).status, 403);
    assert.equal((await core.fetch(request(path, { token: ADMIN, origin: 'http://honbako.example' }))).status, 403);
    assert.equal((await core.fetch(request(path, { token: ADMIN, origin: 'https://evil.example' }))).status, 403);
  }
});
test('Grok, owner, pairing and device credentials stay isolated; phone cannot change another phone job', async () => {
  const { core } = fixture(), phone = await pair(core), grok = await grant(core);
  for (const token of [ADMIN, PAIRING, phone.deviceToken, 'X'.repeat(43)]) assert.equal((await core.fetch(request('/mcp', { token }))).status, 401);
  for (const token of [grok, ADMIN, PAIRING]) assert.equal((await core.fetch(request('/api/device/jobs', { token, method: 'GET' }))).status, 401);
  await assert.rejects(core.admin('status', {}, grok), /Administrator credential/);
  await assert.rejects(core.admin('status', {}, PAIRING), /Administrator credential/);
  const second = await pair(core), otherJob = await core.store.mutate(data => core.store.createJob(data, core.store.device(data, phone.deviceId), 'catalog.search', { query: 'one', sourceIds: ['owned'], limit: 1 }));
  assert.equal((await core.fetch(request(`/api/device/jobs/${otherJob.id}/status`, { token: second.deviceToken, body: { status: 'failed', error: 'foreign job' } }))).status, 404);
});
test('hosted SDK exposes exactly the eight metadata tools plus two opt-in coaching tools over stateless JSON', async () => {
  const { core } = fixture(), token = await grant(core), r = await core.fetch(request('/mcp', { token, body: { jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} }, headers: { 'mcp-protocol-version': '2025-11-25' } }));
  assert.equal(r.status, 200); const result = await r.json(); assert.equal(result.result.tools.length, 10);
  assert.deepEqual(result.result.tools.map(x => x.name).sort(), ['honbako_add_to_library', 'honbako_annotate_page', 'honbako_cancel_job', 'honbako_get_coaching_page', 'honbako_get_job', 'honbako_get_reading_context', 'honbako_get_status', 'honbako_list_sources', 'honbako_search_catalog', 'honbako_search_library']);
  assert.equal(r.headers.get('access-control-allow-origin'), null); assert.equal(r.headers.get('cache-control'), 'no-store');
});
test('Grok grants have absolute 24h expiry and durable revocation/replacement', async () => {
  const { core, open, advance } = fixture(), first = await grant(core);
  await assert.rejects(core.admin('grant', { lifetimeSeconds: 86401 }, ADMIN), /24 hours/);
  const status = await core.admin('status', {}, ADMIN); assert.equal(Date.parse(status.grant.expiresAt) - Date.parse(status.grant.createdAt), 86400000);
  advance(86400000); assert.equal((await open().fetch(request('/mcp', { token: first }))).status, 401);
  const restarted = open(), second = await grant(restarted); await restarted.admin('revoke-grant', {}, ADMIN);
  assert.equal((await open().fetch(request('/mcp', { token: second }))).status, 401);
  assert.notEqual(await grant(restarted), second); assert.equal(restarted.store.control('grok-grant').token, undefined);
});
test('pairing global and IP limits survive object restarts', async () => {
  const { core, open } = fixture();
  for (let i = 0; i < 10; i++) assert.equal((await core.fetch(request('/api/pair', { body: { code: '000000', name: 'Invalid' } }))).status, 401);
  assert.equal((await open().fetch(request('/api/pair', { body: { code: '000000', name: 'Invalid' } }))).status, 429);
  for (const ip of ['203.0.113.2', '203.0.113.3']) for (let i = 0; i < 10; i++) assert.equal((await open().fetch(request('/api/pair', { ip, body: { code: '000000', name: 'Invalid' } }))).status, 401);
  assert.equal((await open().fetch(request('/api/pair', { ip: '203.0.113.4', body: { code: '000000', name: 'Invalid' } }))).status, 429);
});
test('body limits reject invalid JSON, encoded and oversized bodies', async () => {
  const { core } = fixture();
  assert.equal((await core.fetch(request('/api/pair', { body: '[1,2]' }))).status, 400);
  assert.equal((await core.fetch(request('/api/pair', { headers: { 'content-encoding': 'gzip' } }))).status, 415);
  assert.equal((await core.fetch(request('/api/pair', { body: `{"data":"${'x'.repeat(1024 * 1024)}"}` }))).status, 413);
  const stream = new ReadableStream({ start(c) { c.enqueue(new Uint8Array(11)); c.close(); } }); await assert.rejects(boundedBytes(stream, 10), /size limit/);
});
test('migration preserves 30 unclaimed items, phone auth and job identities after restart', async () => {
  const { core, open } = fixture(), state = migrationState(), envelope = { version: 1, state, sha256: stateDigest(state) };
  assert.deepEqual(await core.admin('import-state', envelope, ADMIN), { devices: 1, jobs: 2, pendingJobs: 2 });
  const restarted = open(), restored = restarted.store.data; assert.deepEqual(restored.jobs, state.jobs); assert.equal(restored.pairing, null);
  assert.equal(restarted.store.authenticateDevice(DEVICE), state.devices[0].id); assert.equal(restored.jobs.reduce((n, x) => n + x.payload.items.length, 0), 30);
  assert.ok(restored.jobs.every(x => !x.executionClaimed)); assert.equal((await restarted.admin('status', {}, ADMIN)).migration.pendingItems, 30);
  await assert.rejects(restarted.admin('import-state', envelope, ADMIN), /empty hosted/);
});
test('migration rejects bad checksum, duplicate identities, executing work and unknown secret fields', () => {
  const envelope = state => ({ version: 1, state, sha256: stateDigest(state) }), original = migrationState();
  assert.throws(() => validateMigration({ ...envelope(original), sha256: '0'.repeat(64) }), /checksum/);
  const duplicate = structuredClone(original); duplicate.jobs.push(duplicate.jobs[0]); assert.throws(() => validateMigration(envelope(duplicate)), /identities/);
  const executing = structuredClone(original); executing.jobs[0].executionClaimed = true; assert.throws(() => validateMigration(envelope(executing)), /executing jobs/);
  const unknown = structuredClone(original); unknown.devices[0].deviceToken = DEVICE; assert.throws(() => validateMigration(envelope(unknown)));
});
test('failed SQLite commit rolls back persisted and in-memory state; queue recovers', async () => {
  const { core, db, open } = fixture(), phone = await pair(core), before = structuredClone(core.store.data), original = db.sql.exec; let fail = true;
  db.sql.exec = (statement, ...args) => { if (fail && statement.startsWith('INSERT OR REPLACE INTO bridge_jobs')) throw new Error('simulated disk failure'); return original(statement, ...args); };
  const mutate = () => core.store.mutate(data => core.store.createJob(data, core.store.device(data, phone.deviceId), 'catalog.search', { query: 'one', sourceIds: ['owned'], limit: 1 }));
  await assert.rejects(mutate(), /disk failure/); assert.deepEqual(core.store.data, before); assert.deepEqual(open().store.data, before);
  fail = false; await mutate(); assert.equal(open().store.data.jobs.length, 1);
});
test('private admin Worker still requires owner key; local facade rejects remote and browser access', async () => {
  const { core } = fixture(), env = { OWNER_NAME: 'owned', HONBAKO_OWNER: { idFromName: x => x, get: () => ({ admin: (...args) => core.admin(...args) }) } };
  const invoke = token => adminWorker.fetch(new Request('https://admin.internal/admin', { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: '{"action":"status"}' }), env);
  assert.equal((await invoke(ADMIN)).status, 200); assert.equal((await invoke(PAIRING)).status, 401);
  const binding = { REMOTE_ADMIN: { fetch: () => new Response('{}') } };
  assert.equal((await localAdmin.fetch(request('/admin', { origin: 'https://evil.example' }), binding)).status, 404);
  assert.equal((await localAdmin.fetch(request('/admin', { origin: 'http://127.0.0.1:8789', headers: { origin: 'https://evil.example' } }), binding)).status, 404);
  assert.equal((await localAdmin.fetch(request('/admin', { origin: 'http://127.0.0.1:8789' }), binding)).status, 200);
});
test('hash-only grant restoration preserves the original key and expiry without renewal', async () => {
  const { core, open, advance } = fixture(), token = 'R'.repeat(43), original = { tokenHash: digest(token), createdAt: '2026-10-29T11:30:00.000Z', expiresAt: '2026-10-30T11:30:00.000Z' };
  const restored = await core.admin('restore-grant', original, ADMIN);
  assert.equal(restored.expiresAt, original.expiresAt); assert.equal(restored.alreadyPresent, false); assert.equal(restored.token, undefined);
  assert.equal((await open().admin('restore-grant', original, ADMIN)).alreadyPresent, true);
  const r = await open().fetch(request('/mcp', { token, body: { jsonrpc: '2.0', id: 1, method: 'tools/list' }, headers: { 'mcp-protocol-version': '2025-11-25' } }));
  assert.equal(r.status, 200);
  await assert.rejects(core.admin('restore-grant', { ...original, expiresAt: '2026-10-30T12:00:00.000Z' }, ADMIN), /original expiry|original unexpired/);
  await assert.rejects(core.admin('restore-grant', { ...original, token }, ADMIN), /only a valid credential hash/);
  await assert.rejects(core.admin('restore-grant', { ...original, tokenHash: 'f'.repeat(64) }, ADMIN), /empty grant/);
  advance(23.5 * 60 * 60 * 1000);
  assert.equal((await open().fetch(request('/mcp', { token }))).status, 401);
  await assert.rejects(open().admin('restore-grant', original, ADMIN), /unexpired/);
});
test('grant restore rejects future creation, overlong lifetime and invalid/revoked time changes', async () => {
  const { core } = fixture(), base = { tokenHash: 'a'.repeat(64), createdAt: '2026-10-29T11:30:00Z', expiresAt: '2026-10-30T11:30:00Z' };
  for (const value of [{ ...base, createdAt: '2026-10-29T12:01:00Z' }, { ...base, expiresAt: '2026-10-31T12:00:00Z' }, { ...base, revokedAt: '2026-10-29T12:01:00Z' }, { ...base, tokenHash: 'not-a-hash' }]) await assert.rejects(core.admin('restore-grant', value, ADMIN));
  await core.admin('restore-grant', { ...base, revokedAt: '2026-10-29T11:59:00Z' }, ADMIN);
  await assert.rejects(core.admin('restore-grant', base, ADMIN), /identical/);
});
test('pairing codes are one-use and expire after ten minutes; bounded reads time out', async () => {
  const { core, advance } = fixture(), { code } = await core.admin('pair-code', {}, ADMIN), body = { code, name: 'Owned phone' };
  assert.equal((await core.fetch(request('/api/pair', { body }))).status, 200);
  assert.equal((await core.fetch(request('/api/pair', { body }))).status, 401);
  const next = await core.admin('pair-code', {}, ADMIN); advance(600000);
  assert.equal((await core.fetch(request('/api/pair', { body: { code: next.code, name: 'Owned phone' } }))).status, 401);
  const stream = new ReadableStream({ start() {}, cancel() {} });
  await assert.rejects(boundedBytes(stream, 10, 5), error => error.code === 'request_timeout');
});
test('hash restoration cannot reuse admin, pairing or phone credentials, even with malformed grant storage', async () => {
  const { core } = fixture(), phone = await pair(core), base = { createdAt: '2026-10-29T11:30:00.000Z', expiresAt: '2026-10-30T11:30:00.000Z' };
  for (const token of [ADMIN, PAIRING, phone.deviceToken]) {
    const value = { tokenHash: digest(token), ...base };
    await assert.rejects(core.admin('restore-grant', value, ADMIN), error => error.code === 'credential_role_conflict');
    core.store.setControl('grok-grant', value);
    assert.equal((await core.fetch(request('/mcp', { token, body: { jsonrpc: '2.0', id: 1, method: 'tools/list' } }))).status, 401);
  }
});
