
const authorizeRoles = (...roles) => {
  return (req, res, next) => {
    if (!req.user || !roles.includes(req.user.role)) {
      return res.status(403).json({
        status: "fail",
        message: "Access denied",
      });
    }

    next();
  };
};

module.exports = authorizeRoles;
