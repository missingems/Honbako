import { randomBytes, createHash, createHmac } from 'node:crypto';
import { BridgeError, digest, secureEqual } from '../../src/store.js';
import { reply, readJson, boundedBytes } from '../core.js';
import { remoteBases, remoteRequestBase } from './origins.js';
import { CLIENT_AUTH_METHODS, redirectAllowed, registrationMetadata, authenticateClient, registrationDiagnostic } from './oauth-client.js';
export { redirectAllowed } from './oauth-client.js';
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
export const secret = () => randomBytes(32).toString('base64url');
export const tokenParts = value => /^(d|a|r)_([0-9a-f-]{36})_([A-Za-z0-9_-]{43})_([A-Za-z0-9_-]{16})$/.exec(value ?? '');
export function routedToken(role, id, key, value = secret()) {
  const raw = `${role}_${id}_${value}`;
  return `${raw}_${createHmac('sha256', key).update(raw).digest().subarray(0, 12).toString('base64url')}`;
}
export function validRouteToken(token, key) {
  const p = tokenParts(token);
  return Boolean(p && UUID.test(p[2]) && secureEqual(token, routedToken(p[1], p[2], key, p[3])));
}
export const tokenFrom = request => /^Bearer ([A-Za-z0-9_-]{43,200})$/.exec(request.headers.get('authorization') ?? '')?.[1];
const bad = message => new BridgeError(400, 'invalid_request', message);
const grant = message => new BridgeError(400, 'invalid_grant', message);
const REGISTRATION_MS = 30 * 86400000;
// RFC 8707: an omitted resource means this server's only protected resource.
const audience = (value, base) => [null, '', `${base}/mcp`, `${base}/mcp/`].includes(value);
const pkce = value => /^[A-Za-z0-9_-]{43}$/.test(value ?? '');
const verifierValid = value => /^[A-Za-z0-9._~-]{43,128}$/.test(value ?? '');
const cookieName = '__Host-honbako-oauth';
export function discovery(base) {
  return { issuer: base, authorization_endpoint: `${base}/oauth/authorize`, token_endpoint: `${base}/oauth/token`,
    registration_endpoint: `${base}/oauth/register`, revocation_endpoint: `${base}/oauth/revoke`,
    response_types_supported: ['code'], grant_types_supported: ['authorization_code', 'refresh_token'],
    token_endpoint_auth_methods_supported: CLIENT_AUTH_METHODS, code_challenge_methods_supported: ['S256'], scopes_supported: ['honbako'] };
}
const pageHeaders = { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'referrer-policy': 'no-referrer',
  'x-content-type-options': 'nosniff', 'x-frame-options': 'DENY' };
