const mongoose = require("mongoose");
const Measurement = require("../models/Measurement");

const allowedFields = [
  "heartRate",
  "pulseRate",
  "respiratoryRate",
  "spo2",
  "temperature",
  "bloodPressure",
  "bloodSugar",
  "sleep",
  "activity",
  "measuredAt",
  "source",
];

const typeFields = {
  heartRate: "heartRate",
  pulseRate: "pulseRate",
  respiratoryRate: "respiratoryRate",
  spo2: "spo2",
  temperature: "temperature",
  bloodPressure: "bloodPressure.systolic",
  bloodSugar: "bloodSugar",
  sleep: "sleep.durationMinutes",
  activity: "activity.steps",
};

const getFilter = (req) => {
  return req.user.role === "admin"
    ? {}
    : { astronaut: req.user._id };
};

// POST /api/measurements
const createMeasurement = async (req, res) => {
  try {
    const data = {};

    for (const field of allowedFields) {
      if (req.body[field] !== undefined) {
        data[field] = req.body[field];
      }
    }

    const hasMeasurement = allowedFields
      .filter((field) => !["measuredAt", "source"].includes(field))
      .some((field) => data[field] !== undefined);

    if (!hasMeasurement) {
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

// GET /api/measurements
const getMeasurements = async (req, res) => {
  try {
    const filter = getFilter(req);

    // Filter by measurement type
    if (req.query.type) {
      const field = typeFields[req.query.type];

      if (!field) {
        return res.status(400).json({
          status: "fail",
          message: `Invalid type. Allowed types: ${Object.keys(typeFields).join(", ")}`,
        });
      }

      filter[field] = { $exists: true, $ne: null };
    }

    // Filter by period
    const { period } = req.query;

    if (period && !["daily", "weekly", "monthly"].includes(period)) {
      return res.status(400).json({
        status: "fail",
        message: "period must be daily, weekly or monthly",
      });
    }

    let startDate = req.query.from || req.query.startDate;
    let endDate = req.query.to || req.query.endDate;

    if (period && !startDate && !endDate) {
      const now = new Date();
      const from = new Date(now);

      if (period === "daily") from.setDate(from.getDate() - 1);
      if (period === "weekly") from.setDate(from.getDate() - 7);
      if (period === "monthly") from.setMonth(from.getMonth() - 1);

      startDate = from;
      endDate = now;
    }

    if (startDate || endDate) {
      const from = startDate ? new Date(startDate) : null;
      const to = endDate ? new Date(endDate) : null;

      if (
        (from && Number.isNaN(from.getTime())) ||
        (to && Number.isNaN(to.getTime())) ||
        (from && to && from > to)
      ) {
        return res.status(400).json({
          status: "fail",
          message: "Invalid date range",
        });
      }

      filter.measuredAt = {};

      if (from) filter.measuredAt.$gte = from;
      if (to) filter.measuredAt.$lte = to;
    }

    const page = Math.max(1, Number(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 20));

    const [measurements, total] = await Promise.all([
      Measurement.find(filter)
        .populate("astronaut", "name email")
        .sort({ measuredAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),

      Measurement.countDocuments(filter),
    ]);

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

// GET /api/measurements/:id
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

// PUT /api/measurements/:id
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

// DELETE /api/measurements/:id
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