"""
Leakage-safe biomedical signal preprocessing and Signal Quality Indexing (SQI)
for NASA CSM 256 Hz multimodal physiological recordings (EEG, ECG, Respiration, GSR).

Design invariants:
    1. Recordings are ALWAYS split at TimeSecs discontinuities (negative jumps,
       duplicates, or sampling gaps > max_gap_sec) before filtering or windowing.
    2. All Butterworth IIR filters use second-order sections (SOS) for numerical
       stability at low cutoff frequencies (e.g., 0.05 Hz @ 256 Hz).
    3. Causal filtering (sosfilt with steady-state zi initialization) is supported
       for real-time simulation; segment-local sosfiltfilt is supported for
       offline debrief replay (never spanning discontinuities or train/test splits).
    4. NeXus-10 true-DC offsets on ECG are removed per segment before QRS detection.
    5. GSR zero-dropouts (GSR <= 0) are explicitly masked before filtering and
       surfaced in WindowSQI so corrupted windows trigger INSUFFICIENT_DATA.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np
import pandas as pd
from scipy import signal

from .constants import (
    ECG_RAIL_UV,
    EEG_CHANNELS,
    GSR_DROPOUT_THRESHOLD,
    MAX_RR_INTERVAL_SEC,
    MIN_RR_INTERVAL_SEC,
    NOMINAL_FS_HZ,
    RESP_BAND_HZ,
    RESP_GSR_RAIL_UV,
    TIME_COLUMN,
)


@dataclass
class ContiguousSegment:
    """A single gap-free contiguous slice of a physiological recording."""
    segment_id: int
    start_row: int
    end_row: int  # exclusive
    df: pd.DataFrame


@dataclass
class PreprocessedSegment:
    """Filtered signals and per-sample validity masks for one contiguous segment."""
    segment_id: int
    fs: float
    time_secs: np.ndarray
    eeg: Dict[str, np.ndarray]           # filtered EEG channels
    eeg_valid_mask: Dict[str, np.ndarray]
    ecg_clean: np.ndarray                # 0.5-40 Hz DC-removed ECG
    ecg_qrs: np.ndarray                  # 5-15 Hz QRS-enhanced ECG
    ecg_valid_mask: np.ndarray
    resp_clean: np.ndarray               # 0.05-1.0 Hz detrended respiration
    resp_valid_mask: np.ndarray
    gsr_clean: np.ndarray                # 1.5 Hz low-passed GSR
    gsr_scl: np.ndarray                  # < 0.05 Hz tonic Skin Conductance Level
    gsr_scr: np.ndarray                  # 0.05-1.5 Hz phasic Skin Conductance Response
    gsr_valid_mask: np.ndarray           # False where GSR <= 0 or NaN/saturated
    events: Optional[np.ndarray] = None  # raw integer Event column if present


@dataclass
class WindowSQI:
    """Signal Quality Index (SQI) summary for one analysis window."""
    valid: bool
    sqi_score: float
    eeg_valid_fraction: float
    gsr_valid_fraction: float
    ecg_valid: bool
    resp_valid: bool
    reasons: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, object]:
        return {
            "valid": self.valid,
            "sqi_score": round(float(self.sqi_score), 4),
            "eeg_valid_fraction": round(float(self.eeg_valid_fraction), 4),
            "gsr_valid_fraction": round(float(self.gsr_valid_fraction), 4),
            "ecg_valid": bool(self.ecg_valid),
            "resp_valid": bool(self.resp_valid),
            "reasons": list(self.reasons),
        }


# ---------------------------------------------------------------------------
# 1. Discontinuity Detection & Segment Splitting
# ---------------------------------------------------------------------------
def split_contiguous_segments(
    df: pd.DataFrame,
    *,
    fs: float = NOMINAL_FS_HZ,
    max_gap_sec: float = 0.015,
    min_segment_samples: int = 256,
) -> List[ContiguousSegment]:
    """
    Split a recording DataFrame into strictly monotonic, gap-free segments.

    A new segment begins whenever:
        - dt <= 0 (timestamp reset, negative jump, or duplicate timestamp)
        - dt > (1/fs) + max_gap_sec (missing sample gap)
        - TimeSecs is NaN/Inf
    """
    if TIME_COLUMN not in df.columns:
        raise ValueError(f"Missing required timestamp column '{TIME_COLUMN}'")
    if len(df) == 0:
        return []

    t = pd.to_numeric(df[TIME_COLUMN], errors="coerce").to_numpy(dtype=np.float64)
    finite_mask = np.isfinite(t)
    if not np.all(finite_mask):
        # Drop non-finite timestamp rows while preserving order
        df = df.loc[finite_mask].reset_index(drop=True)
        t = t[finite_mask]
    if len(df) == 0:
        return []

    nominal_dt = 1.0 / fs
    dt = np.diff(t)
    break_indices = np.where((dt <= 0.0) | (dt > nominal_dt + max_gap_sec))[0] + 1

    boundaries = [0] + break_indices.tolist() + [len(df)]
    segments: List[ContiguousSegment] = []
    seg_id = 0
    for start, end in zip(boundaries[:-1], boundaries[1:]):
        if (end - start) >= min_segment_samples:
            segments.append(
                ContiguousSegment(
                    segment_id=seg_id,
                    start_row=int(start),
                    end_row=int(end),
                    df=df.iloc[start:end].reset_index(drop=True),
                )
            )
            seg_id += 1
    return segments


# ---------------------------------------------------------------------------
# 2. Numerically Stable SOS Filtering & Gap-Safe Interpolation Helpers
# ---------------------------------------------------------------------------
def _apply_sos(
    x: np.ndarray,
    sos: np.ndarray,
    *,
    causal: bool = True,
) -> np.ndarray:
    """Apply SOS IIR filter with either causal steady-state init or segment-local zero-phase."""
    x = np.asarray(x, dtype=np.float64)
    if x.size < 16 or not np.all(np.isfinite(x)):
        return x.copy()
    if causal:
        zi = signal.sosfilt_zi(sos) * x[0]
        y, _ = signal.sosfilt(sos, x, zi=zi)
        return y
    # Zero-phase requires enough samples for padding; fall back to causal if too short
    padlen = 3 * (2 * len(sos) + 1)
    if x.size <= padlen:
        zi = signal.sosfilt_zi(sos) * x[0]
        y, _ = signal.sosfilt(sos, x, zi=zi)
        return y
    return signal.sosfiltfilt(sos, x)


def _fill_invalid_for_filtering(
    x: np.ndarray,
    valid_mask: np.ndarray,
    max_interp_samples: int = 64,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Prepare a signal for IIR filtering without letting NaNs/dropouts explode.

    - Micro-gaps (<= max_interp_samples, e.g., 0.25 s at 256 Hz) are linearly
      interpolated AND upgraded to valid in `updated_valid_mask`.
    - Longer gaps are filled with boundary hold ONLY for filter numerical
      stability, while remaining False in `updated_valid_mask` so SQI catches them.
    """
    n = x.size
    out = x.astype(np.float64, copy=True)
    updated_valid = valid_mask.astype(bool, copy=True)

    valid_idx = np.where(updated_valid & np.isfinite(out))[0]
    if valid_idx.size == 0:
        return np.zeros(n, dtype=np.float64), np.zeros(n, dtype=bool)
    if valid_idx.size == n:
        return out, updated_valid

    # Linearly interpolate across all gaps for continuous filter input
    all_idx = np.arange(n)
    out = np.interp(all_idx, valid_idx, out[valid_idx])

    # Identify contiguous invalid runs; mark micro-gaps as repaired, keep long gaps False
    invalid = ~updated_valid
    padded = np.concatenate(([False], invalid, [False]))
    starts = np.where(padded[1:] & ~padded[:-1])[0]
    ends = np.where(~padded[1:] & padded[:-1])[0]
    for s, e in zip(starts, ends):
        if (e - s) <= max_interp_samples and s > 0 and e < n:
            updated_valid[s:e] = True
    return out, updated_valid


