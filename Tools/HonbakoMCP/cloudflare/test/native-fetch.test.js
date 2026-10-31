import test from 'node:test';
import assert from 'node:assert/strict';
import {makeNativeFetch,Headers} from '../remote/native-fetch.js';

test('Apple transport preserves request headers/body, bounds time and rejects redirects',async()=>{
 let observed;
 const transport=makeNativeFetch(async(input,options)=>{observed={input,options};return new Response('{"ok":true}',{status:200});});
 const r=await transport('https://api.storekit.apple.com/inApps/v1/notifications/history',{method:'POST',headers:{authorization:'Bearer fixture'},body:'{}',timeout:30000});
 assert.equal(observed.options.method,'POST');assert.equal(observed.options.body,'{}');
 assert.equal(observed.options.headers.authorization,'Bearer fixture');
 assert.equal(observed.options.redirect,'manual');assert.ok(observed.options.signal instanceof AbortSignal);
 assert.equal('timeout' in observed.options,false);assert.deepEqual(await r.json(),{ok:true});
});
test('OCSP keeps its headers and binary buffer interface without changing signature verification',async()=>{
 let observed;
 const bytes=Buffer.from([0,1,2,255]);
 const transport=makeNativeFetch(async(input,options)=>{observed=options;return new Response(bytes);});
 const headers=new Headers({'content-type':'application/ocsp-request'}),controller=new AbortController();
 const r=await transport('http://ocsp.apple.com/fixture',{method:'POST',headers,body:bytes,signal:controller.signal});
 assert.equal(observed.signal,controller.signal);assert.equal(observed.headers.get('content-type'),'application/ocsp-request');
 assert.deepEqual(await r.buffer(),bytes);
});

test('Redirects are rejected without sending Apple credentials to the redirect destination',async()=>{
 let requests=0;
 const transport=makeNativeFetch(async()=>{requests++;return new Response(null,{status:302,headers:{location:'https://untrusted.example'}});});
 await assert.rejects(transport('https://api.storekit.apple.com/fixture',{headers:{authorization:'Bearer fixture'}}),/redirects are not accepted/);
 assert.equal(requests,1);
});
