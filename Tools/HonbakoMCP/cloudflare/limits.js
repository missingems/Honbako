import { BridgeError } from '../src/store.js';

const DAY_MS = 86400000;
/// Seconds until the next 00:00 UTC, when Workers Free allowances and daily budgets reset.
export const secondsUntilMidnightUTC = now => Math.max(1, Math.ceil(((Math.floor(now / DAY_MS) + 1) * DAY_MS - now) / 1000));
export const utcDay = now => new Date(now).toISOString().slice(0, 10);

/// Fixed-window request counters held in memory. A Durable Object is single-threaded and stays
/// warm while it is polled, so a surge meets the same counters; eviction resets them, which is
/// acceptable. Writing a row per request would spend the account's daily SQLite allowance.
export class MemoryLimiter {
  constructor(clock = Date.now, capacity = 4096) { this.clock = clock; this.capacity = capacity; this.windows = new Map(); }
  /// Counts one request against every key. Returns null when allowed, or the seconds to wait.
  take(keys, limit, windowMs) {
    const now = this.clock(), current = key => { const w = this.windows.get(key); return w && w.expires > now ? w : null; };
    const full = keys.map(current).filter(w => w && w.count >= limit);
    if (full.length) return Math.max(1, Math.ceil((Math.min(...full.map(w => w.expires)) - now) / 1000));
    const fresh = keys.filter(key => !current(key));
    if (fresh.length && this.windows.size + fresh.length > this.capacity) {
      for (const [key, w] of this.windows) if (w.expires <= now) this.windows.delete(key);
      if (this.windows.size + fresh.length > this.capacity) return Math.ceil(windowMs / 1000);
    }
    for (const key of keys) {
      const w = current(key);
      if (w) w.count++; else this.windows.set(key, { count: 1, expires: now + windowMs });
    }
    return null;
  }
  allow(keys, limit, windowMs) { return this.take(keys, limit, windowMs) === null; }
  /// Throws 429 with Retry-After when any key is over its limit.
  enforce(keys, limit, windowMs, message = 'Too many requests; retry later', code = 'rate_limited') {
    const wait = this.take(keys, limit, windowMs);
    if (wait !== null) throw new BridgeError(429, code, message, { retryAfter: wait });
  }
}
