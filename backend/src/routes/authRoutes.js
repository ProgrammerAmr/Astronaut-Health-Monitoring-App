const router = require("express").Router();
const {
  register, login, sendOtp, verifyOtp, resetPassword, logout
} = require("../controllers/authController");
const { protect } = require("../middleware/authMiddleware");

router.post("/register", register);
router.post("/login", login);
router.post("/send-otp", sendOtp);
router.post("/verify-otp", verifyOtp);
router.post("/reset-password", resetPassword);
router.post("/logout", protect, logout);

module.exports = router;
