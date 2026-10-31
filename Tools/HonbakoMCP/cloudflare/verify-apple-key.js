#!/usr/bin/env node
// Read-only credential preflight. Never prints the private key, JWT or Apple response body.
import { readFile } from 'node:fs/promises';
import { createPrivateKey } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { checkAppleConnection, probeAppleHistory } from './remote/apple-connection.js';

export function validateKey(pem) {
  const key = createPrivateKey(pem);
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1')
    throw new Error('Apple verification requires an EC P-256 private key');
}
export const probe = probeAppleHistory;

async function main() {
  const args = process.argv.slice(2), options = {};
  if (args.length !== 6) throw new Error('Provide --key-file PATH --key-id ID --issuer-id UUID');
  for (let i = 0; i < args.length; i += 2) options[args[i]] = args[i + 1];
  if (!/^[A-Z0-9]{10}$/.test(options['--key-id'] ?? '') || !/^[0-9a-f-]{36}$/i.test(options['--issuer-id'] ?? '') || !options['--key-file'])
    throw new Error('Invalid key metadata');
  const pem = await readFile(options['--key-file'], 'utf8'); validateKey(pem);
  const results = await checkAppleConnection({ APP_STORE_PRIVATE_KEY: pem,
    APP_STORE_KEY_ID: options['--key-id'], APP_STORE_ISSUER_ID: options['--issuer-id'] });
  process.stdout.write(`${JSON.stringify({ keyFormat: 'EC P-256', ...results })}\n`);
  if (!results.production.authenticated || !results.sandbox.authenticated) process.exitCode = 1;
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href)
  main().catch(() => { process.stderr.write('Apple credential verification could not complete. No secrets were printed.\n'); process.exitCode = 1; });
