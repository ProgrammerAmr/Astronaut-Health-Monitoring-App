
const mongoose = require("mongoose");

const alertSchema = new mongoose.Schema(
  {
    astronaut: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },

    title: {
      type: String,
      required: true,
    },

    message: {
      type: String,
      required: true,
    },

    severity: {
      type: String,
      enum: ["low", "medium", "high", "critical"],
      default: "low",
    },

    isRead: {
      type: Boolean,
      default: false,
    },

    relatedMeasurement: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Measurement",
    },
  },
  { timestamps: true }
);

alertSchema.index({ astronaut: 1, createdAt: -1 });

module.exports = mongoose.model("Alert", alertSchema);
