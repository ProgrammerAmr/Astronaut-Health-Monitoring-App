
const express = require("express");
const cors = require("cors");
require("dotenv").config();

// Import Routes
const measurementRoutes = require("./src/routes/measurementRoutes");

const app = express();

// Middlewares
app.use(cors());
app.use(express.json());

// Health Check API
app.get("/api/health", (req, res) => {
  res.status(200).json({
    status: "ok",
    message: "Astronaut Health API is running"
  });
});

// Measurements Routes
app.use("/api/measurements", measurementRoutes);

// Server Port
const PORT = process.env.PORT || 5000;

// Start Server
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
