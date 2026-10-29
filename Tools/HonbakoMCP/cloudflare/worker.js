import { DurableObject } from 'cloudflare:workers';
import { SqliteBridgeStore } from './storage.js';
import { HostedBridgeCore, reply } from './core.js';

export class HonbakoOwner extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.core = new HostedBridgeCore(new SqliteBridgeStore(ctx.storage, env.PAIRING_KEY), {
        publicOrigin: env.PUBLIC_ORIGIN, adminKey: env.ADMIN_KEY
      });
    });
  }
  async fetch(request) {
    const response = await this.core.fetch(request);
    await this.core.store.flushCoachingAlarm();
    return response;
  }
  alarm() { return this.core.store.expireCoaching(); }
  // RPC is reachable only by account-owned bindings, with an additional owner credential.
  admin(action, params, key) { return this.core.admin(action, params, key); }
}
export default {
  fetch(request, env) {
    if (!env.OWNER_NAME || !env.HONBAKO_OWNER) return reply(503, { error: { code: 'not_configured', message: 'Companion is not configured' } });
    return env.HONBAKO_OWNER.get(env.HONBAKO_OWNER.idFromName(env.OWNER_NAME)).fetch(request);
  }
};
