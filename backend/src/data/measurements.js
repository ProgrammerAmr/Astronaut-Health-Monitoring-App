
const measurements = [
  {
    id: "m1",
    type: "heart_rate",
    value: 75,
    unit: "bpm",
    timestamp: "2026-11-14T08:30:00Z",
    source: "simulated"
  },
  {
    id: "m2",
    type: "oxygen_saturation",
    value: 98,
    unit: "%",
    timestamp: "2026-11-14T08:30:00Z",
    source: "simulated"
  },
  {
    id: "m3",
    type: "body_temperature",
    value: 36.8,
    unit: "°C",
    timestamp: "2026-11-14T08:30:00Z",
    source: "simulated"
  },
  {
    id: "m4",
    type: "blood_pressure",
    value: {
      systolic: 120,
      diastolic: 80
    },
    unit: "mmHg",
    timestamp: "2026-11-14T08:30:00Z",
    source: "simulated"
  }
];

module.exports = measurements;
