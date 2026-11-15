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
test('explains a proxy error instead of reporting invalid JSON', async () => {
  await assert.rejects(request('/auth/login', { fetcher: async () => ({ ok: false, status: 502, json: async () => ({ message: 'Cannot connect to the backend. Start MongoDB and the Node API, then try again.' }) }) }), e => e.status === 502 && e.message.includes('Start MongoDB'));
});
test('explains non-JSON proxy errors and SPA fallback separately', async () => {
  const invalid = async () => { throw new SyntaxError('Not JSON'); };
  await assert.rejects(request('/health', { fetcher: async () => ({ ok: false, status: 500, json: invalid }) }), e => e.status === 500 && e.message.includes('HTTP 500'));
  await assert.rejects(request('/health', { fetcher: async () => ({ ok: true, status: 200, json: invalid }) }), e => e.message.includes('not the frontend'));
});
test('preview uses an isolated demo header instead of real auth header', async () => {
  let captured;
  await request('/users/me', { preview:true, token:'demo-token', fetcher: async (_url, options) => { captured = options; return {ok:true, json:async () => ({data:{}})}; } });
  assert.equal(captured.headers['X-OrbitCare-Demo-Token'], 'demo-token');
  assert.equal(captured.headers.Authorization, undefined);
});
