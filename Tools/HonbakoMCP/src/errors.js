export class BridgeError extends Error {
  /// `retryAfter` (seconds) is sent as a Retry-After header, so a limited client waits instead of retrying.
  constructor(status, code, message, { retryAfter } = {}) { super(message); this.status = status; this.code = code; if (retryAfter) this.retryAfter = retryAfter; }
}
