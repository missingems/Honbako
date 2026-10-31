import http from 'node:http';
import { promises as fs, constants } from 'node:fs';
import path from 'node:path';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { atomicWrite, BridgeError } from './store.js';

const credentialPattern = /^[A-Za-z0-9_-]{43}$/;
const digest = value => createHash('sha256').update(value).digest();
class GatewayError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}

function bridgeAddress(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('Gateway upstream must be the loopback bridge'); }
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || !url.port || url.username || url.password
      || url.pathname !== '/' || url.search || url.hash) throw new Error('Gateway upstream must be the loopback bridge');
  return new URL('/mcp', url);
}

async function privateDirectory(directory) {
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  const info = await fs.lstat(directory);
  if (!info.isDirectory() || info.isSymbolicLink()) throw new Error('Gateway state must be a private directory');
  await fs.chmod(directory, 0o700);
}

const credentialName = 'grok-gateway-credential.json';
const credentialLifetime = 24 * 60 * 60 * 1000;
async function readCredential(file, tightenPermissions = false) {
  const reader = await fs.open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = await reader.stat();
    if (!info.isFile() || info.size > 1024) throw new Error('Invalid gateway credential file');
    const bytes = Buffer.alloc(1025);
    const { bytesRead } = await reader.read(bytes, 0, bytes.length, 0);
    if (bytesRead > 1024) throw new Error('Invalid gateway credential file');
    if (tightenPermissions) await reader.chmod(0o600);
    return JSON.parse(bytes.subarray(0, bytesRead).toString('utf8'));
  } finally { await reader.close(); }
}

/// Expiry belongs to the stored credential, so restarting cannot extend access.
export async function gatewayCredential(directory, upstreamToken, { clock = Date.now } = {}) {
  if (!credentialPattern.test(upstreamToken ?? '')) throw new Error('Invalid bridge credential');
  await privateDirectory(directory);
  const file = path.join(directory, credentialName);
  let handle;
  try {
    handle = await fs.open(file, 'wx', 0o600);
    const created = clock();
    await handle.writeFile(`${JSON.stringify({ version: 1, token: randomBytes(32).toString('base64url'),
      createdAt: new Date(created).toISOString(), expiresAt: new Date(created + credentialLifetime).toISOString() })}\n`);
    await handle.sync();
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
  } finally { await handle?.close(); }
  const saved = await readCredential(file, true);
  const created = Date.parse(saved.createdAt), expiry = Date.parse(saved.expiresAt);
  if (saved.version !== 1 || !credentialPattern.test(saved.token ?? '')
      || timingSafeEqual(digest(saved.token), digest(upstreamToken)) || !Number.isFinite(created)
      || !Number.isFinite(expiry) || expiry <= created || expiry - created > credentialLifetime)
    throw new Error('Gateway needs its own distinct credential with a valid expiry');
  if (clock() >= expiry) throw new BridgeError(401, 'gateway_credential_expired',
    'The Grok gateway credential expired. Run gateway-revoke, then gateway, and update the private connector credential.');
  return { token: saved.token, file, createdAt: saved.createdAt, expiresAt: saved.expiresAt };
}

export async function gatewayCredentialCurrent(directory, credential) {
  try {
    const saved = await readCredential(path.join(directory, credentialName));
    return saved.version === 1 && saved.expiresAt === credential.expiresAt
      && credentialPattern.test(saved.token ?? '') && timingSafeEqual(digest(saved.token), digest(credential.token));
  } catch { return false; }
}

