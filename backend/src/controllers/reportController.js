const Measurement = require("../models/Measurement");
const asyncHandler = require("../utils/asyncHandler");

const getReport = asyncHandler(async (req, res) => {
  const period = req.query.period || "weekly";
  if (!["daily", "weekly", "monthly"].includes(period)) {
    return res.status(400).json({
      success: false,
      message: "period must be daily, weekly or monthly"
    });
  }

  const now = new Date();
  const from = req.query.from ? new Date(req.query.from) : new Date(now);
  if (!req.query.from) {
    if (period === "daily") from.setDate(from.getDate() - 1);
    if (period === "weekly") from.setDate(from.getDate() - 7);
    if (period === "monthly") from.setMonth(from.getMonth() - 1);
  }
  const to = req.query.to ? new Date(req.query.to) : now;

  if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime()) || from > to) {
    return res.status(400).json({
      success: false,
      message: "Invalid date range"
    });
  }

  const [measurements, summary] = await Promise.all([
    Measurement.find({
      astronaut: req.user._id,
      measuredAt: { $gte: from, $lte: to }
    }).sort({ measuredAt: 1 }),
    Measurement.aggregate([
      {
        $match: {
          astronaut: req.user._id,
          measuredAt: { $gte: from, $lte: to }
        }
      },
      {
        $group: {
          _id: null,
          records: { $sum: 1 },
          avgHeartRate: { $avg: "$heartRate" },
          avgSpo2: { $avg: "$spo2" },
          avgRespiratoryRate: { $avg: "$respiratoryRate" },
          avgBloodSugar: { $avg: "$bloodSugar" },
          totalSteps: { $sum: "$activity.steps" },
          totalCalories: { $sum: "$activity.calories" },
          totalSleepMinutes: { $sum: "$sleep.durationMinutes" }
        }
      }
    ])
  ]);

  res.json({
    success: true,
    data: {
      period,
      from,
      to,
      summary: summary[0] || {
        records: 0,
        avgHeartRate: null,
        avgSpo2: null,
        avgRespiratoryRate: null,
        avgBloodSugar: null,
        totalSteps: 0,
        totalCalories: 0,
        totalSleepMinutes: 0
      },
      measurements
    }
  });
});

module.exports = { getReport };
