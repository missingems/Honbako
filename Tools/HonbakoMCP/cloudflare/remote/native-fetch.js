import { Buffer } from 'node:buffer';

// Workers transport for Apple's official SDK. Signature/certificate/OCSP
// verification stays in the unmodified Apple library; only node-fetch is replaced.
export function makeNativeFetch(fetchImplementation = globalThis.fetch) {
  return async (input, init = {}) => {
    const { timeout, ...options } = init;
    const milliseconds = Number.isFinite(timeout) && timeout > 0 ? Math.min(timeout, 12000) : 12000;
    const response = await fetchImplementation(input, { ...options,
      signal: options.signal ?? AbortSignal.timeout(milliseconds), redirect: 'manual' });
    if (response.status >= 300 && response.status < 400) {
      await response.body?.cancel();
      throw new TypeError('Apple service redirects are not accepted');
    }
    // Apple's OCSP parser uses node-fetch's legacy buffer() method.
    Object.defineProperty(response, 'buffer', { value: async () => Buffer.from(await response.arrayBuffer()) });
    return response;
  };
}
export const Headers = globalThis.Headers;
export const Request = globalThis.Request;
export const Response = globalThis.Response;
export default makeNativeFetch();