export async function revokeGatewayCredential(directory) {
  await privateDirectory(directory);
  await fs.rm(path.join(directory, credentialName), { force: true });
  const folder = path.join(directory, 'client-configs');
  try {
    const info = await fs.lstat(folder);
    if (info.isDirectory() && !info.isSymbolicLink()) await fs.rm(path.join(folder, 'grok-bot-gateway.json'), { force: true });
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
}

export async function writeGatewayClientConfig(directory, url, token, expiresAt) {
  if (!credentialPattern.test(token)) throw new Error('Invalid gateway credential');
  const folder = path.join(directory, 'client-configs');
  await privateDirectory(folder);
  const file = path.join(folder, 'grok-bot-gateway.json');
  await atomicWrite(file, `${JSON.stringify({ url: `${url}/mcp`, headers: { Authorization: `Bearer ${token}` }, ...(expiresAt ? { expiresAt } : {}) }, null, 2)}\n`);
  return file;
}

function readBody(request, maximum, timeoutMs) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    const done = (error, body) => {
      clearTimeout(timer);
      request.off('data', data); request.off('end', end); request.off('error', failed); request.off('aborted', aborted);
      if (error) { request.pause(); reject(error); } else resolve(body);
    };
    const data = chunk => {
      size += chunk.length;
      if (size > maximum) done(new GatewayError(413, 'body_too_large'));
      else chunks.push(chunk);
    };
    const end = () => {
      const body = Buffer.concat(chunks);
      try {
        const parsed = JSON.parse(body.toString('utf8'));
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error();
      } catch { done(new GatewayError(400, 'invalid_json')); return; }
      done(null, body);
    };
    const failed = () => done(new GatewayError(400, 'request_interrupted'));
    const aborted = () => done(new GatewayError(400, 'request_interrupted'));
    const timer = setTimeout(() => done(new GatewayError(408, 'request_timeout')), timeoutMs);
    request.on('data', data).once('end', end).once('error', failed).once('aborted', aborted);
  });
}

function forwardMcp(address, token, body, protocol, timeoutMs, maximum, active) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let upstreamResponse;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      active.delete(upstream);
      if (error) { upstreamResponse?.destroy(); upstream.destroy(); reject(error); }
      else resolve(value);
    };
    const upstream = http.request(address, { method: 'POST', agent: false,
      headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream',
        authorization: `Bearer ${token}`, ...(protocol ? { 'mcp-protocol-version': protocol } : {}) } }, response => {
      upstreamResponse = response;
      const status = response.statusCode ?? 502;
      const contentType = response.headers['content-type'] ?? '';
      if (status >= 500 || (status >= 300 && status < 400) || [401, 403].includes(status)
          || (response.headers['content-encoding'] && response.headers['content-encoding'] !== 'identity')
          || (!/^application\/json(?:\s*;|$)/i.test(contentType) && ![202, 204].includes(status))) {
        finish(new GatewayError(502, 'bridge_unavailable')); return;
      }
      let size = 0;
      const chunks = [];
      response.on('data', chunk => {
        size += chunk.length;
        if (size > maximum) finish(new GatewayError(502, 'bridge_response_too_large'));
        else chunks.push(chunk);
      });
      response.once('aborted', () => finish(new GatewayError(502, 'bridge_unavailable')));
      response.once('error', () => finish(new GatewayError(502, 'bridge_unavailable')));
      response.once('end', () => {
        if (settled) return;
        const payload = Buffer.concat(chunks);
        if (payload.length) {
          try { JSON.parse(payload.toString('utf8')); }
          catch { finish(new GatewayError(502, 'bridge_unavailable')); return; }
        }
        const retry = /^\d{1,3}$/.test(response.headers['retry-after'] ?? '') ? Math.min(60, Number(response.headers['retry-after'])) : undefined;
        finish(null, { status, body: payload, ...(retry ? { retry } : {}) });
      });
    });
    const timer = setTimeout(() => finish(new GatewayError(504, 'bridge_timeout')), timeoutMs);
    active.add(upstream);
    upstream.once('error', () => finish(new GatewayError(502, 'bridge_unavailable')));
    upstream.end(body);
  });
}

