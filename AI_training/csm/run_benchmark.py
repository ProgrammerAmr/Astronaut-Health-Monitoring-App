"""
Crew-grouped, leakage-resistant benchmark runner for DEC-001.

Runs Tier 0 (Dummy, Balanced Logistic Regression) and Tier 1 (Balanced Random
Forest, Regularized GBDT) models across audited formulations (multiclass,
binary_per_state, hierarchical) and modality ablations (full, exclude_frontal_eog,
wearable ecg+resp).

Strict provenance & audit enforcement rule:
    - Real benchmark runs (`--data-dir`) STRICTLY REQUIRE a verified
      `--audit-manifest` JSON emitted by `csm.audit_raw_data` whose gate verdict
      is `READY_FOR_BENCHMARK_PHASE` and whose archive SHA-256 checksums match
      the evaluated directory. Missing, malformed, failed (`REVIEW`/`STOP`), or
      mismatched manifests are refused.
    - `--smoke-test-synthetic` generates mathematically synthetic waveforms ONLY
      to verify end-to-end pipeline mechanics; its JSON report is hard-tagged
      with `"data_provenance": "synthetic"`, `"run_mode": "synthetic_pipeline_smoke_test"`,
      `"scientifically_valid": false`, and `"model_validated": false`.
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional, Sequence, Tuple

import numpy as np
import pandas as pd

from .audit_raw_data import AuditManifestError, parse_csv_identity, verify_audit_manifest
from .constants import (
    BENCHMARK_SESSIONS,
    EEG_CHANNELS,
    LOFT_SESSION,
    NOMINAL_FS_HZ,
    TARGET_CLASSES,
)
from .evaluation import (
    TemperatureScaler,
    assert_no_leakage,
    causal_baseline_normalize,
    compute_classification_metrics,
    compute_operational_loft_metrics,
    make_crew_split_plan,
)
from .features import FeatureConfig, extract_session_features
from .models import CSMModelWrapper, FormulationName, ModelName

ProtocolName = Literal["protocol_a_zeroshot", "protocol_b_calibrated", "protocol_c_benchmark_only"]


# ---------------------------------------------------------------------------
# Loading Real Local NASA Archives -> Feature Table
# ---------------------------------------------------------------------------
def extract_dataset_from_dir(
    data_dir: Path,
    *,
    train_config: FeatureConfig,
    eval_config: FeatureConfig,
) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """Load local NASA CSM ZIPs (or unzipped CSVs) and extract features + metadata."""
    feat_parts: List[pd.DataFrame] = []
    meta_parts: List[pd.DataFrame] = []

    zip_files = sorted(data_dir.glob("*.zip"))
    if zip_files:
        for zpath in zip_files:
            m = re.match(r"^(\d+)$", zpath.stem)
            fallback_sid = int(m.group(1)) if m else None
            with zipfile.ZipFile(zpath, "r") as zf:
                for member in sorted(zf.namelist()):
                    if not member.lower().endswith(".csv") or member.startswith("__MACOSX"):
                        continue
                    sid, sess = parse_csv_identity(member, fallback_subject_id=fallback_sid)
                    if sid is None or sess == "UNKNOWN":
                        continue
                    with zf.open(member, "r") as raw_bin:
                        df = pd.read_csv(io.TextIOWrapper(raw_bin, encoding="utf-8", errors="replace"))
                    is_train_sess = sess in BENCHMARK_SESSIONS
                    cfg = train_config if is_train_sess else eval_config
                    f_df, m_df = extract_session_features(
                        df,
                        subject_id=sid,
                        session_type=sess,
                        config=cfg,
                        is_training=is_train_sess,
                        source_file=f"{zpath.name}:{member}",
                    )
                    if len(f_df) > 0:
                        feat_parts.append(f_df)
                        meta_parts.append(m_df)
    else:
        for csv_path in sorted(data_dir.rglob("*.csv")):
            sid, sess = parse_csv_identity(csv_path.name)
            if sid is None or sess == "UNKNOWN":
                continue
            df = pd.read_csv(csv_path)
            is_train_sess = sess in BENCHMARK_SESSIONS
            cfg = train_config if is_train_sess else eval_config
            f_df, m_df = extract_session_features(
                df,
                subject_id=sid,
                session_type=sess,
                config=cfg,
                is_training=is_train_sess,
                source_file=str(csv_path.relative_to(data_dir)),
            )
            if len(f_df) > 0:
                feat_parts.append(f_df)
                meta_parts.append(m_df)

    if not feat_parts:
        raise FileNotFoundError(f"No valid NASA CSM recordings found in {data_dir}")

    features_df = pd.concat(feat_parts, ignore_index=True)
    meta_df = pd.concat(meta_parts, ignore_index=True)
    return features_df, meta_df


# ---------------------------------------------------------------------------
# Synthetic Smoke-Test Generator (Pipeline Mechanics Verification ONLY)
# ---------------------------------------------------------------------------
def generate_synthetic_smoke_dataset(
    *,
    subject_ids: Sequence[int] = (5, 6, 9, 10, 11, 12, 13, 14),
    benchmark_sec: float = 35.0,
    loft_sec: float = 65.0,
    fs: float = NOMINAL_FS_HZ,
    seed: int = 42,
) -> Dict[Tuple[int, str], pd.DataFrame]:
    """
    Generate small synthetic physiological-like waveforms for pipeline unit/smoke
    testing ONLY. NEVER represents real NASA physiological distributions.
    """
    rng = np.random.default_rng(seed)
    recordings: Dict[Tuple[int, str], pd.DataFrame] = {}

    def _make_recording(n_sec: float, event_schedule: List[Tuple[float, float, int]], subj_offset: float) -> pd.DataFrame:
        n = int(round(n_sec * fs))
        t = np.arange(n, dtype=np.float64) / fs
        events = np.zeros(n, dtype=np.int64)
        for t0, t1, code in event_schedule:
            mask = (t >= t0) & (t < t1)
            events[mask] = code

        # Base rhythms + mild state-dependent spectral shifts
        alpha_amp = np.where(events == 0, 12.0, 6.0)
        beta_amp = np.where(events == 2, 14.0, np.where(events == 5, 10.0, 4.0))
        theta_amp = np.where(events == 5, 11.0, 5.0)
        gamma_amp = np.where(events == 1, 12.0, 3.0)

        data: Dict[str, Any] = {"TimeSecs": t}
        for i, ch in enumerate(EEG_CHANNELS):
            phase = rng.uniform(0, 2 * np.pi)
            sig = (
                alpha_amp * np.sin(2 * np.pi * 10.0 * t + phase)
                + beta_amp * np.sin(2 * np.pi * 20.0 * t + 0.3 * i)
                + theta_amp * np.sin(2 * np.pi * 6.0 * t + 0.2 * i)
                + gamma_amp * np.sin(2 * np.pi * 34.0 * t + 0.1 * i)
                + rng.normal(0.0, 2.0, size=n)
            )
            data[ch] = sig

        # ECG: narrow Gaussian R-peaks + realistic NeXus-10 DC offset (~12,000 uV)
        hr_hz = np.where(events == 1, 1.55, np.where(events == 2, 1.25, 1.10))
        phase_ecg = np.cumsum(hr_hz / fs)
        frac = phase_ecg - np.floor(phase_ecg)
        ecg = 12_000.0 + subj_offset * 500.0 + 900.0 * np.exp(-0.5 * ((frac - 0.5) / 0.015) ** 2) + rng.normal(0, 15.0, size=n)
        data["ECG"] = ecg

        # Respiration: 0.22 Hz baseline, faster under CA/SS
        resp_hz = np.where(events == 1, 0.35, 0.22)
        resp_phase = np.cumsum(2 * np.pi * resp_hz / fs)
        data["R"] = 650.0 + subj_offset * 20.0 + 80.0 * np.sin(resp_phase) + rng.normal(0, 3.0, size=n)

        # GSR: positive baseline with phasic bumps during SS (code 1)
        gsr = 700.0 + subj_offset * 30.0 + np.where(events == 1, 120.0 * np.sin(2 * np.pi * 0.25 * t) ** 2, 0.0) + rng.normal(0, 2.0, size=n)
        data["GSR"] = np.maximum(50.0, gsr)
        data["Event"] = events
        return pd.DataFrame(data)

    for idx, sid in enumerate(subject_ids):
        off = float(idx - len(subject_ids) / 2.0)
        recordings[(sid, "CA")] = _make_recording(benchmark_sec, [(12.0, 28.0, 2)], off)
        recordings[(sid, "DA")] = _make_recording(benchmark_sec, [(12.0, 26.0, 5)], off)
        recordings[(sid, "SS")] = _make_recording(benchmark_sec, [(14.0, 22.0, 1)], off)
        recordings[(sid, LOFT_SESSION)] = _make_recording(
            loft_sec,
            [(15.0, 23.0, 1), (28.0, 42.0, 2), (48.0, 58.0, 5)],
            off,
        )
    return recordings


# ---------------------------------------------------------------------------
# Crew-Grouped Cross-Validation + Calibration + Outer Test Evaluation
# ---------------------------------------------------------------------------
def evaluate_candidate_on_protocol(
    features_df: pd.DataFrame,
    meta_df: pd.DataFrame,
    *,
    model_name: ModelName,
    formulation: FormulationName,
    protocol: ProtocolName = "protocol_a_zeroshot",
    n_outer_test_crews: int = 2,
    apply_causal_norm: bool = True,
    seed: int = 42,
) -> Dict[str, Any]:
    """
    Execute leakage-checked Crew-Grouped LOCO CV on Development crews,
    fit validation-only Temperature Scaling, and evaluate ONCE on untouched
    Outer Test crews.
    """
    # Filter to labeled SQI-valid windows for training; track SQI abstention on eval
    valid_lbl_mask = meta_df["label"].notna()
    features_df = features_df.loc[valid_lbl_mask].reset_index(drop=True)
    meta_df = meta_df.loc[valid_lbl_mask].reset_index(drop=True)

    feature_cols = list(features_df.columns)
    X_all = (
        causal_baseline_normalize(features_df, meta_df)
        if apply_causal_norm
        else features_df.copy()
    )

    split_plan = make_crew_split_plan(meta_df, n_outer_test_crews=n_outer_test_crews, seed=seed)

    dev_fold_metrics: List[Dict[str, Any]] = []
    oof_val_probs: List[np.ndarray] = []
    oof_val_labels: List[np.ndarray] = []

    for train_crews, val_crew in split_plan.loco_folds:
        if protocol == "protocol_a_zeroshot":
            tr_mask = (
                meta_df["crew_id"].isin(train_crews)
                & meta_df["session_type"].isin(BENCHMARK_SESSIONS)
                & meta_df["sqi_valid"]
            )
            va_mask = (meta_df["crew_id"] == val_crew) & (meta_df["session_type"] == LOFT_SESSION)
            allow_same_subj = False
        elif protocol == "protocol_b_calibrated":
            tr_mask = (
                (meta_df["crew_id"].isin(train_crews) | (meta_df["crew_id"] == val_crew))
                & meta_df["session_type"].isin(BENCHMARK_SESSIONS)
                & meta_df["sqi_valid"]
            )
            va_mask = (meta_df["crew_id"] == val_crew) & (meta_df["session_type"] == LOFT_SESSION)
            allow_same_subj = True
        elif protocol == "protocol_c_benchmark_only":
            tr_mask = (
                meta_df["crew_id"].isin(train_crews)
                & meta_df["session_type"].isin(BENCHMARK_SESSIONS)
                & meta_df["sqi_valid"]
            )
            va_mask = (meta_df["crew_id"] == val_crew) & meta_df["session_type"].isin(BENCHMARK_SESSIONS)
            allow_same_subj = False
        else:
            raise ValueError(f"Unknown protocol: {protocol!r}")

        tr_meta = meta_df.loc[tr_mask]
        va_meta = meta_df.loc[va_mask]
        if len(tr_meta) == 0 or len(va_meta) == 0:
            continue

        assert_no_leakage(
            tr_meta,
            va_meta,
            feature_cols,
            allow_same_subject_cross_session=allow_same_subj,
        )

        model = CSMModelWrapper(model_name=model_name, formulation=formulation, seed=seed)
        model.fit(X_all.loc[tr_mask].to_numpy(), tr_meta["label"].to_numpy(dtype=np.int64))
        val_prob = model.predict_proba(X_all.loc[va_mask].to_numpy())
        y_va = va_meta["label"].to_numpy(dtype=np.int64)

        fold_m = compute_classification_metrics(y_va, val_prob)
        fold_m["val_crew_id"] = int(val_crew)
        dev_fold_metrics.append(fold_m)
        oof_val_probs.append(val_prob)
        oof_val_labels.append(y_va)

    if not oof_val_probs:
        raise RuntimeError("No valid development LOCO folds were produced.")

    # Fit post-hoc Temperature Scaling strictly on out-of-fold validation predictions
    oof_probs_cat = np.vstack(oof_val_probs)
    oof_y_cat = np.concatenate(oof_val_labels)
    calibrator = TemperatureScaler().fit(oof_probs_cat, oof_y_cat)

    dev_oof_raw = compute_classification_metrics(oof_y_cat, oof_probs_cat)
    dev_oof_cal = compute_classification_metrics(oof_y_cat, calibrator.transform(oof_probs_cat))

    # Train final candidate on all Dev crews (never seeing Outer Test LOFT!)
    if protocol == "protocol_a_zeroshot":
        final_tr_mask = (
            meta_df["crew_id"].isin(split_plan.dev_crews)
            & meta_df["session_type"].isin(BENCHMARK_SESSIONS)
            & meta_df["sqi_valid"]
        )
        final_te_mask = (
            meta_df["crew_id"].isin(split_plan.outer_test_crews)
            & (meta_df["session_type"] == LOFT_SESSION)
        )
        allow_same_subj_final = False
    elif protocol == "protocol_b_calibrated":
        final_tr_mask = (
            meta_df["session_type"].isin(BENCHMARK_SESSIONS) & meta_df["sqi_valid"]
        )
        final_te_mask = (
            meta_df["crew_id"].isin(split_plan.outer_test_crews)
            & (meta_df["session_type"] == LOFT_SESSION)
        )
        allow_same_subj_final = True
    else:
        final_tr_mask = (
            meta_df["crew_id"].isin(split_plan.dev_crews)
            & meta_df["session_type"].isin(BENCHMARK_SESSIONS)
            & meta_df["sqi_valid"]
        )
        final_te_mask = (
            meta_df["crew_id"].isin(split_plan.outer_test_crews)
            & meta_df["session_type"].isin(BENCHMARK_SESSIONS)
        )
        allow_same_subj_final = False

    final_tr_meta = meta_df.loc[final_tr_mask]
    final_te_meta = meta_df.loc[final_te_mask]
    assert_no_leakage(
        final_tr_meta,
        final_te_meta,
        feature_cols,
        allow_same_subject_cross_session=allow_same_subj_final,
    )

    final_model = CSMModelWrapper(model_name=model_name, formulation=formulation, seed=seed)
    final_model.fit(X_all.loc[final_tr_mask].to_numpy(), final_tr_meta["label"].to_numpy(dtype=np.int64))

    raw_test_prob = final_model.predict_proba(X_all.loc[final_te_mask].to_numpy())
    cal_test_prob = calibrator.transform(raw_test_prob)
    y_test = final_te_meta["label"].to_numpy(dtype=np.int64)

    test_metrics_raw = compute_classification_metrics(y_test, raw_test_prob)
    test_metrics_cal = compute_classification_metrics(y_test, cal_test_prob)

    # Operational LOFT episode/FAR metrics per held-out subject
    operational_by_subject: Dict[str, Any] = {}
    if protocol != "protocol_c_benchmark_only":
        y_pred_cal = np.argmax(cal_test_prob, axis=1)
        for sid in sorted(final_te_meta["subject_id"].unique()):
            smask = (final_te_meta["subject_id"] == sid).to_numpy()
            ts = final_te_meta.loc[smask, "window_end_sec"].to_numpy(dtype=np.float64)
            step = float(np.median(np.diff(np.sort(ts)))) if ts.size > 1 else 1.0
            operational_by_subject[f"subject_{int(sid)}"] = compute_operational_loft_metrics(
                y_test[smask],
                y_pred_cal[smask],
                ts,
                step_sec=max(0.5, step),
            )

    fold_macro_f1s = [fm["macro_f1"] for fm in dev_fold_metrics]

    return {
        "model_name": model_name,
        "formulation": formulation,
        "protocol": protocol,
        "n_features": len(feature_cols),
        "outer_test_crews": list(split_plan.outer_test_crews),
        "dev_crews": list(split_plan.dev_crews),
        "calibration_temperature": round(calibrator.temperature_, 4),
        "dev_loco_macro_f1_mean": round(float(np.mean(fold_macro_f1s)), 4),
        "dev_loco_macro_f1_std": round(float(np.std(fold_macro_f1s)), 4),
        "dev_oof_uncalibrated": dev_oof_raw,
        "dev_oof_calibrated": dev_oof_cal,
        "outer_test_uncalibrated": test_metrics_raw,
        "outer_test_calibrated": test_metrics_cal,
        "outer_test_operational_loft": operational_by_subject,
    }


def run_benchmark_suite(
    *,
    data_dir: Optional[Path] = None,
    audit_manifest: Optional[Path] = None,
    smoke_test_synthetic: bool = False,
    protocol: ProtocolName = "protocol_a_zeroshot",
    ablation: Literal["full", "no_frontal_eog", "wearable_ecg_resp"] = "full",
    seed: int = 42,
    out_file: Optional[Path] = None,
) -> Dict[str, Any]:
    """
    Execute the DEC-001 benchmark suite with strict audit-manifest enforcement.

    Raises AuditManifestError if a real-data run lacks a valid, passed,
    checksum-matching raw-data audit manifest.
    """
    if (data_dir is None) == (not smoke_test_synthetic):
        raise ValueError("Specify exactly ONE of data_dir (real local NASA data) or smoke_test_synthetic=True.")

    if ablation == "full":
        modalities: Tuple[str, ...] = ("eeg", "ecg", "resp", "gsr")
        exclude_frontal = False
    elif ablation == "no_frontal_eog":
        modalities = ("eeg", "ecg", "resp", "gsr")
        exclude_frontal = True
    else:
        modalities = ("ecg", "resp")
        exclude_frontal = False

    audit_meta: Dict[str, Any] = {
        "audit_manifest_path": None,
        "audit_manifest_sha256": None,
        "audit_gate_verdict": None,
        "verified_archive_checksums": None,
    }
    warnings: List[str] = []

    if smoke_test_synthetic:
        train_cfg = FeatureConfig(
            fast_window_sec=4.0,
            slow_window_sec=10.0,
            stride_sec=4.0,
            minority_stride_sec=2.0,
            modalities=modalities,
            exclude_frontal_eog=exclude_frontal,
        )
        eval_cfg = FeatureConfig(
            fast_window_sec=4.0,
            slow_window_sec=10.0,
            stride_sec=2.0,
            modalities=modalities,
            exclude_frontal_eog=exclude_frontal,
        )
        recs = generate_synthetic_smoke_dataset(seed=seed)
        feat_parts, meta_parts = [], []
        for (sid, sess), df in recs.items():
            is_tr = sess in BENCHMARK_SESSIONS
            f_df, m_df = extract_session_features(
                df,
                subject_id=sid,
                session_type=sess,
                config=train_cfg if is_tr else eval_cfg,
                is_training=is_tr,
                source_file=f"synthetic_{sid}_{sess}",
            )
            feat_parts.append(f_df)
            meta_parts.append(m_df)
        features_df = pd.concat(feat_parts, ignore_index=True)
        meta_df = pd.concat(meta_parts, ignore_index=True)
        provenance = "synthetic"
        run_mode = "synthetic_pipeline_smoke_test"
        scientifically_valid = False
        n_outer = 1
        warnings.append(
            "Synthetic pipeline mechanics smoke test only; scientifically invalid for model-performance claims."
        )
    else:
        assert data_dir is not None
        if audit_manifest is None:
            raise AuditManifestError(
                "Refusing scientifically-valid real-data benchmark without --audit-manifest. "
                "Run `python -m csm.audit_raw_data` first and pass its generated audit_manifest.json."
            )
        verified = verify_audit_manifest(audit_manifest, data_dir)
        manifest = verified["manifest"]

        train_cfg = FeatureConfig(
            fast_window_sec=5.0,
            slow_window_sec=30.0,
            stride_sec=5.0,
            minority_stride_sec=1.0,
            modalities=modalities,
            exclude_frontal_eog=exclude_frontal,
        )
        eval_cfg = FeatureConfig(
            fast_window_sec=5.0,
            slow_window_sec=30.0,
            stride_sec=1.0,
            modalities=modalities,
            exclude_frontal_eog=exclude_frontal,
        )
        features_df, meta_df = extract_dataset_from_dir(
            data_dir,
            train_config=train_cfg,
            eval_config=eval_cfg,
        )
        provenance = "real_nasa_csm_local"
        run_mode = "audited_real_data_benchmark"
        scientifically_valid = True
        n_outer = 2
        audit_meta = {
            "audit_manifest_path": str(audit_manifest),
            "audit_manifest_sha256": verified["manifest_sha256"],
            "audit_gate_verdict": manifest["gate_verdict"],
            "verified_archive_checksums": verified["verified_archive_checksums"],
        }

    candidates: List[Tuple[ModelName, FormulationName]] = [
        ("dummy_majority", "multiclass"),
        ("logreg_balanced", "multiclass"),
        ("rf_balanced", "multiclass"),
        ("gbdt_balanced", "multiclass"),
        ("rf_balanced", "binary_per_state"),
        ("rf_balanced", "hierarchical"),
    ]

    runs = []
    for m_name, form in candidates:
        res = evaluate_candidate_on_protocol(
            features_df,
            meta_df,
            model_name=m_name,
            formulation=form,
            protocol=protocol,
            n_outer_test_crews=n_outer,
            seed=seed,
        )
        runs.append(res)

    output = {
        "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "data_provenance": provenance,
        "run_mode": run_mode,
        "scientifically_valid": scientifically_valid,
        "model_validated": False,  # Requires explicit owner review & documented sign-off
        "owner_signoff_recorded": False,
        **audit_meta,
        "ablation": ablation,
        "protocol": protocol,
        "warnings": warnings,
        "runs": runs,
    }

    if out_file is not None:
        out_file.parent.mkdir(parents=True, exist_ok=True)
        out_file.write_text(json.dumps(output, indent=2), encoding="utf-8")
    return output


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="DEC-001 Crew-Grouped Cognitive State Benchmark Runner")
    parser.add_argument("--data-dir", type=Path, default=None, help="Local directory with real NASA CSM ZIP/CSV files")
    parser.add_argument(
        "--audit-manifest",
        type=Path,
        default=None,
        help="Required for --data-dir: path to audit_manifest.json emitted by csm.audit_raw_data",
    )
    parser.add_argument(
        "--smoke-test-synthetic",
        action="store_true",
        help="Run pipeline mechanics verification on synthetic data ONLY (tagged scientifically_valid=false)",
    )
    parser.add_argument("--out-file", type=Path, default=Path("csm_artifacts/benchmark_results.json"))
    parser.add_argument(
        "--protocol",
        choices=("protocol_a_zeroshot", "protocol_b_calibrated", "protocol_c_benchmark_only"),
        default="protocol_a_zeroshot",
    )
    parser.add_argument(
        "--ablation",
        choices=("full", "no_frontal_eog", "wearable_ecg_resp"),
        default="full",
    )
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args(argv)

    if (args.data_dir is None) == (not args.smoke_test_synthetic):
        parser.error("Specify exactly ONE of --data-dir (real local NASA data) or --smoke-test-synthetic.")

    try:
        output = run_benchmark_suite(
            data_dir=args.data_dir,
            audit_manifest=args.audit_manifest,
            smoke_test_synthetic=args.smoke_test_synthetic,
            protocol=args.protocol,
            ablation=args.ablation,
            seed=args.seed,
            out_file=args.out_file,
        )
    except AuditManifestError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    print(
        f"Benchmark complete (provenance={output['data_provenance']}, "
        f"run_mode={output['run_mode']}, scientifically_valid={output['scientifically_valid']}). "
        f"Saved: {args.out_file}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
