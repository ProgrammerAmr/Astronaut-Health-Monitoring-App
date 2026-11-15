const axios = require("axios");

const CSM_SCHEMA_VERSION = "1.0-dec001-draft";
const DEFAULT_TIMEOUT_MS = 5000;
const MIN_TIMEOUT_MS = 500;
const MAX_TIMEOUT_MS = 30000;

const FIXED_DISCLAIMER =
  "Experimental research prototype — not a medical diagnosis or flight-certified system. " +
  "For non-diagnostic research and attention-awareness decision support only.";

const FIXED_LIMITATIONS = Object.freeze([
  "Experimental research prototype — not a medical diagnosis or flight-certified system.",
  "No trained or validated CSM model artifact is currently available; research replay abstains safely with INSUFFICIENT_DATA.",
  "NASA SHARP-1 cohort comprises 100% male commercial airline pilots in a 1g flight simulator; not validated on astronauts or microgravity physiology.",
  "Live-sensor inference is disabled until an approved signal schema, physical units, sampling rate, and verified real-data model artifact exist.",
  "Raw physiological waveforms are rejected and are not persisted.",
]);

function getConfiguredCsmConfig() {
  const rawUrl = (
    process.env.CSM_AI_SERVICE_URL ||
    process.env.AI_SERVICE_URL ||
    ""
  ).trim();

  let baseUrl = null;
  if (rawUrl) {
    try {
      const parsed = new URL(rawUrl);
      if (parsed.protocol === "http:" || parsed.protocol === "https:") {
        baseUrl = parsed.origin + parsed.pathname.replace(/\/+$/, "");
      }
    } catch {
      baseUrl = null;
    }
  }

  const rawTimeout = Number.parseInt(process.env.CSM_AI_TIMEOUT_MS || "", 10);
  const timeoutMs = Number.isFinite(rawTimeout)
    ? Math.min(MAX_TIMEOUT_MS, Math.max(MIN_TIMEOUT_MS, rawTimeout))
    : DEFAULT_TIMEOUT_MS;

  return { baseUrl, timeoutMs };
}

function buildSafeErrorResponse({
  code,
  message,
  astronautId = null,
  sessionId = null,
  mode = null,
  dataProvenance = "unknown",
}) {
  return {
    schema_version: CSM_SCHEMA_VERSION,
    status: "ERROR",
    mode,
    astronaut_id: astronautId,
    session_id: sessionId,
    window_end_sec: null,
    processed_at: new Date().toISOString(),
    data_provenance: dataProvenance,
    prediction: {
      state: null,
      probabilities: null,
      confidence: null,
      abstained: true,
    },
    signal_quality: {
      sqi_score: 0.0,
      valid: false,
      reasons: [code],
    },
    model_status: {
      model_id: null,
      validated: false,
      calibrated: false,
      evaluation_protocol: null,
      cohort_limitations: [...FIXED_LIMITATIONS],
    },
    warnings: [],
    errors: [{ code, message }],
    disclaimer: FIXED_DISCLAIMER,
  };
}

function isTimeoutError(err) {
  if (!err) return false;
  return (
    err.code === "ECONNABORTED" ||
    err.code === "ETIMEDOUT" ||
    err.code === "ERR_CANCELED" ||
    (typeof err.message === "string" && /timeout/i.test(err.message))
  );
}

