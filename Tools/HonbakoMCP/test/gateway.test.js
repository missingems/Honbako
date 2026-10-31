import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
import { gatewayCredential, gatewayCredentialCurrent, revokeGatewayCredential, startMcpGateway, writeGatewayClientConfig } from '../src/gateway.js';
import { BridgeStore } from '../src/store.js';
import { startBridge } from '../src/server.js';
import { options } from '../src/cli.js';

const ownerToken = 'o'.repeat(43);
const grokToken = 'g'.repeat(43);
const message = { jsonrpc: '2.0', id: 1, method: 'ping' };
const waitUntil = async predicate => {
  const end = Date.now() + 3000;
  while (!(await predicate())) {
    if (Date.now() >= end) throw new Error('Timed out waiting for isolated test fixture');
    await new Promise(resolve => setTimeout(resolve, 10));
  }
};
async function temporary(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'honbako-gateway-test-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  return directory;
}
async function mockBridge(t, handler = (_req, res) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end('{"ok":true}'); }) {
  const calls = [];
  const server = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', chunk => chunks.push(chunk));
    req.on('end', () => {
      calls.push({ route: req.url, method: req.method, headers: req.headers, body: Buffer.concat(chunks).toString() });
      handler(req, res);
    });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); });
  return { server, calls, url: `http://127.0.0.1:${server.address().port}` };
}
async function gateway(t, upstream, overrides = {}) {
  const result = await startMcpGateway({ upstreamURL: upstream.url, upstreamToken: ownerToken, token: grokToken, port: 0, ...overrides });
  t.after(() => result.close());
  return result;
}
function post(gateway, body = message, { token = grokToken, headers = {}, route = '/mcp', method = 'POST' } = {}) {
  return fetch(`${gateway.url}${route}`, { method, headers: { 'content-type': 'application/json',
    ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: ['GET', 'HEAD'].includes(method) ? undefined : JSON.stringify(body) });
}
function raw(gateway, { route = '/mcp', method = 'POST', body = JSON.stringify(message), headers = {}, chunks } = {}) {
  return new Promise((resolve, reject) => {
    const request = http.request(gateway.url, { path: route, method, headers: {
      'content-type': 'application/json', Authorization: `Bearer ${grokToken}`, ...headers
    } }, response => {
      const buffers = [];
      response.on('data', chunk => buffers.push(chunk));
      response.on('end', () => resolve({ status: response.statusCode, headers: response.headers, body: Buffer.concat(buffers).toString() }));
    });
    request.on('error', reject);
    if (chunks) { for (const chunk of chunks) request.write(chunk); request.end(); }
    else request.end(body);
  });
}

test('gateway CLI stays loopback-only and uses its own port without changing bridge defaults', () => {
  assert.equal(options(['gateway']).port, 43188);
  assert.equal(options(['serve']).port, 43187);
  assert.equal(options(['gateway']).host, '127.0.0.1');
  assert.throws(() => options(['gateway', '--host', '0.0.0.0']));
  assert.throws(() => options(['gateway', '--host', 'localhost']));
  assert.equal(options(['serve', '--host', '0.0.0.0']).host, '0.0.0.0');
});

test('Grok receives a distinct persistent private credential and never the owner token', async t => {
  const directory = await temporary(t);
  const original = path.join(directory, 'mcp-token');
  await fs.writeFile(original, ownerToken, { mode: 0o600 });
  const first = await gatewayCredential(directory, ownerToken);
  assert.notEqual(first.token, ownerToken);
  assert.match(first.token, /^[A-Za-z0-9_-]{43}$/);
  assert.equal((await gatewayCredential(directory, ownerToken)).token, first.token);
  const file = await writeGatewayClientConfig(directory, 'http://127.0.0.1:43188', first.token);
  const config = JSON.parse(await fs.readFile(file, 'utf8'));
  assert.equal(config.headers.Authorization, `Bearer ${first.token}`);
  assert.ok(!JSON.stringify(config).includes(ownerToken));
  assert.equal(await fs.readFile(original, 'utf8'), ownerToken);
  assert.equal((await fs.stat(directory)).mode & 0o777, 0o700);
  for (const secret of [first.file, file]) assert.equal((await fs.stat(secret)).mode & 0o777, 0o600);
  await fs.writeFile(first.file, JSON.stringify({ version: 1, token: ownerToken, createdAt: first.createdAt, expiresAt: first.expiresAt }));
  await assert.rejects(gatewayCredential(directory, ownerToken), /distinct credential/);
  await fs.unlink(first.file);
  await fs.symlink(original, first.file);
  await assert.rejects(gatewayCredential(directory, ownerToken));
  assert.equal(await fs.readFile(original, 'utf8'), ownerToken);
});

test('gateway rejects nonloopback upstreams and shared credentials before listening', async () => {
  for (const url of ['https://127.0.0.1:43187', 'http://example.com:43187', 'http://localhost:43187',
    'http://127.0.0.1:43187/api/admin', 'http://user:pass@127.0.0.1:43187', 'http://127.0.0.1:43187?token=secret']) {
    await assert.rejects(startMcpGateway({ upstreamURL: url, upstreamToken: ownerToken, token: grokToken, port: 0 }));
  }
  await assert.rejects(startMcpGateway({ upstreamURL: 'http://127.0.0.1:43187', upstreamToken: ownerToken, token: ownerToken, port: 0 }));
  await assert.rejects(startMcpGateway({ upstreamURL: 'http://127.0.0.1:43187', upstreamToken: ownerToken, token: grokToken, host: '0.0.0.0', port: 0 }));
});

test('only the separate Grok credential can forward MCP; headers and routes stay isolated', async t => {
  const upstream = await mockBridge(t);
  const f = await gateway(t, upstream);
  for (const token of [undefined, ownerToken, 'x'.repeat(43)]) {
    const response = await post(f, message, { token: token ?? null });
    assert.equal(response.status, 401);
    assert.ok(!(await response.text()).includes(ownerToken));
  }
  assert.equal(upstream.calls.length, 0);
  const response = await post(f, message, { headers: { 'mcp-protocol-version': '2025-11-25',
    cookie: 'not-forwarded=1', 'proxy-authorization': 'not-forwarded', 'x-forwarded-for': '198.51.100.4' } });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('access-control-allow-origin'), null);
  const call = upstream.calls[0];
  assert.equal(call.route, '/mcp'); assert.equal(call.method, 'POST');
  assert.equal(call.headers.authorization, `Bearer ${ownerToken}`);
  assert.equal(call.headers['mcp-protocol-version'], '2025-11-25');
  for (const header of ['cookie', 'proxy-authorization', 'x-forwarded-for', 'origin']) assert.equal(call.headers[header], undefined);
  assert.ok(!call.body.includes(grokToken));
  assert.deepEqual(JSON.parse(call.body), message);
});

