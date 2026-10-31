import { BridgeStore, BridgeError } from '../src/store.js';
import { MemoryLimiter } from './limits.js';

const copy = value => structuredClone(value);
const json = value => JSON.stringify(value);
const MAX_ROW_BYTES = 1_900_000;
function encode(value) {
  const encoded = json(value);
  if (new TextEncoder().encode(encoded).length > MAX_ROW_BYTES) throw new BridgeError(413, 'state_too_large', 'One device or job exceeds hosted storage capacity');
  return encoded;
}
export function setupStorage(storage) {
  for (const statement of [
    'CREATE TABLE IF NOT EXISTS bridge_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS bridge_devices (id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL, value TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS bridge_jobs (id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL, value TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS bridge_control (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS bridge_limits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires INTEGER NOT NULL)',
    'CREATE TABLE IF NOT EXISTS bridge_coaching (id TEXT PRIMARY KEY, expires INTEGER, value TEXT NOT NULL)',
    'CREATE INDEX IF NOT EXISTS bridge_coaching_expiry ON bridge_coaching(expires)',
    'CREATE INDEX IF NOT EXISTS bridge_limits_expiry ON bridge_limits(expires)'
  ]) storage.sql.exec(statement);
}
function readState(storage) {
  setupStorage(storage);
  const meta = new Map([...storage.sql.exec('SELECT key, value FROM bridge_meta')].map(row => [row.key, JSON.parse(row.value)]));
  return { version: 1, pairing: meta.get('pairing') ?? null,
    devices: [...storage.sql.exec('SELECT value FROM bridge_devices ORDER BY ordinal')].map(row => JSON.parse(row.value)),
    jobs: [...storage.sql.exec('SELECT value FROM bridge_jobs ORDER BY ordinal')].map(row => JSON.parse(row.value)) };
}
function persist(storage, before, after) {
  if (json(before.pairing) !== json(after.pairing)) storage.sql.exec('INSERT OR REPLACE INTO bridge_meta (key, value) VALUES (?, ?)', 'pairing', encode(after.pairing));
  for (const [field, table] of [['devices', 'bridge_devices'], ['jobs', 'bridge_jobs']]) {
    const old = new Map(before[field].map((value, ordinal) => [value.id, { value: json(value), ordinal }]));
    const kept = new Set(after[field].map(value => value.id));
    for (const id of old.keys()) if (!kept.has(id)) storage.sql.exec(`DELETE FROM ${table} WHERE id = ?`, id);
    after[field].forEach((value, ordinal) => {
      const encoded = encode(value), previous = old.get(value.id);
      if (previous?.value !== encoded || previous.ordinal !== ordinal)
        storage.sql.exec(`INSERT OR REPLACE INTO ${table} (id, ordinal, value) VALUES (?, ?, ?)`, value.id, ordinal, encoded);
    });
  }
}
export class SqliteBridgeStore extends BridgeStore {
  constructor(storage, pairingKey, { clock = Date.now } = {}) {
    super(null, pairingKey, readState(storage), clock);
    this.storage = storage;
    this.limiter = new MemoryLimiter(clock);
  }
  coachingDeviceIds() { return [...this.storage.sql.exec('SELECT id FROM bridge_coaching')].map(row => row.id); }
  coachingRecord(id) {
    const row = [...this.storage.sql.exec('SELECT value FROM bridge_coaching WHERE id = ?', id)][0];
    return row ? JSON.parse(row.value) : null;
  }
  writeCoachingRecord(id, value) {
    if (value === null) this.storage.sql.exec('DELETE FROM bridge_coaching WHERE id = ?', id);
    else this.storage.sql.exec('INSERT OR REPLACE INTO bridge_coaching (id, expires, value) VALUES (?, ?, ?)',
      id, !value.closed && value.image && value.accessMode !== 'connection' ? Date.parse(value.expiresAt) : null, encode(value));
    if (this.storage.setAlarm) {
      const update = async () => {
        const next = [...this.storage.sql.exec('SELECT MIN(expires) AS expiry FROM bridge_coaching WHERE expires IS NOT NULL')][0]?.expiry;
        if (next !== null && next !== undefined) await this.storage.setAlarm(Math.max(this.clock() + 1, next));
        else await this.storage.deleteAlarm?.();
      };
      this.coachingAlarmTask = (this.coachingAlarmTask ?? Promise.resolve()).catch(() => {}).then(update);
    }
  }
  async flushCoachingAlarm() { await this.coachingAlarmTask; }
  async expireCoaching() {
    for (const row of this.storage.sql.exec('SELECT id FROM bridge_coaching WHERE expires <= ?', this.clock())) this.coaching.expire(row.id);
    await this.flushCoachingAlarm();
  }
  async mutate(change) {
    const work = this.tail.then(() => {
      const draft = copy(this.data), value = change(draft);
      if (value?.then) throw new Error('Hosted storage mutations must be synchronous');
      this.storage.transactionSync(() => persist(this.storage, this.data, draft));
      this.data = draft;
      return copy(value);
    });
    this.tail = work.catch(() => {});
    return work;
  }
  async importState(state, metadata) {
    const work = this.tail.then(() => {
      if (this.data.devices.length || this.data.jobs.length || this.control('migration'))
        throw new BridgeError(409, 'host_not_empty', 'Import requires a new empty hosted companion');
      const draft = copy({ ...state, pairing: null });
      this.storage.transactionSync(() => {
        persist(this.storage, this.data, draft);
        this.setControl('migration', metadata);
      });
      this.data = draft;
      return { devices: draft.devices.length, jobs: draft.jobs.length, pendingJobs: draft.jobs.filter(job => !['completed', 'failed', 'rejected', 'cancelled'].includes(job.status)).length };
    });
    this.tail = work.catch(() => {});
    return work;
  }
  /// Set by a shared remote workspace; one account-wide set of MCP switches for every device.
  accountPermissions() { return this.control('account-permissions')?.values ?? null; }
  control(key) {
    const row = [...this.storage.sql.exec('SELECT value FROM bridge_control WHERE key = ?', key)][0];
    return row ? JSON.parse(row.value) : null;
  }
  setControl(key, value) {
    this.storage.sql.exec('INSERT OR REPLACE INTO bridge_control (key, value) VALUES (?, ?)', key, encode(value));
  }
  /// Rate counters are kept in memory (see MemoryLimiter), never one SQLite row per request.
  allowRate(keys, limit, windowMs) { return this.limiter.allow(keys, limit, windowMs); }
  enforceRate(keys, limit, windowMs, message, code) { this.limiter.enforce(keys, limit, windowMs, message, code); }
  /// Guesses at a six-digit pairing code are rare and must survive restarts, so they keep saved counters.
  enforceSavedRate(keys, limit, windowMs, message, code) {
    const now = this.clock();
    const wait = this.storage.transactionSync(() => {
      this.storage.sql.exec('DELETE FROM bridge_limits WHERE expires <= ?', now);
      const rows = keys.map(key => ({ key, row: [...this.storage.sql.exec('SELECT count, expires FROM bridge_limits WHERE key = ?', key)][0] }));
      const full = rows.filter(({ row }) => row && row.count >= limit);
      if (full.length) return Math.max(1, Math.ceil((Math.min(...full.map(({ row }) => row.expires)) - now) / 1000));
      if ([...this.storage.sql.exec('SELECT COUNT(*) AS count FROM bridge_limits')][0].count + rows.filter(({ row }) => !row).length > 4096) return Math.ceil(windowMs / 1000);
      for (const { key, row } of rows) this.storage.sql.exec('INSERT OR REPLACE INTO bridge_limits (key, count, expires) VALUES (?, ?, ?)', key, (row?.count ?? 0) + 1, row?.expires ?? now + windowMs);
      return null;
    });
    if (wait !== null) throw new BridgeError(429, code, message, { retryAfter: wait });
  }
}
