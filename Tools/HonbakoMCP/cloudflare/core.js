import { randomBytes } from 'node:crypto';
import { WebStandardStreamableHTTPServerTransport } from '@modelcontextprotocol/server';
import { createMcpServer, dispatch, instructions } from '../src/mcp.js';
import { BridgeError, digest, secureEqual } from '../src/store.js';
import { pairRequest, snapshot, statusRequest, coachingPublish, coachingSession, coachingPause } from '../src/schema.js';
import { stateDigest, validateMigration } from './migration.js';

export const MAX_BODY = 1024 * 1024;
export const MAX_RESPONSE = 2 * 1024 * 1024;
export const MAX_MIGRATION = 16 * 1024 * 1024;
export const GRANT_LIFETIME_MS = 24 * 60 * 60 * 1000;
const DEADLINE = 12000;
export const hostedInstructions = instructions.replace("Cloud clients cannot reach a Mac's localhost or private LAN automatically; this local bridge does not create a public endpoint.", 'This is the owner’s hosted HTTPS companion. The Mac does not need to be running. The paired phone must open Honbako with an Internet connection to sync fresh reading state and process approved jobs; otherwise report its last-known state.');
const strongKey = key => typeof key === 'string' && /^[A-Za-z0-9_-]{43,100}$/.test(key);
const bearer = request => /^Bearer ([A-Za-z0-9_-]{43,100})$/.exec(request.headers.get('authorization') ?? '')?.[1] ?? '';
const terminal = new Set(['completed', 'failed', 'rejected', 'cancelled']);
const responseHeaders = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' };
export function reply(status, value) { return new Response(JSON.stringify(value), { status, headers: responseHeaders }); }
export function failure(error) {
  const known = error instanceof BridgeError, validation = error?.name === 'ZodError';
  return reply(known ? error.status : validation ? 400 : 500, { error: {
    code: known ? error.code : validation ? 'invalid_request' : 'internal_error',
    message: known ? error.message : validation ? 'Request validation failed' : 'Honbako could not complete this request'
  } });
}
export async function boundedBytes(stream, maximum, timeoutMs = DEADLINE) {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader();
  let timeout;
  const expired = new Promise((_, reject) => { timeout = setTimeout(() => { void reader.cancel().catch(() => {}); reject(new BridgeError(408, 'request_timeout', 'Request took too long')); }, timeoutMs); });
  try {
    return await Promise.race([(async () => {
      const chunks = []; let length = 0;
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        length += value.byteLength;
        if (length > maximum) { await reader.cancel(); throw new BridgeError(413, 'body_too_large', 'Request or response exceeds its size limit'); }
        chunks.push(value);
      }
      const result = new Uint8Array(length); let offset = 0;
      for (const value of chunks) { result.set(value, offset); offset += value.byteLength; }
      return result;
    })(), expired]);
  } finally { clearTimeout(timeout); reader.releaseLock(); }
}
export async function readJson(request, maximum = MAX_BODY) {
  if (!/^application\/json(?:\s*;|$)/i.test(request.headers.get('content-type') ?? '')) throw new BridgeError(415, 'json_required', 'Use application/json');
  const length = request.headers.get('content-length');
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > maximum)) throw new BridgeError(413, 'body_too_large', 'Request exceeds its size limit');
  if (request.headers.has('content-encoding') && request.headers.get('content-encoding') !== 'identity') throw new BridgeError(415, 'encoding_rejected', 'Encoded request bodies are not accepted');
  try {
    const value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(await boundedBytes(request.body, maximum)));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('object required');
    return value;
  } catch (error) { if (error instanceof BridgeError) throw error; throw new BridgeError(400, 'invalid_json', 'Use a JSON object'); }
}
function publicRoute(url) {
  if (url.search || url.hash || url.username || url.password || url.pathname.includes('%')) return null;
  if (url.pathname === '/mcp') return { kind: 'mcp', method: 'POST' };
  if (url.pathname === '/api/pair') return { kind: 'pair', method: 'POST' };
  if (url.pathname === '/api/device/state') return { kind: 'state', method: 'POST' };
  if (url.pathname === '/api/device/coaching') return { kind: 'coaching', method: null };
  if (url.pathname === '/api/device/coaching/revoke') return { kind: 'coaching-revoke', method: 'POST' };
  if (url.pathname === '/api/device/coaching/pause') return { kind: 'coaching-pause', method: 'POST' };
  if (url.pathname === '/api/device/jobs') return { kind: 'jobs', method: 'GET' };
  if (url.pathname === '/api/device/disconnect') return { kind: 'disconnect', method: 'POST' };
  const match = /^\/api\/device\/jobs\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/status$/.exec(url.pathname);
  return match ? { kind: 'status', method: 'POST', jobId: match[1] } : null;
}
export class HostedBridgeCore {
  constructor(store, { publicOrigin, adminKey, clock = Date.now } = {}) {
    const origin = new URL(publicOrigin);
    if (origin.protocol !== 'https:' || origin.origin !== publicOrigin || !strongKey(adminKey) || !strongKey(store.token) || secureEqual(adminKey, store.token))
      throw new Error('Hosted origin and distinct strong administrator/pairing secrets are required');
    this.store = store; this.publicOrigin = publicOrigin; this.adminKey = adminKey; this.clock = clock;
  }
  reservedCredentialHash(hash) {
    return secureEqual(hash, digest(this.adminKey)) || secureEqual(hash, digest(this.store.token))
      || this.store.data.devices.some(device => secureEqual(hash, device.tokenHash));
  }
  async fetch(request) {
    try {
      const url = new URL(request.url), route = publicRoute(url);
      // Administrative operations never enter the public HTTP router, even with the owner secret.
      if (!route) return reply(404, { error: { code: 'not_found', message: 'Endpoint not found' } });
      if (url.protocol !== 'https:' || url.origin !== this.publicOrigin) throw new BridgeError(403, 'host_rejected', 'Use the configured HTTPS companion address');
      if (request.headers.has('origin')) throw new BridgeError(403, 'origin_rejected', 'Browser-origin requests are not accepted');
      if (route.kind === 'coaching' ? !['POST', 'GET'].includes(request.method) : request.method !== route.method) throw new BridgeError(405, 'method_not_allowed', 'Method not allowed');
      const address = request.headers.get('cf-connecting-ip') ?? 'unknown';
      const ip = /^[0-9a-fA-F:.]{3,80}$/.test(address) ? digest(address) : 'unknown';
      if (!this.store.allowRate([`request:${ip}`], 600, 60000) || !this.store.allowRate(['request:global'], 1800, 60000))
        throw new BridgeError(429, 'rate_limited', 'Too many requests; retry later');
      if (route.kind === 'pair') {
        if (!this.store.allowRate([`pair:${ip}`], 10, 600000) || !this.store.allowRate(['pair:global'], 30, 600000))
          throw new BridgeError(429, 'pairing_rate_limited', 'Too many pairing attempts; retry later');
        if (this.store.data.devices.length >= 100) throw new BridgeError(429, 'device_limit', 'Remove an unused pairing before connecting another device');
        return reply(200, await this.store.pair(pairRequest.parse(await readJson(request))));
      }
      const token = bearer(request);
      if (route.kind === 'mcp') {
        const grant = this.store.control('grok-grant');
        if (!token || this.reservedCredentialHash(digest(token)) || !grant || grant.revokedAt || this.clock() >= Date.parse(grant.expiresAt) || !secureEqual(digest(token), grant.tokenHash))
          throw new BridgeError(401, 'unauthorized', 'A current Grok MCP grant is required');
        const parsed = await readJson(request);
        return await this.mcp(request, parsed);
      }
      const deviceId = this.store.authenticateDevice(token);
      if (!deviceId) throw new BridgeError(401, 'unauthorized', 'Paired device credential required');
      if (route.kind === 'coaching' && request.method === 'GET') return reply(200, this.store.deviceCoaching(deviceId));
      if (route.kind === 'jobs') return reply(200, await this.store.deviceJobs(deviceId));
      const parsed = await readJson(request);
      if (route.kind === 'coaching') return reply(200, await this.store.publishCoaching(deviceId, coachingPublish.parse(parsed)));
      if (route.kind === 'coaching-revoke') return reply(200, await this.store.revokeCoaching(deviceId, coachingSession.parse(parsed)));
      if (route.kind === 'coaching-pause') return reply(200, this.store.pauseCoaching(deviceId, coachingPause.parse(parsed)));
      if (route.kind === 'state') return reply(200, await this.store.updateSnapshot(deviceId, snapshot.parse(parsed)));
      if (route.kind === 'disconnect') return reply(200, await this.store.disconnect(deviceId));
      return reply(200, await this.store.updateJob(deviceId, route.jobId, statusRequest.parse(parsed)));
    } catch (error) { return failure(error); }
  }
  async mcp(request, parsedBody) {
    const transport = new WebStandardStreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true, maxRequestBodySize: MAX_BODY, keepAliveMs: 0 });
    const server = createMcpServer((name, args) => dispatch(this.store, name, args), { instructions: hostedInstructions });
    let timer;
    try {
      await server.connect(transport);
      const response = await Promise.race([transport.handleRequest(request, { parsedBody }), new Promise((_, reject) => {
        timer = setTimeout(() => { void server.close(); reject(new BridgeError(504, 'request_timeout', 'MCP request took too long')); }, DEADLINE);
      })]);
      const bytes = await boundedBytes(response.body, MAX_RESPONSE);
      if (bytes.byteLength && !/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? ''))
        throw new BridgeError(502, 'unexpected_response', 'Unexpected MCP response');
      return new Response(bytes.byteLength ? bytes : null, { status: response.status, headers: responseHeaders });
    } finally { clearTimeout(timer); await server.close(); }
  }
  async admin(action, params, key) {
    if (!strongKey(key) || !secureEqual(digest(key), digest(this.adminKey))) throw new BridgeError(401, 'unauthorized', 'Administrator credential required');
    await this.store.tail;
    if (action === 'status') {
      const grant = this.store.control('grok-grant');
      return { ...this.store.status(), hosted: true, migration: this.store.control('migration'), grant: grant ? {
        createdAt: grant.createdAt, expiresAt: grant.expiresAt, revoked: Boolean(grant.revokedAt), expired: this.clock() >= Date.parse(grant.expiresAt)
      } : null };
    }
    if (action === 'pair-code') return this.store.createPairCode();
    if (action === 'grant') {
      const lifetime = params?.lifetimeSeconds ?? GRANT_LIFETIME_MS / 1000;
      if (!Number.isInteger(lifetime) || lifetime < 60 || lifetime > GRANT_LIFETIME_MS / 1000) throw new BridgeError(400, 'invalid_grant', 'Grant lifetime must be between one minute and 24 hours');
      const token = randomBytes(32).toString('base64url'), createdAt = new Date(this.clock()).toISOString(), expiresAt = new Date(this.clock() + lifetime * 1000).toISOString();
      this.store.setControl('grok-grant', { tokenHash: digest(token), createdAt, expiresAt });
      return { token, createdAt, expiresAt, endpoint: `${this.publicOrigin}/mcp` };
    }
    if (action === 'restore-grant') {
      const fields = ['tokenHash', 'createdAt', 'expiresAt', 'revokedAt'];
      const value = params ?? {}, created = Date.parse(value.createdAt), expires = Date.parse(value.expiresAt), now = this.clock();
      if (Object.keys(value).some(field => !fields.includes(field)) || !/^[0-9a-f]{64}$/.test(value.tokenHash ?? '')
          || typeof value.createdAt !== 'string' || typeof value.expiresAt !== 'string'
          || !Number.isFinite(created) || !Number.isFinite(expires) || created > now || expires <= now
          || expires <= created || expires - created > GRANT_LIFETIME_MS || expires - now > GRANT_LIFETIME_MS
          || (value.revokedAt !== undefined && (typeof value.revokedAt !== 'string' || !Number.isFinite(Date.parse(value.revokedAt)) || Date.parse(value.revokedAt) < created || Date.parse(value.revokedAt) > now)))
        throw new BridgeError(400, 'invalid_grant', 'Restore requires only a valid credential hash and its original unexpired grant times');
      if (this.reservedCredentialHash(value.tokenHash)) throw new BridgeError(400, 'credential_role_conflict', 'A Grok grant must not reuse an administrator, pairing or device credential');
      const previous = this.store.control('grok-grant');
      const restored = { tokenHash: value.tokenHash, createdAt: value.createdAt, expiresAt: value.expiresAt, ...(value.revokedAt === undefined ? {} : { revokedAt: value.revokedAt }) };
      if (previous) {
        if (previous.tokenHash === value.tokenHash && expires > Date.parse(previous.expiresAt))
          throw new BridgeError(409, 'grant_extension_rejected', 'Restoring a grant cannot extend its original expiry');
        if (JSON.stringify(previous) !== JSON.stringify(restored)) throw new BridgeError(409, 'grant_exists', 'Restore requires an empty grant or an identical existing grant');
        return { restored: true, alreadyPresent: true, createdAt: previous.createdAt, expiresAt: previous.expiresAt, revoked: Boolean(previous.revokedAt) };
      }
      this.store.setControl('grok-grant', restored);
      return { restored: true, alreadyPresent: false, createdAt: restored.createdAt, expiresAt: restored.expiresAt, revoked: Boolean(restored.revokedAt) };
    }
    if (action === 'revoke-grant') {
      const grant = this.store.control('grok-grant');
      if (grant) this.store.setControl('grok-grant', { ...grant, revokedAt: new Date(this.clock()).toISOString() });
      return { revoked: true };
    }
    if (action === 'export-state') {
      const state = structuredClone({ ...this.store.data, pairing: null });
      return { version: 1, state, sha256: stateDigest(state), exportedAt: new Date(this.clock()).toISOString() };
    }
    if (action === 'import-state') {
      const state = validateMigration(params);
      return this.store.importState(state, { importedAt: new Date(this.clock()).toISOString(), sha256: params.sha256, pendingItems: state.jobs.filter(job => job.kind === 'library.add' && !terminal.has(job.status)).reduce((count, job) => count + job.payload.items.length, 0) });
    }
    throw new BridgeError(404, 'unknown_admin_action', 'Unknown administrator operation');
  }
}
