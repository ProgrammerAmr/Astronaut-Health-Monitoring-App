const User = require("../models/User");
const Otp = require("../models/Otp");
const asyncHandler = require("../utils/asyncHandler");
const createToken = require("../utils/token");
const { generateOtp, hashOtp } = require("../utils/otp");
const sendOtpEmail = require("../utils/sendEmail");

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const normalizeEmail = (email) => String(email || "").trim().toLowerCase();

async function createAndSendOtp(email, purpose) {
  const otp = generateOtp();
  await Otp.deleteMany({ email, purpose });
  await Otp.create({
    email,
    purpose,
    otpHash: hashOtp(otp),
    expiresAt: new Date(Date.now() + 10 * 60 * 1000)
  });
  await sendOtpEmail(email, otp, purpose);
}

const register = asyncHandler(async (req, res) => {
  const body = req.body && typeof req.body === "object" ? req.body : {};
  const { fullName, name, email, password } = body;
  const cleanEmail = normalizeEmail(email);
  const cleanName = String(fullName || name || "").trim();

  if (!cleanName || !cleanEmail || !password) {
    return res.status(400).json({
      success: false,
      message: "fullName, email and password are required"
    });
  }
  if (!EMAIL_RE.test(cleanEmail)) {
    return res.status(400).json({
      success: false,
      message: "Please provide a valid email address"
    });
  }
  if (cleanName.length > 120) {
    return res.status(400).json({
      success: false,
      message: "Name must be 120 characters or fewer"
    });
  }
  if (typeof password !== "string" || password.length < 8 || password.length > 128) {
    return res.status(400).json({
      success: false,
      message: "Password must be between 8 and 128 characters"
    });
  }

  let user = await User.findOne({ email: cleanEmail });

  if (user && user.isVerified) {
    return res.status(409).json({
      success: false,
      message: "An account with this email already exists"
    });
  }

  if (user) {
    user.name = cleanName;
    user.password = password;
    await user.save();
  } else {
    user = await User.create({
      name: cleanName,
      email: cleanEmail,
      password,
      isVerified: false
    });
  }

  await createAndSendOtp(cleanEmail, "signup");

  res.status(201).json({
    success: true,
    message: "Account created. Verification code sent to your email."
  });
});

const login = asyncHandler(async (req, res) => {
  const body = req.body && typeof req.body === "object" ? req.body : {};
  const email = normalizeEmail(body.email);
  const { password } = body;

  if (!email || !password || typeof password !== "string") {
    return res.status(400).json({
      success: false,
      message: "Email and password are required"
    });
  }

  const user = await User.findOne({ email }).select("+password");
  if (!user || !(await user.comparePassword(password))) {
    return res.status(401).json({
      success: false,
      message: "Invalid email or password"
    });
  }
  if (!user.isVerified) {
    return res.status(403).json({
      success: false,
      message: "Please verify your email before logging in"
    });
  }

  res.json({
    success: true,
    token: createToken(user),
    user: {
      id: user._id.toString(),
      name: user.name,
      email: user.email,
      role: user.role || "astronaut"
    }
  });
});

const sendOtp = asyncHandler(async (req, res) => {
  const body = req.body && typeof req.body === "object" ? req.body : {};
  const email = normalizeEmail(body.email);
  const purpose = body.purpose || "reset_password";

  if (!email || !EMAIL_RE.test(email) || !["signup", "reset_password"].includes(purpose)) {
    return res.status(400).json({
      success: false,
      message: "A valid email and purpose (signup or reset_password) are required"
    });
  }

  const user = await User.findOne({ email });
  if (!user) {
    return res.status(404).json({
      success: false,
      message: "No account found with this email"
    });
  }
  if (purpose === "signup" && user.isVerified) {
    return res.status(400).json({
      success: false,
      message: "This account is already verified"
    });
  }
  if (purpose === "reset_password" && !user.isVerified) {
    return res.status(400).json({
      success: false,
      message: "Verify your account before resetting the password"
    });
  }

  await createAndSendOtp(email, purpose);
  res.json({ success: true, message: "OTP sent successfully" });
});

