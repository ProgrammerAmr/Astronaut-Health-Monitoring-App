/**
 * Idempotent local synthetic demo seed script for OrbitCare hackathon demonstrations.
 *
 * Usage:
 *   cd backend && npm run seed:demo
 *
 * Requirements:
 *   - backend/.env must configure MONGO_URI (never committed to Git).
 *   - Optional DEMO_USER_PASSWORD env var sets the demo astronaut password
 *     (defaults to a local-only demo password printed to stdout).
 *
 * Safety & provenance notice:
 *   - Seeds ONLY synthetic, clearly labeled demonstration data (zero real personal data).
 *   - Never generates clinical alerts from DEC-001 Cognitive State Monitoring (CSM).
 */

require("dotenv").config();
const mongoose = require("mongoose");

const connectDB = require("../config/db");
const User = require("../models/User");
const Measurement = require("../models/Measurement");
const Alert = require("../models/Alert");

const DEMO_EMAIL = "demo.astronaut@orbitcare.local";
const DEMO_NAME = "Alex Vance (Synthetic Demo)";

async function seedDemo() {
  await connectDB();

  const demoPassword =
    (process.env.DEMO_USER_PASSWORD || "").trim() || "OrbitDemo!2026";
  if (demoPassword.length < 8) {
    throw new Error("DEMO_USER_PASSWORD must be at least 8 characters.");
  }

  let user = await User.findOne({ email: DEMO_EMAIL });
  if (!user) {
    user = await User.create({
      name: DEMO_NAME,
      email: DEMO_EMAIL,
      password: demoPassword,
      isVerified: true,
      role: "astronaut",
      mission: {
        name: "Orbital Demo Mission (Synthetic)",
        role: "Mission Specialist (Demo)",
        status: "Simulation Active",
      },
    });
    console.log(`Created synthetic demo astronaut: ${DEMO_EMAIL}`);
  } else {
    user.name = DEMO_NAME;
    user.isVerified = true;
    user.password = demoPassword;
    await user.save();
    console.log(`Refreshed synthetic demo astronaut: ${DEMO_EMAIL}`);
  }

  // Replace previous synthetic demo records for this demo account cleanly
  await Measurement.deleteMany({ astronaut: user._id, source: "imported" });
  await Alert.deleteMany({
    astronaut: user._id,
    title: /^\[SYNTHETIC DEMO\]/,
  });

  const now = Date.now();
  const hourMs = 60 * 60 * 1000;

  const syntheticMeasurements = [
    {
      astronaut: user._id,
      heartRate: 68,
      pulseRate: 68,
      respiratoryRate: 14,
      spo2: 99,
      temperature: 36.7,
      bloodPressure: { systolic: 118, diastolic: 76 },
      bloodSugar: 94,
      sleep: { durationMinutes: 440, quality: "good" },
      activity: { steps: 6400, calories: 2150, durationMinutes: 65, level: "moderate" },
      measuredAt: new Date(now - 96 * hourMs),
      source: "imported",
    },
    {
      astronaut: user._id,
      heartRate: 72,
      pulseRate: 72,
      respiratoryRate: 15,
      spo2: 98,
      temperature: 36.8,
      bloodPressure: { systolic: 121, diastolic: 78 },
      bloodSugar: 98,
      sleep: { durationMinutes: 410, quality: "fair" },
      activity: { steps: 7200, calories: 2300, durationMinutes: 75, level: "moderate" },
      measuredAt: new Date(now - 72 * hourMs),
      source: "imported",
    },
    {
      astronaut: user._id,
      heartRate: 76,
      pulseRate: 75,
      respiratoryRate: 16,
      spo2: 98,
      temperature: 36.9,
      bloodPressure: { systolic: 124, diastolic: 80 },
      bloodSugar: 102,
      sleep: { durationMinutes: 390, quality: "fair" },
      activity: { steps: 8100, calories: 2480, durationMinutes: 85, level: "high" },
      measuredAt: new Date(now - 48 * hourMs),
      source: "imported",
    },
    {
      astronaut: user._id,
      heartRate: 70,
      pulseRate: 70,
      respiratoryRate: 14,
      spo2: 99,
      temperature: 36.6,
      bloodPressure: { systolic: 116, diastolic: 74 },
      bloodSugar: 91,
      sleep: { durationMinutes: 465, quality: "excellent" },
      activity: { steps: 5900, calories: 2050, durationMinutes: 55, level: "light" },
      measuredAt: new Date(now - 24 * hourMs),
      source: "imported",
    },
    {
      astronaut: user._id,
      heartRate: 74,
      pulseRate: 74,
      respiratoryRate: 15,
      spo2: 98,
      temperature: 36.8,
      bloodPressure: { systolic: 120, diastolic: 77 },
      bloodSugar: 96,
      sleep: { durationMinutes: 430, quality: "good" },
      activity: { steps: 6850, calories: 2210, durationMinutes: 70, level: "moderate" },
      measuredAt: new Date(now - 2 * hourMs),
      source: "imported",
    },
  ];

  const insertedMeasurements = await Measurement.insertMany(syntheticMeasurements);

  // Synthetic non-diagnostic operational reminders (never generated from CSM outputs)
  await Alert.insertMany([
    {
      astronaut: user._id,
      title: "[SYNTHETIC DEMO] Hydration & Sleep Log Reminder",
      message:
        "Synthetic demonstration alert: sleep duration trended slightly below 7h during simulated high-activity cycle.",
      severity: "low",
      isRead: false,
      relatedMeasurement: insertedMeasurements[2]._id,
    },
    {
      astronaut: user._id,
      title: "[SYNTHETIC DEMO] Routine Vitals Check Completed",
      message:
        "Synthetic demonstration alert: baseline simulated vitals entry recorded successfully.",
      severity: "medium",
      isRead: true,
      relatedMeasurement: insertedMeasurements[4]._id,
    },
  ]);

  console.log("");
  console.log("Synthetic demo data seeded successfully!");
  console.log(`  Demo Email:    ${DEMO_EMAIL}`);
  console.log(`  Demo Password: ${demoPassword}`);
  console.log("  Measurements:  5 synthetic records (source=imported)");
  console.log("  Alerts:        2 synthetic non-CSM demo alerts (1 unread, 1 read)");
  console.log("");

  await mongoose.disconnect();
}

seedDemo().catch((err) => {
  console.error("Demo seed failed:", err.message);
  process.exit(1);
});
