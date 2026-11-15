# Data Feasibility Audit Report — DEC-001: AI-Powered Crew Cognitive State Monitoring

**Document Type:** Discovery & Feasibility Audit  
**Decision Reference:** DEC-001  
**Audit Date:** 2026-11-15  
**Audited Repository Baseline:** `ProgrammerAmr/Astronaut-Health-Monitoring-App`  
**Branch:** `arena/586602eb-astronaut-health-monitoring-ap`  
**Base Commit SHA:** `d52c95b4e80936cf6c8a58ba43ef62c4258ba203` (`Restore team AI Flutter data and documentation files`)  
**Dataset Audited:** NASA *Flight Crew Physiological Data for Crew State Monitoring*  
**Official URL:** https://data.nasa.gov/dataset/flight-crew-physiological-data-for-crew-state-monitoring  
**Approved Target Classes:** `Baseline`, `CA` (Channelized Attention), `DA` (Diverted Attention), `SS` (Startle/Surprise)

---

## 1. Executive Conclusion

### **Verdict: `REVISE` (Hold Final Model Training & Integration — Stop Condition #1 Triggered)**

Implementation of a production/final cognitive-state model is **held pending local raw-CSV verification and owner scope revision**:

1. **Stop Condition #1 Triggered (Raw Archive Access & Official Documentation Gaps):**
   - The official NASA Open Data Portal landing page, complete CKAN metadata API (`package_show`), `description.txt`, and primary NASA Langley NTRS technical reports were directly audited.
   - However, the 17 binary `.zip` archives hosted at `https://data.nasa.gov/docs/datasets/public/csm/` could **not** be directly downloaded in the sandboxed audit environment (shell egress restricted to GitHub/npm/PyPI; binary ZIP unsupported by web fetcher; no official NASA GitHub mirror exists). Row-level CSV integrity checks therefore remain **unverified** and must be executed locally using `AI_training/csm/audit_raw_data.py` before any GO decision.
   - Official NASA portal metadata itself contains verified defects: `description.txt` states **18 pilots** in paired crews, whereas the portal publishes only **17 ZIPs** (`20.zip` — right-seat partner of Subject 19 in Crew 10 — is absent); all 18 resources lack file sizes and hashes (`size: null`, `hash: ""`); license is **`notspecified`** (`isopen: false`); EEG units/montage and LOFT ground-truth labeling provenance are undocumented.
2. **Severe Effective Sample Size, Imbalance & Domain-Shift Constraints (Verified in NASA Primary Literature):**
   - Effective independent sample size is **9 cockpit crews** (17 published pilots: 8 complete pairs + 1 singleton), **100% male commercial airline pilots** (zero females, zero astronauts).
   - Extreme class imbalance across SHARP-1: **~83% Baseline, ~14% CA, ~2% DA, ~1% SS** (~15–30 s of SS in benchmarks; ~25–42 s in LOFT). NASA's SHARP-1 evaluation yielded **`0.64 ± 0.14` weighted AUC** on participant-dependent benchmark→LOFT transfer for just two states (CA vs. SS) across the 13/24 pilots with complete datasets.
   - NASA's LOFT scenario validation confirmed imperfect state induction (e.g., 58% Captains / 33% First Officers for wake-encounter SS; 42% of crews for flap-asymmetry CA).
3. **Repository & Architecture Mismatch (Verified in Repo Inspection):**
   - No `DEC-001` record existed prior to this audit (`docs/decisions` was a 1-byte empty file).
   - The existing OrbitCare stack (`AI_training/nasa_claude.py`, `backend/`, `Flutter/`) handles **low-frequency scalar vitals** (HR, BP, SpO2, sleep, radiation) via rules + LLM RAG, whereas NASA CSM requires **256 Hz, 23-channel raw waveforms** (20-ch EEG + 3-lead ECG + chest respiration + finger GSR).

