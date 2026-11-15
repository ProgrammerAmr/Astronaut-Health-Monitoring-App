const express = require("express");
const router = express.Router();

const { protect } = require("../middleware/authMiddleware");
const {
  getCognitiveStateStatus,
  analyzeCognitiveState,
} = require("../controllers/cognitiveStateController");
const { buildSafeErrorResponse } = require("../services/csmClient");

const MAX_CSM_BODY_BYTES = 32 * 1024; // 32 KiB strict cap for CSM metadata requests

// Enforce tight route-level body size limit (works even if parent app allows larger payloads)
function enforceCsmBodyLimit(req, res, next) {
  const contentLength = Number.parseInt(req.headers["content-length"] || "", 10);
  if (Number.isFinite(contentLength) && contentLength > MAX_CSM_BODY_BYTES) {
    return res.status(413).json(
      buildSafeErrorResponse({
        code: "PAYLOAD_TOO_LARGE",
        message: `Request body exceeds maximum allowed size of ${MAX_CSM_BODY_BYTES} bytes.`,
      })
    );
  }
  if (req.body !== undefined) {
    try {
      const size = Buffer.byteLength(JSON.stringify(req.body), "utf8");
      if (size > MAX_CSM_BODY_BYTES) {
        return res.status(413).json(
          buildSafeErrorResponse({
            code: "PAYLOAD_TOO_LARGE",
            message: `Request body exceeds maximum allowed size of ${MAX_CSM_BODY_BYTES} bytes.`,
          })
        );
      }
    } catch {
      return res.status(400).json(
        buildSafeErrorResponse({
          code: "INVALID_PAYLOAD",
          message: "Request body could not be parsed as JSON.",
        })
      );
    }
  }
  return next();
}

router.use(express.json({ limit: "32kb" }));

// Handle route-level JSON parse / body-size errors safely
router.use((err, req, res, next) => {
  if (err && err.type === "entity.too.large") {
    return res.status(413).json(
      buildSafeErrorResponse({
        code: "PAYLOAD_TOO_LARGE",
        message: `Request body exceeds maximum allowed size of ${MAX_CSM_BODY_BYTES} bytes.`,
      })
    );
  }
  if (err && err.type === "entity.parse.failed") {
    return res.status(400).json(
      buildSafeErrorResponse({
        code: "INVALID_JSON",
        message: "Malformed JSON request body.",
      })
    );
  }
  return next(err);
});

router.get("/status", protect, getCognitiveStateStatus);
router.post("/analyze", protect, enforceCsmBodyLimit, analyzeCognitiveState);

module.exports = router;
