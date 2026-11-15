# OrbitCare — Astronaut Health Monitoring App

An end-to-end hackathon prototype for astronaut health tracking, operational alerts, periodic wellness summaries, and experimental DEC-001 Cognitive State Monitoring (CSM) research integration.

> **Important Prototype & Safety Notice**
> - **Hackathon prototype — NOT a clinical, diagnostic, or flight-certified medical product.**
> - The **DEC-001 Cognitive State Monitoring (CSM)** module is **experimental and non-diagnostic**. No trained, medically validated, operational, or astronaut-validated CSM model artifact is claimed or bundled; the service abstains safely (`INSUFFICIENT_DATA`) and never invents probabilities or generates clinical alerts.
> - Synthetic/demo data is permitted only when visibly labeled synthetic/demo and contains zero real personal health data.

---

## Architecture Overview

| Component | Directory | Stack | Purpose |
|---|---|---|---|
| **Mobile App** | `Flutter/` | Flutter (Dart 3), `flutter_secure_storage` | Auth (signup/OTP/login/password reset/logout), JWT secure session restore, dashboard overview, vitals history & creation, alert acknowledgement, reports, and DEC-001 CSM research card |
| **API Backend** | `backend/` | Node.js, Express, MongoDB/Mongoose, JWT | Authentication & OTP verification, user-scoped measurements, dashboard stats, alerts, reports, and authenticated CSM proxy (`/api/cognitive-state/*`) |
| **AI & CSM Service** | `AI_training/` | Python 3.11+, FastAPI, scikit-learn/SciPy | Vitals rule engine + optional Ollama RAG (`/health`, `/analyze`) and isolated DEC-001 CSM governance/service endpoints (`/csm/status`, `/csm/analyze`) |

---

## Quick Start & Local Competition Demo Setup

### Prerequisites
- **Node.js** 20+ (tested on Node 22)
- **MongoDB** (local Community Server via `mongod`, Docker `mongo:7`, or a personal MongoDB URI)
- **Python** 3.11+
- **Flutter SDK** (stable channel, Dart `>=3.7.0 <4.0.0`)

---

### 1. Start MongoDB & Configure Node Backend

```bash
cd backend
cp .env.example .env
```

Edit `backend/.env` locally (never commit `.env`):
- `MONGO_URI=mongodb://127.0.0.1:27017/orbitcare`
- `JWT_SECRET=<replace-with-random-secret>`
- `CSM_AI_SERVICE_URL=http://127.0.0.1:8000`
- `SMTP_*`: optional for local dev — when unset in non-production, signup/reset OTP codes print directly to the backend console (`[DEVELOPMENT OTP]`).

Install dependencies and start the backend:

```bash
npm install
npm run dev
# Health check: curl http://127.0.0.1:5000/api/health
```

#### Optional: Seed Clearly Labeled Synthetic Demo Data
To populate a local demo astronaut account with 5 synthetic vitals entries and 2 synthetic non-CSM demonstration alerts (zero real personal data):

```bash
cd backend
npm run seed:demo
```

This creates/refreshes:
- **Email:** `demo.astronaut@orbitcare.local`
- **Password:** value of `DEMO_USER_PASSWORD` in `.env` (or the default printed to stdout by the script)

---

### 2. Start the Python AI & DEC-001 CSM Service

```bash
cd AI_training
python3 -m venv .venv
source .venv/bin/activate
pip install fastapi uvicorn python-dotenv numpy scipy scikit-learn pytest httpx
uvicorn ai_service:app --host 127.0.0.1 --port 8000
```

Verify service health:
- `GET http://127.0.0.1:8000/health` (existing vitals service)
- `GET http://127.0.0.1:8000/csm/status` (DEC-001 CSM status & validation limitations)

> Note: Running `/csm/status` and `/csm/analyze` does **not** require Ollama, ChromaDB, or raw NASA archives.

---

### 3. Run the Flutter Mobile App

