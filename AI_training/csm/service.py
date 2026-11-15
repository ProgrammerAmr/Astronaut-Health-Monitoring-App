"""
Isolated FastAPI router and service logic for DEC-001 Cognitive State Monitoring.

Mounted by `AI_training/ai_service.py` without modifying existing `/health` or
`/analyze` vitals endpoints.

Hard safety invariants:
    1. Never claims diagnosis, medical validity, operational readiness,
       astronaut validation, flight certification, or live-sensor capability.
    2. Never invents class probabilities — when no verified model artifact
       exists, or SQI/evidence is insufficient, or only synthetic input is
       available, returns `status="INSUFFICIENT_DATA"` with `abstained=True`
       and `probabilities=None`.
    3. Rejects `live_sensor` inference until an approved signal schema,
       physical units, sampling rate, and verified real-data model artifact exist.
    4. Never persists raw physiological signals to disk, database, or logs.
"""

from __future__ import annotations

import json
import math
import os
import re
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Tuple

from fastapi import APIRouter, Body
from fastapi.responses import JSONResponse

from .contract import (
    CSM_DISCLAIMER,
    CSM_SCHEMA_VERSION,
    DEFAULT_COHORT_LIMITATIONS,
    VALID_PROVENANCES,
    build_csm_response,
    error_csm_response,
    verify_model_validation_artifact,
)

CSM_API_VERSION = "v1"
MAX_REQUEST_BYTES = 32 * 1024  # 32 KiB upper bound (raw waveforms are rejected)
SUPPORTED_MODES = ("synthetic_demo", "research_replay")
FORBIDDEN_RAW_SIGNAL_KEYS = frozenset({
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
})
ALLOWED_REQUEST_KEYS = frozenset({
    "mode",
    "astronaut_id",
    "session_id",
    "window_end_sec",
    "data_provenance",
    "signal_quality",
})
_ID_RE = re.compile(r"^[a-zA-Z0-9._:@/-]{1,128}$")
MIN_SQI_SCORE = 0.50


def get_registered_model_status() -> Dict[str, Any]:
    """
    Inspect optional environment-configured model registry paths.

    No trained or validated model artifact is shipped in this repository, so by
    default this reports `registered_model_available=False` and `validated=False`.
    """
    model_path_str = os.getenv("CSM_MODEL_ARTIFACT_PATH", "").strip()
    eval_path_str = os.getenv("CSM_VALIDATION_ARTIFACT_PATH", "").strip()

    model_exists = bool(model_path_str) and Path(model_path_str).is_file()
    validated = False
    validation_reasons: List[str] = []

    if eval_path_str:
        ok, reasons = verify_model_validation_artifact(eval_path_str)
        validated = ok and model_exists
        if not ok:
            validation_reasons = reasons
    else:
        validation_reasons = ["No verified real-data evaluation artifact configured."]

    return {
        "registered_model_available": model_exists,
        "model_id": Path(model_path_str).stem if model_exists else None,
        "validated": validated,
        "calibrated": False,
        "validation_artifact_checked": bool(eval_path_str),
        "validation_notes": validation_reasons,
        "cohort_limitations": list(DEFAULT_COHORT_LIMITATIONS),
    }


def get_csm_status() -> Dict[str, Any]:
    """Return service availability and fixed research limitations (never claims model health)."""
    reg = get_registered_model_status()
    return {
        "api_version": CSM_API_VERSION,
        "schema_version": CSM_SCHEMA_VERSION,
        "service_available": True,
        "supported_modes": list(SUPPORTED_MODES),
        "live_sensor_enabled": False,
        "raw_signal_persistence": False,
        "registered_model_available": reg["registered_model_available"],
        "model_status": {
            "model_id": reg["model_id"],
            "validated": reg["validated"],
            "calibrated": reg["calibrated"],
            "cohort_limitations": reg["cohort_limitations"],
        },
        "limitations": [
            "Experimental research prototype — not a medical diagnosis or flight-certified system.",
            "No trained or validated CSM model artifact is currently available; research replay abstains safely with INSUFFICIENT_DATA.",
            "Live-sensor inference is rejected until an approved signal schema, physical units, sampling rate, and verified model artifact exist.",
            "Raw physiological signals are rejected by this API and are not persisted.",
            *DEFAULT_COHORT_LIMITATIONS,
        ],
        "disclaimer": CSM_DISCLAIMER,
    }


