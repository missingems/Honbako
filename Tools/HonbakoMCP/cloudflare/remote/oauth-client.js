import { BridgeError, digest, secureEqual } from '../../src/store.js';
export const CLIENT_AUTH_METHODS = ['none', 'client_secret_post', 'client_secret_basic'];
const invalid = () => new BridgeError(401, 'invalid_client', 'Client authentication failed');

export function redirectAllowed(value) {
  if (typeof value !== 'string' || value.length >= 2048 || /[\u0000-\u0020\u007f*]/.test(value)) return false;
  try {
    const u = new URL(value);
    if (u.username || u.password || u.hash) return false;
    // Native OAuth clients may use an exact loopback callback (RFC 8252).
    // The registered port/path still match exactly at authorization and exchange.
    const loopback = ['127.0.0.1', '[::1]', 'localhost'].includes(u.hostname);
    if (u.protocol === 'http:') return loopback;
    return u.protocol === 'https:' && !u.hostname.endsWith('.local') && u.hostname.includes('.')
      && !/^[\d.:\[\]]+$/.test(u.hostname) && u.hostname !== 'localhost';
  } catch { return false; }
}

export function registrationMetadata(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new BridgeError(400, 'invalid_client_metadata', 'Registration metadata must be a JSON object');
  if (!Array.isArray(body.redirect_uris) || !body.redirect_uris.length || body.redirect_uris.length > 8 || !body.redirect_uris.every(redirectAllowed))
    throw new BridgeError(400, 'invalid_redirect_uri', 'Register exact HTTPS callback addresses, or exact HTTP callbacks on localhost, 127.0.0.1 or [::1]; wildcards, credentials and fragments are not allowed');
  const method = body.token_endpoint_auth_method ?? 'none';
  if (!CLIENT_AUTH_METHODS.includes(method)) throw new BridgeError(400, 'invalid_client_metadata', 'Use none, client_secret_post or client_secret_basic client authentication; S256 PKCE remains required');
  if (body.grant_types && (!Array.isArray(body.grant_types) || !body.grant_types.length || body.grant_types.some(x => !['authorization_code', 'refresh_token'].includes(x))))
    throw new BridgeError(400, 'invalid_client_metadata', 'Only authorization_code and refresh_token grants are supported');
  if (body.response_types && (!Array.isArray(body.response_types) || body.response_types.length !== 1 || body.response_types[0] !== 'code'))
    throw new BridgeError(400, 'invalid_client_metadata', 'Only the code response type is supported');
  return method;
}

export function authenticateClient(request, params, readClient) {
  const header = request.headers.get('authorization');
  let id = params.get('client_id'), provided = params.get('client_secret'), basic = false;
  if (header) {
    if (provided != null || header.length > 4096 || !/^Basic [A-Za-z0-9+/]+={0,2}$/.test(header)) throw invalid();
    const text = Buffer.from(header.slice(6), 'base64').toString('utf8'), colon = text.indexOf(':');
    if (colon < 1) throw invalid();
    try {
      const decode = s => decodeURIComponent(s.replace(/\+/g, ' '));
      const basicID = decode(text.slice(0, colon));
      if (id && id !== basicID) throw invalid();
      id = basicID; provided = decode(text.slice(colon + 1)); basic = true;
    } catch { throw invalid(); }
  }
  let client;
  try { client = readClient(id); } catch { throw invalid(); }
  const method = client.token_endpoint_auth_method ?? 'none';
  if (method === 'none') {
    if (header || provided != null) throw invalid();
  } else {
    if ((method === 'client_secret_basic') !== basic || !provided || provided.length > 256
        || !client.secretHash || !secureEqual(digest(provided), client.secretHash)) throw invalid();
  }
  return client;
}

// Temporary diagnosis includes only non-secret registration metadata. Never log
// a body, headers, client name, query values, credentials or issued client secrets.
export function registrationDiagnostic(body) {
  const callback = value => {
    if (typeof value !== 'string') return { malformed: true };
    try {
      const u = new URL(value);
      return { scheme: u.protocol, host: u.host,
        path: u.pathname.split('/').map(part => part.length > 40 ? '[redacted]' : part).join('/').slice(0, 200),
        hasQuery: Boolean(u.search), hasFragment: Boolean(u.hash), hasCredentials: Boolean(u.username || u.password) };
    } catch { return { malformed: true }; }
  };
  return { redirectURIs: Array.isArray(body?.redirect_uris) ? body.redirect_uris.slice(0, 8).map(callback) : 'missing_or_invalid',
    authMethod: typeof body?.token_endpoint_auth_method === 'string' && /^[a-z_]{1,40}$/.test(body.token_endpoint_auth_method) ? body.token_endpoint_auth_method : 'omitted_or_invalid',
    grantTypes: Array.isArray(body?.grant_types) ? body.grant_types.slice(0, 5).map(value => typeof value === 'string' && /^[a-z_]{1,40}$/.test(value) ? value : '[invalid]') : 'omitted' };
}
