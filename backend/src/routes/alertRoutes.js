const express = require("express");
const router = express.Router();

const {
  getAlerts,
  createAlert,
  markAlertAsRead,
} = require("../controllers/alertController");

const { protect } = require("../middleware/authMiddleware");
const authorizeRoles = require("../middleware/roleMiddleware");

router.use(protect);

router.get("/", getAlerts);
router.post("/", authorizeRoles("admin"), createAlert);
router.patch("/:id/read", markAlertAsRead);

module.exports = router;