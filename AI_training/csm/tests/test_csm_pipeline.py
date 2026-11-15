"""
Comprehensive unit & integration test suite for DEC-001 (`AI_training/csm`).

Verifies:
    1. Official NASA CSM schema constants & crew/seat mapping
    2. Discontinuity-safe DSP, NeXus-10 DC removal, QRS HR detection, GSR zero masking & SQI
    3. Strictly causal dual-scale feature extraction, forbidden-column absence, stray 3/4 handling, & ablations
    4. Runtime anti-leakage guards (crew leakage, subject leakage, session leakage, TimeSecs leakage)
    5. Mathematical causality of initial-baseline normalization (zero future look-ahead)
    6. Validation-only Temperature Scaling & operational LOFT episode/FAR-per-hour metrics
    7. Tier 0 / Tier 1 models across multiclass, binary_per_state, and hierarchical formulations
    8. Streaming ZIP raw-data auditor across chunk boundaries & Stop-Condition gate verdicts
    9. OrbitCare non-diagnostic JSON contract & SQI abstention safety
   10. End-to-end synthetic smoke-test CLI provenance tagging
"""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

# Ensure AI_training is importable regardless of working directory
AI_TRAINING_DIR = Path(__file__).resolve().parents[2]
if str(AI_TRAINING_DIR) not in sys.path:
    sys.path.insert(0, str(AI_TRAINING_DIR))

from csm.audit_raw_data import run_raw_audit  # noqa: E402
from csm.constants import (  # noqa: E402
    EEG_CHANNELS,
    EXPECTED_COLUMNS,
    FORBIDDEN_FEATURE_COLUMNS,
    FRONTAL_EOG_PRONE_CHANNELS,
    MISSING_EXPECTED_SUBJECT_IDS,
    NOMINAL_FS_HZ,
    PUBLISHED_SUBJECT_IDS,
    subject_to_crew_id,
    subject_to_seat,
)
from csm.contract import build_csm_response, error_csm_response  # noqa: E402
from csm.evaluation import (  # noqa: E402
    TemperatureScaler,
    assert_no_leakage,
    causal_baseline_normalize,
    compute_classification_metrics,
    compute_operational_loft_metrics,
)
from csm.features import FeatureConfig, extract_session_features  # noqa: E402
from csm.models import CSMModelWrapper  # noqa: E402
from csm.preprocessing import (  # noqa: E402
    compute_window_sqi,
    detect_ecg_r_peaks,
    preprocess_segment,
    split_contiguous_segments,
)
from csm.run_benchmark import generate_synthetic_smoke_dataset, main as benchmark_main  # noqa: E402


# ---------------------------------------------------------------------------
# 1. Constants & Schema
# ---------------------------------------------------------------------------
def test_nasa_schema_and_crew_mapping():
    assert len(EXPECTED_COLUMNS) == 25
    assert len(EEG_CHANNELS) == 20
    assert len(PUBLISHED_SUBJECT_IDS) == 17
    assert 20 in MISSING_EXPECTED_SUBJECT_IDS
    assert 20 not in PUBLISHED_SUBJECT_IDS

    # Paired cockpit crews per NASA description.txt
    assert subject_to_crew_id(5) == 3
    assert subject_to_crew_id(6) == 3
    assert subject_to_crew_id(19) == 10
    assert subject_to_crew_id(20) == 10
    assert subject_to_seat(5) == "left"
    assert subject_to_seat(6) == "right"

    for col in ("TimeSecs", "Event", "subject_id", "crew_id", "seat"):
        assert col in FORBIDDEN_FEATURE_COLUMNS


# ---------------------------------------------------------------------------
# 2. Discontinuity-Safe DSP, QRS Detection & SQI
# ---------------------------------------------------------------------------
def test_split_contiguous_segments_breaks_on_gaps_and_backwards_time():
    fs = NOMINAL_FS_HZ
    t1 = np.arange(0, 100) / fs
    t2 = t1[-1] + 0.5 + np.arange(0, 100) / fs  # 500 ms gap
    t3 = np.arange(0, 100) / fs  # backwards jump
    t = np.concatenate([t1, t2, t3])
    df = pd.DataFrame({"TimeSecs": t, "ECG": np.zeros_like(t)})

    segs = split_contiguous_segments(df, fs=fs, max_gap_sec=0.005, min_segment_samples=50)
    assert len(segs) == 3
    assert [len(s.df) for s in segs] == [100, 100, 100]


