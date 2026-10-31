import { BridgeError } from '../../src/store.js';

export const FAMILY_LIMIT = 5;

/// One shared workspace per purchase. Before shared workspaces, `purchase:<hash>` held up to
/// five installation IDs, each with its own workspace; they become the migration's legacy list.
export class PurchaseRegistry {
  constructor(store) { this.store = store; }
  mapping(purchaseHash) {
    const record = this.store.control(`purchase:${purchaseHash}`);
    return Array.isArray(record) ? { workspaceId: null, legacy: record } : record ?? { workspaceId: null, legacy: [] };
  }
  find(purchaseHash, id) {
    const { workspaceId, legacy } = this.mapping(purchaseHash);
    return { workspaceId, retire: Boolean(workspaceId) && workspaceId !== id && legacy.includes(id) };
  }
  /// First wins. The first device to enroll after the update lends its ID, so its AI connections keep working.
  bind(purchaseHash, id) {
    const mapping = this.mapping(purchaseHash);
    if (mapping.workspaceId) return mapping.workspaceId;
    this.store.setControl(`purchase:${purchaseHash}`, { workspaceId: id, legacy: mapping.legacy.filter(x => x !== id) });
    return id;
  }
  /// Drops a mapping whose workspace moved to another purchase after every device left it.
  unbind(purchaseHash, workspaceId) {
    const mapping = this.mapping(purchaseHash);
    if (mapping.workspaceId === workspaceId) this.store.setControl(`purchase:${purchaseHash}`, { ...mapping, workspaceId: null });
  }
  forget(purchaseHash, id) {
    const mapping = this.mapping(purchaseHash);
    if (mapping.workspaceId && mapping.legacy.includes(id)) this.store.setControl(`purchase:${purchaseHash}`, { ...mapping, legacy: mapping.legacy.filter(x => x !== id) });
  }
  /// Family Sharing members each get a per-installation workspace; a purchase cannot spawn unlimited ones.
  allocateFamily(purchaseHash, id) {
    const key = `family:${purchaseHash}`, current = this.store.control(key) ?? [];
    if (current.includes(id)) return;
    if (current.length >= FAMILY_LIMIT) throw new BridgeError(429, 'device_limit', 'This subscription already has five family workspaces');
    this.store.setControl(key, [...current, id]);
  }
  releaseFamily(purchaseHash, id) {
    const key = `family:${purchaseHash}`, current = this.store.control(key) ?? [];
    if (current.includes(id)) this.store.setControl(key, current.filter(x => x !== id));
  }
}

/// Routes a verified enrollment to its purchase's shared workspace. The workspace decides whether
/// the device may join; the mapping is bound only after it accepts, so a refused device cannot claim it.
export async function routeEnrollment({ purchases, workspace }, body, lease, base) {
  const id = body.installationId, into = target => workspace(target).enroll(body, lease, base, target);
  if (lease.familyShared) {
    await purchases.allocateFamily(lease.purchaseHash, id);
    return into(id);
  }
  const route = await purchases.find(lease.purchaseHash, id);
  let target = route.workspaceId ?? id, enrolled;
  try { enrolled = await into(target); }
  catch (error) {
    if (!route.workspaceId || error?.code !== 'purchase_mismatch') throw error;
    // The mapped workspace was emptied and taken over by another purchase; start a new one.
    await purchases.unbind(lease.purchaseHash, route.workspaceId);
    return routeEnrollment({ purchases, workspace }, body, lease, base);
  }
  if (!route.workspaceId) {
    const winner = await purchases.bind(lease.purchaseHash, target);
    if (winner !== target) {
      // Two first devices raced; join the winner and close the workspace this device just took.
      await workspace(target).retire(body);
      target = winner; enrolled = await into(target);
    }
  }
  if (route.retire) {
    // This device had its own workspace before the update. Close it once it has joined.
    await workspace(id).retire(body);
    await purchases.forget(lease.purchaseHash, id);
  }
  return enrolled;
}
