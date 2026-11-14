
const mongoose = require("mongoose");

const measurementSchema = new mongoose.Schema(
  {
    astronaut: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },

    heartRate: {
      type: Number,
      min: 0,
    },

    pulseRate: {
      type: Number,
      min: 0,
    },

    respiratoryRate: {
      type: Number,
      min: 0,
    },

    spo2: {
      type: Number,
      min: 0,
      max: 100,
    },

    bloodPressure: {
      systolic: { type: Number, min: 0 },
      diastolic: { type: Number, min: 0 },
    },

    bloodSugar: {
      type: Number,
      min: 0,
    },

    sleep: {
      durationMinutes: { type: Number, min: 0 },
      quality: {
        type: String,
        enum: ["poor", "fair", "good", "excellent"],
      },
    },

    activity: {
      steps: { type: Number, min: 0 },
      calories: { type: Number, min: 0 },
      durationMinutes: { type: Number, min: 0 },
      level: {
        type: String,
        enum: ["low", "light", "moderate", "high", "intense"],
      },
    },
    measuredAt: {
      type: Date,
      default: Date.now,
    },

    source: {
      type: String,
      enum: ["sensor", "manual", "imported"],
      default: "sensor",
    },
  },
  { timestamps: true }
);

measurementSchema.index({ astronaut: 1, measuredAt: -1 });

module.exports = mongoose.model("Measurement", measurementSchema);
