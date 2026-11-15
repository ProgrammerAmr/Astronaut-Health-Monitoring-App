"""
Non-diagnostic JSON response contract for DEC-001 Crew Cognitive State Monitoring.

Design aligns directly with:
    - docs/ARCHITECTURE_AND_INTERFACES.md (§6, §7, §8)
    - docs/REQUIREMENTS_AND_EVALUATION.md (§2, §9)
    - AI_training/AI_README.md (consistent fail-safe contract & INSUFFICIENT_DATA abstention)

Key safety invariants:
    1. Low Signal Quality Index (SQI) ALWAYS returns status='INSUFFICIENT_DATA'
       with prediction.abstained=True and prediction.state=None — never silently
       defaults to 'Baseline'.
    2. model_status.validated defaults to False and must NEVER be set True
       without documented crew-grouped evaluation evidence on real NASA CSM data.
    3. data_provenance is mandatory and strictly distinguishes real replay,
       live sensor, simulated, and synthetic inputs.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

from .constants import TARGET_CLASSES

CSM_SCHEMA_VERSION = "1.0-dec001-draft"

VALID_PROVENANCES = frozenset({
    "real_nasa_csm_replay",
    "live_sensor",
    "simulated",
    "synthetic",
})

CSM_DISCLAIMER = (
    "Experimental research prototype for attention-awareness support only. "
    "Not a medical diagnosis, not flight-certified, and not a substitute for "
    "professional medical or operational judgment."
)

DEFAULT_COHORT_LIMITATIONS: Tuple[str, ...] = (
    "NASA SHARP-1 dataset comprises 100% male commercial airline pilots in a 1g flight simulator.",
    "Not validated on female subjects, astronaut cohorts, or microgravity physiology.",
    "Physiological markers are non-specific and can reflect motion, speech EMG, or thermal/autonomic load.",
)


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def error_csm_response(
    code: str,
    message: str,
    *,
    astronaut_id: Optional[str] = None,
    session_id: Optional[str] = None,
    data_provenance: str = "unknown",
) -> Dict[str, Any]:
    """Fail-safe error contract; API wrappers should return this rather than raising."""
    return {
        "schema_version": CSM_SCHEMA_VERSION,
        "status": "ERROR",
        "astronaut_id": astronaut_id,
        "session_id": session_id,
        "window_end_sec": None,
        "processed_at": _utc_now_iso(),
        "data_provenance": data_provenance,
        "prediction": {
            "state": None,
            "probabilities": None,
            "confidence": None,
            "abstained": True,
        },
        "signal_quality": {
            "sqi_score": 0.0,
            "valid": False,
            "reasons": [code],
        },
        "model_status": {
            "model_id": None,
            "validated": False,
            "calibrated": False,
            "evaluation_protocol": None,
            "cohort_limitations": list(DEFAULT_COHORT_LIMITATIONS),
        },
        "warnings": [],
        "errors": [{"code": code, "message": message}],
        "disclaimer": CSM_DISCLAIMER,
    }


def build_csm_response(
    *,
    astronaut_id: Optional[str],
    session_id: Optional[str],
    window_end_sec: Optional[float],
    data_provenance: str,
    signal_quality: Mapping[str, Any],
    probabilities: Optional[Mapping[str, float]] = None,
    model_id: str = "untrained-draft",
    model_validated: bool = False,
    calibrated: bool = False,
    evaluation_protocol: Optional[str] = None,
    extra_warnings: Optional[Sequence[str]] = None,
    cohort_limitations: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Build a strictly typed, non-diagnostic DEC-001 cognitive state response."""
    if data_provenance not in VALID_PROVENANCES:
        return error_csm_response(
            "INVALID_PROVENANCE",
            f"data_provenance must be one of {sorted(VALID_PROVENANCES)}, got {data_provenance!r}",
            astronaut_id=astronaut_id,
            session_id=session_id,
            data_provenance=str(data_provenance),
        )

    warnings: List[str] = list(extra_warnings or [])
    if not model_validated:
        warnings.append("Model is NOT validated for operational use (model_status.validated=false).")
    if not calibrated:
        warnings.append("Output probabilities are uncalibrated; interpret confidence scores cautiously.")
    if data_provenance in ("simulated", "synthetic"):
        warnings.append(f"Input data provenance is '{data_provenance}' (not real physiological telemetry).")

    sqi_valid = bool(signal_quality.get("valid", False))
    sqi_score = float(signal_quality.get("sqi_score", 0.0))
    sqi_reasons = list(signal_quality.get("reasons", []))

    # Safety Gate: bad SQI or missing probabilities -> INSUFFICIENT_DATA (never default to Baseline)
    if not sqi_valid or probabilities is None:
        if not sqi_valid:
            warnings.append(
                f"Abstained due to insufficient signal quality (sqi_score={sqi_score:.2f})."
            )
        return {
            "schema_version": CSM_SCHEMA_VERSION,
            "status": "INSUFFICIENT_DATA",
            "astronaut_id": astronaut_id,
            "session_id": session_id,
            "window_end_sec": window_end_sec,
            "processed_at": _utc_now_iso(),
            "data_provenance": data_provenance,
            "prediction": {
                "state": None,
                "probabilities": None,
                "confidence": None,
                "abstained": True,
            },
            "signal_quality": {
                **dict(signal_quality),
                "sqi_score": round(sqi_score, 4),
                "valid": False,
                "reasons": sqi_reasons or ["INSUFFICIENT_SIGNAL_QUALITY"],
            },
            "model_status": {
                "model_id": model_id,
                "validated": bool(model_validated),
                "calibrated": bool(calibrated),
                "evaluation_protocol": evaluation_protocol,
                "cohort_limitations": list(cohort_limitations or DEFAULT_COHORT_LIMITATIONS),
            },
            "warnings": warnings,
            "errors": [],
            "disclaimer": CSM_DISCLAIMER,
        }

    # Validate probability keys and values
    missing_classes = [c for c in TARGET_CLASSES if c not in probabilities]
    if missing_classes:
        return error_csm_response(
            "INVALID_PROBABILITIES",
            f"Missing probability entries for classes: {missing_classes}",
            astronaut_id=astronaut_id,
            session_id=session_id,
            data_provenance=data_provenance,
        )

    cleaned_probs: Dict[str, float] = {}
    for cls_name in TARGET_CLASSES:
        val = float(probabilities[cls_name])
        if not (0.0 <= val <= 1.0) or val != val:  # NaN check
            return error_csm_response(
                "INVALID_PROBABILITY_VALUE",
                f"Probability for {cls_name} must be in [0, 1], got {val!r}",
                astronaut_id=astronaut_id,
                session_id=session_id,
                data_provenance=data_provenance,
            )
        cleaned_probs[cls_name] = round(val, 6)

    prob_sum = sum(cleaned_probs.values())
    if not (0.98 <= prob_sum <= 1.02):
        warnings.append(
            f"Class probabilities summed to {prob_sum:.4f} (expected ~1.0); check formulation/calibration."
        )

    best_state = max(TARGET_CLASSES, key=lambda c: cleaned_probs[c])
    confidence = cleaned_probs[best_state]

    return {
        "schema_version": CSM_SCHEMA_VERSION,
        "status": "OK",
        "astronaut_id": astronaut_id,
        "session_id": session_id,
        "window_end_sec": window_end_sec,
        "processed_at": _utc_now_iso(),
        "data_provenance": data_provenance,
        "prediction": {
            "state": best_state,
            "probabilities": cleaned_probs,
            "confidence": confidence,
            "abstained": False,
        },
        "signal_quality": {
            **dict(signal_quality),
            "sqi_score": round(sqi_score, 4),
            "valid": True,
            "reasons": sqi_reasons,
        },
        "model_status": {
            "model_id": model_id,
            "validated": bool(model_validated),
            "calibrated": bool(calibrated),
            "evaluation_protocol": evaluation_protocol,
            "cohort_limitations": list(cohort_limitations or DEFAULT_COHORT_LIMITATIONS),
        },
        "warnings": warnings,
        "errors": [],
        "disclaimer": CSM_DISCLAIMER,
    }
