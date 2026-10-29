#!/usr/bin/env node
import { promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
import { StdioServerTransport } from '@modelcontextprotocol/server/stdio';
import { BridgeStore, atomicWrite, BridgeError } from './store.js';
import { startBridge } from './server.js';
import { createMcpServer } from './mcp.js';
import { gatewayCredential, gatewayCredentialCurrent, revokeGatewayCredential, startMcpGateway, writeGatewayClientConfig } from './gateway.js';

export function options(argv) {
  const command = argv[0] ?? 'help';
  const result = { command, directory: path.join(os.homedir(), 'Library', 'Application Support', 'HonbakoMCP'), host: '127.0.0.1', port: command === 'gateway' ? 43188 : 43187 };
  for (let index = 1; index < argv.length; index += 2) {
    const name = argv[index], value = argv[index + 1];
    if (!value || !['--state-dir', '--host', '--port', '--device-id'].includes(name)) throw new Error('Invalid arguments');
    if (name === '--state-dir') result.directory = path.resolve(value);
    if (name === '--host') result.host = value;
    if (name === '--device-id') result.deviceId = value;
    if (name === '--port') result.port = Number(value);
  }
  if (!Number.isInteger(result.port) || result.port < 1 || result.port > 65535) throw new Error('Invalid port');
  if (!['127.0.0.1', 'localhost', '::1', '0.0.0.0'].includes(result.host)) throw new Error('Choose loopback or explicit --host 0.0.0.0 for phone LAN pairing');
  if (command === 'gateway' && result.host !== '127.0.0.1') throw new Error('The MCP gateway binds only to 127.0.0.1');
  return result;
}
async function connection(directory) {
  const config = JSON.parse(await fs.readFile(path.join(directory, 'server.json'), 'utf8'));
  const token = (await fs.readFile(path.join(directory, 'mcp-token'), 'utf8')).trim();
  const url = new URL(config.url);
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) || url.protocol !== 'http:') throw new Error('Local server configuration is invalid');
  return { ...config, token };
}
async function admin(config, endpoint, method = 'GET') {
  const response = await fetch(`${config.url}${endpoint}`, { method, redirect: 'error',
    headers: { Authorization: `Bearer ${config.token}` }, signal: AbortSignal.timeout(5000) });
  if (!response.ok) throw new Error('Local bridge rejected this command');
  return response.json();
}
async function lock(directory, filename = 'server.lock', label = 'Bridge') {
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  const file = path.join(directory, filename);
  try { await fs.writeFile(file, JSON.stringify({ pid: process.pid }), { flag: 'wx', mode: 0o600 }); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    const previous = JSON.parse(await fs.readFile(file, 'utf8'));
    try { process.kill(previous.pid, 0); throw new Error(`${label} is already running for this state directory`); }
    catch (error) { if (error.code !== 'ESRCH') throw error; }
    await fs.rm(file); return lock(directory, filename, label);
  }
  return () => fs.rm(file, { force: true });
}
export async function writeClientConfigs(directory, config) {
  const folder = path.join(directory, 'client-configs');
  await fs.mkdir(folder, { mode: 0o700, recursive: true });
  await fs.chmod(folder, 0o700);
  const launcher = fileURLToPath(import.meta.url);
  const stdio = { mcpServers: { honbako: { command: process.execPath, args: [launcher, 'proxy', '--state-dir', directory] } } };
  const http = { url: `${config.url}/mcp`, headers: { Authorization: `Bearer ${config.token}` } };
  const stdioFile = path.join(folder, 'claude-desktop.json'), httpFile = path.join(folder, 'http-client.json');
  await atomicWrite(stdioFile, `${JSON.stringify(stdio, null, 2)}\n`);
  await atomicWrite(httpFile, `${JSON.stringify(http, null, 2)}\n`);
  return { stdioFile, httpFile };
}
async function proxy(directory) {
  const config = await connection(directory);
  const client = new Client({ name: 'honbako-local-proxy', version: '0.1.0' });
  const transport = new StreamableHTTPClientTransport(new URL(`${config.url}/mcp`), {
    requestInit: { headers: { Authorization: `Bearer ${config.token}` } }
  });
  await client.connect(transport);
  const server = createMcpServer((name, args) => client.callTool({ name, arguments: args }));
  await server.connect(new StdioServerTransport());
  const close = async () => { await server.close(); await client.close(); };
  process.once('SIGINT', () => { void close().finally(() => process.exit(0)); });
  process.once('SIGTERM', () => { void close().finally(() => process.exit(0)); });
  process.stdin.once('end', () => { void close(); });
}
export async function finishBridgeShutdown(bridge, store, cleanup) {
  await bridge.close();
  // Requests already accepted may still be committing their final atomic state write.
  await store.tail;
  await cleanup();
}
export async function main(argv = process.argv.slice(2)) {
  const config = options(argv);
  if (config.command === 'serve') {
    const unlock = await lock(config.directory);
    let bridge;
    try {
      const store = await BridgeStore.open(config.directory);
      bridge = await startBridge(store, { host: config.host, port: config.port });
      const saved = { url: bridge.url, host: config.host, port: bridge.port, pid: process.pid, startedAt: new Date().toISOString() };
      await atomicWrite(path.join(config.directory, 'server.json'), `${JSON.stringify(saved)}\n`);
      const files = await writeClientConfigs(config.directory, { ...saved, token: store.token });
      process.stdout.write(`Honbako bridge is running at ${bridge.url}\nMCP endpoint: ${bridge.url}/mcp\nPrivate client configuration: ${files.stdioFile}\n`);
      if (config.host === '0.0.0.0') process.stdout.write('Phone pairing is available on this Mac’s LAN address. Run the pair command to get a one-time code.\n');
      else process.stdout.write('Loopback only. For an iPhone on the same trusted LAN, restart with --host 0.0.0.0.\n');
      let closing;
      const close = () => closing ??= finishBridgeShutdown(bridge, store, async () => { await fs.rm(path.join(config.directory, 'server.json'), { force: true }); await unlock(); });
      for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => { void close().finally(() => process.exit(0)); });
    } catch (error) { if (bridge) await bridge.close(); await unlock(); throw error; }
    return;
  }
  if (config.command === 'gateway-revoke') {
    await revokeGatewayCredential(config.directory);
    process.stdout.write('Grok gateway credential revoked. New gateway requests are rejected; the Mac companion and phone pairing are unchanged.\n');
    return;
  }
  if (config.command === 'gateway') {
    const saved = await connection(config.directory);
    const credential = await gatewayCredential(config.directory, saved.token);
    const unlock = await lock(config.directory, 'gateway.lock', 'MCP gateway');
    let gateway;
    try {
      gateway = await startMcpGateway({ upstreamURL: saved.url, upstreamToken: saved.token,
        token: credential.token, host: config.host, port: config.port, expiresAt: credential.expiresAt,
        credentialCurrent: () => gatewayCredentialCurrent(config.directory, credential) });
      const metadata = { url: gateway.url, host: config.host, port: gateway.port, pid: process.pid, startedAt: new Date().toISOString(), expiresAt: credential.expiresAt };
      await atomicWrite(path.join(config.directory, 'gateway.json'), `${JSON.stringify(metadata)}\n`);
      const file = await writeGatewayClientConfig(config.directory, gateway.url, credential.token, credential.expiresAt);
      process.stdout.write(`Local MCP-only gateway: ${gateway.url}/mcp\nPrivate Grok connector configuration: ${file}\n`);
      process.stdout.write(`Credential expires: ${credential.expiresAt}\nRevoke locally: node src/cli.js gateway-revoke\n`);
      process.stdout.write('Only authenticated POST /mcp is allowed. No public endpoint or tunnel was started.\n');
      let closing;
      const close = () => closing ??= (async () => {
        await gateway.close(); await fs.rm(path.join(config.directory, 'gateway.json'), { force: true }); await unlock();
      })();
      for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => { void close().finally(() => process.exit(0)); });
    } catch (error) {
      if (gateway) await gateway.close();
      await fs.rm(path.join(config.directory, 'gateway.json'), { force: true }); await unlock(); throw error;
    }
    return;
  }
  if (config.command === 'proxy') return proxy(config.directory);
  if (['pair', 'status', 'configure', 'forget'].includes(config.command)) {
    const saved = await connection(config.directory);
    if (config.command === 'forget') {
      if (!/^[0-9a-f-]{36}$/.test(config.deviceId ?? '')) throw new Error('Specify --device-id from status');
      await admin(saved, `/api/admin/devices/${config.deviceId}`, 'DELETE');
      process.stdout.write('Device disconnected; its credential and queued jobs were revoked.\n');
    } else if (config.command === 'pair') {
      const { code, expiresAt } = await admin(saved, '/api/admin/pair-code', 'POST');
      process.stdout.write(`One-time Honbako pairing code: ${code}\nExpires: ${expiresAt}\n`);
      if (saved.host === '0.0.0.0') {
        for (const entries of Object.values(os.networkInterfaces())) for (const entry of entries ?? [])
          if (entry.family === 'IPv4' && !entry.internal) process.stdout.write(`Phone connection address: http://${entry.address}:${saved.port}\n`);
      } else process.stdout.write('The server is loopback-only; restart serve with --host 0.0.0.0 before connecting a phone over LAN.\n');
      process.stdout.write('Enter the Mac address and this code in Honbako’s AI Connections settings.\n');
    } else if (config.command === 'status') process.stdout.write(`${JSON.stringify(await admin(saved, '/api/admin/status'), null, 2)}\n`);
    else {
      const files = await writeClientConfigs(config.directory, saved);
      process.stdout.write(`Private stdio configuration: ${files.stdioFile}\nPrivate HTTP configuration: ${files.httpFile}\nCredentials were saved to private files and were not printed.\n`);
    }
    return;
  }
  process.stdout.write('Honbako local MCP bridge\nCommands: serve, gateway (local MCP-only port 43188), gateway-revoke, pair, status, configure, proxy, forget --device-id UUID\nOptions: --state-dir PATH, --port NUMBER, --host 127.0.0.1 (default) or 0.0.0.0 (explicit phone LAN access)\n');
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => {
    const message = error instanceof BridgeError ? error.message : 'Command failed. Check that the local bridge is running and its private state directory is available.';
    process.stderr.write(`Honbako bridge: ${message}\n`);
    process.exitCode = 1;
  });
}
