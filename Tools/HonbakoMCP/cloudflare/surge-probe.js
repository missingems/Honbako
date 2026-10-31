#!/usr/bin/env node
// Floods the remote Worker and reports how its limits answer: status counts, the first 429,
// Retry-After values, where each 429 came from, and latency.
//
//   node cloudflare/surge-probe.js                 local workerd, scenarios a–e (needs HONBAKO_WRANGLER_ROOT)
//   node cloudflare/surge-probe.js --no-bindings   local, without the Rate Limiting bindings (the fallback)
//   node cloudflare/surge-probe.js --live https://test-mcp.honbako.xyz
//                                                  only a and b, at most 60 requests in total
//
// Every request in --live mode comes out of the account's shared Workers Free allowance, and
// the production hosts are refused. Nothing here deploys, signs in or uses real credentials.
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { routedToken } from './remote/oauth.js';
import { secondsUntilMidnightUTC } from './limits.js';

const LIVE_CAP = 60;
const args = process.argv.slice(2), liveIndex = args.indexOf('--live');
const live = liveIndex >= 0 ? new URL(args[liveIndex + 1] ?? '') : null, bindings = !args.includes('--no-bindings');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function refuseProduction(target) {
  if (target.protocol !== 'https:' || target.pathname !== '/' || target.search) throw new Error('--live takes an https origin, such as https://test-mcp.honbako.xyz');
  const production = JSON.parse(await fs.readFile(new URL('./wrangler.jsonc', import.meta.url), 'utf8'));
  const hosts = [new URL(production.vars.PUBLIC_ORIGIN).host, ...production.vars.REMOTE_ORIGIN_ALIASES.map(a => new URL(a).host), ...production.routes.map(r => r.pattern)];
  if (hosts.includes(target.host)) throw new Error(`${target.host} is production; the probe only runs against the test Worker`);
}