Never hardcode server hostnames in Dart source; pass the backend URL at run/build time via `--dart-define`:

```bash
cd Flutter
flutter pub get

# Android Emulator (reaches host machine via 10.0.2.2)
flutter run --dart-define=ORBITCARE_API_BASE_URL=http://10.0.2.2:5000

# iOS Simulator / macOS / Linux / Desktop
flutter run --dart-define=ORBITCARE_API_BASE_URL=http://127.0.0.1:5000
```

---

## Competition Demo Walkthrough

1. **Authentication & Session Persistence**
   - Sign in with the seeded synthetic demo account (`demo.astronaut@orbitcare.local`) **or** create a new account via **Sign Up** -> read the `[DEVELOPMENT OTP]` code from the backend terminal -> verify on the OTP screen.
   - Restart the app to demonstrate secure JWT session restoration on the Splash screen (`GET /api/users/me`).
2. **Overview & Authenticated DEC-001 CSM Research Card**
   - Review total measurements, unread alert count, and latest vitals snapshot with units and timestamps.
   - Inspect the **Cognitive State Monitoring (DEC-001 RESEARCH)** card: it calls `/api/cognitive-state/status` using the authenticated JWT, clearly displays the experimental non-diagnostic disclaimer, abstains safely (`INSUFFICIENT_DATA`) when no validated model artifact exists, and separates explicitly labeled **Synthetic Demo** from **Research Replay**.
3. **Vitals History & Creation**
   - Open the **Vitals** tab to inspect recorded vitals history, then tap **Log Vitals** to submit new validated measurements (`POST /api/measurements`) and watch Overview + History + Reports update immediately.
4. **Alerts & Acknowledgement**
   - Open the **Alerts** tab, filter **All / Unread**, and tap **Mark as Read** (`PATCH /api/alerts/:id/read`) to acknowledge an alert and decrement the unread badge.
5. **Periodic Reports & Logout**
   - Open the **Reports** tab to switch between **Daily**, **Weekly**, and **Monthly** aggregated summaries (`GET /api/reports?period=...`).
   - Tap the **Sign Out** icon to clear secure storage and return to the Login screen.

---

## Automated Verification & CI

All suites run automatically via `.github/workflows/ci.yml` without secrets, NASA downloads, cloud databases, or Ollama:

```bash
# 1. Python vitals & DEC-001 CSM tests
pytest -v AI_training/test_nasa_claude.py AI_training/csm/tests/

# 2. Node.js auth, ownership, validation, and CSM proxy tests
cd backend && npm test

# 3. Flutter static analysis and unit/widget tests
cd Flutter && flutter pub get && flutter analyze && flutter test
```

---

## DEC-001 CSM Scope & Limitations

- Based on NASA `OSD-431` / `DEC-001` ground-based aviation cognitive state research metadata (not orbital spaceflight telemetry).
- Raw NASA physiological archive ZIPs and trained model artifacts are intentionally excluded from Git.
- Live wearable/sensor streaming (`mode: "live_sensor"`) and raw physiological waveforms are rejected by backend validation.
- Detailed documentation: [`backend/API_DOCUMENTATION.md`](backend/API_DOCUMENTATION.md) and [`AI_training/csm/README.md`](AI_training/csm/README.md).

---

## Web frontend (بديل Flutter)

A standalone browser frontend is available in [`web/`](web/README.md). It connects to the existing Node API and its authenticated experimental CSM AI proxy. For local setup, start MongoDB, the Node backend, and the Python AI service as described above, then:

```bash
cd web
npm ci
npm run dev
```

Open the URL printed by Vite. The development proxy sends same-origin `/api` requests to the backend; set `ORBITCARE_BACKEND_URL` for a different backend address. See the web README for deployment, authentication, AI limitations, and troubleshooting. This branch is based on `test` at `b4ad28b`, not the later connectivity changes merged from the linked branch into `main`.