function authorizationPage(id, base, nonce) {
  // Client-controlled names and redirect URIs are displayed only by native SwiftUI Text.
  const link = `honbako://mcp-authorize?request=${id}`;
  const html = `<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Connect Honbako</title><style>body{font:17px system-ui;margin:12vh auto;padding:24px;max-width:480px;color-scheme:light dark}a{display:block;padding:16px;background:#1675e8;color:white;border-radius:16px;text-align:center;text-decoration:none}p{line-height:1.6}</style><h1>Connect your AI</h1><p>Open Honbako on your iPhone and approve this connection. Your library stays private until you approve.</p><a href="${link}">Open Honbako</a><p>If you are on another device, send the Open Honbako link to your iPhone. Keep this browser tab open.</p><p id="status">Waiting for your approval…</p><script nonce="${nonce}">const poll=async()=>{try{const r=await fetch(${JSON.stringify(`${base}/oauth/result?request=${id}`)},{credentials:'same-origin'});const v=await r.json();if(v.redirect){location.replace(v.redirect);return;}if(!r.ok){document.getElementById('status').textContent='This request expired. Start connecting again from your AI.';return;}}catch{}setTimeout(poll,2000)};poll();</script></html>`;
  return new Response(html, { headers: { ...pageHeaders, 'content-security-policy': `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'` } });
}
export class OAuthBroker {
  constructor(records, { base, aliases = [], workspace, routeKey, clock = Date.now, onRegistration }) {
    this.bases = remoteBases(new URL(base).origin, aliases);
    if (!this.bases.includes(base)) throw bad('Use the configured Honbako issuer');
    this.records = records; this.base = base; this.workspace = workspace; this.clock = clock; this.routeKey = routeKey; this.onRegistration = onRegistration;
  }
  read(key) {
    const record = this.records.get(key);
    if (!record || record.until <= this.clock()) throw bad('This connection request expired; start again in your AI');
    return record;
  }
  scopedRead(key, base) {
    const record = this.read(key);
    // Missing issuer identifies a pre-migration record; it stays on the legacy host.
    if ((record.issuer ?? this.base) !== base) throw bad('Use the issuer that started this connection');
    return record;
  }
  async fetch(request) {
    // Request-local context: Durable Objects may interleave requests across awaits.
    const base = remoteRequestBase(request, this.bases);
    const url = new URL(request.url), prefix = new URL(base).pathname;
    const path = url.pathname.startsWith(`${prefix}/`) ? url.pathname.slice(prefix.length) : '';
    this.records.purge(this.clock());
    if (path === '/oauth/register' && request.method === 'POST') {
      const body = await readJson(request, 8192);
      this.onRegistration?.(registrationDiagnostic(body));
      const method = registrationMetadata(body);
      const client_id = crypto.randomUUID(), clientSecret = method === 'none' ? null : secret();
      const value = { issuer: base, client_id, redirect_uris: [...new Set(body.redirect_uris)], client_name: typeof body.client_name === 'string' ? body.client_name.slice(0, 80) : 'Your AI',
        token_endpoint_auth_method: method, ...(clientSecret ? { secretHash: digest(clientSecret) } : {}), until: this.clock() + REGISTRATION_MS };
      this.records.set(`client:${client_id}`, value);
      return reply(201, { client_id, redirect_uris: value.redirect_uris, client_name: value.client_name,
        client_id_issued_at: Math.floor(this.clock() / 1000),
        ...(clientSecret ? { client_secret: clientSecret, client_secret_expires_at: Math.floor(value.until / 1000) } : {}),
        token_endpoint_auth_method: method, grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'] });
    }
    if (path === '/oauth/authorize' && request.method === 'GET') {
      const p = url.searchParams;
      for (const key of p.keys()) if (p.getAll(key).length !== 1) throw bad('Duplicate authorization parameters');
      const client = this.scopedRead(`client:${p.get('client_id')}`, base);
      if (p.get('response_type') !== 'code' || !client.redirect_uris.includes(p.get('redirect_uri'))
          || !audience(p.get('resource'), base) || (p.get('scope') || 'honbako') !== 'honbako'
          || p.get('code_challenge_method') !== 'S256' || !pkce(p.get('code_challenge')) || (p.get('state')?.length ?? 0) > 2048) throw bad('Use the registered callback, Honbako resource and S256 PKCE');
      const id = crypto.randomUUID(), browser = secret();
      this.records.set(`pending:${id}`, { issuer: base, clientId: client.client_id, name: client.client_name, redirect: p.get('redirect_uri'), state: p.get('state'),
        challenge: p.get('code_challenge'), browserHash: digest(browser), until: this.clock() + 5 * 60000 });
      const response = authorizationPage(id, base, secret());
      response.headers.set('set-cookie', `${cookieName}=${browser}; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=300`);
      return response;
    }
    if (path === '/oauth/result' && request.method === 'GET') {
      const id = url.searchParams.get('request'), pending = this.scopedRead(`pending:${id}`, base);
      const browser = request.headers.get('cookie')?.split(';').map(x => x.trim()).find(x => x.startsWith(`${cookieName}=`))?.slice(cookieName.length + 1) ?? '';
      if (!secureEqual(digest(browser), pending.browserHash)) throw new BridgeError(401, 'unauthorized', 'Use the browser that started this connection');
      if (!pending.approved && !pending.denied) return reply(200, { waiting: true });
      const redirect = new URL(pending.redirect);
      if (pending.denied) redirect.searchParams.set('error', 'access_denied');
      else {
        const code = secret();
        this.records.set(`code:${digest(code)}`, { ...pending, until: this.clock() + 60000 });
        redirect.searchParams.set('code', code);
      }
      if (pending.state !== null) redirect.searchParams.set('state', pending.state);
      this.records.delete(`pending:${id}`);
      return reply(200, { redirect: redirect.href });
    }
    if (path === '/oauth/token' && request.method === 'POST') {
      const content = request.headers.get('content-type') ?? '';
      if (!content.startsWith('application/x-www-form-urlencoded')) throw bad('Use form-encoded OAuth parameters');
      const bytes = await boundedBytes(request.body, 8192);
      const p = new URLSearchParams(new TextDecoder().decode(bytes));
      for (const key of p.keys()) if (p.getAll(key).length !== 1) throw bad('Duplicate token parameters');
      const client = authenticateClient(request, p, id => this.scopedRead(`client:${id}`, base));
      if (!audience(p.get('resource'), base)) throw bad('The token audience must be Honbako');
      let issued;
      if (p.get('grant_type') === 'refresh_token') {
        const token = p.get('refresh_token'), parts = tokenParts(token);
        if (!parts || parts[1] !== 'r' || !validRouteToken(token, this.routeKey)) throw grant('Invalid refresh token');
        issued = await this.grantFrom(() => this.workspace(parts[2]).refresh(token, client.client_id, base));
      } else {
        if (p.get('grant_type') !== 'authorization_code') throw new BridgeError(400, 'unsupported_grant_type', 'Use authorization_code or refresh_token');
        if (!verifierValid(p.get('code_verifier'))) throw bad('Authorization code and PKCE verifier required');
        const key = `code:${digest(p.get('code') ?? '')}`;
        let code;
        try { code = this.scopedRead(key, base); } catch { throw grant('Invalid authorization code'); }
        // A code is single-use, even after a failed verifier attempt.
        this.records.delete(key);
        const challenge = createHash('sha256').update(p.get('code_verifier')).digest('base64url');
        if (!secureEqual(challenge, code.challenge) || code.clientId !== client.client_id || code.redirect !== p.get('redirect_uri')) throw grant('Invalid authorization code');
        issued = await this.grantFrom(() => this.workspace(code.workspaceId).issue(code.clientId, base));
      }
      // A registration in use slides its 30-day window; idle registrations still expire.
      this.records.set(`client:${client.client_id}`, { ...client, until: this.clock() + REGISTRATION_MS });
      return reply(200, issued);
    }
    if (path === '/oauth/revoke' && request.method === 'POST') {
      if (!(request.headers.get('content-type') ?? '').startsWith('application/x-www-form-urlencoded')) throw bad('Use form-encoded OAuth parameters');
      const p = new URLSearchParams(new TextDecoder().decode(await boundedBytes(request.body, 8192)));
      for (const key of p.keys()) if (p.getAll(key).length !== 1) throw bad('Duplicate revocation parameters');
      const client = authenticateClient(request, p, id => this.scopedRead(`client:${id}`, base));
      const token = p.get('token'), parts = tokenParts(token);
      if (parts && validRouteToken(token, this.routeKey) && ['a', 'r'].includes(parts[1])) await this.workspace(parts[2]).revoke(token, client.client_id, base);
      return reply(200, {});
    }
    return reply(404, { error: 'not_found' });
  }
  async grantFrom(action) {
    // A lapsed subscription or disconnected phone ends the grant (RFC 6749 5.2);
    // temporary Apple outages keep their own status so clients may retry.
    try { return await action(); } catch (e) {
      if (e instanceof BridgeError && (e.code === 'pro_required' || e.code === 'unauthorized')) throw grant(e.message);
      throw e;
    }
  }
  pending(id) {
    if (!UUID.test(id ?? '')) throw bad('Invalid authorization request');
    const p = this.read(`pending:${id}`);
    if (p.approved || p.denied) throw bad('This request has already been answered');
    return { id, clientName: p.name, callbackHost: new URL(p.redirect).host, expiresAt: new Date(p.until).toISOString() };
  }
  approve(id, workspaceId, approved) {
    const key = `pending:${id}`, p = this.read(key);
    if (p.approved || p.denied) throw bad('This request has already been answered');
    this.records.set(key, { ...p, workspaceId: approved ? workspaceId : undefined, approved, denied: !approved });
    return { approved };
  }
}
