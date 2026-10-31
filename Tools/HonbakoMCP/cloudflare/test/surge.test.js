import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { remoteFetch } from '../remote/router.js';
import { routedToken } from '../remote/oauth.js';
import { rpcResult } from '../remote/rpc.js';
import { MemoryLimiter, secondsUntilMidnightUTC } from '../limits.js';
import { DEVICE_RATE } from '../remote/workspace.js';
import { BASE, ROUTE_KEY, cloud, device, tools, state } from './fixtures.js';

const ORIGIN = new URL(BASE).origin;
// Cloudflare's binding behaves as a fixed window per key; this one follows the fixture's clock.
function binding(limit, clock) {
  const windows = new Map();
  return { calls: 0, async limit({ key }) {
    this.calls++;
    assert.ok(!key.includes(ROUTE_KEY) && key.length < 80, 'keys never carry a token or secret');
    const slot = `${Math.floor(clock() / 60000)}:${key}`, count = (windows.get(slot) ?? 0) + 1;
    windows.set(slot, count);
    return { success: count <= limit };
  } };
}
/// The Worker's bindings, with every Durable Object call counted. Workspaces are the fixture's own.
function edge(c, { limiters = true } = {}) {
  const calls = { workspace: 0, broker: 0 };
  const env = { REMOTE_MCP_ENABLED: 'YES', PUBLIC_ORIGIN: ORIGIN, REMOTE_ROUTING_KEY: ROUTE_KEY,
    HONBAKO_WORKSPACE: { idFromName: name => name, get: id => ({ fetch: request => { calls.workspace++; return c.open(id).fetch(request); } }) },
    HONBAKO_AUTH: { idFromName: name => name, get: () => ({
      fetch: async () => { calls.broker++; return new Response('{}', { status: 400 }); },
      enrollmentLimit: () => { calls.broker++; return rpcResult(() => {}); } }) },
    ...(limiters ? { DEVICE_RATE_LIMITER: binding(150, c.clock), AI_RATE_LIMITER: binding(120, c.clock), SETUP_RATE_LIMITER: binding(20, c.clock) } : {}) };
  const send = (path, { token, body, ip = '198.51.100.7', method = body === undefined ? 'GET' : 'POST' } = {}) => remoteFetch(new Request(`${ORIGIN}${path}`, { method,
    headers: { accept: 'application/json, text/event-stream', 'content-type': 'application/json', 'cf-connecting-ip': ip, ...(token ? { authorization: `Bearer ${token}` } : {}) },
    ...(method === 'GET' ? {} : { body: JSON.stringify(body) }) }), env);
  return { env, calls, send };
}
const statuses = responses => responses.reduce((all, r) => ({ ...all, [r.status]: (all[r.status] ?? 0) + 1 }), {});

test('Junk tokens cost one HMAC check and never reach a Durable Object or a rate limiter', async () => {
  const c = cloud(), e = edge(c);
  const junk = [routedToken('d', randomUUID(), 'J'.repeat(43)), routedToken('a', randomUUID(), 'J'.repeat(43)), 'x'.repeat(60)];
  for (let i = 0; i < 90; i++) {
    const r = await e.send(i % 2 ? '/remote/mcp' : '/remote/api/device/jobs', { token: junk[i % 3], ...(i % 2 ? { body: tools } : {}) });
    assert.equal(r.status, 401);
  }
  assert.deepEqual(e.calls, { workspace: 0, broker: 0 });
  assert.equal(e.env.DEVICE_RATE_LIMITER.calls + e.env.AI_RATE_LIMITER.calls, 0);
});

