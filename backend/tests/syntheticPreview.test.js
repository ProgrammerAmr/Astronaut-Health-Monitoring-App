const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createPreviewApp } = require('../preview/server');

test('preview is isolated and accepts only acknowledged synthetic measurements', async () => {
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
    const jsonHeaders = {...headers, 'Content-Type':'application/json'};
    const create = body => fetch(base + '/measurements', {method:'POST', headers:jsonHeaders, body:JSON.stringify(body)});
    assert.equal((await create({heartRate:80})).status, 400);
    assert.equal((await create({heartRate:500, syntheticConfirmed:true})).status, 400);
    assert.equal((await create({heartRate:80, name:'Personal Data', syntheticConfirmed:true})).status, 400);
    const added = await create({heartRate:80, syntheticConfirmed:true});
    assert.equal(added.status, 201);
    assert.equal((await added.json()).data.source, 'synthetic');
    const refreshed = await fetch(base + '/dashboard/overview', {headers}).then(r => r.json());
    assert.equal(refreshed.data.totalMeasurements, 6);
    assert.equal(refreshed.data.latestMeasurement.heartRate, 80);
    const report = await fetch(base + '/reports?period=weekly', {headers}).then(r => r.json());
    assert.equal(report.data.summary.records, 6);
    assert.ok(Number.isFinite(report.data.summary.avgSpo2));
    const bData = await fetch(base + '/measurements', {headers:{Authorization:`Bearer ${b.token}`}}).then(r => r.json());
    assert.equal(bData.data.length, 5);
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

test('the preview accepts its dedicated demo token header', async () => {
  const server = createPreviewApp().listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}/api`;
  try {
    const {token} = await fetch(base + '/demo/session', {method:'POST'}).then(r => r.json());
    const result = await fetch(base + '/users/me', {headers:{'X-OrbitCare-Demo-Token':token}});
    assert.equal(result.status, 200);
  } finally { await new Promise(resolve => server.close(resolve)); }
});
