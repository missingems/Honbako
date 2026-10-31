import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {BridgeStore} from '../src/store.js';
import {dispatch} from '../src/mcp.js';
const stamp = '2026-10-30T06:00:00.000Z';
async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(),'honbako-management-'));
  t.after(() => rm(directory,{recursive:true,force:true}));
  const store = await BridgeStore.open(directory,{clock:()=>Date.parse(stamp)});
  const code = await store.createPairCode();
  const phone = await store.pair({code:code.code,name:'Fixture phone'});
  const state = {schemaVersion:1,generatedAt:stamp,library:[],sources:[],reading:null,
    readingHistoryAccess:true,automationCapabilities:['reading.history','sources.manage'],permissions:{}};
  await store.updateSnapshot(phone.deviceId,state);
  return {store,phone,state,call:(name,args={})=>dispatch(store,name,args)};
}
test('Full history is an on-demand paginated job, not restricted to library membership',async t=>{
  const f=await fixture(t);
  const job=await f.call('honbako_get_reading_history',{limit:100});
  assert.equal(job.kind,'history.read');assert.equal(job.payload.before,stamp);assert.equal(job.payload.offset,0);
  const entries=Array.from({length:100},(_,i)=>({sourceId:'removed-source',mangaId:'outside-library',chapterId:`c${i}`,title:'Saved history',chapterTitle:'Chapter',completed:true,readAt:stamp,page:12,totalPages:12}));
  await f.store.updateJob(f.phone.deviceId,job.id,{status:'completed',result:{entries,nextOffset:100,before:stamp,observedAt:stamp,coverage:'saved_chapter_history',excludedRecords:0}});
  assert.equal((await f.call('honbako_get_job',{jobId:job.id})).result.entries.length,100);
  const next=await f.call('honbako_get_reading_history',{offset:100,limit:100,before:stamp});assert.equal(next.payload.offset,100);
  await f.store.updateSnapshot(f.phone.deviceId,{...f.state,readingHistoryAccess:false});
  await assert.rejects(f.call('honbako_get_reading_history'),{status:403});
  assert.throws(()=>f.store.job({jobId:job.id}),{status:404});
});
test('Source changes cannot complete before explicit phone approval, and retries retain identity',async t=>{
  const f=await fixture(t),change={action:'add_repository',repositoryURL:'https://owner.example/sources.json'};
  const input={change,idempotencyKey:'install_original_repository'};
  const job=await f.call('honbako_manage_sources',input);
  assert.equal(job.status,'queued');assert.equal((await f.call('honbako_manage_sources',input)).id,job.id);
  const result={change,applied:true,observedAt:stamp};
  await assert.rejects(f.store.updateJob(f.phone.deviceId,job.id,{status:'completed',result}),{status:409});
  await assert.rejects(f.call('honbako_manage_sources',{...input,change:{action:'refresh_repositories'}}),{status:409});
  await f.store.updateJob(f.phone.deviceId,job.id,{status:'awaitingApproval',approvalGranted:true});
  await assert.rejects(f.store.updateJob(f.phone.deviceId,job.id,{status:'completed',result:{...result,change:{action:'refresh_repositories'}}}),{status:400});
  await f.store.updateJob(f.phone.deviceId,job.id,{status:'completed',result});
  assert.equal(f.store.job({jobId:job.id}).result.applied,true);
});
test('Source catalog is paginated and disabled permission gates are enforced by the server',async t=>{
  const f=await fixture(t);
  const job=await f.call('honbako_get_source_catalog',{offset:200,limit:50});assert.equal(job.payload.offset,200);
  await f.store.updateSnapshot(f.phone.deviceId,{...f.state,permissions:{libraryRead:false,sourcesWrite:false,readingRead:false,pageRead:false,annotationsWrite:false,libraryWrite:false}});
  await assert.rejects(f.store.publishCoaching(f.phone.deviceId,{}),{status:403});
  for(const [name,args] of [['honbako_search_library',{}],['honbako_list_sources',{}],['honbako_get_reading_context',{}],['honbako_get_coaching_page',{}],['honbako_get_source_catalog',{}],['honbako_manage_sources',{change:{action:'refresh_repositories'},idempotencyKey:'disabled'}]])
    await assert.rejects(f.call(name,args),{status:403});
});
test('Source changes accept named actions, never credential URLs or arbitrary package commands',async t=>{
  const f=await fixture(t);
  for(const repositoryURL of ['http://owner.example/list','https://user:secret@owner.example/list','https://owner.example/list?key=secret','https://owner.example/list#secret'])
    await assert.rejects(f.call('honbako_manage_sources',{change:{action:'add_repository',repositoryURL},idempotencyKey:'unsafe'}));
  await assert.rejects(f.call('honbako_manage_sources',{change:{action:'install',sourceId:'exact-source',packageURL:'https://evil.example/code.zip'},idempotencyKey:'unsafe'}));
  await assert.rejects(f.call('honbako_get_reading_history',{limit:101}));
});
test('Older phones fail with an app-update instruction rather than leaving unknown jobs queued',async t=>{
  const f=await fixture(t);await f.store.updateSnapshot(f.phone.deviceId,{...f.state,automationCapabilities:[]});
  await assert.rejects(f.call('honbako_get_reading_history'),{status:409,code:'update_app'});
  await assert.rejects(f.call('honbako_get_source_catalog'),{status:409,code:'update_app'});
  assert.equal(f.store.data.jobs.length,0);
});
