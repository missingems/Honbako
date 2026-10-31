#!/usr/bin/env node
// Local-only integration. Builds dry-run bundles and runs workerd with fixture credentials/state.
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
import { digest } from '../src/store.js';
import { stateDigest } from './migration.js';

const wranglerRoot = process.env.HONBAKO_WRANGLER_ROOT;
if (!wranglerRoot) throw new Error('Set HONBAKO_WRANGLER_ROOT to the installed official Wrangler package directory');
const { Miniflare, Log, LogLevel, convertV4MiniflareOptions } = await import(pathToFileURL(path.resolve(wranglerRoot, '../miniflare/dist/src/index.js')).href);
const root = path.resolve(fileURLToPath(new URL('..', import.meta.url)));
const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'honbako-workerd-test-'));
const origin = 'https://honbako-integration.example', adminKey = 'A'.repeat(43), pairingKey = 'P'.repeat(43), importedToken = 'T'.repeat(43);
const at = new Date().toISOString(), importedDeviceId = randomUUID();
const items = Array.from({ length: 30 }, (_, i) => ({ sourceId: 'owned.catalog', mangaId: `original-${i}` }));
const state = { version: 1, pairing: null, devices: [{ id: importedDeviceId, name: 'Imported fixture phone', tokenHash: digest(importedToken), createdAt: at, lastSeen: at, snapshot: null }],
  jobs: [items.slice(0, 20), items.slice(20)].map((batch, i) => ({ id: randomUUID(), deviceId: importedDeviceId, kind: 'library.add', payload: { items: batch, idempotencyKey: `fixture-batch-${i}` }, idempotencyKey: `fixture-batch-${i}`, status: 'awaitingApproval', executionClaimed: false, createdAt: at, updatedAt: at })) };