def test_ecg_dc_removal_and_qrs_heart_rate_accuracy():
    fs = NOMINAL_FS_HZ
    duration_sec = 20.0
    n = int(duration_sec * fs)
    t = np.arange(n, dtype=np.float64) / fs

    # 75 BPM = 1.25 Hz QRS complexes + realistic NeXus-10 +18,500 uV DC offset
    hr_hz = 1.25
    frac = (hr_hz * t) - np.floor(hr_hz * t)
    ecg_raw = 18_500.0 + 1_200.0 * np.exp(-0.5 * ((frac - 0.5) / 0.012) ** 2)

    df = pd.DataFrame({
        "TimeSecs": t,
        **{ch: np.sin(2 * np.pi * 10.0 * t) * 10.0 for ch in EEG_CHANNELS},
        "ECG": ecg_raw,
        "R": 650.0 + 50.0 * np.sin(2 * np.pi * 0.25 * t),
        "GSR": 500.0 + 10.0 * np.sin(2 * np.pi * 0.1 * t),
        "Event": np.zeros(n, dtype=int),
    })

    seg = split_contiguous_segments(df, fs=fs, min_segment_samples=256)[0]
    pre = preprocess_segment(seg, fs=fs, causal=True)

    # DC offset must be removed (well below raw 18,500 uV)
    assert abs(float(np.mean(pre.ecg_clean[256:]))) < 50.0
    # Detected HR should be close to 75 BPM
    peaks, rr = detect_ecg_r_peaks(pre.ecg_qrs, fs=fs)
    assert peaks.size >= 18
    est_bpm = 60.0 / float(np.median(rr))
    assert 70.0 <= est_bpm <= 80.0


def test_sqi_abstains_on_gsr_zero_dropout_and_flat_eeg():
    fs = NOMINAL_FS_HZ
    n = int(6 * fs)
    t = np.arange(n) / fs

    # Healthy EEG + ECG (QRS spikes) + Resp, but GSR is 100% dropped to zero
    frac = (1.2 * t) - np.floor(1.2 * t)
    ecg_raw = 12_000.0 + 1_000.0 * np.exp(-0.5 * ((frac - 0.5) / 0.012) ** 2)

    df_gsr_drop = pd.DataFrame({
        "TimeSecs": t,
        **{ch: 10.0 * np.sin(2 * np.pi * 10.0 * t) for ch in EEG_CHANNELS},
        "ECG": ecg_raw,
        "R": 100.0 * np.sin(2 * np.pi * 0.25 * t),
        "GSR": np.zeros(n),
    })
    seg = split_contiguous_segments(df_gsr_drop, fs=fs, min_segment_samples=256)[0]
    pre = preprocess_segment(seg, fs=fs, causal=True)

    sqi_full = compute_window_sqi(pre, 0, n, required_modalities=("eeg", "ecg", "resp", "gsr"))
    assert sqi_full.gsr_valid_fraction == 0.0
    assert sqi_full.valid is False
    assert any("GSR" in r for r in sqi_full.reasons)

    # Wearable subset (ecg+resp only) ignores dead GSR
    sqi_wear = compute_window_sqi(pre, 0, n, required_modalities=("ecg", "resp"))
    assert not any("GSR" in r for r in sqi_wear.reasons)
    assert sqi_wear.valid is True

    # Flatlined EEG (>50% channels flat) triggers EEG_LOW_QUALITY
    df_flat_eeg = df_gsr_drop.copy()
    for ch in EEG_CHANNELS[:14]:
        df_flat_eeg[ch] = 0.0
    df_flat_eeg["GSR"] = 500.0 + 5.0 * np.sin(2 * np.pi * 0.1 * t)
    seg_flat = split_contiguous_segments(df_flat_eeg, fs=fs, min_segment_samples=256)[0]
    pre_flat = preprocess_segment(seg_flat, fs=fs, causal=True)
    sqi_eeg = compute_window_sqi(pre_flat, 0, n, required_modalities=("eeg", "ecg", "resp", "gsr"))
    assert sqi_eeg.valid is False
    assert any("EEG_LOW_QUALITY" in r for r in sqi_eeg.reasons)


