import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { randomUUID, createHash } from 'node:crypto';
import { AppleProVerifier, BUNDLE, PRODUCT, LEASE_MS } from '../remote/entitlement.js';
import { RemoteWorkspace } from '../remote/workspace.js';
import { OAuthBroker, secret, routedToken, validRouteToken, tokenParts } from '../remote/oauth.js';
import { SqliteBridgeStore } from '../storage.js';
import { BridgeError } from '../../src/store.js';
const BASE = 'https://honbako.example/remote', ROUTE_KEY = 'K'.repeat(43);
const at = Date.now();
const active = { bundleId: BUNDLE, productId: PRODUCT, type: 'Auto-Renewable Subscription', environment: 'Production', originalTransactionId: '12345', expiresDate: at + 86400000, inAppOwnershipType: 'PURCHASED' };
function verifier(transaction = active, status = 1, renewal) {
  return new AppleProVerifier({}, { clock: () => at, signedVerifier: { async verifyAndDecodeTransaction() { return transaction; },
    async verifyAndDecodeRenewalInfo(value) { if (!value || !renewal) throw new Error('missing renewal'); return renewal; } },
    api: { async getAllSubscriptionStatuses() { return { data: [{ lastTransactions: [{ status, signedTransactionInfo: 'signed', ...(renewal ? { signedRenewalInfo: 'renewal' } : {}) }] }] }; } } });
}
function store(clock) {
  const db = new DatabaseSync(':memory:');
  const storage = { sql: { exec(s, ...args) { const p = db.prepare(s); return p.columns().length ? p.all(...args) : (p.run(...args), []); } },
    transactionSync(f) { db.exec('BEGIN'); try { const r = f(); db.exec('COMMIT'); return r; } catch (e) { db.exec('ROLLBACK'); throw e; } } };
  return new SqliteBridgeStore(storage, 'P'.repeat(43), { clock });
}
function fixture({ current = async () => { throw Object.assign(new Error('Pro expired'), { status: 402 }); } } = {}) {
  let now = at;
  const allocations = new Map();
  const make = () => {
    const s = store(() => now);
    // Mirrors HonbakoAuthorization.allocatePurchase/releasePurchase in worker.js.
    return new RemoteWorkspace(s, { base: BASE, routeKey: ROUTE_KEY, clock: () => now,
      verifier: { async enroll() { return lease(); }, current },
      allocate: async (hash, id) => { const a = allocations.get(hash) ?? []; if (!a.includes(id) && a.length >= 5) throw new BridgeError(429, 'device_limit', 'This subscription already has five remote workspaces'); allocations.set(hash, [...new Set([...a, id])]); },
      release: async (hash, id) => { allocations.set(hash, (allocations.get(hash) ?? []).filter(x => x !== id)); } });
  };
  const lease = (purchaseHash = 'purchase') => ({ originalTransactionId: '12345', purchaseHash, expiresAt: now + 86400000, leaseUntil: now + LEASE_MS });
  return { make, lease, allocations, advance: ms => { now += ms; }, clock: () => now };
}
const enrollment = () => ({ installationId: randomUUID(), deviceSecret: secret(), name: 'Owned phone', signedTransaction: 'x'.repeat(100) });
const req = (path, token, body, method = 'POST') => new Request(`${BASE}${path}`, { method, headers: { accept: 'application/json, text/event-stream', 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, ...(method === 'GET' ? {} : { body: JSON.stringify(body ?? {}) }) });

test('Production Pro requires matching bundle/product, live Apple status, expiry and no revocation', async () => {
  const lease = await verifier().enroll('x'.repeat(100)); assert.equal(lease.leaseUntil, at + LEASE_MS);
  for (const patch of [{ productId: 'other' }, { bundleId: 'other' }, { environment: 'Sandbox' }, { environment: 'Xcode' }, { revocationDate: at - 1 }, { expiresDate: at }, { type: 'Non-Consumable' }])
    await assert.rejects(verifier({ ...active, ...patch }).enroll('x'.repeat(100)), { status: 402 });
  for (const status of [2, 3, 5]) await assert.rejects(verifier(active, status).enroll('x'.repeat(100)), { status: 402 });
  await assert.rejects(verifier().enroll({ hasPro: true }), { status: 402 });
});
test('Annual Pro uses the same verified entitlement checks while unknown products and environment mismatches remain denied', async () => {
  const annual = { ...active, productId: 'com.missingems.honbaku.pro.annual' };
  assert.equal((await verifier(annual).enroll('x'.repeat(100))).originalTransactionId, active.originalTransactionId);
  await assert.rejects(verifier({ ...annual, environment: 'Sandbox' }).enroll('x'.repeat(100)), { status: 402 });
  await assert.rejects(verifier({ ...annual, revocationDate: at }).enroll('x'.repeat(100)), { status: 402 });
});
test('Real Apple verifier rejects unsigned and forged transaction payloads, and missing server keys fails closed', async () => {
  assert.throws(() => new AppleProVerifier({}), { status: 503 });
  const real = new AppleProVerifier({}, { api: {} });
  const fake = `${Buffer.from('{"alg":"none"}').toString('base64url')}.${Buffer.from(JSON.stringify(active)).toString('base64url')}.`;
  await assert.rejects(real.enroll(fake.padEnd(150, 'x')), { status: 402 });
});
test('Private installation identity, route MAC, cross-user and cross-role access stay isolated', async () => {
  const f = fixture(), a = f.make(), b = f.make(), identityA = enrollment(), identityB = enrollment();
  const pa = await a.enroll(identityA), pb = await b.enroll(identityB);
  assert.ok(validRouteToken(pa.deviceToken, ROUTE_KEY));
  assert.ok(!validRouteToken(pa.deviceToken.slice(0, -1) + '!', ROUTE_KEY));
  assert.ok(!validRouteToken(pa.deviceToken.replace(identityA.installationId, identityB.installationId), ROUTE_KEY));
  await assert.rejects(a.enroll({ ...identityA, deviceSecret: secret() }), { status: 401 });
  assert.equal((await b.fetch(req('/api/device/jobs', pa.deviceToken, null, 'GET'))).status, 401);
  const ai = await a.issue(randomUUID());
  assert.equal((await a.fetch(req('/api/device/jobs', ai.access_token, null, 'GET'))).status, 401);
  assert.equal((await a.fetch(req('/mcp', pa.deviceToken))).status, 401);
  assert.equal((await b.fetch(req('/mcp', ai.access_token))).status, 401);
  assert.equal((await a.fetch(req('/api/device/jobs', pb.deviceToken, null, 'GET'))).status, 401);
});
test('Remote requests fail closed when Apple lease expires; disconnect remains available and revokes AI access', async () => {
  const f = fixture(), w = f.make(), phone = await w.enroll(enrollment()), ai = await w.issue('client');
  const list = { jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} };
  assert.equal((await w.fetch(req('/mcp', ai.access_token, list))).status, 200);
  f.advance(LEASE_MS);
  await assert.rejects(w.requirePro(), /Pro expired/);
  const disconnected = await w.fetch(req('/api/device/disconnect', phone.deviceToken, {}));
  assert.equal(disconnected.status, 200);
  assert.equal((await w.fetch(req('/mcp', ai.access_token, list))).status, 401);
  assert.throws(() => w.owner(phone.deviceToken), { status: 401 });
});
test('Refresh credentials rotate, bind the client and revoke access together', async () => {
  const f = fixture(), w = f.make(); await w.enroll(enrollment());
  const first = await w.issue('one');
  await assert.rejects(w.refresh(first.refresh_token, 'two'), { status: 400 });
  const second = await w.refresh(first.refresh_token, 'one');
  await assert.rejects(w.refresh(first.refresh_token, 'one'), { status: 400 });
  assert.notEqual(second.access_token, first.access_token);
  w.revoke(second.refresh_token, 'one');
  assert.equal(w.grants().length, 0);
});
function brokerFixture(workspace, clock = Date.now) {
  const data = new Map();
  const records = { get: k => data.get(k), set: (k, v) => data.set(k, v), delete: k => data.delete(k), purge: now => { for (const [k, v] of data) if (v.until <= now) data.delete(k); } };
  return new OAuthBroker(records, { base: BASE, routeKey: ROUTE_KEY, clock, workspace: () => workspace });
}
async function authorization(broker, overrides = {}) {
  const registered = await broker.fetch(req('/oauth/register', null, { redirect_uris: ['https://ai.example/callback'], client_name: 'My AI' }));
  const client = await registered.json(), verifier = secret();
  const p = new URLSearchParams({ client_id: client.client_id, redirect_uri: client.redirect_uris[0], response_type: 'code', scope: 'honbako', resource: `${BASE}/mcp`, code_challenge_method: 'S256', code_challenge: createHash('sha256').update(verifier).digest('base64url'), state: 'original-state', ...overrides });
  const response = await broker.fetch(new Request(`${BASE}/oauth/authorize?${p}`));
  const html = await response.text(), id = /honbako:\/\/mcp-authorize\?request=([0-9a-f-]+)/.exec(html)[1];
  const cookie = response.headers.get('set-cookie').split(';')[0];
  return { client, verifier, id, cookie };
}
const form = values => new Request(`${BASE}/oauth/token`, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(values) });
test('OAuth needs explicit phone consent, original browser cookie, exact resource and single-use PKCE code', async () => {
  const f = fixture(), w = f.make(), phone = await w.enroll(enrollment()), broker = brokerFixture(w), auth = await authorization(broker);
  assert.equal(broker.pending(auth.id).clientName, 'My AI');
  const result = () => broker.fetch(new Request(`${BASE}/oauth/result?request=${auth.id}`, { headers: { cookie: auth.cookie } }));
  assert.equal((await (await result()).json()).waiting, true);
  await assert.rejects(broker.fetch(new Request(`${BASE}/oauth/result?request=${auth.id}`)), { status: 401 });
  broker.approve(auth.id, phone.deviceId, true);
  const redirect = new URL((await (await result()).json()).redirect);
  assert.equal(redirect.searchParams.get('state'), 'original-state');
  assert.equal(redirect.origin, 'https://ai.example');
  const values = { grant_type: 'authorization_code', client_id: auth.client.client_id, code: redirect.searchParams.get('code'), redirect_uri: 'https://ai.example/callback', resource: `${BASE}/mcp`, code_verifier: auth.verifier };
  const issued = await (await broker.fetch(form(values))).json();
  assert.ok(validRouteToken(issued.access_token, ROUTE_KEY));
  await assert.rejects(broker.fetch(form(values)), { status: 400 });
});
test('OAuth rejects callback substitution, missing PKCE/resource, and denied requests never issue tokens', async () => {
  const f = fixture(), w = f.make(); await w.enroll(enrollment()); const broker = brokerFixture(w);
  for (const patch of [{ redirect_uri: 'https://evil.example' }, { code_challenge_method: 'plain' }, { resource: 'https://another.example/mcp' }, { code_challenge: '' }]) await assert.rejects(authorization(broker, patch), { status: 400 });
  const a = await authorization(broker); broker.approve(a.id, 'ignored', false);
  const r = await broker.fetch(new Request(`${BASE}/oauth/result?request=${a.id}`, { headers: { cookie: a.cookie } }));
  const u = new URL((await r.json()).redirect); assert.equal(u.searchParams.get('error'), 'access_denied'); assert.equal(u.searchParams.has('code'), false);
});

