"""
Official NASA Crew State Monitoring (CSM) dataset schema, provenance constants,
and biomedical signal processing defaults for DEC-001.

All dataset schema definitions are grounded directly in:
    https://data.nasa.gov/docs/datasets/public/csm/description.txt
and the official NASA Open Data Portal CKAN package:
    https://data.nasa.gov/api/3/action/package_show?id=flight-crew-physiological-data-for-crew-state-monitoring
"""

from __future__ import annotations

from typing import Dict, FrozenSet, Tuple

# ---------------------------------------------------------------------------
# Provenance & Official Portal Resources
# ---------------------------------------------------------------------------
NASA_DATASET_PAGE = (
    "https://data.nasa.gov/dataset/"
    "flight-crew-physiological-data-for-crew-state-monitoring"
)
NASA_BASE_URL = "https://data.nasa.gov/docs/datasets/public/csm"
NASA_DESCRIPTION_URL = f"{NASA_BASE_URL}/description.txt"

# Verified 17 subject ZIPs listed on data.nasa.gov (Subject 20 is absent despite
# description.txt stating 18 pilots).
PUBLISHED_SUBJECT_IDS: Tuple[int, ...] = (
    5, 6, 9, 10, 11, 12, 13, 14, 17, 18, 19, 21, 22, 23, 24, 25, 26
)
MISSING_EXPECTED_SUBJECT_IDS: Tuple[int, ...] = (20,)


def subject_zip_url(subject_id: int) -> str:
    return f"{NASA_BASE_URL}/{subject_id}.zip"


def subject_to_crew_id(subject_id: int) -> int:
    """
    Per description.txt:
    'Crews are pairs of subjects, so the i-th crew consists of subject 2i-1 and subject 2i.'
    Example: subjects 13 and 14 -> Crew 7.
    """
    if subject_id < 1:
        raise ValueError(f"subject_id must be >= 1, got {subject_id}")
    return (subject_id + 1) // 2


def subject_to_seat(subject_id: int) -> str:
    """Per description.txt: odd = left seat (Captain), even = right seat (First Officer)."""
    if subject_id < 1:
        raise ValueError(f"subject_id must be >= 1, got {subject_id}")
    return "left" if (subject_id % 2 == 1) else "right"


# ---------------------------------------------------------------------------
# Exact 25-Column Schema (from description.txt)
# ---------------------------------------------------------------------------
TIME_COLUMN = "TimeSecs"
EVENT_COLUMN = "Event"

EEG_CHANNELS: Tuple[str, ...] = (
    "EEG_FP1", "EEG_F7", "EEG_F8", "EEG_T4", "EEG_T6",
    "EEG_T5", "EEG_T3", "EEG_FP2", "EEG_O1", "EEG_P3",
    "EEG_Pz", "EEG_F3", "EEG_Fz", "EEG_F4", "EEG_C4",
    "EEG_P4", "EEG_POz", "EEG_C3", "EEG_Cz", "EEG_O2",
)

# Frontal / anterior-temporal channels most susceptible to EOG blinks & facial EMG
# Used for confounding-sensitivity ablations.
FRONTAL_EOG_PRONE_CHANNELS: FrozenSet[str] = frozenset({
    "EEG_FP1", "EEG_FP2", "EEG_F7", "EEG_F8",
})

PERIPHERAL_CHANNELS: Tuple[str, ...] = ("ECG", "R", "GSR")
SIGNAL_CHANNELS: Tuple[str, ...] = EEG_CHANNELS + PERIPHERAL_CHANNELS
EXPECTED_COLUMNS: Tuple[str, ...] = (TIME_COLUMN,) + SIGNAL_CHANNELS + (EVENT_COLUMN,)

# Session types per subject
BENCHMARK_SESSIONS: Tuple[str, ...] = ("CA", "DA", "SS")
LOFT_SESSION = "LOFT"
ALL_SESSION_TYPES: Tuple[str, ...] = BENCHMARK_SESSIONS + (LOFT_SESSION,)

# ---------------------------------------------------------------------------
# Official NASA Event Code Mapping -> Approved DEC-001 Target Classes
# ---------------------------------------------------------------------------
# Approved target classes (fixed integer indices 0..3 for ML models):
TARGET_CLASSES: Tuple[str, ...] = ("Baseline", "CA", "DA", "SS")
CLASS_TO_INDEX: Dict[str, int] = {name: idx for idx, name in enumerate(TARGET_CLASSES)}
INDEX_TO_CLASS: Dict[int, str] = {idx: name for idx, name in enumerate(TARGET_CLASSES)}

# Raw NASA CSV Event integer -> Approved class name
RAW_EVENT_TO_CLASS: Dict[int, str] = {
    0: "Baseline",
    1: "SS",
    2: "CA",
    5: "DA",
}

# Per description.txt: '3: There should be no 3s. If there are, treat them as 0s.'
# '4: There should be no 4s. If there are, treat them as 0s.'
# Tracked explicitly during audit so Baseline contamination is never hidden!
STRAY_EVENT_CODES: FrozenSet[int] = frozenset({3, 4})

# Columns that MUST NEVER be used as model input features (anti-leakage guard)
FORBIDDEN_FEATURE_COLUMNS: FrozenSet[str] = frozenset({
    TIME_COLUMN,
    EVENT_COLUMN,
    "time",
    "timestamp",
    "window_start_sec",
    "window_end_sec",
    "subject_id",
    "crew_id",
    "crew",
    "seat",
    "session_type",
    "experiment",
    "source_file",
    "segment_id",
    "label",
    "label_name",
    "label_purity",
    "sqi_valid",
    "sqi_score",
    "is_boundary",
})

# ---------------------------------------------------------------------------
# Biomedical Sampling & Sensor Specification Constants
# ---------------------------------------------------------------------------
NOMINAL_FS_HZ: float = 256.0
NOMINAL_DT_SEC: float = 1.0 / NOMINAL_FS_HZ

# NeXus-10 Mark II hardware range thresholds (from description.txt, in µV):
# ECG: -100 mV to +100 mV -> ±100,000 µV
# R / GSR: -2.0 V to +2.0 V -> ±2,000,000 µV
ECG_RAIL_UV: float = 99_000.0
RESP_GSR_RAIL_UV: float = 1_990_000.0

# Standard EEG canonical frequency bands (Hz) within 1–40 Hz analysis band
EEG_BANDS_HZ: Dict[str, Tuple[float, float]] = {
    "delta": (1.0, 4.0),
    "theta": (4.0, 8.0),
    "alpha": (8.0, 13.0),
    "low_beta": (13.0, 20.0),
    "high_beta": (20.0, 30.0),
    "low_gamma": (30.0, 40.0),
}

# Physiological HR / Respiration plausibility limits
MIN_RR_INTERVAL_SEC: float = 0.30   # 200 bpm upper HR bound
MAX_RR_INTERVAL_SEC: float = 1.80   # 33.3 bpm lower HR bound
RESP_BAND_HZ: Tuple[float, float] = (0.05, 1.0)
RESP_RATE_SEARCH_HZ: Tuple[float, float] = (0.08, 0.70)  # 4.8 to 42 breaths/min
GSR_DROPOUT_THRESHOLD: float = 0.0  # <= 0 indicates lead-off / zero-padding dropout