**Conditional Path Forward:**
- For an **offline, non-diagnostic, aviation-analog research/debrief prototype** (replaying pre-recorded multimodal sessions with strict SQI abstention and uncertainty reporting), DEC-001 can move to a conditional **GO** once the local raw-CSV audit passes and the owner approves the scope revisions in Section 12.
- For a **real-time, subject-independent, 4-class operational astronaut monitor** integrated directly into OrbitCare's current scalar-vitals hardware/API stack, this dataset is a **`NO-GO`**.

---

## 2. Repository Inspection & Dataset Provenance

### 2.1 Verified Repository State at Base Commit `d52c95b4e80936cf6c8a58ba43ef62c4258ba203`

| Path | Verification Result |
|---|---|
| `README.md` | Exists (55 lines). Educational prototype; non-diagnostic; Flutter + Node.js + Python; no CSM reference. |
| `docs/ARCHITECTURE_AND_INTERFACES.md` | Exists (190 lines). Provisional HTTP/JSON contracts for scalar vitals (`/api/measurements`, `/api/alerts`, `/api/analysis`); mandates provenance separation (real vs. simulated vs. synthetic). |
| `docs/REQUIREMENTS_AND_EVALUATION.md` | Exists (130 lines). FR-01..FR-05, NFR-01..NFR-05; mandates documented methods, uncertainty communication, and prohibits unvalidated medical diagnostic claims (§9). |
| `docs/DATA_AND_DELIVERABLES.md` | Exists (152 lines). Requires documenting units, missing data, license/redistribution terms, avoiding leakage, and keeping large datasets outside GitHub (§3–§6). |
| `docs/decisions` *(prior to branch)* | Was a **1-byte empty file** (not a directory). Zero `DEC-001` references existed anywhere in the repo. |
| `ai_training/AI_README.md` (lowercase) | **Did not exist** (Linux case-sensitive path). Actual path is **`AI_training/AI_README.md`**. |
| `AI_training/AI_README.md` | Exists (81 lines). Rules + ChromaDB/Ollama RAG vitals service (`nasa_claude.py`, `ai_service.py`, `thresholds.json` with `validated: false`). Note internal doc discrepancy: references `tests/test_nasa_claude.py`, whereas actual test file is `AI_training/test_nasa_claude.py` (35 passing tests). |
| `AI_backend/` | Empty directory containing only `.gitkeep`. |
| Existing Data & Backend Models | `backend/src/models/Measurement.js` and `AI_training/thresholds.json` cover scalar vitals only. Existing datasets (`data/bidmc/`, `AI_training/nasa_docs/`) are BIDMC 1 Hz ICU numerics, NASA OSDR omics/CBC metadata, NHANES `P_DEMO.csv`, and spaceflight BP summary tables. Zero 256 Hz EEG/ECG/R/GSR ingestion existed. |

### 2.2 Dataset Provenance (Verified Facts)

- **Official Portal:** https://data.nasa.gov/dataset/flight-crew-physiological-data-for-crew-state-monitoring
- **CKAN API:** `https://data.nasa.gov/api/3/action/package_show?id=flight-crew-physiological-data-for-crew-state-monitoring`
- **Package ID:** `7f671252-e746-407d-b255-83dc743a8df5` | **Legacy ID:** `https://data.nasa.gov/api/views/8a5d-xhfr`
- **Publisher / Maintainer:** Dr. Angela R. Harrivel (`angela.r.harrivel@nasa.gov`), NASA Langley Research Center (CSAOB)
- **Catalog Dates:** Issued `2019-09-17`; Modified `2024-05-15`; CKAN Created `2025-03-31T15:15:46Z`; CKAN Updated `2025-04-23T22:40:38Z`
- **Originating Study:** **SHARP-1** (*Scenarios for Human Attention Restoration using Psychophysiology*, Spring 2016, NASA LaRC Cockpit Motion Facility, CAST SE211, NASA LaRC IRB-approved). Primary NASA sources:
  - Harrivel et al. (2016), AIAA SciTech, NTRS `20160007651`
  - Harrivel et al. (2017), AIAA SciTech, NTRS `20170001220`
  - Stephens et al. (2017), ISAP, NTRS `20170005473`
  - Comstock et al. (2020), `NASA/TM-2020-220576`, NTRS `20200002935`
  - Terwilliger, Sarle, Walker, & Harrivel (2020), MODSIM World Paper No. 0053
  - Harrivel et al. (2021), `NASA/TM-20205003444`, NTRS `20205003444`