def _detect_flatline_mask(
    x: np.ndarray,
    *,
    fs: float = NOMINAL_FS_HZ,
    min_flat_sec: float = 1.0,
    eps: float = 1e-9,
) -> np.ndarray:
    """Return True where samples belong to a constant/flatline run >= min_flat_sec."""
    n = x.size
    min_run = max(2, int(round(min_flat_sec * fs)))
    if n < min_run:
        return np.zeros(n, dtype=bool)
    is_const_step = np.abs(np.diff(x)) <= eps
    padded = np.concatenate(([False], is_const_step, [False]))
    starts = np.where(padded[1:] & ~padded[:-1])[0]
    ends = np.where(~padded[1:] & padded[:-1])[0]
    flat = np.zeros(n, dtype=bool)
    for s, e in zip(starts, ends):
        if (e - s + 1) >= min_run:
            flat[s : e + 1] = True
    return flat


def _design_bandpass(low_hz: float, high_hz: float, fs: float, order: int = 4) -> np.ndarray:
    nyq = 0.5 * fs
    lo = max(1e-4, low_hz / nyq)
    hi = min(0.99, high_hz / nyq)
    return signal.butter(order, [lo, hi], btype="bandpass", output="sos")


def _design_lowpass(cutoff_hz: float, fs: float, order: int = 4) -> np.ndarray:
    nyq = 0.5 * fs
    wn = min(0.99, max(1e-4, cutoff_hz / nyq))
    return signal.butter(order, wn, btype="lowpass", output="sos")