test('Forged refresh routes are rejected before any private workspace is allocated', async () => {
  let calls = 0;
  const broker = brokerFixture({refresh() { calls++; }});
  const client = await (await broker.fetch(req('/oauth/register', null, {redirect_uris:['https://ai.example/callback']}))).json();
  const forged = `r_${randomUUID()}_${secret()}_${'X'.repeat(16)}`;
  await assert.rejects(broker.fetch(form({grant_type:'refresh_token',resource:`${BASE}/mcp`,client_id:client.client_id,refresh_token:forged})), {status:400});
  assert.equal(calls, 0);
});
test('Routing-key rotation re-enrolls the same private installation and preserves its library', async () => {
  const f = fixture(), w = f.make(), identity = enrollment(), old = await w.enroll(identity);
  await w.store.updateSnapshot(old.deviceId, {schemaVersion:1,generatedAt:new Date(at).toISOString(),library:[{sourceId:'owned',mangaId:'one',title:'One'}],sources:[]});
  w.routeKey = 'N'.repeat(43);
  const renewed = await w.enroll(identity);
  assert.notEqual(renewed.deviceToken, old.deviceToken);
  assert.equal(w.store.data.devices[0].snapshot.library.length, 1);
  assert.equal(w.store.authenticateDevice(renewed.deviceToken), old.deviceId);
  assert.equal(w.store.authenticateDevice(old.deviceToken), null);
});

