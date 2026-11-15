"""
Leakage-resistant, crew-grouped evaluation, causal normalization, probability
calibration, and operational LOFT metrics for DEC-001.

Non-negotiable invariants enforced at runtime:
    1. Zero crew overlap between train and validation/test in Protocol A & C
       (paired left/right-seat pilots always remain in the same crew fold).
    2. Zero forbidden metadata columns (TimeSecs, subject_id, crew_id, seat,
       experiment, source_file, etc.) permitted in model feature matrices.
    3. Normalization is strictly causal (initial-baseline z-scoring or
       fold-local RobustScaler fitted on train fold only).
    4. Post-hoc Temperature Scaling is fitted strictly on held-out validation
       folds — never on training data or untouched outer test crews.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Sequence, Tuple

import numpy as np
import pandas as pd
from scipy.optimize import minimize_scalar
from sklearn.metrics import (
    average_precision_score,
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
    log_loss,
    precision_recall_fscore_support,
    roc_auc_score,
)

from .constants import (
    CLASS_TO_INDEX,
    FORBIDDEN_FEATURE_COLUMNS,
    LOFT_SESSION,
    TARGET_CLASSES,
)


# ---------------------------------------------------------------------------
# 1. Runtime Anti-Leakage Verification
# ---------------------------------------------------------------------------
def assert_no_leakage(
    train_meta: pd.DataFrame,
    eval_meta: pd.DataFrame,
    feature_cols: Sequence[str],
    *,
    allow_same_subject_cross_session: bool = False,
) -> None:
    """
    Raise ValueError immediately if any structural or feature leakage is detected.

    - Always forbids metadata/timestamp columns inside `feature_cols`.
    - Always forbids overlapping (subject_id, session_type) recordings across train/eval.
    - Unless `allow_same_subject_cross_session=True` (Protocol B calibrated regime),
      strictly forbids any crew_id or subject_id overlap between train and eval.
    """
    forbidden_lower = {c.lower() for c in FORBIDDEN_FEATURE_COLUMNS}
    leaked_cols = [c for c in feature_cols if c.lower() in forbidden_lower]
    if leaked_cols:
        raise ValueError(f"LEAKAGE DETECTED: Forbidden metadata columns in features: {leaked_cols}")

    if len(train_meta) == 0 or len(eval_meta) == 0:
        raise ValueError("Train and eval metadata must both be non-empty.")

    # Never share the same recording session across train and eval (prevents random window splitting)
    train_recordings = set(zip(train_meta["subject_id"], train_meta["session_type"]))
    eval_recordings = set(zip(eval_meta["subject_id"], eval_meta["session_type"]))
    shared_recordings = train_recordings & eval_recordings
    if shared_recordings:
        raise ValueError(
            f"LEAKAGE DETECTED: Same (subject_id, session_type) recording appears in both "
            f"train and eval (random window splitting is forbidden): {sorted(shared_recordings)}"
        )

    if not allow_same_subject_cross_session:
        train_crews = set(train_meta["crew_id"].unique())
        eval_crews = set(eval_meta["crew_id"].unique())
        shared_crews = train_crews & eval_crews
        if shared_crews:
            raise ValueError(
                f"LEAKAGE DETECTED: Crew IDs shared across train and eval in subject-independent "
                f"protocol: {sorted(shared_crews)}"
            )

        train_subjects = set(train_meta["subject_id"].unique())
        eval_subjects = set(eval_meta["subject_id"].unique())
        shared_subjects = train_subjects & eval_subjects
        if shared_subjects:
            raise ValueError(
                f"LEAKAGE DETECTED: Subject IDs shared across train and eval: {sorted(shared_subjects)}"
            )


# ---------------------------------------------------------------------------
# 2. Crew-Grouped Outer Test Vault + Development LOCO CV Plan
# ---------------------------------------------------------------------------
@dataclass
class CrewSplitPlan:
    """Locked outer test crews + Leave-One-Crew-Out development folds."""
    outer_test_crews: Tuple[int, ...]
    dev_crews: Tuple[int, ...]
    loco_folds: List[Tuple[Tuple[int, ...], int]]  # list of (train_crews, val_crew)


def make_crew_split_plan(
    meta_df: pd.DataFrame,
    *,
    n_outer_test_crews: int = 2,
    seed: int = 42,
    prefer_complete_loft_crews: bool = True,
) -> CrewSplitPlan:
    """
    Partition distinct cockpit crews into:
        - Untouched Outer Test Vault (`n_outer_test_crews` complete crews)
        - Development Set (`remaining crews`) with Leave-One-Crew-Out (LOCO) CV folds.
    """
    if "crew_id" not in meta_df.columns:
        raise ValueError("meta_df must contain 'crew_id'")

    all_crews = sorted(int(c) for c in meta_df["crew_id"].unique())
    if len(all_crews) < n_outer_test_crews + 2:
        raise ValueError(
            f"Need at least {n_outer_test_crews + 2} distinct crews to create an untouched "
            f"outer test vault plus >=2 development crews; found {len(all_crews)}: {all_crews}"
        )

    # Prefer placing crews that have all 4 target classes present in LOFT into the outer test set
    eligible_outer: List[int] = []
    if prefer_complete_loft_crews and "session_type" in meta_df.columns and "label" in meta_df.columns:
        loft_df = meta_df[meta_df["session_type"] == LOFT_SESSION]
        for cid in all_crews:
            c_labels = set(loft_df.loc[loft_df["crew_id"] == cid, "label"].dropna().unique())
            if len(c_labels) == len(TARGET_CLASSES):
                eligible_outer.append(cid)

    rng = np.random.default_rng(seed)
    if len(eligible_outer) >= n_outer_test_crews:
        chosen = sorted(int(x) for x in rng.choice(eligible_outer, size=n_outer_test_crews, replace=False))
    else:
        chosen = sorted(int(x) for x in rng.choice(all_crews, size=n_outer_test_crews, replace=False))

    outer_set = set(chosen)
    dev_crews = tuple(c for c in all_crews if c not in outer_set)
    loco_folds = [
        (tuple(c for c in dev_crews if c != val_c), val_c)
        for val_c in dev_crews
    ]
    return CrewSplitPlan(
        outer_test_crews=tuple(chosen),
        dev_crews=dev_crews,
        loco_folds=loco_folds,
    )


# ---------------------------------------------------------------------------
# 3. Strictly Causal Initial-Baseline Normalization
# ---------------------------------------------------------------------------
def causal_baseline_normalize(
    features_df: pd.DataFrame,
    meta_df: pd.DataFrame,
    *,
    baseline_duration_sec: float = 120.0,
    min_baseline_windows: int = 5,
    eps: float = 1e-6,
) -> pd.DataFrame:
    """
    Normalize each (subject_id, session_type) recording using ONLY its initial
    `baseline_duration_sec` trailing windows (strictly causal — NEVER computes
    statistics across future emergency events in the recording).

    If fewer than `min_baseline_windows` fall inside `baseline_duration_sec`,
    uses the first `min_baseline_windows` chronological windows of that recording
    (or leaves unchanged if recording is shorter than 2 windows).
    """
    if len(features_df) != len(meta_df):
        raise ValueError("features_df and meta_df must have equal length.")
    if len(features_df) == 0:
        return features_df.copy()

    out = features_df.astype(np.float64).copy()
    group_keys = meta_df[["subject_id", "session_type"]].drop_duplicates()

    for _, grp in group_keys.iterrows():
        mask = (meta_df["subject_id"] == grp["subject_id"]) & (
            meta_df["session_type"] == grp["session_type"]
        )
        idx = meta_df.index[mask]
        if len(idx) < 2:
            continue

        # Sort chronologically by window_end_sec
        sub_meta = meta_df.loc[idx].sort_values("window_end_sec")
        sorted_idx = sub_meta.index
        t0 = float(sub_meta["window_start_sec"].iloc[0])
        base_mask = (sub_meta["window_end_sec"] - t0) <= baseline_duration_sec
        base_idx = sorted_idx[base_mask]
        if len(base_idx) < min_baseline_windows:
            base_idx = sorted_idx[: min(len(sorted_idx), min_baseline_windows)]

        base_vals = out.loc[base_idx]
        med = base_vals.median(axis=0).fillna(0.0)
        q75 = base_vals.quantile(0.75, axis=0)
        q25 = base_vals.quantile(0.25, axis=0)
        iqr = (q75 - q25).fillna(0.0)
        std = base_vals.std(axis=0, ddof=0).fillna(0.0)
        # Robust scale: prefer IQR/1.349, fallback to std, then 1.0
        scale = np.where(iqr > eps, iqr / 1.3489795, np.where(std > eps, std, 1.0))
        scale_series = pd.Series(scale, index=out.columns)

        out.loc[sorted_idx] = ((out.loc[sorted_idx] - med) / scale_series).clip(-10.0, 10.0)

    return out


# ---------------------------------------------------------------------------
# 4. Post-Hoc Probability Calibration (Validation-Fold Temperature Scaling)
# ---------------------------------------------------------------------------
def _softmax(logits: np.ndarray) -> np.ndarray:
    shifted = logits - np.max(logits, axis=1, keepdims=True)
    exps = np.exp(shifted)
    return exps / np.sum(exps, axis=1, keepdims=True)


def _probs_to_logits(probs: np.ndarray, eps: float = 1e-7) -> np.ndarray:
    clipped = np.clip(np.asarray(probs, dtype=np.float64), eps, 1.0 - eps)
    clipped = clipped / np.sum(clipped, axis=1, keepdims=True)
    return np.log(clipped)


class TemperatureScaler:
    """
    Multiclass Temperature Scaling fitted strictly on held-out validation data
    by minimizing multiclass negative log-likelihood (NLL).
    """

    def __init__(self) -> None:
        self.temperature_: float = 1.0
        self.fitted_: bool = False

    def fit(self, val_probs: np.ndarray, y_val: np.ndarray) -> "TemperatureScaler":
        logits = _probs_to_logits(val_probs)
        y = np.asarray(y_val, dtype=np.int64)
        n_classes = logits.shape[1]

        def nll(temp: float) -> float:
            scaled = _softmax(logits / max(1e-3, temp))
            return float(log_loss(y, scaled, labels=list(range(n_classes))))

        res = minimize_scalar(nll, bounds=(0.1, 10.0), method="bounded")
        self.temperature_ = float(res.x) if res.success else 1.0
        self.fitted_ = True
        return self

    def transform(self, probs: np.ndarray) -> np.ndarray:
        logits = _probs_to_logits(probs)
        return _softmax(logits / self.temperature_)


# ---------------------------------------------------------------------------
# 5. Comprehensive Classification, Calibration & Operational LOFT Metrics
# ---------------------------------------------------------------------------
def compute_ece(
    y_true: np.ndarray,
    y_prob: np.ndarray,
    *,
    n_bins: int = 10,
) -> float:
    """Top-label Expected Calibration Error (ECE) over uniform confidence bins."""
    y = np.asarray(y_true, dtype=np.int64)
    p = np.asarray(y_prob, dtype=np.float64)
    confidences = np.max(p, axis=1)
    predictions = np.argmax(p, axis=1)
    accuracies = (predictions == y).astype(np.float64)

    bins = np.linspace(0.0, 1.0, n_bins + 1)
    ece = 0.0
    n = float(len(y))
    if n == 0:
        return 0.0
    for lo, hi in zip(bins[:-1], bins[1:]):
        if hi == 1.0:
            in_bin = (confidences >= lo) & (confidences <= hi)
        else:
            in_bin = (confidences >= lo) & (confidences < hi)
        count = int(np.sum(in_bin))
        if count > 0:
            ece += (count / n) * abs(float(np.mean(accuracies[in_bin])) - float(np.mean(confidences[in_bin])))
    return float(ece)


def compute_classification_metrics(
    y_true: np.ndarray,
    y_prob: np.ndarray,
    *,
    class_names: Sequence[str] = TARGET_CLASSES,
) -> Dict[str, Any]:
    """
    Compute per-class Precision/Recall/F1, Macro-F1, Balanced Accuracy,
    per-class PR-AUC & ROC-AUC, raw & normalized 4x4 Confusion Matrix,
    Multiclass Log-Loss, per-class Brier Score, and ECE.
    """
    y = np.asarray(y_true, dtype=np.int64)
    p = np.asarray(y_prob, dtype=np.float64)
    n_classes = len(class_names)
    labels = list(range(n_classes))

    if p.ndim != 2 or p.shape[1] != n_classes:
        raise ValueError(f"Expected y_prob shape (N, {n_classes}), got {p.shape}")

    p = np.clip(p, 1e-7, 1.0 - 1e-7)
    p = p / np.sum(p, axis=1, keepdims=True)
    y_pred = np.argmax(p, axis=1)

    prec, rec, f1, supp = precision_recall_fscore_support(
        y, y_pred, labels=labels, zero_division=0
    )

    per_class: Dict[str, Dict[str, Optional[float]]] = {}
    brier_scores: List[float] = []
    for idx, name in enumerate(class_names):
        y_bin = (y == idx).astype(np.int64)
        pos_count = int(np.sum(y_bin))
        neg_count = int(len(y_bin) - pos_count)

        pr_auc: Optional[float] = None
        roc_auc: Optional[float] = None
        if pos_count > 0 and neg_count > 0:
            pr_auc = float(average_precision_score(y_bin, p[:, idx]))
            roc_auc = float(roc_auc_score(y_bin, p[:, idx]))

        brier = float(np.mean((p[:, idx] - y_bin) ** 2))
        brier_scores.append(brier)

        per_class[name] = {
            "precision": round(float(prec[idx]), 4),
            "recall": round(float(rec[idx]), 4),
            "f1": round(float(f1[idx]), 4),
            "support": int(supp[idx]),
            "pr_auc": round(pr_auc, 4) if pr_auc is not None else None,
            "roc_auc": round(roc_auc, 4) if roc_auc is not None else None,
            "brier": round(brier, 4),
        }

    cm_raw = confusion_matrix(y, y_pred, labels=labels)
    row_sums = cm_raw.sum(axis=1, keepdims=True)
    cm_norm = np.divide(
        cm_raw.astype(np.float64),
        np.where(row_sums > 0, row_sums, 1.0),
    )

    present_classes = [i for i in labels if supp[i] > 0]
    macro_f1_present = float(np.mean([f1[i] for i in present_classes])) if present_classes else 0.0
    macro_f1_all = float(f1_score(y, y_pred, labels=labels, average="macro", zero_division=0))

    bal_acc = float(balanced_accuracy_score(y, y_pred)) if len(present_classes) >= 2 else 0.0
    mlog_loss = float(log_loss(y, p, labels=labels))
    ece = compute_ece(y, p)

    return {
        "n_samples": int(len(y)),
        "macro_f1": round(macro_f1_all, 4),
        "macro_f1_present_classes": round(macro_f1_present, 4),
        "balanced_accuracy": round(bal_acc, 4),
        "multiclass_log_loss": round(mlog_loss, 4),
        "mean_brier_score": round(float(np.mean(brier_scores)), 4),
        "ece": round(ece, 4),
        "per_class": per_class,
        "confusion_matrix_labels": list(class_names),
        "confusion_matrix_raw": cm_raw.tolist(),
        "confusion_matrix_row_normalized": np.round(cm_norm, 4).tolist(),
    }


def _find_contiguous_episodes(
    labels: np.ndarray,
    timestamps: np.ndarray,
    target_idx: int,
    max_step_gap: float,
) -> List[Tuple[float, float]]:
    """Find contiguous (start_sec, end_sec) episodes where labels == target_idx."""
    episodes: List[Tuple[float, float]] = []
    in_ep = False
    ep_start = 0.0
    prev_t = 0.0

    for lbl, t in zip(labels.tolist(), timestamps.tolist()):
        if lbl == target_idx:
            if not in_ep:
                ep_start = float(t)
                in_ep = True
            elif (float(t) - prev_t) > max_step_gap:
                episodes.append((ep_start, prev_t))
                ep_start = float(t)
            prev_t = float(t)
        else:
            if in_ep:
                episodes.append((ep_start, prev_t))
                in_ep = False
    if in_ep:
        episodes.append((ep_start, prev_t))
    return episodes


def compute_operational_loft_metrics(
    y_true: np.ndarray,
    y_pred: np.ndarray,
    window_end_secs: np.ndarray,
    *,
    step_sec: float = 1.0,
    onset_tolerance_sec: float = 3.0,
) -> Dict[str, Any]:
    """
    Compute operational event-level monitoring metrics on sequential LOFT streams:
        - Per-state episode-level recall (whether a true episode triggered at least
          one matching alert within [ep_start - tol, ep_end + tol])
        - Median detection latency from true episode onset (seconds)
        - False Alarm Rate per Hour (FAR/hr) during nominal Baseline periods
          (counted as distinct false-alarm alert episodes per hour of Baseline)
    """
    y_t = np.asarray(y_true, dtype=np.int64)
    y_p = np.asarray(y_pred, dtype=np.int64)
    ts = np.asarray(window_end_secs, dtype=np.float64)

    order = np.argsort(ts)
    y_t, y_p, ts = y_t[order], y_p[order], ts[order]
    max_gap = max(2.5 * step_sec, 5.0)

    baseline_idx = CLASS_TO_INDEX["Baseline"]
    baseline_mask = y_t == baseline_idx
    baseline_hours = (float(np.sum(baseline_mask)) * step_sec) / 3600.0

    # Count distinct false-alarm alert episodes during true Baseline windows
    fa_binary = (baseline_mask & (y_p != baseline_idx)).astype(np.int64)
    fa_episodes = _find_contiguous_episodes(fa_binary, ts, target_idx=1, max_step_gap=max_gap)
    far_per_hour = (len(fa_episodes) / baseline_hours) if baseline_hours > 1e-6 else None
    baseline_window_fa_rate = (
        float(np.mean(y_p[baseline_mask] != baseline_idx)) if np.any(baseline_mask) else None
    )

    state_events: Dict[str, Dict[str, Any]] = {}
    for cls_name in ("CA", "DA", "SS"):
        c_idx = CLASS_TO_INDEX[cls_name]
        true_eps = _find_contiguous_episodes(y_t, ts, target_idx=c_idx, max_step_gap=max_gap)
        detected = 0
        latencies: List[float] = []
        pred_times = ts[y_p == c_idx]

        for ep_start, ep_end in true_eps:
            hits = pred_times[
                (pred_times >= ep_start - onset_tolerance_sec)
                & (pred_times <= ep_end + onset_tolerance_sec)
            ]
            if hits.size > 0:
                detected += 1
                latencies.append(float(hits[0] - ep_start))

        state_events[cls_name] = {
            "n_true_episodes": len(true_eps),
            "n_detected_episodes": detected,
            "episode_recall": round(detected / len(true_eps), 4) if true_eps else None,
            "median_onset_latency_sec": round(float(np.median(latencies)), 2) if latencies else None,
        }

    return {
        "baseline_duration_hours": round(baseline_hours, 4),
        "false_alarm_episodes": len(fa_episodes),
        "false_alarm_rate_per_hour": round(far_per_hour, 2) if far_per_hour is not None else None,
        "baseline_window_false_alarm_fraction": (
            round(baseline_window_fa_rate, 4) if baseline_window_fa_rate is not None else None
        ),
        "per_state_episodes": state_events,
    }
