require("dotenv").config();

const os = require("os");

const express = require("express");
const cors = require("cors");
const mongoose = require("mongoose");

const connectDB = require("./src/config/db");

const app = express();

app.use(cors());
app.use(express.json({ limit: "1mb" }));

/** Human readable MongoDB state, used by /api/health and the startup banner. */
function mongoState() {
  const states = {
    0: "disconnected",
    1: "connected",
    2: "connecting",
    3: "disconnecting"
  };
  return states[mongoose.connection.readyState] || "unknown";
}

/** Every non-loopback IPv4 address, so the team knows what to type in the app. */
function lanAddresses() {
  const addresses = [];
  const interfaces = os.networkInterfaces();
  Object.keys(interfaces).forEach((name) => {
    (interfaces[name] || []).forEach((info) => {
      if (info.family === "IPv4" && !info.internal) {
        addresses.push({ interface: name, address: info.address });
      }
    });
  });
  return addresses;
}

app.get("/api/health", (req, res) => {
  const smtpConfigured = Boolean(
    process.env.SMTP_HOST &&
      process.env.SMTP_PORT &&
      process.env.SMTP_USER &&
      process.env.SMTP_PASS
  );
  res.status(200).json({
    success: true,
    message: "OrbitCare API is running",
    status: "ok",
    database: mongoState(),
    emailConfigured: smtpConfigured,
    environment: process.env.NODE_ENV || "development",
    version: require("./package.json").version,
    uptimeSeconds: Math.round(process.uptime())
  });
});

app.use("/api/auth", require("./src/routes/authRoutes"));
app.use("/api/users", require("./src/routes/userRoutes"));
app.use("/api/measurements", require("./src/routes/measurementRoutes"));
app.use("/api/dashboard", require("./src/routes/dashboardRoutes"));
app.use("/api/alerts", require("./src/routes/alertRoutes"));
app.use("/api/reports", require("./src/routes/reportRoutes"));
app.use("/api/cognitive-state", require("./src/routes/cognitiveStateRoutes"));

app.use((req, res) => {
  res.status(404).json({
    success: false,
    message: `Route not found: ${req.method} ${req.originalUrl}`
  });
});

app.use((err, req, res, next) => {
  console.error(err);
  res.status(err.status || 500).json({
    success: false,
    message: err.message || "Internal server error"
  });
});

const PORT = process.env.PORT || 5000;

function printStartupBanner(port) {
  const lan = lanAddresses();
  const line = "-".repeat(64);

  console.log("");
  console.log(line);
  console.log(`OrbitCare API running on http://localhost:${port}`);
  console.log(`  MongoDB      : ${mongoState()}`);
  console.log(`  Environment  : ${process.env.NODE_ENV || "development"}`);
  console.log(`  Health check : curl http://127.0.0.1:${port}/api/health`);
  console.log("");
  console.log("  Point the Flutter app at one of these URLs:");
  console.log(`    Android emulator : http://10.0.2.2:${port}`);
  console.log(
    `    iOS sim / desktop / web : http://localhost:${port}`
  );
  if (lan.length > 0) {
    lan.forEach((entry) => {
      console.log(
        `    Physical device (same Wi-Fi, ${entry.interface}) : http://${entry.address}:${port}`
      );
    });
  } else {
    console.log(
      "    Physical device        : connect to Wi-Fi, then use this PC's LAN IP"
    );
  }
  console.log("");
  console.log(
    "  Tip: inside the app open Settings -> Backend Connection to test/save the URL."
  );
  console.log(line);
  console.log("");
}

if (require.main === module) {
  (async () => {
    try {
      await connectDB();
      const server = app.listen(PORT, "0.0.0.0", () => {
        printStartupBanner(PORT);
      });

      server.on("error", (error) => {
        if (error.code === "EADDRINUSE") {
          console.error(
            `\nPort ${PORT} is already in use.\n` +
              `  - Stop the other process, or\n` +
              `  - Run on another port: PORT=5050 npm run dev\n` +
              `  - Then point the app at that port in Settings -> Backend Connection.\n`
          );
          process.exit(1);
        }
        console.error("\nServer error:", error.message);
        process.exit(1);
      });
    } catch (error) {
      console.error("\nServer startup failed:\n");
      console.error(error.message);
      console.error(
        "\nThe HTTP server was NOT started, so the mobile app cannot connect.\n" +
          "Run `npm run doctor` inside backend/ for a full environment report.\n"
      );
      process.exit(1);
    }
  })();
}

module.exports = app;
module.exports.lanAddresses = lanAddresses;
module.exports.mongoState = mongoState;
