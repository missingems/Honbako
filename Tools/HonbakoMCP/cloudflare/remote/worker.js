import { rpcResult, unwrapRPC } from './rpc.js';
import { DurableObject } from 'cloudflare:workers';
import { SqliteBridgeStore } from '../storage.js';
import { reply } from '../core.js';
import { BridgeError, digest } from '../../src/store.js';
import { AppleProVerifier } from './entitlement.js';
import { OAuthBroker } from './oauth.js';
import { DAILY_REQUEST_BUDGET, RemoteWorkspace } from './workspace.js';
import { PurchaseRegistry } from './purchases.js';
import { baseFor, broker, workspace } from './router.js';
export { enrollRemote, remoteFetch } from './router.js';

// The broker holds client registrations and short-lived authorization challenges,
// never library/page data. Normal MCP requests route directly to the private workspace.
export class HonbakoAuthorization extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env); this.env = env;
    this.store = new SqliteBridgeStore(ctx.storage, 'B'.repeat(43));
    this.purchases = new PurchaseRegistry(this.store);
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
      const response = reply(e instanceof BridgeError ? e.status : 500, { error: e instanceof BridgeError ? e.code : 'server_error', error_description: e instanceof BridgeError ? e.message : 'Authorization unavailable' });
      if (e?.retryAfter) response.headers.set('retry-after', String(e.retryAfter));
      return response;
    }
  }
  // In-memory counters (see MemoryLimiter): an attempt never writes a row.
  limit(request) {
    const ip = digest(request.headers.get('cf-connecting-ip') ?? 'unknown');
    this.store.enforceRate([`oauth:${ip}`], 120, 60000, 'Too many authorization requests');
    this.store.enforceRate(['oauth:global'], 3000, 60000, 'Too many authorization requests');
  }
  enrollmentLimit(ip) { return rpcResult(() => this.checkEnrollmentLimit(ip)); }
  checkEnrollmentLimit(ip) {
    this.store.enforceRate([`enroll:${digest(ip)}`], 10, 600000, 'Too many setup attempts');
    this.store.enforceRate(['enroll:global'], 1000, 600000, 'Too many setup attempts');
  }
  workspaceFor(purchaseHash, id) { return rpcResult(() => this.purchases.find(purchaseHash, id)); }
  bind(purchaseHash, id) { return rpcResult(() => this.purchases.bind(purchaseHash, id)); }
  unbind(purchaseHash, id) { return rpcResult(() => this.purchases.unbind(purchaseHash, id)); }
  forget(purchaseHash, id) { return rpcResult(() => this.purchases.forget(purchaseHash, id)); }
  allocate(purchaseHash, id) { return rpcResult(() => this.purchases.allocateFamily(purchaseHash, id)); }
  release(purchaseHash, id) { return rpcResult(() => this.purchases.releaseFamily(purchaseHash, id)); }
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
      release: async (hash, id) => unwrapRPC(await broker(env).release(hash, id)),
      dailyBudget: Number(env.WORKSPACE_DAILY_REQUEST_BUDGET ?? DAILY_REQUEST_BUDGET) });
  }
  async fetch(request) { const response = await this.core.fetch(request); await this.store.flushCoachingAlarm(); return response; }
  enroll(body, lease, base, workspaceId) { return rpcResult(() => this.core.enroll(body, lease, base, workspaceId)); }
  retire(body) { return rpcResult(() => this.core.retire(body)); }
  issue(clientId, issuer) { return rpcResult(() => this.core.issue(clientId, issuer)); }
  refresh(token, clientId, issuer) { return rpcResult(() => this.core.refresh(token, clientId, issuer)); }
  revoke(token, clientId, issuer) { return rpcResult(() => this.core.revoke(token, clientId, issuer)); }
  authorize(token, id, approved) { return rpcResult(() => this.authorizeDevice(token, id, approved)); }
  async authorizeDevice(token, id, approved) {
    const { workspaceId } = this.core.owner(token);
    await this.core.requirePro();
    if (approved === undefined) return unwrapRPC(await broker(this.env).pending(id));
    return unwrapRPC(await broker(this.env).approve(id, workspaceId, approved));
  }
  alarm() { return this.store.expireCoaching(); }
}