# ---------------------------------------------------------------------------
# 3. Causal Feature Extraction, Stray Events & Ablations
# ---------------------------------------------------------------------------
def test_feature_extraction_no_forbidden_columns_and_ablations():
    recs = generate_synthetic_smoke_dataset(subject_ids=(5,), benchmark_sec=25.0, loft_sec=35.0, seed=7)
    df_loft = recs[(5, "LOFT")]

    # Full extraction
    cfg_full = FeatureConfig(fast_window_sec=4.0, slow_window_sec=10.0, stride_sec=4.0)
    f_full, m_full = extract_session_features(df_loft, subject_id=5, session_type="LOFT", config=cfg_full, is_training=False)
    assert len(f_full) > 0
    assert len(f_full) == len(m_full)
    assert not (set(f_full.columns) & FORBIDDEN_FEATURE_COLUMNS)
    assert any(c.startswith("EEG_FP1_") for c in f_full.columns)
    assert any(c.startswith("gsr_") for c in f_full.columns)

    # Frontal EOG-prone ablation must drop FP1, FP2, F7, F8
    cfg_no_frontal = FeatureConfig(
        fast_window_sec=4.0, slow_window_sec=10.0, stride_sec=4.0, exclude_frontal_eog=True
    )
    f_nf, _ = extract_session_features(df_loft, subject_id=5, session_type="LOFT", config=cfg_no_frontal, is_training=False)
    for ch in FRONTAL_EOG_PRONE_CHANNELS:
        assert not any(col.startswith(f"{ch}_") for col in f_nf.columns)

    # Wearable ECG+Resp ablation must drop all EEG and GSR features
    cfg_wear = FeatureConfig(
        fast_window_sec=4.0, slow_window_sec=10.0, stride_sec=4.0, modalities=("ecg", "resp")
    )
    f_w, _ = extract_session_features(df_loft, subject_id=5, session_type="LOFT", config=cfg_wear, is_training=False)
    assert not any(c.startswith("EEG_") or c.startswith("eeg_") for c in f_w.columns)
    assert not any(c.startswith("gsr_") for c in f_w.columns)
    assert any(c.startswith("ecg_") for c in f_w.columns)
    assert any(c.startswith("resp_") for c in f_w.columns)


def test_stray_event_3_4_policy_drop_vs_map():
    recs = generate_synthetic_smoke_dataset(subject_ids=(5,), benchmark_sec=20.0, loft_sec=20.0, seed=11)
    df = recs[(5, "CA")].copy()
    # Mark entire recording as stray Event code 3
    df["Event"] = 3

    cfg_drop = FeatureConfig(
        fast_window_sec=4.0, slow_window_sec=8.0, stride_sec=4.0, treat_stray_3_4_as_baseline=False
    )
    f_drop, m_drop = extract_session_features(df, subject_id=5, session_type="CA", config=cfg_drop, is_training=True)
    assert len(f_drop) == 0 and len(m_drop) == 0

    cfg_map = FeatureConfig(
        fast_window_sec=4.0, slow_window_sec=8.0, stride_sec=4.0, treat_stray_3_4_as_baseline=True
    )
    f_map, m_map = extract_session_features(df, subject_id=5, session_type="CA", config=cfg_map, is_training=True)
    assert len(f_map) > 0
    assert set(m_map["label"].unique()) == {0}


# ---------------------------------------------------------------------------
# 4. Anti-Leakage Runtime Guards & Causal Baseline Normalization
# ---------------------------------------------------------------------------
def test_assert_no_leakage_catches_crew_subject_session_and_timesecs_leakage():
    tr_meta = pd.DataFrame({
        "subject_id": [5, 5],
        "crew_id": [3, 3],
        "session_type": ["CA", "DA"],
    })
    # Co-pilot Subject 6 belongs to the SAME crew_id=3!
    te_same_crew = pd.DataFrame({
        "subject_id": [6, 6],
        "crew_id": [3, 3],
        "session_type": ["LOFT", "LOFT"],
    })
    te_disjoint_crew = pd.DataFrame({
        "subject_id": [9, 9],
        "crew_id": [5, 5],
        "session_type": ["LOFT", "LOFT"],
    })

    # 1. Forbidden TimeSecs column must raise
    with pytest.raises(ValueError, match="Forbidden metadata columns"):
        assert_no_leakage(tr_meta, te_disjoint_crew, ["ecg_hr_bpm", "TimeSecs"])

    # 2. Same crew across train/test in Protocol A must raise
    with pytest.raises(ValueError, match="Crew IDs shared"):
        assert_no_leakage(tr_meta, te_same_crew, ["ecg_hr_bpm"], allow_same_subject_cross_session=False)

    # 3. Same (subject, session) in Protocol B must raise
    te_same_sess = pd.DataFrame({"subject_id": [5], "crew_id": [3], "session_type": ["CA"]})
    with pytest.raises(ValueError, match="random window splitting"):
        assert_no_leakage(tr_meta, te_same_sess, ["ecg_hr_bpm"], allow_same_subject_cross_session=True)

    # 4. Valid Protocol A (disjoint crews) passes
    assert_no_leakage(tr_meta, te_disjoint_crew, ["ecg_hr_bpm"], allow_same_subject_cross_session=False)

    # 5. Valid Protocol B (same subject, Benchmark -> LOFT) passes
    te_same_subj_loft = pd.DataFrame({"subject_id": [5], "crew_id": [3], "session_type": ["LOFT"]})
    assert_no_leakage(tr_meta, te_same_subj_loft, ["ecg_hr_bpm"], allow_same_subject_cross_session=True)


