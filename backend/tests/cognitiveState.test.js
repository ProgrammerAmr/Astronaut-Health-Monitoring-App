const { describe, it, before, after, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const jwt = require("jsonwebtoken");

// Configure test JWT secret before loading app/middleware
const TEST_JWT_SECRET = "test-only-ephemeral-jwt-secret-dec001";
process.env.JWT_SECRET = TEST_JWT_SECRET;

const User = require("../src/models/User");
const app = require("../server");

const USERS = {
  "507f1f77bcf86cd799439011": {
    _id: "507f1f77bcf86cd799439011",
    name: "Astronaut One",
    email: "astro1@example.test",
    role: "astronaut",
  },
  "507f1f77bcf86cd799439012": {
    _id: "507f1f77bcf86cd799439012",
    name: "Astronaut Two",
    email: "astro2@example.test",
    role: "astronaut",
  },
  "507f1f77bcf86cd799439099": {
    _id: "507f1f77bcf86cd799439099",
    name: "Flight Admin",
    email: "admin@example.test",
    role: "admin",
  },
};

function makeToken(userId) {
  return jwt.sign({ id: userId }, TEST_JWT_SECRET, { expiresIn: "1h" });
}

function listenServer(server) {
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => {
      const addr = server.address();
      resolve(`http://127.0.0.1:${addr.port}`);
    });
  });
}

function closeServer(server) {
  return new Promise((resolve) => server.close(() => resolve()));
}

async function apiRequest(baseUrl, path, { method = "GET", token, body, rawBody } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  let payload;
  if (rawBody !== undefined) {
    headers["Content-Type"] = "application/json";
    payload = rawBody;
  } else if (body !== undefined) {
    headers["Content-Type"] = "application/json";
    payload = JSON.stringify(body);
  }
  const resp = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    body: payload,
  });
  const text = await resp.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = null;
  }
  return { status: resp.status, json, text };
}