def _validate_signal_quality(raw_sqi: Any) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    if raw_sqi is None:
        return None, None
    if not isinstance(raw_sqi, Mapping):
        return None, "signal_quality must be a JSON object when provided."

    valid = raw_sqi.get("valid")
    if valid is not None and not isinstance(valid, bool):
        return None, "signal_quality.valid must be a boolean."

    score = raw_sqi.get("sqi_score")
    if score is not None:
        if isinstance(score, bool) or not isinstance(score, (int, float)) or not math.isfinite(float(score)):
            return None, "signal_quality.sqi_score must be a finite number in [0.0, 1.0]."
        score_f = float(score)
        if score_f < 0.0 or score_f > 1.0:
            return None, "signal_quality.sqi_score must be between 0.0 and 1.0."
    else:
        score_f = 1.0 if valid is True else 0.0

    reasons = raw_sqi.get("reasons", [])
    if not isinstance(reasons, list) or len(reasons) > 20 or not all(
        isinstance(r, str) and len(r) <= 160 for r in reasons
    ):
        return None, "signal_quality.reasons must be a list of up to 20 short strings."

    inferred_valid = bool(valid) if isinstance(valid, bool) else (score_f >= MIN_SQI_SCORE)
    if score_f < MIN_SQI_SCORE:
        inferred_valid = False
        if "SQI_BELOW_THRESHOLD" not in reasons:
            reasons = [*reasons, "SQI_BELOW_THRESHOLD"]

    cleaned: Dict[str, Any] = {
        "valid": inferred_valid,
        "sqi_score": round(score_f, 4),
        "reasons": list(reasons),
    }
    for opt_bool in ("ecg_valid", "resp_valid"):
        if opt_bool in raw_sqi:
            if not isinstance(raw_sqi[opt_bool], bool):
                return None, f"signal_quality.{opt_bool} must be a boolean."
            cleaned[opt_bool] = raw_sqi[opt_bool]
    for opt_frac in ("eeg_valid_fraction", "gsr_valid_fraction"):
        if opt_frac in raw_sqi:
            v = raw_sqi[opt_frac]
            if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(float(v)) or not (0.0 <= float(v) <= 1.0):
                return None, f"signal_quality.{opt_frac} must be a finite number in [0.0, 1.0]."
            cleaned[opt_frac] = round(float(v), 4)

    return cleaned, None