test('pairing, owner administration, other routes, methods, query tokens and browser origins are blocked', async t => {
  const upstream = await mockBridge(t);
  const f = await gateway(t, upstream);
  for (const route of ['/api/pair', '/api/device/jobs', '/api/admin/status', '/api/admin/pair-code', '/health', '/pair',
    '/mcp/', '/mcp?access_token=hidden', '/%6dcp', '//mcp', '/mcp/../api/admin/status', '/%2e%2e/api/admin/status',
    'http://127.0.0.1:43187/api/admin/status']) {
    assert.equal((await raw(f, { route })).status, 404, route);
  }
  for (const method of ['GET', 'DELETE', 'OPTIONS', 'PUT']) assert.equal((await post(f, message, { method })).status, 405);
  assert.equal((await post(f, message, { headers: { Origin: 'https://hostile.example' } })).status, 403);
  assert.equal((await post(f, message, { headers: { Origin: f.url } })).status, 403);
  assert.equal((await raw(f, { headers: { Host: 'hostile.example' } })).status, 403);
  assert.equal(upstream.calls.length, 0);
});

test('invalid, encoded, oversized and chunked request bodies never reach the owner bridge', async t => {
  const upstream = await mockBridge(t);
  const f = await gateway(t, upstream, { maxBodyBytes: 100 });
  assert.equal((await post(f, message, { headers: { 'content-type': 'text/plain' } })).status, 415);
  assert.equal((await post(f, message, { headers: { 'content-encoding': 'gzip' } })).status, 415);
  assert.equal((await post(f, message, { headers: { 'mcp-protocol-version': 'invalid-version' } })).status, 400);
  for (const body of ['{', 'null', '[]', 'true']) assert.equal((await raw(f, { body })).status, 400);
  assert.equal((await raw(f, { body: 'x'.repeat(101), headers: { 'content-length': '101' } })).status, 413);
  assert.equal((await raw(f, { chunks: ['{"value":"', 'x'.repeat(101), '"}'] })).status, 413);
  assert.equal(upstream.calls.length, 0);
});

