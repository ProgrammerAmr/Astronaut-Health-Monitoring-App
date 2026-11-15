
const Alert = require("../models/Alert");
const mongoose = require("mongoose");

const getAlerts = async (req, res) => {
  try {
    const filter = req.user.role === "admin"
      ? {}
      : { astronaut: req.user._id };

    if (req.query.isRead !== undefined) {
      if (!["true", "false"].includes(req.query.isRead)) {
        return res.status(400).json({ status: "fail", message: "isRead must be true or false" });
      }
      filter.isRead = req.query.isRead === "true";
    }
    const alerts = await Alert.find(filter)
      .populate("astronaut", "name email")
      .sort({ createdAt: -1 });

    res.status(200).json({
      status: "success",
      results: alerts.length,
      data: alerts,
    });
  } catch (error) {
    res.status(500).json({
      status: "fail",
      message: error.message,
    });
  }
};

const createAlert = async (req, res) => {
  try {
    const { astronaut, title, message, severity, relatedMeasurement } =
      req.body;

    if (!astronaut || !title || !message) {
      return res.status(400).json({
        status: "fail",
        message: "Astronaut, title and message are required",
      });
    }

    if (!mongoose.isValidObjectId(astronaut)) {
      return res.status(400).json({
        status: "fail",
        message: "Invalid astronaut ID",
      });
    }

    if (
      severity !== undefined &&
      !["low", "medium", "high", "critical"].includes(severity)
    ) {
      return res.status(400).json({
        status: "fail",
        message: "severity must be low, medium, high, or critical",
      });
    }

    if (
      relatedMeasurement !== undefined &&
      relatedMeasurement !== null &&
      !mongoose.isValidObjectId(relatedMeasurement)
    ) {
      return res.status(400).json({
        status: "fail",
        message: "Invalid relatedMeasurement ID",
      });
    }

    const alert = await Alert.create({
      astronaut,
      title,
      message,
      severity,
      relatedMeasurement,
    });

    res.status(201).json({
      status: "success",
      data: alert,
    });
  } catch (error) {
    res.status(400).json({
      status: "fail",
      message: error.message,
    });
  }
};

const markAlertAsRead = async (req, res) => {
  try {
    const { id } = req.params;

    if (!mongoose.isValidObjectId(id)) {
      return res.status(400).json({
        status: "fail",
        message: "Invalid alert ID",
      });
    }

    const filter = { _id: id };

    if (req.user.role !== "admin") {
      filter.astronaut = req.user._id;
    }

    const alert = await Alert.findOneAndUpdate(
      filter,
      { isRead: true },
      { new: true }
    );

    if (!alert) {
      return res.status(404).json({
        status: "fail",
        message: "Alert not found",
      });
    }

    res.status(200).json({
      status: "success",
      data: alert,
    });
  } catch (error) {
    res.status(500).json({
      status: "fail",
      message: error.message,
    });
  }
};

module.exports = {
  getAlerts,
  createAlert,
  markAlertAsRead,
};

