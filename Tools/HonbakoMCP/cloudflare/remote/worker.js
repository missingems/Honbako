import { rpcResult, unwrapRPC } from './rpc.js';
import { DurableObject } from 'cloudflare:workers';
import { SqliteBridgeStore } from '../storage.js';
import { failure, reply, readJson } from '../core.js';
import { BridgeError, digest } from '../../src/store.js';
import { AppleProVerifier } from './entitlement.js';
import { OAuthBroker, UUID, discovery, secret, tokenFrom, tokenParts, validRouteToken } from './oauth.js';
import { remoteBases, remoteRequestBase } from './origins.js';
import { RemoteWorkspace } from './workspace.js';

const baseFor = env => `${env.PUBLIC_ORIGIN}/remote`;
const workspace = (env, id) => env.HONBAKO_WORKSPACE.get(env.HONBAKO_WORKSPACE.idFromName(id));
const broker = env => env.HONBAKO_AUTH.get(env.HONBAKO_AUTH.idFromName('oauth-v1'));

// The broker holds client registrations and short-lived authorization challenges,
// never library/page data. Normal MCP requests route directly to the private workspace.
export class HonbakoAuthorization extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env); this.env = env;
    this.store = new SqliteBridgeStore(ctx.storage, 'B'.repeat(43));
    const sql = ctx.storage.sql;
    sql.exec('CREATE TABLE IF NOT EXISTS remote_auth (key TEXT PRIMARY KEY, value TEXT NOT NULL, expires INTEGER NOT NULL)');
    sql.exec('CREATE INDEX IF NOT EXISTS remote_auth_expiry ON remote_auth(expires)');
    const records = {
      get(key) { const row = [...sql.exec('SELECT value FROM remote_auth WHERE key = ?', key)][0]; return row ? JSON.parse(row.value) : null; },
      set(key, value) { sql.exec('INSERT OR REPLACE INTO remote_auth (key, value, expires) VALUES (?, ?, ?)', key, JSON.stringify(value), value.until); },
      delete(key) { sql.exec('DELETE FROM remote_auth WHERE key = ?', key); },
      purge(now) { sql.exec('DELETE FROM remote_auth WHERE expires <= ?', now); }
    };
    this.oauth = new OAuthBroker(records, { onRegistration: value => {
      const until = Number(this.env.OAUTH_REGISTRATION_DIAGNOSTICS_UNTIL);
      if (Number.isFinite(until) && Date.now() < until) console.info('honbako.oauth.registration', JSON.stringify(value));
    }, base: baseFor(env), aliases: env.REMOTE_ORIGIN_ALIASES, routeKey: env.REMOTE_ROUTING_KEY, workspace: id => ({
      issue: async (...args) => unwrapRPC(await workspace(env, id).issue(...args)),
      refresh: async (...args) => unwrapRPC(await workspace(env, id).refresh(...args)),
      revoke: async (...args) => unwrapRPC(await workspace(env, id).revoke(...args))
    }) });
  }
  async fetch(request) {
    try {
      this.limit(request);
      return await this.oauth.fetch(request);
    } catch (e) {
      // OAuth endpoints use RFC 6749 error fields, not application error envelopes.
      return reply(e instanceof BridgeError ? e.status : 500, { error: e instanceof BridgeError ? e.code : 'server_error', error_description: e instanceof BridgeError ? e.message : 'Authorization unavailable' });
    }
  }
  limit(request) {
    const ip = digest(request.headers.get('cf-connecting-ip') ?? 'unknown');
    if (!this.store.allowRate([`oauth:${ip}`], 120, 60000) || !this.store.allowRate(['oauth:global'], 3000, 60000))
      throw new BridgeError(429, 'rate_limited', 'Too many authorization requests');
  }
  enrollmentLimit(ip) { return rpcResult(() => this.checkEnrollmentLimit(ip)); }
  checkEnrollmentLimit(ip) {
    if (!this.store.allowRate([`enroll:${digest(ip)}`], 10, 600000) || !this.store.allowRate(['enroll:global'], 1000, 600000)) throw new BridgeError(429, 'rate_limited', 'Too many setup attempts');
  }
  allocate(purchaseHash, id) { return rpcResult(() => this.allocatePurchase(purchaseHash, id)); }
  allocatePurchase(purchaseHash, id) {
    // Apple proof can restore multiple personal devices, but cannot spawn unlimited hosted workspaces.
    const key = `purchase:${purchaseHash}`, current = this.store.control(key) ?? [];
    if (!current.includes(id)) {
      if (current.length >= 5) throw new BridgeError(429, 'device_limit', 'This subscription already has five remote workspaces');
      this.store.setControl(key, [...current, id]);
    }
  }
  release(purchaseHash, id) { return rpcResult(() => this.releasePurchase(purchaseHash, id)); }
  releasePurchase(purchaseHash, id) {
    // A disconnected installation no longer counts toward its purchase's five workspaces.
    const key = `purchase:${purchaseHash}`, current = this.store.control(key) ?? [];
    if (current.includes(id)) this.store.setControl(key, current.filter(x => x !== id));
  }
  pending(id) { return rpcResult(() => this.oauth.pending(id)); }
  approve(id, workspaceId, approved) { return rpcResult(() => this.oauth.approve(id, workspaceId, approved)); }
}
export class HonbakoWorkspace extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env); this.env = env;
    this.store = new SqliteBridgeStore(ctx.storage, 'W'.repeat(43));
    this.core = new RemoteWorkspace(this.store, { base: baseFor(env), aliases: env.REMOTE_ORIGIN_ALIASES, routeKey: env.REMOTE_ROUTING_KEY,
      // Construct the verifier lazily: missing Apple credentials still allow disconnect/revocation.
      verifier: { current: id => new AppleProVerifier(env).current(id) },
      allocate: async (hash, id) => unwrapRPC(await broker(env).allocate(hash, id)),
      release: async (hash, id) => unwrapRPC(await broker(env).release(hash, id)) });
  }
  async fetch(request) { const response = await this.core.fetch(request); await this.store.flushCoachingAlarm(); return response; }
  enroll(body, lease, base) { return rpcResult(() => this.core.enroll(body, lease, base)); }
  issue(clientId, issuer) { return rpcResult(() => this.core.issue(clientId, issuer)); }
  refresh(token, clientId, issuer) { return rpcResult(() => this.core.refresh(token, clientId, issuer)); }
  revoke(token, clientId, issuer) { return rpcResult(() => this.core.revoke(token, clientId, issuer)); }
  authorize(token, id, approved) { return rpcResult(() => this.authorizeDevice(token, id, approved)); }
  async authorizeDevice(token, id, approved) {
    const workspaceId = this.core.owner(token);
    await this.core.requirePro();
    if (approved === undefined) return unwrapRPC(await broker(this.env).pending(id));
    return unwrapRPC(await broker(this.env).approve(id, workspaceId, approved));
  }
  alarm() { return this.store.expireCoaching(); }
}
export async function remoteFetch(request, env) {
  try {
    if (env.REMOTE_MCP_ENABLED !== 'YES' || !env.HONBAKO_WORKSPACE || !env.HONBAKO_AUTH || !/^[A-Za-z0-9_-]{43,100}$/.test(env.REMOTE_ROUTING_KEY ?? ''))
      return reply(503, { error: { code: 'remote_not_available', message: 'Automatic remote setup is not available yet' } });
    const base = remoteRequestBase(request, remoteBases(env.PUBLIC_ORIGIN, env.REMOTE_ORIGIN_ALIASES));
    const u = new URL(request.url), path = u.pathname;
    if (path === '/remote/capabilities' && request.method === 'GET') return reply(200, { available: Boolean(env.APP_STORE_PRIVATE_KEY && env.APP_STORE_KEY_ID && env.APP_STORE_ISSUER_ID) });
    if (path === '/.well-known/oauth-protected-resource/remote/mcp' && request.method === 'GET')
      return reply(200, { resource: `${base}/mcp`, authorization_servers: [base], scopes_supported: ['honbako'], bearer_methods_supported: ['header'] });
    if (['/.well-known/oauth-authorization-server/remote', '/remote/.well-known/oauth-authorization-server'].includes(path) && request.method === 'GET') return reply(200, discovery(base));
    if (path.startsWith('/remote/oauth/')) {
      const origin = request.headers.get('origin');
      if (origin && origin !== u.origin) throw new BridgeError(403, 'origin_rejected', 'Cross-origin browser requests are not supported');
      return broker(env).fetch(request);
    }
    if (request.headers.has('origin') || u.search) throw new BridgeError(403, 'origin_rejected', 'This route is for Honbako and authorized AI clients');
    if (path === '/remote/enroll' && request.method === 'POST') {
      unwrapRPC(await broker(env).enrollmentLimit(request.headers.get('cf-connecting-ip') ?? 'unknown'));
      const body = await readJson(request, 32768);
      if (!UUID.test(body.installationId ?? '') || !/^[A-Za-z0-9_-]{43}$/.test(body.deviceSecret ?? '')) throw new BridgeError(400, 'invalid_request', 'Private installation identity required');
      // Verify before allocating any per-user object. Invalid receipts cannot spawn tenants.
      const lease = await new AppleProVerifier(env).enroll(body.signedTransaction);
      return reply(200, unwrapRPC(await workspace(env, body.installationId).enroll(body, lease, base)));
    }
    const token = tokenFrom(request), parts = tokenParts(token);
    if (!validRouteToken(token, env.REMOTE_ROUTING_KEY)) {
      const r = reply(401, { error: 'unauthorized' });
      if (path === '/remote/mcp') r.headers.set('www-authenticate', `Bearer resource_metadata="${u.origin}/.well-known/oauth-protected-resource/remote/mcp", scope="honbako"`);
      return r;
    }
    if (path === '/remote/api/device/authorization' && request.method === 'POST') {
      const body = await readJson(request, 4096);
      if (!UUID.test(body.requestId ?? '') || (body.approved !== undefined && typeof body.approved !== 'boolean')) throw new BridgeError(400, 'invalid_request', 'Valid connection request required');
      return reply(200, unwrapRPC(await workspace(env, parts[2]).authorize(token, body.requestId, body.approved)));
    }
    if (!(path === '/remote/mcp' && parts[1] === 'a') && !(path.startsWith('/remote/api/device/') && parts[1] === 'd')) return reply(401, { error: 'unauthorized' });
    return workspace(env, parts[2]).fetch(request);
  } catch (error) { return failure(error); }
}
