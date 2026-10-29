import { reply } from './core.js';

// Wrangler dev binds this facade to 127.0.0.1. The remote binding uses the operator's Cloudflare login.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) || url.pathname !== '/admin' || url.search || request.method !== 'POST' || request.headers.has('origin'))
      return reply(404, { error: { code: 'not_found', message: 'Endpoint not found' } });
    return env.REMOTE_ADMIN.fetch(new Request('https://admin.internal/admin', {
      method: 'POST', headers: { 'content-type': request.headers.get('content-type') ?? '', authorization: request.headers.get('authorization') ?? '' }, body: request.body, duplex: 'half'
    }));
  }
};
