import { appleRoots } from './apple-roots.js';
import { BridgeError, digest } from '../../src/store.js';

export const PRODUCT = 'com.missingems.honbaku.pro';
export const ANNUAL_PRODUCT = 'com.missingems.honbaku.pro.annual';
export const PRODUCTS = new Set([PRODUCT, ANNUAL_PRODUCT]);
export const BUNDLE = 'com.missingems.honbaku';
export const LEASE_MS = 15 * 60 * 1000;
// Apple documents inAppOwnershipType as PURCHASED or FAMILY_SHARED. Only an explicit
// PURCHASED joins the purchaser's shared workspace; anything else (FAMILY_SHARED, a
// missing or unknown value) gets its own per-installation workspace instead.
// Pending: confirm the live values with a sandbox Family Sharing purchase.
export const purchasedByOwner = transaction => transaction?.inAppOwnershipType === 'PURCHASED';
const denied = () => new BridgeError(402, 'pro_required', 'An active Honbako Pro subscription is required for remote MCP');

// Both the device JWS and a fresh server-to-server subscription status must agree.
// Xcode/personal flags and a client-supplied hasPro value are never entitlement evidence.
export class AppleProVerifier {
  constructor(env, { clock = Date.now, signedVerifier, api } = {}) {
    this.clock = clock;
    this.environment = env.APP_STORE_ENVIRONMENT === 'Sandbox' ? 'Sandbox' : 'Production';
    this.env = env; this.verifier = signedVerifier; this.api = api;
    if (!api && (!env.APP_STORE_PRIVATE_KEY || !env.APP_STORE_KEY_ID || !env.APP_STORE_ISSUER_ID))
      throw new BridgeError(503, 'purchases_not_configured', 'Remote subscriptions are not configured yet');
  }
  async ready() {
    if (this.verifier && this.api) return;
    // Apple’s dependency initializes a CSPRNG on import. Defer that import to
    // a request handler, where Workers permits cryptographic random values.
    const { SignedDataVerifier, AppStoreServerAPIClient } = await import('@apple/app-store-server-library');
    this.verifier ??= new SignedDataVerifier(appleRoots, true, this.environment, BUNDLE, 6827059668);
    this.api ??= new AppStoreServerAPIClient(this.env.APP_STORE_PRIVATE_KEY, this.env.APP_STORE_KEY_ID, this.env.APP_STORE_ISSUER_ID, BUNDLE, this.environment);
  }
  validate(transaction, expiresAt = transaction.expiresDate) {
    if (transaction.bundleId !== BUNDLE || transaction.environment !== this.environment || !PRODUCTS.has(transaction.productId)
        || transaction.type !== 'Auto-Renewable Subscription' || transaction.revocationDate != null
        || !/^\d{1,40}$/.test(transaction.originalTransactionId ?? '')
        || !Number.isFinite(transaction.expiresDate) || !Number.isFinite(expiresAt) || expiresAt <= this.clock()) throw denied();
    return transaction;
  }
  async enroll(jws) {
    if (typeof jws !== 'string' || jws.length < 100 || jws.length > 24000) throw denied();
    await this.ready();
    let transaction;
    // The device copy may be past expiresDate during a billing grace period; the
    // fresh App Store status check below is the only evidence of an active period.
    try { transaction = this.validate(await this.verifier.verifyAndDecodeTransaction(jws), Number.MAX_SAFE_INTEGER); }
    catch (e) {
      if (e?.status === 2) throw new BridgeError(503, 'purchase_check_unavailable', 'Apple’s certificate check is temporarily unavailable');
      throw denied();
    }
    const lease = await this.current(transaction.originalTransactionId);
    return { ...lease, familyShared: lease.familyShared || !purchasedByOwner(transaction) };
  }
  async current(originalTransactionId) {
    await this.ready();
    let response;
    try { response = await this.api.getAllSubscriptionStatuses(originalTransactionId); }
    catch { throw new BridgeError(503, 'purchase_check_unavailable', 'Apple’s subscription check is temporarily unavailable'); }
    const active = [];
    for (const group of response.data ?? []) for (const last of group.lastTransactions ?? []) {
      // 1 = active, 4 = billing grace period (access continues until Apple's signed grace expiry).
      if (![1, 4].includes(last.status) || !last.signedTransactionInfo) continue;
      try {
        const transaction = await this.verifier.verifyAndDecodeTransaction(last.signedTransactionInfo);
        let expiresAt = transaction.expiresDate;
        if (last.status === 4) {
          const renewal = await this.verifier.verifyAndDecodeRenewalInfo(last.signedRenewalInfo);
          if (renewal.originalTransactionId !== transaction.originalTransactionId) continue;
          expiresAt = Math.max(expiresAt, renewal.gracePeriodExpiresDate);
        }
        this.validate(transaction, expiresAt);
        if (transaction.originalTransactionId === originalTransactionId) active.push({ expiresAt, purchased: purchasedByOwner(transaction) });
      } catch { /* An unverified or inactive record cannot grant hosting. */ }
    }
    if (!active.length) throw denied();
    const expiresAt = Math.max(...active.map(a => a.expiresAt));
    return { originalTransactionId, purchaseHash: digest(`${this.environment}:${originalTransactionId}`), familyShared: active.some(a => !a.purchased),
      expiresAt, checkedAt: this.clock(), leaseUntil: Math.min(expiresAt, this.clock() + LEASE_MS) };
  }
}