- **License & Redistribution Terms:** Portal states `accessLevel: "public"`, `private: false`, **but** `isopen: false`, `license_id: "notspecified"`, `license_title: "License not specified"`. `description.txt` specifies no license or redistribution terms. Raw files must NOT be committed to GitHub.

---

## 3. Resource Inventory (Verified via NASA CKAN API)

| Pos | Resource Name | Official Source URL | Format / MIME | CKAN Size / Hash | Sandbox Audit Status |
|---:|---|---|---|---|---|
| 0–10 | `5, 6, 9, 10, 11, 12, 13, 14, 17, 18, 19` | `https://data.nasa.gov/docs/datasets/public/csm/<id>.zip` | ZIP (`application/zip`) | `null` / `""` | Not downloaded in sandbox (egress/binary restriction); verify locally via `audit_raw_data.py` |
| — | *(Missing)* `20` | `https://data.nasa.gov/docs/datasets/public/csm/20.zip` | — | — | **ABSENT from NASA catalog** (must probe locally via `--check-missing-20`) |
| 11–16 | `21, 22, 23, 24, 25, 26` | `https://data.nasa.gov/docs/datasets/public/csm/<id>.zip` | ZIP (`application/zip`) | `null` / `""` | Not downloaded in sandbox; verify locally via `audit_raw_data.py` |
| 17 | `Description` | `https://data.nasa.gov/docs/datasets/public/csm/description.txt` | TXT (`text/plain`) | `null` / `""` | **Fetched & fully audited** (59 lines, S3 presigned redirect) |

---

## 4. Participant, Session & Channel Inventory

### 4.1 Participants & Crew Pairing

Per `description.txt`, crew `i` consists of left-seat subject `2i-1` (odd) and right-seat subject `2i` (even):

| Crew ID | Left Seat (Captain) | Right Seat (First Officer) | Portal Status |
|---:|---|---|---|
| 1, 2, 4, 8 | `1, 3, 7, 15` | `2, 4, 8, 16` | Excluded from public release |
| 3 | `5.zip` | `6.zip` | Complete pair |
| 5 | `9.zip` | `10.zip` | Complete pair |
| 6 | `11.zip` | `12.zip` | Complete pair |
| 7 | `13.zip` | `14.zip` | Complete pair |
| 9 | `17.zip` | `18.zip` | Complete pair |
| 10 | `19.zip` | **`20.zip` MISSING** | **Unpaired singleton** |
| 11 | `21.zip` | `22.zip` | Complete pair |
| 12 | `23.zip` | `24.zip` | Complete pair |
| 13 | `25.zip` | `26.zip` | Complete pair |

- **Totals:** **17 published pilots** across **9 cockpit crews** (8 complete pairs + 1 singleton).
- **Cohort Demographics (Verified, Harrivel et al., 2017 §II & Stephens et al., 2017):** Commercial airline pilots averaging 22,000 flight hours (B-757/B-787), **100% male ("none female")**.

### 4.2 Sessions & Expected Files per Subject

- Morning Benchmarks (non-flight desktop, ~6 min each): `<id>_CA.csv` (Tetris), `<id>_DA.csv` (display vigilance + periodic math every 20–30 s), `<id>_SS.csv` (jump-scare movie clips, ~15 s per startle).
- Afternoon Operational Sim (~60–90 min gate-to-gate): `<id>_Loft.csv` (motion-based flight simulator with 2 CA events, 2 SS events, ≥2 DA events).
- Primary literature (Terwilliger & Harrivel, 2020 §1.1) reports **~2.3 × 10⁷ total rows** across all 18 pilots (4 files each). Exact row counts and durations for the 17 published ZIPs are **unverified** until local audit runs.