test('stateless official MCP client discovers tools through the restricted gateway', async t => {
  const directory = await temporary(t);
  const store = await BridgeStore.open(directory);
  const bridge = await startBridge(store, { port: 0 });
  t.after(() => bridge.close());
  const f = await startMcpGateway({ upstreamURL: bridge.url, upstreamToken: store.token, token: grokToken, port: 0 });
  t.after(() => f.close());
  const client = new Client({ name: 'isolated-grok-gateway-test', version: '1' });
  t.after(() => client.close());
  await client.connect(new StreamableHTTPClientTransport(new URL(`${f.url}/mcp`), {
    requestInit: { headers: { Authorization: `Bearer ${grokToken}` } }
  }));
  assert.equal((await client.listTools()).tools.length, 14);
  const status = await client.callTool({ name: 'honbako_get_status', arguments: {} });
  assert.ok(!status.isError);
  assert.deepEqual(status.structuredContent.devices, []);
  for (const route of ['/api/admin/status', '/api/pair']) assert.equal((await post(f, {}, { route })).status, 404);
});

test('request rate and concurrent upstream work are bounded and recover without retries', async t => {
  let now = 0;
  const upstream = await mockBridge(t);
  const limited = await gateway(t, upstream, { rateLimit: 2, clock: () => now, rateWindowMs: 1000 });
  assert.equal((await post(limited)).status, 200);
  assert.equal((await post(limited)).status, 200);
  const denied = await post(limited); assert.equal(denied.status, 429); assert.equal(denied.headers.get('retry-after'), '1');
  now = 1000;
  assert.equal((await post(limited)).status, 200);
  assert.equal(upstream.calls.length, 3);
  let release;
  const held = await mockBridge(t, (_request, response) => {
    release = () => { response.writeHead(200, { 'content-type': 'application/json' }); response.end('{"ok":true}'); };
  });
  const f = await gateway(t, held, { maxConcurrent: 1 });
  const first = post(f);
  await waitUntil(() => release !== undefined);
  assert.equal((await post(f)).status, 503);
  assert.equal(held.calls.length, 1);
  release(); assert.equal((await first).status, 200);
});

test('timeouts, redirects, invalid and oversized upstream responses fail closed without leaking credentials', async t => {
  for (const kind of ['timeout', 'redirect', 'private-error', 'invalid-json', 'too-large']) {
    const upstream = await mockBridge(t, (_request, response) => {
      if (kind === 'timeout') return;
      response.writeHead(kind === 'redirect' ? 302 : kind === 'private-error' ? 500 : 200,
        { 'content-type': 'application/json', ...(kind === 'redirect' ? { location: 'https://not-followed.invalid' } : {}) });
      response.end(kind === 'invalid-json' ? 'not-json' : JSON.stringify({ value: kind === 'too-large' ? 'x'.repeat(200) : ownerToken }));
    });
    const f = await gateway(t, upstream, { timeoutMs: 100, maxResponseBytes: 100 });
    const response = await post(f);
    assert.equal(response.status, kind === 'timeout' ? 504 : 502, kind);
    assert.equal(response.headers.get('location'), null);
    const body = await response.text();
    assert.ok(!body.includes(ownerToken)); assert.ok(!body.includes(grokToken));
    assert.equal(upstream.calls.length, 1, 'The gateway must never retry a potentially mutating MCP POST');
  }
});

test('incomplete request bodies time out before the upstream is contacted', async t => {
  const upstream = await mockBridge(t);
  const f = await gateway(t, upstream, { timeoutMs: 100 });
  const result = await new Promise((resolve, reject) => {
    const request = http.request(`${f.url}/mcp`, { method: 'POST', headers: {
      'content-type': 'application/json', 'content-length': '80', Authorization: `Bearer ${grokToken}`
    } }, response => {
      response.resume(); response.once('end', () => resolve(response.statusCode));
    });
    request.once('error', reject);
    request.write('{');
  });
  assert.equal(result, 408);
  assert.equal(upstream.calls.length, 0);
});

