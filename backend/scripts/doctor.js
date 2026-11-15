#!/usr/bin/env node
/**
 * OrbitCare backend environment doctor.
 *
 *   cd backend && npm run doctor          # report only
 *   cd backend && npm run doctor -- --fix # create a working backend/.env
 *
 * Diagnoses the reasons the Flutter app usually fails to connect or to get past
 * the login screen: missing .env, MongoDB not running, port already taken, and
 * the wrong backend URL on the device.
 */

const fs = require("fs");
const net = require("net");
const os = require("os");
const path = require("path");
const crypto = require("crypto");

const BACKEND_DIR = path.resolve(__dirname, "..");
const ENV_PATH = path.join(BACKEND_DIR, ".env");
const ENV_EXAMPLE_PATH = path.join(BACKEND_DIR, ".env.example");

const FIX_MODE = process.argv.includes("--fix");

const GREEN = "\x1b[32m";
const RED = "\x1b[31m";
const YELLOW = "\x1b[33m";
const CYAN = "\x1b[36m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

const ok = (msg) => console.log(`${GREEN}  [OK]${RESET}   ${msg}`);
const warn = (msg) => console.log(`${YELLOW}  [WARN]${RESET} ${msg}`);
const fail = (msg) => console.log(`${RED}  [FAIL]${RESET} ${msg}`);
const info = (msg) => console.log(`         ${msg}`);
const section = (msg) => console.log(`\n${BOLD}${CYAN}${msg}${RESET}`);

let failures = 0;
let warnings = 0;

function countFail() {
  failures += 1;
}
function countWarn() {
  warnings += 1;
}

function parseEnvFile(content) {
  const values = {};
  content.split(/\r?\n/).forEach((line) => {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) return;
    const index = trimmed.indexOf("=");
    if (index === -1) return;
    values[trimmed.slice(0, index).trim()] = trimmed.slice(index + 1).trim();
  });
  return values;
}

function lanAddresses() {
  const addresses = [];
  const interfaces = os.networkInterfaces();
  Object.keys(interfaces).forEach((name) => {
    (interfaces[name] || []).forEach((entry) => {
      if (entry.family === "IPv4" && !entry.internal) {
        addresses.push({ interface: name, address: entry.address });
      }
    });
  });
  return addresses;
}

async function isPortFree(port, host = "0.0.0.0") {
  return new Promise((resolve) => {
    const tester = net
      .createServer()
      .once("error", () => resolve(false))
      .once("listening", () => {
        tester.close(() => resolve(true));
      })
      .listen(port, host);
  });
}

async function checkNodeVersion() {
  section("1. Node.js runtime");
  const major = Number(process.versions.node.split(".")[0]);
  if (major >= 20) {
    ok(`Node ${process.versions.node}`);
  } else {
    fail(`Node ${process.versions.node} is too old (20+ required)`);
    info("Install Node 20 LTS or newer from https://nodejs.org");
    countFail();
  }
}

function checkDependencies() {
  section("2. Backend dependencies");
  const modulesDir = path.join(BACKEND_DIR, "node_modules");
  if (fs.existsSync(path.join(modulesDir, "express"))) {
    ok("node_modules installed");
  } else {
    fail("node_modules missing or incomplete");
    info("Run: cd backend && npm install");
    countFail();
  }
}

function ensureEnvFile() {
  section("3. Environment file (backend/.env)");

  if (fs.existsSync(ENV_PATH)) {
    ok(".env exists");
    return parseEnvFile(fs.readFileSync(ENV_PATH, "utf8"));
  }

  if (!FIX_MODE) {
    fail(".env is missing - the backend cannot start without it");
    info("Run: cd backend && cp .env.example .env   (Windows: copy .env.example .env)");
    info("Or let this script build one for you: npm run doctor -- --fix");
    countFail();
    return {};
  }

  if (!fs.existsSync(ENV_EXAMPLE_PATH)) {
    fail(".env.example is missing, cannot generate .env");
    countFail();
    return {};
  }

  const template = fs.readFileSync(ENV_EXAMPLE_PATH, "utf8");
  const generated = template
    .replace(/^MONGO_URI=.*$/m, "MONGO_URI=mongodb://127.0.0.1:27017/orbitcare")
    .replace(/^JWT_SECRET=.*$/m, `JWT_SECRET=${crypto.randomBytes(32).toString("hex")}`)
    .replace(/^PORT=.*$/m, "PORT=5000")
    .replace(/^NODE_ENV=.*$/m, "NODE_ENV=development");

  fs.writeFileSync(ENV_PATH, generated, "utf8");
  ok("created backend/.env from .env.example (with a generated JWT_SECRET)");
  return parseEnvFile(generated);
}

