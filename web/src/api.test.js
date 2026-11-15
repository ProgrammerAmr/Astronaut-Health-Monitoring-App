import { test } from 'node:test';
import assert from 'node:assert/strict';
import { request } from './api.js';

test('sends same-origin authenticated JSON requests', async () => {
  let captured;
  const result = await request('/measurements', { token: 'test-token', method: 'POST', body: { heartRate: 80 }, fetcher: async (...args) => { captured = args; return { ok: true, json: async () => ({ data: 1 }) }; } });
  assert.equal(captured[0], '/api/measurements');
  assert.equal(captured[1].headers.Authorization, 'Bearer test-token');
  assert.deepEqual(JSON.parse(captured[1].body), { heartRate: 80 });
  assert.equal(result.data, 1);
});
test('surfaces safe API error messages and status', async () => {
  await assert.rejects(request('/cognitive-state/status', { fetcher: async () => ({ ok: false, status: 503, json: async () => ({ errors: [{ message: 'Service unavailable' }] }) }) }), e => e.status === 503 && e.message === 'Service unavailable');
});
test('handles a network failure', async () => {
  await assert.rejects(request('/health', { fetcher: async () => { throw Error('offline'); } }), e => e.status === 0);
});