def test_causal_baseline_normalization_has_zero_future_lookahead():
    n = 20
    ends = np.arange(1, n + 1, dtype=float) * 5.0
    starts = ends - 5.0
    meta = pd.DataFrame({
        "subject_id": [5] * n,
        "crew_id": [3] * n,
        "session_type": ["LOFT"] * n,
        "window_start_sec": starts,
        "window_end_sec": ends,
        "sqi_valid": [True] * n,
    })
    feat_orig = pd.DataFrame({"f1": np.linspace(10.0, 29.0, n), "f2": np.ones(n) * 5.0})

    # Perturb the future (windows after 30 s) violently!
    feat_perturbed = feat_orig.copy()
    feat_perturbed.loc[meta["window_end_sec"] > 30.0, "f1"] += 1_000_000.0

    norm_orig = causal_baseline_normalize(feat_orig, meta, baseline_duration_sec=30.0, min_baseline_windows=3)
    norm_pert = causal_baseline_normalize(feat_perturbed, meta, baseline_duration_sec=30.0, min_baseline_windows=3)

    # Early windows (<= 30 s) must be bit-for-bit identical -> proves zero future look-ahead!
    early = meta["window_end_sec"] <= 30.0
    np.testing.assert_allclose(norm_orig.loc[early, "f1"], norm_pert.loc[early, "f1"], atol=1e-12)


# ---------------------------------------------------------------------------
# 5. Calibration & Operational LOFT Metrics
# ---------------------------------------------------------------------------
def test_temperature_scaler_and_operational_loft_metrics():
    rng = np.random.default_rng(123)
    logits = rng.normal(0, 3.0, size=(200, 4))
    y = np.argmax(logits + rng.normal(0, 1.0, size=(200, 4)), axis=1)
    # Artificially overconfident softmax
    overconf = np.exp(logits * 4.0)
    overconf /= overconf.sum(axis=1, keepdims=True)

    scaler = TemperatureScaler().fit(overconf, y)
    assert scaler.temperature_ > 1.0
    cal_probs = scaler.transform(overconf)
    np.testing.assert_allclose(cal_probs.sum(axis=1), 1.0, atol=1e-6)

    m_raw = compute_classification_metrics(y, overconf)
    m_cal = compute_classification_metrics(y, cal_probs)
    assert m_cal["multiclass_log_loss"] <= m_raw["multiclass_log_loss"] + 1e-4

    # Operational LOFT metrics: 1 true CA episode (t=20..29) detected at t=22, plus 1 false alarm (t=50..52)
    ts = np.arange(0.0, 60.0, 1.0)
    y_true = np.zeros(60, dtype=int)
    y_true[20:30] = 1  # CA
    y_pred = np.zeros(60, dtype=int)
    y_pred[22:28] = 1  # True detection (latency = 2 s)
    y_pred[50:53] = 1  # 3-sec false alarm episode

    op = compute_operational_loft_metrics(y_true, y_pred, ts, step_sec=1.0, onset_tolerance_sec=3.0)
    assert op["per_state_episodes"]["CA"]["n_true_episodes"] == 1
    assert op["per_state_episodes"]["CA"]["n_detected_episodes"] == 1
    assert op["per_state_episodes"]["CA"]["episode_recall"] == 1.0
    assert op["per_state_episodes"]["CA"]["median_onset_latency_sec"] == pytest.approx(2.0)
    assert op["false_alarm_episodes"] == 1
    assert op["false_alarm_rate_per_hour"] > 0.0


# ---------------------------------------------------------------------------
# 6. Models Across All Formulations (Including Missing Rare Class Resilience)
# ---------------------------------------------------------------------------
@pytest.mark.parametrize("model_name", ["dummy_majority", "logreg_balanced", "rf_balanced", "gbdt_balanced"])
@pytest.mark.parametrize("formulation", ["multiclass", "binary_per_state", "hierarchical"])
def test_model_wrappers_emit_valid_4class_probabilities(model_name, formulation):
    rng = np.random.default_rng(0)
    X = rng.normal(0, 1, size=(120, 8))
    y = rng.choice([0, 1, 2, 3], size=120, p=[0.55, 0.20, 0.15, 0.10])

    clf = CSMModelWrapper(model_name=model_name, formulation=formulation, seed=0)
    clf.fit(X, y)
    probs = clf.predict_proba(X[:20])
    assert probs.shape == (20, 4)
    assert np.all(np.isfinite(probs))
    assert np.all(probs >= 0.0)
    np.testing.assert_allclose(probs.sum(axis=1), 1.0, atol=1e-6)


