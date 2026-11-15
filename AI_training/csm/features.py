"""
Dual-scale causal windowing and neurophysiological feature extraction for DEC-001.

Implements:
    - Fast trailing window (default 5.0 s): EEG relative spectral bands, NASA
      Engagement Index (beta / (alpha + theta)), Frontal-Theta/Parietal-Alpha,
      Frontal Alpha Asymmetry, Hjorth parameters, spectral entropy, acute HR,
      and phasic GSR SCR metrics.
    - Slow trailing context window (default 30.0 s, strictly causal): stable
      Respiration Rate (0.08-0.70 Hz), time-domain HRV (RMSSD, SDNN), HR delta
      vs. slow baseline, and tonic GSR SCL slope.
    - Explicit ablation switches:
        * modalities: e.g., ("eeg", "ecg", "resp", "gsr") or wearable-feasible ("ecg", "resp")
        * exclude_frontal_eog: drops EEG_FP1/FP2/F7/F8 to quantify blink/EMG confounding
    - Physical separation of features from metadata so forbidden columns
      (TimeSecs, crew_id, subject_id, seat, session_type) can NEVER leak into X.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np
import pandas as pd
from scipy import signal, stats

from .constants import (
    CLASS_TO_INDEX,
    EEG_BANDS_HZ,
    EEG_CHANNELS,
    FRONTAL_EOG_PRONE_CHANNELS,
    NOMINAL_FS_HZ,
    RAW_EVENT_TO_CLASS,
    RESP_RATE_SEARCH_HZ,
    STRAY_EVENT_CODES,
    subject_to_crew_id,
    subject_to_seat,
)
from .preprocessing import (
    PreprocessedSegment,
    compute_window_sqi,
    detect_ecg_r_peaks,
    preprocess_segment,
    split_contiguous_segments,
)


@dataclass
class FeatureConfig:
    """Configuration for causal dual-scale windowing and feature extraction."""
    fs: float = NOMINAL_FS_HZ
    fast_window_sec: float = 5.0
    slow_window_sec: float = 30.0
    stride_sec: float = 5.0
    minority_stride_sec: Optional[float] = None  # optional denser stride for DA/SS in train only
    modalities: Tuple[str, ...] = ("eeg", "ecg", "resp", "gsr")
    exclude_frontal_eog: bool = False
    causal_filtering: bool = True
    apply_notch_60hz: bool = True
    apply_eeg_car: bool = True
    min_label_purity: float = 0.95  # drop mixed transition windows when training
    treat_stray_3_4_as_baseline: bool = False  # False = drop/flag rather than silently contaminate


# ---------------------------------------------------------------------------
# Single-Window Signal Feature Helpers
# ---------------------------------------------------------------------------
def _safe_skew_kurtosis(x: np.ndarray) -> Tuple[float, float]:
    if x.size < 4 or float(np.std(x)) < 1e-12:
        return 0.0, 0.0
    sk = float(stats.skew(x, bias=False))
    ku = float(stats.kurtosis(x, bias=False))
    return (sk if np.isfinite(sk) else 0.0), (ku if np.isfinite(ku) else 0.0)


def _hjorth_parameters(x: np.ndarray) -> Tuple[float, float, float]:
    """Compute Hjorth activity (var), mobility, and complexity safely."""
    var0 = float(np.var(x))
    if var0 <= 1e-18:
        return 0.0, 0.0, 0.0
    d1 = np.diff(x)
    var1 = float(np.var(d1))
    if var1 <= 1e-18:
        return var0, 0.0, 0.0
    mobility = float(np.sqrt(var1 / var0))
    d2 = np.diff(d1)
    var2 = float(np.var(d2))
    complexity = float(np.sqrt(var2 / var1) / mobility) if (var2 > 1e-18 and mobility > 1e-12) else 0.0
    return var0, mobility, complexity


def _spectral_entropy(psd: np.ndarray) -> float:
    total = float(np.sum(psd))
    if total <= 1e-18:
        return 0.0
    p = psd / total
    p = p[p > 0.0]
    if p.size <= 1:
        return 0.0
    return float(-np.sum(p * np.log2(p)) / np.log2(psd.size))


def _extract_eeg_window_features(
    pre: PreprocessedSegment,
    start: int,
    end: int,
    *,
    exclude_frontal_eog: bool = False,
) -> Dict[str, float]:
    feats: Dict[str, float] = {}
    channels = [
        ch for ch in pre.eeg.keys()
        if (not exclude_frontal_eog) or (ch not in FRONTAL_EOG_PRONE_CHANNELS)
    ]
    if not channels:
        return feats

    n_win = end - start
    nperseg = min(n_win, int(2.0 * pre.fs))  # 2 s Welch segments -> 0.5 Hz resolution
    band_rel_by_ch: Dict[str, Dict[str, float]] = {}

    for ch in channels:
        x = pre.eeg[ch][start:end]
        freqs, psd = signal.welch(x, fs=pre.fs, nperseg=nperseg)
        in_band = (freqs >= 1.0) & (freqs <= 40.0)
        psd_in = psd[in_band]
        freqs_in = freqs[in_band]
        total_power = float(np.trapezoid(psd_in, freqs_in)) if psd_in.size > 1 else 0.0
        safe_total = total_power if total_power > 1e-18 else 1e-18

        ch_bands: Dict[str, float] = {}
        for bname, (f_lo, f_hi) in EEG_BANDS_HZ.items():
            bmask = (freqs_in >= f_lo) & (freqs_in < f_hi)
            bp = float(np.trapezoid(psd_in[bmask], freqs_in[bmask])) if np.sum(bmask) >= 2 else (
                float(np.sum(psd_in[bmask])) if np.any(bmask) else 0.0
            )
            rel = bp / safe_total
            ch_bands[bname] = rel
            feats[f"{ch}_rel_{bname}"] = rel
            feats[f"{ch}_log_{bname}"] = float(np.log1p(max(0.0, bp)))

        band_rel_by_ch[ch] = ch_bands
        act, mob, comp = _hjorth_parameters(x)
        feats[f"{ch}_hjorth_log_act"] = float(np.log1p(max(0.0, act)))
        feats[f"{ch}_hjorth_mob"] = mob
        feats[f"{ch}_hjorth_comp"] = comp
        feats[f"{ch}_spec_entropy"] = _spectral_entropy(psd_in)

    # Cross-channel neurophysiological summary indices
    all_alpha = float(np.mean([band_rel_by_ch[c]["alpha"] for c in channels]))
    all_theta = float(np.mean([band_rel_by_ch[c]["theta"] for c in channels]))
    all_beta = float(
        np.mean([band_rel_by_ch[c]["low_beta"] + band_rel_by_ch[c]["high_beta"] for c in channels])
    )
    # NASA Engagement Index (Pope et al., 1995): beta / (alpha + theta)
    feats["eeg_nasa_engagement_index"] = all_beta / max(1e-6, all_alpha + all_theta)

    # Frontal-Theta / Parietal-Alpha workload ratio
    if "EEG_Fz" in band_rel_by_ch and "EEG_Pz" in band_rel_by_ch:
        feats["eeg_fz_theta_pz_alpha_ratio"] = band_rel_by_ch["EEG_Fz"]["theta"] / max(
            1e-6, band_rel_by_ch["EEG_Pz"]["alpha"]
        )
    else:
        feats["eeg_fz_theta_pz_alpha_ratio"] = all_theta / max(1e-6, all_alpha)

    # Frontal Alpha Asymmetry: ln(F4_alpha) - ln(F3_alpha)
    if "EEG_F4" in band_rel_by_ch and "EEG_F3" in band_rel_by_ch:
        feats["eeg_frontal_alpha_asymmetry"] = float(
            np.log(max(1e-6, band_rel_by_ch["EEG_F4"]["alpha"]))
            - np.log(max(1e-6, band_rel_by_ch["EEG_F3"]["alpha"]))
        )
    else:
        feats["eeg_frontal_alpha_asymmetry"] = 0.0

    # High-frequency EMG contamination indicator (low_gamma / alpha ratio)
    all_gamma = float(np.mean([band_rel_by_ch[c]["low_gamma"] for c in channels]))
    feats["eeg_mean_gamma_alpha_ratio"] = all_gamma / max(1e-6, all_alpha)
    return feats


def _extract_ecg_window_features(
    pre: PreprocessedSegment,
    fast_start: int,
    slow_start: int,
    end: int,
) -> Dict[str, float]:
    ecg_fast = pre.ecg_clean[fast_start:end]
    _, rr_fast = detect_ecg_r_peaks(pre.ecg_qrs[fast_start:end], fs=pre.fs)
    _, rr_slow = detect_ecg_r_peaks(pre.ecg_qrs[slow_start:end], fs=pre.fs)

    hr_fast = float(60.0 / np.mean(rr_fast)) if rr_fast.size >= 1 else np.nan
    hr_slow = float(60.0 / np.mean(rr_slow)) if rr_slow.size >= 1 else np.nan
    hr_delta = (hr_fast - hr_slow) if (np.isfinite(hr_fast) and np.isfinite(hr_slow)) else 0.0

    if rr_slow.size >= 3:
        rr_ms = rr_slow * 1000.0
        sdnn_ms = float(np.std(rr_ms, ddof=1))
        rmssd_ms = float(np.sqrt(np.mean(np.diff(rr_ms) ** 2)))
    else:
        sdnn_ms = np.nan
        rmssd_ms = np.nan

    q75, q25 = np.percentile(ecg_fast, [75, 25]) if ecg_fast.size >= 4 else (0.0, 0.0)
    skew_v, kurt_v = _safe_skew_kurtosis(ecg_fast)

    return {
        "ecg_hr_bpm_fast": hr_fast,
        "ecg_hr_bpm_slow": hr_slow,
        "ecg_hr_delta_bpm": hr_delta,
        "ecg_rmssd_ms": rmssd_ms,
        "ecg_sdnn_ms": sdnn_ms,
        "ecg_iqr": float(q75 - q25),
        "ecg_skew": skew_v,
        "ecg_kurtosis": kurt_v,
    }


def _extract_resp_window_features(
    pre: PreprocessedSegment,
    slow_start: int,
    end: int,
) -> Dict[str, float]:
    r_slow = pre.resp_clean[slow_start:end]
    n = r_slow.size
    if n < int(4.0 * pre.fs) or float(np.std(r_slow)) < 1e-9:
        return {
            "resp_rate_bpm": np.nan,
            "resp_spectral_entropy": 0.0,
            "resp_iqr": 0.0,
            "resp_peak_to_peak": 0.0,
        }

    # High frequency-resolution Welch PSD on trailing slow context window
    nperseg = min(n, int(16.0 * pre.fs))
    nfft = max(nperseg, int(32.0 * pre.fs))  # zero-padded for 0.03125 Hz bin spacing (~1.9 bpm)
    freqs, psd = signal.welch(r_slow, fs=pre.fs, nperseg=nperseg, nfft=nfft)
    f_lo, f_hi = RESP_RATE_SEARCH_HZ
    mask = (freqs >= f_lo) & (freqs <= f_hi)
    if np.any(mask) and float(np.max(psd[mask])) > 1e-18:
        peak_freq = float(freqs[mask][int(np.argmax(psd[mask]))])
        resp_rate_bpm = peak_freq * 60.0
        spec_ent = _spectral_entropy(psd[mask])
    else:
        resp_rate_bpm = np.nan
        spec_ent = 0.0

    q95, q75, q25, q05 = np.percentile(r_slow, [95, 75, 25, 5])
    return {
        "resp_rate_bpm": resp_rate_bpm,
        "resp_spectral_entropy": spec_ent,
        "resp_iqr": float(q75 - q25),
        "resp_peak_to_peak": float(q95 - q05),
    }


def _extract_gsr_window_features(
    pre: PreprocessedSegment,
    fast_start: int,
    slow_start: int,
    end: int,
) -> Dict[str, float]:
    scl_slow = pre.gsr_scl[slow_start:end]
    scr_fast = pre.gsr_scr[fast_start:end]
    valid_fast = pre.gsr_valid_mask[fast_start:end]
    valid_frac = float(np.mean(valid_fast)) if valid_fast.size > 0 else 0.0

    # Tonic SCL slope over trailing slow window
    if scl_slow.size >= 4:
        t_axis = np.arange(scl_slow.size, dtype=np.float64) / pre.fs
        t_centered = t_axis - np.mean(t_axis)
        denom = float(np.sum(t_centered * t_centered))
        scl_slope = float(np.sum(t_centered * (scl_slow - np.mean(scl_slow))) / denom) if denom > 0 else 0.0
        scl_mean = float(np.mean(scl_slow))
    else:
        scl_slope = 0.0
        scl_mean = 0.0

    # Phasic SCR peaks & NASA Harrivel (2017) slope + drop score
    gsr_fast = pre.gsr_clean[fast_start:end]
    d_gsr = np.diff(gsr_fast) if gsr_fast.size >= 2 else np.array([0.0])
    mean_slope = float(np.mean(d_gsr))
    # Harrivel et al. (2017) §III.A: count of time instances where GSR slope drops below -0.25
    drop_score = float(np.sum(d_gsr < -0.25)) / max(1.0, float(d_gsr.size))

    scr_std = float(np.std(scr_fast))
    if scr_fast.size >= int(pre.fs) and scr_std > 1e-6:
        peaks, props = signal.find_peaks(
            scr_fast,
            height=max(0.5 * scr_std, 1e-3),
            distance=int(0.8 * pre.fs),
        )
        scr_peak_count = float(peaks.size)
        scr_max = float(np.max(props["peak_heights"])) if peaks.size > 0 else 0.0
    else:
        scr_peak_count = 0.0
        scr_max = 0.0

    return {
        "gsr_scl_mean": scl_mean,
        "gsr_scl_slope": scl_slope,
        "gsr_scr_peak_count": scr_peak_count,
        "gsr_scr_max": scr_max,
        "gsr_mean_slope": mean_slope,
        "gsr_drop_score": drop_score,
        "gsr_valid_fraction": valid_frac,
    }


# ---------------------------------------------------------------------------
# Label Resolution for One Window
# ---------------------------------------------------------------------------
def _resolve_window_label(
    raw_events: Optional[np.ndarray],
    start: int,
    end: int,
    *,
    treat_stray_3_4_as_baseline: bool = False,
) -> Tuple[Optional[int], Optional[str], float, bool, int]:
    """
    Resolve ground-truth class for a window [start, end).

    Returns:
        (label_idx, label_name, purity, is_boundary, stray_3_4_count)
    """
    if raw_events is None:
        return None, None, 0.0, False, 0

    slice_ev = raw_events[start:end]
    stray_count = int(np.sum(np.isin(slice_ev, list(STRAY_EVENT_CODES))))

    mapped: List[int] = []
    for code in slice_ev.tolist():
        if code in RAW_EVENT_TO_CLASS:
            mapped.append(CLASS_TO_INDEX[RAW_EVENT_TO_CLASS[code]])
        elif code in STRAY_EVENT_CODES and treat_stray_3_4_as_baseline:
            mapped.append(CLASS_TO_INDEX["Baseline"])

    if len(mapped) != slice_ev.size or len(mapped) == 0:
        return None, None, 0.0, True, stray_count

    arr = np.asarray(mapped, dtype=np.int64)
    vals, counts = np.unique(arr, return_counts=True)
    best_pos = int(np.argmax(counts))
    best_idx = int(vals[best_pos])
    purity = float(counts[best_pos] / arr.size)
    is_boundary = bool(vals.size > 1)
    from .constants import INDEX_TO_CLASS
    return best_idx, INDEX_TO_CLASS[best_idx], purity, is_boundary, stray_count


# ---------------------------------------------------------------------------
# End-to-End Session Feature Extraction
# ---------------------------------------------------------------------------
def extract_session_features(
    df: pd.DataFrame,
    *,
    subject_id: int,
    session_type: str,
    config: Optional[FeatureConfig] = None,
    is_training: bool = True,
    source_file: str = "",
) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """
    Extract strictly causal dual-scale features from one recording CSV DataFrame.

    Returns:
        (features_df, metadata_df) with aligned row indices.
        Metadata is physically separated from features to prevent leakage.
    """
    cfg = config or FeatureConfig()
    crew_id = subject_to_crew_id(subject_id)
    seat = subject_to_seat(subject_id)

    fast_samples = int(round(cfg.fast_window_sec * cfg.fs))
    slow_samples = int(round(cfg.slow_window_sec * cfg.fs))
    base_stride = max(1, int(round(cfg.stride_sec * cfg.fs)))
    minority_stride = (
        max(1, int(round(cfg.minority_stride_sec * cfg.fs)))
        if (is_training and cfg.minority_stride_sec is not None)
        else base_stride
    )

    segments = split_contiguous_segments(
        df,
        fs=cfg.fs,
        min_segment_samples=fast_samples,
    )

    feat_rows: List[Dict[str, float]] = []
    meta_rows: List[Dict[str, object]] = []

    for seg in segments:
        pre = preprocess_segment(
            seg,
            fs=cfg.fs,
            causal=cfg.causal_filtering,
            apply_notch_60hz=cfg.apply_notch_60hz,
            apply_eeg_car=cfg.apply_eeg_car,
            eeg_channels=EEG_CHANNELS if "eeg" in cfg.modalities else (),
        )
        n = pre.time_secs.size
        end = fast_samples
        while end <= n:
            fast_start = end - fast_samples
            slow_start = max(0, end - slow_samples)

            label_idx, label_name, purity, is_boundary, stray_cnt = _resolve_window_label(
                pre.events,
                fast_start,
                end,
                treat_stray_3_4_as_baseline=cfg.treat_stray_3_4_as_baseline,
            )

            # Determine next step (optional denser stride for rare DA/SS classes in train only)
            step = base_stride
            if is_training and label_name in ("DA", "SS"):
                step = minority_stride

            # In training mode, drop unlabeled, stray-contaminated, or impure transition windows
            if is_training:
                if label_idx is None or purity < cfg.min_label_purity:
                    end += step
                    continue

            sqi = compute_window_sqi(
                pre,
                fast_start,
                end,
                required_modalities=cfg.modalities,
            )

            row_feats: Dict[str, float] = {}
            if "eeg" in cfg.modalities:
                row_feats.update(
                    _extract_eeg_window_features(
                        pre,
                        fast_start,
                        end,
                        exclude_frontal_eog=cfg.exclude_frontal_eog,
                    )
                )
            if "ecg" in cfg.modalities:
                row_feats.update(_extract_ecg_window_features(pre, fast_start, slow_start, end))
            if "resp" in cfg.modalities:
                row_feats.update(_extract_resp_window_features(pre, slow_start, end))
            if "gsr" in cfg.modalities:
                row_feats.update(_extract_gsr_window_features(pre, fast_start, slow_start, end))

            feat_rows.append(row_feats)
            meta_rows.append(
                {
                    "subject_id": subject_id,
                    "crew_id": crew_id,
                    "seat": seat,
                    "session_type": session_type,
                    "source_file": source_file,
                    "segment_id": pre.segment_id,
                    "window_start_sec": float(pre.time_secs[fast_start]),
                    "window_end_sec": float(pre.time_secs[end - 1]),
                    "label": label_idx,
                    "label_name": label_name,
                    "label_purity": round(purity, 4),
                    "is_boundary": is_boundary,
                    "stray_3_4_samples": stray_cnt,
                    "sqi_valid": sqi.valid,
                    "sqi_score": round(sqi.sqi_score, 4),
                }
            )
            end += step

    features_df = pd.DataFrame(feat_rows)
    metadata_df = pd.DataFrame(meta_rows)
    return features_df, metadata_df
