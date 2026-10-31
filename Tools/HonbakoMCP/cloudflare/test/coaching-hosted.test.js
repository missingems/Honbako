import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { SqliteBridgeStore } from '../storage.js';
import { HostedBridgeCore } from '../core.js';
import { digest } from '../../src/store.js';
const ADMIN = 'A'.repeat(43), PAIR = 'P'.repeat(43), ORIGIN = 'https://coaching.example';
const jpeg = readFileSync(new URL('../../test/fixtures/coaching-page.jpg', import.meta.url));
function fixture() {
  const db = new DatabaseSync(':memory:'); let alarm = null, now = Date.parse('2026-10-29T14:00:00Z');
  const storage = { sql: { exec(sql, ...args) { const statement = db.prepare(sql); return statement.columns().length ? statement.all(...args) : (statement.run(...args), []); } },
    transactionSync(change) { db.exec('BEGIN'); try { const out = change(); db.exec('COMMIT'); return out; } catch (error) { db.exec('ROLLBACK'); throw error; } },
    async setAlarm(at) { alarm = at; }, async deleteAlarm() { alarm = null; } };
  const open = () => new HostedBridgeCore(new SqliteBridgeStore(storage, PAIR, { clock: () => now }), { publicOrigin: ORIGIN, adminKey: ADMIN, clock: () => now });
  return { db, open, core: open(), advance(ms) { now += ms; }, get alarm() { return alarm; }, get now() { return now; } };
}
const request = (route, token, body, method = 'POST') => new Request(ORIGIN + route, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}), accept: 'application/json, text/event-stream' }, ...(body ? { body: JSON.stringify(body) } : {}) });
async function pair(core) { const { code } = await core.admin('pair-code', {}, ADMIN); return (await core.fetch(request('/api/pair', null, { code, name: 'Hosted fixture' }))).json(); }
const payload = at => ({ sessionId: randomUUID(), pageGeneration: 1, expiresAt: new Date(at + 600000).toISOString(),
  page: { pageId: randomUUID(), contentHash: digest(jpeg), sourceId: 'owned', mangaId: 'owned-book', title: 'Original page', chapterId: 'chapter-1', chapterTitle: 'One', page: 1, capturedAt: new Date(at).toISOString() },
  image: { mimeType: 'image/jpeg', data: jpeg.toString('base64'), width: 8, height: 8 } });
test('hosted page bytes survive object eviction only until fixed expiry and stay out of exports/jobs', async () => {
  const f = fixture(), phone = await pair(f.core), page = payload(f.now);
  assert.equal((await f.core.fetch(request('/api/device/coaching', phone.deviceToken, page))).status, 200);
  await f.core.store.flushCoachingAlarm(); assert.equal(f.alarm, Date.parse(page.expiresAt));
  const restarted = f.open(); assert.equal(restarted.store.deviceCoaching(phone.deviceId).pageId, page.page.pageId);
  const exported = await restarted.admin('export-state', {}, ADMIN);
  assert.ok(!JSON.stringify(exported).includes(page.image.data)); assert.ok(!JSON.stringify(exported).includes(page.sessionId)); assert.equal(exported.state.jobs.length, 0);
  f.advance(600000); await restarted.store.expireCoaching();
  const row = JSON.parse([...f.db.prepare('SELECT value FROM bridge_coaching WHERE id = ?').all(phone.deviceId)][0].value);
  assert.equal(row.image, undefined); assert.equal(row.page, undefined); assert.deepEqual(row.annotations, []); assert.equal(f.alarm, null);
  assert.equal(f.open().store.deviceCoaching(phone.deviceId).active, false);
});
test('hosted coaching routes need phone credentials and Grok cannot publish, revoke or forget pages', async () => {
  const f = fixture(), phone = await pair(f.core), grant = await f.core.admin('grant', {}, ADMIN), page = payload(f.now);
  for (const token of [ADMIN, PAIR, grant.token, 'X'.repeat(43)]) assert.equal((await f.core.fetch(request('/api/device/coaching', token, page))).status, 401);
  for (const method of ['DELETE', 'PUT', 'OPTIONS']) assert.equal((await f.core.fetch(request('/api/device/coaching', phone.deviceToken, null, method))).status, 405);
  assert.equal((await f.core.fetch(request('/api/device/coaching', phone.deviceToken, page))).status, 200);
  assert.equal((await f.core.fetch(request('/api/device/coaching/revoke', grant.token, { sessionId: page.sessionId }))).status, 401);
  const paused = await (await f.core.fetch(request('/api/device/coaching/pause', phone.deviceToken, { sessionId: page.sessionId, pageGeneration: 1, pageId: page.page.pageId }))).json();
  assert.equal(paused.active, true); assert.equal(paused.observation, 'last_shared');
  await f.core.store.disconnect(phone.deviceId); assert.equal(f.core.store.coachingRecord(phone.deviceId), null);
});

test('hosted connection access survives time and object eviction until device disconnection', async () => {
  const f = fixture(), phone = await pair(f.core), page = { ...payload(f.now), accessMode: 'connection' }; delete page.expiresAt;
  assert.equal((await f.core.fetch(request('/api/device/coaching', phone.deviceToken, page))).status, 200);
  await f.core.store.flushCoachingAlarm(); assert.equal(f.alarm, null);
  f.advance(30 * 24 * 60 * 60 * 1000);
  const restarted = f.open(); await restarted.store.expireCoaching();
  const state = restarted.store.deviceCoaching(phone.deviceId);
  assert.equal(state.active, true); assert.equal(state.expiresAt, null); assert.equal(state.accessMode, 'connection');
  const exported = await restarted.admin('export-state', {}, ADMIN);
  assert.ok(!JSON.stringify(exported).includes(page.image.data));
  await restarted.store.disconnect(phone.deviceId);
  assert.equal(restarted.store.coachingRecord(phone.deviceId), null);
});
test('hosted jobs polls summarise drawings from small SQLite fields, without parsing page pixels', async () => {
  const f = fixture(), phone = await pair(f.core), page = payload(f.now);
  const jobs = async () => (await f.core.fetch(request('/api/device/jobs', phone.deviceToken, null, 'GET'))).json();
  assert.deepEqual((await jobs()).coaching, { active: false, sessionId: null, reason: 'not_shared' });
  await f.core.fetch(request('/api/device/coaching', phone.deviceToken, page));
  const header = f.core.store.coachingHeader(phone.deviceId);
  assert.equal(header.hasImage, true); assert.equal(header.closed, false); assert.equal(header.pageId, page.page.pageId); assert.equal('image' in header, false);
  const shared = await jobs();
  assert.deepEqual(shared.coaching, { active: true, sessionId: page.sessionId, pageGeneration: 1, pageId: page.page.pageId, annotationRevision: 0 });
  assert.ok(!JSON.stringify(shared).includes(page.image.data));
  f.advance(600000);
  assert.deepEqual((await jobs()).coaching, { active: false, sessionId: page.sessionId, reason: 'expired' });
  assert.equal(f.core.store.coachingHeader(phone.deviceId).hasImage, false);
});
