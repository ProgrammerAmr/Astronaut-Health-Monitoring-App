"""
DEC-001 Crew Cognitive State Monitoring (CSM) — Feasibility Audit & Research Pipeline.

Governance Notice:
    This package provides reproducible local raw-data auditing, leakage-safe
    biomedical signal preprocessing, crew-grouped evaluation, candidate baseline
    models, and a non-diagnostic JSON contract. No trained model artifact is
    validated until the local Stop-Condition #1 audit passes on the official NASA
    CSM archives.
"""

from .constants import (
    CLASS_TO_INDEX,
    EEG_CHANNELS,
    EXPECTED_COLUMNS,
    FORBIDDEN_FEATURE_COLUMNS,
    INDEX_TO_CLASS,
    NOMINAL_FS_HZ,
    PERIPHERAL_CHANNELS,
    PUBLISHED_SUBJECT_IDS,
    RAW_EVENT_TO_CLASS,
    SIGNAL_CHANNELS,
    TARGET_CLASSES,
    subject_to_crew_id,
    subject_to_seat,
)

from .contract import (
    CSM_DISCLAIMER,
    CSM_SCHEMA_VERSION,
    build_csm_response,
    error_csm_response,
    verify_model_validation_artifact,
)

__all__ = [
    "CLASS_TO_INDEX",
    "CSM_DISCLAIMER",
    "CSM_SCHEMA_VERSION",
    "EEG_CHANNELS",
    "EXPECTED_COLUMNS",
    "FORBIDDEN_FEATURE_COLUMNS",
    "INDEX_TO_CLASS",
    "NOMINAL_FS_HZ",
    "PERIPHERAL_CHANNELS",
    "PUBLISHED_SUBJECT_IDS",
    "RAW_EVENT_TO_CLASS",
    "SIGNAL_CHANNELS",
    "TARGET_CLASSES",
    "build_csm_response",
    "error_csm_response",
    "subject_to_crew_id",
    "subject_to_seat",
    "verify_model_validation_artifact",
]
