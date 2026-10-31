import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
import { LEASE_MS } from '../remote/entitlement.js';
import { RemoteWorkspace } from '../remote/workspace.js';
import { PurchaseRegistry, routeEnrollment } from '../remote/purchases.js';
import { secret, tokenParts } from '../remote/oauth.js';
import { SqliteBridgeStore } from '../storage.js';
export const BASE = 'https://honbako.example/remote', ROUTE_KEY = 'K'.repeat(43), at = Date.now();
/// `rows.written` counts SQLite rows changed, the Workers Free allowance that runs out first.
export function store(clock, rows = { written: 0 }) {
  const db = new DatabaseSync(':memory:');
  const storage = { sql: { exec(s, ...args) { const p = db.prepare(s); if (p.columns().length) return p.all(...args); rows.written += Number(p.run(...args).changes); return []; } },
    transactionSync(f) { db.exec('BEGIN'); try { const r = f(); db.exec('COMMIT'); return r; } catch (e) { db.exec('ROLLBACK'); throw e; } } };
  return new SqliteBridgeStore(storage, 'P'.repeat(43), { clock });
}
// Mirrors remote/worker.js: one broker, one workspace per name, tokens routed by their embedded ID.
export function cloud({ dailyBudget } = {}) {
  let now = at;
  const rows = { written: 0 }, clock = () => now, registry = new PurchaseRegistry(store(clock)), stores = new Map(), spaces = new Map();
  const lease = (purchaseHash = 'purchase', familyShared = false) => ({ originalTransactionId: '12345', purchaseHash, familyShared, expiresAt: now + 86400000, leaseUntil: now + LEASE_MS });
  const open = id => {
    if (!spaces.has(id)) {
      if (!stores.has(id)) stores.set(id, store(clock, rows));
      spaces.set(id, new RemoteWorkspace(stores.get(id), { base: BASE, routeKey: ROUTE_KEY, clock, dailyBudget,
        verifier: { async current() { return lease(); } }, release: async (hash, owner) => registry.releaseFamily(hash, owner) }));
    }
    return spaces.get(id);
  };
  const enroll = (identity, granted = lease()) => routeEnrollment({ purchases: registry, workspace: open }, identity, granted, BASE);
  const route = token => open(tokenParts(token)[2]);
  const call = (token, path, body, method = body === undefined ? 'GET' : 'POST') => route(token).fetch(new Request(`${BASE}${path}`, { method,
    headers: { accept: 'application/json, text/event-stream', 'content-type': 'application/json', authorization: `Bearer ${token}` }, ...(method === 'GET' ? {} : { body: JSON.stringify(body) }) }));
  // Restart one workspace from its saved storage, as a deploy would.
  const restart = id => { spaces.delete(id); return open(id); };
  return { registry, stores, open, enroll, route, call, restart, lease, rows, clock, advance: ms => { now += ms; } };
}
export const device = (name = 'iPhone') => ({ installationId: randomUUID(), deviceSecret: secret(), name, signedTransaction: 'x'.repeat(100) });
export const tools = { jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} };
export const state = (overrides = {}) => ({ schemaVersion: 1, generatedAt: new Date(at).toISOString(), library: [{ sourceId: 'owned', mangaId: 'one', title: 'One' }],
  sources: [{ id: 'owned', name: 'Owned', supportsSearch: true }], readingHistoryAccess: true, automationCapabilities: ['reading.history', 'sources.manage', 'library.remove'], ...overrides });
