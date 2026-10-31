import { z } from 'zod';
import { createHash } from 'node:crypto';
import { snapshot, item, searchResult, addResult } from '../src/schema.js';
import { BridgeError } from '../src/store.js';
const date = z.iso.datetime({ offset: true });
const uuid = z.uuid();
const idempotency = z.string().regex(/^[A-Za-z0-9_-]{1,128}$/);
const device = z.object({ id: uuid, name: z.string().min(1).max(512), tokenHash: z.string().regex(/^[0-9a-f]{64}$/),
  createdAt: date, lastSeen: date.nullable().optional(), snapshot: snapshot.nullable(), snapshotReceivedAt: date.optional() }).strict();
const common = { id: uuid, deviceId: uuid, status: z.enum(['queued', 'awaitingApproval', 'completed', 'failed', 'rejected', 'cancelled']),
  createdAt: date, updatedAt: date, executionClaimed: z.boolean().optional(), error: z.string().max(1000).optional(), idempotencyKey: idempotency.optional() };
const job = z.discriminatedUnion('kind', [
  z.object({ ...common, kind: z.literal('catalog.search'), payload: z.object({ query: z.string().min(1).max(300), sourceIds: z.array(z.string().min(1).max(256)).min(1).max(20), limit: z.number().int().min(1).max(20) }).strict(), result: searchResult.optional() }).strict(),
  z.object({ ...common, kind: z.literal('library.add'), payload: z.object({ items: z.array(item).min(1).max(20), idempotencyKey: idempotency }).strict(), result: addResult.optional() }).strict()
]);
const state = z.object({ version: z.literal(1), pairing: z.unknown().nullable(), devices: z.array(device).max(100), jobs: z.array(job).max(2100) }).strict();
export const stateDigest = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
export function validateMigration(envelope) {
  if (!envelope || envelope.version !== 1 || !/^[0-9a-f]{64}$/.test(envelope.sha256 ?? '') || stateDigest(envelope.state) !== envelope.sha256)
    throw new BridgeError(400, 'invalid_migration', 'Migration checksum or version is invalid');
  const parsed = state.parse(envelope.state);
  const deviceIds = new Set(parsed.devices.map(value => value.id));
  if (deviceIds.size !== parsed.devices.length || new Set(parsed.jobs.map(value => value.id)).size !== parsed.jobs.length || parsed.jobs.some(value => !deviceIds.has(value.deviceId)))
    throw new BridgeError(400, 'invalid_migration', 'Migration identities are inconsistent');
  if (parsed.jobs.some(value => value.executionClaimed && !['completed', 'failed', 'rejected', 'cancelled'].includes(value.status)))
    throw new BridgeError(409, 'execution_in_progress', 'Finish executing jobs before moving this companion');
  if (parsed.jobs.some(value => value.kind === 'library.add' && value.status === 'completed' && !value.executionClaimed))
    throw new BridgeError(400, 'invalid_migration', 'Completed imports must retain their approval receipts');
  return { ...parsed, pairing: null };
}
