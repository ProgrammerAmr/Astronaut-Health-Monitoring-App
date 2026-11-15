const crypto = require("crypto");
const jwt = require("jsonwebtoken");

const DEV_FALLBACK_SECRET = "orbitcare-insecure-development-only-secret";

let warnedAboutDevSecret = false;

/**
 * Resolves the JWT signing secret.
 *
 * - Production: JWT_SECRET is mandatory (never sign tokens with a public value).
 * - Development/test: fall back to a clearly labelled local secret so a missing
 *   .env does not break login with a confusing 500 ("JWT_SECRET is missing").
 */
function resolveJwtSecret() {
  const configured = String(process.env.JWT_SECRET || "").trim();
  if (configured) return configured;

  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "JWT_SECRET is required in production. Add it to backend/.env " +
        "(generate one with: node -e \"console.log(require('crypto').randomBytes(48).toString('hex'))\")"
    );
  }

  if (!warnedAboutDevSecret) {
    warnedAboutDevSecret = true;
    console.warn(
      "[auth] JWT_SECRET is not set - using an INSECURE development fallback. " +
        "Add JWT_SECRET to backend/.env before deploying. " +
        `Suggested value: ${crypto.randomBytes(32).toString("hex")}`
    );
  }

  return DEV_FALLBACK_SECRET;
}

function createToken(user) {
  return jwt.sign(
    { id: user._id.toString(), role: user.role },
    resolveJwtSecret(),
    { expiresIn: process.env.JWT_EXPIRES_IN || "7d" }
  );
}

module.exports = createToken;
module.exports.resolveJwtSecret = resolveJwtSecret;
module.exports.DEV_FALLBACK_SECRET = DEV_FALLBACK_SECRET;