describe("DEC-001 Authenticated Node Cognitive State Integration", () => {
  let appServer;
  let appBaseUrl;
  let mockUpstreamServer;
  let mockUpstreamUrl;
  let upstreamMode = "normal";
  let lastUpstreamBody = null;
  const origFindById = User.findById;

  before(async () => {
    // Stub User.findById so JWT protect works without live MongoDB
    User.findById = async (id) => USERS[String(id)] || null;

    appServer = http.createServer(app);
    appBaseUrl = await listenServer(appServer);

    mockUpstreamServer = http.createServer((req, res) => {
      let raw = "";
      req.on("data", (chunk) => {
        raw += chunk;
      });
      req.on("end", () => {
        if (upstreamMode === "slow") {
          setTimeout(() => {
            if (!res.writableEnded) {
              res.writeHead(200, { "Content-Type": "application/json" });
              res.end(JSON.stringify({ service_available: true }));
            }
          }, 1500);
          return;
        }
        if (upstreamMode === "error500") {
          res.writeHead(500, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ detail: "upstream boom" }));
          return;
        }
        if (req.method === "GET" && req.url === "/csm/status") {
          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(
            JSON.stringify({
              api_version: "v1",
              schema_version: "1.0-dec001-draft",
              service_available: true,
              registered_model_available: false,
              live_sensor_enabled: false,
              raw_signal_persistence: false,
              supported_modes: ["synthetic_demo", "research_replay"],
              model_status: {
                model_id: null,
                validated: false,
                calibrated: false,
              },
            })
          );
          return;
        }
        if (req.method === "POST" && req.url === "/csm/analyze") {
          lastUpstreamBody = JSON.parse(raw || "{}");
          const isDemo = lastUpstreamBody.mode === "synthetic_demo";
          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(
            JSON.stringify({
              schema_version: "1.0-dec001-draft",
              api_version: "v1",
              status: "INSUFFICIENT_DATA",
              mode: lastUpstreamBody.mode,
              demo_mode: isDemo,
              astronaut_id: lastUpstreamBody.astronaut_id,
              session_id: lastUpstreamBody.session_id || null,
              data_provenance: isDemo ? "synthetic" : "real_nasa_csm_replay",
              prediction: {
                state: null,
                probabilities: null,
                confidence: null,
                abstained: true,
              },
              signal_quality: {
                valid: true,
                sqi_score: 0.92,
                reasons: [
                  isDemo
                    ? "SYNTHETIC_DEMO_NO_MODEL_PROBABILITIES"
                    : "NO_REGISTERED_MODEL_ARTIFACT",
                ],
              },
              model_status: {
                model_id: null,
                validated: false,
                calibrated: false,
              },
              warnings: isDemo
                ? ["Synthetic demo data: no real telemetry and no model."]
                : ["No registered model artifact."],
              errors: [],
              disclaimer:
                "Experimental research prototype — not a medical diagnosis or flight-certified system.",
            })
          );
          return;
        }
        res.writeHead(404);
        res.end();
      });
    });
    mockUpstreamUrl = await listenServer(mockUpstreamServer);
  });

  after(async () => {
    User.findById = origFindById;
    await closeServer(appServer);
    await closeServer(mockUpstreamServer);
  });

  beforeEach(() => {
    upstreamMode = "normal";
    lastUpstreamBody = null;
    process.env.CSM_AI_SERVICE_URL = mockUpstreamUrl;
    process.env.CSM_AI_TIMEOUT_MS = "500";
  });

  it("preserves existing /api/health endpoint", async () => {
    const res = await apiRequest(appBaseUrl, "/api/health");
    assert.equal(res.status, 200);
    assert.equal(res.json.success, true);
  });

  it("blocks unauthenticated requests with 401", async () => {
    const rStatus = await apiRequest(appBaseUrl, "/api/cognitive-state/status");
    assert.equal(rStatus.status, 401);

    const rAnalyze = await apiRequest(appBaseUrl, "/api/cognitive-state/analyze", {
      method: "POST",
      body: { mode: "synthetic_demo" },
    });
    assert.equal(rAnalyze.status, 401);
  });

  it("enforces non-admin user ownership (403 on other astronautId; allows self and admin)", async () => {
    const astro1Token = makeToken("507f1f77bcf86cd799439011");
    const adminToken = makeToken("507f1f77bcf86cd799439099");

    // Non-admin trying to access another astronaut -> 403
    const forbidden = await apiRequest(appBaseUrl, "/api/cognitive-state/analyze", {
      method: "POST",
      token: astro1Token,
      body: {
        mode: "synthetic_demo",
        astronautId: "507f1f77bcf86cd799439012",
      },
    });
    assert.equal(forbidden.status, 403);
    assert.equal(forbidden.json.errors[0].code, "FORBIDDEN_ASTRONAUT_ACCESS");
    assert.equal(forbidden.json.prediction.abstained, true);

    // Non-admin omitting astronautId defaults to own ID -> 200
    const ownSelf = await apiRequest(appBaseUrl, "/api/cognitive-state/analyze", {
      method: "POST",
      token: astro1Token,
      body: { mode: "synthetic_demo", sessionId: "demo-self" },
    });
    assert.equal(ownSelf.status, 200);
    assert.equal(lastUpstreamBody.astronaut_id, "507f1f77bcf86cd799439011");
    assert.equal(ownSelf.json.data_provenance, "synthetic");
    assert.equal(ownSelf.json.model_status.validated, false);

    // Admin accessing another astronaut -> 200
    const adminReq = await apiRequest(appBaseUrl, "/api/cognitive-state/analyze", {
      method: "POST",
      token: adminToken,
      body: {
        mode: "research_replay",
        astronautId: "507f1f77bcf86cd799439012",
        signalQuality: { valid: true, sqi_score: 0.9 },
      },
    });
    assert.equal(adminReq.status, 200);
    assert.equal(lastUpstreamBody.astronaut_id, "507f1f77bcf86cd799439012");
    assert.equal(adminReq.json.status, "INSUFFICIENT_DATA");
  });

  it("validates fields strictly: rejects live_sensor, raw signals, unknown fields, and >32kb payloads", async () => {
    const token = makeToken("507f1f77bcf86cd799439011");

    const liveMode = await apiRequest(appBaseUrl, "/api/cognitive-state/analyze", {
      method: "POST",
      token,
      body: { mode: "live_sensor" },
    });
    assert.equal(liveMode.status, 400);
    assert.equal(liveMode.json.errors[0].code, "LIVE_SENSOR_UNSUPPORTED");

    const liveProv = await apiRequest(appBaseUrl, "/api/cognitive-state/analyze", {
      method: "POST",
      token,
      body: { mode: "research_replay", dataProvenance: "live_sensor" },
    });
    assert.equal(liveProv.status, 400);
    assert.equal(liveProv.json.errors[0].code, "LIVE_SENSOR_UNSUPPORTED");

    const rawSignals = await apiRequest(appBaseUrl, "/api/cognitive-state/analyze", {
      method: "POST",
      token,
      body: { mode: "research_replay", eeg: [1, 2, 3] },
    });
    assert.equal(rawSignals.status, 400);
    assert.equal(rawSignals.json.errors[0].code, "RAW_SIGNAL_NOT_ACCEPTED");

    const badMode = await apiRequest(appBaseUrl, "/api/cognitive-state/analyze", {
      method: "POST",
      token,
      body: { mode: "diagnostic_mode" },
    });
    assert.equal(badMode.status, 400);
    assert.equal(badMode.json.errors[0].code, "INVALID_MODE");

    const oversized = await apiRequest(appBaseUrl, "/api/cognitive-state/analyze", {
      method: "POST",
      token,
      body: {
        mode: "synthetic_demo",
        signalQuality: { valid: true, reasons: ["a".repeat(36000)] },
      },
    });
    assert.equal(oversized.status, 413);
    assert.equal(oversized.json.errors[0].code, "PAYLOAD_TOO_LARGE");
  });

  it("returns safe status and limitations from GET /api/cognitive-state/status", async () => {
    const token = makeToken("507f1f77bcf86cd799439011");
    const res = await apiRequest(appBaseUrl, "/api/cognitive-state/status", {
      token,
    });
    assert.equal(res.status, 200);
    assert.equal(res.json.service_available, true);
    assert.equal(res.json.model_status.validated, false);
    assert.equal(res.json.live_sensor_enabled, false);
    assert.ok(Array.isArray(res.json.limitations) && res.json.limitations.length >= 3);
    assert.match(res.json.disclaimer, /not a medical diagnosis/i);
  });

  it("maps unconfigured URL, timeout, unreachable upstream, and 500 to safe error responses with no substituted prediction", async () => {
    const token = makeToken("507f1f77bcf86cd799439011");

    // 1. Unconfigured URL (no hardcoded localhost fallback)
    delete process.env.CSM_AI_SERVICE_URL;
    delete process.env.AI_SERVICE_URL;
    const unconf = await apiRequest(appBaseUrl, "/api/cognitive-state/analyze", {
      method: "POST",
      token,
      body: { mode: "synthetic_demo" },
    });
    assert.equal(unconf.status, 503);
    assert.equal(unconf.json.status, "ERROR");
    assert.equal(unconf.json.errors[0].code, "CSM_SERVICE_UNCONFIGURED");
    assert.equal(unconf.json.prediction.probabilities, null);
    assert.equal(unconf.json.prediction.abstained, true);

    // 2. Upstream timeout -> 504
    process.env.CSM_AI_SERVICE_URL = mockUpstreamUrl;
    process.env.CSM_AI_TIMEOUT_MS = "500";
    upstreamMode = "slow";
    const timedOut = await apiRequest(appBaseUrl, "/api/cognitive-state/analyze", {
      method: "POST",
      token,
      body: { mode: "synthetic_demo" },
    });
    assert.equal(timedOut.status, 504);
    assert.equal(timedOut.json.status, "ERROR");
    assert.equal(timedOut.json.errors[0].code, "CSM_UPSTREAM_TIMEOUT");
    assert.equal(timedOut.json.prediction.probabilities, null);

    // 3. Upstream 500 -> 502 safe error
    upstreamMode = "error500";
    const upstreamErr = await apiRequest(appBaseUrl, "/api/cognitive-state/analyze", {
      method: "POST",
      token,
      body: { mode: "synthetic_demo" },
    });
    assert.equal(upstreamErr.status, 502);
    assert.equal(upstreamErr.json.status, "ERROR");
    assert.equal(upstreamErr.json.prediction.probabilities, null);

    // 4. Unreachable port -> 503 safe error
    process.env.CSM_AI_SERVICE_URL = "http://127.0.0.1:1";
    const unreachable = await apiRequest(appBaseUrl, "/api/cognitive-state/status", {
      token,
    });
    assert.equal(unreachable.status, 503);
    assert.equal(unreachable.json.service_available, false);
    assert.equal(unreachable.json.errors[0].code, "CSM_UPSTREAM_UNAVAILABLE");
  });
});
