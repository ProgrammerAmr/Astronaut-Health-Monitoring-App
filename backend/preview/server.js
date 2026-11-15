// Explicitly opt-in, in-memory synthetic preview; not the real MongoDB backend.
// Never accept passwords, email, or real health data here.
const express = require('express');
const crypto = require('node:crypto');
const { getCognitiveStateStatus, analyzeCognitiveState } = require('../src/controllers/cognitiveStateController');

function createPreviewApp({ now = Date.now, idleTimeoutMs = 8 * 60 * 60 * 1000, maxSessionMs = 24 * 60 * 60 * 1000 } = {}) {
  const app = express();
  const sessions = new Map();
  app.use(express.json({ limit: '32kb' }));
  app.get('/api/health', (_req, res) => res.json({ success: true, synthetic_preview: true }));
  app.post('/api/demo/session', (_req, res) => {
    const timestamp = now();
    for (const [key, session] of sessions) if (session.expiresAt <= timestamp) sessions.delete(key);
    if (sessions.size >= 100) return res.status(503).json({ message: 'Preview is busy; please try again later.' });
    const token = crypto.randomBytes(32).toString('hex');
    const measurements = [76, 72, 78, 74, 71].map((heartRate, i) => ({
      _id: crypto.randomUUID(), heartRate, spo2: 98, respiratoryRate: 16, temperature: 36.8,
      measuredAt: new Date(timestamp - i * 86400000).toISOString(), source: 'synthetic',
    }));
    const alerts = [{ _id: crypto.randomUUID(), title: '[SYNTHETIC] Demo reminder', message: 'This is an example alert, not a clinical notification.', severity: 'low', isRead: false, createdAt: new Date(timestamp).toISOString() }];
    sessions.set(token, { measurements, alerts, expiresAt: timestamp + idleTimeoutMs, maxExpiresAt: timestamp + maxSessionMs });
    res.json({ token, user: { id: 'synthetic-demo', name: 'Synthetic Astronaut', role: 'demo' } });
  });
  app.use('/api', (req, res, next) => {
    const token = (req.get('Authorization') || '').replace(/^Bearer /, '');
    const session = sessions.get(token);
    if (!session || session.expiresAt <= now()) { sessions.delete(token); return res.status(401).json({ message: 'Preview session expired. Start the demo again.' }); }
    session.expiresAt = Math.min(now() + idleTimeoutMs, session.maxExpiresAt);
    req.demo = session;
    req.demoToken = token;
    req.user = { _id: 'synthetic-demo', role: 'astronaut' };
    next();
  });
  app.post('/api/auth/logout', (req, res) => { sessions.delete(req.demoToken); res.json({ success: true }); });
  app.get('/api/users/me', (_req, res) => res.json({ data: { user: { id: 'synthetic-demo', name: 'Synthetic Astronaut', role: 'demo' } } }));
  app.get('/api/dashboard/overview', (req, res) => res.json({ data: { totalMeasurements: req.demo.measurements.length, unreadAlerts: req.demo.alerts.filter(a => !a.isRead).length, latestMeasurement: req.demo.measurements[0] || null } }));
  app.get('/api/measurements', (req, res) => res.json({ data: req.demo.measurements.slice(0, 100) }));
  // Preview only allows the fixed sample entries, so no personal health data can be entered.
  app.post('/api/measurements', (_req, res) => res.status(403).json({ message: 'Adding measurements is disabled in the synthetic preview.' }));
  app.get('/api/alerts', (req, res) => res.json({ data: req.demo.alerts }));
  app.patch('/api/alerts/:id/read', (req, res) => {
    const alert = req.demo.alerts.find(a => a._id === req.params.id);
    if (!alert) return res.status(404).json({ message: 'Alert not found.' });
    alert.isRead = true; res.json({ data: alert });
  });
  app.get('/api/reports', (req, res) => {
    const period = req.query.period || 'weekly';
    const days = { daily: 1, weekly: 7, monthly: 30 }[period];
    if (!days) return res.status(400).json({ message: 'Invalid period.' });
    const entries = req.demo.measurements.filter(m => Date.parse(m.measuredAt) >= now() - days * 86400000);
    const avg = key => entries.length ? entries.reduce((sum, m) => sum + m[key], 0) / entries.length : null;
    return res.json({ data: { period, summary: { records: entries.length, avgHeartRate: avg('heartRate'), avgSpo2: avg('spo2'), avgTemperature: avg('temperature'), totalSleepMinutes: 0, totalSteps: 0 } } });
  });
  app.get('/api/cognitive-state/status', getCognitiveStateStatus);
  app.post('/api/cognitive-state/analyze', (req, res, next) => {
    if (req.body?.mode !== 'synthetic_demo' || req.body?.dataProvenance !== 'synthetic') return res.status(400).json({ message: 'Only synthetic demo mode is supported in preview.' });
    return analyzeCognitiveState(req, res, next);
  });
  app.use((_req, res) => res.status(404).json({ message: 'Not available in synthetic preview.' }));
  return app;
}

if (require.main === module) {
  if (process.env.ORBITCARE_SYNTHETIC_PREVIEW !== '1' || process.env.NODE_ENV === 'production') {
    console.error('Synthetic preview requires ORBITCARE_SYNTHETIC_PREVIEW=1 and must not run in production.');
    process.exit(1);
  }
  createPreviewApp().listen(5000, '127.0.0.1', () => console.log('Synthetic preview API listening on 127.0.0.1:5000 (in-memory only).'));
}
module.exports = { createPreviewApp };
