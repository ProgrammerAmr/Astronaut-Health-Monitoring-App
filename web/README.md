# OrbitCare web frontend

A browser frontend replacing Flutter for this workflow. It talks to the existing Node API through same-origin `/api` requests. The Node API proxies the authenticated, experimental CSM research calls to the Python service; the browser does not call Python directly. No real or demo measurements are fabricated by the frontend.

## Local setup

1. Start MongoDB. Configure `backend/.env` using `backend/.env.example`: set `MONGO_URI`, a strong `JWT_SECRET`, and `CSM_AI_SERVICE_URL=http://127.0.0.1:8000`. Then run `cd backend && npm ci && npm run dev`.
2. Start the Python AI service as documented in the root README: `cd AI_training`, install the Python dependencies, then run `uvicorn ai_service:app --host 127.0.0.1 --port 8000`.
3. From `web/`, run `npm ci && npm run dev`. Open the Vite URL. Vite proxies `/api` to `http://127.0.0.1:5000` on the **server**, not in the browser. If the backend is elsewhere, start Vite with `ORBITCARE_BACKEND_URL=http://host:port npm run dev`.
4. Register and verify via email (or backend console OTP in development), or seed the explicitly synthetic demo account with `cd backend && npm run seed:demo` and use the password printed by the seed script.

Login tokens are held in `sessionStorage` and sent as Bearer tokens to the backend; closing the tab clears the session. Don't use real patient data in this prototype. Run over HTTPS outside local development. Before production, use a hardened auth/session design, an explicit host allowlist, security headers and a same-origin reverse proxy to the Node API. `npm run build` produces static files; `vite preview` does **not** proxy `/api` and is not a production server. Configure the deployment server to route `/api/*` to Node and serve the built SPA for other routes.

The AI card uses `/api/cognitive-state/status` and `/api/cognitive-state/analyze` (synthetic demo only). The CSM service is experimental, non-diagnostic, and has no bundled validated model. It can return `INSUFFICIENT_DATA`, and never generates alerts. If it is unavailable, the UI shows the error instead of fabricating a result. The separate `/analyze` vitals rules endpoint is not exposed by the Node API and is not called from the browser.

## Checks

```sh
npm test
npm run build
```

## Connection troubleshooting

The web server by itself is **not** the backend. A Vite proxy error or “Cannot connect to the backend” means the Node API is not reachable at the configured server-side address. First start MongoDB and then Node, and verify the backend before using the web login. For example, with Docker available locally:

```sh
docker run -d --name orbitcare-mongo -p 27017:27017 mongo:7
cd backend
cp .env.example .env
```

Edit `backend/.env`: set `MONGO_URI=mongodb://127.0.0.1:27017/orbitcare` and `JWT_SECRET` to a long random secret. Set `CSM_AI_SERVICE_URL=http://127.0.0.1:8000` if the AI service runs on the same machine. Then:

```sh
npm ci
npm run dev
# In a second terminal, check:
curl http://127.0.0.1:5000/api/health
```

If Node cannot start, read its terminal output and check MongoDB and `.env`. Once the health check works, start the web server as above and register/verify or seed the demo account. `ORBITCARE_BACKEND_URL` must be reachable from the machine running Vite. For a deployed frontend, configure the hosting reverse proxy to forward `/api` to Node; Vite's development proxy does not exist in a static deployment. An HTML response at `/api` usually means the host is serving the frontend fallback instead of forwarding the API request.

The AI service is separate: start it and set `CSM_AI_SERVICE_URL` to enable the experimental CSM card. Its absence does not prevent login, but will display a service-unavailable message on the card.
