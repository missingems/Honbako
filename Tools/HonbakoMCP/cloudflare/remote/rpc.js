import { BridgeError } from '../../src/store.js';
// Workers RPC does not preserve custom Error fields/prototypes. Carry only
// sanitized application failures across private bindings in a typed envelope.
export async function rpcResult(action) {
  try { return { ok: true, value: await action() }; }
  catch (e) { return { ok: false, status: e instanceof BridgeError ? e.status : 500,
    code: e instanceof BridgeError ? e.code : 'internal_error',
    message: e instanceof BridgeError ? e.message : 'Honbako could not complete this request' }; }
}
export function unwrapRPC(result) {
  if (result?.ok === true) return result.value;
  if (result?.ok === false && Number.isInteger(result.status) && result.status >= 400 && result.status <= 599)
    throw new BridgeError(result.status, result.code, result.message);
  throw new BridgeError(502, 'invalid_response', 'Honbako’s private service is unavailable');
}
