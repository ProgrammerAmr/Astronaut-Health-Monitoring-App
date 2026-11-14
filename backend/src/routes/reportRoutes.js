const router = require("express").Router();
const { protect } = require("../middleware/authMiddleware");
const { getReport } = require("../controllers/reportController");

router.get("/", protect, getReport);

module.exports = router;