function checkEnvValues(env) {
  section("4. Configuration values");

  const mongoUri = (env.MONGO_URI || process.env.MONGO_URI || "").trim();
  if (mongoUri) {
    ok(`MONGO_URI = ${mongoUri.replace(/\/\/([^:]+):([^@]+)@/, "//***:***@")}`);
  } else {
    warn("MONGO_URI is empty - the backend will try mongodb://127.0.0.1:27017/orbitcare");
    info("Set it in backend/.env if your database lives elsewhere (Atlas, Docker network, ...).");
    countWarn();
  }

  const jwtSecret = (env.JWT_SECRET || process.env.JWT_SECRET || "").trim();
  if (jwtSecret) {
    ok("JWT_SECRET is set");
    if (jwtSecret.length < 16) {
      warn("JWT_SECRET is short - use at least 32 random characters");
      countWarn();
    }
  } else {
    warn("JWT_SECRET is empty - login only works with an INSECURE development fallback");
    info('Generate one with: node -e "console.log(require(\'crypto\').randomBytes(48).toString(\'hex\'))"');
    countWarn();
  }

  const smtpConfigured =
    env.SMTP_HOST && env.SMTP_PORT && env.SMTP_USER && env.SMTP_PASS;
  if (smtpConfigured) {
    ok("SMTP configured - OTP emails will be sent");
  } else {
    warn("SMTP not configured - signup/reset OTP codes print to the backend terminal");
    info("Look for a line like: [DEVELOPMENT OTP] signup OTP for you@mail.com: 123456");
    info("Login is blocked until that OTP is verified, or until you use the seeded demo account.");
    countWarn();
  }
}

async function checkMongo(env) {
  section("5. MongoDB connection");

  const mongoUri =
    (env.MONGO_URI || process.env.MONGO_URI || "").trim() ||
    "mongodb://127.0.0.1:27017/orbitcare";

  let mongoose;
  try {
    mongoose = require("mongoose");
  } catch (_) {
    fail("mongoose is not installed - run: cd backend && npm install");
    countFail();
    return false;
  }

  try {
    await mongoose.connect(mongoUri, { serverSelectionTimeoutMS: 4000 });
    ok(`connected to ${mongoUri.replace(/\/\/([^:]+):([^@]+)@/, "//***:***@")}`);
    await mongoose.disconnect();
    return true;
  } catch (error) {
    fail(`could not connect to ${mongoUri}`);
    info(`reason: ${error.message.split("\n")[0]}`);
    info("Without MongoDB the backend exits at startup, so the app cannot log in.");
    info("Fix one of these:");
    info("  - local server : mongod   (Windows service 'MongoDB Server' must be running)");
    info("  - docker       : docker run -d -p 27017:27017 --name orbitcare-mongo mongo:7");
    info("  - remote/Atlas : set MONGO_URI in backend/.env");
    countFail();
    return false;
  }
}

async function checkPort(env) {
  section("6. HTTP port");
  const port = Number((env.PORT || process.env.PORT || "5000").trim());
  const free = await isPortFree(port);
  if (free) {
    ok(`port ${port} is free`);
  } else {
    fail(`port ${port} is already in use`);
    info("Another process (or a previous backend run) is holding the port.");
    info(`  - Windows: netstat -ano | findstr :${port}   then   taskkill /PID <pid> /F`);
    info(`  - macOS/Linux: lsof -i :${port}`);
    info(`  - or use another port: PORT=5050 npm run dev (then update the app URL)`);
    countFail();
  }
  return port;
}

