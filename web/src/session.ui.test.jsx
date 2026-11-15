// @vitest-environment jsdom
import React from 'react';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';

let App;
let requests;
let validTokens;
let sessionCount;
const response = (status, json) => ({ ok: status >= 200 && status < 300, status, json: async () => json });

beforeEach(async () => {
  vi.resetModules();
  vi.stubEnv('VITE_ORBITCARE_SYNTHETIC_DEMO', '1');
  sessionStorage.clear(); localStorage.clear();
  requests = [];
  validTokens = new Set();
  sessionCount = 0;
  vi.stubGlobal('fetch', vi.fn(async (url, options) => {
    const token = options.headers['X-OrbitCare-Demo-Token'] || options.headers.Authorization?.replace('Bearer ', '');
    requests.push({url, token});
    if (url === '/api/demo/session') { const token = `token-${++sessionCount}`; validTokens.add(token); return response(200, { token, user: { name:'Synthetic Astronaut' } }); }
    if (!validTokens.has(token)) return response(401, { message:'Preview session expired' });
    if (url === '/api/auth/logout') { validTokens.delete(token); return response(200, {}); }
    if (url === '/api/users/me') return response(200, { data:{user:{name:'Synthetic Astronaut'}} });
    if (url === '/api/dashboard/overview') return response(200, { data:{} });
    if (url === '/api/measurements?limit=100' || url === '/api/alerts') return response(200, {data:[]});
    if (url.startsWith('/api/reports')) return response(200, {data:{summary:{}}});
    if (url === '/api/cognitive-state/status') return response(200, {registered_model_available:false});
    throw new Error(`Unexpected URL: ${url}`);
  }));
  App = (await import('./App.jsx')).default;
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); vi.unstubAllEnvs(); });

test('keeps the demo session across remounts and exits only on explicit sign out', async () => {
  const view = render(<App/>);
  fireEvent.click(screen.getByText('Open synthetic demo'));
  await screen.findByText('SYNTHETIC PREVIEW');
  await waitFor(() => expect(requests.some(r => r.url === '/api/users/me')).toBe(true));
  expect(localStorage.getItem('orbitcare_preview_token')).toBe('token-1');
  view.unmount();
  render(<App/>);
  await screen.findByText('SYNTHETIC PREVIEW');
  await waitFor(() => expect(requests.filter(r => r.url === '/api/users/me').length).toBeGreaterThanOrEqual(2));
  expect(sessionCount).toBe(1);
  fireEvent.click(screen.getByText('Sign out'));
  await screen.findByText('Open synthetic demo');
  expect(localStorage.getItem('orbitcare_preview_token')).toBeNull();
});

test('recovers an invalidated preview session without bouncing out', async () => {
  localStorage.setItem('orbitcare_preview_token', 'old-token');
  render(<App/>);
  await screen.findByText(/temporary demo session was restarted/);
  await waitFor(() => expect(localStorage.getItem('orbitcare_preview_token')).toBe('token-1'));
  expect(screen.getByText('SYNTHETIC PREVIEW')).toBeTruthy();
  expect(sessionCount).toBe(1);
});

test('stale in-flight requests cannot undo a new session after sign out', async () => {
  const originalFetch = globalThis.fetch;
  let releaseOldProfile;
  const oldProfile = new Promise(resolve => { releaseOldProfile = resolve; });
  vi.stubGlobal('fetch', vi.fn((url, options) => {
    if (url === '/api/users/me' && options.headers['X-OrbitCare-Demo-Token'] === 'token-1') return oldProfile;
    return originalFetch(url, options);
  }));
  render(<App/>);
  fireEvent.click(screen.getByText('Open synthetic demo'));
  await screen.findByText('SYNTHETIC PREVIEW');
  await waitFor(() => expect(fetch.mock.calls.some(([url, opts]) => url === '/api/users/me' && opts.headers['X-OrbitCare-Demo-Token'] === 'token-1')).toBe(true));
  fireEvent.click(screen.getByText('Sign out'));
  await screen.findByText('Open synthetic demo');
  fireEvent.click(screen.getByText('Open synthetic demo'));
  await screen.findByText('SYNTHETIC PREVIEW');
  await waitFor(() => expect(localStorage.getItem('orbitcare_preview_token')).toBe('token-2'));
  releaseOldProfile(response(401, {message:'Old session expired'}));
  await waitFor(() => expect(requests.some(r => r.url === '/api/users/me' && r.token === 'token-2')).toBe(true));
  expect(localStorage.getItem('orbitcare_preview_token')).toBe('token-2');
  expect(screen.getByText('SYNTHETIC PREVIEW')).toBeTruthy();
});

test('a failed preview recovery stays on the dashboard and allows reconnect', async () => {
  localStorage.setItem('orbitcare_preview_token', 'expired');
  const normalFetch = globalThis.fetch;
  let allowRecovery = false;
  vi.stubGlobal('fetch', vi.fn((url, options) => {
    if (url === '/api/demo/session' && !allowRecovery) return Promise.resolve(response(503, {message:'Preview temporarily unavailable'}));
    return normalFetch(url, options);
  }));
  render(<App/>);
  await screen.findByText(/Could not reconnect the preview/);
  expect(screen.getByText('SYNTHETIC PREVIEW')).toBeTruthy();
  expect(screen.queryByText('Open synthetic demo')).toBeNull();
  allowRecovery = true;
  fireEvent.click(screen.getByText('Reconnect demo'));
  await waitFor(() => expect(localStorage.getItem('orbitcare_preview_token')).toBe('token-1'));
  expect(screen.getByText('SYNTHETIC PREVIEW')).toBeTruthy();
});
