import test from 'node:test';
import assert from 'node:assert/strict';
import { finishBridgeShutdown } from '../../src/cli.js';
test('source shutdown drains accepted state writes before removing writer metadata or lock', async () => {
  const steps = []; let commit;
  const store = { tail: new Promise(resolve => { commit = () => { steps.push('durable-commit'); resolve(); }; }) };
  let stopped;
  const bridge = { close: async () => { steps.push('network-stopped'); stopped?.(); } };
  const networkStopped = new Promise(resolve => { stopped = resolve; });
  const shuttingDown = finishBridgeShutdown(bridge, store, () => { steps.push('lock-removed'); });
  await networkStopped; await Promise.resolve();
  assert.deepEqual(steps, ['network-stopped']);
  commit(); await shuttingDown;
  assert.deepEqual(steps, ['network-stopped', 'durable-commit', 'lock-removed']);
});
