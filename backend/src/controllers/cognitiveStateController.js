const {
  buildSafeErrorResponse,
  fetchCsmStatus,
  requestCsmAnalysis,
} = require("../services/csmClient");

const SUPPORTED_MODES = new Set(["synthetic_demo", "research_replay"]);
const ALLOWED_PROVENANCES = new Set([
  "synthetic",
  "simulated",
  "real_nasa_csm_replay",
]);
const FORBIDDEN_RAW_SIGNAL_KEYS = new Set([
  "raw_signals",
  "rawSignals",
  "raw_waveform",
  "rawWaveform",
  "waveforms",
  "samples",
  "eeg",
  "ecg",
  "gsr",
  "resp",
  "respiration",
]);
const ALLOWED_BODY_KEYS = new Set([
  "mode",
  "sessionId",
  "session_id",
  "astronautId",
  "astronaut_id",
  "windowEndSec",
  "window_end_sec",
  "dataProvenance",
  "data_provenance",
  "signalQuality",
  "signal_quality",
]);
const ALLOWED_SQI_KEYS = new Set([
  "valid",
  "sqi_score",
  "sqiScore",
  "reasons",
  "ecg_valid",
  "ecgValid",
  "resp_valid",
  "respValid",
  "eeg_valid_fraction",
  "eegValidFraction",
  "gsr_valid_fraction",
  "gsrValidFraction",
]);
const SAFE_ID_RE = /^[a-zA-Z0-9._:@/-]{1,128}$/;

function isPlainObject(val) {
  return val !== null && typeof val === "object" && !Array.isArray(val);
}

function validateSignalQuality(rawSqi) {
  if (rawSqi === undefined || rawSqi === null) {
    return { ok: true, value: undefined };
  }
  if (!isPlainObject(rawSqi)) {
    return { ok: false, message: "signalQuality must be a JSON object." };
  }

  const unknownSqiKeys = Object.keys(rawSqi).filter(
    (k) => !ALLOWED_SQI_KEYS.has(k)
  );
  if (unknownSqiKeys.length > 0) {
    return {
      ok: false,
      message: `Unsupported signalQuality field(s): ${unknownSqiKeys.join(", ")}`,
    };
  }

  const out = {};
  if (rawSqi.valid !== undefined) {
    if (typeof rawSqi.valid !== "boolean") {
      return { ok: false, message: "signalQuality.valid must be a boolean." };
    }
    out.valid = rawSqi.valid;
  }

  const scoreVal =
    rawSqi.sqi_score !== undefined ? rawSqi.sqi_score : rawSqi.sqiScore;
  if (scoreVal !== undefined) {
    if (
      typeof scoreVal !== "number" ||
      !Number.isFinite(scoreVal) ||
      scoreVal < 0 ||
      scoreVal > 1
    ) {
      return {
        ok: false,
        message: "signalQuality.sqi_score must be a finite number in [0, 1].",
      };
    }
    out.sqi_score = scoreVal;
  }

  if (rawSqi.reasons !== undefined) {
    if (
      !Array.isArray(rawSqi.reasons) ||
      rawSqi.reasons.length > 20 ||
      !rawSqi.reasons.every((r) => typeof r === "string" && r.length <= 160)
    ) {
      return {
        ok: false,
        message:
          "signalQuality.reasons must be an array of up to 20 short strings.",
      };
    }
    out.reasons = rawSqi.reasons;
  }

  const boolPairs = [
    ["ecg_valid", "ecgValid"],
    ["resp_valid", "respValid"],
  ];
  for (const [snake, camel] of boolPairs) {
    const v = rawSqi[snake] !== undefined ? rawSqi[snake] : rawSqi[camel];
    if (v !== undefined) {
      if (typeof v !== "boolean") {
        return { ok: false, message: `signalQuality.${snake} must be a boolean.` };
      }
      out[snake] = v;
    }
  }

  const fracPairs = [
    ["eeg_valid_fraction", "eegValidFraction"],
    ["gsr_valid_fraction", "gsrValidFraction"],
  ];
  for (const [snake, camel] of fracPairs) {
    const v = rawSqi[snake] !== undefined ? rawSqi[snake] : rawSqi[camel];
    if (v !== undefined) {
      if (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > 1) {
        return {
          ok: false,
          message: `signalQuality.${snake} must be a finite number in [0, 1].`,
        };
      }
      out[snake] = v;
    }
  }

  return { ok: true, value: out };
}