test('gateway CLI writes private metadata/config only and removes its own lock on graceful stop', async t => {
  const directory = await temporary(t);
  const upstream = await mockBridge(t);
  await fs.writeFile(path.join(directory, 'mcp-token'), `${ownerToken}\n`, { mode: 0o600 });
  await fs.writeFile(path.join(directory, 'server.json'), JSON.stringify({ url: upstream.url }), { mode: 0o600 });
  const reservation = http.createServer();
  await new Promise(resolve => reservation.listen(0, '127.0.0.1', resolve));
  const port = reservation.address().port;
  await new Promise(resolve => reservation.close(resolve));
  const command = fileURLToPath(new URL('../src/cli.js', import.meta.url));
  const child = spawn(process.execPath, [command, 'gateway', '--state-dir', directory, '--port', String(port)], { stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  child.stdout.on('data', chunk => { output += chunk.toString(); });
  child.stderr.on('data', chunk => { output += chunk.toString(); });
  t.after(async () => { if (child.exitCode === null) { child.kill('SIGINT'); await once(child, 'exit'); } });
  await waitUntil(async () => {
    try { return JSON.parse(await fs.readFile(path.join(directory, 'gateway.json'), 'utf8')).port === port; }
    catch { return false; }
  });
  const credential = JSON.parse(await fs.readFile(path.join(directory, 'grok-gateway-credential.json'), 'utf8')).token;
  await waitUntil(() => output.includes('No public endpoint or tunnel was started.'));
  assert.ok(!output.includes(credential)); assert.ok(!output.includes(ownerToken));
  for (const file of ['gateway.json', 'gateway.lock', 'grok-gateway-credential.json', 'client-configs/grok-bot-gateway.json'])
    assert.equal((await fs.stat(path.join(directory, file))).mode & 0o777, 0o600);
  assert.deepEqual(JSON.parse(await fs.readFile(path.join(directory, 'server.json'), 'utf8')), { url: upstream.url });
  assert.equal((await fs.readFile(path.join(directory, 'mcp-token'), 'utf8')).trim(), ownerToken);
  child.kill('SIGINT'); await once(child, 'exit');
  for (const file of ['gateway.json', 'gateway.lock']) await assert.rejects(fs.access(path.join(directory, file)));
  assert.equal(JSON.parse(await fs.readFile(path.join(directory, 'grok-gateway-credential.json'), 'utf8')).token, credential);
});


test('stored expiry survives restart and revocation immediately denies further requests without touching the owner bridge', async t => {
  const directory = await temporary(t);
  let now = Date.now();
  const credential = await gatewayCredential(directory, ownerToken, { clock: () => now });
  const expiry = Date.parse(credential.expiresAt);
  assert.equal(expiry - Date.parse(credential.createdAt), 24 * 60 * 60 * 1000);
  now += 1000;
  assert.equal((await gatewayCredential(directory, ownerToken, { clock: () => now })).expiresAt, credential.expiresAt);
  const upstream = await mockBridge(t);
  const f = await gateway(t, upstream, { token: credential.token, expiresAt: credential.expiresAt,
    clock: () => now, credentialCurrent: () => gatewayCredentialCurrent(directory, credential) });
  assert.equal((await post(f, message, { token: credential.token })).status, 200);
  now = expiry;
  assert.equal((await post(f, message, { token: credential.token })).status, 401);
  await assert.rejects(gatewayCredential(directory, ownerToken, { clock: () => now }), error => error.code === 'gateway_credential_expired');
  now = expiry - 500;
  await revokeGatewayCredential(directory);
  assert.equal((await post(f, message, { token: credential.token })).status, 401);
  assert.equal(upstream.calls.length, 1);
  assert.equal(await gatewayCredentialCurrent(directory, credential), false);
  const replacement = await gatewayCredential(directory, ownerToken, { clock: () => now });
  assert.notEqual(replacement.token, credential.token);
  assert.equal((await post(f, message, { token: credential.token })).status, 401,
    'A running gateway cannot accept a replacement credential until explicitly restarted');
});
