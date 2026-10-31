import { BridgeError, digest, secureEqual } from '../../src/store.js';
import { HostedBridgeCore, hostedInstructions, readJson, reply, failure } from '../core.js';
import { remoteBases, remoteRequestBase, requireRemoteBase } from './origins.js';
import { UUID, secret, tokenParts, tokenFrom, routedToken } from './oauth.js';
import { secondsUntilMidnightUTC, utcDay } from '../limits.js';

export const DEVICE_LIMIT = 5;
/// Requests per workspace per UTC day (WORKSPACE_DAILY_REQUEST_BUDGET), so one account's surge or
/// looping client cannot spend the allowance every account shares. AI calls have their own cap.
export const DAILY_REQUEST_BUDGET = 20000, DAILY_MCP_BUDGET = 2000;
/// Per minute, matching the Worker's Rate Limiting bindings for when those are missing.
export const DEVICE_RATE = 150, MCP_RATE = 120;
const BUDGET_SAVE_MS = 30000, BUDGET_SAVE_REQUESTS = 100;
const removal = new Set(['/api/device/disconnect', '/api/device/disconnect-all', '/api/device/remove']);
const PERMISSIONS = ['libraryRead', 'readingRead', 'pageRead', 'libraryWrite', 'sourcesWrite', 'annotationsWrite'];
const unauthorized = () => new BridgeError(401, 'unauthorized', 'Your paired Honbako device is required');

