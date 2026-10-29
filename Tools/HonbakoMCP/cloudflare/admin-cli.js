#!/usr/bin/env node
import { promises as fs, constants } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { pathToFileURL } from 'node:url';
import { stateDigest, validateMigration } from './migration.js';
import { MAX_MIGRATION, boundedBytes } from './core.js';

async function privateRead(file, maximum = MAX_MIGRATION) {
  const handle = await fs.open(file, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.size > maximum || (stat.mode & 0o077)) throw new Error('Private input must be a bounded owner-only regular file');
    return await handle.readFile('utf8');
  } finally { await handle.close(); }
}
async function privateWrite(file, value) {
  const handle = await fs.open(file, 'wx', 0o600);
  try { await handle.writeFile(`${JSON.stringify(value, null, 2)}\n`); await handle.sync(); }
  finally { await handle.close(); }
}
async function verifyStopped(directory) {
  let lock;
  try { lock = JSON.parse(await privateRead(path.join(directory, 'server.lock'), 1024)); }
  catch (error) { if (error.code === 'ENOENT') return; throw error; }
  if (!Number.isSafeInteger(lock.pid) || lock.pid <= 0) throw new Error('Invalid source writer lock');
  try { process.kill(lock.pid, 0); }
  catch (error) { if (error.code === 'ESRCH') return; throw error; }
  throw new Error('Stop the local companion writer before exporting its migration state');
}
export async function main(args = process.argv.slice(2)) {
  const command = args.shift(), options = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!['--state-dir', '--output', '--input', '--credential-file', '--url', '--lifetime-seconds'].includes(args[i]) || args[i + 1] === undefined) throw new Error('Invalid arguments');
    options[args[i].slice(2)] = args[i + 1];
  }
  if (command === 'export-local') {
    if (!options.output) throw new Error('Export requires a new private --output file');
    const directory = options['state-dir'] ?? path.join(os.homedir(), 'Library', 'Application Support', 'HonbakoMCP');
    await verifyStopped(directory);
    const state = JSON.parse(await privateRead(path.join(directory, 'state.json')));
    await verifyStopped(directory);
    state.pairing = null;
    const envelope = { version: 1, state, sha256: stateDigest(state), exportedAt: new Date().toISOString() };
    validateMigration(envelope);
    await privateWrite(options.output, envelope);
    process.stdout.write('Private migration snapshot saved after verifying the source writer is stopped. Keep it stopped during cutover.\n');
    return;
  }
  const action = { status: 'status', pair: 'pair-code', grant: 'grant', 'restore-grant': 'restore-grant', revoke: 'revoke-grant', import: 'import-state', export: 'export-state' }[command];
  if (!action || !options['credential-file']) throw new Error('Choose status/pair/grant/restore-grant/revoke/import/export and an owner-only --credential-file');
  const url = new URL(options.url ?? 'http://127.0.0.1:8789/admin');
  if (url.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) || url.pathname !== '/admin' || url.search || url.hash || url.username || url.password) throw new Error('Admin commands use only the loopback Wrangler facade');
  const credential = JSON.parse(await privateRead(options['credential-file'], 1024));
  if (!/^[A-Za-z0-9_-]{43,100}$/.test(credential.adminKey ?? '')) throw new Error('Private credential file must contain adminKey');
  if (['pair', 'grant', 'export'].includes(command) && !options.output) throw new Error('This command requires a new private --output file');
  let params = {};
  if (command === 'import' || command === 'restore-grant') {
    if (!options.input) throw new Error('Import requires a private --input snapshot');
    params = JSON.parse(await privateRead(options.input)); if (command === 'import') validateMigration(params);
  }
  if (command === 'grant' && options['lifetime-seconds']) params.lifetimeSeconds = Number(options['lifetime-seconds']);
  const invoke = async (operation, input = {}) => {
    const response = await fetch(url, { method: 'POST', redirect: 'error', headers: { 'content-type': 'application/json', authorization: `Bearer ${credential.adminKey}` }, body: JSON.stringify({ action: operation, params: input }), signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error(`Private companion operation failed (${response.status})`);
    return JSON.parse(new TextDecoder().decode(await boundedBytes(response.body, MAX_MIGRATION)));
  };
  let result;
  try { result = await invoke(action, params); }
  catch (error) {
    if (command !== 'import') throw error;
    // A lost HTTP response after an atomic commit is reconciled by the immutable checkpoint, never by overwriting hosted state.
    const status = await invoke('status');
    if (status.migration?.sha256 !== params.sha256) throw error;
    result = { devices: status.devices.length, jobs: params.state.jobs.length, pendingJobs: status.devices.reduce((count, value) => count + value.pendingJobs, 0), alreadyImported: true };
  }
  if (options.output) { await privateWrite(options.output, result); process.stdout.write('Result saved to the requested private file.\n'); }
  else if (command === 'status') process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  else process.stdout.write(`${command === 'import' ? `Imported ${result.devices} devices and ${result.jobs} jobs; ${result.pendingJobs} remain pending.` : command === 'restore-grant' ? 'Original Grok grant restored without extending its expiry.' : 'Grok grant revoked.'}\n`);
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) main().catch(() => { process.stderr.write('Honbako private admin command failed. Verify the private input files and local admin facade.\n'); process.exitCode = 1; });
