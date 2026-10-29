import { promises as fs } from 'node:fs';
import path from 'node:path';
import { randomBytes, randomInt, randomUUID, createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { snapshot as snapshotSchema, searchResult, addResult } from './schema.js';
import { BridgeError } from './errors.js';
import { CoachingSessions } from './coaching.js';
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
const terminal = new Set(['completed', 'failed', 'rejected', 'cancelled']);
const clone = value => structuredClone(value);
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
    this.coaching = new CoachingSessions({ clock, read: id => this.coachingRecord(id), write: (id, value) => this.writeCoachingRecord(id, value), list: () => this.coachingDeviceIds() });
    this.coachingRecords = new Map(); this.coachingTimers = new Map();
  }
  now() { return new Date(this.clock()).toISOString(); }
  coachingDeviceIds() { return [...this.coachingRecords.keys()]; }
  coachingRecord(id) { return this.coachingRecords.get(id) ?? null; }
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
    await this.mutate(data => { this.device(data, id).lastSeen = this.now(); });
    this.device(this.data, id); const result = this.coaching.publish(id, payload); await this.coachingPersistence; return result;
  }
  deviceCoaching(id) { const device = this.device(this.data, id); return this.coaching.status(id, this.freshness(device)); }
  pauseCoaching(id, payload) { this.device(this.data, id); return this.coaching.pause(id, payload); }
  async revokeCoaching(id, payload) { this.device(this.data, id); const result = this.coaching.revoke(id, payload); await this.coachingPersistence; return result; }
  coachingPage(args) { const device = this.device(this.data, args.deviceId); return this.coaching.page(device.id, this.freshness(device)); }
  annotatePage(args) { const device = this.device(this.data, args.deviceId); return this.coaching.annotate(device.id, args); }
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
  device(data, id) {
    if (!id && data.devices.length !== 1) throw new BridgeError(400, 'choose_device', data.devices.length ? 'Specify deviceId when more than one device is paired' : 'Pair a Honbako device first');
    const found = data.devices.find(device => device.id === (id ?? data.devices[0]?.id));
    if (!found) throw new BridgeError(404, 'device_not_found', 'Paired device not found');
    return found;
  }
  freshness(device) {
    const age = device.lastSeen ? Math.max(0, this.clock() - Date.parse(device.lastSeen)) : Infinity;
    const stateAge = device.snapshotReceivedAt ? Math.max(0, this.clock() - Date.parse(device.snapshotReceivedAt)) : Infinity;
    return { connected: age <= 30000, snapshotFresh: stateAge <= 30000, lastSeen: device.lastSeen,
      snapshotReceivedAt: device.snapshotReceivedAt ?? null, snapshotAgeSeconds: Number.isFinite(stateAge) ? Math.floor(stateAge / 1000) : null };
  }
  status() {
    return { schemaVersion: 1, serverTime: this.now(), devices: this.data.devices.map(device => ({ deviceId: device.id,
      name: device.name, ...this.freshness(device), snapshotAvailable: Boolean(device.snapshot),
      libraryTruncated: device.snapshot?.libraryTruncated ?? false, sourcesTruncated: device.snapshot?.sourcesTruncated ?? false, libraryCount: device.snapshot?.library.length ?? 0,
      pendingJobs: this.data.jobs.filter(job => job.deviceId === device.id && !terminal.has(job.status)).length })),
      workflow: 'Open Honbako on the paired device to sync state and process jobs. Library additions require approval on the phone.' };
  }
  readingContext(args) {
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
    const device = this.device(this.data, args.deviceId), query = args.query.toLocaleLowerCase();
    const matches = (device.snapshot?.library ?? []).filter(book => book.title.toLocaleLowerCase().includes(query)).slice(0, args.limit);
    return { deviceId: device.id, ...this.freshness(device), matches, libraryTruncated: device.snapshot?.libraryTruncated ?? false };
  }
  listSources(args) {
    const device = this.device(this.data, args.deviceId);
    return { deviceId: device.id, ...this.freshness(device), sources: device.snapshot?.sources ?? [], sourcesTruncated: device.snapshot?.sourcesTruncated ?? false };
  }
  async disconnect(id) {
    return this.mutate(data => {
      this.device(data, id);
      data.devices = data.devices.filter(device => device.id !== id);
      data.jobs = data.jobs.filter(job => job.deviceId !== id);
      this.writeCoachingRecord(id, null);
      return { ok: true };
    });
  }
  async updateSnapshot(id, payload) {
    const snapshot = snapshotSchema.parse(payload);
    return this.mutate(data => {
      const device = this.device(data, id);
      if (device.snapshot && Date.parse(snapshot.generatedAt) < Date.parse(device.snapshot.generatedAt))
        return { ok: true, accepted: false, reason: 'older_snapshot', receivedAt: device.snapshotReceivedAt };
      device.snapshot = snapshot; device.snapshotReceivedAt = this.now(); device.lastSeen = this.now();
      return { ok: true, accepted: true, receivedAt: device.snapshotReceivedAt };
    });
  }
  async deviceJobs(id) {
    return this.mutate(data => {
      this.device(data, id).lastSeen = this.now();
      return { jobs: data.jobs.filter(job => job.deviceId === id && ['queued', 'awaitingApproval'].includes(job.status)).map(job => this.publicJob(job)) };
    });
  }
  publicJob(job) {
    const { deviceId, id, kind, payload, status, createdAt, updatedAt, executionClaimed, result, error } = job;
    return { deviceId, id, kind, payload, status, createdAt, updatedAt, executionClaimed: Boolean(executionClaimed),
      ...(result === undefined ? {} : { result }), ...(error ? { error } : {}) };
  }
  createJob(data, device, kind, payload, idempotencyKey) {
    if (data.jobs.filter(job => !terminal.has(job.status)).length >= 100) throw new BridgeError(429, 'queue_full', 'Finish or cancel queued work before adding more jobs');
    const job = { id: randomUUID(), deviceId: device.id, kind, payload, status: 'queued', createdAt: this.now(), updatedAt: this.now(),
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
  async searchCatalog(args) {
    return this.mutate(data => {
      const device = this.device(data, args.deviceId);
      const sources = (device.snapshot?.sources ?? []).filter(source => source.supportsSearch);
      const ids = args.sourceIds ?? sources.map(source => source.id);
      if (ids.length > 20) throw new BridgeError(400, 'choose_sources', 'Choose up to 20 connected source IDs for one catalog search');
      if (!ids.length || ids.some(id => !sources.some(source => source.id === id)))
        throw new BridgeError(400, 'source_not_connected', 'Search only sources already connected and enabled in Honbako');
      return this.createJob(data, device, 'catalog.search', { query: args.query, sourceIds: [...new Set(ids)], limit: args.limit });
    });
  }
  async addToLibrary(args) {
    return this.mutate(data => {
      const device = this.device(data, args.deviceId);
      const items = [...new Map(args.items.map(item => [key(item), item])).values()];
      const existing = data.jobs.find(job => job.deviceId === device.id && job.kind === 'library.add' && job.idempotencyKey === args.idempotencyKey);
      if (existing) {
        if (JSON.stringify(existing.payload.items.map(key).sort()) !== JSON.stringify(items.map(key).sort()))
          throw new BridgeError(409, 'idempotency_conflict', 'This idempotency key was already used for different books');
        return this.publicJob(existing);
      }
      const known = new Set((device.snapshot?.library ?? []).map(key));
      for (const job of data.jobs.filter(job => job.deviceId === device.id && job.kind === 'catalog.search' && job.status === 'completed'))
        for (const match of job.result?.matches ?? []) known.add(key(match));
      if (items.some(item => !known.has(key(item)))) throw new BridgeError(400, 'search_first', 'Search the connected catalog and use an exact returned title ID before adding');
      if (items.some(item => !(device.snapshot?.sources ?? []).some(source => source.id === item.sourceId)))
        throw new BridgeError(400, 'source_not_connected', 'The selected source is no longer connected');
      return this.createJob(data, device, 'library.add', { items, idempotencyKey: args.idempotencyKey }, args.idempotencyKey);
    });
  }
  job(args) {
    const device = this.device(this.data, args.deviceId);
    const job = this.data.jobs.find(job => job.id === args.jobId && job.deviceId === device.id);
    if (!job) throw new BridgeError(404, 'job_not_found', 'Job not found for this device');
    return this.publicJob(job);
  }
  async cancelJob(args) {
    return this.mutate(data => {
      const device = this.device(data, args.deviceId);
      const job = data.jobs.find(job => job.id === args.jobId && job.deviceId === device.id);
      if (!job) throw new BridgeError(404, 'job_not_found', 'Job not found for this device');
      if (terminal.has(job.status)) return this.publicJob(job);
      if (job.executionClaimed) throw new BridgeError(409, 'already_executing', 'Approval was already granted and the phone may be executing this job; cancellation is too late');
      if (!terminal.has(job.status)) { job.status = 'cancelled'; job.updatedAt = this.now(); }
      return this.publicJob(job);
    });
  }
  async updateJob(deviceId, jobId, payload) {
    return this.mutate(data => {
      this.device(data, deviceId).lastSeen = this.now();
      const job = data.jobs.find(job => job.id === jobId && job.deviceId === deviceId);
      if (!job) throw new BridgeError(404, 'job_not_found', 'Job not found for this device');
      if (terminal.has(job.status)) {
        if (job.status === payload.status) return { ok: true, job: this.publicJob(job) };
        throw new BridgeError(409, 'job_terminal', 'Job is already finished or cancelled');
      }
      if (payload.approvalGranted && (job.kind !== 'library.add' || payload.status !== 'awaitingApproval'))
        throw new BridgeError(400, 'invalid_approval', 'Approval can only claim a pending library addition');
      if (job.kind === 'library.add' && payload.status === 'completed' && !job.executionClaimed)
        throw new BridgeError(409, 'approval_required', 'Approve the addition on the phone before executing it');
      if (payload.status === 'completed') {
        const result = job.kind === 'catalog.search' ? searchResult.parse(payload.result) : addResult.parse(payload.result);
        if (job.kind === 'catalog.search' && (result.matches.length > job.payload.limit || result.matches.some(match => !job.payload.sourceIds.includes(match.sourceId))))
          throw new BridgeError(400, 'result_out_of_scope', 'Search results must belong to the requested connected sources');
        if (job.kind === 'library.add' && [...result.added, ...result.alreadyPresent].some(item => !job.payload.items.some(asked => key(asked) === key(item))))
          throw new BridgeError(400, 'result_out_of_scope', 'Addition results must belong to the approved job');
        if (job.kind === 'library.add') {
          const accounted = [...result.added, ...result.alreadyPresent].map(key);
          if (new Set(accounted).size !== accounted.length || job.payload.items.some(item => !accounted.includes(key(item))))
            throw new BridgeError(400, 'incomplete_result', 'Every approved book must be accounted for exactly once before completion');
        }
        job.result = result;
      }
      if (payload.approvalGranted) job.executionClaimed = true;
      job.status = payload.status; job.updatedAt = this.now();
      if (payload.error) job.error = payload.error;
      return { ok: true, job: this.publicJob(job) };
    });
  }
}
