import { unwrapRPC } from './remote/rpc.js';
import { failure, readJson, reply, MAX_MIGRATION } from './core.js';

// No public routes, workers.dev URL, or preview URL. Invoke through an account-owned service binding.
export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);
      if (url.pathname !== '/admin' || url.search || request.method !== 'POST' || request.headers.has('origin')) return reply(404, { error: { code: 'not_found', message: 'Endpoint not found' } });
      const key = /^Bearer ([A-Za-z0-9_-]{43,100})$/.exec(request.headers.get('authorization') ?? '')?.[1] ?? '';
      const { action, params = {} } = await readJson(request, MAX_MIGRATION);
      const result = await env.HONBAKO_OWNER.get(env.HONBAKO_OWNER.idFromName(env.OWNER_NAME)).admin(action, params, key);
      return reply(200, action === 'verify-apple' ? unwrapRPC(result) : result);
    } catch (error) { return failure(error); }
  }
};