test('Billing grace period (status 4) stays active until Apple’s signed grace expiry, never beyond it', async () => {
  const lapsed = { ...active, expiresDate: at - 1000 }, grace = { originalTransactionId: active.originalTransactionId, gracePeriodExpiresDate: at + 3 * 86400000 };
  const lease = await verifier(lapsed, 4, grace).enroll('x'.repeat(100));
  assert.equal(lease.expiresAt, grace.gracePeriodExpiresDate); assert.equal(lease.leaseUntil, at + LEASE_MS);
  await assert.rejects(verifier(lapsed, 4, { ...grace, gracePeriodExpiresDate: at - 1 }).enroll('x'.repeat(100)), { status: 402 });
  await assert.rejects(verifier(lapsed, 4).enroll('x'.repeat(100)), { status: 402 });
  await assert.rejects(verifier(lapsed, 4, { ...grace, originalTransactionId: '999' }).enroll('x'.repeat(100)), { status: 402 });
  await assert.rejects(verifier(lapsed, 1, grace).enroll('x'.repeat(100)), { status: 402 });
});
test('Cloud AI connectors may omit scope and resource; other scopes and audiences are still rejected', async () => {
  const f = fixture(), w = f.make(), phone = await w.enroll(enrollment()), broker = brokerFixture(w);
  for (const patch of [{ scope: 'other' }, { scope: 'honbako extra' }, { resource: `${BASE}/mcp/x` }]) await assert.rejects(authorization(broker, patch), { status: 400, code: 'invalid_request' });
  for (const patch of [{ scope: '' }, { resource: `${BASE}/mcp/` }]) assert.ok((await authorization(broker, patch)).id);
  const p = new URLSearchParams({ client_id: (await authorization(broker)).client.client_id, redirect_uri: 'https://ai.example/callback', response_type: 'code', code_challenge_method: 'S256', code_challenge: createHash('sha256').update(secret()).digest('base64url') });
  assert.equal((await broker.fetch(new Request(`${BASE}/oauth/authorize?${p}`))).status, 200);
  const auth = await authorization(broker); broker.approve(auth.id, phone.deviceId, true);
  const code = new URL((await (await broker.fetch(new Request(`${BASE}/oauth/result?request=${auth.id}`, { headers: { cookie: auth.cookie } }))).json()).redirect).searchParams.get('code');
  const issued = await (await broker.fetch(form({ grant_type: 'authorization_code', client_id: auth.client.client_id, code, redirect_uri: 'https://ai.example/callback', code_verifier: auth.verifier }))).json();
  await assert.rejects(broker.fetch(form({ grant_type: 'refresh_token', client_id: auth.client.client_id, refresh_token: issued.refresh_token, resource: 'https://another.example/mcp' })), { status: 400, code: 'invalid_request' });
  const refreshed = await broker.fetch(form({ grant_type: 'refresh_token', client_id: auth.client.client_id, refresh_token: issued.refresh_token, resource: `${BASE}/mcp/` }));
  assert.equal(refreshed.status, 200);
  const challenge = (await w.fetch(req('/mcp', 'x'.repeat(43)))).headers.get('www-authenticate');
  assert.ok(challenge.includes('scope="honbako"'));
});
test('Token endpoint uses RFC 6749 invalid_grant for spent codes, bad verifiers, reused refresh tokens and a Pro lapse', async () => {
  const f = fixture({ current: async () => { throw new BridgeError(402, 'pro_required', 'Remote MCP requires an active Pro subscription'); } });
  const w = f.make(), phone = await w.enroll(enrollment()), broker = brokerFixture(w, f.clock);
  const code = async () => {
    const auth = await authorization(broker); broker.approve(auth.id, phone.deviceId, true);
    const c = new URL((await (await broker.fetch(new Request(`${BASE}/oauth/result?request=${auth.id}`, { headers: { cookie: auth.cookie } }))).json()).redirect).searchParams.get('code');
    return { grant_type: 'authorization_code', client_id: auth.client.client_id, code: c, redirect_uri: 'https://ai.example/callback', code_verifier: auth.verifier };
  };
  const wrong = await code();
  await assert.rejects(broker.fetch(form({ ...wrong, code_verifier: secret() })), { status: 400, code: 'invalid_grant' });
  await assert.rejects(broker.fetch(form(wrong)), { status: 400, code: 'invalid_grant' });
  const late = await code(); f.advance(61000);
  await assert.rejects(broker.fetch(form(late)), { status: 400, code: 'invalid_grant' });
  const values = await code(), issued = await (await broker.fetch(form(values))).json();
  await assert.rejects(broker.fetch(form(values)), { status: 400, code: 'invalid_grant' });
  const refresh = { grant_type: 'refresh_token', client_id: values.client_id, refresh_token: issued.refresh_token };
  const next = await (await broker.fetch(form(refresh))).json();
  await assert.rejects(broker.fetch(form(refresh)), { status: 400, code: 'invalid_grant' });
  await assert.rejects(broker.fetch(form({ ...refresh, refresh_token: next.refresh_token, client_id: randomUUID() })), { status: 401, code: 'invalid_client' });
  f.advance(LEASE_MS);
  await assert.rejects(broker.fetch(form({ ...refresh, refresh_token: next.refresh_token })), { status: 400, code: 'invalid_grant' });
});
test('A registration in use slides its 30-day window while idle registrations still expire', async () => {
  const f = fixture({ current: async () => f.lease() }), w = f.make(), phone = await w.enroll(enrollment()), broker = brokerFixture(w, f.clock);
  const used = await authorization(broker), idle = await authorization(broker); broker.approve(used.id, phone.deviceId, true);
  const code = new URL((await (await broker.fetch(new Request(`${BASE}/oauth/result?request=${used.id}`, { headers: { cookie: used.cookie } }))).json()).redirect).searchParams.get('code');
  let issued = await (await broker.fetch(form({ grant_type: 'authorization_code', client_id: used.client.client_id, code, redirect_uri: 'https://ai.example/callback', code_verifier: used.verifier }))).json();
  for (let day = 0; day < 3; day++) {
    f.advance(20 * 86400000);
    issued = await (await broker.fetch(form({ grant_type: 'refresh_token', client_id: used.client.client_id, refresh_token: issued.refresh_token }))).json();
    assert.ok(issued.refresh_token);
  }
  assert.ok((await authorization(broker, { client_id: used.client.client_id })).id);
  await assert.rejects(authorization(broker, { client_id: idle.client.client_id }), { status: 400, message: /expired/ });
  f.advance(31 * 86400000);
  await assert.rejects(broker.fetch(form({ grant_type: 'refresh_token', client_id: used.client.client_id, refresh_token: issued.refresh_token })), { status: 401, code: 'invalid_client' });
});