async function fetchCsmStatus({ httpClient = axios } = {}) {
  const { baseUrl, timeoutMs } = getConfiguredCsmConfig();
  if (!baseUrl) {
    return {
      httpStatus: 503,
      body: {
        api_version: "v1",
        schema_version: CSM_SCHEMA_VERSION,
        service_available: false,
        registered_model_available: false,
        live_sensor_enabled: false,
        raw_signal_persistence: false,
        supported_modes: ["synthetic_demo", "research_replay"],
        model_status: {
          model_id: null,
          validated: false,
          calibrated: false,
          cohort_limitations: [...FIXED_LIMITATIONS],
        },
        limitations: [...FIXED_LIMITATIONS],
        errors: [
          {
            code: "CSM_SERVICE_UNCONFIGURED",
            message:
              "Cognitive state AI service URL is not configured (set CSM_AI_SERVICE_URL).",
          },
        ],
        disclaimer: FIXED_DISCLAIMER,
      },
    };
  }

  try {
    const resp = await httpClient.get(`${baseUrl}/csm/status`, {
      timeout: timeoutMs,
      maxContentLength: 256 * 1024,
      validateStatus: () => true,
    });

    if (
      resp.status >= 200 &&
      resp.status < 300 &&
      resp.data &&
      typeof resp.data === "object" &&
      !Array.isArray(resp.data)
    ) {
      return {
        httpStatus: 200,
        body: {
          api_version: resp.data.api_version || "v1",
          schema_version: resp.data.schema_version || CSM_SCHEMA_VERSION,
          service_available: Boolean(resp.data.service_available),
          registered_model_available: Boolean(
            resp.data.registered_model_available
          ),
          live_sensor_enabled: false,
          raw_signal_persistence: false,
          supported_modes: Array.isArray(resp.data.supported_modes)
            ? resp.data.supported_modes
            : ["synthetic_demo", "research_replay"],
          model_status: {
            model_id: resp.data.model_status?.model_id ?? null,
            validated: Boolean(resp.data.model_status?.validated === true),
            calibrated: Boolean(resp.data.model_status?.calibrated === true),
            cohort_limitations: [...FIXED_LIMITATIONS],
          },
          limitations: [...FIXED_LIMITATIONS],
          disclaimer: FIXED_DISCLAIMER,
        },
      };
    }

    return {
      httpStatus: 503,
      body: {
        api_version: "v1",
        schema_version: CSM_SCHEMA_VERSION,
        service_available: false,
        registered_model_available: false,
        live_sensor_enabled: false,
        raw_signal_persistence: false,
        supported_modes: ["synthetic_demo", "research_replay"],
        model_status: {
          model_id: null,
          validated: false,
          calibrated: false,
          cohort_limitations: [...FIXED_LIMITATIONS],
        },
        limitations: [...FIXED_LIMITATIONS],
        errors: [
          {
            code: "CSM_UPSTREAM_UNAVAILABLE",
            message: `Cognitive state AI service returned status ${resp.status}.`,
          },
        ],
        disclaimer: FIXED_DISCLAIMER,
      },
    };
  } catch (err) {
    const timedOut = isTimeoutError(err);
    return {
      httpStatus: timedOut ? 504 : 503,
      body: {
        api_version: "v1",
        schema_version: CSM_SCHEMA_VERSION,
        service_available: false,
        registered_model_available: false,
        live_sensor_enabled: false,
        raw_signal_persistence: false,
        supported_modes: ["synthetic_demo", "research_replay"],
        model_status: {
          model_id: null,
          validated: false,
          calibrated: false,
          cohort_limitations: [...FIXED_LIMITATIONS],
        },
        limitations: [...FIXED_LIMITATIONS],
        errors: [
          {
            code: timedOut ? "CSM_UPSTREAM_TIMEOUT" : "CSM_UPSTREAM_UNAVAILABLE",
            message: timedOut
              ? "Cognitive state AI service status request timed out."
              : "Cognitive state AI service is currently unreachable.",
          },
        ],
        disclaimer: FIXED_DISCLAIMER,
      },
    };
  }
}

async function requestCsmAnalysis(payload, { httpClient = axios } = {}) {
  const { baseUrl, timeoutMs } = getConfiguredCsmConfig();
  const baseMeta = {
    astronautId: payload.astronaut_id ?? null,
    sessionId: payload.session_id ?? null,
    mode: payload.mode ?? null,
    dataProvenance: payload.data_provenance ?? "unknown",
  };

  if (!baseUrl) {
    return {
      httpStatus: 503,
      body: buildSafeErrorResponse({
        ...baseMeta,
        code: "CSM_SERVICE_UNCONFIGURED",
        message:
          "Cognitive state AI service URL is not configured (set CSM_AI_SERVICE_URL).",
      }),
    };
  }

  try {
    const resp = await httpClient.post(`${baseUrl}/csm/analyze`, payload, {
      timeout: timeoutMs,
      maxBodyLength: 32 * 1024,
      maxContentLength: 256 * 1024,
      headers: { "Content-Type": "application/json" },
      validateStatus: () => true,
    });

    const data = resp.data;
    const isValidContract =
      data &&
      typeof data === "object" &&
      !Array.isArray(data) &&
      typeof data.status === "string" &&
      data.prediction &&
      typeof data.prediction === "object";

    if (resp.status >= 200 && resp.status < 300 && isValidContract) {
      return { httpStatus: 200, body: data };
    }

    if (resp.status >= 400 && resp.status < 500 && isValidContract) {
      return { httpStatus: resp.status, body: data };
    }

    return {
      httpStatus: 502,
      body: buildSafeErrorResponse({
        ...baseMeta,
        code: "CSM_UPSTREAM_INVALID_RESPONSE",
        message: `Cognitive state AI service returned an invalid or failed response (HTTP ${resp.status}). No prediction was substituted.`,
      }),
    };
  } catch (err) {
    const timedOut = isTimeoutError(err);
    return {
      httpStatus: timedOut ? 504 : 503,
      body: buildSafeErrorResponse({
        ...baseMeta,
        code: timedOut ? "CSM_UPSTREAM_TIMEOUT" : "CSM_UPSTREAM_UNAVAILABLE",
        message: timedOut
          ? "Cognitive state AI service request timed out. No prediction was substituted."
          : "Cognitive state AI service is currently unavailable. No prediction was substituted.",
      }),
    };
  }
}

module.exports = {
  CSM_SCHEMA_VERSION,
  FIXED_DISCLAIMER,
  FIXED_LIMITATIONS,
  getConfiguredCsmConfig,
  buildSafeErrorResponse,
  fetchCsmStatus,
  requestCsmAnalysis,
};
