import test from 'node:test';
import assert from 'node:assert/strict';
import { probeAppleHistory, checkAppleConnection } from '../remote/apple-connection.js';

test('Apple credential preflight is bounded to TEST history and does not return its contents', async () => {
  let called;
  const result = await probeAppleHistory({ async getNotificationHistory(token, request) {
    called = {token,request}; return {notificationHistory:[{signedPayload:'never-return-this'}]};
  } }, () => 1800000000000);
  assert.deepEqual(called, {token:null,request:{startDate:1799999940000,endDate:1800000000000,notificationType:'TEST'}});
  assert.deepEqual(result, {authenticated:true,outcome:'test_history_authorized',httpStatus:200});
});
test('Rejected or unavailable Apple access never passes and error messages/credentials are not returned', async () => {
  for (const status of [400,401,403,404,429,500]) {
    const result=await probeAppleHistory({async getNotificationHistory(){throw {httpStatusCode:status,apiError:4000006,message:'private-token'};}});
    assert.equal(result.authenticated,false); assert.equal(result.httpStatus,status);
    assert.equal(JSON.stringify(result).includes('private-token'),false);
  }
  await assert.rejects(checkAppleConnection({}), {status:503});
});
