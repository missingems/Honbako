import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { main } from '../admin-cli.js';
import { stateDigest } from '../migration.js';
async function scratch(change) { const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'honbako-hosted-test-')); try { await change(directory); } finally { await fs.rm(directory, { recursive: true, force: true }); } }
async function capture(change) { const output = []; const original = process.stdout.write; process.stdout.write = value => { output.push(String(value)); return true; }; try { await change(); return output.join(''); } finally { process.stdout.write = original; } }
const emptyState = { version: 1, pairing: null, devices: [], jobs: [] };
test('migration CLI refuses an active local writer and writes only a new 0600 checkpoint', async () => scratch(async directory => {
  await fs.writeFile(path.join(directory, 'state.json'), JSON.stringify(emptyState), { mode: 0o600 });
  await fs.writeFile(path.join(directory, 'server.lock'), JSON.stringify({ pid: process.pid }), { mode: 0o600 });
  await assert.rejects(main(['export-local', '--state-dir', directory, '--output', path.join(directory, 'live.json')]), /Stop the local companion/);
  await fs.rm(path.join(directory, 'server.lock'));
  const file = path.join(directory, 'checkpoint.json'); await capture(() => main(['export-local', '--state-dir', directory, '--output', file]));
  assert.equal((await fs.stat(file)).mode & 0o077, 0); assert.equal(JSON.parse(await fs.readFile(file, 'utf8')).sha256, stateDigest(emptyState));
  await assert.rejects(main(['export-local', '--state-dir', directory, '--output', file]), error => error.code === 'EEXIST');
}));
test('lost import response reconciles exact private checkpoint without importing again', async () => scratch(async directory => {
  const state = structuredClone(emptyState), envelope = { version: 1, state, sha256: stateDigest(state) }, input = path.join(directory, 'input.json'), key = path.join(directory, 'admin.json');
  await fs.writeFile(input, JSON.stringify(envelope), { mode: 0o600 }); await fs.writeFile(key, JSON.stringify({ adminKey: 'A'.repeat(43) }), { mode: 0o600 });
  const fetch = globalThis.fetch, calls = [];
  globalThis.fetch = async (_url, options) => { const body = JSON.parse(options.body); calls.push(body.action); if (body.action === 'import-state') throw new Error('response lost after commit'); return Response.json({ migration: { sha256: envelope.sha256 }, devices: [] }); };
  try { const output = await capture(() => main(['import', '--credential-file', key, '--input', input])); assert.match(output, /Imported 0 devices/); assert.deepEqual(calls, ['import-state', 'status']); }
  finally { globalThis.fetch = fetch; }
}));
test('pair/grant results go to private files and never stdout', async () => scratch(async directory => {
  const key = path.join(directory, 'admin.json'), output = path.join(directory, 'grant.json'), token = 'R'.repeat(43); await fs.writeFile(key, JSON.stringify({ adminKey: 'A'.repeat(43) }), { mode: 0o600 });
  const fetch = globalThis.fetch; globalThis.fetch = async () => Response.json({ token, expiresAt: '2026-10-30T12:00:00Z' });
  try { const text = await capture(() => main(['grant', '--credential-file', key, '--output', output])); assert.ok(!text.includes(token)); assert.equal((await fs.stat(output)).mode & 0o077, 0); assert.equal(JSON.parse(await fs.readFile(output, 'utf8')).token, token); }
  finally { globalThis.fetch = fetch; }
}));
