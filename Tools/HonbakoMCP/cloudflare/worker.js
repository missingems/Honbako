import { rpcResult } from './remote/rpc.js';
import { checkAppleConnection } from './remote/apple-connection.js';
import { remoteFetch } from './remote/worker.js';
export { HonbakoAuthorization, HonbakoWorkspace } from './remote/worker.js';
import { DurableObject } from 'cloudflare:workers';
import { SqliteBridgeStore } from './storage.js';
import { HostedBridgeCore, reply } from './core.js';

export class HonbakoOwner extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.env = env;
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
  async admin(action, params, key) {
    if (action === 'verify-apple') {
      // Reuse the existing owner authentication; this has no public HTTP route.
      return rpcResult(async () => {
        await this.core.admin('status', {}, key);
        return checkAppleConnection(this.env);
      });
    }
    return this.core.admin(action, params, key);
  }
}
export default {
  fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === '/remote' || path.startsWith('/remote/') || path.startsWith('/.well-known/')) return remoteFetch(request, env);
    if (!env.OWNER_NAME || !env.HONBAKO_OWNER) return reply(503, { error: { code: 'not_configured', message: 'Companion is not configured' } });
    return env.HONBAKO_OWNER.get(env.HONBAKO_OWNER.idFromName(env.OWNER_NAME)).fetch(request);
  }
};