def test_model_wrapper_handles_absent_rare_class():
    rng = np.random.default_rng(1)
    X = rng.normal(0, 1, size=(60, 6))
    y = rng.choice([0, 1], size=60)  # Classes 2 and 3 absent in fold
    for form in ("multiclass", "binary_per_state", "hierarchical"):
        clf = CSMModelWrapper(model_name="logreg_balanced", formulation=form, seed=1)
        clf.fit(X, y)
        probs = clf.predict_proba(X[:10])
        assert probs.shape == (10, 4)
        np.testing.assert_allclose(probs.sum(axis=1), 1.0, atol=1e-6)
        # Absent classes receive near-zero probability (epsilon-clipped for log-loss stability)
        assert np.all(probs[:, 2] < 1e-5) and np.all(probs[:, 3] < 1e-5)


# ---------------------------------------------------------------------------
# 7. Streaming Raw-ZIP Auditor & Stop-Condition Gates
# ---------------------------------------------------------------------------
def _write_subject_zip(
    zip_path: Path,
    subject_id: int,
    include_all_loft_classes: bool = True,
    inject_stray_3: bool = False,
):
    fs = NOMINAL_FS_HZ
    n = 400
    t = np.arange(n, dtype=float) / fs
    t_gap = t.copy()
    t_gap[200:] += 0.25  # 250 ms gap spanning chunk boundary when chunksize=128

    base = {
        "TimeSecs": t_gap,
        **{ch: np.sin(2 * np.pi * 10.0 * t) for ch in EEG_CHANNELS},
        "ECG": np.full(n, 1000.0),
        "R": np.full(n, 500.0),
        "GSR": np.where(np.arange(n) < 40, 0.0, 600.0),  # 10% zero-dropout
        "Event": np.zeros(n, dtype=int),
    }

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for sess, ev_arr in [
            ("CA", np.where(np.arange(n) >= 200, 2, 0)),
            ("DA", np.where(np.arange(n) >= 200, 5, 0)),
            ("SS", np.where(np.arange(n) >= 200, 1, 0)),
        ]:
            df = pd.DataFrame({**base, "Event": ev_arr})
            zf.writestr(f"{subject_id}_{sess}.csv", df.to_csv(index=False))

        loft_ev = np.zeros(n, dtype=int)
        if include_all_loft_classes:
            loft_ev[100:150] = 1
            loft_ev[150:250] = 2
            loft_ev[250:320] = 5
        if inject_stray_3:
            loft_ev[320:330] = 3
        df_loft = pd.DataFrame({**base, "Event": loft_ev})
        zf.writestr(f"{subject_id}_Loft.csv", df_loft.to_csv(index=False))


def test_raw_zip_auditor_streaming_and_gates(tmp_path: Path):
    data_dir = tmp_path / "raw"
    out_dir = tmp_path / "out"
    data_dir.mkdir()

    # Build 2 crews (subjects 5,6 and 9,10) with stray Event=3 in LOFT
    for sid in (5, 6, 9, 10):
        _write_subject_zip(data_dir / f"{sid}.zip", sid, include_all_loft_classes=True, inject_stray_3=(sid == 5))

    report = run_raw_audit(data_dir=data_dir, out_dir=out_dir, chunksize=128)
    assert (out_dir / "audit_report.json").exists()
    assert (out_dir / "audit_summary_files.csv").exists()
    assert (out_dir / "audit_class_distribution.csv").exists()
    assert (out_dir / "audit_report.md").exists()

    gs = report["gate_summary"]
    assert gs["n_subjects_audited"] == 4
    assert gs["n_crews_audited"] == 2
    assert gs["gates"]["schema_integrity"]["status"] == "PASS"
    assert gs["gates"]["label_mapping"]["status"] == "REVIEW"  # Caught stray Event=3!
    assert gs["crews_with_4class_loft"] == [3, 5]

    # Verify cross-chunk gap & GSR zero-dropout rate (40/400 = 10.0%)
    fa5 = [f for f in report["file_audits"] if f["subject_id"] == 5 and f["session_type"] == "LOFT"][0]
    assert fa5["time_gap_steps"] == 1
    assert fa5["gsr_zero_or_neg_pct"] == pytest.approx(10.0, abs=0.01)
    assert fa5["stray_3_4_rows"] == 10

    # Now test STOP gate when LOFT has no non-baseline labels
    data_dir2 = tmp_path / "raw_stop"
    out_dir2 = tmp_path / "out_stop"
    data_dir2.mkdir()
    _write_subject_zip(data_dir2 / "5.zip", 5, include_all_loft_classes=False)
    rep_stop = run_raw_audit(data_dir=data_dir2, out_dir=out_dir2, chunksize=128)
    assert rep_stop["gate_summary"]["overall_gate_verdict"] == "STOP_CONDITION_TRIGGERED"
    assert rep_stop["gate_summary"]["gates"]["loft_4class_coverage"]["status"] == "STOP"