/// One workspace per Pro purchase, shared by up to five of the person's devices.
/// Each device keeps its own owner record and token; AI connections belong to the workspace.
export class RemoteWorkspace {
  constructor(store, { base, aliases = [], verifier, release = async () => {}, routeKey, clock = Date.now, dailyBudget = DAILY_REQUEST_BUDGET }) {
    this.bases = remoteBases(new URL(base).origin, aliases);
    requireRemoteBase(base, this.bases);
    this.store = store; this.base = base; this.verifier = verifier; this.release = release; this.clock = clock; this.routeKey = routeKey;
    this.dailyBudget = Number.isSafeInteger(dailyBudget) && dailyBudget > 0 ? dailyBudget : DAILY_REQUEST_BUDGET;
    this.budget = store.control('remote-budget'); this.budgetSaved = { at: clock(), requests: this.budget?.requests ?? 0 };
    let admin = store.control('remote-admin');
    if (!admin) { admin = secret(); store.setControl('remote-admin', admin); }
    this.bridge = new HostedBridgeCore(store, { publicOrigin: new URL(base).origin, adminKey: admin, clock });
    this.migrate();
  }
  atomically(change) { return this.store.storage?.transactionSync ? this.store.storage.transactionSync(change) : change(); }
  /// Before shared workspaces, a single installation owned each workspace, which was named by its ID.
  migrate() {
    const legacy = this.store.control('remote-owner');
    if (!legacy || this.store.control('remote-owners')) return;
    const { purchaseHash, ...owner } = legacy;
    this.atomically(() => {
      this.store.setControl('remote-workspace', { id: owner.id, purchaseHash: owner.disabled ? null : purchaseHash ?? null, familyShared: false });
      this.store.setControl('remote-owners', [owner]);
      this.store.setControl('remote-owner', null);
    });
  }
  meta() { return this.store.control('remote-workspace'); }
  owners() { return this.store.control('remote-owners') ?? []; }
  active() { return this.owners().filter(owner => !owner.disabled); }
  owner(token) {
    const parts = tokenParts(token), meta = this.meta(), hash = parts ? digest(token) : '';
    const found = parts?.[1] === 'd' && meta && parts[2] === meta.id && this.active().find(owner => secureEqual(hash, owner.tokenHash));
    if (!found) throw unauthorized();
    return { deviceId: found.id, workspaceId: meta.id };
  }
  async enroll(body, verifiedLease, base = this.base, workspaceId = body.installationId) {
    requireRemoteBase(base, this.bases);
    if (!UUID.test(body.installationId ?? '') || !/^[A-Za-z0-9_-]{43}$/.test(body.deviceSecret ?? '') || typeof body.name !== 'string' || body.name.length > 80 || !UUID.test(workspaceId ?? ''))
      throw new BridgeError(400, 'invalid_request', 'A private installation identity is required');
    const id = body.installationId, identityHash = digest(body.deviceSecret);
    // A device proves its own secret against its own record only, and never replaces another's.
    const prove = () => {
      if (this.meta() && this.meta().id !== workspaceId) throw new BridgeError(409, 'workspace_mismatch', 'This workspace has another address');
      const mine = this.owners().find(owner => owner.id === id);
      if (mine && !secureEqual(mine.identityHash, identityHash)) throw new BridgeError(401, 'unauthorized', 'This workspace belongs to another installation');
    };
    prove();
    const lease = verifiedLease ?? await this.verifier.enroll(body.signedTransaction);
    // A Family Sharing member never joins the purchaser's devices.
    if (lease.familyShared && workspaceId !== id) throw new BridgeError(409, 'purchase_mismatch', 'Family Sharing members use their own workspace');
    const token = routedToken('d', workspaceId, this.routeKey, body.deviceSecret), hash = digest(token);
    // Recheck after external verification/registry awaits to prevent enrollment races.
    const joined = await this.store.mutate(data => {
      prove();
      const meta = this.meta(), active = this.active(), others = active.filter(owner => owner.id !== id);
      // Only a workspace with connected devices stays bound to its purchase. Once every device
      // has left, a device that proved its secret above may bring it under another purchase.
      if (active.length && (meta?.purchaseHash !== lease.purchaseHash || Boolean(meta?.familyShared) !== Boolean(lease.familyShared)))
        throw new BridgeError(409, 'purchase_mismatch', 'This workspace is already linked to another purchase');
      if (others.length >= DEVICE_LIMIT) throw new BridgeError(429, 'device_limit', 'This subscription already uses remote MCP on five devices');
      const previous = this.owners().find(owner => owner.id === id);
      this.store.setControl('remote-owners', [...this.owners().filter(owner => owner.id !== id),
        { id, tokenHash: hash, identityHash, joinedAt: previous?.joinedAt ?? this.store.now() }]);
      this.store.setControl('remote-workspace', { id: workspaceId, purchaseHash: lease.purchaseHash, familyShared: Boolean(lease.familyShared) });
      this.store.setControl('remote-lease', lease);
      const existing = data.devices.find(d => d.id === id);
      if (existing) { existing.tokenHash = hash; existing.name = body.name; }
      else data.devices.push({ id, name: body.name, tokenHash: hash, createdAt: this.store.now(), lastSeen: this.store.now(), snapshot: null });
      return others.length > 0;
    });
    return { deviceId: id, deviceToken: token, endpoint: base, workspaceId, joinedOtherDevices: joined, entitlementExpiresAt: new Date(lease.expiresAt).toISOString() };
  }
  /// Turning off one device removes only that device. The last device to leave ends
  /// every AI connection, because nothing remains for them to read.
  async removeDevice(deviceId) {
    const owners = this.owners();
    if (!owners.some(owner => owner.id === deviceId && !owner.disabled)) throw new BridgeError(404, 'device_not_found', 'That device is no longer connected');
    this.store.setControl('remote-owners', owners.map(owner => owner.id === deviceId ? { ...owner, disabled: true } : owner));
    if (this.store.data.devices.some(device => device.id === deviceId)) await this.store.disconnect(deviceId);
    if (!this.active().length) await this.close();
    return { ok: true };
  }
  /// Disconnect All Devices: every device, AI connection, job, page and permission goes.
  async clear() {
    await this.store.mutate(data => {
      for (const device of data.devices) this.store.writeCoachingRecord(device.id, null);
      data.devices = []; data.jobs = [];
    });
    this.store.setControl('remote-owners', []);
    await this.close();
    return { ok: true };
  }
  async close() {
    const meta = this.meta();
    // A family member's workspace releases its place in the purchase's family allowance first.
    if (meta?.familyShared && meta.purchaseHash) await this.release(meta.purchaseHash, meta.id);
    this.atomically(() => {
      for (const [key, value] of [['remote-grants', []], ['remote-spent-refresh', []], ['remote-lease', null], ['account-permissions', null]]) this.store.setControl(key, value);
      if (meta) this.store.setControl('remote-workspace', { ...meta, purchaseHash: null });
    });
  }
  /// A device joining its purchase's shared workspace closes the one it owned before
  /// (decision 4: that workspace's AI connections end). Only its own secret can do this.
  async retire(body) {
    const mine = this.owners().find(owner => owner.id === body.installationId);
    if (!mine) return { retired: false };
    if (this.meta()?.id !== body.installationId || !secureEqual(mine.identityHash, digest(body.deviceSecret ?? ''))) throw unauthorized();
    await this.clear();
    return { retired: true };
  }
  info(deviceId) {
    const data = this.store.data, current = data.devices.length ? this.store.currentDevice(data) : null;
    const active = new Set(this.active().map(owner => owner.id)), permissions = this.store.control('account-permissions');
    return { workspaceId: this.meta().id, deviceId, currentDeviceId: current?.id ?? null, deviceLimit: DEVICE_LIMIT,
      devices: data.devices.filter(device => active.has(device.id)).map(device => ({ deviceId: device.id, name: device.name,
        lastActive: this.store.lastSeen(device), thisDevice: device.id === deviceId, current: device.id === current?.id })),
      permissions: permissions ? { values: permissions.values, revision: permissions.revision } : null };
  }
  /// One set of MCP permissions for the account: every device shows and enforces the same switches.
  async setPermissions(deviceId, body) {
    const values = body?.permissions;
    if (!values || typeof values !== 'object' || Array.isArray(values) || !Object.keys(values).length
        || Object.entries(values).some(([key, value]) => !PERMISSIONS.includes(key) || typeof value !== 'boolean'))
      throw new BridgeError(400, 'invalid_request', 'Send MCP permission switches as true or false');
    const previous = this.store.control('account-permissions');
    const next = { values: { ...previous?.values, ...values }, revision: (previous?.revision ?? 0) + 1, updatedBy: deviceId, updatedAt: this.store.now() };
    this.store.setControl('account-permissions', next);
    await this.store.restrictToAccountPermissions();
    return { permissions: { values: next.values, revision: next.revision } };
  }
  /// Counts one request against today's budget, in memory; the saved count trails by at most
  /// 30 s or 100 requests, and Disconnect All keeps it so starting over does not reset it.
  spend(kind) {
    const now = this.clock(), day = utcDay(now);
    if (this.budget?.day !== day) { this.budget = { day, requests: 0, mcp: 0 }; this.budgetSaved = { at: 0, requests: 0 }; }
    if (this.budget.requests >= this.dailyBudget || (kind === 'mcp' && this.budget.mcp >= DAILY_MCP_BUDGET))
      throw new BridgeError(429, 'rate_limited', 'Your AI connection has reached today’s limit and resumes at 00:00 UTC', { retryAfter: secondsUntilMidnightUTC(now) });
    this.budget.requests++;
    if (kind === 'mcp') this.budget.mcp++;
    if (now - this.budgetSaved.at >= BUDGET_SAVE_MS || this.budget.requests - this.budgetSaved.requests >= BUDGET_SAVE_REQUESTS) {
      this.store.setControl('remote-budget', this.budget);
      this.budgetSaved = { at: now, requests: this.budget.requests };
    }
  }
  async requirePro() {
    let lease = this.store.control('remote-lease');
    if (!lease) throw new BridgeError(402, 'pro_required', 'Remote MCP requires Honbako Pro');
    if (lease.leaseUntil <= this.clock()) {
      // Concurrent requests share one Apple check. Failure never extends the lease.
      this.checking ??= this.verifier.current(lease.originalTransactionId).then(current => {
        if (current.purchaseHash !== lease.purchaseHash || (current.familyShared && !lease.familyShared)) throw new BridgeError(402, 'pro_required', 'Purchase identity changed');
        const renewed = { ...current, familyShared: Boolean(lease.familyShared || current.familyShared) };
        this.store.setControl('remote-lease', renewed); return renewed;
      }).finally(() => { this.checking = null; });
      lease = await this.checking;
    }
    if (lease.expiresAt <= this.clock() || lease.leaseUntil <= this.clock()) throw new BridgeError(402, 'pro_required', 'Remote MCP requires an active Pro subscription');
  }
  async issue(clientId, issuer = this.base, familyId = crypto.randomUUID()) {
    requireRemoteBase(issuer, this.bases);
    await this.requirePro();
    const meta = this.meta();
    if (!meta || !this.active().length) throw new BridgeError(401, 'unauthorized', 'Open Honbako and enable the server again');
    const id = meta.id;
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
        if (request.method !== 'POST') return reply(405, { error: 'method_not_allowed' });
        this.store.enforceRate(['remote:mcp:minute'], MCP_RATE, 60000, 'Remote MCP is busy; retry later');
        this.spend('mcp');
        await this.requirePro();
        return this.bridge.mcp(request, await readJson(request));
      }
      const { deviceId } = this.owner(token);
      if (!removal.has(path)) {
        this.store.enforceRate([`remote:device:${deviceId}`], DEVICE_RATE, 60000);
        this.spend('device');
      }
      // Removing devices is always available, even after Pro lapses.
      if (path === '/api/device/disconnect' && request.method === 'POST') return reply(200, await this.removeDevice(deviceId));
      if (path === '/api/device/disconnect-all' && request.method === 'POST') return reply(200, await this.clear());
      if (path === '/api/device/remove' && request.method === 'POST') {
        const body = await readJson(request, 4096);
        if (!UUID.test(body.deviceId ?? '')) throw new BridgeError(400, 'invalid_request', 'Choose a connected device');
        return reply(200, await this.removeDevice(body.deviceId));
      }
      await this.requirePro();
      if (!path.startsWith('/api/device/') || path.includes('/oauth')) return reply(404, { error: 'not_found' });
      if (path === '/api/device/workspace' && request.method === 'GET') return reply(200, this.info(deviceId));
      if (path === '/api/device/permissions' && request.method === 'POST') return reply(200, await this.setPermissions(deviceId, await readJson(request, 4096)));
      const response = await this.bridge.fetch(new Request(`${new URL(this.base).origin}${path}`, request));
      // Every poll also carries the device list and the account's permissions, so no extra request is needed.
      if (path === '/api/device/jobs' && request.method === 'GET' && response.status === 200)
        return reply(200, { ...(await response.json()), workspace: this.info(deviceId) });
      return response;
    } catch (error) { return failure(error); }
  }
}