def analyze_csm_payload(payload: Any) -> Tuple[int, Dict[str, Any]]:
    """
    Validate and process a CSM analyze request, returning (http_status, body).

    Strictly non-persisting, non-diagnostic, and fail-safe.
    """
    if not isinstance(payload, Mapping):
        return 400, error_csm_response(
            "INVALID_PAYLOAD",
            "Request body must be a JSON object.",
        )

    try:
        serialized_size = len(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    except Exception:  # noqa: BLE001
        return 400, error_csm_response("INVALID_PAYLOAD", "Request body is not JSON-serializable.")

    if serialized_size > MAX_REQUEST_BYTES:
        return 413, error_csm_response(
            "PAYLOAD_TOO_LARGE",
            f"Request body exceeds maximum allowed size of {MAX_REQUEST_BYTES} bytes.",
        )

    # Reject raw physiological signal uploads explicitly
    raw_keys_present = sorted(set(payload.keys()) & FORBIDDEN_RAW_SIGNAL_KEYS)
    if raw_keys_present:
        return 400, error_csm_response(
            "RAW_SIGNAL_NOT_ACCEPTED",
            f"Raw physiological signal fields ({raw_keys_present}) are not accepted or persisted by this endpoint.",
        )

    unknown_keys = sorted(set(payload.keys()) - ALLOWED_REQUEST_KEYS)
    if unknown_keys:
        return 400, error_csm_response(
            "UNKNOWN_FIELDS",
            f"Unsupported request field(s): {unknown_keys}. Allowed fields: {sorted(ALLOWED_REQUEST_KEYS)}.",
        )

    astronaut_id = payload.get("astronaut_id")
    if astronaut_id is not None:
        if not isinstance(astronaut_id, str) or not _ID_RE.match(astronaut_id):
            return 400, error_csm_response(
                "INVALID_ASTRONAUT_ID",
                "astronaut_id must be a safe identifier string (1-128 chars).",
            )

    session_id = payload.get("session_id")
    if session_id is not None:
        if not isinstance(session_id, str) or not _ID_RE.match(session_id):
            return 400, error_csm_response(
                "INVALID_SESSION_ID",
                "session_id must be a safe identifier string (1-128 chars).",
                astronaut_id=astronaut_id,
            )

    window_end_sec = payload.get("window_end_sec")
    if window_end_sec is not None:
        if (
            isinstance(window_end_sec, bool)
            or not isinstance(window_end_sec, (int, float))
            or not math.isfinite(float(window_end_sec))
            or float(window_end_sec) < 0.0
            or float(window_end_sec) > 86_400.0
        ):
            return 400, error_csm_response(
                "INVALID_WINDOW_END_SEC",
                "window_end_sec must be a finite number in [0, 86400].",
                astronaut_id=astronaut_id,
                session_id=session_id,
            )
        window_end_sec = float(window_end_sec)

    mode = payload.get("mode")
    raw_provenance = payload.get("data_provenance")

    # Reject live-sensor inference explicitly (either via mode or provenance)
    if mode == "live_sensor" or raw_provenance == "live_sensor":
        return 400, error_csm_response(
            "LIVE_SENSOR_UNSUPPORTED",
            "Live-sensor inference is rejected until an approved signal schema, physical units, "
            "sampling rate, and verified real-data model artifact exist.",
            astronaut_id=astronaut_id,
            session_id=session_id,
            data_provenance="live_sensor",
            mode=str(mode) if mode is not None else None,
        )

    if not isinstance(mode, str) or mode not in SUPPORTED_MODES:
        return 400, error_csm_response(
            "INVALID_MODE",
            f"mode is required and must be one of {list(SUPPORTED_MODES)}, got {mode!r}.",
            astronaut_id=astronaut_id,
            session_id=session_id,
            mode=str(mode) if mode is not None else None,
        )

    if raw_provenance is not None and (not isinstance(raw_provenance, str) or raw_provenance not in VALID_PROVENANCES):
        return 400, error_csm_response(
            "INVALID_PROVENANCE",
            f"data_provenance must be one of {sorted(VALID_PROVENANCES - {'live_sensor'})}, got {raw_provenance!r}.",
            astronaut_id=astronaut_id,
            session_id=session_id,
            mode=mode,
        )

    sqi_cleaned, sqi_err = _validate_signal_quality(payload.get("signal_quality"))
    if sqi_err is not None:
        return 400, error_csm_response(
            "INVALID_SIGNAL_QUALITY",
            sqi_err,
            astronaut_id=astronaut_id,
            session_id=session_id,
            data_provenance=raw_provenance or ("synthetic" if mode == "synthetic_demo" else "real_nasa_csm_replay"),
            mode=mode,
        )

    reg = get_registered_model_status()

    # Branch 1: Explicit synthetic demo mode
    if mode == "synthetic_demo":
        effective_sqi = sqi_cleaned or {
            "valid": True,
            "sqi_score": 0.92,
            "reasons": ["SYNTHETIC_DEMO_PREVIEW"],
        }
        # Never invent probabilities — abstain safely while clearly flagging synthetic demo mode
        resp = build_csm_response(
            astronaut_id=astronaut_id,
            session_id=session_id or "synthetic-demo-session",
            window_end_sec=window_end_sec if window_end_sec is not None else 0.0,
            data_provenance="synthetic",
            signal_quality=effective_sqi,
            probabilities=None,
            model_id=None,
            model_validated=False,
            calibrated=False,
            evaluation_protocol=None,
            mode="synthetic_demo",
            abstention_reason=(
                "INSUFFICIENT_SIGNAL_QUALITY"
                if not effective_sqi["valid"]
                else "SYNTHETIC_DEMO_NO_MODEL_PROBABILITIES"
            ),
            extra_warnings=[
                "Synthetic demo data: Explicitly requested synthetic_demo mode only. "
                "No real physiological telemetry and no registered CSM model exist; "
                "probabilities are intentionally withheld (not invented)."
            ],
        )
        resp["api_version"] = CSM_API_VERSION
        resp["demo_mode"] = True
        resp["raw_signal_persistence"] = False
        return 200, resp

    # Branch 2: research_replay mode
    effective_provenance = raw_provenance or "real_nasa_csm_replay"

    # Synthetic or simulated input in research_replay -> always abstain with INSUFFICIENT_DATA
    if effective_provenance in ("synthetic", "simulated"):
        resp = build_csm_response(
            astronaut_id=astronaut_id,
            session_id=session_id,
            window_end_sec=window_end_sec,
            data_provenance=effective_provenance,
            signal_quality=sqi_cleaned or {
                "valid": False,
                "sqi_score": 0.0,
                "reasons": ["SYNTHETIC_INPUT_NOT_ELIGIBLE_FOR_RESEARCH_REPLAY"],
            },
            probabilities=None,
            model_id=None,
            model_validated=False,
            calibrated=False,
            mode="research_replay",
            abstention_reason="SYNTHETIC_INPUT_NOT_ELIGIBLE_FOR_RESEARCH_REPLAY",
            extra_warnings=[
                "Research replay abstained because input provenance is synthetic/simulated rather than real NASA CSM replay data."
            ],
        )
        resp["api_version"] = CSM_API_VERSION
        resp["demo_mode"] = False
        resp["raw_signal_persistence"] = False
        return 200, resp

    # Missing signal quality evidence -> abstain with INSUFFICIENT_DATA
    if sqi_cleaned is None:
        resp = build_csm_response(
            astronaut_id=astronaut_id,
            session_id=session_id,
            window_end_sec=window_end_sec,
            data_provenance=effective_provenance,
            signal_quality={
                "valid": False,
                "sqi_score": 0.0,
                "reasons": ["MISSING_SIGNAL_QUALITY_EVIDENCE"],
            },
            probabilities=None,
            model_id=reg["model_id"],
            model_validated=False,
            calibrated=False,
            mode="research_replay",
            abstention_reason="MISSING_SIGNAL_QUALITY_EVIDENCE",
            extra_warnings=[
                "Research replay abstained because required signal_quality evidence was not supplied."
            ],
        )
        resp["api_version"] = CSM_API_VERSION
        resp["demo_mode"] = False
        resp["raw_signal_persistence"] = False
        return 200, resp

    # Low SQI -> abstain with INSUFFICIENT_DATA
    if not sqi_cleaned["valid"]:
        resp = build_csm_response(
            astronaut_id=astronaut_id,
            session_id=session_id,
            window_end_sec=window_end_sec,
            data_provenance=effective_provenance,
            signal_quality=sqi_cleaned,
            probabilities=None,
            model_id=reg["model_id"],
            model_validated=False,
            calibrated=False,
            mode="research_replay",
            abstention_reason="INSUFFICIENT_SIGNAL_QUALITY",
        )
        resp["api_version"] = CSM_API_VERSION
        resp["demo_mode"] = False
        resp["raw_signal_persistence"] = False
        return 200, resp

    # No registered / verified model artifact -> abstain safely (never invent probabilities!)
    resp = build_csm_response(
        astronaut_id=astronaut_id,
        session_id=session_id,
        window_end_sec=window_end_sec,
        data_provenance=effective_provenance,
        signal_quality=sqi_cleaned,
        probabilities=None,
        model_id=reg["model_id"],
        model_validated=False,
        calibrated=False,
        mode="research_replay",
        abstention_reason="NO_REGISTERED_MODEL_ARTIFACT",
        extra_warnings=[
            "No trained or verified CSM model artifact is registered. "
            "Abstaining safely with INSUFFICIENT_DATA instead of inventing probabilities."
        ],
    )
    resp["api_version"] = CSM_API_VERSION
    resp["demo_mode"] = False
    resp["raw_signal_persistence"] = False
    return 200, resp


router = APIRouter(prefix="/csm", tags=["DEC-001 Cognitive State Monitoring (Research)"])


@router.get("/status")
def csm_status_endpoint() -> Dict[str, Any]:
    """Service availability & fixed research limitations (non-diagnostic)."""
    return get_csm_status()


@router.post("/analyze")
def csm_analyze_endpoint(payload: Any = Body(...)) -> JSONResponse:
    """Versioned DEC-001 research endpoint; never invents probabilities or persists raw signals."""
    status_code, body = analyze_csm_payload(payload)
    return JSONResponse(status_code=status_code, content=body)