# ---------------------------------------------------------------------------
# 8. OrbitCare Non-Diagnostic JSON Contract & Safety Abstention
# ---------------------------------------------------------------------------
def test_orbitcare_contract_abstains_on_low_sqi_and_enforces_non_diagnostic_fields():
    # Low SQI -> strict abstention (never defaults to Baseline)
    resp_abstain = build_csm_response(
        astronaut_id="crew-5",
        session_id="loft-1",
        window_end_sec=15.0,
        data_provenance="real_nasa_csm_replay",
        signal_quality={"valid": False, "sqi_score": 0.25, "reasons": ["GSR_DROPOUT_OR_INVALID"]},
        probabilities={"Baseline": 0.1, "CA": 0.7, "DA": 0.1, "SS": 0.1},
    )
    assert resp_abstain["status"] == "INSUFFICIENT_DATA"
    assert resp_abstain["prediction"]["state"] is None
    assert resp_abstain["prediction"]["probabilities"] is None
    assert resp_abstain["prediction"]["abstained"] is True
    assert resp_abstain["model_status"]["validated"] is False
    assert "not a medical diagnosis" in resp_abstain["disclaimer"].lower()

    # Valid SQI -> calibrated probabilities + research disclaimer
    resp_ok = build_csm_response(
        astronaut_id="crew-5",
        session_id="loft-1",
        window_end_sec=20.0,
        data_provenance="real_nasa_csm_replay",
        signal_quality={"valid": True, "sqi_score": 0.96, "reasons": []},
        probabilities={"Baseline": 0.10, "CA": 0.72, "DA": 0.12, "SS": 0.06},
        calibrated=True,
    )
    assert resp_ok["status"] == "OK"
    assert resp_ok["prediction"]["state"] == "CA"
    assert resp_ok["prediction"]["abstained"] is False
    assert resp_ok["prediction"]["confidence"] == pytest.approx(0.72)
    assert sum(resp_ok["prediction"]["probabilities"].values()) == pytest.approx(1.0, abs=1e-4)
    assert resp_ok["model_status"]["validated"] is False

    # Invalid provenance returns structured ERROR contract (fail-safe, never crashes API)
    resp_bad_prov = build_csm_response(
        astronaut_id="crew-5",
        session_id="loft-1",
        window_end_sec=20.0,
        data_provenance="unverified_magic",
        signal_quality={"valid": True, "sqi_score": 1.0, "reasons": []},
        probabilities={"Baseline": 1.0, "CA": 0.0, "DA": 0.0, "SS": 0.0},
    )
    assert resp_bad_prov["status"] == "ERROR"
    assert resp_bad_prov["errors"][0]["code"] == "INVALID_PROVENANCE"

    # Missing probability key returns structured ERROR contract
    resp_bad_probs = build_csm_response(
        astronaut_id="crew-5",
        session_id="loft-1",
        window_end_sec=20.0,
        data_provenance="synthetic",
        signal_quality={"valid": True, "sqi_score": 1.0, "reasons": []},
        probabilities={"Baseline": 0.5, "CA": 0.5},
    )
    assert resp_bad_probs["status"] == "ERROR"
    assert resp_bad_probs["errors"][0]["code"] == "INVALID_PROBABILITIES"

    err = error_csm_response("SENSOR_DISCONNECTED", "Sensor disconnected")
    assert err["status"] == "ERROR"
    assert err["prediction"]["abstained"] is True


