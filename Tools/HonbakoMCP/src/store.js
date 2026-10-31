import { promises as fs } from 'node:fs';
import path from 'node:path';
import { randomBytes, randomInt, randomUUID, createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { snapshot as snapshotSchema, searchResult, addResult, removeResult } from './schema.js';
import { BridgeError } from './errors.js';
import { historyResult, sourceCatalogResult, sourceChangeResult } from './management-schema.js';
import { CoachingSessions, headerOf } from './coaching.js';
export { BridgeError } from './errors.js';

export const digest = text => createHash('sha256').update(text).digest('hex');
export const secureEqual = (left, right) => {
  const a = Buffer.from(String(left)), b = Buffer.from(String(right));
  return a.length === b.length && timingSafeEqual(a, b);
};
export async function atomicWrite(file, data) {
  const temp = `${file}.${randomUUID()}.tmp`;
  const handle = await fs.open(temp, 'wx', 0o600);
  try { await handle.writeFile(data); await handle.sync(); } finally { await handle.close(); }
  try { await fs.rename(temp, file); await fs.chmod(file, 0o600); }
  catch (error) { await fs.rm(temp, { force: true }); throw error; }
  const directory = await fs.open(path.dirname(file), 'r');
  try { await directory.sync(); } finally { await directory.close(); }
}
const key = value => JSON.stringify([value.sourceId, value.mangaId]);
// Jobs that change the person's library or sources run only after an explicit phone approval.
const approvalKinds = new Set(['library.add', 'library.remove', 'sources.change']);
const terminal = new Set(['completed', 'failed', 'rejected', 'cancelled']);
const clone = value => structuredClone(value);
const deviceHistoryDisabled = (data, id) => data.devices.find(d => d.id === id)?.snapshot?.readingHistoryAccess !== true;
// A job without a deviceId belongs to the whole workspace: any of the person's devices may run it.
const visibleTo = (job, id) => (job.deviceId ?? id) === id;
const claimant = job => job.claimedBy ?? job.deviceId ?? null;
const latest = (devices, field) => devices.reduce((best, device) => device[field] && (!best || device[field] > best[field]) ? device : best, null);
const RUNNER_MS = 60000, HANDLED_MS = 3600000, LIBRARY_FRESH_SECONDS = 600, SEEN_SAVE_MS = 30000;
const handledElsewhere = () => new BridgeError(409, 'already_handled', 'Another of your devices already handled this request');
export class BridgeStore {
  static async open(directory, { clock = Date.now } = {}) {
    await fs.mkdir(directory, { recursive: true, mode: 0o700 });
    if ((await fs.lstat(directory)).isSymbolicLink()) throw new Error('State directory must not be a symbolic link');
    await fs.chmod(directory, 0o700);
    const tokenFile = path.join(directory, 'mcp-token');
    let token;
    try { token = (await fs.readFile(tokenFile, 'utf8')).trim(); }
    catch (error) {
      if (error.code !== 'ENOENT') throw error;
      token = randomBytes(32).toString('base64url');
      await fs.writeFile(tokenFile, `${token}\n`, { mode: 0o600, flag: 'wx' });
    }
    await fs.chmod(tokenFile, 0o600);
    if (!/^[A-Za-z0-9_-]{40,100}$/.test(token)) throw new Error('Invalid MCP credential file');
    let data;
    const stateFile = path.join(directory, 'state.json');
    try { data = JSON.parse(await fs.readFile(stateFile, 'utf8')); }
    catch (error) { if (error.code !== 'ENOENT') throw error; data = { version: 1, pairing: null, devices: [], jobs: [] }; }
    if (data.version !== 1 || !Array.isArray(data.devices) || !Array.isArray(data.jobs)) throw new Error('Unsupported bridge state');
    const store = new BridgeStore(directory, token, data, clock);
    try {
      const file = path.join(directory, 'coaching-tombstones.json');
      if ((await fs.stat(file)).size > 2 * 1024 * 1024) throw new Error('Coaching tombstones exceed capacity');
      const closed = JSON.parse(await fs.readFile(file, 'utf8'));
      if (closed.version !== 1 || !Array.isArray(closed.records) || closed.records.length > 1000) throw new Error('Invalid coaching tombstones');
      for (const [id, record] of closed.records) {
        if (!data.devices.some(device => device.id === id)) continue;
        if (record.closed !== true || record.image || record.page || !Array.isArray(record.closedSessions) || record.closedSessions.length > 64 ||
            ![record.sessionId, ...record.closedSessions].every(value => /^[0-9a-fA-F-]{36}$/.test(value)) || (!(record.accessMode === 'connection' && record.expiresAt == null) && !Number.isFinite(Date.parse(record.expiresAt))))
          throw new Error('Invalid coaching tombstone');
        store.coachingRecords.set(id, record);
      }
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    await atomicWrite(stateFile, `${JSON.stringify(data)}\n`);
    return store;
  }
  constructor(directory, token, data, clock) {
    this.directory = directory; this.token = token; this.data = data; this.clock = clock; this.tail = Promise.resolve();
    this.coaching = new CoachingSessions({ clock, read: id => this.coachingRecord(id), write: (id, value) => this.writeCoachingRecord(id, value), list: () => this.coachingDeviceIds(), header: id => this.coachingHeader(id) });
    this.coachingRecords = new Map(); this.coachingTimers = new Map(); this.seen = new Map();
  }
  now() { return new Date(this.clock()).toISOString(); }
  /// Every request refreshes when a device was last seen in memory. The saved copy moves at most
  /// every 30 s, so a device that is only polling does not rewrite its record on each request.
  touch(device, save = false) {
    const now = this.clock();
    this.seen.set(device.id, now);
    if (save || !device.lastSeen || now - Date.parse(device.lastSeen) >= SEEN_SAVE_MS) device.lastSeen = new Date(now).toISOString();
  }
  lastSeen(device) {
    const saved = device.lastSeen ? Date.parse(device.lastSeen) : null, seen = this.seen.get(device.id) ?? null;
    const latest = saved === null ? seen : seen === null ? saved : Math.max(saved, seen);
    return latest === null ? null : new Date(latest).toISOString();
  }
  coachingDeviceIds() { return [...this.coachingRecords.keys()]; }
  coachingRecord(id) { return this.coachingRecords.get(id) ?? null; }
  coachingHeader(id) { return headerOf(this.coachingRecord(id)); }
  persistCoachingTombstones() {
    if (!this.directory) return;
    const records = [...this.coachingRecords].map(([id, value]) => [id, { sessionId: value.sessionId, accessMode: value.accessMode, expiresAt: value.expiresAt,
      pageGeneration: value.pageGeneration ?? 0, closed: true, reason: value.closed ? value.reason : 'restart',
      closedSessions: value.closedSessions ?? [], annotations: [], annotationRevision: 0 }]);
    const text = JSON.stringify({ version: 1, records });
    if (text === this.coachingPersistedText) return;
    this.coachingPersistedText = text;
    this.coachingPersistence = (this.coachingPersistence ?? Promise.resolve()).catch(() => {}).then(() => atomicWrite(path.join(this.directory, 'coaching-tombstones.json'), text + '\n'));
    void this.coachingPersistence.catch(() => {});
  }
  writeCoachingRecord(id, value) {
    clearTimeout(this.coachingTimers.get(id)); this.coachingTimers.delete(id);
    if (!value) { this.coachingRecords.delete(id); this.persistCoachingTombstones(); return; }
    this.coachingRecords.set(id, structuredClone(value));
    this.persistCoachingTombstones();
    if (value.image && value.accessMode !== 'connection') {
      const delay = Math.max(1, Date.parse(value.expiresAt) - this.clock());
      const timer = setTimeout(() => { this.coaching.expire(id); this.coachingTimers.delete(id); }, delay);
      timer.unref?.(); this.coachingTimers.set(id, timer);
    }
  }
  async publishCoaching(id, payload) {
    await this.mutate(data => { this.touch(this.device(data, id)); });
    this.permission(this.device(this.data, id), 'pageRead'); const result = this.coaching.publish(id, payload); await this.coachingPersistence; return result;
  }
  deviceCoaching(id) { const device = this.device(this.data, id); return this.coaching.status(id, this.freshness(device)); }
  pauseCoaching(id, payload) { this.device(this.data, id); return this.coaching.pause(id, payload); }
  async revokeCoaching(id, payload) { this.device(this.data, id); const result = this.coaching.revoke(id, payload); await this.coachingPersistence; return result; }
  coachingPage(args) { const device = this.device(this.data, args.deviceId); this.permission(device, 'pageRead'); return this.coaching.page(device.id, this.freshness(device)); }
  annotatePage(args) { const device = this.device(this.data, args.deviceId); this.permission(device, 'pageRead'); this.permission(device, 'annotationsWrite'); return this.coaching.annotate(device.id, args); }
  async mutate(change) {
    const work = this.tail.then(async () => {
      const draft = clone(this.data);
      const value = change(draft);
      await atomicWrite(path.join(this.directory, 'state.json'), `${JSON.stringify(draft)}\n`);
      this.data = draft;
      return clone(value);
    });
    this.tail = work.catch(() => {});
    return work;
  }
  codeHash(code) { return createHmac('sha256', this.token).update(code).digest('hex'); }
  async createPairCode() {
    const code = String(randomInt(1000000)).padStart(6, '0');
    const expiresAt = new Date(this.clock() + 600000).toISOString();
    await this.mutate(data => { data.pairing = { hash: this.codeHash(code), expiresAt }; });
    return { code, expiresAt };
  }
  async pair({ code, name }) {
    const deviceToken = randomBytes(32).toString('base64url');
    const deviceId = randomUUID();
    return this.mutate(data => {
      if (!data.pairing || this.clock() >= Date.parse(data.pairing.expiresAt) || !secureEqual(data.pairing.hash, this.codeHash(code)))
        throw new BridgeError(401, 'invalid_pairing', 'Pairing code is invalid or expired');
      data.pairing = null;
      data.devices.push({ id: deviceId, name, tokenHash: digest(deviceToken), createdAt: this.now(), lastSeen: this.now(), snapshot: null });
      return { deviceId, deviceToken };
    });
  }
  authenticateDevice(token) {
    if (typeof token !== 'string' || token.length > 200) return null;
    const hash = digest(token);
    return this.data.devices.find(device => secureEqual(device.tokenHash, hash))?.id ?? null;
  }
  /// Without a deviceId, reading context and the shared page come from the current device,
  /// and library requests from the freshest library. A deviceId only targets one device.
  device(data, id, purpose = 'current') {
    if (!id && !data.devices.length) throw new BridgeError(404, 'device_not_found', 'Pair a Honbako device first');
    const found = id ? data.devices.find(device => device.id === id) : purpose === 'library' ? this.libraryDevice(data) : this.currentDevice(data);
    if (!found) throw new BridgeError(404, 'device_not_found', 'Paired device not found');
    return found;
  }
  /// The device that last reported an open reader. Every device refreshes lastSeen while
  /// it polls, so that never moves the pointer; the latest snapshot is only a fallback.
  currentDevice(data) {
    return latest(data.devices, 'readingActiveAt') ?? latest(data.devices, 'snapshotReceivedAt') ?? data.devices[0] ?? null;
  }
  libraryDevice(data) {
    const current = this.currentDevice(data);
    if (current?.snapshot && (this.freshness(current).snapshotAgeSeconds ?? Infinity) <= LIBRARY_FRESH_SECONDS) return current;
    return latest(data.devices.filter(device => device.snapshot), 'snapshotReceivedAt') ?? current;
  }
  /// Snapshots of every device a workspace-level request may run on; one targeted device otherwise.
  reachable(data, device, pinned) { return pinned ? [device] : data.devices; }
  freshness(device) {
    const lastSeen = this.lastSeen(device), age = lastSeen ? Math.max(0, this.clock() - Date.parse(lastSeen)) : Infinity;
    const stateAge = device.snapshotReceivedAt ? Math.max(0, this.clock() - Date.parse(device.snapshotReceivedAt)) : Infinity;
    return { connected: age <= 30000, snapshotFresh: stateAge <= 30000, lastSeen,
      snapshotReceivedAt: device.snapshotReceivedAt ?? null, snapshotAgeSeconds: Number.isFinite(stateAge) ? Math.floor(stateAge / 1000) : null };
  }
  status() {
    const current = this.data.devices.length ? this.currentDevice(this.data) : null;
    return { schemaVersion: 1, serverTime: this.now(), currentDeviceId: current?.id ?? null, devices: this.data.devices.map(device => ({ deviceId: device.id,
      name: device.name, current: device.id === current?.id, ...this.freshness(device), snapshotAvailable: Boolean(device.snapshot),
      libraryTruncated: device.snapshot?.libraryTruncated ?? false, sourcesTruncated: device.snapshot?.sourcesTruncated ?? false, libraryCount: device.snapshot?.library.length ?? 0,
      pendingJobs: this.data.jobs.filter(job => visibleTo(job, device.id) && !terminal.has(job.status)).length })),
      workflow: 'Open Honbako on any connected device to sync state and process jobs. Library and source changes need approval in Honbako on one of those devices; the first approval wins.' };
  }
  readingContext(args) {
    this.permission(this.device(this.data, args.deviceId), 'readingRead');
    const device = this.device(this.data, args.deviceId), freshness = this.freshness(device);
    const reading = device.snapshot?.reading ?? null;
    const active = Boolean(reading?.active && freshness.connected && freshness.snapshotFresh);
    return { deviceId: device.id, ...freshness, observation: active ? 'current' : 'last_known',
      reading: reading ? { ...reading, active } : null,
      spoilerBoundary: reading ? { chapterId: reading.chapterId, chapterTitle: reading.chapterTitle, page: reading.page,
        lastVisiblePage: reading.lastVisiblePage ?? reading.page,
        instruction: 'Do not reveal events beyond this chapter and visible page. Only metadata is available; no full text or page images are supplied.' } : null };
  }
  librarySearch(args) {
    const device = this.device(this.data, args.deviceId, 'library'), query = args.query.toLocaleLowerCase();
    this.permission(device, 'libraryRead');
    const matches = (device.snapshot?.library ?? []).filter(book => book.title.toLocaleLowerCase().includes(query)).slice(0, args.limit);
    return { deviceId: device.id, ...this.freshness(device), matches, libraryTruncated: device.snapshot?.libraryTruncated ?? false };
  }
  listSources(args) {
    const device = this.device(this.data, args.deviceId, 'library');
    this.permission(device, 'libraryRead');
    return { deviceId: device.id, ...this.freshness(device), sources: device.snapshot?.sources ?? [], sourcesTruncated: device.snapshot?.sourcesTruncated ?? false };
  }
  async disconnect(id) {
    return this.mutate(data => {
      this.device(data, id);
      data.devices = data.devices.filter(device => device.id !== id);
      data.jobs = data.jobs.filter(job => job.deviceId !== id);
      // Workspace jobs stay for the remaining devices. A change this device had
      // already claimed cannot finish elsewhere, so it fails honestly.
      for (const job of data.jobs) {
        if (job.runner === id) { delete job.runner; delete job.runnerUntil; }
        if (!terminal.has(job.status) && job.executionClaimed && claimant(job) === id) {
          job.status = 'failed'; job.updatedAt = this.now();
          job.error = 'The device that approved this request was disconnected before it finished. Check the library before retrying.';
        }
      }
      this.writeCoachingRecord(id, null);
      this.prune(data);
      return { ok: true };
    });
  }
  async updateSnapshot(id, payload) {
    const snapshot = snapshotSchema.parse(payload);
    return this.mutate(data => {
      const device = this.device(data, id);
      if (device.snapshot && Date.parse(snapshot.generatedAt) < Date.parse(device.snapshot.generatedAt))
        return { ok: true, accepted: false, reason: 'older_snapshot', receivedAt: device.snapshotReceivedAt };
      this.restrictCoaching(id, snapshot.permissions);
      device.snapshot = snapshot; device.snapshotReceivedAt = this.now(); this.touch(device, true);
      if (snapshot.reading?.active) device.readingActiveAt = this.now();
      this.prune(data);
      return { ok: true, accepted: true, receivedAt: device.snapshotReceivedAt };
    });
  }
  restrictCoaching(id, permissions) {
    if (permissions?.pageRead === false) this.writeCoachingRecord(id, null);
    else if (permissions?.annotationsWrite === false) {
      const coaching = this.coachingRecord(id);
      if (coaching?.annotations?.length) this.writeCoachingRecord(id, { ...coaching, annotations: [], annotationRevision: coaching.annotationRevision + 1 });
    }
  }
  /// Permissions shared by every device of a hosted workspace; local pairings keep per-device switches.
  accountPermissions() { return null; }
  async restrictToAccountPermissions() {
    return this.mutate(data => {
      for (const device of data.devices) this.restrictCoaching(device.id, this.accountPermissions());
      this.prune(data);
      return { ok: true };
    });
  }
  allows(device, job) {
    const denied = name => device.snapshot?.permissions?.[name] === false || this.accountPermissions()?.[name] === false;
    if (['catalog.search', 'sources.catalog'].includes(job.kind)) return !denied('libraryRead');
    if (job.kind === 'history.read') return device.snapshot?.readingHistoryAccess === true && !denied('readingRead');
    return true;
  }
  /// Drops search, source-catalog and history work (including results) once no device that
  /// could run it still allows it. A workspace job survives while any device allows it.
  prune(data) {
    data.jobs = data.jobs.filter(job => {
      const devices = job.deviceId == null ? data.devices : data.devices.filter(device => device.id === job.deviceId);
      return devices.some(device => this.allows(device, job));
    });
  }
  /// Whether a device has what an unpinned job needs. Jobs nobody can run go to every device.
  canRun(device, job) {
    const snapshot = device.snapshot, capabilities = snapshot?.automationCapabilities ?? [];
    const sources = new Set((snapshot?.sources ?? []).map(source => source.id));
    if (job.kind === 'catalog.search') return job.payload.sourceIds.every(id => sources.has(id));
    if (job.kind === 'library.add') return job.payload.items.every(item => sources.has(item.sourceId));
    if (job.kind === 'library.remove') return capabilities.includes('library.remove');
    if (job.kind === 'history.read') return capabilities.includes('reading.history') && snapshot?.readingHistoryAccess === true;
    if (['sources.catalog', 'sources.change'].includes(job.kind)) return capabilities.includes('sources.manage');
    return true;
  }
  offered(data, job, device, now) {
    if (!['queued', 'awaitingApproval'].includes(job.status) || !visibleTo(job, device.id)) return false;
    // A change another device claimed is no longer this device's to approve.
    if (job.executionClaimed && claimant(job) !== device.id) return false;
    if (job.deviceId != null) return true;
    if (!approvalKinds.has(job.kind) && job.runner && job.runner !== device.id && job.runnerUntil > now && data.devices.some(other => other.id === job.runner)) return false;
    return this.canRun(device, job) || !data.devices.some(other => this.canRun(other, job));
  }
  async deviceJobs(id) {
    return this.mutate(data => {
      const device = this.device(data, id), now = this.clock();
      this.touch(device);
      const jobs = data.jobs.filter(job => this.offered(data, job, device, now));
      // Searches and reads run on one device at a time; a device that goes quiet loses its turn.
      for (const job of jobs) if (job.deviceId == null && !approvalKinds.has(job.kind) && (job.runner !== id || job.runnerUntil - now < RUNNER_MS / 2)) {
        job.runner = id; job.runnerUntil = now + RUNNER_MS;
      }
      const handled = data.jobs.filter(job => approvalKinds.has(job.kind) && job.handledBy && job.handledBy !== id && visibleTo(job, id)
        && now - Date.parse(job.updatedAt) < HANDLED_MS).slice(-20)
        .map(job => ({ id: job.id, status: job.status, handledBy: data.devices.find(other => other.id === job.handledBy)?.name ?? null }));
      return { jobs: jobs.map(job => this.publicJob(job)), handled, coaching: this.coaching.summary(id) };
    });
  }
  publicJob(job) {
    const { id, kind, payload, status, createdAt, updatedAt, executionClaimed, result, error } = job;
    const deviceId = job.deviceId ?? job.handledBy ?? job.runner ?? null;
    return { deviceId, id, kind, payload, status, createdAt, updatedAt, executionClaimed: Boolean(executionClaimed),
      ...(result === undefined ? {} : { result }), ...(error ? { error } : {}) };
  }
  createJob(data, device, kind, payload, idempotencyKey, pinned = true) {
    if (data.jobs.filter(job => !terminal.has(job.status)).length >= 100) throw new BridgeError(429, 'queue_full', 'Finish or cancel queued work before adding more jobs');
    const job = { id: randomUUID(), deviceId: pinned ? device.id : null, kind, payload, status: 'queued', createdAt: this.now(), updatedAt: this.now(),
      ...(idempotencyKey ? { idempotencyKey } : {}) };
    data.jobs.push(job);
    // Bound recent completed metadata; pending work remains durable. Native additions also deduplicate by book identity.
    const finished = data.jobs.filter(job => terminal.has(job.status));
    if (finished.length > 2000) {
      const remove = new Set(finished.slice(0, finished.length - 2000).map(job => job.id));
      data.jobs = data.jobs.filter(job => !remove.has(job.id));
    }
    return this.publicJob(job);
  }
  permission(device, name) {
    if (device.snapshot?.permissions?.[name] === false || this.accountPermissions()?.[name] === false) throw new BridgeError(403, 'permission_disabled', 'This capability is disabled in Honbako MCP permissions');
  }
  requireCapability(device, capability) {
    if (!device.snapshot?.automationCapabilities?.includes(capability))
      throw new BridgeError(409, 'update_app', 'Open an updated Honbako app and wait for it to sync before using this tool');
  }
  async readingHistory(args) {
    return this.mutate(data => {
      const device = this.device(data, args.deviceId, 'library'); this.requireCapability(device, 'reading.history'); this.permission(device, 'readingRead');
      if (device.snapshot?.readingHistoryAccess !== true) throw new BridgeError(403, 'reading_access_disabled', 'Enable Reading Access in Honbako before requesting history');
      return this.createJob(data, device, 'history.read', { offset: args.offset, limit: args.limit, before: args.before ?? this.now() }, undefined, Boolean(args.deviceId));
    });
  }
  async sourceCatalog(args) {
    return this.mutate(data => {
      const device = this.device(data, args.deviceId, 'library'); this.requireCapability(device, 'sources.manage'); this.permission(device, 'libraryRead');
      return this.createJob(data, device, 'sources.catalog', { offset: args.offset, limit: args.limit }, undefined, Boolean(args.deviceId));
    });
  }
  async manageSources(args) {
    return this.mutate(data => {
      const device = this.device(data, args.deviceId, 'library'); this.requireCapability(device, 'sources.manage'); this.permission(device, 'sourcesWrite');
      const existing = data.jobs.find(j => visibleTo(j, device.id) && j.kind === 'sources.change' && j.idempotencyKey === args.idempotencyKey);
      if (existing) {
        if (JSON.stringify(existing.payload.change) !== JSON.stringify(args.change)) throw new BridgeError(409, 'idempotency_conflict', 'This key already belongs to a different source change');
        return this.publicJob(existing);
      }
      return this.createJob(data, device, 'sources.change', { change: args.change, idempotencyKey: args.idempotencyKey }, args.idempotencyKey, Boolean(args.deviceId));
    });
  }
  async searchCatalog(args) {
    return this.mutate(data => {
      const device = this.device(data, args.deviceId, 'library'), pinned = Boolean(args.deviceId);
      this.permission(device, 'libraryRead');
      const searchable = d => (d.snapshot?.sources ?? []).filter(source => source.supportsSearch);
      const sources = this.reachable(data, device, pinned).flatMap(searchable);
      const ids = args.sourceIds ?? searchable(device).map(source => source.id);
      if (ids.length > 20) throw new BridgeError(400, 'choose_sources', 'Choose up to 20 connected source IDs for one catalog search');
      if (!ids.length || ids.some(id => !sources.some(source => source.id === id)))
        throw new BridgeError(400, 'source_not_connected', 'Search only sources already connected and enabled in Honbako');
      return this.createJob(data, device, 'catalog.search', { query: args.query, sourceIds: [...new Set(ids)], limit: args.limit }, undefined, pinned);
    });
  }
  async addToLibrary(args) {
    return this.mutate(data => {
      const device = this.device(data, args.deviceId, 'library'), pinned = Boolean(args.deviceId), devices = this.reachable(data, device, pinned);
      this.permission(device, 'libraryWrite');
      const items = [...new Map(args.items.map(item => [key(item), item])).values()];
      const existing = data.jobs.find(job => visibleTo(job, device.id) && job.kind === 'library.add' && job.idempotencyKey === args.idempotencyKey);
      if (existing) {
        if (JSON.stringify(existing.payload.items.map(key).sort()) !== JSON.stringify(items.map(key).sort()))
          throw new BridgeError(409, 'idempotency_conflict', 'This idempotency key was already used for different books');
        return this.publicJob(existing);
      }
      const known = new Set(devices.flatMap(d => d.snapshot?.library ?? []).map(key));
      for (const job of data.jobs.filter(job => visibleTo(job, device.id) && job.kind === 'catalog.search' && job.status === 'completed'))
        for (const match of job.result?.matches ?? []) known.add(key(match));
      if (items.some(item => !known.has(key(item)))) throw new BridgeError(400, 'search_first', 'Search the connected catalog and use an exact returned title ID before adding');
      if (items.some(item => !devices.some(d => (d.snapshot?.sources ?? []).some(source => source.id === item.sourceId))))
        throw new BridgeError(400, 'source_not_connected', 'The selected source is no longer connected');
      return this.createJob(data, device, 'library.add', { items, idempotencyKey: args.idempotencyKey }, args.idempotencyKey, pinned);
    });
  }
  async removeFromLibrary(args) {
    return this.mutate(data => {
      const device = this.device(data, args.deviceId, 'library'), pinned = Boolean(args.deviceId);
      this.requireCapability(device, 'library.remove'); this.permission(device, 'libraryWrite');
      const items = [...new Map(args.items.map(item => [key(item), item])).values()];
      const existing = data.jobs.find(job => visibleTo(job, device.id) && job.kind === 'library.remove' && job.idempotencyKey === args.idempotencyKey);
      if (existing) {
        if (JSON.stringify(existing.payload.items.map(key).sort()) !== JSON.stringify(items.map(key).sort()))
          throw new BridgeError(409, 'idempotency_conflict', 'This idempotency key was already used for different books');
        return this.publicJob(existing);
      }
      const saved = new Set(this.reachable(data, device, pinned).flatMap(d => d.snapshot?.library ?? []).map(key));
      if (items.some(item => !saved.has(key(item)))) throw new BridgeError(400, 'not_in_library', 'Use honbako_search_library and remove only exact saved title IDs');
      return this.createJob(data, device, 'library.remove', { items, idempotencyKey: args.idempotencyKey }, args.idempotencyKey, pinned);
    });
  }
  job(args) {
    if (args.deviceId) this.device(this.data, args.deviceId);
    const job = this.data.jobs.find(job => job.id === args.jobId && (!args.deviceId || visibleTo(job, args.deviceId)));
    if (!job) throw new BridgeError(404, 'job_not_found', 'Job not found for this device');
    return this.publicJob(job);
  }
  async cancelJob(args) {
    return this.mutate(data => {
      if (args.deviceId) this.device(data, args.deviceId);
      const job = data.jobs.find(job => job.id === args.jobId && (!args.deviceId || visibleTo(job, args.deviceId)));
      if (!job) throw new BridgeError(404, 'job_not_found', 'Job not found for this device');
      if (terminal.has(job.status)) return this.publicJob(job);
      if (job.executionClaimed) throw new BridgeError(409, 'already_executing', 'Approval was already granted and the phone may be executing this job; cancellation is too late');
      if (!terminal.has(job.status)) { job.status = 'cancelled'; job.updatedAt = this.now(); }
      return this.publicJob(job);
    });
  }
  async updateJob(deviceId, jobId, payload) {
    return this.mutate(data => {
      this.touch(this.device(data, deviceId), true);
      const job = data.jobs.find(job => job.id === jobId && visibleTo(job, deviceId));
      if (!job) throw new BridgeError(404, 'job_not_found', 'Job not found for this device');
      // The first device to approve a change claims it; every other device's
      // answer is refused, so it can never fail or reject work in progress.
      const approval = approvalKinds.has(job.kind), elsewhere = approval && (job.executionClaimed ? claimant(job) : job.handledBy ?? deviceId) !== deviceId;
      if (terminal.has(job.status)) {
        if (elsewhere) throw handledElsewhere();
        if (job.status === payload.status) return { ok: true, job: this.publicJob(job) };
        throw new BridgeError(409, 'job_terminal', 'Job is already finished or cancelled');
      }
      if (elsewhere) throw handledElsewhere();
      if (payload.approvalGranted && (!approvalKinds.has(job.kind) || payload.status !== 'awaitingApproval'))
        throw new BridgeError(400, 'invalid_approval', 'Approval can only claim a pending library or source change');
      if (approvalKinds.has(job.kind) && payload.status === 'completed' && !job.executionClaimed)
        throw new BridgeError(409, 'approval_required', 'Approve the change on the phone before executing it');
      if (payload.status === 'completed') {
        const device = this.device(data, deviceId);
        if (['library.add', 'library.remove'].includes(job.kind)) this.permission(device, 'libraryWrite');
        if (job.kind === 'sources.change') this.permission(device, 'sourcesWrite');
        const validators = { 'catalog.search': searchResult, 'library.add': addResult, 'library.remove': removeResult, 'history.read': historyResult,
          'sources.catalog': sourceCatalogResult, 'sources.change': sourceChangeResult };
        const result = validators[job.kind].parse(payload.result);
        if (job.kind === 'history.read' && (deviceHistoryDisabled(data, deviceId) || result.entries.length > job.payload.limit || result.before !== job.payload.before))
          throw new BridgeError(403, 'reading_access_disabled', 'History access is disabled or this page is outside the request');
        if (job.kind === 'sources.catalog' && result.sources.length > job.payload.limit) throw new BridgeError(400, 'result_out_of_scope', 'Source page exceeds requested limit');
        if (job.kind === 'sources.change' && JSON.stringify(result.change) !== JSON.stringify(job.payload.change))
          throw new BridgeError(400, 'result_out_of_scope', 'Source result must match the approved change');
        if (job.kind === 'catalog.search' && (result.matches.length > job.payload.limit || result.matches.some(match => !job.payload.sourceIds.includes(match.sourceId))))
          throw new BridgeError(400, 'result_out_of_scope', 'Search results must belong to the requested connected sources');
        if (job.kind === 'library.add' && [...result.added, ...result.alreadyPresent].some(item => !job.payload.items.some(asked => key(asked) === key(item))))
          throw new BridgeError(400, 'result_out_of_scope', 'Addition results must belong to the approved job');
        if (job.kind === 'library.add') {
          const accounted = [...result.added, ...result.alreadyPresent].map(key);
          if (new Set(accounted).size !== accounted.length || job.payload.items.some(item => !accounted.includes(key(item))))
            throw new BridgeError(400, 'incomplete_result', 'Every approved book must be accounted for exactly once before completion');
        }
        if (job.kind === 'library.remove') {
          const accounted = [...result.removed, ...result.notPresent].map(key);
          if (accounted.some(item => !job.payload.items.some(asked => key(asked) === item)))
            throw new BridgeError(400, 'result_out_of_scope', 'Removal results must belong to the approved job');
          if (new Set(accounted).size !== accounted.length || job.payload.items.some(item => !accounted.includes(key(item))))
            throw new BridgeError(400, 'incomplete_result', 'Every approved book must be accounted for exactly once before completion');
        }
        job.result = result;
      }
      if (payload.approvalGranted) { job.executionClaimed = true; job.claimedBy = deviceId; }
      if (approval && (payload.approvalGranted || terminal.has(payload.status))) job.handledBy = deviceId;
      job.status = payload.status; job.updatedAt = this.now();
      if (payload.error) job.error = payload.error;
      return { ok: true, job: this.publicJob(job) };
    });
  }
}
