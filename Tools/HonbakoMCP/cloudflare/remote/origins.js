import { BridgeError } from '../../src/store.js';

const rejected = () => new BridgeError(403, 'host_rejected', 'Use the configured Honbako HTTPS server');

// Aliases share one environment's storage, never another environment's keys or tenants.
// PUBLIC_ORIGIN remains the legacy issuer for records created before alias support.
export function remoteBases(primaryOrigin, aliases = []) {
  if (!Array.isArray(aliases) || aliases.length > 8) throw rejected();
  return [...new Set([primaryOrigin, ...aliases])].map(origin => {
    let url;
    try { url = new URL(origin); } catch { throw rejected(); }
    if (typeof origin !== 'string' || /[\s*]/.test(origin) || url.protocol !== 'https:' || url.origin !== origin || url.username || url.password) throw rejected();
    return `${origin}/remote`;
  });
}

export function remoteRequestBase(request, bases) {
  const url = new URL(request.url);
  const base = bases.find(value => new URL(value).origin === url.origin);
  if (!base || url.protocol !== 'https:' || url.username || url.password || url.hash || url.pathname.includes('%')) throw rejected();
  return base;
}

export function requireRemoteBase(base, bases) {
  if (!bases.includes(base)) throw rejected();
  return base;
}
