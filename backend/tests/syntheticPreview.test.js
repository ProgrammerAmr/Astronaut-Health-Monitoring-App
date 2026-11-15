const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createPreviewApp } = require('../preview/server');

test('preview is isolated, synthetic and rejects real account and measurement writes', async () => {
  const server = createPreviewApp().listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}/api`;
  try {
    const open = () => fetch(base + '/demo/session', { method: 'POST' }).then(r => r.json());
    const [a, b] = await Promise.all([open(), open()]);
    const headers = { Authorization: `Bearer ${a.token}` };
    assert.notEqual(a.token, b.token);
    const measurements = await fetch(base + '/measurements', { headers }).then(r => r.json());
    assert.equal(measurements.data.length, 5);
    assert.ok(measurements.data.every(m => m.source === 'synthetic'));
    assert.equal((await fetch(base + '/auth/register', { method: 'POST', headers })).status, 404);
    assert.equal((await fetch(base + '/measurements', { method: 'POST', headers })).status, 403);
    const alerts = await fetch(base + '/alerts', { headers }).then(r => r.json());
    await fetch(base + `/alerts/${alerts.data[0]._id}/read`, { method: 'PATCH', headers });
    const bAlerts = await fetch(base + '/alerts', { headers: { Authorization: `Bearer ${b.token}` } }).then(r => r.json());
    assert.equal(bAlerts.data[0].isRead, false);
    await fetch(base + '/auth/logout', { method: 'POST', headers });
    assert.equal((await fetch(base + '/users/me', { headers })).status, 401);
  } finally { await new Promise(resolve => server.close(resolve)); }
});

test('active preview sessions slide until the absolute limit and logout remains final', async () => {
  let clock = 1_000_000;
  const app = createPreviewApp({ now: () => clock, idleTimeoutMs: 1000, maxSessionMs: 2500 });
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}/api`;
  try {
    const { token } = await fetch(base + '/demo/session', { method: 'POST' }).then(r => r.json());
    const headers = { Authorization: `Bearer ${token}` };
    clock += 900;
    assert.equal((await fetch(base + '/users/me', {headers})).status, 200);
    clock += 900;
    assert.equal((await fetch(base + '/users/me', {headers})).status, 200);
    clock += 700;
    assert.equal((await fetch(base + '/users/me', {headers})).status, 401);
  } finally { await new Promise(resolve => server.close(resolve)); }
});
