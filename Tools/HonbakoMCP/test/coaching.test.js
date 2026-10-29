import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { promises as fs, readFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
import { BridgeStore, digest } from '../src/store.js';
import { startBridge } from '../src/server.js';
import { COACHING_LIFETIME_MS, MAX_COACHING_IMAGE } from '../src/coaching-schema.js';
const base = Date.parse('2026-10-29T14:00:00Z');
const jpeg = readFileSync(new URL('./fixtures/coaching-page.jpg', import.meta.url)); // Owned8x8JPEG; model vision ingestion is a separate client test.
async function fixture(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'honbako-coaching-test-')); let now = base;
  const store = await BridgeStore.open(directory, { clock: () => now });
  const bridge = await startBridge(store, { port: 0 });
  t.after(async () => { await bridge.close(); for (const timer of store.coachingTimers.values()) clearTimeout(timer); await fs.rm(directory, { recursive: true, force: true }); });
  const request = (route, token, body, method = 'POST') => fetch(bridge.url + route, { method,
    headers: { ...(body ? { 'content-type': 'application/json' } : {}), ...(token ? { authorization: 'Bearer ' + token } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
  const pair = async () => { const { code } = await store.createPairCode(); return (await request('/api/pair', null, { code, name: 'Fixture phone' })).json(); };
  const phone = await pair();
  const payload = () => ({ sessionId: randomUUID(), pageGeneration: 1, expiresAt: new Date(now + COACHING_LIFETIME_MS).toISOString(),
    page: { pageId: randomUUID(), contentHash: digest(jpeg), sourceId: 'own.source', mangaId: 'own-book', title: 'Owned practice page', chapterId: 'chapter-1', chapterTitle: 'First chapter', chapterNumber: 1, page: 2, totalPages: 9, capturedAt: new Date(now).toISOString() },
    image: { mimeType: 'image/jpeg', data: jpeg.toString('base64'), width: 8, height: 8 } });
  const client = new Client({ name: 'coaching-fixture', version: '1' });
  await client.connect(new StreamableHTTPClientTransport(new URL(bridge.url + '/mcp'), { requestInit: { headers: { authorization: 'Bearer ' + store.token } } }));
  t.after(() => client.close());
  return { directory, store, bridge, request, pair, phone, payload, client, advance(ms) { now += ms; } };
}
const fetchPage = (f, deviceId = f.phone.deviceId) => f.client.callTool({ name: 'honbako_get_coaching_page', arguments: { deviceId } });
const drawArgs = (page, baseRevision = 0) => ({ sessionId: page.sessionId, pageGeneration: page.pageGeneration, pageId: page.page.pageId,
  contentHash: page.page.contentHash, baseRevision, annotations: [{ id: 'point-this-out', type: 'arrow', from: { x: .1, y: .2 }, to: { x: .3, y: .4 }, color: 'yellow' }] });
test('no image exists until phone approval; official MCP receives image and exact last-shared identity', async t => {
  const f = await fixture(t); assert.equal((await fetchPage(f)).isError, true);
  assert.equal((await f.request('/api/device/coaching', f.store.token, f.payload())).status, 401);
  const payload = f.payload(); assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, payload)).status, 200);
  const result = await fetchPage(f); assert.ok(!result.isError); assert.equal(result.content.filter(x => x.type === 'image').length, 1);
  assert.equal(result.content.find(x => x.type === 'image').data, payload.image.data);
  assert.equal(result.structuredContent.observation, 'last_shared'); assert.equal(result.structuredContent.pageId, payload.page.pageId);
  assert.equal(result.structuredContent.spoilerBoundary.lastVisiblePage, 2);
  const saved = await fs.readFile(path.join(f.directory, 'state.json'), 'utf8');
  assert.ok(!saved.includes(payload.image.data)); assert.ok(!saved.includes(payload.sessionId));
  assert.equal(f.store.data.jobs.length, 0);
});
test('drawing revisions and page generations reject late replies and leave library jobs unchanged', async t => {
  const f = await fixture(t), payload = f.payload(); await f.request('/api/device/coaching', f.phone.deviceToken, payload);
  const args = { ...drawArgs(payload), deviceId: f.phone.deviceId };
  const first = await f.client.callTool({ name: 'honbako_annotate_page', arguments: args }); assert.equal(first.structuredContent.annotationRevision, 1);
  assert.equal((await f.client.callTool({ name: 'honbako_annotate_page', arguments: args })).isError, true);
  const fetched = await (await f.request('/api/device/coaching', f.phone.deviceToken, null, 'GET')).json(); assert.equal(fetched.annotations[0].type, 'arrow');
  const next = { ...payload, pageGeneration: 2, page: { ...payload.page, pageId: randomUUID(), page: 3 } };
  assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, next)).status, 200);
  assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, payload)).status, 409);
  assert.equal((await f.client.callTool({ name: 'honbako_annotate_page', arguments: { ...args, baseRevision: 1 } })).isError, true);
  const current = (await fetchPage(f)).structuredContent; assert.equal(current.annotationRevision, 0); assert.deepEqual(current.annotations, []);
  assert.equal(f.store.data.jobs.length, 0);
});
test('shared cached page stays available offline, but revocation and absolute ten-minute expiry erase it', async t => {
  const f = await fixture(t), payload = f.payload(); await f.request('/api/device/coaching', f.phone.deviceToken, payload);
  await f.request('/api/device/coaching/pause', f.phone.deviceToken, { sessionId: payload.sessionId, pageGeneration: 1, pageId: payload.page.pageId }); f.advance(45000);
  const cached = await fetchPage(f); assert.ok(!cached.isError); assert.equal(cached.structuredContent.observation, 'last_shared');
  assert.equal(cached.structuredContent.deviceFreshness.connected, false);
  assert.equal((await f.client.callTool({ name: 'honbako_annotate_page', arguments: { ...drawArgs(payload), deviceId: f.phone.deviceId } })).isError, undefined);
  const extension = { ...payload, expiresAt: new Date(base + COACHING_LIFETIME_MS + 45000).toISOString() };
  assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, extension)).status, 409);
  f.advance(COACHING_LIFETIME_MS); assert.equal((await fetchPage(f)).isError, true);
  const record = f.store.coachingRecord(f.phone.deviceId); assert.equal(record.image, undefined); assert.equal(record.page, undefined); assert.deepEqual(record.annotations, []);
  assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, { ...payload, page: { ...payload.page, capturedAt: new Date(base + COACHING_LIFETIME_MS + 45000).toISOString() }, expiresAt: new Date(base + 2 * COACHING_LIFETIME_MS).toISOString() })).status, 410);
  const next = f.payload(); await f.request('/api/device/coaching', f.phone.deviceToken, next);
  await f.request('/api/device/coaching/revoke', f.phone.deviceToken, { sessionId: next.sessionId });
  assert.equal((await fetchPage(f)).isError, true); assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, next)).status, 410);
});
test('late initial publish cannot resurrect a revoked consent; forgetting the device clears all coaching bytes', async t => {
  const f = await fixture(t), payload = f.payload(); await f.request('/api/device/coaching/revoke', f.phone.deviceToken, { sessionId: payload.sessionId });
  assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, payload)).status, 410);
  const next = f.payload(); await f.request('/api/device/coaching', f.phone.deviceToken, next);
  await f.store.disconnect(f.phone.deviceId); assert.equal(f.store.coachingRecord(f.phone.deviceId), null);
  assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, null, 'GET')).status, 401);
});
test('normalized labels and freehand strokes are bounded; no HTML, scripts, URLs or nonfinite coordinates execute', async t => {
  const f = await fixture(t), payload = f.payload(); await f.request('/api/device/coaching', f.phone.deviceToken, payload);
  const baseArgs = { ...drawArgs(payload), deviceId: f.phone.deviceId };
  const invalid = [
    [{ id: 'bad', type: 'box', rect: { x: .9, y: .9, width: .5, height: .5 } }],
    [{ id: 'bad', type: 'stroke', points: [{ x: .1, y: .2 }] }],
    [{ id: 'bad', type: 'label', rect: { x: .1, y: .1, width: .5, height: .1 }, text: 'x', html: '<script>bad()</script>' }],
    [{ id: 'bad', type: 'arrow', from: { x: -1, y: .2 }, to: { x: .2, y: .2 } }]
  ];
  for (const annotations of invalid) assert.equal((await f.client.callTool({ name: 'honbako_annotate_page', arguments: { ...baseArgs, annotations } })).isError, true);
  const accepted = [{ id: 'hand', type: 'stroke', points: [{ x: .1, y: .2 }, { x: .2, y: .3 }], color: 'blue' },
    { id: 'note', type: 'label', rect: { x: .1, y: .4, width: .7, height: .2 }, text: 'This is a plain coaching note.' }];
  assert.equal((await f.client.callTool({ name: 'honbako_annotate_page', arguments: { ...baseArgs, annotations: accepted } })).structuredContent.annotations.length, 2);
});
test('page bytes, hashes, sessions and devices are isolated and strictly bounded', async t => {
  const f = await fixture(t), payload = f.payload();
  for (const invalid of [{ ...payload, image: { ...payload.image, data: 'not-base64' } }, { ...payload, page: { ...payload.page, contentHash: 'a'.repeat(64) } },
    { ...payload, image: { ...payload.image, data: Buffer.alloc(MAX_COACHING_IMAGE + 1).toString('base64') } }]) assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, invalid)).status, 400);
  await f.request('/api/device/coaching', f.phone.deviceToken, payload);
  const second = await f.pair(); assert.equal((await fetchPage(f, second.deviceId)).isError, true);
  assert.equal((await f.client.callTool({ name: 'honbako_annotate_page', arguments: { ...drawArgs(payload), deviceId: second.deviceId } })).isError, true);
});

