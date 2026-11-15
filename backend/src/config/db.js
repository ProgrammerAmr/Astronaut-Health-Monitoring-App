const mongoose = require("mongoose");

const connectDB = async () => {
  if (!process.env.MONGO_URI || !String(process.env.MONGO_URI).trim()) {
    throw new Error(
      "MONGO_URI is missing. Copy backend/.env.example to backend/.env and configure MONGO_URI."
    );
  }
  try {
    await mongoose.connect(process.env.MONGO_URI);
    console.log("MongoDB Connected Successfully");
  } catch (error) {
    console.error("MongoDB Connection Failed:", error.message);
    process.exit(1);
  }
};

module.exports = connectDB;
