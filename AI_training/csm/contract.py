"""
Non-diagnostic JSON response contract for DEC-001 Crew Cognitive State Monitoring.

Design aligns directly with:
    - docs/ARCHITECTURE_AND_INTERFACES.md (§6, §7, §8)
    - docs/REQUIREMENTS_AND_EVALUATION.md (§2, §9)
    - AI_training/AI_README.md (consistent fail-safe contract & INSUFFICIENT_DATA abstention)

Key safety invariants:
    1. Low Signal Quality Index (SQI) or missing prediction/model ALWAYS returns
       status='INSUFFICIENT_DATA' with prediction.abstained=True and
       prediction.state=None — never silently defaults to 'Baseline' and never
       invents probabilities.
    2. model_status.validated ALWAYS defaults to False, and untrusted attempts
       to set model_validated=True without a verified, auditable real-data
       evaluation artifact are strictly REJECTED (never honored).
    3. data_provenance is mandatory and strictly distinguishes real replay,
       live sensor, simulated, and synthetic inputs.
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple, Union

from .constants import TARGET_CLASSES

CSM_SCHEMA_VERSION = "1.0-dec001-draft"

VALID_PROVENANCES = frozenset({
    "real_nasa_csm_replay",
    "live_sensor",
    "simulated",
    "synthetic",
})

CSM_DISCLAIMER = (
    "Experimental research prototype — not a medical diagnosis or flight-certified system. "
    "For non-diagnostic research and attention-awareness decision support only."
)

DEFAULT_COHORT_LIMITATIONS: Tuple[str, ...] = (
    "NASA SHARP-1 dataset comprises 100% male commercial airline pilots in a 1g flight simulator.",
    "Not validated on female subjects, astronaut cohorts, or microgravity physiology.",
    "No trained or validated CSM model artifact is shipped in this repository.",
    "Physiological markers are non-specific and can reflect motion, speech EMG, or thermal/autonomic load.",
)

_SHA256_HEX_RE = re.compile(r"^[0-9a-f]{64}$")


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def verify_model_validation_artifact(
    artifact_path: Union[str, Path],
) -> Tuple[bool, List[str]]:
    """
    Verify an on-disk evaluation artifact before allowing `model_status.validated=True`.

    Requires an auditable, real-data evaluation artifact proving:
        - scientifically_valid is strictly True
        - data_provenance is 'real_nasa_csm_local' (never synthetic/simulated)
        - audit_gate_verdict == 'READY_FOR_BENCHMARK_PHASE'
        - audit_manifest_sha256 is a valid 64-char SHA-256 hex digest
        - owner_signoff_recorded is strictly True with a non-empty reference
        - non-empty crew-grouped outer_test_calibrated metrics exist
    """
    reasons: List[str] = []
    path = Path(artifact_path)
    if not path.is_file():
        return False, [f"Validation artifact file does not exist: {path}"]

    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        return False, [f"Validation artifact is not valid JSON: {type(exc).__name__}: {exc}"]

    if not isinstance(payload, dict):
        return False, ["Validation artifact JSON root must be an object."]

    if payload.get("scientifically_valid") is not True:
        reasons.append("Artifact does not have scientifically_valid=true.")

    if payload.get("data_provenance") != "real_nasa_csm_local":
        reasons.append(
            f"Artifact data_provenance must be 'real_nasa_csm_local', got {payload.get('data_provenance')!r}."
        )

    if payload.get("audit_gate_verdict") != "READY_FOR_BENCHMARK_PHASE":
        reasons.append(
            f"Artifact audit_gate_verdict must be 'READY_FOR_BENCHMARK_PHASE', "
            f"got {payload.get('audit_gate_verdict')!r}."
        )

    manifest_hash = payload.get("audit_manifest_sha256")
    if not isinstance(manifest_hash, str) or not _SHA256_HEX_RE.match(manifest_hash):
        reasons.append("Artifact missing valid 64-hex audit_manifest_sha256.")

    if payload.get("owner_signoff_recorded") is not True:
        reasons.append("Artifact does not record explicit owner_signoff_recorded=true.")

    signoff_ref = payload.get("owner_signoff_reference")
    if not isinstance(signoff_ref, str) or not signoff_ref.strip():
        reasons.append("Artifact missing non-empty owner_signoff_reference.")

    runs = payload.get("runs")
    if not isinstance(runs, list) or len(runs) == 0:
        reasons.append("Artifact missing non-empty crew-grouped evaluation runs.")
    else:
        has_outer_metrics = any(
            isinstance(r, dict)
            and isinstance(r.get("outer_test_calibrated"), dict)
            and "macro_f1" in r["outer_test_calibrated"]
            for r in runs
        )
        if not has_outer_metrics:
            reasons.append("Artifact runs lack outer_test_calibrated evaluation metrics.")

    return len(reasons) == 0, reasons


def error_csm_response(
    code: str,
    message: str,
    *,
    astronaut_id: Optional[str] = None,
    session_id: Optional[str] = None,
    data_provenance: str = "unknown",
    mode: Optional[str] = None,
) -> Dict[str, Any]:
    """Fail-safe error contract; API wrappers should return this rather than raising."""
    return {
        "schema_version": CSM_SCHEMA_VERSION,
        "status": "ERROR",
        "mode": mode,
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
    model_id: Optional[str] = "untrained-draft",
    model_validated: bool = False,
    validation_artifact_path: Optional[Union[str, Path]] = None,
    calibrated: bool = False,
    evaluation_protocol: Optional[str] = None,
    mode: Optional[str] = None,
    abstention_reason: Optional[str] = None,
    extra_warnings: Optional[Sequence[str]] = None,
    cohort_limitations: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """
    Build a strictly typed, non-diagnostic DEC-001 cognitive state response.

    Security & scientific governance guard:
        Passing `model_validated=True` without a verifiable real-data
        `validation_artifact_path` is strictly REJECTED with an
        UNTRUSTED_VALIDATION_CLAIM error response (`model_status.validated=False`).
    """
    if data_provenance not in VALID_PROVENANCES:
        return error_csm_response(
            "INVALID_PROVENANCE",
            f"data_provenance must be one of {sorted(VALID_PROVENANCES)}, got {data_provenance!r}",
            astronaut_id=astronaut_id,
            session_id=session_id,
            data_provenance=str(data_provenance),
            mode=mode,
        )

    # Enforce verifiable model validation governance
    verified_validated = False
    if model_validated:
        if data_provenance in ("synthetic", "simulated"):
            return error_csm_response(
                "UNTRUSTED_VALIDATION_CLAIM",
                f"Cannot claim model_validated=true for non-real provenance {data_provenance!r}.",
                astronaut_id=astronaut_id,
                session_id=session_id,
                data_provenance=data_provenance,
                mode=mode,
            )
        if validation_artifact_path is None:
            return error_csm_response(
                "UNTRUSTED_VALIDATION_CLAIM",
                "Rejected untrusted model_validated=true without a verified real-data evaluation artifact.",
                astronaut_id=astronaut_id,
                session_id=session_id,
                data_provenance=data_provenance,
                mode=mode,
            )
        artifact_ok, artifact_reasons = verify_model_validation_artifact(validation_artifact_path)
        if not artifact_ok:
            return error_csm_response(
                "UNTRUSTED_VALIDATION_CLAIM",
                "Rejected model_validated=true: " + "; ".join(artifact_reasons),
                astronaut_id=astronaut_id,
                session_id=session_id,
                data_provenance=data_provenance,
                mode=mode,
            )
        verified_validated = True

    warnings: List[str] = list(extra_warnings or [])
    if not verified_validated:
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
            if not sqi_reasons:
                sqi_reasons = ["INSUFFICIENT_SIGNAL_QUALITY"]
        elif abstention_reason:
            warnings.append(abstention_reason)
            if abstention_reason not in sqi_reasons:
                sqi_reasons = [*sqi_reasons, abstention_reason]

        return {
            "schema_version": CSM_SCHEMA_VERSION,
            "status": "INSUFFICIENT_DATA",
            "mode": mode,
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
                "valid": sqi_valid,
                "reasons": sqi_reasons,
            },
            "model_status": {
                "model_id": model_id,
                "validated": False,
                "calibrated": False,
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
            mode=mode,
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
                mode=mode,
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
        "mode": mode,
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
            "validated": verified_validated,
            "calibrated": bool(calibrated),
            "evaluation_protocol": evaluation_protocol,
            "cohort_limitations": list(cohort_limitations or DEFAULT_COHORT_LIMITATIONS),
        },
        "warnings": warnings,
        "errors": [],
        "disclaimer": CSM_DISCLAIMER,
    }