test('resume keeps same-page background drawings and rejects a delayed older pause', async t => {
  const f = await fixture(t), payload = f.payload(); await f.request('/api/device/coaching', f.phone.deviceToken, payload);
  const args = { ...drawArgs(payload), deviceId: f.phone.deviceId };
  await f.client.callTool({ name: 'honbako_annotate_page', arguments: args });
  const paused = { sessionId: payload.sessionId, pageGeneration: 1, pageId: payload.page.pageId };
  assert.equal((await f.request('/api/device/coaching/pause', f.phone.deviceToken, paused)).status, 200);
  const resumed = { ...payload, pageGeneration: 3 };
  assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, resumed)).status, 200);
  assert.equal((await f.request('/api/device/coaching/pause', f.phone.deviceToken, paused)).status, 409);
  const current = (await fetchPage(f)).structuredContent;
  assert.equal(current.pageGeneration, 3); assert.equal(current.annotationRevision, 1); assert.equal(current.annotations.length, 1);
  assert.equal((await f.client.callTool({ name: 'honbako_annotate_page', arguments: { ...args, baseRevision: 1 } })).isError, true);
});
test('a local bridge restart closes old consents without storing page bytes or allowing late resurrection', async t => {
  const f = await fixture(t), payload = f.payload(); await f.request('/api/device/coaching', f.phone.deviceToken, payload);
  const stored = await fs.readFile(path.join(f.directory, 'coaching-tombstones.json'), 'utf8');
  assert.ok(!stored.includes(payload.image.data)); assert.ok(!stored.includes(payload.page.title)); assert.ok(!stored.includes('contentHash'));
  const restarted = await BridgeStore.open(f.directory, { clock: () => base });
  assert.equal(restarted.deviceCoaching(f.phone.deviceId).reason, 'restart');
  await assert.rejects(restarted.publishCoaching(f.phone.deviceId, payload), error => error.code === 'coaching_closed');
  assert.equal(restarted.coachingRecord(f.phone.deviceId).image, undefined);
});

