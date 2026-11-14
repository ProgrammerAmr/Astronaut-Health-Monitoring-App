
const measurements = require("../data/measurements");

// Get all measurements or filter by type
const getMeasurements = (req, res) => {
  const { type } = req.query;

  let filteredMeasurements = measurements;

  if (type) {
    filteredMeasurements = measurements.filter(
      (item) => item.type === type
    );
  }

  res.status(200).json({
    success: true,
    count: filteredMeasurements.length,
    data: filteredMeasurements
  });
};

// Get measurement by ID
const getMeasurementById = (req, res) => {
  const { id } = req.params;

  const measurement = measurements.find(
    (item) => item.id === id
  );

  if (!measurement) {
    return res.status(404).json({
      success: false,
      message: "Measurement not found"
    });
  }

  res.status(200).json({
    success: true,
    data: measurement
  });
};

module.exports = {
  getMeasurements,
  getMeasurementById
};
