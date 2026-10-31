import { BridgeError } from '../../src/store.js';
import { BUNDLE } from './entitlement.js';

// Read-only probe of this app's TEST notification history, with no notification
// sent, customer transaction queried, or credential included in the result.
export async function probeAppleHistory(api, clock = Date.now, onFailure) {
  const endDate = clock();
  try {
    await api.getNotificationHistory(null, { startDate: endDate - 60000, endDate, notificationType: 'TEST' });
    return { authenticated: true, outcome: 'test_history_authorized', httpStatus: 200 };
  } catch (error) {
    onFailure?.(error);
    const status = error?.httpStatusCode, code = error?.apiError;
    return { authenticated: false, outcome: 'not_verified',
      ...(Number.isInteger(status) ? { httpStatus: status } : {}),
      ...(Number.isInteger(code) ? { appleErrorCode: code } : {}) };
  }
}
export async function checkAppleConnection(env, onFailure) {
  if (!env.APP_STORE_PRIVATE_KEY || !/^[A-Z0-9]{10}$/.test(env.APP_STORE_KEY_ID ?? '')
      || !/^[0-9a-f-]{36}$/i.test(env.APP_STORE_ISSUER_ID ?? ''))
    throw new BridgeError(503, 'purchases_not_configured', 'Apple purchase verification is not configured');
  // The official library initializes randomness; load it inside the handler.
  const { AppStoreServerAPIClient, Environment } = await import('@apple/app-store-server-library');
  const result = { bundleId: BUNDLE };
  for (const [name, environment] of [['production', Environment.PRODUCTION], ['sandbox', Environment.SANDBOX]]) {
    const api = new AppStoreServerAPIClient(env.APP_STORE_PRIVATE_KEY, env.APP_STORE_KEY_ID, env.APP_STORE_ISSUER_ID, BUNDLE, environment);
    result[name] = await probeAppleHistory(api, Date.now, onFailure);
  }
  return result;
}