def _design_notch_60hz(fs: float, q: float = 30.0) -> Optional[np.ndarray]:
    if fs <= 125.0:
        return None
    b, a = signal.iirnotch(w0=60.0, Q=q, fs=fs)
    return signal.tf2sos(b, a)


# ---------------------------------------------------------------------------
# 3. Modality-Specific Segment Preprocessing
# ---------------------------------------------------------------------------
def preprocess_segment(
    seg: ContiguousSegment,
    *,
    fs: float = NOMINAL_FS_HZ,
    causal: bool = True,
    apply_notch_60hz: bool = True,
    apply_eeg_car: bool = True,
    eeg_channels: Sequence[str] = EEG_CHANNELS,
) -> PreprocessedSegment:
    """
    Preprocess one gap-free contiguous segment across EEG, ECG, Respiration, and GSR.
    """
    df = seg.df
    n = len(df)
    time_secs = pd.to_numeric(df[TIME_COLUMN], errors="coerce").to_numpy(dtype=np.float64)

    events: Optional[np.ndarray] = None
    if "Event" in df.columns:
        events = pd.to_numeric(df["Event"], errors="coerce").fillna(-1).to_numpy(dtype=np.int64)

    sos_notch = _design_notch_60hz(fs) if apply_notch_60hz else None

    # --- EEG (1-40 Hz bandpass + optional 60 Hz notch + valid-channel CAR) ---
    sos_eeg = _design_bandpass(1.0, 40.0, fs, order=4)
    eeg_filtered: Dict[str, np.ndarray] = {}
    eeg_valid_masks: Dict[str, np.ndarray] = {}

    present_eeg = [ch for ch in eeg_channels if ch in df.columns]
    for ch in present_eeg:
        raw = pd.to_numeric(df[ch], errors="coerce").to_numpy(dtype=np.float64)
        finite = np.isfinite(raw)
        flat = _detect_flatline_mask(np.where(finite, raw, 0.0), fs=fs)
        valid = finite & ~flat
        filled, valid = _fill_invalid_for_filtering(raw, valid)
        # Per-segment DC removal (causal uses initial baseline median of first 1s)
        dc = float(np.median(filled[: min(n, int(fs))])) if causal else float(np.median(filled))
        centered = filled - dc
        y = _apply_sos(centered, sos_eeg, causal=causal)
        if sos_notch is not None:
            y = _apply_sos(y, sos_notch, causal=causal)
        eeg_filtered[ch] = y
        eeg_valid_masks[ch] = valid

    if apply_eeg_car and len(present_eeg) >= 4:
        # Compute Common Average Reference across channels that are valid at each sample
        stack = np.vstack([eeg_filtered[ch] for ch in present_eeg])
        mask_stack = np.vstack([eeg_valid_masks[ch] for ch in present_eeg]).astype(np.float64)
        valid_counts = mask_stack.sum(axis=0)
        safe_counts = np.where(valid_counts >= 4, valid_counts, 1.0)
        car = np.where(valid_counts >= 4, (stack * mask_stack).sum(axis=0) / safe_counts, 0.0)
        for ch in present_eeg:
            eeg_filtered[ch] = eeg_filtered[ch] - car

    # --- ECG (DC removal + 0.5-40 Hz clean + 5-15 Hz QRS band) ---
    if "ECG" in df.columns:
        raw_ecg = pd.to_numeric(df["ECG"], errors="coerce").to_numpy(dtype=np.float64)
        finite_ecg = np.isfinite(raw_ecg)
        sat_ecg = finite_ecg & (np.abs(raw_ecg) >= ECG_RAIL_UV)
        flat_ecg = _detect_flatline_mask(np.where(finite_ecg, raw_ecg, 0.0), fs=fs)
        ecg_valid = finite_ecg & ~sat_ecg & ~flat_ecg
        filled_ecg, ecg_valid = _fill_invalid_for_filtering(raw_ecg, ecg_valid)
        dc_ecg = float(np.median(filled_ecg[: min(n, int(fs))])) if causal else float(np.median(filled_ecg))
        centered_ecg = filled_ecg - dc_ecg
        ecg_clean = _apply_sos(centered_ecg, _design_bandpass(0.5, 40.0, fs, order=4), causal=causal)
        if sos_notch is not None:
            ecg_clean = _apply_sos(ecg_clean, sos_notch, causal=causal)
        ecg_qrs = _apply_sos(centered_ecg, _design_bandpass(5.0, 15.0, fs, order=3), causal=causal)
    else:
        ecg_clean = np.zeros(n, dtype=np.float64)
        ecg_qrs = np.zeros(n, dtype=np.float64)
        ecg_valid = np.zeros(n, dtype=bool)

    # --- Respiration (detrend + 0.05-1.0 Hz bandpass) ---
    if "R" in df.columns:
        raw_r = pd.to_numeric(df["R"], errors="coerce").to_numpy(dtype=np.float64)
        finite_r = np.isfinite(raw_r)
        sat_r = finite_r & (np.abs(raw_r) >= RESP_GSR_RAIL_UV)
        flat_r = _detect_flatline_mask(np.where(finite_r, raw_r, 0.0), fs=fs, min_flat_sec=2.0)
        resp_valid = finite_r & ~sat_r & ~flat_r
        filled_r, resp_valid = _fill_invalid_for_filtering(raw_r, resp_valid)
        dc_r = float(np.median(filled_r[: min(n, int(2 * fs))])) if causal else float(np.median(filled_r))
        resp_clean = _apply_sos(
            filled_r - dc_r,
            _design_bandpass(RESP_BAND_HZ[0], RESP_BAND_HZ[1], fs, order=3),
            causal=causal,
        )
    else:
        resp_clean = np.zeros(n, dtype=np.float64)
        resp_valid = np.zeros(n, dtype=bool)

    # --- GSR (zero-dropout masking + 1.5 Hz low-pass + tonic SCL / phasic SCR) ---
    if "GSR" in df.columns:
        raw_gsr = pd.to_numeric(df["GSR"], errors="coerce").to_numpy(dtype=np.float64)
        finite_gsr = np.isfinite(raw_gsr)
        dropout_gsr = finite_gsr & (raw_gsr <= GSR_DROPOUT_THRESHOLD)
        sat_gsr = finite_gsr & (np.abs(raw_gsr) >= RESP_GSR_RAIL_UV)
        flat_gsr = _detect_flatline_mask(np.where(finite_gsr, raw_gsr, 0.0), fs=fs, min_flat_sec=3.0)
        gsr_valid = finite_gsr & ~dropout_gsr & ~sat_gsr & ~flat_gsr
        filled_gsr, gsr_valid = _fill_invalid_for_filtering(raw_gsr, gsr_valid)
        gsr_clean = _apply_sos(filled_gsr, _design_lowpass(1.5, fs, order=3), causal=causal)
        gsr_scl = _apply_sos(gsr_clean, _design_lowpass(0.05, fs, order=2), causal=causal)
        gsr_scr = gsr_clean - gsr_scl
    else:
        gsr_clean = np.zeros(n, dtype=np.float64)
        gsr_scl = np.zeros(n, dtype=np.float64)
        gsr_scr = np.zeros(n, dtype=np.float64)
        gsr_valid = np.zeros(n, dtype=bool)

    return PreprocessedSegment(
        segment_id=seg.segment_id,
        fs=fs,
        time_secs=time_secs,
        eeg=eeg_filtered,
        eeg_valid_mask=eeg_valid_masks,
        ecg_clean=ecg_clean,
        ecg_qrs=ecg_qrs,
        ecg_valid_mask=ecg_valid,
        resp_clean=resp_clean,
        resp_valid_mask=resp_valid,
        gsr_clean=gsr_clean,
        gsr_scl=gsr_scl,
        gsr_scr=gsr_scr,
        gsr_valid_mask=gsr_valid,
        events=events,
    )


