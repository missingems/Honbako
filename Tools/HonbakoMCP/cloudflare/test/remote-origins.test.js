import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { randomUUID, createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { OAuthBroker, secret } from '../remote/oauth.js';
import { RemoteWorkspace } from '../remote/workspace.js';
import { remoteBases, remoteRequestBase } from '../remote/origins.js';
import { SqliteBridgeStore } from '../storage.js';
import { digest } from '../../src/store.js';

const origin = 'https://honbako-mcp.jun-19c.workers.dev';
const alias = 'https://mcp.honbako.xyz';
const base = `${origin}/remote`, branded = `${alias}/remote`, routeKey = 'K'.repeat(43);
const request = (at, path, body, token) => new Request(`${at}${path}`, {
  method: body === undefined ? 'GET' : 'POST',
  headers: { accept: 'application/json, text/event-stream', 'content-type': 'application/json', ...(token ? {authorization: `Bearer ${token}`} : {}) },
  ...(body === undefined ? {} : {body: JSON.stringify(body)})
});
const form = (at, values) => new Request(`${at}/oauth/token`, {method: 'POST', headers: {'content-type':'application/x-www-form-urlencoded'}, body: new URLSearchParams(values)});
function fixture() {
  const db = new DatabaseSync(':memory:'), now = Date.now();
  const storage = {sql: {exec(s, ...args) { const p = db.prepare(s); return p.columns().length ? p.all(...args) : (p.run(...args), []); }},
    transactionSync(f) {db.exec('BEGIN'); try {const r = f(); db.exec('COMMIT'); return r;} catch(e) {db.exec('ROLLBACK'); throw e;}}};
  const store = new SqliteBridgeStore(storage, 'P'.repeat(43));
  const lease = {originalTransactionId:'12345', purchaseHash:'purchase', expiresAt:now+86400000, leaseUntil:now+900000};
  const workspace = new RemoteWorkspace(store, {base, aliases:[alias], routeKey, allocate:async()=>{}, verifier:{enroll:async()=>lease}});
  const records = new Map(), recordStore = {get:k=>records.get(k), set:(k,v)=>records.set(k,v), delete:k=>records.delete(k), purge:()=>{}};
  const broker = new OAuthBroker(recordStore, {base, aliases:[alias], routeKey, workspace:()=>workspace});
  return {workspace, records, broker, db};
}
function omitIssuer(records, key) { const value = {...records.get(key)}; delete value.issuer; records.set(key, value); }
async function authorize(f, at, legacy = false) {
  const registration = await f.broker.fetch(request(at, '/oauth/register', {redirect_uris:['https://ai.example/callback']}));
  const client = await registration.json(), verifier = secret();
  if (legacy) omitIssuer(f.records, `client:${client.client_id}`);
  const params = new URLSearchParams({client_id:client.client_id, redirect_uri:client.redirect_uris[0], response_type:'code', scope:'honbako', resource:`${at}/mcp`, code_challenge_method:'S256', code_challenge:createHash('sha256').update(verifier).digest('base64url')});
  const consent = await f.broker.fetch(request(at, `/oauth/authorize?${params}`));
  const html = await consent.text(), id = /mcp-authorize\?request=([a-f0-9-]+)/.exec(html)[1];
  if (legacy) omitIssuer(f.records, `pending:${id}`);
  const cookie = consent.headers.get('set-cookie').split(';')[0];
  assert.match(consent.headers.get('set-cookie'), /^__Host-honbako-oauth=.*; Path=\/; Secure; HttpOnly; SameSite=Lax/);
  assert.ok(html.includes(`${at}/oauth/result`));
  f.broker.approve(id, f.phone.deviceId, true);
  return {client, verifier, id, cookie, params};
}
async function code(f, at, legacy = false) {
  const auth = await authorize(f, at, legacy);
  const resultRequest = host => new Request(`${host}/oauth/result?request=${auth.id}`, {headers:{cookie:auth.cookie}});
  const other = at === base ? branded : base;
  await assert.rejects(f.broker.fetch(resultRequest(other)), {status:400});
  const result = await (await f.broker.fetch(resultRequest(at))).json();
  const value = new URL(result.redirect).searchParams.get('code');
  if (legacy) omitIssuer(f.records, `code:${digest(value)}`);
  return {grant_type:'authorization_code', client_id:auth.client.client_id, redirect_uri:auth.client.redirect_uris[0], resource:`${at}/mcp`, code_verifier:auth.verifier, code:value};
}
async function enroll(f) {
  f.identity = {installationId:randomUUID(), deviceSecret:secret(), name:'Owned phone'};
  f.phone = await f.workspace.enroll(f.identity);
}
const tools = {jsonrpc:'2.0', id:1, method:'tools/list'};

test('Only exact configured HTTPS origins work, with no wildcard, forwarded-host or prefix match', () => {
  const bases = remoteBases(origin, [alias]);
  assert.equal(remoteRequestBase(request(branded, '/mcp'), bases), branded);
  for (const bad of ['https://mcp.honbako.xyz.evil.example', 'https://test-mcp.honbako.xyz', 'http://mcp.honbako.xyz', 'https://mcp.honbako.xyz:8443'])
    assert.throws(()=>remoteRequestBase(request(`${bad}/remote`, '/mcp'), bases), {status:403});
  assert.throws(()=>remoteRequestBase(new Request('https://evil.example/remote/mcp', {headers:{'x-forwarded-host':'mcp.honbako.xyz'}}), bases), {status:403});
  for (const aliases of [['https://mcp.honbako.xyz/'], ['https://mcp.honbako.xyz/path'], ['http://mcp.honbako.xyz'], ['https://*.honbako.xyz'], 'https://mcp.honbako.xyz']) {
    assert.throws(()=>remoteBases(origin, aliases), {status:403});
  }
});

test('Legacy registrations, in-flight consent/code, access and refresh grants remain valid only at their original issuer', async () => {
  const f = fixture();
  try {
    await enroll(f);
    const fields = await code(f, base, true);
    await assert.rejects(f.broker.fetch(form(branded, {...fields, resource:`${branded}/mcp`})), {status:401});
    assert.ok(f.records.has(`code:${digest(fields.code)}`));
    const tokens = await (await f.broker.fetch(form(base, fields))).json();
    const grants = f.workspace.grants().map(g=>{const v={...g};delete v.issuer;return v;});
    f.workspace.store.setControl('remote-grants', grants);
    assert.equal((await f.workspace.fetch(request(base, '/mcp', tools, tokens.access_token))).status, 200);
    assert.equal((await f.workspace.fetch(request(branded, '/mcp', tools, tokens.access_token))).status, 401);
    await assert.rejects(f.workspace.refresh(tokens.refresh_token, fields.client_id, branded), {status:400});
    assert.equal(f.workspace.grants().length, 1);
    const refreshed = await (await f.broker.fetch(form(base, {grant_type:'refresh_token', client_id:fields.client_id, resource:`${base}/mcp`, refresh_token:tokens.refresh_token}))).json();
    assert.ok(refreshed.access_token);
    assert.equal(f.workspace.grants()[0].familyId, grants[0].familyId);
    assert.equal(f.workspace.grants()[0].issuer, base);
  } finally {f.db.close();}
});

test('Branded consent, resource, code and tokens bind to branded issuer while phone pairing and snapshot stay unchanged', async () => {
  const f = fixture();
  try {
    await enroll(f);
    const snapshot = {schemaVersion:1, generatedAt:new Date().toISOString(), library:[{sourceId:'owned',mangaId:'one',title:'Original'}], sources:[]};
    assert.equal((await f.workspace.fetch(request(branded, '/api/device/state', snapshot, f.phone.deviceToken))).status, 200);
    const identity = await f.workspace.enroll(f.identity, undefined, branded);
    assert.equal(identity.endpoint, branded); assert.equal(identity.deviceId, f.phone.deviceId); assert.equal(identity.deviceToken, f.phone.deviceToken);
    assert.equal(f.workspace.store.data.devices.length, 1);
    assert.equal(f.workspace.store.data.devices[0].snapshot.library[0].title, 'Original');
    const fields = await code(f, branded);
    await assert.rejects(f.broker.fetch(form(branded, {...fields, resource:`${base}/mcp`})), {status:400});
    const tokens = await (await f.broker.fetch(form(branded, fields))).json();
    assert.equal(f.workspace.grants()[0].issuer, branded);
    assert.equal((await f.workspace.fetch(request(branded, '/mcp', tools, tokens.access_token))).status, 200);
    const wrongHost = await f.workspace.fetch(request(base, '/mcp', tools, tokens.access_token));
    assert.equal(wrongHost.status,401); assert.ok(wrongHost.headers.get('www-authenticate').includes(origin));
    f.workspace.revoke(tokens.refresh_token, fields.client_id, base); assert.equal(f.workspace.grants().length,1);
    const refreshed = await f.workspace.refresh(tokens.refresh_token, fields.client_id, branded);
    f.workspace.revoke(refreshed.refresh_token, fields.client_id, branded); assert.equal(f.workspace.grants().length,0);
  } finally {f.db.close();}
});

test('Concurrent OAuth exchanges carry request-local issuer across awaited workspace calls', async () => {
  const f = fixture();
  try {
    await enroll(f);
    const oldFields = await code(f, base), newFields = await code(f, branded), calls = [];
    let release;
    const gate = new Promise(resolve=>{release=resolve;});
    f.broker.workspace = () => ({async issue(clientId, issuer) {calls.push({clientId,issuer}); if(calls.length===2)release(); await gate; return {issuer,clientId};}});
    const results = await Promise.all([f.broker.fetch(form(base, oldFields)),f.broker.fetch(form(branded, newFields))]);
    assert.deepEqual(await results[0].json(), {issuer:base,clientId:oldFields.client_id});
    assert.deepEqual(await results[1].json(), {issuer:branded,clientId:newFields.client_id});
    assert.equal(f.broker.base,base); assert.equal(f.workspace.base,base);
  } finally {f.db.close();}
});

test('Frozen deployment configuration preserves legacy issuers, worker identities and environment-specific aliases', async () => {
  const prod = JSON.parse(await readFile(new URL('../wrangler.jsonc',import.meta.url),'utf8'));
  const beta = JSON.parse(await readFile(new URL('../wrangler.remote.jsonc',import.meta.url),'utf8'));
  assert.equal(prod.name,'honbako-mcp'); assert.equal(prod.vars.PUBLIC_ORIGIN,origin);
  assert.equal(beta.name,'honbako-mcp-pro-preview'); assert.equal(beta.vars.PUBLIC_ORIGIN,'https://honbako-mcp-pro-preview.jun-19c.workers.dev');
  assert.deepEqual(prod.vars.REMOTE_ORIGIN_ALIASES,[alias]);
  assert.deepEqual(beta.vars.REMOTE_ORIGIN_ALIASES,['https://test-mcp.honbako.xyz']);
  assert.equal(prod.vars.APP_STORE_ENVIRONMENT,'Production'); assert.equal(beta.vars.APP_STORE_ENVIRONMENT,'Sandbox');
  assert.equal(prod.workers_dev,true); assert.equal(beta.workers_dev,true);
  assert.deepEqual(prod.routes,[{pattern:'mcp.honbako.xyz',custom_domain:true}]);
  assert.deepEqual(beta.routes,[{pattern:'test-mcp.honbako.xyz',custom_domain:true}]);
  assert.deepEqual(prod.migrations.map(x=>x.tag),['v1','v2-remote-pro']); assert.deepEqual(beta.migrations.map(x=>x.tag),['v1-remote-beta']);
});
