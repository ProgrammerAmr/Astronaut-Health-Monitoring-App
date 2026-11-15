const mongoose = require("mongoose");

const DEFAULT_LOCAL_MONGO_URI = "mongodb://127.0.0.1:27017/orbitcare";

const MONGO_HELP = [
  "MongoDB is not reachable. Fix one of these and start the backend again:",
  "  1) Local server   : mongod            (or start the 'MongoDB' Windows service)",
  "  2) Docker         : docker run -d -p 27017:27017 --name orbitcare-mongo mongo:7",
  "  3) Atlas / remote : set MONGO_URI in backend/.env to your connection string",
  "Then verify with    : npm run doctor   (inside backend/)"
].join("\n");

/**
 * Resolves the Mongo connection string.
 *
 * In development an empty MONGO_URI falls back to a local MongoDB instance so
 * that `cp .env.example .env && npm run dev` works out of the box instead of
 * exiting before the HTTP server ever listens (which the mobile app then
 * reports as "unable to reach the backend").
 */
function resolveMongoUri() {
  const configured = String(process.env.MONGO_URI || "").trim();
  if (configured) {
    return { uri: configured, usedFallback: false };
  }

  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "MONGO_URI is required in production. Set it in backend/.env " +
        "(see backend/.env.example)."
    );
  }

  return { uri: DEFAULT_LOCAL_MONGO_URI, usedFallback: true };
}

/**
 * Connects to MongoDB with a couple of retries and actionable errors.
 * Throws on failure (the caller decides whether to exit).
 */
const connectDB = async ({
  retries = 2,
  retryDelayMs = 1500,
  logger = console
} = {}) => {
  const { uri, usedFallback } = resolveMongoUri();

  if (usedFallback) {
    logger.warn(
      `[db] MONGO_URI is not set - using the local default ${uri}\n` +
        "[db] Set MONGO_URI in backend/.env to use a different database."
    );
  }

  let lastError = null;

  for (let attempt = 1; attempt <= retries + 1; attempt += 1) {
    try {
      await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000 });
      logger.log(`MongoDB Connected Successfully (${uri})`);
      return mongoose.connection;
    } catch (error) {
      lastError = error;
      if (attempt <= retries) {
        logger.warn(
          `[db] MongoDB connection attempt ${attempt} failed: ${error.message}. Retrying in ${retryDelayMs}ms...`
        );
        await new Promise((resolve) => setTimeout(resolve, retryDelayMs));
      }
    }
  }

  throw new Error(
    `MongoDB Connection Failed: ${lastError ? lastError.message : "unknown error"}\n${MONGO_HELP}`
  );
};

module.exports = connectDB;
module.exports.DEFAULT_LOCAL_MONGO_URI = DEFAULT_LOCAL_MONGO_URI;
module.exports.resolveMongoUri = resolveMongoUri;
module.exports.MONGO_HELP = MONGO_HELP;