# ---------------------------------------------------------------------------
# 8. Governance Defenses: Enforceable Audit Manifest & Untrusted Validation
# ---------------------------------------------------------------------------
def test_untrusted_model_validated_is_rejected_without_verified_artifact(tmp_path: Path):
    # 1. Bare model_validated=True with no artifact -> REJECTED
    resp_bare = build_csm_response(
        astronaut_id="crew-5",
        session_id="loft-1",
        window_end_sec=20.0,
        data_provenance="real_nasa_csm_replay",
        signal_quality={"valid": True, "sqi_score": 0.95, "reasons": []},
        probabilities={"Baseline": 0.7, "CA": 0.1, "DA": 0.1, "SS": 0.1},
        model_validated=True,
    )
    assert resp_bare["status"] == "ERROR"
    assert resp_bare["errors"][0]["code"] == "UNTRUSTED_VALIDATION_CLAIM"
    assert resp_bare["model_status"]["validated"] is False
    assert resp_bare["prediction"]["abstained"] is True

    # 2. Synthetic evaluation artifact cannot validate a model -> REJECTED
    bad_art = tmp_path / "synthetic_eval.json"
    bad_art.write_text(json.dumps({
        "scientifically_valid": False,
        "data_provenance": "synthetic",
        "audit_gate_verdict": "READY_FOR_BENCHMARK_PHASE",
        "audit_manifest_sha256": "a" * 64,
        "owner_signoff_recorded": True,
        "owner_signoff_reference": "DEC-001-REVIEW",
        "runs": [{"outer_test_calibrated": {"macro_f1": 0.5}}],
    }), encoding="utf-8")
    resp_syn_art = build_csm_response(
        astronaut_id="crew-5",
        session_id="loft-1",
        window_end_sec=20.0,
        data_provenance="real_nasa_csm_replay",
        signal_quality={"valid": True, "sqi_score": 0.95, "reasons": []},
        probabilities={"Baseline": 0.7, "CA": 0.1, "DA": 0.1, "SS": 0.1},
        model_validated=True,
        validation_artifact_path=bad_art,
    )
    assert resp_syn_art["status"] == "ERROR"
    assert resp_syn_art["errors"][0]["code"] == "UNTRUSTED_VALIDATION_CLAIM"
    assert resp_syn_art["model_status"]["validated"] is False

    # 3. Real-data artifact without owner sign-off -> REJECTED
    unsigned_art = tmp_path / "unsigned_eval.json"
    unsigned_art.write_text(json.dumps({
        "scientifically_valid": True,
        "data_provenance": "real_nasa_csm_local",
        "audit_gate_verdict": "READY_FOR_BENCHMARK_PHASE",
        "audit_manifest_sha256": "b" * 64,
        "owner_signoff_recorded": False,
        "runs": [{"outer_test_calibrated": {"macro_f1": 0.65}}],
    }), encoding="utf-8")
    resp_unsigned = build_csm_response(
        astronaut_id="crew-5",
        session_id="loft-1",
        window_end_sec=20.0,
        data_provenance="real_nasa_csm_replay",
        signal_quality={"valid": True, "sqi_score": 0.95, "reasons": []},
        probabilities={"Baseline": 0.7, "CA": 0.1, "DA": 0.1, "SS": 0.1},
        model_validated=True,
        validation_artifact_path=unsigned_art,
    )
    assert resp_unsigned["status"] == "ERROR"
    assert resp_unsigned["errors"][0]["code"] == "UNTRUSTED_VALIDATION_CLAIM"
    assert resp_unsigned["model_status"]["validated"] is False

    # 4. Complete auditable real-data artifact still rejected if request provenance is synthetic
    good_art = tmp_path / "verified_eval.json"
    good_art.write_text(json.dumps({
        "scientifically_valid": True,
        "data_provenance": "real_nasa_csm_local",
        "audit_gate_verdict": "READY_FOR_BENCHMARK_PHASE",
        "audit_manifest_sha256": "c" * 64,
        "owner_signoff_recorded": True,
        "owner_signoff_reference": "ADR-DEC-001-SIGNED",
        "runs": [{"outer_test_calibrated": {"macro_f1": 0.65}}],
    }), encoding="utf-8")
    resp_syn_req = build_csm_response(
        astronaut_id="crew-5",
        session_id="loft-1",
        window_end_sec=20.0,
        data_provenance="synthetic",
        signal_quality={"valid": True, "sqi_score": 0.95, "reasons": []},
        probabilities={"Baseline": 0.7, "CA": 0.1, "DA": 0.1, "SS": 0.1},
        model_validated=True,
        validation_artifact_path=good_art,
    )
    assert resp_syn_req["status"] == "ERROR"
    assert resp_syn_req["errors"][0]["code"] == "UNTRUSTED_VALIDATION_CLAIM"
    assert resp_syn_req["model_status"]["validated"] is False


