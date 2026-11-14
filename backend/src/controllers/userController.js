
const User = require("../models/User");

const getMe = async (req, res) => {
  res.status(200).json({
    status: "success",
    data: { user: req.user },
  });
};

const updateMe = async (req, res) => {
  try {
    const { name, email } = req.body;
    const updates = {};

    if (name !== undefined) updates.name = name;
    if (email !== undefined) {
      updates.email = email.toLowerCase().trim();
    }

    if (Object.keys(updates).length === 0) {
      return res.status(400).json({
        status: "fail",
        message: "No valid fields provided",
      });
    }

    const user = await User.findByIdAndUpdate(
      req.user._id,
      updates,
      { new: true, runValidators: true }
    );

    res.status(200).json({
      status: "success",
      data: { user },
    });
  } catch (error) {
    res.status(error.code === 11000 ? 409 : 400).json({
      status: "fail",
      message: error.code === 11000
        ? "Email already exists"
        : error.message,
    });
  }
};

const changePassword = async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;

    if (!currentPassword || !newPassword) {
      return res.status(400).json({
        status: "fail",
        message: "Current and new passwords are required",
      });
    }

    if (newPassword.length < 8) {
      return res.status(400).json({
        status: "fail",
        message: "New password must be at least 8 characters",
      });
    }

    const user = await User.findById(req.user._id).select("+password");

    if (!(await user.comparePassword(currentPassword))) {
      return res.status(401).json({
        status: "fail",
        message: "Current password is incorrect",
      });
    }

    user.password = newPassword;
    await user.save();

    res.status(200).json({
      status: "success",
      message: "Password changed successfully",
    });
  } catch (error) {
    res.status(400).json({
      status: "fail",
      message: error.message,
    });
  }
};

const getAllUsers = async (req, res) => {
  try {
    const users = await User.find().sort({ createdAt: -1 });

    res.status(200).json({
      status: "success",
      results: users.length,
      data: { users },
    });
  } catch (error) {
    res.status(500).json({
      status: "fail",
      message: error.message,
    });
  }
};

module.exports = {
  getMe,
  updateMe,
  changePassword,
  getAllUsers,
};