const verifyOtp = asyncHandler(async (req, res) => {
  const body = req.body && typeof req.body === "object" ? req.body : {};
  const email = normalizeEmail(body.email);
  const otp = String(body.otp || "").trim();
  const purpose = body.purpose || "signup";

  if (!email || !otp || !["signup", "reset_password"].includes(purpose)) {
    return res.status(400).json({
      success: false,
      message: "Email, OTP and a valid purpose are required"
    });
  }

  const record = await Otp.findOne({ email, purpose }).sort({ createdAt: -1 });
  if (!record || record.expiresAt < new Date()) {
    return res.status(400).json({
      success: false,
      message: "OTP is invalid or expired"
    });
  }
  if (record.attempts >= 5) {
    await Otp.deleteOne({ _id: record._id });
    return res.status(429).json({
      success: false,
      message: "Too many attempts. Request a new OTP."
    });
  }

  if (record.otpHash !== hashOtp(otp)) {
    record.attempts += 1;
    await record.save();
    return res.status(400).json({
      success: false,
      message: "Incorrect OTP"
    });
  }

  if (purpose === "signup") {
    const user = await User.findOne({ email });
    if (!user) {
      return res.status(404).json({
        success: false,
        message: "Account not found"
      });
    }
    user.isVerified = true;
    await user.save();
    await Otp.deleteOne({ _id: record._id });

    return res.json({
      success: true,
      message: "OTP verified. Account activated successfully.",
      token: createToken(user),
      user: {
        id: user._id.toString(),
        name: user.name,
        email: user.email,
        role: user.role || "astronaut"
      }
    });
  }

  // For password reset, keep the valid OTP until reset-password consumes it.
  res.json({
    success: true,
    message: "OTP verified successfully. You can reset your password now."
  });
});

const resetPassword = asyncHandler(async (req, res) => {
  const body = req.body && typeof req.body === "object" ? req.body : {};
  const email = normalizeEmail(body.email);
  const otp = String(body.otp || "").trim();
  const newPassword = typeof body.newPassword === "string" ? body.newPassword : "";

  if (!email || !otp || !newPassword) {
    return res.status(400).json({
      success: false,
      message: "Email, OTP and newPassword are required"
    });
  }
  if (newPassword.length < 8 || newPassword.length > 128) {
    return res.status(400).json({
      success: false,
      message: "New password must be between 8 and 128 characters"
    });
  }

  const record = await Otp.findOne({ email, purpose: "reset_password" })
    .sort({ createdAt: -1 });

  if (!record || record.expiresAt < new Date()) {
    return res.status(400).json({
      success: false,
      message: "OTP is invalid or expired. Request a new code."
    });
  }

  if (record.attempts >= 5) {
    await Otp.deleteOne({ _id: record._id });
    return res.status(429).json({
      success: false,
      message: "Too many attempts. Request a new OTP."
    });
  }

  if (record.otpHash !== hashOtp(otp)) {
    record.attempts += 1;
    await record.save();
    return res.status(400).json({
      success: false,
      message: "OTP is invalid or expired. Request a new code."
    });
  }

  const user = await User.findOne({ email });
  if (!user) {
    return res.status(404).json({
      success: false,
      message: "Account not found"
    });
  }

  user.password = newPassword;
  await user.save();
  await Otp.deleteMany({ email, purpose: "reset_password" });

  res.json({ success: true, message: "Password reset successfully" });
});

// Stateless JWT logout acknowledgement (clients must also clear stored tokens).
const logout = asyncHandler(async (req, res) => {
  res.status(200).json({
    success: true,
    message: "Logged out successfully"
  });
});

module.exports = { register, login, sendOtp, verifyOtp, resetPassword, logout };
