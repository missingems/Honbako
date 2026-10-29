import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import http from 'node:http';
import { promisify } from 'node:util';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import { BridgeStore, atomicWrite } from '../src/store.js';
import { startBridge } from '../src/server.js';
import { writeClientConfigs } from '../src/cli.js';
const execute = promisify(execFile);
const baseTime = Date.parse('2026-10-29T12:00:00Z');
const state = (title = 'Original sample', sourceId = 'own-source') => ({ schemaVersion: 1, generatedAt: new Date(baseTime).toISOString(),
  library: [{ sourceId, mangaId: 'book-1', title, lastReadPage: 12 }],
  sources: [{ id: sourceId, name: 'Owner sample catalog', supportsSearch: true }],
  reading: { sourceId, mangaId: 'book-1', title, chapterId: 'chapter-2', chapterTitle: 'Chapter 2', chapterNumber: 2,
    page: 12, lastVisiblePage: 13, totalPages: 30, updatedAt: new Date(baseTime).toISOString(), active: true } });
async function fixture(t) {
  const folder = await fs.mkdtemp(path.join(os.tmpdir(), 'honbako-mcp-test-'));
  let now = baseTime;
  const store = await BridgeStore.open(folder, { clock: () => now });
  const bridge = await startBridge(store, { port: 0 });
  t.after(async () => { await bridge.close(); await fs.rm(folder, { recursive: true, force: true }); });
  const request = (method, route, token, payload, headers = {}) => fetch(`${bridge.url}${route}`, { method,
    headers: { ...(payload === undefined ? {} : { 'content-type': 'application/json' }), ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: payload === undefined ? undefined : JSON.stringify(payload) });
  async function pair(name = 'Fake phone') {
    const { code } = await store.createPairCode();
    const response = await request('POST', '/api/pair', null, { code, name });
    assert.equal(response.status, 200); return response.json();
  }
  async function connect() {
    const client = new Client({ name: 'isolated-test-client', version: '1' });
    await client.connect(new StreamableHTTPClientTransport(new URL(`${bridge.url}/mcp`), { requestInit: { headers: { Authorization: `Bearer ${store.token}` } } }));
    t.after(() => client.close()); return client;
  }
  return { folder, store, bridge, request, pair, connect, advance: milliseconds => { now += milliseconds; } };
}
const tool = async (client, name, args = {}) => client.callTool({ name, arguments: args });
const output = result => { assert.ok(!result.isError, JSON.stringify(result)); return result.structuredContent; };
async function finishSearch(f, phone, args = {}) {
  const client = await f.connect();
  const job = output(await tool(client, 'honbako_search_catalog', { query: 'Moon', ...args }));
  const result = { matches: [{ sourceId: 'own-source', mangaId: 'moon-2', title: 'Original Moon', author: 'Owner' }] };
  assert.equal((await f.request('POST', `/api/device/jobs/${job.id}/status`, phone.deviceToken, { status: 'completed', result })).status, 200);
  return { client, job };
}

test('credentials, one-time pairing, expiry and private durable permissions', async t => {
  const f = await fixture(t);
  assert.equal((await f.request('GET', '/api/device/jobs')).status, 401);
  assert.equal((await f.request('POST', '/mcp', 'incorrect-token-with-enough-length', {})).status, 401);
  const code = await f.store.createPairCode();
  assert.equal((await f.request('POST', '/api/pair', null, { code: 'bad', name: 'Fake' })).status, 400);
  const paired = await f.request('POST', '/api/pair', null, { code: code.code, name: 'Fake' });
  assert.equal(paired.status, 200); const phone = await paired.json();
  assert.equal((await f.request('POST', '/mcp', phone.deviceToken, {})).status, 401);
  assert.equal((await f.request('GET', '/api/device/jobs', f.store.token)).status, 401);
  assert.equal((await f.request('POST', '/api/pair', null, { code: code.code, name: 'Replay' })).status, 401);
  const expired = await f.store.createPairCode(); f.advance(600001);
  assert.equal((await f.request('POST', '/api/pair', null, { code: expired.code, name: 'Expired' })).status, 401);
  const contents = await fs.readFile(path.join(f.folder, 'state.json'), 'utf8');
  assert.ok(!contents.includes(phone.deviceToken)); assert.ok(!contents.includes(f.store.token));
  assert.equal((await fs.stat(f.folder)).mode & 0o777, 0o700);
  for (const file of ['state.json', 'mcp-token']) assert.equal((await fs.stat(path.join(f.folder, file))).mode & 0o777, 0o600);
});

test('pairing attempts are rate-limited independently of device credentials', async t => {
  const f = await fixture(t);
  for (let index = 0; index < 10; index++) assert.equal((await f.request('POST', '/api/pair', null, { code: '000000', name: 'Fake' })).status, 401);
  assert.equal((await f.request('POST', '/api/pair', null, { code: '000000', name: 'Fake' })).status, 429);
});

test('snapshots persist, stale reading is last-known, and clearing replaces all metadata', async t => {
  const f = await fixture(t), phone = await f.pair();
  assert.equal((await f.request('POST', '/api/device/state', phone.deviceToken, state())).status, 200);
  let context = f.store.readingContext({}); assert.equal(context.observation, 'current'); assert.equal(context.reading.active, true);
  assert.equal(context.spoilerBoundary.lastVisiblePage, 13);
  assert.equal(f.store.librarySearch({ query: '', limit: 20 }).matches[0].lastReadPage, 12);
  f.advance(31000); await f.request('GET', '/api/device/jobs', phone.deviceToken);
  context = f.store.readingContext({}); assert.equal(context.connected, true); assert.equal(context.snapshotFresh, false);
  assert.equal(context.observation, 'last_known'); assert.equal(context.reading.active, false);
  await f.bridge.close();
  const reopened = await BridgeStore.open(f.folder, { clock: () => baseTime + 31000 });
  assert.equal(reopened.authenticateDevice(phone.deviceToken), phone.deviceId);
  assert.equal(reopened.readingContext({}).reading.page, 12);
  await reopened.updateSnapshot(phone.deviceId, { schemaVersion: 1, generatedAt: new Date(baseTime).toISOString(), library: [], sources: [], reading: null });
  assert.equal(reopened.readingContext({}).reading, null); assert.equal(reopened.listSources({}).sources.length, 0);
});

test('wire validation rejects invalid page ranges, credential-like IDs and oversized payloads', async t => {
  const f = await fixture(t), phone = await f.pair();
  for (const badId of ['source?token=secret', 'source#fragment', 'https://name:password@example.com/book', 'bad\nidentity']) {
    const input = state(); input.library[0].mangaId = badId;
    assert.equal((await f.request('POST', '/api/device/state', phone.deviceToken, input)).status, 400);
  }
  const reversed = state(); reversed.reading.lastVisiblePage = 11;
  assert.equal((await f.request('POST', '/api/device/state', phone.deviceToken, reversed)).status, 400);
  const outside = state(); outside.reading.lastVisiblePage = 31;
  assert.equal((await f.request('POST', '/api/device/state', phone.deviceToken, outside)).status, 400);
  const large = state(); large.library[0].title = 'x'.repeat(1024 * 1024);
  assert.equal((await f.request('POST', '/api/device/state', phone.deviceToken, large)).status, 413);
  const hostileHost = await new Promise((resolve, reject) => {
    const request = http.request(`${f.bridge.url}/health`, { headers: { Host: 'evil.example' } }, response => { response.resume(); resolve(response.statusCode); });
    request.on('error', reject); request.end();
  });
  assert.equal(hostileHost, 403);
  assert.equal((await f.request('GET', '/health', null, undefined, { Origin: 'https://evil.example' })).status, 403);
});

test('official HTTP SDK supports catalog results, phone approval, addition and idempotent retry', async t => {
  const f = await fixture(t), phone = await f.pair();
  await f.request('POST', '/api/device/state', phone.deviceToken, state());
  const { client, job: search } = await finishSearch(f, phone);
  assert.equal((await client.listTools()).tools.length, 10);
  assert.equal(output(await tool(client, 'honbako_get_job', { jobId: search.id })).result.matches[0].title, 'Original Moon');
  assert.equal((await tool(client, 'honbako_add_to_library', { items: [{ sourceId: 'own-source', mangaId: 'invented' }], idempotencyKey: 'never-invent-ids' })).isError, true);
  const args = { items: [{ sourceId: 'own-source', mangaId: 'moon-2' }], idempotencyKey: 'stable-retry-1' };
  const added = output(await tool(client, 'honbako_add_to_library', args)); assert.equal(added.status, 'queued');
  assert.equal(output(await tool(client, 'honbako_add_to_library', args)).id, added.id);
  assert.equal((await tool(client, 'honbako_add_to_library', { ...args, items: [{ sourceId: 'own-source', mangaId: 'different' }] })).isError, true);
  const result = { added: [{ sourceId: 'own-source', mangaId: 'moon-2', title: 'Original Moon' }], alreadyPresent: [] };
  const route = `/api/device/jobs/${added.id}/status`;
  assert.equal((await f.request('POST', route, phone.deviceToken, { status: 'completed', result })).status, 409);
  assert.equal((await f.request('POST', route, phone.deviceToken, { status: 'awaitingApproval' })).status, 200);
  assert.equal(output(await tool(client, 'honbako_get_job', { jobId: added.id })).executionClaimed, false);
  assert.equal((await f.request('POST', route, phone.deviceToken, { status: 'awaitingApproval', approvalGranted: true })).status, 200);
  assert.equal((await tool(client, 'honbako_cancel_job', { jobId: added.id })).isError, true);
  assert.equal((await f.request('POST', route, phone.deviceToken, { status: 'completed', result })).status, 200);
  const finished = output(await tool(client, 'honbako_get_job', { jobId: added.id })); assert.equal(finished.status, 'completed');
  assert.equal(output(await tool(client, 'honbako_add_to_library', args)).id, finished.id);
  assert.equal(output(await tool(client, 'honbako_cancel_job', { jobId: finished.id })).status, 'completed');
  const persisted = JSON.parse(await fs.readFile(path.join(f.folder, 'state.json'), 'utf8'));
  assert.equal(persisted.jobs.find(job => job.id === finished.id).status, 'completed');
});

test('unclaimed work cancels before execution; devices and jobs remain isolated', async t => {
  const f = await fixture(t), a = await f.pair('Phone A'), b = await f.pair('Phone B');
  await f.request('POST', '/api/device/state', a.deviceToken, state('Private A'));
  await f.request('POST', '/api/device/state', b.deviceToken, state('Private B', 'other-source'));
  const client = await f.connect();
  assert.equal((await tool(client, 'honbako_get_reading_context')).isError, true);
  const aContext = output(await tool(client, 'honbako_get_reading_context', { deviceId: a.deviceId })); assert.equal(aContext.reading.title, 'Private A');
  const job = output(await tool(client, 'honbako_search_catalog', { deviceId: a.deviceId, query: 'Moon' }));
  const bJobs = await (await f.request('GET', '/api/device/jobs', b.deviceToken)).json(); assert.equal(bJobs.jobs.length, 0);
  assert.equal((await f.request('POST', `/api/device/jobs/${job.id}/status`, b.deviceToken, { status: 'failed', error: 'Must not touch another device' })).status, 404);
  assert.equal((await tool(client, 'honbako_get_job', { deviceId: b.deviceId, jobId: job.id })).isError, true);
  assert.equal(output(await tool(client, 'honbako_cancel_job', { deviceId: a.deviceId, jobId: job.id })).status, 'cancelled');
  assert.equal((await f.request('POST', `/api/device/jobs/${job.id}/status`, a.deviceToken, { status: 'completed', result: { matches: [] } })).status, 409);
  const aJobs = await (await f.request('GET', '/api/device/jobs', a.deviceToken)).json(); assert.equal(aJobs.jobs.length, 0);
  assert.equal((await f.request('POST', '/api/device/disconnect', a.deviceToken, {})).status, 200);
  assert.equal((await f.request('GET', '/api/device/jobs', a.deviceToken)).status, 401);
  assert.equal(output(await tool(client, 'honbako_get_reading_context')).reading.title, 'Private B');
  assert.ok(!JSON.stringify(f.store.data).includes('Private A'));
});

test('revocation wins over later serialized snapshot/job mutations', async t => {
  const f = await fixture(t), phone = await f.pair();
  await f.store.updateSnapshot(phone.deviceId, state());
  const drop = f.store.disconnect(phone.deviceId);
  const late = f.store.updateSnapshot(phone.deviceId, state('Must not return'));
  await drop; await assert.rejects(late, error => error.code === 'device_not_found');
  assert.equal(f.store.authenticateDevice(phone.deviceToken), null); assert.equal(f.store.status().devices.length, 0);
});

test('desktop stdio proxy reaches the same server and generated configs do not print credentials', async t => {
  const f = await fixture(t), phone = await f.pair();
  await f.request('POST', '/api/device/state', phone.deviceToken, state('Proxy sample'));
  const saved = { url: f.bridge.url, port: f.bridge.port, host: '127.0.0.1' };
  await atomicWrite(path.join(f.folder, 'server.json'), JSON.stringify(saved));
  const files = await writeClientConfigs(f.folder, { ...saved, token: f.store.token });
  for (const file of Object.values(files)) assert.equal((await fs.stat(file)).mode & 0o777, 0o600);
  const config = JSON.parse(await fs.readFile(files.stdioFile, 'utf8'));
  assert.ok(!JSON.stringify(config).includes(f.store.token));
  const cli = fileURLToPath(new URL('../src/cli.js', import.meta.url));
  const configured = await execute(process.execPath, [cli, 'configure', '--state-dir', f.folder]);
  assert.ok(!configured.stdout.includes(f.store.token)); assert.ok(!configured.stderr.includes(f.store.token));
  const client = new Client({ name: 'fake-desktop', version: '1' });
  const transport = new StdioClientTransport({ command: process.execPath, args: [cli, 'proxy', '--state-dir', f.folder], stderr: 'pipe' });
  let stderr = ''; transport.stderr?.on('data', chunk => { stderr += chunk; });
  await client.connect(transport); t.after(() => client.close());
  const result = output(await tool(client, 'honbako_get_reading_context'));
  assert.equal(result.reading.title, 'Proxy sample'); assert.ok(!JSON.stringify(result).includes(phone.deviceToken));
  await client.close(); assert.ok(!stderr.includes(f.store.token));
});


test('delayed older snapshots cannot restore cleared context or refresh freshness', async t => {
  const f = await fixture(t), phone = await f.pair();
  const old = state('Older reading');
  await f.request('POST', '/api/device/state', phone.deviceToken, old);
  f.advance(1000);
  const cleared = { schemaVersion: 1, generatedAt: new Date(baseTime + 1000).toISOString(), library: [], sources: [], reading: null };
  const clearResponse = await (await f.request('POST', '/api/device/state', phone.deviceToken, cleared)).json();
  f.advance(40000);
  const delayed = await (await f.request('POST', '/api/device/state', phone.deviceToken, old)).json();
  assert.equal(delayed.accepted, false); assert.equal(delayed.receivedAt, clearResponse.receivedAt);
  const context = f.store.readingContext({});
  assert.equal(context.reading, null); assert.equal(context.snapshotFresh, false);
  assert.equal(context.observation, 'last_known'); assert.equal(f.store.librarySearch({ query: '', limit: 20 }).matches.length, 0);
});

test('only this Mac’s hostname and exact local variant pass Host validation', async t => {
  const f = await fixture(t);
  async function rawHost(host) {
    return new Promise((resolve, reject) => {
      const request = http.request(`${f.bridge.url}/health`, { headers: { Host: host } }, response => { response.resume(); resolve(response.statusCode); });
      request.on('error', reject); request.end();
    });
  }
  const actual = os.hostname().toLowerCase();
  assert.equal(await rawHost(actual), 200);
  if (!actual.includes('.')) assert.equal(await rawHost(`${actual}.local`), 200);
  assert.equal(await rawHost('unrelated-host.local'), 403);
});

test('cancelled approval jobs do not execute, and later deliberate retries need a new key', async t => {
  const f = await fixture(t), phone = await f.pair();
  await f.request('POST', '/api/device/state', phone.deviceToken, state());
  const { client } = await finishSearch(f, phone);
  const args = { items: [{ sourceId: 'own-source', mangaId: 'moon-2' }], idempotencyKey: 'cancel-before-approval' };
  const queued = output(await tool(client, 'honbako_add_to_library', args));
  const route = `/api/device/jobs/${queued.id}/status`;
  assert.equal((await f.request('POST', route, phone.deviceToken, { status: 'awaitingApproval' })).status, 200);
  assert.equal(output(await tool(client, 'honbako_cancel_job', { jobId: queued.id })).status, 'cancelled');
  assert.equal((await f.request('POST', route, phone.deviceToken, { status: 'awaitingApproval', approvalGranted: true })).status, 409);
  assert.equal(output(await tool(client, 'honbako_add_to_library', args)).id, queued.id);
  const retry = output(await tool(client, 'honbako_add_to_library', { ...args, idempotencyKey: 'explicit-new-request' }));
  assert.notEqual(retry.id, queued.id); assert.equal(retry.status, 'queued');
  const retryRoute = `/api/device/jobs/${retry.id}/status`;
  await f.request('POST', retryRoute, phone.deviceToken, { status: 'awaitingApproval', approvalGranted: true });
  assert.equal((await f.request('POST', retryRoute, phone.deviceToken, { status: 'completed', result: { added: [], alreadyPresent: [] } })).status, 400);
  assert.equal((await f.request('POST', retryRoute, phone.deviceToken, { status: 'failed', error: 'One item could not be added' })).status, 200);
  assert.equal(output(await tool(client, 'honbako_get_job', { jobId: retry.id })).status, 'failed');
});