function printFlutterCommands(port) {
  section("7. How to point the Flutter app at this backend");

  const lan = lanAddresses();
  const emulatorUrl = `http://10.0.2.2:${port}`;
  const localhostUrl = `http://localhost:${port}`;

  console.log("  The app now falls back to a local default, but being explicit is safer:");
  console.log("");
  console.log(`  ${BOLD}Android emulator${RESET}`);
  console.log(`    flutter run --dart-define=ORBITCARE_API_BASE_URL=${emulatorUrl}`);
  console.log("");
  console.log(`  ${BOLD}iOS simulator / Windows / macOS / Linux / Chrome${RESET}`);
  console.log(`    flutter run --dart-define=ORBITCARE_API_BASE_URL=${localhostUrl}`);

  if (lan.length > 0) {
    console.log("");
    console.log(`  ${BOLD}Physical phone or tablet (same Wi-Fi as this PC)${RESET}`);
    lan.forEach((entry) => {
      console.log(
        `    flutter run --dart-define=ORBITCARE_API_BASE_URL=http://${entry.address}:${port}   (${entry.interface})`
      );
    });
    console.log("");
    console.log("    If the phone cannot reach that IP, allow the port through the firewall:");
    console.log(
      `    netsh advfirewall firewall add rule name="OrbitCare API" dir=in action=allow protocol=TCP localport=${port}`
    );
  } else {
    console.log("");
    warn("No LAN IPv4 address detected - a physical device cannot reach this PC yet");
    info("Connect to Wi-Fi (or Ethernet) and run this doctor again.");
    countWarn();
  }

  console.log("");
  console.log("  Inside the app you can also change/test the URL without rebuilding:");
  console.log("  Login screen -> 'Backend Connection' -> Test -> Save URL.");
}

function printDemoAccountSteps() {
  section("8. Getting past the login screen");
  console.log("  Login requires an *email-verified* account. Two ways in:");
  console.log("");
  console.log(`  ${BOLD}A) Seeded demo astronaut (recommended for demos)${RESET}`);
  console.log("     cd backend && npm run seed:demo");
  console.log("     email    : demo.astronaut@orbitcare.local");
  console.log("     password : OrbitDemo!2026  (or DEMO_USER_PASSWORD from .env)");
  console.log("");
  console.log(`  ${BOLD}B) Sign up in the app${RESET}`);
  console.log("     1. Sign Up -> the backend terminal prints [DEVELOPMENT OTP] ... : 123456");
  console.log("     2. Enter that code on the OTP screen");
  console.log("     3. You are logged in; afterwards the normal login form works");
}

async function main() {
  console.log("");
  console.log(`${BOLD}OrbitCare backend doctor${RESET}`);
  console.log(`working directory: ${BACKEND_DIR}`);
  if (FIX_MODE) {
    console.log(`mode: ${YELLOW}--fix${RESET} (will create backend/.env if missing)`);
  }

  await checkNodeVersion();
  checkDependencies();
  const env = ensureEnvFile();
  checkEnvValues(env);
  const mongoOk = await checkMongo(env);
  const port = await checkPort(env);
  printFlutterCommands(port);
  printDemoAccountSteps();

  section("Summary");
  if (failures === 0) {
    console.log(`${GREEN}${BOLD}  Backend environment looks good.${RESET}`);
    if (warnings > 0) {
      console.log(`${YELLOW}  ${warnings} warning(s) worth reading above.${RESET}`);
    }
    console.log("");
    console.log("  Start it with:  cd backend && npm run dev");
    if (!mongoOk) {
      console.log("");
    }
  } else {
    console.log(
      `${RED}${BOLD}  ${failures} blocking problem(s) found - fix them above, then run: npm run dev${RESET}`
    );
  }
  console.log("");

  process.exitCode = failures === 0 ? 0 : 1;
}

main().catch((error) => {
  console.error(`${RED}Doctor crashed: ${error.message}${RESET}`);
  process.exitCode = 1;
});
