#!/usr/bin/env node
// Local-only platform integration. No production deploy, credentials or live pairing.
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { randomUUID, createHash, generateKeyPairSync, verify } from 'node:crypto';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
const root = path.resolve(fileURLToPath(new URL('..', import.meta.url)));
const wranglerRoot = process.env.HONBAKO_WRANGLER_ROOT;
if (!wranglerRoot) throw new Error('Set HONBAKO_WRANGLER_ROOT');
const { Miniflare, Log, LogLevel, convertV4MiniflareOptions } = await import(pathToFileURL(path.resolve(wranglerRoot, '../miniflare/dist/src/index.js')).href);
const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'honbako-remote-integration-'));
const brandedOrigin = 'https://honbako-branded-integration.example', brandedBase = `${brandedOrigin}/remote`;
const origin = 'https://honbako-integration.example', base = `${origin}/remote`, routingKey = 'K'.repeat(43);
let mf, client;
const fixtureKeys = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const fixtureSigningKey = fixtureKeys.privateKey.export({type:'pkcs8',format:'pem'});
let appleOutboundRequests = 0;
try {
  const config = JSON.parse(await fs.readFile(path.join(root, 'cloudflare', process.env.HONBAKO_REMOTE_RUNTIME_CONFIG ?? 'wrangler.remote.jsonc'), 'utf8'));
  const productionEntry = config.main === 'worker.js';
  // This local-only entry supplies fixtures through account-owned RPC. It is never a deployed entrypoint.
  const entry = path.join(directory, 'fixture-entry.js');
  await fs.writeFile(entry, `import production from ${JSON.stringify(path.join(root, 'cloudflare', config.main))};\nexport {HonbakoAuthorization,HonbakoWorkspace${productionEntry ? ',HonbakoOwner' : ''}} from ${JSON.stringify(path.join(root, 'cloudflare', config.main))};\nimport {unwrapRPC} from ${JSON.stringify(path.join(root, 'cloudflare/remote/rpc.js'))};\nimport {AppleProVerifier} from ${JSON.stringify(path.join(root, 'cloudflare/remote/entitlement.js'))};\nimport {checkAppleConnection} from ${JSON.stringify(path.join(root, 'cloudflare/remote/apple-connection.js'))};\nimport legacyFetch from 'node-fetch';\nexport default {async fetch(request,env){const u=new URL(request.url);if(u.pathname==='/fixture/apple-connection'){const diagnostics=[];const result=await checkAppleConnection(env,e=>diagnostics.push({name:e.name,message:e.message}));return Response.json({...result,fixtureDiagnostics:diagnostics});}if(u.pathname==='/fixture/ocsp'){const r=await legacyFetch('http://ocsp.apple.com/fixture',{method:'POST',headers:{'content-type':'application/ocsp-request'},body:new Uint8Array([1,2])});return new Response(await r.buffer());}if(u.pathname==='/fixture/enroll'){const body=await request.json();const now=Date.now();return Response.json(unwrapRPC(await env.HONBAKO_WORKSPACE.get(env.HONBAKO_WORKSPACE.idFromName(body.installationId)).enroll(body,{originalTransactionId:'12345',purchaseHash:'fixture-purchase',expiresAt:now+86400000,leaseUntil:now+900000},u.origin+'/remote')));}if(u.pathname==='/fixture/apple'){try{const v=new AppleProVerifier({}, {api:{}});await v.enroll('x'.repeat(150));return new Response('unexpected', {status:500});}catch(e){return Response.json({status:e.status??500},{status:e.status??500});}}return production.fetch(request,env);}};`);
  config.main = entry;
  config.alias = Object.fromEntries(Object.entries(config.alias ?? {}).map(([key,value]) => [key,path.resolve(root,'cloudflare',value)]));
  const configPath = path.join(directory, 'wrangler.json'); await fs.writeFile(configPath, JSON.stringify(config));
  const built = spawnSync(process.execPath, [path.join(wranglerRoot, 'bin/wrangler.js'), 'deploy', '--dry-run', '--config', configPath, '--outdir', path.join(directory, 'bundle')], { cwd: root, env: { ...process.env, WRANGLER_SEND_METRICS: 'false' }, encoding: 'utf8' });
  assert.equal(built.status, 0, built.stderr || built.stdout);
  const script = await fs.readFile(path.join(directory, 'bundle/fixture-entry.js'), 'utf8');
  const makeRuntime = () => {
    const options = convertV4MiniflareOptions({ log: new Log(LogLevel.ERROR), workers: [{ name: 'remote-fixture', modules: true, script,
      compatibilityDate: '2026-10-29', compatibilityFlags: ['nodejs_compat'], bindings: { PUBLIC_ORIGIN: origin, REMOTE_ORIGIN_ALIASES: [brandedOrigin], OWNER_NAME: 'pilot', ADMIN_KEY: 'A'.repeat(43), PAIRING_KEY: 'P'.repeat(43), REMOTE_MCP_ENABLED: 'YES', REMOTE_ROUTING_KEY: routingKey, APP_STORE_ENVIRONMENT: config.vars.APP_STORE_ENVIRONMENT, APP_STORE_PRIVATE_KEY: fixtureSigningKey, APP_STORE_KEY_ID: 'F123456789', APP_STORE_ISSUER_ID: '00000000-0000-4000-8000-000000000000' },
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
  mf = makeRuntime(); await mf.ready;
  const jsonAt = (at, pathname, body, token, method='POST') => mf.dispatchFetch(`${at}${pathname}`, { method, headers: { accept: 'application/json, text/event-stream', 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, ...(method === 'GET' ? {} : { body: JSON.stringify(body ?? {}) }) });
  const json = (...args) => jsonAt(origin, ...args);
  assert.equal((await json('/fixture/apple')).status, 402); // Actual Apple verifier imports and fails closed in workerd.
  const appleConnection = await (await json('/fixture/apple-connection')).json();
  assert.equal(appleConnection.sandbox.authenticated,true,JSON.stringify(appleConnection));
  assert.equal(appleConnection.production.httpStatus,401);
  const ocsp = await json('/fixture/ocsp'); assert.deepEqual(Buffer.from(await ocsp.arrayBuffer()),Buffer.from([0,1,2,255]));
  assert.equal(appleOutboundRequests,3);
  assert.equal((await mf.dispatchFetch(`${origin}/api/admin/status`)).status,404);
  assert.equal((await mf.dispatchFetch(`${origin}/mcp`)).status,productionEntry ? 405 : 404);
  assert.equal((await mf.dispatchFetch(`${base}/capabilities`)).status,200);
  const one = { installationId: randomUUID(), deviceSecret: 'S'.repeat(43), name: 'Fixture one' };
  const two = { installationId: randomUUID(), deviceSecret: 'T'.repeat(43), name: 'Fixture two' };
  const phone = await (await json('/fixture/enroll', one)).json(), other = await (await json('/fixture/enroll', two)).json();
  assert.ok(phone.deviceToken, JSON.stringify(phone));
  assert.equal((await json('/remote/api/device/state', { schemaVersion: 1, generatedAt: new Date().toISOString(), library: [{sourceId:'owned',mangaId:'original',title:'Owned Original'}], sources: [], readingHistoryAccess:true, automationCapabilities:['reading.history','sources.manage'] }, phone.deviceToken)).status, 200);
  const unauthorized = await json('/remote/mcp', {jsonrpc:'2.0',id:1,method:'tools/list'}); assert.equal(unauthorized.status, 401); assert.ok(unauthorized.headers.get('www-authenticate').includes('oauth-protected-resource'));
  assert.equal((await mf.dispatchFetch(`${origin}/.well-known/oauth-protected-resource/remote/mcp`)).status, 200);
  const metadata = await (await mf.dispatchFetch(`${origin}/.well-known/oauth-authorization-server/remote`)).json(); assert.equal(metadata.issuer, base);
  const registration = await (await json('/remote/oauth/register', { redirect_uris: ['https://ai.example/callback'], client_name:'Fixture AI' })).json();
  const verifier = 'V'.repeat(43), challenge = createHash('sha256').update(verifier).digest('base64url');
  const params = new URLSearchParams({client_id:registration.client_id,redirect_uri:'https://ai.example/callback',response_type:'code',scope:'honbako',resource:`${base}/mcp`,code_challenge_method:'S256',code_challenge:challenge,state:'fixture-state'});
  const consent = await mf.dispatchFetch(`${base}/oauth/authorize?${params}`), html = await consent.text(); assert.equal(consent.status, 200, html);
  const requestId = /honbako:\/\/mcp-authorize\?request=([0-9a-f-]+)/.exec(html)[1], cookie = consent.headers.get('set-cookie').split(';')[0];
  const pending = await (await json('/remote/api/device/authorization', { requestId }, phone.deviceToken)).json(); assert.equal(pending.clientName, 'Fixture AI');
  assert.equal((await json('/remote/api/device/authorization', { requestId, approved:true }, phone.deviceToken)).status, 200);
  const finished = await (await mf.dispatchFetch(`${base}/oauth/result?request=${requestId}`, {headers:{cookie}})).json();
  const callback = new URL(finished.redirect); assert.equal(callback.searchParams.get('state'), 'fixture-state');
  const tokenBody = { grant_type:'authorization_code',client_id:registration.client_id,redirect_uri:'https://ai.example/callback',resource:`${base}/mcp`,code_verifier:verifier,code:callback.searchParams.get('code') };
  const exchange = body => mf.dispatchFetch(`${base}/oauth/token`, {method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams(body).toString()});
  const tokensResponse = await exchange(tokenBody), tokens = await tokensResponse.json(); assert.equal(tokensResponse.status, 200, JSON.stringify(tokens));
  assert.equal((await exchange(tokenBody)).status, 400);
  // Alias routing reaches the same Durable Objects, but OAuth identities keep exact issuers.
  const aliasPhone = await (await jsonAt(brandedOrigin,'/fixture/enroll',one)).json();
  assert.equal(aliasPhone.deviceId,phone.deviceId); assert.equal(aliasPhone.deviceToken,phone.deviceToken); assert.equal(aliasPhone.endpoint,brandedBase);
  const aliasMetadata = await (await mf.dispatchFetch(`${brandedOrigin}/.well-known/oauth-authorization-server/remote`)).json();
  assert.equal(aliasMetadata.issuer,brandedBase); assert.equal(aliasMetadata.token_endpoint,`${brandedBase}/oauth/token`);
  const aliasResource = await (await mf.dispatchFetch(`${brandedOrigin}/.well-known/oauth-protected-resource/remote/mcp`)).json();
  assert.equal(aliasResource.resource,`${brandedBase}/mcp`); assert.deepEqual(aliasResource.authorization_servers,[brandedBase]);
  assert.equal((await mf.dispatchFetch('https://unconfigured.example/remote/capabilities')).status,403);
  assert.equal((await mf.dispatchFetch(`${brandedBase}/oauth/register`,{method:'POST',headers:{origin, 'content-type':'application/json'},body:'{}'})).status,403);
  assert.equal((await jsonAt(brandedOrigin,'/remote/api/device/jobs',undefined,phone.deviceToken,'GET')).status,200);
  const aliasDenied = await jsonAt(brandedOrigin,'/remote/mcp',{jsonrpc:'2.0',id:1,method:'tools/list'},tokens.access_token);
  assert.equal(aliasDenied.status,401); assert.ok(aliasDenied.headers.get('www-authenticate').includes(brandedOrigin));
  const aliasRegistration = await (await jsonAt(brandedOrigin,'/remote/oauth/register',{redirect_uris:['https://ai.example/callback'],client_name:'Branded AI'})).json();
  const aliasParams = new URLSearchParams({...Object.fromEntries(params),client_id:aliasRegistration.client_id,resource:`${brandedBase}/mcp`});
  const aliasConsent = await mf.dispatchFetch(`${brandedBase}/oauth/authorize?${aliasParams}`), aliasHtml = await aliasConsent.text();
  assert.equal(aliasConsent.status,200,aliasHtml); assert.ok(aliasHtml.includes(`${brandedBase}/oauth/result`));
  const aliasRequestId = /honbako:\/\/mcp-authorize\?request=([0-9a-f-]+)/.exec(aliasHtml)[1], aliasCookie = aliasConsent.headers.get('set-cookie').split(';')[0];
  assert.equal((await json('/remote/api/device/authorization',{requestId:aliasRequestId,approved:true},phone.deviceToken)).status,200);
  assert.equal((await mf.dispatchFetch(`${base}/oauth/result?request=${aliasRequestId}`,{headers:{cookie:aliasCookie}})).status,400);
  const aliasFinished = await (await mf.dispatchFetch(`${brandedBase}/oauth/result?request=${aliasRequestId}`,{headers:{cookie:aliasCookie}})).json();
  const aliasExchange = body => mf.dispatchFetch(`${brandedBase}/oauth/token`,{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams(body).toString()});
  const aliasTokensResponse = await aliasExchange({...tokenBody,client_id:aliasRegistration.client_id,resource:`${brandedBase}/mcp`,code:new URL(aliasFinished.redirect).searchParams.get('code')});
  const aliasTokens = await aliasTokensResponse.json(); assert.equal(aliasTokensResponse.status,200,JSON.stringify(aliasTokens));
  const aliasTools = () => jsonAt(brandedOrigin,'/remote/mcp',{jsonrpc:'2.0',id:1,method:'tools/list'},aliasTokens.access_token);
  assert.equal((await aliasTools()).status,200);
  assert.equal((await json('/remote/mcp',{jsonrpc:'2.0',id:1,method:'tools/list'},aliasTokens.access_token)).status,401);
  assert.equal((await aliasExchange({grant_type:'refresh_token',client_id:registration.client_id,resource:`${brandedBase}/mcp`,refresh_token:tokens.refresh_token})).status,401);
  if (productionEntry) assert.equal((await jsonAt(brandedOrigin,'/api/pair',{code:'invalid',name:'No pilot on alias'})).status,403);
  const connect = async token => {
    client = new Client({name:'remote-fixture',version:'1'});
    await client.connect(new StreamableHTTPClientTransport(new URL(`${base}/mcp`), {requestInit:{headers:{authorization:`Bearer ${token}`}},fetch:(url,init)=>mf.dispatchFetch(String(url),{...init,headers:Object.fromEntries(new Headers(init?.headers))})}));
    assert.equal((await client.listTools()).tools.length,13);
    const library = await client.callTool({name:'honbako_search_library',arguments:{query:'Owned'}}); assert.equal(library.structuredContent.matches[0].title,'Owned Original');
    const history = await client.callTool({name:'honbako_get_reading_history',arguments:{limit:100}});
    assert.equal(history.structuredContent.kind,'history.read');
    const historyJob = history.structuredContent;
    const historyResult = {entries:[{sourceId:'gone',mangaId:'outside-library',chapterId:'one',title:'Saved history',chapterTitle:'One',completed:true,readAt:new Date().toISOString()}],nextOffset:null,before:historyJob.payload.before,observedAt:new Date().toISOString(),coverage:'saved_chapter_history',excludedRecords:0};
    assert.equal((await json(`/remote/api/device/jobs/${historyJob.id}/status`,{status:'completed',result:historyResult},phone.deviceToken)).status,200);
    const read = await client.callTool({name:'honbako_get_job',arguments:{jobId:historyJob.id}}); assert.equal(read.structuredContent.result.entries[0].mangaId,'outside-library');
    const source = await client.callTool({name:'honbako_manage_sources',arguments:{change:{action:'refresh_repositories'},idempotencyKey:'refresh-fixture'}});
    assert.equal(source.structuredContent.kind,'sources.change');
    if(source.structuredContent.status !== 'completed') {
      const result={change:{action:'refresh_repositories'},applied:true,observedAt:new Date().toISOString()};
      assert.equal((await json(`/remote/api/device/jobs/${source.structuredContent.id}/status`,{status:'completed',result},phone.deviceToken)).status,409);
      assert.equal((await json(`/remote/api/device/jobs/${source.structuredContent.id}/status`,{status:'awaitingApproval',approvalGranted:true},phone.deviceToken)).status,200);
      assert.equal((await json(`/remote/api/device/jobs/${source.structuredContent.id}/status`,{status:'completed',result},phone.deviceToken)).status,200);
    }
    const foreign = await client.callTool({name:'honbako_get_reading_context',arguments:{deviceId:other.deviceId}}); assert.equal(foreign.isError,true);
  };
  await connect(tokens.access_token); await client.close(); client=null;
  await mf.dispose(); mf=makeRuntime(); await mf.ready;
  assert.equal((await aliasTools()).status,200);
  await connect(tokens.access_token); await client.close(); client=null;
  const refreshed = await (await exchange({grant_type:'refresh_token',refresh_token:tokens.refresh_token,client_id:registration.client_id,resource:`${base}/mcp`})).json(); assert.ok(refreshed.access_token);
  assert.equal((await exchange({grant_type:'refresh_token',refresh_token:tokens.refresh_token,client_id:registration.client_id,resource:`${base}/mcp`})).status,400);
  assert.equal((await json('/remote/api/device/disconnect',{},phone.deviceToken)).status,200);
  assert.equal((await json('/remote/mcp',{jsonrpc:'2.0',id:1,method:'tools/list'},refreshed.access_token)).status,401);
  assert.equal((await aliasTools()).status,401);
  process.stdout.write(JSON.stringify({originAliases:true,issuerIsolation:true,aliasPersistence:true,runtime:'workerd',entry:productionEntry?'production':'sandbox',deployed:false,fixtureOnly:true,appleLibraryLoads:true,appleOutboundTransport:true,ocspBinaryTransport:true,invalidAppleProofRejected:true,oauthConsent:true,pkce:true,refreshRotation:true,tenantIsolation:true,tools:13,historyJobs:true,sourceApproval:true,persistenceRestart:true,disconnectRevokes:true})+'\n');
} finally { await client?.close().catch(()=>{}); await mf?.dispose(); await fs.rm(directory,{recursive:true,force:true}); }
