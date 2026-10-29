import http from 'node:http';
import { networkInterfaces, hostname } from 'node:os';
import { NodeStreamableHTTPServerTransport } from '@modelcontextprotocol/node';
import { pairRequest, snapshot, statusRequest, coachingPublish, coachingSession, coachingPause } from './schema.js';
import { BridgeError, secureEqual } from './store.js';
import { createMcpServer, dispatch } from './mcp.js';

const MAX_BODY = 1024 * 1024;
const bearer = request => /^Bearer ([A-Za-z0-9_-]{20,200})$/.exec(request.headers.authorization ?? '')?.[1] ?? '';
function reply(response, status, body) {
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' });
  response.end(JSON.stringify(body));
}
async function body(request) {
  if (!/^application\/json(?:\s*;|$)/i.test(request.headers['content-type'] ?? '')) throw new BridgeError(415, 'json_required', 'Use application/json');
  if (Number(request.headers['content-length'] ?? 0) > MAX_BODY) throw new BridgeError(413, 'body_too_large', 'Request body exceeds 1 MiB');
  let length = 0; const chunks = [];
  for await (const chunk of request) {
    length += chunk.length;
    if (length > MAX_BODY) throw new BridgeError(413, 'body_too_large', 'Request body exceeds 1 MiB');
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new BridgeError(400, 'invalid_json', 'Invalid JSON request'); }
}
class Limiter {
  constructor() { this.entries = new Map(); }
  allow(key, limit, windowMs) {
    const now = Date.now();
    let entry = this.entries.get(key);
    if (!entry || now >= entry.expires) {
      if (this.entries.size >= 2000) for (const [key, value] of this.entries) if (value.expires <= now) this.entries.delete(key);
      if (!entry && this.entries.size >= 2000) return false;
      entry = { count: 0, expires: now + windowMs }; this.entries.set(key, entry);
    }
    if (this.entries.size > 2000) for (const [key, value] of this.entries) if (value.expires <= now) this.entries.delete(key);
    return ++entry.count <= limit;
  }
}
export async function startBridge(store, { host = '127.0.0.1', port = 43187 } = {}) {
  const limiter = new Limiter();
  const localName = hostname().toLowerCase();
  const allowedHosts = new Set(['127.0.0.1', 'localhost', '[::1]', host, localName]);
  if (!localName.includes('.')) allowedHosts.add(`${localName}.local`);
  for (const entries of Object.values(networkInterfaces())) for (const entry of entries ?? []) allowedHosts.add(entry.address);
  const activeMcp = new Set();
  const server = http.createServer(async (request, response) => {
    response.setHeader('cache-control', 'no-store');
    try {
      let url;
      try { url = new URL(request.url, `http://${request.headers.host}`); }
      catch { throw new BridgeError(400, 'invalid_host', 'Invalid request host'); }
      if (!allowedHosts.has(url.hostname)) throw new BridgeError(403, 'host_rejected', 'Host is not this Mac');
      if (request.headers.origin) {
        let origin; try { origin = new URL(request.headers.origin); } catch { throw new BridgeError(403, 'origin_rejected', 'Origin not allowed'); }
        if (origin.origin !== url.origin) throw new BridgeError(403, 'origin_rejected', 'Origin not allowed');
      }
      const ip = request.socket.remoteAddress ?? 'unknown';
      if (!limiter.allow(`request:${ip}`, 600, 60000)) throw new BridgeError(429, 'rate_limited', 'Too many requests; retry later');
      if (url.pathname === '/health' && request.method === 'GET') return reply(response, 200, { ok: true, service: 'honbako-mcp' });
      if (url.pathname === '/api/pair' && request.method === 'POST') {
        if (!limiter.allow(`pair:${ip}`, 10, 600000)) throw new BridgeError(429, 'pairing_rate_limited', 'Too many pairing attempts; retry later');
        return reply(response, 200, await store.pair(pairRequest.parse(await body(request))));
      }
      const token = bearer(request);
      const personal = Boolean(token && secureEqual(token, store.token));
      if (url.pathname === '/mcp') {
        if (!personal) throw new BridgeError(401, 'unauthorized', 'MCP bearer credential required');
        if (request.method !== 'POST') throw new BridgeError(405, 'method_not_allowed', 'This stateless MCP endpoint accepts POST requests');
        const parsed = await body(request);
        const transport = new NodeStreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
        const mcp = createMcpServer((name, args) => dispatch(store, name, args));
        activeMcp.add(mcp);
        response.on('close', () => { activeMcp.delete(mcp); void mcp.close(); });
        await mcp.connect(transport);
        await transport.handleRequest(request, response, parsed);
        return;
      }
      if (url.pathname.startsWith('/api/admin/')) {
        if (!personal) throw new BridgeError(401, 'unauthorized', 'Personal MCP bearer credential required');
        if (url.pathname === '/api/admin/pair-code' && request.method === 'POST') return reply(response, 200, await store.createPairCode());
        const forget = /^\/api\/admin\/devices\/([0-9a-f-]{36})$/.exec(url.pathname);
        if (forget && request.method === 'DELETE') return reply(response, 200, await store.disconnect(forget[1]));
        if (url.pathname === '/api/admin/status' && request.method === 'GET') return reply(response, 200, store.status());
        throw new BridgeError(404, 'not_found', 'Endpoint not found');
      }
      const deviceId = store.authenticateDevice(token);
      if (!deviceId) throw new BridgeError(401, 'unauthorized', 'Paired device bearer credential required');
      if (url.pathname === '/api/device/coaching' && request.method === 'POST') return reply(response, 200, await store.publishCoaching(deviceId, coachingPublish.parse(await body(request))));
      if (url.pathname === '/api/device/coaching' && request.method === 'GET') return reply(response, 200, store.deviceCoaching(deviceId));
      if (url.pathname === '/api/device/coaching/revoke' && request.method === 'POST') return reply(response, 200, await store.revokeCoaching(deviceId, coachingSession.parse(await body(request))));
      if (url.pathname === '/api/device/coaching/pause' && request.method === 'POST') return reply(response, 200, store.pauseCoaching(deviceId, coachingPause.parse(await body(request))));
      if (url.pathname === '/api/device/disconnect' && request.method === 'POST') { await body(request); return reply(response, 200, await store.disconnect(deviceId)); }
      if (url.pathname === '/api/device/state' && request.method === 'POST') return reply(response, 200, await store.updateSnapshot(deviceId, snapshot.parse(await body(request))));
      if (url.pathname === '/api/device/jobs' && request.method === 'GET') return reply(response, 200, await store.deviceJobs(deviceId));
      const match = /^\/api\/device\/jobs\/([0-9a-f-]{36})\/status$/.exec(url.pathname);
      if (match && request.method === 'POST') return reply(response, 200, await store.updateJob(deviceId, match[1], statusRequest.parse(await body(request))));
      throw new BridgeError(404, 'not_found', 'Endpoint not found');
    } catch (error) {
      if (response.headersSent) { response.end(); return; }
      const known = error instanceof BridgeError;
      const validation = error.name === 'ZodError';
      reply(response, known ? error.status : validation ? 400 : 500,
        { error: { code: known ? error.code : validation ? 'invalid_request' : 'internal_error',
          message: known ? error.message : validation ? 'Request validation failed' : 'The local bridge could not complete this request' } });
    }
  });
  server.requestTimeout = 15000; server.headersTimeout = 10000; server.keepAliveTimeout = 5000;
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, host, resolve); });
  const address = server.address();
  const localHost = host === '::1' ? '[::1]' : '127.0.0.1';
  return { server, url: `http://${localHost}:${address.port}`, port: address.port,
    async close() { for (const mcp of activeMcp) await mcp.close(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); await store.coachingPersistence; } };
}
