import { unwrapRPC } from './rpc.js';
import { failure, reply, readJson } from '../core.js';
import { BridgeError, digest } from '../../src/store.js';
import { AppleProVerifier } from './entitlement.js';
import { UUID, discovery, tokenFrom, tokenParts, validRouteToken } from './oauth.js';
import { remoteBases, remoteRequestBase } from './origins.js';
import { routeEnrollment } from './purchases.js';

export const baseFor = env => `${env.PUBLIC_ORIGIN}/remote`;
export const workspace = (env, id) => env.HONBAKO_WORKSPACE.get(env.HONBAKO_WORKSPACE.idFromName(id));
export const broker = env => env.HONBAKO_AUTH.get(env.HONBAKO_AUTH.idFromName('oauth-v1'));

/// Cloudflare's Rate Limiting bindings answer before any Durable Object runs, so a surge or a
/// looping token costs only Worker requests. A missing or failing binding falls through to the
/// objects' own in-memory limits. Both match the `ratelimits` periods in the wrangler configs.
const EDGE_PERIOD_SECONDS = 60;
async function edgeLimited(limiter, key) {
  if (typeof limiter?.limit !== 'function') return false;
  try { return (await limiter.limit({ key })).success === false; } catch { return false; }
}
const limited = () => failure(new BridgeError(429, 'rate_limited', 'Too many requests; retry later', { retryAfter: EDGE_PERIOD_SECONDS }));
/// A token's third part is its secret, so keys use a digest of it and never the token itself.
/// Its second part is the workspace, which every device and AI connection of a purchase shares.
const deviceKey = parts => `d:${parts[2]}:${digest(parts[3]).slice(0, 24)}`;
const clientAddress = request => `ip:${digest(request.headers.get('cf-connecting-ip') ?? 'unknown').slice(0, 24)}`;

export function enrollRemote(env, body, lease, base) {
  const auth = broker(env), rpc = name => async (...args) => unwrapRPC(await auth[name](...args));
  return routeEnrollment({ purchases: { find: rpc('workspaceFor'), bind: rpc('bind'), unbind: rpc('unbind'), forget: rpc('forget'), allocateFamily: rpc('allocate') },
    workspace: id => ({ enroll: async (...args) => unwrapRPC(await workspace(env, id).enroll(...args)), retire: async b => unwrapRPC(await workspace(env, id).retire(b)) }) }, body, lease, base);
}
export async function remoteFetch(request, env) {
  try {
    if (env.REMOTE_MCP_ENABLED !== 'YES' || !env.HONBAKO_WORKSPACE || !env.HONBAKO_AUTH || !/^[A-Za-z0-9_-]{43,100}$/.test(env.REMOTE_ROUTING_KEY ?? ''))
      return reply(503, { error: { code: 'remote_not_available', message: 'Automatic remote setup is not available yet' } });
    const base = remoteRequestBase(request, remoteBases(env.PUBLIC_ORIGIN, env.REMOTE_ORIGIN_ALIASES));
    const u = new URL(request.url), path = u.pathname;
    if (path === '/remote/capabilities' && request.method === 'GET') return reply(200, { available: Boolean(env.APP_STORE_PRIVATE_KEY && env.APP_STORE_KEY_ID && env.APP_STORE_ISSUER_ID) });
    if (path === '/.well-known/oauth-protected-resource/remote/mcp' && request.method === 'GET')
      return reply(200, { resource: `${base}/mcp`, authorization_servers: [base], scopes_supported: ['honbako'], bearer_methods_supported: ['header'] });
    if (['/.well-known/oauth-authorization-server/remote', '/remote/.well-known/oauth-authorization-server'].includes(path) && request.method === 'GET') return reply(200, discovery(base));
    if (path.startsWith('/remote/oauth/')) {
      const origin = request.headers.get('origin');
      if (origin && origin !== u.origin) throw new BridgeError(403, 'origin_rejected', 'Cross-origin browser requests are not supported');
      if (await edgeLimited(env.SETUP_RATE_LIMITER, clientAddress(request))) return limited();
      return broker(env).fetch(request);
    }
    if (request.headers.has('origin') || u.search) throw new BridgeError(403, 'origin_rejected', 'This route is for Honbako and authorized AI clients');
    if (path === '/remote/enroll' && request.method === 'POST') {
      if (await edgeLimited(env.SETUP_RATE_LIMITER, clientAddress(request))) return limited();
      unwrapRPC(await broker(env).enrollmentLimit(request.headers.get('cf-connecting-ip') ?? 'unknown'));
      const body = await readJson(request, 32768);
      if (!UUID.test(body.installationId ?? '') || !/^[A-Za-z0-9_-]{43}$/.test(body.deviceSecret ?? '')) throw new BridgeError(400, 'invalid_request', 'Private installation identity required');
      // Verify before allocating any per-user object. Invalid receipts cannot spawn tenants.
      const lease = await new AppleProVerifier(env).enroll(body.signedTransaction);
      return reply(200, await enrollRemote(env, body, lease, base));
    }
    const token = tokenFrom(request), parts = tokenParts(token);
    // A forged or junk token costs one HMAC check here and never reaches a Durable Object.
    if (!validRouteToken(token, env.REMOTE_ROUTING_KEY)) {
      const r = reply(401, { error: 'unauthorized' });
      if (path === '/remote/mcp') r.headers.set('www-authenticate', `Bearer resource_metadata="${u.origin}/.well-known/oauth-protected-resource/remote/mcp", scope="honbako"`);
      return r;
    }
    const device = path.startsWith('/remote/api/device/') && parts[1] === 'd', ai = path === '/remote/mcp' && parts[1] === 'a';
    if (!device && !ai) return reply(401, { error: 'unauthorized' });
    // Every AI connection of a workspace shares one limit, as in the workspace itself.
    if (device ? await edgeLimited(env.DEVICE_RATE_LIMITER, deviceKey(parts)) : await edgeLimited(env.AI_RATE_LIMITER, `a:${parts[2]}`)) return limited();
    if (path === '/remote/api/device/authorization' && request.method === 'POST') {
      const body = await readJson(request, 4096);
      if (!UUID.test(body.requestId ?? '') || (body.approved !== undefined && typeof body.approved !== 'boolean')) throw new BridgeError(400, 'invalid_request', 'Valid connection request required');
      return reply(200, unwrapRPC(await workspace(env, parts[2]).authorize(token, body.requestId, body.approved)));
    }
    return workspace(env, parts[2]).fetch(request);
  } catch (error) { return failure(error); }
}
