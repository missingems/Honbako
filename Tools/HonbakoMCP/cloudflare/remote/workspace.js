import { BridgeError, digest, secureEqual } from '../../src/store.js';
import { HostedBridgeCore, hostedInstructions, readJson, reply, failure } from '../core.js';
import { remoteBases, remoteRequestBase, requireRemoteBase } from './origins.js';
import { UUID, secret, tokenParts, tokenFrom, routedToken } from './oauth.js';

export class RemoteWorkspace {
  constructor(store, { base, aliases = [], verifier, allocate, release = async () => {}, routeKey, clock = Date.now }) {
    this.bases = remoteBases(new URL(base).origin, aliases);
    requireRemoteBase(base, this.bases);
    this.store = store; this.base = base; this.verifier = verifier; this.allocate = allocate; this.release = release; this.clock = clock; this.routeKey = routeKey;
    let admin = store.control('remote-admin');
    if (!admin) { admin = secret(); store.setControl('remote-admin', admin); }
    this.bridge = new HostedBridgeCore(store, { publicOrigin: new URL(base).origin, adminKey: admin, clock });
  }
  owner(token) {
    const parts = tokenParts(token), saved = this.store.control('remote-owner');
    if (!parts || parts[1] !== 'd' || !saved || saved.disabled || saved.id !== parts[2] || !secureEqual(digest(token), saved.tokenHash))
      throw new BridgeError(401, 'unauthorized', 'Your paired Honbako device is required');
    return saved.id;
  }
  async enroll(body, verifiedLease, base = this.base) {
    requireRemoteBase(base, this.bases);
    if (!UUID.test(body.installationId ?? '') || !/^[A-Za-z0-9_-]{43}$/.test(body.deviceSecret ?? '') || typeof body.name !== 'string' || body.name.length > 80)
      throw new BridgeError(400, 'invalid_request', 'A private installation identity is required');
    const id = body.installationId, token = routedToken('d', id, this.routeKey, body.deviceSecret), hash = digest(token);
    const previous = this.store.control('remote-owner');
    if (previous && (!secureEqual(previous.identityHash, digest(body.deviceSecret)) || previous.id !== id)) throw new BridgeError(401, 'unauthorized', 'This workspace belongs to another installation');
    const lease = verifiedLease ?? await this.verifier.enroll(body.signedTransaction);
    // Only an active workspace stays bound to its purchase. A disconnected installation
    // (which still proved its deviceSecret above) may enroll under another Apple account.
    if (previous?.purchaseHash && previous.purchaseHash !== lease.purchaseHash) {
      if (!previous.disabled) throw new BridgeError(409, 'purchase_mismatch', 'This workspace is already linked to another purchase');
      await this.release(previous.purchaseHash, id);
    }
    await this.allocate(lease.purchaseHash, id);
    // Recheck after external verification/registry awaits to prevent enrollment races.
    await this.store.mutate(data => {
      const current = this.store.control('remote-owner');
      if (current && (!secureEqual(current.identityHash, digest(body.deviceSecret)) || current.id !== id)) throw new BridgeError(401, 'unauthorized', 'This workspace belongs to another installation');
      if (current?.purchaseHash && !current.disabled && current.purchaseHash !== lease.purchaseHash) throw new BridgeError(409, 'purchase_mismatch', 'This workspace is already linked to another purchase');
      this.store.setControl('remote-owner', { id, tokenHash: hash, identityHash: digest(body.deviceSecret), purchaseHash: lease.purchaseHash });
      const existing = data.devices.find(d => d.id === id);
      if (existing) existing.tokenHash = hash;
      else data.devices.push({ id, name: body.name, tokenHash: hash, createdAt: this.store.now(), lastSeen: this.store.now(), snapshot: null });
      this.store.setControl('remote-lease', lease);
    });
    return { deviceId: id, deviceToken: token, endpoint: base, entitlementExpiresAt: new Date(lease.expiresAt).toISOString() };
  }
  async requirePro() {
    let lease = this.store.control('remote-lease');
    if (!lease) throw new BridgeError(402, 'pro_required', 'Remote MCP requires Honbako Pro');
    if (lease.leaseUntil <= this.clock()) {
      // Concurrent requests share one Apple check. Failure never extends the lease.
      this.checking ??= this.verifier.current(lease.originalTransactionId).then(current => {
        if (current.purchaseHash !== lease.purchaseHash) throw new BridgeError(402, 'pro_required', 'Purchase identity changed');
        this.store.setControl('remote-lease', current); return current;
      }).finally(() => { this.checking = null; });
      lease = await this.checking;
    }
    if (lease.expiresAt <= this.clock() || lease.leaseUntil <= this.clock()) throw new BridgeError(402, 'pro_required', 'Remote MCP requires an active Pro subscription');
  }
  async issue(clientId, issuer = this.base, familyId = crypto.randomUUID()) {
    requireRemoteBase(issuer, this.bases);
    await this.requirePro();
    const owner = this.store.control('remote-owner');
    if (!owner || owner.disabled) throw new BridgeError(401, 'unauthorized', 'Open Honbako and enable the server again');
    const id = owner.id;
    const access = routedToken('a', id, this.routeKey), refresh = routedToken('r', id, this.routeKey);
    const grants = this.grants();
    if (grants.length >= 16) throw new BridgeError(429, 'connection_limit', 'Remove an AI connection before adding another');
    grants.push({ issuer, clientId, familyId, accessHash: digest(access), refreshHash: digest(refresh), accessUntil: this.clock() + 15 * 60000, until: this.clock() + 30 * 86400000 });
    this.store.setControl('remote-grants', grants);
    return { access_token: access, token_type: 'Bearer', expires_in: 900, refresh_token: refresh, scope: 'honbako' };
  }
  grants() { return (this.store.control('remote-grants') ?? []).filter(g => g.until > this.clock()); }
  async refresh(token, clientId, issuer = this.base) {
    requireRemoteBase(issuer, this.bases);
    const hash = digest(token), grants = this.grants(), grant = grants.find(g => secureEqual(g.refreshHash, hash));
    if (!grant || grant.clientId !== clientId || (grant.issuer ?? this.base) !== issuer) {
      const spent = (this.store.control('remote-spent-refresh') ?? []).find(g => g.until > this.clock() && g.clientId === clientId && (g.issuer ?? this.base) === issuer && secureEqual(g.hash, hash));
      if (spent) this.store.setControl('remote-grants', grants.filter(g => g.familyId !== spent.familyId));
      throw new BridgeError(400, 'invalid_grant', 'This AI connection must be authorized again');
    }
    await this.requirePro();
    // Serialize consumption before issuing new credentials; old refresh tokens never work twice.
    const current = this.grants();
    if (!current.some(g => secureEqual(g.refreshHash, hash))) throw new BridgeError(400, 'invalid_grant', 'Refresh token was already used');
    this.store.setControl('remote-grants', current.filter(g => g.familyId !== grant.familyId));
    const spent = (this.store.control('remote-spent-refresh') ?? []).filter(g => g.until > this.clock());
    spent.push({ issuer, hash, familyId: grant.familyId, clientId, until: grant.until });
    this.store.setControl('remote-spent-refresh', spent.slice(-128));
    return this.issue(clientId, issuer, grant.familyId);
  }
  revoke(token, clientId, issuer = this.base) {
    requireRemoteBase(issuer, this.bases);
    const hash = digest(token);
    this.store.setControl('remote-grants', this.grants().filter(g => !(g.clientId === clientId && (g.issuer ?? this.base) === issuer && (secureEqual(g.refreshHash, hash) || secureEqual(g.accessHash, hash)))));
  }
  async fetch(request) {
    try {
      const base = remoteRequestBase(request, this.bases), u = new URL(request.url), prefix = new URL(base).pathname;
      const path = u.pathname.startsWith(`${prefix}/`) ? u.pathname.slice(prefix.length) : '';
      if (u.search || request.headers.has('origin'))
        throw new BridgeError(403, 'request_rejected', 'Use the configured Honbako server');
      const token = tokenFrom(request), parts = tokenParts(token);
      if (path === '/mcp') {
        const grant = parts?.[1] === 'a' && this.grants().find(g => (g.issuer ?? this.base) === base && g.accessUntil > this.clock() && secureEqual(g.accessHash, digest(token)));
        if (!grant) {
          const response = reply(401, { error: 'unauthorized' });
          response.headers.set('www-authenticate', `Bearer resource_metadata="${new URL(base).origin}/.well-known/oauth-protected-resource${new URL(base).pathname}/mcp", scope="honbako"`);
          return response;
        }
        await this.requirePro();
        if (request.method !== 'POST') return reply(405, { error: 'method_not_allowed' });
        if (!this.store.allowRate(['remote:mcp:day'], 2000, 86400000) || !this.store.allowRate(['remote:mcp:minute'], 120, 60000)) throw new BridgeError(429, 'rate_limited', 'Remote MCP is busy; retry later');
        return this.bridge.mcp(request, await readJson(request));
      }
      this.owner(token);
      if (path === '/api/device/disconnect' && request.method === 'POST') {
        // Release the purchase slot first: a failed release leaves the phone able to retry.
        const { purchaseHash, ...owner } = this.store.control('remote-owner');
        if (purchaseHash) await this.release(purchaseHash, owner.id);
        this.store.setControl('remote-owner', { ...owner, disabled: true });
        this.store.setControl('remote-grants', []);
        this.store.setControl('remote-lease', null);
        return this.bridge.fetch(new Request(`${new URL(this.base).origin}${path}`, request));
      }
      await this.requirePro();
      if (!path.startsWith('/api/device/') || path.includes('/oauth')) return reply(404, { error: 'not_found' });
      return this.bridge.fetch(new Request(`${new URL(this.base).origin}${path}`, request));
    } catch (error) { return failure(error); }
  }
}
