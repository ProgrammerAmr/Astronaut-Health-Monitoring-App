const express = require("express");

const {
  getMeasurements,
  getMeasurementById
} = require("../controllers/measurementController");

const router = express.Router();

router.get("/", getMeasurements);

router.get("/:id", getMeasurementById);

module.exports = router;