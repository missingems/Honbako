// Local-only workerd runtime for the remote Worker: no deploy, credentials or live pairing.
// Shared by integration-remote-workerd.js and surge-probe.js.
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { generateKeyPairSync, verify } from 'node:crypto';
export const root = path.resolve(fileURLToPath(new URL('..', import.meta.url)));

/// Builds the configured entry with fixture routes and returns a runtime that can be restarted
/// on the same storage. `rateLimits: false` leaves out the Rate Limiting bindings, as on an
/// account without them; `bindings` overrides variables such as the daily budget.
export async function remoteFixture({ configName = process.env.HONBAKO_REMOTE_RUNTIME_CONFIG ?? 'wrangler.remote.jsonc', rateLimits = true, bindings = {} } = {}) {
  const wranglerRoot = process.env.HONBAKO_WRANGLER_ROOT;
  if (!wranglerRoot) throw new Error('Set HONBAKO_WRANGLER_ROOT');
  const { Miniflare, Log, LogLevel, convertV4MiniflareOptions } = await import(pathToFileURL(path.resolve(wranglerRoot, '../miniflare/dist/src/index.js')).href);
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'honbako-remote-integration-'));
  const brandedOrigin = 'https://honbako-branded-integration.example', origin = 'https://honbako-integration.example', routingKey = 'K'.repeat(43);
  const fixtureKeys = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const fixtureSigningKey = fixtureKeys.privateKey.export({type:'pkcs8',format:'pem'});
  let appleOutboundRequests = 0;
  try {
    const config = JSON.parse(await fs.readFile(path.join(root, 'cloudflare', configName), 'utf8'));
    const productionEntry = config.main === 'worker.js';
    // This local-only entry supplies fixtures through account-owned RPC. It is never a deployed entrypoint.
    const entry = path.join(directory, 'fixture-entry.js');
    await fs.writeFile(entry, `import production from ${JSON.stringify(path.join(root, 'cloudflare', config.main))};\nexport {HonbakoAuthorization,HonbakoWorkspace${productionEntry ? ',HonbakoOwner' : ''}} from ${JSON.stringify(path.join(root, 'cloudflare', config.main))};\nimport {enrollRemote} from ${JSON.stringify(path.join(root, 'cloudflare/remote/worker.js'))};\nimport {AppleProVerifier} from ${JSON.stringify(path.join(root, 'cloudflare/remote/entitlement.js'))};\nimport {checkAppleConnection} from ${JSON.stringify(path.join(root, 'cloudflare/remote/apple-connection.js'))};\nimport legacyFetch from 'node-fetch';\nexport default {async fetch(request,env){const u=new URL(request.url);if(u.pathname==='/fixture/apple-connection'){const diagnostics=[];const result=await checkAppleConnection(env,e=>diagnostics.push({name:e.name,message:e.message}));return Response.json({...result,fixtureDiagnostics:diagnostics});}if(u.pathname==='/fixture/ocsp'){const r=await legacyFetch('http://ocsp.apple.com/fixture',{method:'POST',headers:{'content-type':'application/ocsp-request'},body:new Uint8Array([1,2])});return new Response(await r.buffer());}if(u.pathname==='/fixture/enroll'){const {purchase='fixture-purchase',...body}=await request.json();const now=Date.now();return Response.json(await enrollRemote(env,body,{originalTransactionId:'12345',purchaseHash:purchase,familyShared:false,expiresAt:now+86400000,leaseUntil:now+900000},u.origin+'/remote'));}if(u.pathname==='/fixture/apple'){try{const v=new AppleProVerifier({}, {api:{}});await v.enroll('x'.repeat(150));return new Response('unexpected', {status:500});}catch(e){return Response.json({status:e.status??500},{status:e.status??500});}}return production.fetch(request,env);}};`);
    config.main = entry;
    config.alias = Object.fromEntries(Object.entries(config.alias ?? {}).map(([key,value]) => [key,path.resolve(root,'cloudflare',value)]));
    const configPath = path.join(directory, 'wrangler.json'); await fs.writeFile(configPath, JSON.stringify(config));
    const built = spawnSync(process.execPath, [path.join(wranglerRoot, 'bin/wrangler.js'), 'deploy', '--dry-run', '--config', configPath, '--outdir', path.join(directory, 'bundle')], { cwd: root, env: { ...process.env, WRANGLER_SEND_METRICS: 'false' }, encoding: 'utf8' });
    assert.equal(built.status, 0, built.stderr || built.stdout);
    const script = await fs.readFile(path.join(directory, 'bundle/fixture-entry.js'), 'utf8');
    // The configured Rate Limiting bindings, as Miniflare's local fixed windows.
    const ratelimits = rateLimits ? Object.fromEntries((config.ratelimits ?? []).map(({ name, namespace_id, simple }) => [name, { namespace_id, simple }])) : {};
    const makeRuntime = () => {
      const options = convertV4MiniflareOptions({ log: new Log(LogLevel.ERROR), workers: [{ name: 'remote-fixture', modules: true, script,
        compatibilityDate: '2026-10-29', compatibilityFlags: ['nodejs_compat'], ratelimits, bindings: { PUBLIC_ORIGIN: origin, REMOTE_ORIGIN_ALIASES: [brandedOrigin], OWNER_NAME: 'pilot', ADMIN_KEY: 'A'.repeat(43), PAIRING_KEY: 'P'.repeat(43), REMOTE_MCP_ENABLED: 'YES', REMOTE_ROUTING_KEY: routingKey, APP_STORE_ENVIRONMENT: config.vars.APP_STORE_ENVIRONMENT, WORKSPACE_DAILY_REQUEST_BUDGET: config.vars.WORKSPACE_DAILY_REQUEST_BUDGET, APP_STORE_PRIVATE_KEY: fixtureSigningKey, APP_STORE_KEY_ID: 'F123456789', APP_STORE_ISSUER_ID: '00000000-0000-4000-8000-000000000000', ...bindings },
        outboundService: async request => {
          appleOutboundRequests++;
          const url = new URL(request.url);
          if (url.hostname === 'ocsp.apple.com' && url.pathname === '/fixture') {
            assert.equal(request.method,'POST');
            assert.equal(request.headers.get('content-type'),'application/ocsp-request');
            return new Response(new Uint8Array([0,1,2,255]));
          }
          assert.ok(['api.storekit.apple.com','api.storekit-sandbox.apple.com'].includes(url.hostname));
          assert.equal(url.pathname,'/inApps/v1/notifications/history');
          const token = request.headers.get('authorization').slice(7).split('.');
          assert.equal(verify('sha256',Buffer.from(`${token[0]}.${token[1]}`),{key:fixtureKeys.publicKey,dsaEncoding:'ieee-p1363'},Buffer.from(token[2],'base64url')),true);
          assert.equal(JSON.parse(Buffer.from(token[1],'base64url')).bid,'com.missingems.honbaku');
          assert.equal((await request.json()).notificationType,'TEST');
          if (url.hostname === 'api.storekit.apple.com') return new Response(null,{status:401});
          return Response.json({hasMore:false,notificationHistory:[]});
        },
        durableObjects: { ...(productionEntry ? { HONBAKO_OWNER: { className: 'HonbakoOwner', useSQLite: true } } : {}), HONBAKO_AUTH: { className: 'HonbakoAuthorization', useSQLite: true }, HONBAKO_WORKSPACE: { className: 'HonbakoWorkspace', useSQLite: true } } }] });
      options.resourcePersistencePath = path.join(directory, 'durable'); options.enableDevRegistry = false; options.telemetry = { enabled: false }; return new Miniflare(options);
    };
    const fixture = { origin, base: `${origin}/remote`, brandedOrigin, brandedBase: `${brandedOrigin}/remote`, routingKey, productionEntry, config, mf: null,
      get appleOutboundRequests() { return appleOutboundRequests; },
      /// Starts the runtime, or restarts it on the same storage.
      async start() { await fixture.mf?.dispose(); fixture.mf = makeRuntime(); await fixture.mf.ready; return fixture.mf; },
      jsonAt: (at, pathname, body, token, method='POST', headers={}) => fixture.mf.dispatchFetch(`${at}${pathname}`, { method, headers: { accept: 'application/json, text/event-stream', 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers }, ...(method === 'GET' ? {} : { body: JSON.stringify(body ?? {}) }) }),
      json: (...args) => fixture.jsonAt(origin, ...args),
      async close() { await fixture.mf?.dispose(); fixture.mf = null; await fs.rm(directory,{recursive:true,force:true}); } };
    return fixture;
  } catch (error) { await fs.rm(directory,{recursive:true,force:true}); throw error; }
}
