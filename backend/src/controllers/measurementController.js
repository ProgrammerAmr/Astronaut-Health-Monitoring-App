
const mongoose = require("mongoose");
const Measurement = require("../models/Measurement");

const allowedFields = [
  "heartRate",
  "pulseRate",
  "respiratoryRate",
  "spo2",
  "bloodPressure",
  "bloodSugar",
  "sleep",
  "activity",
  "measuredAt",
  "source",
];

const getFilter = (req) => {
  return req.user.role === "admin"
    ? {}
    : { astronaut: req.user._id };
};

const createMeasurement = async (req, res) => {
  try {
    const data = {};

    for (const field of allowedFields) {
      if (req.body[field] !== undefined) {
        data[field] = req.body[field];
      }
    }

    const hasVitalSigns = [
      "heartRate",
      "pulseRate",
      "respiratoryRate",
      "spo2"
    ].some((field) => data[field] !== undefined);

    const hasOtherMeasurements = [
      "bloodPressure",
      "bloodSugar",
      "sleep",
      "activity"
    ].some((field) => data[field] !== undefined);

    if (!hasVitalSigns && !hasOtherMeasurements) {
      return res.status(400).json({
        status: "fail",
        message: "At least one measurement is required",
      });
    }
    const measurement = await Measurement.create({
      ...data,
      astronaut: req.user._id,
    });

    res.status(201).json({
      status: "success",
      data: measurement,
    });
  } catch (error) {
    res.status(400).json({
      status: "fail",
      message: error.message,
    });
  }
};

const getMeasurements = async (req, res) => {
  try {
    const filter = getFilter(req);

    const startDate = req.query.from || req.query.startDate;
    const endDate = req.query.to || req.query.endDate;
    if (startDate || endDate) {
      filter.measuredAt = {};

      if (startDate) {
        filter.measuredAt.$gte = new Date(startDate);
      }

      if (endDate) {
        filter.measuredAt.$lte = new Date(endDate);
      }

      if (Object.values(filter.measuredAt).some(
        (date) => Number.isNaN(date.getTime())
      )) {
        return res.status(400).json({
          status: "fail",
          message: "Invalid date filter",
        });
      }
    }

    const page = Math.max(1, Number(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 20));

    const measurements = await Measurement.find(filter)
      .populate("astronaut", "name email")
      .sort({ measuredAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit);

    const total = await Measurement.countDocuments(filter);

    res.status(200).json({
      status: "success",
      page,
      limit,
      total,
      pages: Math.ceil(total / limit),
      data: measurements,
    });
  } catch (error) {
    res.status(500).json({
      status: "fail",
      message: error.message,
    });
  }
};

const getMeasurementById = async (req, res) => {
  try {
    const { id } = req.params;

    if (!mongoose.isValidObjectId(id)) {
      return res.status(400).json({
        status: "fail",
        message: "Invalid measurement ID",
      });
    }

    const measurement = await Measurement.findOne({
      _id: id,
      ...getFilter(req),
    }).populate("astronaut", "name email");

    if (!measurement) {
      return res.status(404).json({
        status: "fail",
        message: "Measurement not found",
      });
    }

    res.status(200).json({
      status: "success",
      data: measurement,
    });
  } catch (error) {
    res.status(500).json({
      status: "fail",
      message: error.message,
    });
  }
};

const updateMeasurement = async (req, res) => {
  try {
    const { id } = req.params;

    if (!mongoose.isValidObjectId(id)) {
      return res.status(400).json({
        status: "fail",
        message: "Invalid measurement ID",
      });
    }

    const updates = {};

    for (const field of allowedFields) {
      if (req.body[field] !== undefined) {
        updates[field] = req.body[field];
      }
    }

    if (Object.keys(updates).length === 0) {
      return res.status(400).json({
        status: "fail",
        message: "No valid fields provided",
      });
    }

    const measurement = await Measurement.findOneAndUpdate(
      { _id: id, ...getFilter(req) },
      updates,
      { new: true, runValidators: true }
    );

    if (!measurement) {
      return res.status(404).json({
        status: "fail",
        message: "Measurement not found",
      });
    }

    res.status(200).json({
      status: "success",
      data: measurement,
    });
  } catch (error) {
    res.status(400).json({
      status: "fail",
      message: error.message,
    });
  }
};

const deleteMeasurement = async (req, res) => {
  try {
    const { id } = req.params;

    if (!mongoose.isValidObjectId(id)) {
      return res.status(400).json({
        status: "fail",
        message: "Invalid measurement ID",
      });
    }

    const measurement = await Measurement.findOneAndDelete({
      _id: id,
      ...getFilter(req),
    });

    if (!measurement) {
      return res.status(404).json({
        status: "fail",
        message: "Measurement not found",
      });
    }

    res.status(200).json({
      status: "success",
      message: "Measurement deleted successfully",
    });
  } catch (error) {
    res.status(500).json({
      status: "fail",
      message: error.message,
    });
  }
};

module.exports = {
  createMeasurement,
  getMeasurements,
  getMeasurementById,
  updateMeasurement,
  deleteMeasurement,
};



