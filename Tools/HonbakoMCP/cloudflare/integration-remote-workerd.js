#!/usr/bin/env node
// Local-only platform integration. No production deploy, credentials or live pairing.
import assert from 'node:assert/strict';
import { randomUUID, createHash } from 'node:crypto';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
import { remoteFixture } from './workerd-fixture.js';
let fixture, client;
try {
  fixture = await remoteFixture();
  const { origin, base, brandedOrigin, brandedBase, productionEntry, jsonAt, json } = fixture;
  let mf = await fixture.start();
  assert.equal((await json('/fixture/apple')).status, 402); // Actual Apple verifier imports and fails closed in workerd.
  const appleConnection = await (await json('/fixture/apple-connection')).json();
  assert.equal(appleConnection.sandbox.authenticated,true,JSON.stringify(appleConnection));
  assert.equal(appleConnection.production.httpStatus,401);
  const ocsp = await json('/fixture/ocsp'); assert.deepEqual(Buffer.from(await ocsp.arrayBuffer()),Buffer.from([0,1,2,255]));
  assert.equal(fixture.appleOutboundRequests,3);
  assert.equal((await mf.dispatchFetch(`${origin}/api/admin/status`)).status,404);
  assert.equal((await mf.dispatchFetch(`${origin}/mcp`)).status,productionEntry ? 405 : 404);
  assert.equal((await mf.dispatchFetch(`${base}/capabilities`)).status,200);
  const one = { installationId: randomUUID(), deviceSecret: 'S'.repeat(43), name: 'Fixture one' };
  const two = { installationId: randomUUID(), deviceSecret: 'T'.repeat(43), name: 'Fixture two', purchase: 'fixture-other-purchase' };
  const three = { installationId: randomUUID(), deviceSecret: 'U'.repeat(43), name: 'Fixture iPad' };
  const phone = await (await json('/fixture/enroll', one)).json(), other = await (await json('/fixture/enroll', two)).json();
  assert.ok(phone.deviceToken, JSON.stringify(phone));
  assert.notEqual(other.workspaceId, phone.workspaceId);
  // A second device proving the same purchase joins the first one's workspace.
  const pad = await (await json('/fixture/enroll', three)).json();
  assert.deepEqual([pad.workspaceId, pad.deviceId, pad.joinedOtherDevices], [phone.deviceId, three.installationId, true]);
  const shared = await (await json('/remote/api/device/jobs', undefined, pad.deviceToken, 'GET')).json();
  assert.deepEqual(shared.workspace.devices.map(d => d.name).sort(), ['Fixture iPad', 'Fixture one']);
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
    assert.equal((await client.listTools()).tools.length,14);
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
  mf = await fixture.start();
  assert.equal((await aliasTools()).status,200);
  await connect(tokens.access_token); await client.close(); client=null;
  const refreshed = await (await exchange({grant_type:'refresh_token',refresh_token:tokens.refresh_token,client_id:registration.client_id,resource:`${base}/mcp`})).json(); assert.ok(refreshed.access_token);
  assert.equal((await exchange({grant_type:'refresh_token',refresh_token:tokens.refresh_token,client_id:registration.client_id,resource:`${base}/mcp`})).status,400);
  // Turning off one device leaves the AI connection with the other; the last one ends it.
  assert.equal((await json('/remote/api/device/disconnect',{},pad.deviceToken)).status,200);
  assert.equal((await json('/remote/api/device/jobs',undefined,pad.deviceToken,'GET')).status,401);
  assert.equal((await aliasTools()).status,200);
  assert.equal((await json('/remote/api/device/disconnect',{},phone.deviceToken)).status,200);
  assert.equal((await json('/remote/mcp',{jsonrpc:'2.0',id:1,method:'tools/list'},refreshed.access_token)).status,401);
  assert.equal((await aliasTools()).status,401);
  process.stdout.write(JSON.stringify({originAliases:true,issuerIsolation:true,aliasPersistence:true,runtime:'workerd',entry:productionEntry?'production':'sandbox',deployed:false,fixtureOnly:true,appleLibraryLoads:true,appleOutboundTransport:true,ocspBinaryTransport:true,invalidAppleProofRejected:true,oauthConsent:true,pkce:true,refreshRotation:true,tenantIsolation:true,tools:14,historyJobs:true,sourceApproval:true,persistenceRestart:true,sharedWorkspace:true,disconnectRevokes:true})+'\n');
} finally { await client?.close().catch(()=>{}); await fixture?.close(); }