function validateAndNormalizeRequest(req) {
  const body = req.body;
  if (!isPlainObject(body)) {
    return {
      httpStatus: 400,
      error: buildSafeErrorResponse({
        code: "INVALID_PAYLOAD",
        message: "Request body must be a JSON object.",
      }),
    };
  }

  const keys = Object.keys(body);
  const rawKeys = keys.filter((k) => FORBIDDEN_RAW_SIGNAL_KEYS.has(k));
  if (rawKeys.length > 0) {
    return {
      httpStatus: 400,
      error: buildSafeErrorResponse({
        code: "RAW_SIGNAL_NOT_ACCEPTED",
        message: `Raw physiological signal fields (${rawKeys.join(", ")}) are rejected and not persisted.`,
      }),
    };
  }

  const unknownKeys = keys.filter((k) => !ALLOWED_BODY_KEYS.has(k));
  if (unknownKeys.length > 0) {
    return {
      httpStatus: 400,
      error: buildSafeErrorResponse({
        code: "UNKNOWN_FIELDS",
        message: `Unsupported request field(s): ${unknownKeys.join(", ")}`,
      }),
    };
  }

  const authenticatedUserId = String(req.user._id);
  const isAdmin = req.user.role === "admin";

  const requestedAstronautId =
    body.astronautId !== undefined ? body.astronautId : body.astronaut_id;
  if (requestedAstronautId !== undefined && requestedAstronautId !== null) {
    if (
      typeof requestedAstronautId !== "string" ||
      !SAFE_ID_RE.test(requestedAstronautId)
    ) {
      return {
        httpStatus: 400,
        error: buildSafeErrorResponse({
          code: "INVALID_ASTRONAUT_ID",
          message: "astronautId must be a safe identifier string (1-128 chars).",
        }),
      };
    }
    if (!isAdmin && requestedAstronautId !== authenticatedUserId) {
      return {
        httpStatus: 403,
        error: buildSafeErrorResponse({
          code: "FORBIDDEN_ASTRONAUT_ACCESS",
          message:
            "Non-admin users may only request cognitive state analysis for their own account.",
          astronautId: authenticatedUserId,
        }),
      };
    }
  }
  const effectiveAstronautId = requestedAstronautId || authenticatedUserId;

  const sessionId =
    body.sessionId !== undefined ? body.sessionId : body.session_id;
  if (sessionId !== undefined && sessionId !== null) {
    if (typeof sessionId !== "string" || !SAFE_ID_RE.test(sessionId)) {
      return {
        httpStatus: 400,
        error: buildSafeErrorResponse({
          code: "INVALID_SESSION_ID",
          message: "sessionId must be a safe identifier string (1-128 chars).",
          astronautId: effectiveAstronautId,
        }),
      };
    }
  }

  const mode = body.mode;
  const provenance =
    body.dataProvenance !== undefined
      ? body.dataProvenance
      : body.data_provenance;

  if (mode === "live_sensor" || provenance === "live_sensor") {
    return {
      httpStatus: 400,
      error: buildSafeErrorResponse({
        code: "LIVE_SENSOR_UNSUPPORTED",
        message:
          "Live-sensor inference is rejected until an approved signal schema, physical units, sampling rate, and verified real-data model artifact exist.",
        astronautId: effectiveAstronautId,
        sessionId: sessionId || null,
        mode: typeof mode === "string" ? mode : null,
        dataProvenance: "live_sensor",
      }),
    };
  }

  if (typeof mode !== "string" || !SUPPORTED_MODES.has(mode)) {
    return {
      httpStatus: 400,
      error: buildSafeErrorResponse({
        code: "INVALID_MODE",
        message:
          "mode is required and must be either 'synthetic_demo' or 'research_replay'.",
        astronautId: effectiveAstronautId,
        sessionId: sessionId || null,
        mode: typeof mode === "string" ? mode : null,
      }),
    };
  }

  if (provenance !== undefined && provenance !== null) {
    if (
      typeof provenance !== "string" ||
      !ALLOWED_PROVENANCES.has(provenance)
    ) {
      return {
        httpStatus: 400,
        error: buildSafeErrorResponse({
          code: "INVALID_PROVENANCE",
          message:
            "dataProvenance must be one of: synthetic, simulated, real_nasa_csm_replay.",
          astronautId: effectiveAstronautId,
          sessionId: sessionId || null,
          mode,
        }),
      };
    }
  }

  const windowEndSec =
    body.windowEndSec !== undefined ? body.windowEndSec : body.window_end_sec;
  if (windowEndSec !== undefined && windowEndSec !== null) {
    if (
      typeof windowEndSec !== "number" ||
      !Number.isFinite(windowEndSec) ||
      windowEndSec < 0 ||
      windowEndSec > 86400
    ) {
      return {
        httpStatus: 400,
        error: buildSafeErrorResponse({
          code: "INVALID_WINDOW_END_SEC",
          message: "windowEndSec must be a finite number in [0, 86400].",
          astronautId: effectiveAstronautId,
          sessionId: sessionId || null,
          mode,
        }),
      };
    }
  }

  const rawSqi =
    body.signalQuality !== undefined ? body.signalQuality : body.signal_quality;
  const sqiCheck = validateSignalQuality(rawSqi);
  if (!sqiCheck.ok) {
    return {
      httpStatus: 400,
      error: buildSafeErrorResponse({
        code: "INVALID_SIGNAL_QUALITY",
        message: sqiCheck.message,
        astronautId: effectiveAstronautId,
        sessionId: sessionId || null,
        mode,
      }),
    };
  }

  const upstreamPayload = {
    mode,
    astronaut_id: effectiveAstronautId,
  };
  if (sessionId) upstreamPayload.session_id = sessionId;
  if (windowEndSec !== undefined && windowEndSec !== null) {
    upstreamPayload.window_end_sec = windowEndSec;
  }
  if (provenance) upstreamPayload.data_provenance = provenance;
  if (sqiCheck.value !== undefined) {
    upstreamPayload.signal_quality = sqiCheck.value;
  }

  return { ok: true, payload: upstreamPayload };
}

// GET /api/cognitive-state/status
const getCognitiveStateStatus = async (req, res) => {
  const result = await fetchCsmStatus();
  return res.status(result.httpStatus).json(result.body);
};

// POST /api/cognitive-state/analyze
// Note: Does NOT persist raw signals and does NOT create automatic Alert records.
const analyzeCognitiveState = async (req, res) => {
  const check = validateAndNormalizeRequest(req);
  if (!check.ok) {
    return res.status(check.httpStatus).json(check.error);
  }

  const result = await requestCsmAnalysis(check.payload);
  return res.status(result.httpStatus).json(result.body);
};

module.exports = {
  getCognitiveStateStatus,
  analyzeCognitiveState,
  validateAndNormalizeRequest,
};
