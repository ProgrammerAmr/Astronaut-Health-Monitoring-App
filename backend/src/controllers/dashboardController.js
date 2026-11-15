const Measurement = require("../models/Measurement");
const Alert = require("../models/Alert");

const getDashboard = async (req, res) => {
  try {
    const filter = req.user.role === "admin"
      ? {}
      : { astronaut: req.user._id };

    const [totalMeasurements, averages, latestMeasurements, unreadAlerts] =
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
              averageTemperature: { $avg: "$temperature" },
            },
          },
        ]),

        Measurement.find(filter)
          .sort({ measuredAt: -1 })
          .limit(5),

        Alert.countDocuments({
          ...filter,
          isRead: false,
        }),
      ]);

    res.status(200).json({
      status: "success",
      data: {
        totalMeasurements,
        unreadAlerts,
        averages: averages[0] || {
          averageHeartRate: null,
          averagePulseRate: null,
          averageRespiratoryRate: null,
          averageSpo2: null,
          averageTemperature: null,
        },
        latestMeasurement: latestMeasurements[0] || null,
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