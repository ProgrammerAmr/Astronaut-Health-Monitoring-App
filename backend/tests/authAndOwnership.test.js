const { describe, it, before, after, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const jwt = require("jsonwebtoken");

const TEST_JWT_SECRET = "test-only-ephemeral-jwt-secret-auth-ownership";
process.env.JWT_SECRET = TEST_JWT_SECRET;

const User = require("../src/models/User");
const Otp = require("../src/models/Otp");
const Measurement = require("../src/models/Measurement");
const Alert = require("../src/models/Alert");
const { hashOtp } = require("../src/utils/otp");
const app = require("../server");

const ASTRO_1_ID = "507f1f77bcf86cd799439011";
const ASTRO_2_ID = "507f1f77bcf86cd799439012";
const ADMIN_ID = "507f1f77bcf86cd799439099";
const MEAS_1_ID = "607f1f77bcf86cd799439001";
const MEAS_2_ID = "607f1f77bcf86cd799439002";
const ALERT_1_ID = "707f1f77bcf86cd799439001";
const ALERT_2_ID = "707f1f77bcf86cd799439002";

function makeToken(userId, role = "astronaut") {
  return jwt.sign({ id: userId, role }, TEST_JWT_SECRET, { expiresIn: "1h" });
}

function listenServer(server) {
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => {
      resolve(`http://127.0.0.1:${server.address().port}`);
    });
  });
}

function closeServer(server) {
  return new Promise((resolve) => server.close(() => resolve()));
}

async function reqJson(baseUrl, path, { method = "GET", token, body } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  let payload;
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
    payload = JSON.stringify(body);
  }
  const resp = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    body: payload,
  });
  const json = await resp.json().catch(() => null);
  return { status: resp.status, json };
}