test('connection access has no sharing timer and retains the last page until disconnection', async t => {
  const f = await fixture(t), page = { ...f.payload(), accessMode: 'connection' }; delete page.expiresAt;
  assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, page)).status, 200);
  f.advance(30 * 24 * 60 * 60 * 1000);
  const current = await fetchPage(f);
  assert.equal(current.isError, undefined); assert.equal(current.structuredContent.accessMode, 'connection');
  assert.equal(current.structuredContent.expiresAt, null); assert.equal(current.structuredContent.observation, 'last_shared');
  assert.equal(current.structuredContent.deviceFreshness.connected, false);
  assert.equal((await f.client.callTool({ name: 'honbako_annotate_page', arguments: { ...drawArgs(page), deviceId: f.phone.deviceId } })).structuredContent.annotationRevision, 1);
  assert.equal(f.store.coachingTimers.size, 0);
  await f.store.disconnect(f.phone.deviceId);
  assert.equal(f.store.coachingRecord(f.phone.deviceId), null);
  assert.equal((await fetchPage(f)).isError, true);
});
test('connection access preserves resumed drawings and cannot replace timed consent in place', async t => {
  const f = await fixture(t), timed = f.payload(); await f.request('/api/device/coaching', f.phone.deviceToken, timed);
  const upgrade = { ...timed, accessMode: 'connection' }; delete upgrade.expiresAt;
  assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, upgrade)).status, 409);
  const page = { ...f.payload(), accessMode: 'connection' }; delete page.expiresAt;
  await f.request('/api/device/coaching', f.phone.deviceToken, page);
  await f.client.callTool({ name: 'honbako_annotate_page', arguments: { ...drawArgs(page), deviceId: f.phone.deviceId } });
  await f.request('/api/device/coaching/pause', f.phone.deviceToken, { sessionId: page.sessionId, pageGeneration: 1, pageId: page.page.pageId });
  f.advance(900000);
  const resumed = { ...page, pageGeneration: 3, page: { ...page.page, capturedAt: new Date(base + 900000).toISOString() } };
  assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, resumed)).status, 200);
  const current = (await fetchPage(f)).structuredContent;
  assert.equal(current.annotationRevision, 1); assert.equal(current.annotations.length, 1);
  await f.request('/api/device/coaching/revoke', f.phone.deviceToken, { sessionId: page.sessionId });
  assert.equal((await fetchPage(f)).isError, true);
  assert.equal((await f.request('/api/device/coaching', f.phone.deviceToken, resumed)).status, 410);
});
test('connection access can republish after a bridge restart without storing disk images', async t => {
  const f = await fixture(t), page = { ...f.payload(), accessMode: 'connection' }; delete page.expiresAt;
  await f.request('/api/device/coaching', f.phone.deviceToken, page);
  const restarted = await BridgeStore.open(f.directory, { clock: () => base });
  assert.equal(restarted.deviceCoaching(f.phone.deviceId).reason, 'restart');
  await assert.rejects(restarted.publishCoaching(f.phone.deviceId, page), error => error.code === 'coaching_closed');
  await restarted.publishCoaching(f.phone.deviceId, { ...page, sessionId: randomUUID() });
  assert.equal(restarted.deviceCoaching(f.phone.deviceId).active, true);
  const saved = await fs.readFile(path.join(f.directory, 'coaching-tombstones.json'), 'utf8');
  assert.ok(!saved.includes(page.image.data)); assert.ok(!saved.includes(page.page.title));
});
