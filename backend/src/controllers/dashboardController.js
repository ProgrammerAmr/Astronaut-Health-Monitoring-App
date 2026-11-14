
const Measurement = require("../models/Measurement");

const getDashboard = async (req, res) => {
  try {
    const filter = req.user.role === "admin"
      ? {}
      : { astronaut: req.user._id };

    const [totalMeasurements, averages, latestMeasurements] =
      await Promise.all([
        Measurement.countDocuments(filter),

        Measurement.aggregate([
          { $match: filter },
          {
            $group: {
              _id: null,
              averageHeartRate: { $avg: "$heartRate" },
              averagePulseRate: { $avg: "$pulseRate" },
              averageRespiratoryRate: { $avg: "$respiratoryRate" },
              averageSpo2: { $avg: "$spo2" },
            },
          },
        ]),

        Measurement.find(filter)
          .sort({ measuredAt: -1 })
          .limit(5),
      ]);

    res.status(200).json({
      status: "success",
      data: {
        totalMeasurements,
        averages: averages[0] || {},
        latestMeasurements,
      },
    });
  } catch (error) {
    res.status(500).json({
      status: "fail",
      message: error.message,
    });
  }
};

module.exports = { getDashboard };