describe("OrbitCare Auth, Validation, and User Ownership Enforcement", () => {
  let server;
  let baseUrl;

  // In-memory mock stores
  let usersById;
  let usersByEmail;
  let otps;
  let measurements;
  let alerts;

  const orig = {
    userFindById: User.findById,
    userFindOne: User.findOne,
    userCreate: User.create,
    otpFindOne: Otp.findOne,
    otpCreate: Otp.create,
    otpDeleteOne: Otp.deleteOne,
    otpDeleteMany: Otp.deleteMany,
    measFind: Measurement.find,
    measFindOne: Measurement.findOne,
    measCreate: Measurement.create,
    measCount: Measurement.countDocuments,
    measAgg: Measurement.aggregate,
    measUpdate: Measurement.findOneAndUpdate,
    measDelete: Measurement.findOneAndDelete,
    alertFind: Alert.find,
    alertCount: Alert.countDocuments,
    alertUpdate: Alert.findOneAndUpdate,
  };

  function makeUserRecord(raw) {
    return {
      ...raw,
      comparePassword: async (candidate) => candidate === raw.plainPassword,
      save: async function save() {
        usersById[String(this._id)] = this;
        usersByEmail[this.email] = this;
        return this;
      },
    };
  }

  function resetStores() {
    const u1 = makeUserRecord({
      _id: ASTRO_1_ID,
      name: "Astronaut One",
      email: "astro1@example.test",
      plainPassword: "Password!1",
      isVerified: true,
      role: "astronaut",
    });
    const u2 = makeUserRecord({
      _id: ASTRO_2_ID,
      name: "Astronaut Two",
      email: "astro2@example.test",
      plainPassword: "Password!2",
      isVerified: false,
      role: "astronaut",
    });
    const admin = makeUserRecord({
      _id: ADMIN_ID,
      name: "Mission Admin",
      email: "admin@example.test",
      plainPassword: "AdminPass!1",
      isVerified: true,
      role: "admin",
    });
    usersById = { [ASTRO_1_ID]: u1, [ASTRO_2_ID]: u2, [ADMIN_ID]: admin };
    usersByEmail = { [u1.email]: u1, [u2.email]: u2, [admin.email]: admin };
    otps = [];
    measurements = [
      {
        _id: MEAS_1_ID,
        astronaut: ASTRO_1_ID,
        heartRate: 72,
        spo2: 99,
        temperature: 36.8,
        respiratoryRate: 15,
        measuredAt: new Date("2026-11-14T10:00:00Z"),
        source: "manual",
      },
      {
        _id: MEAS_2_ID,
        astronaut: ASTRO_2_ID,
        heartRate: 88,
        spo2: 97,
        temperature: 37.1,
        respiratoryRate: 18,
        measuredAt: new Date("2026-11-14T11:00:00Z"),
        source: "manual",
      },
    ];
    alerts = [
      {
        _id: ALERT_1_ID,
        astronaut: ASTRO_1_ID,
        title: "Astro 1 Alert",
        message: "Own alert",
        severity: "low",
        isRead: false,
        createdAt: new Date("2026-11-14T12:00:00Z"),
      },
      {
        _id: ALERT_2_ID,
        astronaut: ASTRO_2_ID,
        title: "Astro 2 Private Alert",
        message: "Other user alert",
        severity: "high",
        isRead: false,
        createdAt: new Date("2026-11-14T12:05:00Z"),
      },
    ];
  }

  before(async () => {
    resetStores();

    User.findById = async (id) => usersById[String(id)] || null;
    User.findOne = (query) => {
      const found = query?.email ? usersByEmail[query.email] || null : null;
      return {
        select: async () => found,
        then: (resolve, reject) => Promise.resolve(found).then(resolve, reject),
      };
    };
    User.create = async (doc) => {
      const rec = makeUserRecord({
        _id: "507f1f77bcf86cd799439088",
        ...doc,
        plainPassword: doc.password,
        role: doc.role || "astronaut",
      });
      usersById[rec._id] = rec;
      usersByEmail[rec.email] = rec;
      return rec;
    };

    Otp.deleteMany = async ({ email, purpose }) => {
      otps = otps.filter((o) => !(o.email === email && o.purpose === purpose));
    };
    Otp.deleteOne = async ({ _id }) => {
      otps = otps.filter((o) => o._id !== _id);
    };
    Otp.create = async (doc) => {
      const rec = {
        _id: `otp-${otps.length + 1}`,
        attempts: 0,
        createdAt: new Date(),
        ...doc,
        save: async function save() {
          return this;
        },
      };
      otps.push(rec);
      return rec;
    };
    Otp.findOne = ({ email, purpose }) => ({
      sort: async () => {
        const matches = otps.filter(
          (o) => o.email === email && o.purpose === purpose
        );
        return matches.length ? matches[matches.length - 1] : null;
      },
    });

    const filterMeasurements = (filter = {}) =>
      measurements.filter((m) => {
        if (filter._id && String(m._id) !== String(filter._id)) return false;
        if (filter.astronaut && String(m.astronaut) !== String(filter.astronaut)) {
          return false;
        }
        return true;
      });

    Measurement.find = (filter) => {
      const rows = filterMeasurements(filter);
      const chain = {
        populate: () => chain,
        sort: () => chain,
        skip: () => chain,
        limit: () => chain,
        then: (resolve, reject) => Promise.resolve(rows).then(resolve, reject),
      };
      return chain;
    };
    Measurement.findOne = (filter) => {
      const found = filterMeasurements(filter)[0] || null;
      return {
        populate: async () => found,
        then: (resolve, reject) => Promise.resolve(found).then(resolve, reject),
      };
    };
    Measurement.countDocuments = async (filter) => filterMeasurements(filter).length;
    Measurement.aggregate = async (pipeline) => {
      const match = pipeline[0]?.$match || {};
      const rows = filterMeasurements(match);
      if (rows.length === 0) return [];
      const avg = (k) => rows.reduce((s, r) => s + (r[k] || 0), 0) / rows.length;
      return [
        {
          _id: null,
          records: rows.length,
          averageHeartRate: avg("heartRate"),
          avgHeartRate: avg("heartRate"),
          averageSpo2: avg("spo2"),
          avgSpo2: avg("spo2"),
          averageRespiratoryRate: avg("respiratoryRate"),
          avgRespiratoryRate: avg("respiratoryRate"),
          averageTemperature: avg("temperature"),
          avgTemperature: avg("temperature"),
          totalSteps: 0,
          totalCalories: 0,
          totalSleepMinutes: 0,
        },
      ];
    };
    Measurement.create = async (doc) => {
      const created = {
        _id: `607f1f77bcf86cd7994391${measurements.length}`,
        measuredAt: new Date(),
        source: "manual",
        ...doc,
      };
      measurements.push(created);
      return created;
    };
    Measurement.findOneAndUpdate = async (filter, updates) => {
      const found = filterMeasurements(filter)[0];
      if (!found) return null;
      Object.assign(found, updates);
      return found;
    };
    Measurement.findOneAndDelete = async (filter) => {
      const found = filterMeasurements(filter)[0];
      if (!found) return null;
      measurements = measurements.filter((m) => m._id !== found._id);
      return found;
    };

    const filterAlerts = (filter = {}) =>
      alerts.filter((a) => {
        if (filter._id && String(a._id) !== String(filter._id)) return false;
        if (filter.astronaut && String(a.astronaut) !== String(filter.astronaut)) {
          return false;
        }
        if (filter.isRead !== undefined && a.isRead !== filter.isRead) {
          return false;
        }
        return true;
      });

    Alert.find = (filter) => {
      const rows = filterAlerts(filter);
      return {
        populate: () => ({
          sort: async () => rows,
        }),
      };
    };
    Alert.countDocuments = async (filter) => filterAlerts(filter).length;
    Alert.findOneAndUpdate = async (filter, updates) => {
      const found = filterAlerts(filter)[0];
      if (!found) return null;
      Object.assign(found, updates);
      return found;
    };

    server = http.createServer(app);
    baseUrl = await listenServer(server);
  });

  after(async () => {
    User.findById = orig.userFindById;
    User.findOne = orig.userFindOne;
    User.create = orig.userCreate;
    Otp.findOne = orig.otpFindOne;
    Otp.create = orig.otpCreate;
    Otp.deleteOne = orig.otpDeleteOne;
    Otp.deleteMany = orig.otpDeleteMany;
    Measurement.find = orig.measFind;
    Measurement.findOne = orig.measFindOne;
    Measurement.create = orig.measCreate;
    Measurement.countDocuments = orig.measCount;
    Measurement.aggregate = orig.measAgg;
    Measurement.findOneAndUpdate = orig.measUpdate;
    Measurement.findOneAndDelete = orig.measDelete;
    Alert.find = orig.alertFind;
    Alert.countDocuments = orig.alertCount;
    Alert.findOneAndUpdate = orig.alertUpdate;
    await closeServer(server);
  });

  beforeEach(() => resetStores());

  it("handles login success, invalid credentials (401), unverified account (403), and authenticated logout", async () => {
    const ok = await reqJson(baseUrl, "/api/auth/login", {
      method: "POST",
      body: { email: "astro1@example.test", password: "Password!1" },
    });
    assert.equal(ok.status, 200);
    assert.equal(ok.json.success, true);
    assert.ok(ok.json.token);
    assert.equal(ok.json.user.role, "astronaut");

    const badPass = await reqJson(baseUrl, "/api/auth/login", {
      method: "POST",
      body: { email: "astro1@example.test", password: "WrongPassword!" },
    });
    assert.equal(badPass.status, 401);

    const unverified = await reqJson(baseUrl, "/api/auth/login", {
      method: "POST",
      body: { email: "astro2@example.test", password: "Password!2" },
    });
    assert.equal(unverified.status, 403);

    const unauthLogout = await reqJson(baseUrl, "/api/auth/logout", {
      method: "POST",
    });
    assert.equal(unauthLogout.status, 401);

    const authLogout = await reqJson(baseUrl, "/api/auth/logout", {
      method: "POST",
      token: ok.json.token,
    });
    assert.equal(authLogout.status, 200);
    assert.equal(authLogout.json.success, true);
  });

  it("completes signup OTP verification and tracks failed OTP attempts on password reset", async () => {
    // Seed signup OTP for unverified astro2
    await Otp.create({
      email: "astro2@example.test",
      purpose: "signup",
      otpHash: hashOtp("123456"),
      expiresAt: new Date(Date.now() + 60_000),
    });

    const verified = await reqJson(baseUrl, "/api/auth/verify-otp", {
      method: "POST",
      body: { email: "astro2@example.test", otp: "123456", purpose: "signup" },
    });
    assert.equal(verified.status, 200);
    assert.ok(verified.json.token);
    assert.equal(usersById[ASTRO_2_ID].isVerified, true);

    // Seed reset OTP and verify attempts increment on wrong OTP
    await Otp.create({
      email: "astro1@example.test",
      purpose: "reset_password",
      otpHash: hashOtp("654321"),
      expiresAt: new Date(Date.now() + 60_000),
    });

    const wrongReset = await reqJson(baseUrl, "/api/auth/reset-password", {
      method: "POST",
      body: {
        email: "astro1@example.test",
        otp: "000000",
        newPassword: "NewPassword!9",
      },
    });
    assert.equal(wrongReset.status, 400);
    assert.equal(otps[0].attempts, 1);

    const goodReset = await reqJson(baseUrl, "/api/auth/reset-password", {
      method: "POST",
      body: {
        email: "astro1@example.test",
        otp: "654321",
        newPassword: "NewPassword!9",
      },
    });
    assert.equal(goodReset.status, 200);
    assert.equal(goodReset.json.success, true);
  });

  it("verifies full register -> send-otp -> verify-otp -> login -> /api/users/me -> /api/health contract", async () => {
    // 1. Health endpoint
    const health = await reqJson(baseUrl, "/api/health");
    assert.equal(health.status, 200);
    assert.equal(health.json.success, true);
    assert.equal(health.json.message, "OrbitCare API is running");
    assert.equal(typeof health.json.emailConfigured, "boolean");

    // 2. Register new astronaut (non-production logs dev OTP when SMTP unset)
    const reg = await reqJson(baseUrl, "/api/auth/register", {
      method: "POST",
      body: {
        fullName: "New Crew Member",
        email: "newcrew@example.test",
        password: "OrbitPass!2026",
      },
    });
    assert.equal(reg.status, 201);
    assert.equal(reg.json.success, true);
    assert.equal(usersByEmail["newcrew@example.test"].isVerified, false);

    // 3. Resend signup OTP via POST /api/auth/send-otp
    const resend = await reqJson(baseUrl, "/api/auth/send-otp", {
      method: "POST",
      body: {
        email: "newcrew@example.test",
        purpose: "signup",
      },
    });
    assert.equal(resend.status, 200);
    assert.equal(resend.json.success, true);

    // Replace stored hash with known OTP so we can verify end-to-end
    otps[otps.length - 1].otpHash = hashOtp("778899");

    // 4. Verify signup OTP -> returns JWT + activates user
    const verify = await reqJson(baseUrl, "/api/auth/verify-otp", {
      method: "POST",
      body: {
        email: "newcrew@example.test",
        otp: "778899",
        purpose: "signup",
      },
    });
    assert.equal(verify.status, 200);
    assert.equal(verify.json.success, true);
    assert.ok(verify.json.token);
    assert.equal(verify.json.user.email, "newcrew@example.test");
    assert.equal(verify.json.user.role, "astronaut");

    // 5. Login with verified credentials
    const login = await reqJson(baseUrl, "/api/auth/login", {
      method: "POST",
      body: {
        email: "newcrew@example.test",
        password: "OrbitPass!2026",
      },
    });
    assert.equal(login.status, 200);
    assert.equal(login.json.success, true);
    assert.ok(login.json.token);

    // 6. Validate restored session against GET /api/users/me
    const me = await reqJson(baseUrl, "/api/users/me", {
      token: login.json.token,
    });
    assert.equal(me.status, 200);
    assert.equal(me.json.status, "success");
    assert.equal(me.json.data.user.email, "newcrew@example.test");
  });

  it("enforces user ownership on dashboard, measurements, alerts, and reports", async () => {
    const token1 = makeToken(ASTRO_1_ID);

    // Dashboard returns only Astro 1 data
    const dash = await reqJson(baseUrl, "/api/dashboard", { token: token1 });
    assert.equal(dash.status, 200);
    assert.equal(dash.json.data.totalMeasurements, 1);
    assert.equal(dash.json.data.unreadAlerts, 1);

    // Measurements list returns only Astro 1 measurement
    const list = await reqJson(baseUrl, "/api/measurements", { token: token1 });
    assert.equal(list.status, 200);
    assert.equal(list.json.data.length, 1);
    assert.equal(list.json.data[0]._id, MEAS_1_ID);

    // Accessing Astro 2 measurement by ID returns 404 (not leaked!)
    const otherMeas = await reqJson(baseUrl, `/api/measurements/${MEAS_2_ID}`, {
      token: token1,
    });
    assert.equal(otherMeas.status, 404);

    // Invalid measurement range rejected with 400
    const badMeas = await reqJson(baseUrl, "/api/measurements", {
      method: "POST",
      token: token1,
      body: { heartRate: 999, spo2: 150 },
    });
    assert.equal(badMeas.status, 400);

    // Valid measurement creation succeeds for authenticated user
    const created = await reqJson(baseUrl, "/api/measurements", {
      method: "POST",
      token: token1,
      body: {
        heartRate: 75,
        spo2: 98,
        respiratoryRate: 15,
        temperature: 36.7,
        bloodPressure: { systolic: 120, diastolic: 78 },
        source: "manual",
      },
    });
    assert.equal(created.status, 201);
    assert.equal(created.json.data.astronaut, ASTRO_1_ID);

    // Alerts list returns only Astro 1 alert; marking Astro 2 alert returns 404
    const alertList = await reqJson(baseUrl, "/api/alerts", { token: token1 });
    assert.equal(alertList.status, 200);
    assert.equal(alertList.json.data.length, 1);
    assert.equal(alertList.json.data[0]._id, ALERT_1_ID);

    const markOther = await reqJson(baseUrl, `/api/alerts/${ALERT_2_ID}/read`, {
      method: "PATCH",
      token: token1,
    });
    assert.equal(markOther.status, 404);

    const markOwn = await reqJson(baseUrl, `/api/alerts/${ALERT_1_ID}/read`, {
      method: "PATCH",
      token: token1,
    });
    assert.equal(markOwn.status, 200);
    assert.equal(markOwn.json.data.isRead, true);

    // Reports endpoint returns summary scoped to Astro 1
    const rep = await reqJson(baseUrl, "/api/reports?period=weekly", {
      token: token1,
    });
    assert.equal(rep.status, 200);
    assert.equal(rep.json.success, true);
    assert.equal(rep.json.data.period, "weekly");
    assert.equal(rep.json.data.summary.records, 2);
  });
});