test('A flooding device token gets 429 with Retry-After from the Worker, with no Durable Object call', async () => {
  const c = cloud(), e = edge(c), phone = await c.enroll(device('iPhone')), pad = await c.enroll(device('iPad'));
  const flood = [];
  for (let i = 0; i < 200; i++) flood.push(await e.send('/remote/api/device/jobs', { token: phone.deviceToken }));
  assert.deepEqual(statuses(flood), { 200: 150, 429: 50 });
  assert.equal(e.calls.workspace, 150);
  const refused = flood.at(-1);
  assert.equal(refused.headers.get('retry-after'), '60');
  assert.equal((await refused.json()).error.code, 'rate_limited');
  // The other device of the same workspace has its own allowance.
  assert.equal((await e.send('/remote/api/device/jobs', { token: pad.deviceToken })).status, 200);
  c.advance(60000);
  assert.equal((await e.send('/remote/api/device/jobs', { token: phone.deviceToken })).status, 200);
});

test('AI calls share one limit per workspace at the edge', async () => {
  const c = cloud({ dailyBudget: 100000 }), e = edge(c), phone = await c.enroll(device());
  const one = await c.open(phone.workspaceId).issue('client-one'), two = await c.open(phone.workspaceId).issue('client-two');
  const results = [];
  for (let i = 0; i < 130; i++) results.push(await e.send('/remote/mcp', { token: (i % 2 ? one : two).access_token, body: tools }));
  assert.deepEqual(statuses(results), { 200: 120, 429: 10 });
  assert.equal(e.calls.workspace, 120);
});

test('Setup and OAuth floods from one address get 429 before the broker; another address is unaffected', async () => {
  const c = cloud(), e = edge(c);
  const enroll = [], oauth = [];
  for (let i = 0; i < 25; i++) enroll.push(await e.send('/remote/enroll', { body: { installationId: randomUUID(), deviceSecret: 'S'.repeat(43), name: 'x' } }));
  assert.equal(enroll.slice(0, 20).filter(r => r.status === 429).length, 0);
  assert.deepEqual(enroll.slice(20).map(r => r.status), [429, 429, 429, 429, 429]);
  assert.equal(e.calls.broker, 20);
  for (let i = 0; i < 5; i++) oauth.push(await e.send('/remote/oauth/register', { body: { redirect_uris: ['https://example.com/cb'] } }));
  assert.ok(oauth.every(r => r.status === 429), 'enroll and OAuth share the address allowance');
  assert.equal(e.calls.broker, 20);
  assert.notEqual((await e.send('/remote/oauth/register', { ip: '198.51.100.8', body: {} })).status, 429);
});

test('Without the bindings, or when one fails, the workspace’s own limits still apply', async () => {
  for (const env of [{ limiters: false }, { limiters: true }]) {
    const c = cloud(), e = edge(c, env), phone = await c.enroll(device());
    if (env.limiters) e.env.DEVICE_RATE_LIMITER.limit = async () => { throw new Error('binding unavailable'); };
    const flood = [];
    for (let i = 0; i < DEVICE_RATE + 5; i++) flood.push(await e.send('/remote/api/device/jobs', { token: phone.deviceToken }));
    assert.deepEqual(statuses(flood), { 200: DEVICE_RATE, 429: 5 });
    const retry = Number(flood.at(-1).headers.get('retry-after'));
    assert.ok(retry >= 1 && retry <= 60, String(retry));
    // Disconnecting is never limited.
    assert.equal((await e.send('/remote/api/device/disconnect', { token: phone.deviceToken, body: {} })).status, 200);
  }
});

test('A normal reading pace is never limited, at the edge or in the workspace', async () => {
  const c = cloud(), e = edge(c), phone = await c.enroll(device('iPhone')), pad = await c.enroll(device('iPad'));
  await c.open(phone.workspaceId).issue('client');
  const seen = [];
  // Ten minutes of two devices reading with page sharing: annotations every 0.75 s, jobs every 3 s, state every 15 s.
  for (let tick = 0; tick < 800; tick++) {
    for (const token of [phone.deviceToken, pad.deviceToken]) {
      seen.push(await e.send('/remote/api/device/coaching', { token }));
      if (tick % 4 === 0) seen.push(await e.send('/remote/api/device/jobs', { token }));
      if (tick % 20 === 0) seen.push(await e.send('/remote/api/device/state', { token, body: state({ generatedAt: new Date(c.clock()).toISOString() }) }));
    }
    c.advance(750);
  }
  assert.equal(seen.filter(r => r.status === 429).length, 0);
  assert.ok(seen.every(r => r.status === 200), JSON.stringify(statuses(seen)));
});

