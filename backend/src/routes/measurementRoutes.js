const express = require("express");
const router = express.Router();

const {
  createMeasurement,
  getMeasurements,
  getMeasurementById,
  updateMeasurement,
  deleteMeasurement,
} = require("../controllers/measurementController");

const { protect } = require("../middleware/authMiddleware");

router.use(protect);

router.post("/", createMeasurement);
router.get("/", getMeasurements);
router.get("/:id", getMeasurementById);
router.put("/:id", updateMeasurement);
router.delete("/:id", deleteMeasurement);

module.exports = router;