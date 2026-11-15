require("dotenv").config();

const express = require("express");
const cors = require("cors");
const connectDB = require("./src/config/db");

const app = express();

app.use(cors());
app.use(express.json({ limit: "1mb" }));

app.get("/api/health", (req, res) => {
  res.status(200).json({
    success: true,
    message: "OrbitCare API is running"
  });
});

app.use("/api/auth", require("./src/routes/authRoutes"));
app.use("/api/users", require("./src/routes/userRoutes"));
app.use("/api/measurements", require("./src/routes/measurementRoutes"));
app.use("/api/dashboard", require("./src/routes/dashboardRoutes"));
app.use("/api/alerts", require("./src/routes/alertRoutes"));
app.use("/api/reports", require("./src/routes/reportRoutes"));
app.use("/api/cognitive-state", require("./src/routes/cognitiveStateRoutes"));

// Keep API misses as JSON instead of serving the SPA's HTML to API clients.
app.use("/api", (req, res) => {
  res.status(404).json({
    success: false,
    message: `Route not found: ${req.method} ${req.originalUrl}`
  });
});

// Opt-in static serving for the single-origin hosted web deployment.
if (process.env.WEB_DIST_DIR) {
  const path = require("node:path");
  const webDir = path.resolve(process.env.WEB_DIST_DIR);
  app.use(express.static(webDir));
  app.get("/{*path}", (req, res) => res.sendFile(path.join(webDir, "index.html")));
}

app.use((req, res) => res.status(404).json({ success: false, message: "Route not found" }));

app.use((err, req, res, next) => {
  console.error(err);
  res.status(err.status || 500).json({
    success: false,
    message: err.message || "Internal server error"
  });
});

const PORT = process.env.PORT || 5000;

if (require.main === module) {
  (async () => {
    try {
      await connectDB();
      app.listen(PORT, "0.0.0.0", () => {
        console.log(`OrbitCare API running on http://localhost:${PORT}`);
      });
    } catch (error) {
      console.error("Server startup failed:", error.message);
      process.exit(1);
    }
  })();
}

module.exports = app;

