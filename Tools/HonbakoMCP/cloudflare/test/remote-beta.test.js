import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { AppleProVerifier, PRODUCT, BUNDLE, LEASE_MS } from '../remote/entitlement.js';

const now = Date.now();
const transaction = { bundleId: BUNDLE, productId: PRODUCT, environment: 'Sandbox',
  type: 'Auto-Renewable Subscription', originalTransactionId: '987654321', expiresDate: now + 86400000 };
const make = (value = transaction, status = 1) => new AppleProVerifier({APP_STORE_ENVIRONMENT:'Sandbox'}, {
  clock: () => now,
  signedVerifier: {async verifyAndDecodeTransaction() { return value; }},
  api: {async getAllSubscriptionStatuses() { return {data:[{lastTransactions:[{status,signedTransactionInfo:'fixture'}]}]}; }}
});
test('Sandbox Pro requires its own active Apple transaction and does not accept Production or Xcode purchases', async () => {
  const lease = await make().enroll('x'.repeat(150));
  assert.equal(lease.leaseUntil, now + LEASE_MS);
  for (const patch of [{environment:'Production'}, {environment:'Xcode'}, {productId:'other'}, {bundleId:'other'},
    {expiresDate:now}, {revocationDate:now-1}, {type:'Non-Consumable'}])
    await assert.rejects(make({...transaction,...patch}).enroll('x'.repeat(150)), {status:402});
  for (const status of [2,3,4,5]) await assert.rejects(make(transaction,status).enroll('x'.repeat(150)), {status:402});
  await assert.rejects(make().enroll({hasPro:true}), {status:402});
});
test('The real Sandbox verifier rejects an unsigned transaction rather than trusting the beta flag', async () => {
  const verifier = new AppleProVerifier({APP_STORE_ENVIRONMENT:'Sandbox'}, {api:{}});
  const fake = `${Buffer.from('{"alg":"none"}').toString('base64url')}.${Buffer.from(JSON.stringify(transaction)).toString('base64url')}.`;
  await assert.rejects(verifier.enroll(fake), {status:402});
});
test('The beta deployment has a distinct origin and fresh SQLite namespaces, with no legacy owner binding', async () => {
  const production = JSON.parse(await readFile(new URL('../wrangler.jsonc', import.meta.url), 'utf8'));
  const beta = JSON.parse(await readFile(new URL('../wrangler.remote.jsonc', import.meta.url), 'utf8'));
  assert.notEqual(beta.name, production.name);
  assert.notEqual(beta.vars.PUBLIC_ORIGIN, production.vars.PUBLIC_ORIGIN);
  assert.equal(beta.vars.APP_STORE_ENVIRONMENT, 'Sandbox');
  assert.notEqual(production.vars.APP_STORE_ENVIRONMENT, 'Sandbox');
  assert.equal(production.vars.REMOTE_MCP_ENABLED, 'YES');
  assert.equal(production.vars.APP_STORE_ENVIRONMENT, 'Production');
  assert.equal(beta.main, 'remote-beta.js');
  assert.deepEqual(beta.durable_objects.bindings.map(v=>v.name).sort(), ['HONBAKO_AUTH','HONBAKO_WORKSPACE']);
  assert.ok(beta.durable_objects.bindings.every(v=>!v.script_name));
  assert.ok(beta.migrations.every(v=>v.new_sqlite_classes && !v.new_classes));
  assert.equal(beta.observability.enabled,false);
});
