import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {registrationDiagnostic} from '../remote/oauth-client.js';
import {OAuthBroker, secret, redirectAllowed, discovery} from '../remote/oauth.js';
const base='https://honbako.example/remote', routeKey='R'.repeat(43);
function fixture() {
 const data=new Map(), issued=[];
 const records={get:k=>data.get(k),set:(k,v)=>data.set(k,v),delete:k=>data.delete(k),purge:()=>{}};
 const broker=new OAuthBroker(records,{base,routeKey,workspace:()=>({issue:async id=>{issued.push(id);return {access_token:'fixture'};},refresh:async()=>({access_token:'refreshed'}),revoke:async()=>{}})});
 const register=body=>broker.fetch(new Request(base+'/oauth/register',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)}));
 return {broker,data,issued,register};
}
for(const method of ['none','client_secret_post','client_secret_basic']) test(`OAuth ${method} registration completes with exact callback, phone consent and mandatory S256 PKCE`,async()=>{
 const f=fixture(),redirect='https://accounts.provider.example/oauth/callback';
 const response=await f.register({redirect_uris:[redirect],client_name:'Fixture AI',token_endpoint_auth_method:method});
 assert.equal(response.status,201);const c=await response.json();assert.equal(c.token_endpoint_auth_method,method);
 assert.equal(Boolean(c.client_secret),method!=='none');if(c.client_secret)assert.equal(JSON.stringify([...f.data.values()]).includes(c.client_secret),false);
 const verifier=secret(),params=new URLSearchParams({client_id:c.client_id,redirect_uri:redirect,response_type:'code',scope:'honbako',resource:base+'/mcp',code_challenge_method:'S256',code_challenge:createHash('sha256').update(verifier).digest('base64url'),state:'roundtrip'});
 const auth=await f.broker.fetch(new Request(base+'/oauth/authorize?'+params)),html=await auth.text(),id=/mcp-authorize\?request=([a-f0-9-]+)/.exec(html)[1];
 assert.equal(f.issued.length,0);f.broker.approve(id,'owned-workspace',true);
 const result=await f.broker.fetch(new Request(base+'/oauth/result?request='+id,{headers:{cookie:auth.headers.get('set-cookie').split(';')[0]}}));
 const callback=new URL((await result.json()).redirect),code=callback.searchParams.get('code');
 const fields={grant_type:'authorization_code',client_id:c.client_id,redirect_uri:redirect,resource:base+'/mcp',code_verifier:verifier,code};
 const headers={'content-type':'application/x-www-form-urlencoded'};
 if(method==='client_secret_post')fields.client_secret=c.client_secret;
 if(method==='client_secret_basic')headers.authorization='Basic '+Buffer.from(c.client_id+':'+c.client_secret).toString('base64');
 if(method!=='none') {
  const missing={...fields};delete missing.client_secret;
  await assert.rejects(f.broker.fetch(new Request(base+'/oauth/token',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams(missing)})),{status:401,code:'invalid_client'});
 }
 const token=await f.broker.fetch(new Request(base+'/oauth/token',{method:'POST',headers,body:new URLSearchParams(fields)}));assert.equal(token.status,200);assert.deepEqual(f.issued,[c.client_id]);
});
test('Only exact HTTPS or standard loopback redirects are accepted; public HTTP, wildcards and secrets remain rejected',()=>{
 for(const uri of ['https://provider.example/callback','http://127.0.0.1:43199/callback','http://[::1]:43199/callback','http://localhost:43199/callback'])assert.equal(redirectAllowed(uri),true,uri);
 for(const uri of ['http://provider.example/callback','http://192.168.1.2/callback','https://*.provider.example/callback','https://user:secret@provider.example/callback','https://provider.example/callback#fragment','javascript:alert(1)'])assert.equal(redirectAllowed(uri),false,uri);
 assert.deepEqual(discovery(base).code_challenge_methods_supported,['S256']);
});
test('Registration reports the actual metadata error and never skips PKCE for confidential clients',async()=>{
 const f=fixture();await assert.rejects(f.register({redirect_uris:['http://public.example/callback']}),{code:'invalid_redirect_uri'});
 await assert.rejects(f.register({redirect_uris:['https://ai.example/callback'],token_endpoint_auth_method:'client_secret_jwt'}),{code:'invalid_client_metadata'});
 const client=await (await f.register({redirect_uris:['http://127.0.0.1:44000/callback'],token_endpoint_auth_method:'client_secret_post'})).json();
 const p=new URLSearchParams({client_id:client.client_id,redirect_uri:client.redirect_uris[0],scope:'honbako',resource:base+'/mcp',response_type:'code'});
 await assert.rejects(f.broker.fetch(new Request(base+'/oauth/authorize?'+p)),{status:400});
});

test('Registration diagnosis excludes secrets, callback query values and identifying long path segments',()=>{
 const result=registrationDiagnostic({redirect_uris:['https://user:password@provider.example/callback?token=private#hidden','https://provider.example/'+'s'.repeat(50)],token_endpoint_auth_method:'client_secret_post',client_secret:'do-not-log',client_name:'private name'});
 const text=JSON.stringify(result);
 for(const secret of ['password','private','hidden','do-not-log','private name','s'.repeat(50)])assert.equal(text.includes(secret),false);
 assert.equal(result.authMethod,'client_secret_post');assert.equal(result.redirectURIs[0].host,'provider.example');
});

test('Grok Bot can register its cloud and localhost callbacks together without a client secret', async () => {
 const f=fixture(), callbacks=['https://www.cursor.com/agents/mcp/oauth/callback','http://localhost:8787/callback'];
 const response=await f.register({redirect_uris:callbacks,token_endpoint_auth_method:'none',grant_types:['authorization_code','refresh_token']});
 assert.equal(response.status,201);const client=await response.json();assert.deepEqual(client.redirect_uris,callbacks);
 assert.equal(client.client_secret,undefined);
 const parameters=new URLSearchParams({client_id:client.client_id,redirect_uri:callbacks[1],response_type:'code',scope:'honbako',resource:base+'/mcp',code_challenge_method:'S256',code_challenge:createHash('sha256').update(secret()).digest('base64url')});
 assert.equal((await f.broker.fetch(new Request(base+'/oauth/authorize?'+parameters))).status,200);
 parameters.set('redirect_uri','http://localhost:8788/callback');
 await assert.rejects(f.broker.fetch(new Request(base+'/oauth/authorize?'+parameters)),{status:400});
});
