const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

test('hosts frontend and preserves JSON API errors on same origin', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'orbitcare-web-'));
  fs.writeFileSync(path.join(dir, 'index.html'), '<h1>OrbitCare</h1>');
  process.env.WEB_DIST_DIR = dir;
  const app = require('../server');
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    const home = await fetch(base + '/');
    assert.equal(home.status, 200);
    assert.match(await home.text(), /OrbitCare/);
    const missing = await fetch(base + '/api/missing');
    assert.equal(missing.status, 404);
    assert.equal((await missing.json()).success, false);
    const health = await fetch(base + '/api/health');
    assert.equal((await health.json()).success, true);
  } finally {
    await new Promise(resolve => server.close(resolve));
    fs.rmSync(dir, { recursive: true, force: true });
    delete process.env.WEB_DIST_DIR;
  }
});