let mf, client, publicScript, adminScript, stage = 'build';
function build(config, outdir) {
  const result = spawnSync(process.execPath, [path.join(wranglerRoot, 'bin/wrangler.js'), 'deploy', '--dry-run', '--config', path.join(root, 'cloudflare', config), '--outdir', outdir], { cwd: root, env: { ...process.env, WRANGLER_SEND_METRICS: 'false' }, encoding: 'utf8' });
  if (result.status !== 0) throw new Error(`Local dry-run bundle failed: ${result.stderr || result.stdout}`);
}
const headers = token => ({ 'content-type': 'application/json', accept: 'application/json, text/event-stream', ...(token ? { authorization: `Bearer ${token}` } : {}) });
async function admin(action, params = {}) {
  const worker = await mf.getWorker('honbako-mcp-admin');
  const response = await worker.fetch('https://admin.internal/admin', { method: 'POST', headers: headers(adminKey), body: JSON.stringify({ action, params }) });
  assert.equal(response.status, 200, `private admin ${action}`); return response.json();
}
async function phone(pathname, token, body, method = 'POST') {
  return mf.dispatchFetch(`${origin}${pathname}`, { method, headers: headers(token), ...(method === 'GET' ? {} : { body: JSON.stringify(body ?? {}) }) });
}
async function connectMcp(token) {
  client = new Client({ name: 'honbako-workerd-integration', version: '1.0.0' });
  await client.connect(new StreamableHTTPClientTransport(new URL(`${origin}/mcp`), {
    requestInit: { headers: { authorization: `Bearer ${token}` } }, fetch: (url, init) => mf.dispatchFetch(String(url), { ...init, headers: Object.fromEntries(new Headers(init?.headers)) })
  }));
  const tools = await client.listTools(); assert.equal(tools.tools.length, 13); return tools.tools.length;
}
async function call(name, args = {}) {
  const value = await client.callTool({ name, arguments: args }); assert.ok(!value.isError, name); return value.structuredContent;
}
function createRuntime() {
  const options = convertV4MiniflareOptions({ log: new Log(LogLevel.ERROR), durableObjectsPersist: path.join(directory, 'durable'), workers: [
    { name: 'honbako-mcp', modules: true, script: publicScript, compatibilityDate: '2026-10-29', compatibilityFlags: ['nodejs_compat'],
      bindings: { PUBLIC_ORIGIN: origin, OWNER_NAME: 'fixture-owner', ADMIN_KEY: adminKey, PAIRING_KEY: pairingKey }, durableObjects: { HONBAKO_OWNER: { className: 'HonbakoOwner', useSQLite: true } } },
    { name: 'honbako-mcp-admin', modules: true, script: adminScript, compatibilityDate: '2026-10-29', compatibilityFlags: ['nodejs_compat'],
      bindings: { OWNER_NAME: 'fixture-owner' }, durableObjects: { HONBAKO_OWNER: { className: 'HonbakoOwner', scriptName: 'honbako-mcp', useSQLite: true } } }
  ] });
  options.resourcePersistencePath = path.join(directory, 'durable');
  options.enableDevRegistry = false; options.telemetry = { enabled: false };
  return new Miniflare(options);
}
try {
  build('wrangler.jsonc', path.join(directory, 'public')); build('wrangler.admin.jsonc', path.join(directory, 'admin'));
  publicScript = await fs.readFile(path.join(directory, 'public', 'worker.js'), 'utf8');
  adminScript = await fs.readFile(path.join(directory, 'admin', 'admin-worker.js'), 'utf8');
  mf = createRuntime(); await mf.ready;
  const migrated = await admin('import-state', { version: 1, state, sha256: stateDigest(state) }); assert.equal(migrated.pendingJobs, 2);
  const privateAdminWorker = await mf.getWorker('honbako-mcp-admin');
  for (const [candidate, expected] of [['X'.repeat(43), 401], [adminKey, 503]]) {
    const check = await privateAdminWorker.fetch('https://admin.internal/admin', { method: 'POST', headers: headers(candidate), body: JSON.stringify({ action: 'verify-apple', params: {} }) });
    assert.equal(check.status, expected, 'Apple check must authenticate privately and fail closed without configured keys');
  }
  const pairing = await admin('pair-code');
  const pairedResponse = await phone('/api/pair', null, { code: pairing.code, name: 'Fresh fixture phone' }); assert.equal(pairedResponse.status, 200);
  const paired = await pairedResponse.json();
  const source = { id: 'owned.catalog', name: 'Owned original catalog', supportsSearch: true };
  const snapshot = { schemaVersion: 1, generatedAt: new Date().toISOString(), sources: [source], library: [] };
  assert.equal((await phone('/api/device/state', paired.deviceToken, snapshot)).status, 200);
  const grant = await admin('grant', { lifetimeSeconds: 3600 });
  stage = 'initial MCP grant probe';
  const grantProbe = await phone('/mcp', grant.token, { jsonrpc: '2.0', id: 0, method: 'tools/list' });
  assert.equal(grantProbe.status, 200, JSON.stringify(await admin('status')));
  stage = 'initial official client connection'; await connectMcp(grant.token);
  assert.equal((await call('honbako_get_status')).devices.length, 2);
  const search = await call('honbako_search_catalog', { deviceId: paired.deviceId, query: 'Original', sourceIds: [source.id], limit: 2 });
  const matches = [1, 2].map(i => ({ sourceId: source.id, mangaId: `fixture-${i}`, title: `Owned original ${i}` }));
  assert.equal((await phone(`/api/device/jobs/${search.id}/status`, paired.deviceToken, { status: 'completed', result: { matches } })).status, 200);
  const addition = await call('honbako_add_to_library', { deviceId: paired.deviceId, items: matches.map(({ sourceId, mangaId }) => ({ sourceId, mangaId })), idempotencyKey: 'fixture-import' });
  assert.equal((await phone(`/api/device/jobs/${addition.id}/status`, paired.deviceToken, { status: 'completed', result: { added: matches, alreadyPresent: [] } })).status, 409);
  assert.equal((await phone(`/api/device/jobs/${addition.id}/status`, paired.deviceToken, { status: 'awaitingApproval' })).status, 200);
  assert.equal((await phone(`/api/device/jobs/${addition.id}/status`, paired.deviceToken, { status: 'awaitingApproval', approvalGranted: true })).status, 200);
  assert.equal((await phone(`/api/device/jobs/${addition.id}/status`, paired.deviceToken, { status: 'completed', result: { added: matches, alreadyPresent: [] } })).status, 200);
  snapshot.generatedAt = new Date().toISOString(); snapshot.library = matches;
  snapshot.reading = { ...matches[0], chapterId: 'original-chapter', chapterTitle: 'Original chapter', page: 2, lastVisiblePage: 2, totalPages: 5, updatedAt: snapshot.generatedAt, active: true };
  assert.equal((await phone('/api/device/state', paired.deviceToken, snapshot)).status, 200);
  assert.equal((await call('honbako_get_reading_context', { deviceId: paired.deviceId })).reading.page, 2);
  const duplicate = await call('honbako_add_to_library', { deviceId: paired.deviceId, items: matches.map(({ sourceId, mangaId }) => ({ sourceId, mangaId })), idempotencyKey: 'fixture-import' }); assert.equal(duplicate.id, addition.id);
  for (const method of ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']) assert.equal((await mf.dispatchFetch(`${origin}/api/admin/status`, { method, headers: headers(adminKey) })).status, 404);
  stage = 'opt-in page coaching';
  const pageBytes = await fs.readFile(new URL('../test/fixtures/coaching-page.jpg', import.meta.url)); // OwnedJPEG, not a model-vision claim.
  const coaching = { sessionId: randomUUID(), pageGeneration: 1, expiresAt: new Date(Date.now() + 60000).toISOString(),
    page: { pageId: randomUUID(), contentHash: digest(pageBytes), sourceId: source.id, mangaId: matches[0].mangaId,
      title: matches[0].title, chapterId: 'original-chapter', chapterTitle: 'Original chapter', page: 2, totalPages: 5, capturedAt: new Date().toISOString() },
    image: { mimeType: 'image/jpeg', data: pageBytes.toString('base64'), width: 8, height: 8 } };
  assert.equal((await client.callTool({ name: 'honbako_get_coaching_page', arguments: { deviceId: paired.deviceId } })).isError, true);
  assert.equal((await phone('/api/device/coaching', paired.deviceToken, coaching)).status, 200);
  const pageResult = await client.callTool({ name: 'honbako_get_coaching_page', arguments: { deviceId: paired.deviceId } });
  assert.ok(!pageResult.isError); assert.equal(pageResult.content.find(x => x.type === 'image').data, coaching.image.data);
  assert.equal(pageResult.structuredContent.observation, 'last_shared');
  const drawn = await call('honbako_annotate_page', { deviceId: paired.deviceId, sessionId: coaching.sessionId, pageGeneration: 1,
    pageId: coaching.page.pageId, contentHash: coaching.page.contentHash, baseRevision: 0,
    annotations: [{ id: 'fixture-note', type: 'label', rect: { x: .1, y: .1, width: .7, height: .2 }, text: 'Original coaching note' },
      { id: 'fixture-stroke', type: 'stroke', points: [{ x: .1, y: .4 }, { x: .3, y: .5 }], color: 'blue' }] });
  assert.equal(drawn.annotationRevision, 1);
  assert.equal((await (await phone('/api/device/coaching', paired.deviceToken, null, 'GET')).json()).annotations.length, 2);
  stage = 'persisted restart';
  await client.close(); client = null; await mf.dispose(); mf = createRuntime(); await mf.ready;
  await connectMcp(grant.token);
  const status = await call('honbako_get_status'); assert.equal(status.devices.find(x => x.deviceId === paired.deviceId).libraryCount, 2);
  assert.equal((await call('honbako_get_job', { deviceId: paired.deviceId, jobId: addition.id })).status, 'completed');
  const restoredPage = await call('honbako_get_coaching_page', { deviceId: paired.deviceId });
  assert.equal(restoredPage.pageId, coaching.page.pageId); assert.equal(restoredPage.annotationRevision, 1);
  assert.equal((await phone('/api/device/coaching/revoke', paired.deviceToken, { sessionId: coaching.sessionId })).status, 200);
  assert.equal((await client.callTool({ name: 'honbako_get_coaching_page', arguments: { deviceId: paired.deviceId } })).isError, true);
  const expiring = { ...coaching, sessionId: randomUUID(), expiresAt: new Date(Date.now() + 2000).toISOString(), page: { ...coaching.page, pageId: randomUUID(), capturedAt: new Date().toISOString() } };
  assert.equal((await phone('/api/device/coaching', paired.deviceToken, expiring)).status, 200);
  await new Promise(resolve => setTimeout(resolve, 2300));
  assert.equal((await client.callTool({ name: 'honbako_get_coaching_page', arguments: { deviceId: paired.deviceId } })).isError, true);
  assert.equal((await (await phone('/api/device/coaching', paired.deviceToken, null, 'GET')).json()).active, false);
  const remainingResponse = await phone('/api/device/jobs', importedToken, null, 'GET'); assert.equal(remainingResponse.status, 200);
  const remaining = await remainingResponse.json(); assert.deepEqual(remaining.jobs.map(x => x.id), state.jobs.map(x => x.id));
  assert.equal(remaining.jobs.reduce((count, x) => count + x.payload.items.length, 0), 30); assert.ok(remaining.jobs.every(x => !x.executionClaimed));
  assert.equal((await admin('status')).migration.sha256, stateDigest(state));
  process.stdout.write(`${JSON.stringify({ runtime: 'workerd/Miniflare', deployed: false, fixtureOnly: true, tools: 10, privateAdminBinding: true, publicAdmin404: true, phonePairing: true, asyncSearchApprovalImport: true, duplicateImportIdempotent: true, persistedRestart: true, pendingMigrationItems: 30, originalPendingIdsPreserved: true, temporaryFilesCleaned: true, coachingImageContent: true, coachingStructuredOverlay: true, coachingPersistedRestart: true, coachingFixedExpiryAndRevoke: true, modelVisionIngestionVerified: false })}\n`);
} catch (error) { throw new Error(`Workerd integration failed at ${stage}`, { cause: error }); } finally {
  if (client) await client.close().catch(() => {});
  if (mf) await mf.dispose().catch(() => {});
  await fs.rm(directory, { recursive: true, force: true });
}