### 4.3 Physiological Channels & Synchronization (25 Columns @ 256 Hz)

| Column(s) | Sensor Hardware | Rate | Documented Spec (`description.txt`) | Documented Units / Gaps |
|---|---|---:|---|---|
| `TimeSecs` | EyesDx MAPPS sync clock | 256 Hz | Elapsed seconds | Monotonicity/gap behavior unverified |
| 20 EEG channels (`EEG_FP1`..`EEG_O2`) | ABM **B-Alert X24** | 256 Hz | 10–20 scalp montage | **Units, reference electrode, and hardware filters UNSPECIFIED** |
| `ECG` | Mind Media **NeXus-10 Mark II** (3-point) | 256 Hz | `0.012215 µV/bit`; `-100 mV` to `+100 mV` | Implicitly µV; true-DC amplifier introduces large (~12 mV) DC offsets |
| `R` | **NeXus-10 Mark II** (chest belt) | 256 Hz | `0.2384186 µV/bit`; `-2.0 V` to `+2.0 V` | Relative uncalibrated chest-expansion voltage (µV) |
| `GSR` | **NeXus-10 Mark II** (finger electrodes) | 256 Hz | `0.2384186 µV/bit`; `-2.0 V` to `+2.0 V` | Raw voltage (µV); conversion to µS undocumented |
| `Event` | Event marker | 256 Hz | Integer `{0, 1, 2, (3, 4), 5}` | Categorical cognitive-state label |

---

## 5. Label and Class Analysis

- **Official Mapping (`description.txt`):** `0 = Baseline (No event)`, `1 = SS`, `2 = CA`, `5 = DA`.
- **Stray Code Risk:** `description.txt` notes *"3: There should be no 3s. If there are, treat them as 0s"* and *"4: There should be no 4s. If there are, treat them as 0s."* If present in raw CSVs (e.g., residual SHARP-1 Workload or Confirmation Bias codes), collapsing `3`/`4` into `0` contaminates Baseline. Raw frequency must be verified locally.
- **Extreme Imbalance (Terwilliger & Harrivel, 2020 §1.1):** **~83% Baseline, ~14% CA, ~2% DA, ~1% SS**.
- **LOFT Ground-Truth Uncertainty:** NASA reports describe both *intended scenario event windows* (Harrivel et al., 2017) and *post-hoc NASA/Boeing SME video annotation* (NASA/TM–20205003444 §II.B), without clarifying which populates `*_Loft.csv`. Furthermore, intended LOFT events failed to induce behavioral states in 42–67% of pilots depending on role and event (Stephens et al., 2017).

---

## 6. Signal-Quality Assessment

- **Verified Primary Evidence:** `description.txt` warns of noise/artifacts; SHARP-1 lost 11 of 24 pilots to incomplete data in Harrivel et al. (2017) and excluded Smart Eye tracking due to pervasive dropout; Terwilliger & Harrivel (2020) note substantial data had to be discarded due to biophysical noise; pilot surveys documented wire binding and finger-GSR interference (Harrivel et al., 2017 Table 5).
- **Secondary Hypotheses (Kaggle Derivative — Unverified on Raw NASA ZIPs):** High GSR zero-dropout spikes (`GSR == 0`, bimodal gap `~50–250 µV`), large ECG DC offsets (`-18.6k` to `+34.2k µV`) with train/test range shifts, respiration baseline offsets correlated with seat, and higher EEG variance/zero-spikes in LOFT.
- **Mandatory Local Verification:** Implemented in `AI_training/csm/audit_raw_data.py` to produce exact per-file tables for NaNs, flatlines, GSR zeros, rail saturation, `TimeSecs` discontinuities, `Event` codes `0..5`, and contiguous episode counts.

---

## 7. Potential Confounders and Domain Shift

