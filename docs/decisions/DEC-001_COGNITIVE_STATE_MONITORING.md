# DEC-001: AI-Powered Crew Cognitive State Monitoring

- **Status:** Proposed (`REVISE` — Held Pending Local Raw-CSV Audit & Owner Sign-Off)
- **Date:** 2026-11-15
- **Related Audit:** `docs/decisions/DEC-001_FEASIBILITY_AUDIT.md`
- **External Dataset Reference:** `data/external/nasa_csm/README.md`
- **Engineering Scaffolding:** `AI_training/csm/`

---

## 1. Context

The project owner proposed adding AI-powered crew cognitive state monitoring targeting four classes:
- `Baseline` (No event)
- `CA` (Channelized Attention)
- `DA` (Diverted Attention)
- `SS` (Startle/Surprise)

using NASA's *Flight Crew Physiological Data for Crew State Monitoring* (SHARP-1, NASA Langley Research Center).

The feasibility audit (`docs/decisions/DEC-001_FEASIBILITY_AUDIT.md`) verified that:
1. The existing OrbitCare stack (`AI_training/nasa_claude.py`, `backend/`, `Flutter/`) ingests **low-frequency scalar vitals** (HR, BP, SpO2, sleep, radiation), whereas NASA CSM contains **256 Hz, 23-channel raw waveforms** (20 EEG + ECG + Respiration + GSR).
2. The public NASA dataset has **9 independent cockpit crews (17 published pilots; `20.zip` missing)**, 100% male airline pilots, severe class imbalance (~83% / ~14% / ~2% / ~1%), undocumented license (`notspecified`), and substantial benchmark→LOFT and aviation→spaceflight domain shifts.
3. Raw `.zip` files could not be downloaded inside the restricted audit environment (Stop Condition #1), so local raw-CSV verification must precede any model training or product integration.

---

## 2. Decision (Provisional Scope & Engineering Guardrails)

### 2.1 Non-Diagnostic & Operational Framing
- DEC-001 is strictly an **experimental, non-diagnostic attention-awareness research prototype** (e.g., offline pre-recorded session replay / post-mission debrief analysis).
- Outputs **must never** be presented as medical diagnoses, psychological evaluations, or flight-certified astronaut telemetry.
- All outputs must carry explicit provenance (`real_nasa_csm_replay | live_sensor | simulated | synthetic`), `model_status.validated` (`false` until audited real-data validation gates pass), Signal Quality Index (SQI), calibration status, and explicit limitations.

### 2.2 Clean Architectural Isolation
- DEC-001 lives in a dedicated, isolated package `AI_training/csm/` so the existing OrbitCare rule-based vitals + RAG service (`AI_training/nasa_claude.py` and `AI_training/ai_service.py`) remains completely unaffected and backward-compatible.
- No trained model artifacts are committed to this branch prior to passing Gate 1 (raw NASA CSV audit) and Gate 3–4 (crew-grouped evaluation).

### 2.3 Mandatory Technical Guardrails
1. **Data Governance:** Raw NASA ZIP/CSV files must remain outside Git (enforced via `.gitignore` and documented in `data/external/nasa_csm/README.md`).
2. **Leakage Prevention:** Every split is grouped by **Crew ID** (`crew_id = (subject_id + 1) // 2`). `TimeSecs`, `subject_id`, `crew_id`, `seat`, and `experiment` are strictly forbidden as model inputs. All scalers, imputers, and calibrators are fitted inside training/validation folds only.
3. **Signal Quality Abstention:** Low-SQI windows (sensor dropout, GSR zero lead-off, flatlines, rail saturation, time discontinuities) must return `status: "INSUFFICIENT_DATA"` — never silently defaulting to `Baseline`.
4. **Confounding & Wearable Feasibility Ablations:** Every benchmark run must include:
   - Full 4-modality (`EEG + ECG + Resp + GSR`)
   - Frontal-EOG-excluded EEG ablation (drops `FP1, FP2, F7, F8` to measure blink/facial-EMG confounding)
   - Wearable-feasible peripheral ablation (`ECG + Resp`, matching feasible astronaut/OrbitCare wearables without a 20-ch wet-gel EEG cap)
5. **Calibration & Operational Metrics:** Report per-class Precision/Recall/F1, Macro-F1, PR-AUC, 4×4 confusion matrix, Log-Loss, Brier, ECE (with validation-only Temperature Scaling), and LOFT episode recall + False Alarm Rate per hour (FAR/hr).

---

## 3. Proposed JSON Analysis Contract (`AI_training/csm/contract.py`)

Aligned with `docs/ARCHITECTURE_AND_INTERFACES.md` §6 and `AI_training/AI_README.md`:

```json
{
  "schema_version": "1.0-dec001-draft",
  "status": "OK | INSUFFICIENT_DATA | ERROR",
  "astronaut_id": "pilot-13",
  "session_id": "13_Loft",
  "window_end_sec": 1245.0,
  "processed_at": "2026-11-15T12:00:00Z",
  "data_provenance": "real_nasa_csm_replay",
  "prediction": {
    "state": "CA",
    "probabilities": {"Baseline": 0.18, "CA": 0.72, "DA": 0.08, "SS": 0.02},
    "confidence": 0.72,
    "abstained": false
  },
  "signal_quality": {
    "sqi_score": 0.94,
    "valid": true,
    "eeg_valid_fraction": 1.0,
    "gsr_valid_fraction": 1.0,
    "ecg_valid": true,
    "resp_valid": true,
    "reasons": []
  },
  "model_status": {
    "model_id": "untrained-draft",
    "validated": false,
    "calibrated": false,
    "evaluation_protocol": "Protocol_A_ZeroShot_CrewGrouped",
    "cohort_limitations": [
      "Trained/evaluated on 100% male commercial airline pilots in 1g flight simulator (SHARP-1)",
      "Not validated on female subjects or microgravity spaceflight physiology"
    ]
  },
  "warnings": [],
  "errors": [],
  "disclaimer": "Experimental research prototype for attention-awareness support only. Not a medical diagnosis, not flight-certified, and not a substitute for professional medical or operational judgment."
}
```

---

## 4. Consequences & Next Steps

- **Positive:** Prevents silent data leakage, fake metrics, and accidental legal/storage violations while giving the team a ready-to-run, thoroughly tested pipeline once the NASA ZIPs are downloaded locally.
- **Negative / Tradeoffs:** Defers UI/backend live integration until real NASA evaluation metrics confirm whether 4-class (or 2-stage hierarchical) detection achieves acceptable FAR/hr and rare-class recall.
- **Immediate Owner Action:** Run `python -m csm.audit_raw_data --download --check-missing-20` locally, review the resulting `audit_report.md`, and approve Gates 1–5 in `docs/decisions/DEC-001_FEASIBILITY_AUDIT.md`.