def test_audit_manifest_enforcement_blocks_missing_review_stop_malformed_and_mismatched(tmp_path: Path):
    from csm.audit_raw_data import AUDIT_MANIFEST_FILENAME, AuditManifestError, verify_audit_manifest
    from csm.run_benchmark import run_benchmark_suite

    data_dir = tmp_path / "raw"
    out_dir = tmp_path / "audit_out"
    data_dir.mkdir()

    for sid in (5, 6, 9, 10):
        _write_subject_zip(data_dir / f"{sid}.zip", sid, include_all_loft_classes=True, inject_stray_3=False)

    # Audit emits audit_manifest.json with schema_version, checksums, verdict, provenance
    run_raw_audit(data_dir=data_dir, out_dir=out_dir, chunksize=128)
    manifest_path = out_dir / AUDIT_MANIFEST_FILENAME
    assert manifest_path.exists()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    assert manifest["schema_version"] == "1.0-dec001-audit-manifest"
    assert manifest["data_provenance"] == "real_nasa_csm_local"
    assert len(manifest["input_archives"]) == 4
    assert all(len(a["sha256"]) == 64 for a in manifest["input_archives"])
    # Only 4/17 subjects -> verdict is REVISE_OR_OWNER_REVIEW
    assert manifest["gate_verdict"] == "REVISE_OR_OWNER_REVIEW"

    # 1. Benchmark refuses real data without --audit-manifest
    with pytest.raises(AuditManifestError, match="without --audit-manifest"):
        run_benchmark_suite(data_dir=data_dir, audit_manifest=None)

    # 2. Benchmark refuses REVIEW manifest verdict
    with pytest.raises(AuditManifestError, match="REVISE_OR_OWNER_REVIEW"):
        run_benchmark_suite(data_dir=data_dir, audit_manifest=manifest_path)

    # CLI also exits with status 2 on refused manifest
    rc_refused = benchmark_main([
        "--data-dir", str(data_dir),
        "--audit-manifest", str(manifest_path),
        "--out-file", str(tmp_path / "should_not_exist.json"),
    ])
    assert rc_refused == 2
    assert not (tmp_path / "should_not_exist.json").exists()

    # 3. Malformed JSON manifest refused
    bad_json = tmp_path / "bad_manifest.json"
    bad_json.write_text("{not-valid-json", encoding="utf-8")
    with pytest.raises(AuditManifestError, match="malformed JSON"):
        verify_audit_manifest(bad_json, data_dir)

    # 4. STOP verdict refused
    stop_manifest = tmp_path / "stop_manifest.json"
    stop_payload = dict(manifest, gate_verdict="STOP_CONDITION_TRIGGERED")
    stop_manifest.write_text(json.dumps(stop_payload), encoding="utf-8")
    with pytest.raises(AuditManifestError, match="STOP_CONDITION_TRIGGERED"):
        verify_audit_manifest(stop_manifest, data_dir)

    # 5. Synthesize a PASS manifest to test checksum tampering & extra archive detection
    pass_payload = dict(
        manifest,
        gate_verdict="READY_FOR_BENCHMARK_PHASE",
        gates={k: {"status": "PASS", "detail": "ok"} for k in manifest["gates"]},
    )
    pass_manifest = tmp_path / "pass_manifest.json"
    pass_manifest.write_text(json.dumps(pass_payload), encoding="utf-8")

    # Exact match passes verification
    verified = verify_audit_manifest(pass_manifest, data_dir)
    assert verified["verified_archive_count"] == 4
    assert len(verified["manifest_sha256"]) == 64

    # Extra un-audited ZIP breaks verification
    _write_subject_zip(data_dir / "11.zip", 11, include_all_loft_classes=True)
    with pytest.raises(AuditManifestError, match="un-audited archive"):
        verify_audit_manifest(pass_manifest, data_dir)
    (data_dir / "11.zip").unlink()

    # Tampering with an archive file breaks SHA-256 checksum verification
    with (data_dir / "5.zip").open("ab") as f:
        f.write(b"tampered")
    with pytest.raises(AuditManifestError, match="SHA-256 checksum mismatch"):
        verify_audit_manifest(pass_manifest, data_dir)


# ---------------------------------------------------------------------------
# 9. End-to-End Synthetic Smoke-Test Benchmark CLI
# ---------------------------------------------------------------------------
def test_benchmark_cli_smoke_test_provenance_and_execution(tmp_path: Path):
    out_json = tmp_path / "smoke_bench.json"
    rc = benchmark_main([
        "--smoke-test-synthetic",
        "--protocol",
        "protocol_a_zeroshot",
        "--ablation",
        "wearable_ecg_resp",
        "--out-file",
        str(out_json),
        "--seed",
        "7",
    ])
    assert rc == 0
    payload = json.loads(out_json.read_text(encoding="utf-8"))
    assert payload["data_provenance"] == "synthetic"
    assert payload["run_mode"] == "synthetic_pipeline_smoke_test"
    assert payload["scientifically_valid"] is False
    assert payload["model_validated"] is False
    assert payload["audit_manifest_sha256"] is None
    assert len(payload["runs"]) == 6
    for run in payload["runs"]:
        assert 0.0 <= run["outer_test_calibrated"]["macro_f1"] <= 1.0
        assert run["calibration_temperature"] > 0.0