test('A workspace over its daily budget waits until 00:00 UTC; the count survives a restart and resets the next day', async () => {
  const c = cloud({ dailyBudget: 250 }), phone = await c.enroll(device());
  for (let i = 0; i < 249; i++) { assert.equal((await c.call(phone.deviceToken, '/api/device/jobs')).status, 200); if (i % 100 === 99) c.advance(61000); }
  // A restart loses at most the last 30 s or 100 requests of the count.
  const restarted = c.restart(phone.workspaceId);
  assert.ok(restarted.budget.requests >= 200, String(restarted.budget.requests));
  let r;
  for (let i = 0; i < 60 && (r = await c.call(phone.deviceToken, '/api/device/jobs')).status === 200; i++);
  assert.equal(r.status, 429);
  assert.equal(Number(r.headers.get('retry-after')), secondsUntilMidnightUTC(c.clock()));
  assert.match((await r.json()).error.message, /today’s limit/);
  // AI calls are refused too, while removing a device still works.
  const ai = await c.open(phone.workspaceId).issue('client');
  assert.equal((await c.call(ai.access_token, '/mcp', tools)).status, 429);
  c.advance(secondsUntilMidnightUTC(c.clock()) * 1000);
  assert.equal((await c.call(phone.deviceToken, '/api/device/jobs')).status, 200);
});

test('Polling and AI reads write no SQLite rows; saved state trails by at most 30 s', async () => {
  const c = cloud(), phone = await c.enroll(device()), ai = await c.open(phone.workspaceId).issue('client');
  assert.equal((await c.call(phone.deviceToken, '/api/device/state', state())).status, 200);
  assert.equal((await c.call(phone.deviceToken, '/api/device/jobs')).status, 200);
  c.advance(31000);
  assert.equal((await c.call(phone.deviceToken, '/api/device/jobs')).status, 200);
  const before = c.rows.written;
  for (let i = 0; i < 20; i++) {
    for (const path of ['/api/device/jobs', '/api/device/coaching', '/api/device/workspace']) assert.equal((await c.call(phone.deviceToken, path)).status, 200);
    assert.equal((await c.call(ai.access_token, '/mcp', tools)).status, 200);
    c.advance(1000);
  }
  assert.equal(c.rows.written - before, 0, 'eighty requests in twenty seconds wrote no rows');
  // Last seen still moves with every poll, in memory: the last one was a second ago.
  const info = await (await c.call(phone.deviceToken, '/api/device/workspace')).json();
  assert.equal(info.devices[0].lastActive, new Date(c.clock() - 1000).toISOString());
  c.advance(30000);
  const saved = c.rows.written;
  assert.equal((await c.call(phone.deviceToken, '/api/device/jobs')).status, 200);
  assert.ok(c.rows.written - saved <= 2, `one device row and the budget, got ${c.rows.written - saved}`);
});

test('The memory limiter reports how long to wait and bounds its key count', () => {
  let now = 0;
  const limiter = new MemoryLimiter(() => now, 3);
  assert.equal(limiter.take(['a'], 2, 60000), null);
  assert.equal(limiter.take(['a'], 2, 60000), null);
  now = 15000;
  assert.equal(limiter.take(['a'], 2, 60000), 45);
  for (const key of ['b', 'c']) assert.equal(limiter.take([key], 2, 60000), null);
  assert.equal(limiter.take(['d'], 2, 60000), 60, 'a full table refuses new keys rather than growing');
  now = 60000;
  assert.equal(limiter.take(['d'], 2, 60000), null, 'expired windows are swept');
});
