
const jwt = require("jsonwebtoken");
const User = require("../models/User");
const { resolveJwtSecret } = require("../utils/token");

const protect = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({
        status: "fail",
        message: "Please login first",
      });
    }

    // Use the same resolution as token signing, otherwise a development server
    // without JWT_SECRET would happily issue tokens at login and then reject
    // every authenticated request (the app looks like it "cannot pass login").
    let secret;
    try {
      secret = resolveJwtSecret();
    } catch (secretError) {
      console.error("[auth] JWT configuration error:", secretError.message);
      return res.status(500).json({
        status: "error",
        message: secretError.message,
      });
    }

    const token = authHeader.split(" ")[1];
    const decoded = jwt.verify(token, secret);

    const user = await User.findById(decoded.id);

    if (!user) {
      return res.status(401).json({
        status: "fail",
        message: "User no longer exists",
      });
    }

    req.user = user;
    next();
  } catch (error) {
    if (error && error.name !== "JsonWebTokenError" &&
        error.name !== "TokenExpiredError" &&
        error.name !== "NotBeforeError") {
      // Not a token problem (database, configuration, ...): log it so the
      // developer is not chasing a phantom "invalid token" bug.
      console.error("[auth] protect middleware error:", error.message);
    }
    return res.status(401).json({
      status: "fail",
      message: error && error.name === "TokenExpiredError"
        ? "Token expired, please login again"
        : "Invalid or expired token",
    });
  }
};

module.exports = { protect };