1. **Task-Artifact Confounding:** Benchmark classes map 1-to-1 to distinct tasks in separate files (`CA = Tetris`, `DA = Vigilance+Math`, `SS = Jump-Scare Movies`), confounding oculomotor/blink EOG (`EEG_FP1/FP2/F7/F8`), motor EMG, and file-level impedance drift with cognitive labels.
2. **Global Timestamp Leakage:** Verified by Terwilliger & Harrivel (2020 §1.2) — `TimeSecs` predicts scripted event offsets and must be strictly excluded from model features.
3. **Morning Benchmark → Afternoon LOFT Shift:** Nominal LOFT flying has NASA-TLX workload = **62** (matching benchmark CA = 62 / DA = 59, vs. Rest = 25; Harrivel et al., 2017 Table 6), plus 6-DOF simulator motion, live ATC speech EMG, circadian/gel drift, and left/right seat duty asymmetry.
4. **Aviation → Astronaut Operational Shift:** 100% male airline pilots in 1g simulator with 20-ch wet-gel EEG vs. sex-diverse astronauts in microgravity (cephalad fluid shifts, autonomic remodeling, wearable constraints).
5. **Small Effective Sample Size:** 9 independent crews (17 pilots), with ≤~34 pilot-level SS episodes in benchmarks and ≤~34 in LOFT.

---

## 8. Leakage-Resistant Evaluation Proposal

Implemented in `AI_training/csm/evaluation.py`:

- **Hard Anti-Leakage Invariants:** Zero random window splitting; strict exclusion of `TimeSecs`, `crew_id`, `subject_id`, `seat`, `experiment`; strict **Crew-Level Grouping** (`crew_id = (subject_id + 1) // 2`) so cockpit pairs never split across folds; all scalers/imputers/calibrators fitted strictly inside training/validation folds; strictly causal trailing windows.
- **Outer Vault + Inner LOCO CV:** Hold out **2–3 complete crews** untouched as an Outer Test Vault; run **Leave-One-Crew-Out (LOCO)** CV on the remaining 6–7 Development crews.
- **Dual Protocols:**
  - **Protocol A (Primary — Zero-Shot Subject-Independent, Benchmark → LOFT):** Train on `(K-1)` dev crews, select on held-out dev crew's LOFT, final once-only test on untouched outer crews' LOFT (+ Benchmark diagnostic).
  - **Protocol B (Secondary — Per-User Baseline-Calibrated, Benchmark → LOFT):** Permits causal calibration using each test pilot's morning benchmark/resting baseline only (zero test LOFT leakage).
  - **Contingency Protocol C (Benchmark-Only Crew-Grouped LOCO):** Activated only if raw-CSV audit proves LOFT labels are invalid/incomplete, with explicit scope downgrade prohibiting operational claims.

---

## 9. Preprocessing Recommendations

Implemented in `AI_training/csm/preprocessing.py` and `AI_training/csm/features.py`:

- **Discontinuity Splitting:** Split continuous streams wherever `|Δt - 1/256| > 5 ms` or timestamps reset; never filter/window across gaps.
- **Modality-Specific DSP:** EEG (`1–40 Hz` bandpass, `60 Hz` notch, valid-channel CAR); ECG (DC offset removal, `0.5–40 Hz` + `5–15 Hz` Pan-Tompkins R-peak detection with physiological RR filtering `0.30–1.80 s`); Respiration (`0.05–1.0 Hz` bandpass); GSR (zero-dropout masking prior to `1.5 Hz` low-pass + tonic SCL `< 0.05 Hz` / phasic SCR `0.05–1.5 Hz` split).
- **SQI Abstention Gate:** Per-window Signal Quality Index flags dead/saturated/dropout windows and forces `INSUFFICIENT_DATA` output.
- **Dual-Scale Causal Windows:** `5 s` trailing fast window (EEG/acute HR/SCR) + `30 s` trailing slow context window (HRV RMSSD/SDNN, respiration rate, tonic GSR slope); low-overlap training stride with `≥95%` label purity; full sequential evaluation stride.
- **Causal Normalization:** Within-session initial-baseline z-scoring (causal only — never full-recording mean/std) + fold-local `RobustScaler`.

---

## 10. Model Formulation & Candidate Architectures

