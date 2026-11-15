/**
 * Regression tests for the two failures that most often look like
 * "the app cannot connect / cannot get past login":
 *
 *  1. A development backend without JWT_SECRET used to sign tokens at login
 *     (or throw a 500) and then reject every authenticated request, because
 *     the auth middleware verified with `process.env.JWT_SECRET` only.
 *  2. GET /api/users/me nests the profile under `data.user`; the mobile client
 *     must receive a usable id/name/email there or session restore shows a
 *     blank "Astronaut" profile.
 */

const { describe, it, before, after } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const jwt = require("jsonwebtoken");

// Simulate a fresh checkout: developer copied .env.example or has no .env at all.
delete process.env.JWT_SECRET;
delete process.env.MONGO_URI;
delete process.env.NODE_ENV;

const User = require("../src/models/User");
const app = require("../server");
const createToken = require("../src/utils/token");
const { resolveJwtSecret, DEV_FALLBACK_SECRET } = require("../src/utils/token");

const USER_ID = "507f1f77bcf86cd799439055";
const PROFILE = {
  _id: USER_ID,
  name: "Nova Lin",
  email: "nova@example.test",
  role: "astronaut",
  mission: {
    name: "Synthetic Demo Mission",
    role: "Flight Engineer",
    status: "Simulation Active",
  },
};

async function requestJson(baseUrl, path, { token } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(`${baseUrl}${path}`, { headers });
  const json = await response.json().catch(() => null);
  return { status: response.status, json };
}

describe("Development JWT fallback and profile contract", () => {
  let server;
  let baseUrl;
  const originalFindById = User.findById;

  before(async () => {
    User.findById = async (id) => (String(id) === USER_ID ? { ...PROFILE } : null);
    server = http.createServer(app);
    await new Promise((resolve) => {
      server.listen(0, "127.0.0.1", resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(async () => {
    User.findById = originalFindById;
    await new Promise((resolve) => server.close(resolve));
  });

  it("falls back to a development signing secret when JWT_SECRET is unset", () => {
    assert.equal(resolveJwtSecret(), DEV_FALLBACK_SECRET);
    const token = createToken({ _id: USER_ID, role: "astronaut" });
    const decoded = jwt.verify(token, DEV_FALLBACK_SECRET);
    assert.equal(decoded.id, USER_ID);
  });

  it("requires JWT_SECRET in production instead of using the fallback", () => {
    process.env.NODE_ENV = "production";
    try {
      assert.throws(() => resolveJwtSecret(), /JWT_SECRET is required in production/);
    } finally {
      delete process.env.NODE_ENV;
    }
  });

  it("accepts the token it just issued on a protected route (no silent 401 loop)", async () => {
    const token = createToken({ _id: USER_ID, role: "astronaut" });
    const me = await requestJson(baseUrl, "/api/users/me", { token });

    assert.equal(me.status, 200, JSON.stringify(me.json));
    assert.equal(me.json.status, "success");
    assert.ok(me.json.data, "response must include data");
    assert.ok(me.json.data.user, "profile must be nested under data.user");
    assert.equal(me.json.data.user.email, PROFILE.email);
    assert.equal(me.json.data.user.name, PROFILE.name);
  });

  it("rejects a token signed with a different secret", async () => {
    const foreign = jwt.sign({ id: USER_ID, role: "astronaut" }, "another-secret");
    const res = await requestJson(baseUrl, "/api/users/me", { token: foreign });
    assert.equal(res.status, 401);
  });

  it("rejects requests without a bearer token", async () => {
    const res = await requestJson(baseUrl, "/api/users/me");
    assert.equal(res.status, 401);
    assert.equal(res.json.message, "Please login first");
  });

  it("keeps /api/health public and reports the database state", async () => {
    const res = await requestJson(baseUrl, "/api/health");
    assert.equal(res.status, 200);
    assert.equal(res.json.success, true);
    assert.equal(res.json.message, "OrbitCare API is running");
    assert.equal(typeof res.json.database, "string");
  });
});