/// Local-only, stateless server-to-server gateway. A future HTTPS tunnel must
/// target this port and rewrite Host to 127.0.0.1:<port>; never target the bridge.
export async function startMcpGateway({ upstreamURL, upstreamToken, token, host = '127.0.0.1', port = 43188,
  timeoutMs = 12000, maxBodyBytes = 1024 * 1024, maxResponseBytes = 2 * 1024 * 1024,
  rateLimit = 300, rateWindowMs = 60000, maxConcurrent = 8, clock = Date.now,
  expiresAt = new Date(clock() + credentialLifetime).toISOString(), credentialCurrent = async () => true } = {}) {
  if (host !== '127.0.0.1') throw new Error('The MCP gateway binds only to 127.0.0.1');
  if (!credentialPattern.test(token ?? '') || !credentialPattern.test(upstreamToken ?? '')
      || timingSafeEqual(digest(token), digest(upstreamToken))) throw new Error('Gateway needs distinct, valid credentials');
  const expiry = Date.parse(expiresAt);
  if (!Number.isFinite(expiry) || expiry <= clock() || expiry - clock() > credentialLifetime) throw new Error('Gateway credential expiry must be within24hours');
  const address = bridgeAddress(upstreamURL);
  const expected = digest(token);
  const active = new Set();
  let inFlight = 0, requests = 0, windowStart = clock(), gatewayPort;
  const server = http.createServer(async (request, response) => {
    response.setHeader('cache-control', 'no-store');
    response.setHeader('x-content-type-options', 'nosniff');
    try {
      const now = clock();
      if (now - windowStart >= rateWindowMs) { windowStart = now; requests = 0; }
      if (++requests > rateLimit) throw new GatewayError(429, 'rate_limited');
      // Match the raw request-target exactly: no query credentials, encoded
      // paths, absolute URLs or normalized traversal can reach another route.
      if (request.url !== '/mcp') throw new GatewayError(404, 'not_found');
      const hostCount = request.rawHeaders.filter((_, index) => index % 2 === 0 && request.rawHeaders[index].toLowerCase() === 'host').length;
      if (hostCount !== 1 || ![`127.0.0.1:${gatewayPort}`, `localhost:${gatewayPort}`].includes(request.headers.host?.toLowerCase()))
        throw new GatewayError(403, 'host_rejected');
      // This is not a browser endpoint. No cross-origin or preflight bypass is
      // provided; the authenticated Bot connector sends server-to-server HTTP.
      if (request.headers.origin !== undefined) throw new GatewayError(403, 'origin_rejected');
      if (request.method !== 'POST') throw new GatewayError(405, 'method_not_allowed');
      const authCount = request.rawHeaders.filter((_, index) => index % 2 === 0 && request.rawHeaders[index].toLowerCase() === 'authorization').length;
      const bearer = /^Bearer ([A-Za-z0-9_-]{43})$/i.exec(request.headers.authorization ?? '')?.[1];
      if (authCount !== 1 || !bearer || !timingSafeEqual(digest(bearer), expected)) throw new GatewayError(401, 'unauthorized');
      if (clock() >= expiry || !(await credentialCurrent())) throw new GatewayError(401, 'credential_expired_or_revoked');
      if (!/^application\/json(?:\s*;|$)/i.test(request.headers['content-type'] ?? '')
          || (request.headers['content-encoding'] && request.headers['content-encoding'] !== 'identity'))
        throw new GatewayError(415, 'json_required');
      const protocol = request.headers['mcp-protocol-version'];
      if (protocol !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(protocol)) throw new GatewayError(400, 'invalid_protocol');
      if (Number(request.headers['content-length'] ?? 0) > maxBodyBytes) throw new GatewayError(413, 'body_too_large');
      if (inFlight >= maxConcurrent) throw new GatewayError(503, 'gateway_busy');
      inFlight += 1;
      try {
        const body = await readBody(request, maxBodyBytes, timeoutMs);
        if (clock() >= expiry || !(await credentialCurrent())) throw new GatewayError(401, 'credential_expired_or_revoked');
        const result = await forwardMcp(address, upstreamToken, body, protocol, timeoutMs, maxResponseBytes, active);
        if (response.destroyed) return;
        response.writeHead(result.status, { ...(result.body.length ? { 'content-type': 'application/json; charset=utf-8' } : {}),
          ...(result.retry ? { 'retry-after': String(result.retry) } : {}) });
        response.end(result.body);
      } finally { inFlight -= 1; }
    } catch (error) {
      if (response.destroyed || response.headersSent) { response.destroy(); return; }
      const known = error instanceof GatewayError;
      response.writeHead(known ? error.status : 502, { 'content-type': 'application/json; charset=utf-8', connection: 'close',
        ...(error.status === 429 ? { 'retry-after': String(Math.ceil(rateWindowMs / 1000)) } : {}) });
      response.once('finish', () => { if (!request.complete) request.destroy(); });
      response.end(JSON.stringify({ error: { code: known ? error.code : 'gateway_unavailable', message: 'The MCP gateway could not complete this request.' } }));
    }
  });
  server.requestTimeout = timeoutMs + 1000;
  server.headersTimeout = Math.min(timeoutMs, 10000);
  server.keepAliveTimeout = 3000;
  server.maxRequestsPerSocket = 100;
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, host, resolve); });
  gatewayPort = server.address().port;
  let closing;
  return { server, port: gatewayPort, url: `http://127.0.0.1:${gatewayPort}`,
    close() {
      closing ??= (async () => {
        for (const request of active) request.destroy();
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
      })();
      return closing;
    } };
}