Implemented in `AI_training/csm/models.py` (for local benchmarking after Stop Condition #1 clears):

- **Tier 0 Baselines:** Majority-class dummy + Class-weighted L2 Logistic Regression.
- **Tier 1 Primary Candidates:** Balanced Random Forest + Class-weighted Regularized GBDT (XGBoost / HistGradientBoosting) with feature/modality ablations (`full 4-modality`, `exclude_frontal_eog` blink-confounding check, and `ecg+resp` wearable-feasible subset).
- **1D CNN Assessment:** **Not justified as an initial primary architecture** on raw 256 Hz waveforms (N = 9 crews; Terwilliger & Harrivel, 2020 documented overfitting at 4/64ths of Epoch 1). Only compact strongly regularized architectures (e.g., EEGNet-scale) may be explored in Phase 2 after Tier 1 baselines are locked.
- **Formulations Compared:** 4-class multiclass softmax vs. 3 binary-per-state One-vs-Rest detectors vs. 2-stage hierarchical (`Any-AHPLS vs. Baseline` → `CA/DA/SS`).
- **Metrics & Calibration:** Per-class Precision/Recall/F1, Macro-F1, PR-AUC, ROC-AUC, 4×4 Confusion Matrix, Log-Loss, Brier Score, ECE, post-hoc **Temperature Scaling** (validation-fold only), plus LOFT episode recall, onset latency, and **False Alarm Rate per Hour (FAR/hr)**.
- **Explainability Limits:** SHAP/Gini attribution is associative (not causal), unstable across collinear EEG channels, cannot distinguish ocular/EMG artifacts from cognition, and faces physiological non-specificity.

---

## 11. Risks, Unknowns, and Evidence Gaps

1. **Raw ZIPs uninspected in sandbox** (Blocker — Stop Condition #1).
2. **`20.zip` absent from NASA portal** (17 ZIPs vs. 18 pilots claimed).
3. **`license_id: "notspecified"`, `isopen: false`** (blocks committing dataset copies to GitHub).
4. **Undocumented EEG units/montage & LOFT label provenance** (scenario intent vs. SME video).
5. **Small N (9 crews, 100% male pilots) & extreme rare-class sparsity (~1% SS, ~2% DA).**
6. **Severe task-artifact confounding, LOFT baseline TLX shift (62 vs. 25), and aviation→spaceflight physiological gap.**
7. **Product hardware/API mismatch** with OrbitCare's current scalar-vitals architecture.

---

## 12. Owner Approval Checklist (Required Before Production Training / Integration)

- [ ] **Gate 1 (Mandatory):** Run `python -m csm.audit_raw_data --download --check-missing-20 --data-dir ./local_nasa_csm --out-dir ./audit_outputs` locally on an unrestricted machine and review generated `audit_report.md`.
- [ ] **Gate 2 (Scope Framing):** Confirm DEC-001 is explicitly scoped and UI-badged as an *offline, non-diagnostic aviation-analog research prototype* (and decide whether to evaluate the wearable-feasible `ECG + Respiration` ablation alongside full 23-channel EEG+peripheral).
- [ ] **Gate 3 (Evaluation Protocol):** Approve Crew-Grouped Outer Test Vault (`2–3 crews`) and primary evaluation regime (`Protocol A: Zero-Shot` vs. `Protocol B: Per-User Calibrated`).
- [ ] **Gate 4 (Acceptance Thresholds & Fallback):** Approve minimum acceptable Macro-F1, per-class SS/DA PR-AUC, and LOFT FAR/hr targets, plus whether 2-stage hierarchical fallback is acceptable if 4-class SS/DA recall is insufficient.
- [ ] **Gate 5 (Governance & Legal):** Confirm raw NASA files remain excluded from Git (`.gitignore`), verify NASA reuse terms / contact maintainer (`angela.r.harrivel@nasa.gov`) regarding missing `20.zip` and EEG/LOFT documentation, and sign off on `docs/decisions/DEC-001_COGNITIVE_STATE_MONITORING.md`.