# ---------------------------------------------------------------------------
# 4. Pan-Tompkins-Style QRS Detector & Physiological RR Filtering
# ---------------------------------------------------------------------------
def detect_ecg_r_peaks(
    ecg_qrs: np.ndarray,
    *,
    fs: float = NOMINAL_FS_HZ,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Detect QRS R-peaks on 5-15 Hz bandpass-filtered ECG and return:
        (peak_indices, valid_rr_intervals_sec)

    Handles both upright and inverted ECG polarity by integrating the squared
    first derivative (Pan-Tompkins energy envelope). Rejects non-physiological
    RR intervals outside [0.30 s, 1.80 s] and ectopic beats deviating > 25%
    from the local median RR interval.
    """
    x = np.asarray(ecg_qrs, dtype=np.float64)
    if x.size < int(1.5 * fs) or np.std(x) < 1e-9:
        return np.array([], dtype=np.int64), np.array([], dtype=np.float64)

    # Differentiate -> square -> 150 ms moving average integration
    diff_x = np.diff(x, prepend=x[0])
    sq_x = diff_x * diff_x
    win = max(3, int(round(0.150 * fs)))
    kernel = np.ones(win, dtype=np.float64) / float(win)
    mwi = np.convolve(sq_x, kernel, mode="same")

    # Robust adaptive threshold
    p95 = float(np.percentile(mwi, 95))
    median_val = float(np.median(mwi))
    if p95 <= 1e-12:
        return np.array([], dtype=np.int64), np.array([], dtype=np.float64)
    threshold = median_val + 0.30 * (p95 - median_val)
    min_dist = max(1, int(round(0.28 * fs)))  # 280 ms refractory (~214 bpm max)

    raw_peaks, _ = signal.find_peaks(mwi, height=threshold, distance=min_dist)
    if raw_peaks.size < 2:
        return raw_peaks.astype(np.int64), np.array([], dtype=np.float64)

    # Refine peaks to local |ecg_qrs| extrema within ±80 ms
    search_rad = max(1, int(round(0.080 * fs)))
    refined: List[int] = []
    abs_x = np.abs(x)
    for pk in raw_peaks:
        lo = max(0, int(pk) - search_rad)
        hi = min(x.size, int(pk) + search_rad + 1)
        best = lo + int(np.argmax(abs_x[lo:hi]))
        if not refined or (best - refined[-1]) >= min_dist:
            refined.append(best)
    peak_idx = np.asarray(refined, dtype=np.int64)
    if peak_idx.size < 2:
        return peak_idx, np.array([], dtype=np.float64)

    rr = np.diff(peak_idx) / float(fs)
    phys_mask = (rr >= MIN_RR_INTERVAL_SEC) & (rr <= MAX_RR_INTERVAL_SEC)
    rr_phys = rr[phys_mask]
    if rr_phys.size < 2:
        return peak_idx, rr_phys

    # Ectopic / missed-beat filter relative to median RR
    med_rr = float(np.median(rr_phys))
    ectopic_mask = np.abs(rr_phys - med_rr) <= 0.25 * med_rr
    rr_clean = rr_phys[ectopic_mask]
    return peak_idx, rr_clean


# ---------------------------------------------------------------------------
# 5. Window-Level Signal Quality Index (SQI)
# ---------------------------------------------------------------------------
def compute_window_sqi(
    pre: PreprocessedSegment,
    start: int,
    end: int,
    *,
    required_modalities: Sequence[str] = ("eeg", "ecg", "resp", "gsr"),
    min_eeg_channel_fraction: float = 0.75,
    min_sample_valid_fraction: float = 0.80,
) -> WindowSQI:
    """
    Assess per-window signal quality across active modalities.

    Returns valid=False (triggering INSUFFICIENT_DATA abstention) whenever any
    required modality fails quality thresholds.
    """
    req = set(required_modalities)
    reasons: List[str] = []
    component_scores: List[float] = []

    # EEG quality
    if pre.eeg:
        ch_valid_fracs = [
            float(np.mean(pre.eeg_valid_mask[ch][start:end]))
            for ch in pre.eeg
        ]
        good_channels = sum(1 for f in ch_valid_fracs if f >= min_sample_valid_fraction)
        eeg_valid_fraction = good_channels / float(len(ch_valid_fracs))
    else:
        eeg_valid_fraction = 0.0

    if "eeg" in req:
        component_scores.append(eeg_valid_fraction)
        if eeg_valid_fraction < min_eeg_channel_fraction:
            reasons.append(
                f"EEG_LOW_QUALITY ({eeg_valid_fraction:.2f} < {min_eeg_channel_fraction:.2f})"
            )

    # ECG quality
    ecg_frac = float(np.mean(pre.ecg_valid_mask[start:end])) if end > start else 0.0
    _, rr_clean = detect_ecg_r_peaks(pre.ecg_qrs[start:end], fs=pre.fs)
    win_sec = max(1e-6, (end - start) / pre.fs)
    expected_min_beats = max(1, int(win_sec * 0.45))  # >= 27 bpm minimum beat count
    ecg_valid = (ecg_frac >= min_sample_valid_fraction) and (rr_clean.size >= expected_min_beats)
    if "ecg" in req:
        component_scores.append(ecg_frac if ecg_valid else 0.5 * ecg_frac)
        if not ecg_valid:
            reasons.append(
                f"ECG_LOW_QUALITY (valid_frac={ecg_frac:.2f}, valid_rr={rr_clean.size})"
            )

    # Respiration quality
    resp_frac = float(np.mean(pre.resp_valid_mask[start:end])) if end > start else 0.0
    resp_std = float(np.std(pre.resp_clean[start:end])) if end > start else 0.0
    resp_valid = (resp_frac >= min_sample_valid_fraction) and (resp_std > 1e-6)
    if "resp" in req:
        component_scores.append(resp_frac if resp_valid else 0.0)
        if not resp_valid:
            reasons.append(f"RESP_LOW_QUALITY (valid_frac={resp_frac:.2f}, std={resp_std:.2e})")

    # GSR quality (catches GSR == 0 lead-off dropouts)
    gsr_valid_fraction = float(np.mean(pre.gsr_valid_mask[start:end])) if end > start else 0.0
    gsr_ok = gsr_valid_fraction >= min_sample_valid_fraction
    if "gsr" in req:
        component_scores.append(gsr_valid_fraction)
        if not gsr_ok:
            reasons.append(
                f"GSR_DROPOUT_OR_INVALID ({gsr_valid_fraction:.2f} < {min_sample_valid_fraction:.2f})"
            )

    sqi_score = float(np.mean(component_scores)) if component_scores else 0.0
    overall_valid = len(reasons) == 0

    return WindowSQI(
        valid=overall_valid,
        sqi_score=sqi_score,
        eeg_valid_fraction=eeg_valid_fraction,
        gsr_valid_fraction=gsr_valid_fraction,
        ecg_valid=ecg_valid,
        resp_valid=resp_valid,
        reasons=reasons,
    )
