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

function isFiniteNumber(v) {
  return typeof v === "number" && Number.isFinite(v);
}

function validateMeasurementPayload(data) {
  const numericBounds = {
    heartRate: [20, 260, "heartRate must be between 20 and 260 bpm"],
    pulseRate: [20, 260, "pulseRate must be between 20 and 260 bpm"],
    respiratoryRate: [4, 80, "respiratoryRate must be between 4 and 80 breaths/min"],
    spo2: [0, 100, "spo2 must be between 0 and 100%"],
    temperature: [30, 45, "temperature must be between 30 and 45 °C"],
    bloodSugar: [10, 800, "bloodSugar must be between 10 and 800 mg/dL"],
  };

  for (const [key, [minVal, maxVal, msg]] of Object.entries(numericBounds)) {
    if (data[key] !== undefined) {
      if (!isFiniteNumber(data[key]) || data[key] < minVal || data[key] > maxVal) {
        return msg;
      }
    }
  }

  if (data.bloodPressure !== undefined) {
    const bp = data.bloodPressure;
    if (!bp || typeof bp !== "object" || Array.isArray(bp)) {
      return "bloodPressure must be an object with systolic and/or diastolic";
    }
    if (
      bp.systolic !== undefined &&
      (!isFiniteNumber(bp.systolic) || bp.systolic < 40 || bp.systolic > 260)
    ) {
      return "bloodPressure.systolic must be between 40 and 260 mmHg";
    }
    if (
      bp.diastolic !== undefined &&
      (!isFiniteNumber(bp.diastolic) || bp.diastolic < 20 || bp.diastolic > 180)
    ) {
      return "bloodPressure.diastolic must be between 20 and 180 mmHg";
    }
    if (
      bp.systolic !== undefined &&
      bp.diastolic !== undefined &&
      bp.systolic < bp.diastolic
    ) {
      return "bloodPressure.systolic must be greater than or equal to diastolic";
    }
  }

  if (data.sleep !== undefined) {
    const sleep = data.sleep;
    if (!sleep || typeof sleep !== "object" || Array.isArray(sleep)) {
      return "sleep must be an object";
    }
    if (
      sleep.durationMinutes !== undefined &&
      (!isFiniteNumber(sleep.durationMinutes) ||
        sleep.durationMinutes < 0 ||
        sleep.durationMinutes > 1440)
    ) {
      return "sleep.durationMinutes must be between 0 and 1440 minutes";
    }
    if (
      sleep.quality !== undefined &&
      !["poor", "fair", "good", "excellent"].includes(sleep.quality)
    ) {
      return "sleep.quality must be poor, fair, good, or excellent";
    }
  }

  if (data.activity !== undefined) {
    const act = data.activity;
    if (!act || typeof act !== "object" || Array.isArray(act)) {
      return "activity must be an object";
    }
    for (const k of ["steps", "calories", "durationMinutes"]) {
      if (act[k] !== undefined && (!isFiniteNumber(act[k]) || act[k] < 0)) {
        return `activity.${k} must be a non-negative number`;
      }
    }
    if (
      act.level !== undefined &&
      !["low", "light", "moderate", "high", "intense"].includes(act.level)
    ) {
      return "activity.level must be low, light, moderate, high, or intense";
    }
  }

  if (data.source !== undefined && !["sensor", "manual", "imported"].includes(data.source)) {
    return "source must be sensor, manual, or imported";
  }

  if (data.measuredAt !== undefined) {
    const dt = new Date(data.measuredAt);
    if (Number.isNaN(dt.getTime())) {
      return "measuredAt must be a valid ISO date";
    }
  }

  return null;
}

// POST /api/measurements
const createMeasurement = async (req, res) => {
  try {
    if (!req.body || typeof req.body !== "object" || Array.isArray(req.body)) {
      return res.status(400).json({
        status: "fail",
        message: "Request body must be a JSON object",
      });
    }

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

    const validationError = validateMeasurementPayload(data);
    if (validationError) {
      return res.status(400).json({
        status: "fail",
        message: validationError,
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

    const validationError = validateMeasurementPayload(updates);
    if (validationError) {
      return res.status(400).json({
        status: "fail",
        message: validationError,
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
  validateMeasurementPayload,
  createMeasurement,
  getMeasurements,
  getMeasurementById,
  updateMeasurement,
  deleteMeasurement,
};