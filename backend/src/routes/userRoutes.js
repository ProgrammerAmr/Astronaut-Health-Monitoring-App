const express = require("express");
const router = express.Router();

const {
  getMe,
  updateMe,
  changePassword,
  getAllUsers,
} = require("../controllers/userController");

const { protect } = require("../middleware/authMiddleware");
const authorizeRoles = require("../middleware/roleMiddleware");

router.use(protect);

router.get("/me", getMe);
router.patch("/me", updateMe);
router.patch("/change-password", changePassword);
router.get("/", authorizeRoles("admin"), getAllUsers);

module.exports = router;