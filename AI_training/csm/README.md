# DEC-001 Crew Cognitive State Monitoring (`AI_training/csm`)

> **Governance Status:** `REVISE` — Research & audit scaffolding only. **No trained model is shipped or validated in this repository.** All real-data runs require executing Gate 1 (`audit_raw_data`) locally on the official NASA CSM archives outside Git.

## Overview

This package isolates DEC-001 biomedical signal processing and evaluation from the existing OrbitCare rule-based vitals + RAG module (`AI_training/nasa_claude.py`, `AI_training/ai_service.py`):

| Module | Responsibility |
|---|---|
| `constants.py` | Official NASA `description.txt` 25-column schema, `Event` mapping (`0,1,2,5` + stray `3/4` tracking), 17 published subject IDs, crew pairing (`crew_id = (subject_id + 1) // 2`), forbidden leakage columns |
| `audit_raw_data.py` | Streaming (constant-memory) local downloader + Stop-Condition #1 raw-CSV auditor (NaNs, `TimeSecs` gaps, GSR zero-dropouts, saturation, flatlines, stray `3/4` codes, LOFT 4-class coverage, SHA-256 checksums) |
| `preprocessing.py` | Discontinuity splitting (`split_contiguous_segments`), numerically stable SOS filtering for EEG/ECG/Respiration/GSR, NeXus-10 DC offset removal, GSR zero-dropout masking + tonic/phasic split, Pan-Tompkins QRS detection, per-window SQI |
| `features.py` | Strictly causal dual-scale windowing (`5 s` fast + `30 s` slow context), EEG spectral bands + NASA Engagement Index + Hjorth, ECG/HRV, Respiration rate, GSR SCL/SCR + drop score, plus `exclude_frontal_eog` and `ecg+resp` ablations |
| `evaluation.py` | Runtime anti-leakage assertions (`assert_no_leakage`), Crew-Grouped Outer Test Vault + Dev LOCO CV, causal initial-baseline normalization, validation-only Temperature Scaling, per-class PR-AUC/F1/Confusion Matrix/ECE, and LOFT episode recall + FAR/hr |
| `models.py` | Tier 0 (`dummy_majority`, `logreg_balanced`) and Tier 1 (`rf_balanced`, `gbdt_balanced`) wrappers across `multiclass`, `binary_per_state`, and `hierarchical` formulations |
| `contract.py` | OrbitCare-aligned non-diagnostic JSON contract enforcing `INSUFFICIENT_DATA` abstention on low SQI and rejecting untrusted `model_validated=true` claims unless backed by a verified real-data evaluation artifact |
| `service.py` | Isolated FastAPI router (`/csm/status`, `/csm/analyze`) mounted by `AI_training/ai_service.py` without altering existing `/health` or `/analyze`; rejects `live_sensor` & raw signal uploads, never persists raw signals, never invents probabilities |
| `run_benchmark.py` | End-to-end crew-grouped benchmark CLI enforcing verified `--audit-manifest` checksums for real NASA data + strictly tagged `--smoke-test-synthetic` mode (`data_provenance="synthetic"`, `scientifically_valid=false`) |

## Quickstart

### 1. Install Dependencies
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r AI_training/csm/requirements-csm.txt
```

### 2. Run Automated Tests (Existing OrbitCare + DEC-001 Package + FastAPI Service)
```bash
pytest -q AI_training/test_nasa_claude.py AI_training/csm/tests/test_csm_pipeline.py AI_training/csm/tests/test_csm_service.py
```

### 3. Run Mandatory Gate 1 Local Raw-Data Audit (Unrestricted Machine)
```bash
PYTHONPATH=AI_training python -m csm.audit_raw_data \
  --download \
  --check-missing-20 \
  --data-dir data/external/nasa_csm/raw \
  --out-dir audit_outputs/nasa_csm
```
This emits `audit_outputs/nasa_csm/audit_manifest.json` (schema version, timestamp, SHA-256 checksums, gate verdict, gate details, and provenance).

### 4. Run Crew-Grouped Baseline Benchmark (Requires Passed Audit Manifest)
```bash
PYTHONPATH=AI_training python -m csm.run_benchmark \
  --data-dir data/external/nasa_csm/raw \
  --audit-manifest audit_outputs/nasa_csm/audit_manifest.json \
  --protocol protocol_a_zeroshot \
  --ablation full \
  --out-file csm_artifacts/benchmark_protocol_a_full.json
```
Additional mandatory confounding & feasibility ablations:
- `--ablation no_frontal_eog` (drops `EEG_FP1/FP2/F7/F8` to test blink/facial-EMG confounding)
- `--ablation wearable_ecg_resp` (tests wearable-feasible `ECG + Respiration` subset without 20-ch wet-gel EEG)