/// Where a 429 came from: Cloudflare's WAF answers with an HTML block page or cf-mitigated,
/// our Worker with a JSON `rate_limited` error (application or OAuth shape).
function source(response, text) {
  if (response.status !== 429) return null;
  if (response.headers.has('cf-mitigated') || /text\/html/i.test(response.headers.get('content-type') ?? '')) return 'waf';
  try { const body = JSON.parse(text); if ((body.error?.code ?? body.error) === 'rate_limited') return 'worker'; } catch {}
  return 'other';
}
function transport({ dispatch, ip }) {
  let sent = 0;
  return {
    get sent() { return sent; },
    async send(origin, pathname, { method = 'GET', token, body } = {}) {
      if (live && sent >= LIVE_CAP) throw new Error(`Live cap of ${LIVE_CAP} requests reached`);
      sent++;
      const headers = { accept: 'application/json, text/event-stream', 'user-agent': 'honbako-surge-probe', ...(body === undefined ? {} : { 'content-type': 'application/json' }),
        ...(token ? { authorization: `Bearer ${token}` } : {}), ...(ip ? { 'cf-connecting-ip': ip } : {}) };
      const started = performance.now();
      const response = await dispatch(`${origin}${pathname}`, { method, headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
      const text = await response.text();
      return { status: response.status, retryAfter: response.headers.get('retry-after'), source: source(response, text), ms: performance.now() - started };
    }
  };
}
function report(name, expectation, results, check, extra = {}) {
  const statuses = {}, first = results.findIndex(r => r.status === 429), sources = {};
  for (const r of results) { statuses[r.status] = (statuses[r.status] ?? 0) + 1; if (r.source) sources[r.source] = (sources[r.source] ?? 0) + 1; }
  const ms = results.map(r => r.ms).sort((a, b) => a - b), at = q => ms.length ? Math.round(ms[Math.min(ms.length - 1, Math.floor(q * ms.length))]) : null;
  const summary = { scenario: name, expectation, requests: results.length, statuses, first429: first < 0 ? null : first + 1,
    retryAfter: [...new Set(results.map(r => r.retryAfter).filter(Boolean))], sources429: sources,
    latencyMs: { p50: at(0.5), p95: at(0.95), max: ms.length ? Math.round(ms.at(-1)) : null }, ...extra };
  summary.pass = check(summary, results);
  process.stdout.write(`${JSON.stringify(summary)}\n`);
  return summary.pass;
}
const junk = () => [routedToken('d', randomUUID(), 'J'.repeat(43)), routedToken('a', randomUUID(), 'J'.repeat(43))];

// (a) Forged tokens: an HMAC check in the Worker, a cheap 401, and no Durable Object.
async function junkTokens(net, origin, count, objects) {
  const before = await objects?.(), results = [];
  for (let i = 0; i < count; i++) {
    const [deviceToken, aiToken] = junk();
    results.push(await (i % 2 ? net.send(origin, '/remote/mcp', { method: 'POST', token: aiToken, body: { jsonrpc: '2.0', id: 1, method: 'tools/list' } })
      : net.send(origin, '/remote/api/device/jobs', { token: deviceToken })));
  }
  const created = objects ? (await objects()) - before : undefined;
  // The enrolled fixture workspaces already have their files, so a zero here is not vacuous.
  return report('a-junk-tokens', 'every request 401, no Durable Object created', results,
    s => s.statuses[401] === s.requests && (created === undefined || (before > 0 && created === 0)), created === undefined ? {} : { durableObjectsBefore: before, newDurableObjects: created });
}
// (b) Setup and registration floods from one address. The bodies are invalid, so nothing is stored.
/// With the SETUP binding, enrollment and registration share one allowance per address, so the
/// registrations after an enroll flood are refused too. Without it, enrollment falls back to the
/// broker's 10 per 10 minutes and registration to its separate 120 a minute.
async function setupFlood(net, origin, enrollCount, registerCount, firstExpected, shared) {
  const results = [];
  for (let i = 0; i < enrollCount; i++) results.push(await net.send(origin, '/remote/enroll', { method: 'POST', body: { installationId: 'probe', deviceSecret: 'probe' } }));
  for (let i = 0; i < registerCount; i++) results.push(await net.send(origin, '/remote/oauth/register', { method: 'POST', body: {} }));
  const registrations = results.slice(enrollCount);
  return report('b-setup-flood', `enroll 429 by request ${firstExpected} with Retry-After; registrations ${shared ? 'refused too' : 'under their own limit'}`, results,
    s => s.first429 !== null && s.first429 <= firstExpected && results.slice(s.first429 - 1, enrollCount).every(r => r.status === 429) && s.retryAfter.length > 0
      && (shared === undefined || registrations.every(r => (r.status === 429) === shared)), { registrations429: registrations.filter(r => r.status === 429).length });
}
// (c) One device polling at five times the reading pace (about 7 a second).
async function fastDevice(net, origin, token) {
  const results = [], started = Date.now();
  while (Date.now() - started < 60000) {
    const r = await net.send(origin, results.length % 5 ? '/remote/api/device/coaching' : '/remote/api/device/jobs', { token });
    results.push(r);
    if (results.filter(x => x.status === 429).length >= 10) break;
    await sleep(140);
  }
  return report('c-fast-device', '429 with Retry-After within a minute', results,
    s => s.first429 !== null && s.first429 <= 300 && s.retryAfter.length > 0 && s.sources429.worker === s.statuses[429]);
}
// (d) The normal reading pace for two minutes: page annotations every 0.75 s and jobs every 3 s.
async function readingPace(net, origin, token, seconds = 120) {
  const results = [], started = performance.now();
  const ticks = Array.from({ length: Math.floor(seconds / 0.75) }, (_, i) => ({ at: i * 750, path: '/remote/api/device/coaching' }))
    .concat(Array.from({ length: Math.floor(seconds / 3) }, (_, i) => ({ at: i * 3000 + 100, path: '/remote/api/device/jobs' }))).sort((a, b) => a.at - b.at);
  await Promise.all(ticks.map(async tick => {
    await sleep(Math.max(0, tick.at - (performance.now() - started)));
    results.push(await net.send(origin, tick.path, { token }));
  }));
  return report('d-reading-pace', 'no 429 in two minutes', results, s => !s.statuses[429] && s.statuses[200] === s.requests);
}
// (e) A workspace past its daily budget waits until 00:00 UTC.
async function overBudget(net, origin, token, budget) {
  const results = [];
  for (let i = 0; i < budget + 5; i++) results.push(await net.send(origin, '/remote/api/device/jobs', { token }));
  const expected = secondsUntilMidnightUTC(Date.now());
  return report('e-daily-budget', `429 from request ${budget + 1}, Retry-After ≈ ${expected} s (00:00 UTC)`, results,
    s => s.first429 === budget + 1 && results.slice(budget).every(r => r.status === 429 && Math.abs(Number(r.retryAfter) - expected) <= 5), { midnightSeconds: expected });
}

const passed = [];
if (live) {
  await refuseProduction(live);
  const net = transport({ dispatch: fetch });
  passed.push(await junkTokens(net, live.origin, 20));
  passed.push(await setupFlood(net, live.origin, 25, 15, 21));
  process.stdout.write(`${JSON.stringify({ target: live.origin, requests: net.sent, cap: LIVE_CAP })}\n`);
} else {
  const { remoteFixture } = await import('./workerd-fixture.js');
  const BUDGET = 40;
  const fixture = await remoteFixture({ rateLimits: bindings }), budgetFixture = await remoteFixture({ rateLimits: bindings, bindings: { WORKSPACE_DAILY_REQUEST_BUDGET: String(BUDGET) } });
  try {
    for (const f of [fixture, budgetFixture]) await f.start();
    const enroll = async (f, name, purchase) => (await (await f.json('/fixture/enroll', { installationId: randomUUID(), deviceSecret: randomUUID().replaceAll('-', '').padEnd(43, 'x'), name, purchase })).json()).deviceToken;
    const objects = async () => {
      const files = await fs.readdir(path.join(fixture.directory, 'durable'), { recursive: true }).catch(() => []);
      return files.filter(file => file.endsWith('.sqlite')).length;
    };
    const net = transport({ dispatch: (url, init) => fixture.mf.dispatchFetch(url, init), ip: '198.51.100.7' });
    const [fast, reader] = [await enroll(fixture, 'Probe fast', 'probe-fast'), await enroll(fixture, 'Probe reader', 'probe-reader')];
    passed.push(await junkTokens(net, fixture.origin, 40, objects));
    passed.push(await setupFlood(net, fixture.origin, 25, 5, bindings ? 21 : 11, bindings));
    passed.push(await fastDevice(net, fixture.origin, fast));
    passed.push(await readingPace(net, fixture.origin, reader));
    const budgetNet = transport({ dispatch: (url, init) => budgetFixture.mf.dispatchFetch(url, init), ip: '198.51.100.9' });
    passed.push(await overBudget(budgetNet, budgetFixture.origin, await enroll(budgetFixture, 'Probe budget', 'probe-budget'), BUDGET));
    process.stdout.write(`${JSON.stringify({ target: 'local-workerd', rateLimitBindings: bindings, requests: net.sent + budgetNet.sent })}\n`);
  } finally { await fixture.close(); await budgetFixture.close(); }
}
process.exitCode = passed.every(Boolean) ? 0 : 1;
