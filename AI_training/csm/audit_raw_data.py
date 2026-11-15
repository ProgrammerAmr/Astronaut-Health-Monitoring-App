"""
Reproducible Stop-Condition #1 Raw Data Downloader & Streaming Auditor for DEC-001.

Usage (on a machine with unrestricted access to data.nasa.gov):
    PYTHONPATH=AI_training python -m csm.audit_raw_data \
        --download \
        --check-missing-20 \
        --data-dir data/external/nasa_csm/raw \
        --out-dir audit_outputs/nasa_csm

Or audit already-downloaded ZIP archives locally without downloading:
    PYTHONPATH=AI_training python -m csm.audit_raw_data \
        --data-dir data/external/nasa_csm/raw \
        --out-dir audit_outputs/nasa_csm

All CSV files are streamed chunk-by-chunk (constant memory) so ~2.3e7 rows across
the 17 NASA archives can be audited cleanly on a standard laptop.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import sys
import urllib.error
import urllib.request
import zipfile
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

import numpy as np
import pandas as pd

from .constants import (
    ECG_RAIL_UV,
    EEG_CHANNELS,
    EVENT_COLUMN,
    EXPECTED_COLUMNS,
    GSR_DROPOUT_THRESHOLD,
    MISSING_EXPECTED_SUBJECT_IDS,
    NASA_DESCRIPTION_URL,
    NOMINAL_DT_SEC,
    NOMINAL_FS_HZ,
    PUBLISHED_SUBJECT_IDS,
    RAW_EVENT_TO_CLASS,
    RESP_GSR_RAIL_UV,
    SIGNAL_CHANNELS,
    STRAY_EVENT_CODES,
    TARGET_CLASSES,
    TIME_COLUMN,
    subject_to_crew_id,
    subject_to_seat,
    subject_zip_url,
)

SESSION_FILENAME_RE = re.compile(r"(?:^|[/_-])(\d+)_(CA|DA|SS|LOFT)\.csv$", re.IGNORECASE)

AUDIT_MANIFEST_SCHEMA_VERSION = "1.0-dec001-audit-manifest"
AUDIT_MANIFEST_FILENAME = "audit_manifest.json"
REQUIRED_AUDIT_GATES = (
    "archive_access",
    "schema_integrity",
    "label_mapping",
    "loft_4class_coverage",
)
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class AuditManifestError(ValueError):
    """Raised when an audit manifest is missing, malformed, failed, or checksum-mismatched."""


# ---------------------------------------------------------------------------
# Helpers: Hashing, Downloading & Filename Parsing
# ---------------------------------------------------------------------------
def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def parse_csv_identity(member_name: str, fallback_subject_id: Optional[int] = None) -> Tuple[Optional[int], str]:
    """Extract (subject_id, canonical_session_type) from a CSV filename like '5_Loft.csv'."""
    m = SESSION_FILENAME_RE.search(member_name.replace("\\", "/"))
    if m:
        return int(m.group(1)), m.group(2).upper()
    stem = Path(member_name).stem.upper()
    for sess in ("LOFT", "CA", "DA", "SS"):
        if stem.endswith(f"_{sess}") or stem == sess:
            return fallback_subject_id, sess
    return fallback_subject_id, "UNKNOWN"


def download_url(url: str, dest: Path, timeout_sec: float = 120.0) -> Dict[str, Any]:
    """Download one URL to dest (skipping if non-empty file already exists)."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        return {
            "url": url,
            "path": str(dest),
            "status": "cached",
            "bytes": dest.stat().st_size,
            "sha256": sha256_file(dest),
        }

    req = urllib.request.Request(url, headers={"User-Agent": "OrbitCare-DEC001-Audit/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
            status_code = getattr(resp, "status", 200)
            tmp_path = dest.with_suffix(dest.suffix + ".part")
            h = hashlib.sha256()
            total = 0
            with tmp_path.open("wb") as out:
                while True:
                    buf = resp.read(1 << 20)
                    if not buf:
                        break
                    out.write(buf)
                    h.update(buf)
                    total += len(buf)
            tmp_path.replace(dest)
            return {
                "url": url,
                "path": str(dest),
                "status": f"downloaded_http_{status_code}",
                "bytes": total,
                "sha256": h.hexdigest(),
            }
    except urllib.error.HTTPError as exc:
        return {"url": url, "path": str(dest), "status": f"http_error_{exc.code}", "bytes": 0, "sha256": None}
    except Exception as exc:  # noqa: BLE001
        return {"url": url, "path": str(dest), "status": f"error_{type(exc).__name__}: {exc}", "bytes": 0, "sha256": None}


def probe_url_status(url: str, timeout_sec: float = 30.0) -> Dict[str, Any]:
    """HTTP HEAD probe (e.g., to verify whether missing 20.zip exists on NASA S3)."""
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "OrbitCare-DEC001-Audit/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
            return {
                "url": url,
                "http_status": getattr(resp, "status", 200),
                "content_length": resp.headers.get("Content-Length"),
                "content_type": resp.headers.get("Content-Type"),
            }
    except urllib.error.HTTPError as exc:
        return {"url": url, "http_status": exc.code, "error": str(exc)}
    except Exception as exc:  # noqa: BLE001
        return {"url": url, "http_status": None, "error": f"{type(exc).__name__}: {exc}"}


# ---------------------------------------------------------------------------
# Streaming Single-CSV Audit
# ---------------------------------------------------------------------------
def audit_csv_stream(
    stream: io.TextIOBase,
    *,
    source_name: str,
    subject_id: Optional[int],
    session_type: str,
    chunksize: int = 65_536,
    max_gap_sec: float = 0.005,
) -> Dict[str, Any]:
    """
    Audit one NASA CSM CSV stream in constant memory.

    Checks:
        - Exact column schema match against description.txt (25 columns)
        - Total rows, NaN/Inf counts per column
        - TimeSecs continuity across chunk boundaries (dt <= 0, gaps > nominal + max_gap_sec)
        - Event code counts {0, 1, 2, 3, 4, 5, unexpected} and contiguous episode counts
        - GSR <= 0 zero-dropout rate, ECG/R/GSR rail saturation, EEG amplitude quantiles/range
        - Constant/flatline runs >= 1 second on EEG/ECG/R/GSR
    """
    reader = pd.read_csv(stream, chunksize=chunksize, low_memory=False)

    columns: Optional[List[str]] = None
    total_rows = 0
    nan_counts: Counter[str] = Counter()
    inf_counts: Counter[str] = Counter()
    event_counts: Counter[str] = Counter()
    episode_counts: Counter[str] = Counter()

    # Time continuity state across chunks
    first_time: Optional[float] = None
    last_time: Optional[float] = None
    prev_time: Optional[float] = None
    non_monotonic_steps = 0
    gap_steps = 0
    dt_samples: List[np.ndarray] = []
    dt_sample_cap = 200_000

    # Episode state machine across chunks
    prev_event: Optional[int] = None

    # Signal quality accumulators
    gsr_zero_or_neg = 0
    ecg_saturated = 0
    resp_saturated = 0
    gsr_saturated = 0
    flatline_counts: Counter[str] = Counter()

    # Running min/max/sum/sumsq for key channels
    tracked_stats_cols = ("EEG_FP1", "EEG_Cz", "EEG_O1", "ECG", "R", "GSR")
    col_min: Dict[str, float] = {}
    col_max: Dict[str, float] = {}
    col_sum: Dict[str, float] = {c: 0.0 for c in tracked_stats_cols}
    col_sumsq: Dict[str, float] = {c: 0.0 for c in tracked_stats_cols}
    col_n: Dict[str, int] = {c: 0 for c in tracked_stats_cols}

    # Flatline carry-over state per monitored channel
    monitored_flat_cols = ("EEG_FP1", "EEG_Cz", "ECG", "R", "GSR")
    flat_prev_val: Dict[str, Optional[float]] = {c: None for c in monitored_flat_cols}
    flat_run_len: Dict[str, int] = {c: 0 for c in monitored_flat_cols}
    min_flat_run = int(NOMINAL_FS_HZ)  # 1 second = 256 samples

    for chunk in reader:
        if columns is None:
            columns = [str(c).strip() for c in chunk.columns]
            chunk.columns = columns
        else:
            chunk.columns = columns

        n_chunk = len(chunk)
        if n_chunk == 0:
            continue
        total_rows += n_chunk

        # NaN / Inf per column
        for col in columns:
            vals = pd.to_numeric(chunk[col], errors="coerce").to_numpy(dtype=np.float64)
            n_nan = int(np.sum(np.isnan(vals)))
            n_inf = int(np.sum(np.isinf(vals)))
            if n_nan:
                nan_counts[col] += n_nan
            if n_inf:
                inf_counts[col] += n_inf

        # TimeSecs continuity
        if TIME_COLUMN in chunk.columns:
            t = pd.to_numeric(chunk[TIME_COLUMN], errors="coerce").to_numpy(dtype=np.float64)
            finite_t = t[np.isfinite(t)]
            if finite_t.size > 0:
                if first_time is None:
                    first_time = float(finite_t[0])
                last_time = float(finite_t[-1])

                if prev_time is not None:
                    dt_cross = finite_t[0] - prev_time
                    if dt_cross <= 0.0:
                        non_monotonic_steps += 1
                    elif dt_cross > NOMINAL_DT_SEC + max_gap_sec:
                        gap_steps += 1

                if finite_t.size > 1:
                    dt = np.diff(finite_t)
                    non_monotonic_steps += int(np.sum(dt <= 0.0))
                    gap_steps += int(np.sum(dt > NOMINAL_DT_SEC + max_gap_sec))
                    if sum(a.size for a in dt_samples) < dt_sample_cap:
                        dt_samples.append(dt[: max(0, dt_sample_cap - sum(a.size for a in dt_samples))])
                prev_time = float(finite_t[-1])

        # Event counts & contiguous episodes
        if EVENT_COLUMN in chunk.columns:
            ev_raw = pd.to_numeric(chunk[EVENT_COLUMN], errors="coerce")
            valid_ev = ev_raw.dropna().to_numpy(dtype=np.int64)
            if valid_ev.size > 0:
                uvals, ucnts = np.unique(valid_ev, return_counts=True)
                for uv, uc in zip(uvals.tolist(), ucnts.tolist()):
                    event_counts[str(uv)] += int(uc)

                # Episode transitions
                if prev_event is None or valid_ev[0] != prev_event:
                    episode_counts[str(int(valid_ev[0]))] += 1
                changes = np.where(valid_ev[1:] != valid_ev[:-1])[0] + 1
                for idx in changes.tolist():
                    episode_counts[str(int(valid_ev[idx]))] += 1
                prev_event = int(valid_ev[-1])

        # GSR zero-dropouts & hardware saturation
        if "GSR" in chunk.columns:
            gsr = pd.to_numeric(chunk["GSR"], errors="coerce").to_numpy(dtype=np.float64)
            gsr_fin = gsr[np.isfinite(gsr)]
            gsr_zero_or_neg += int(np.sum(gsr_fin <= GSR_DROPOUT_THRESHOLD))
            gsr_saturated += int(np.sum(np.abs(gsr_fin) >= RESP_GSR_RAIL_UV))

        if "ECG" in chunk.columns:
            ecg = pd.to_numeric(chunk["ECG"], errors="coerce").to_numpy(dtype=np.float64)
            ecg_fin = ecg[np.isfinite(ecg)]
            ecg_saturated += int(np.sum(np.abs(ecg_fin) >= ECG_RAIL_UV))

        if "R" in chunk.columns:
            resp = pd.to_numeric(chunk["R"], errors="coerce").to_numpy(dtype=np.float64)
            resp_fin = resp[np.isfinite(resp)]
            resp_saturated += int(np.sum(np.abs(resp_fin) >= RESP_GSR_RAIL_UV))

        # Running summary stats on representative channels
        for col in tracked_stats_cols:
            if col not in chunk.columns:
                continue
            arr = pd.to_numeric(chunk[col], errors="coerce").to_numpy(dtype=np.float64)
            arr = arr[np.isfinite(arr)]
            if arr.size == 0:
                continue
            cmin = float(np.min(arr))
            cmax = float(np.max(arr))
            col_min[col] = cmin if col not in col_min else min(col_min[col], cmin)
            col_max[col] = cmax if col not in col_max else max(col_max[col], cmax)
            col_sum[col] += float(np.sum(arr))
            col_sumsq[col] += float(np.sum(arr * arr))
            col_n[col] += int(arr.size)

        # Flatline runs (>= 256 identical consecutive samples)
        for col in monitored_flat_cols:
            if col not in chunk.columns:
                continue
            arr = pd.to_numeric(chunk[col], errors="coerce").to_numpy(dtype=np.float64)
            if arr.size == 0:
                continue
            # Vectorized flatline detection within chunk
            same = np.isfinite(arr[1:]) & np.isfinite(arr[:-1]) & (np.abs(arr[1:] - arr[:-1]) <= 1e-9)
            padded = np.concatenate(([False], same, [False]))
            starts = np.where(padded[1:] & ~padded[:-1])[0]
            ends = np.where(~padded[1:] & padded[:-1])[0]
            for s, e in zip(starts.tolist(), ends.tolist()):
                run = e - s + 1
                if run >= min_flat_run:
                    flatline_counts[col] += run

            # Handle constant chunk carry-over cleanly
            if flat_prev_val[col] is not None and np.isfinite(arr[0]) and abs(arr[0] - flat_prev_val[col]) <= 1e-9:
                flat_run_len[col] += 1
            else:
                flat_run_len[col] = 1
            flat_prev_val[col] = float(arr[-1]) if np.isfinite(arr[-1]) else None

    columns = columns or []
    missing_cols = [c for c in EXPECTED_COLUMNS if c not in columns]
    extra_cols = [c for c in columns if c not in EXPECTED_COLUMNS]

    dt_all = np.concatenate(dt_samples) if dt_samples else np.array([], dtype=np.float64)
    median_dt = float(np.median(dt_all)) if dt_all.size > 0 else None
    est_fs = (1.0 / median_dt) if (median_dt and median_dt > 0) else None

    # Map event counts to approved classes + stray 3/4 + unexpected
    class_rows = {cls: 0 for cls in TARGET_CLASSES}
    class_episodes = {cls: 0 for cls in TARGET_CLASSES}
    stray_3_4_rows = 0
    unexpected_event_rows = 0

    for code_str, cnt in event_counts.items():
        code = int(code_str)
        if code in RAW_EVENT_TO_CLASS:
            cls_name = RAW_EVENT_TO_CLASS[code]
            class_rows[cls_name] += cnt
            class_episodes[cls_name] += episode_counts.get(code_str, 0)
        elif code in STRAY_EVENT_CODES:
            stray_3_4_rows += cnt
        else:
            unexpected_event_rows += cnt

    channel_stats: Dict[str, Dict[str, Optional[float]]] = {}
    for col in tracked_stats_cols:
        n_c = col_n[col]
        if n_c > 0:
            mean_v = col_sum[col] / n_c
            var_v = max(0.0, (col_sumsq[col] / n_c) - mean_v * mean_v)
            channel_stats[col] = {
                "min": round(col_min[col], 4),
                "max": round(col_max[col], 4),
                "mean": round(mean_v, 4),
                "std": round(float(np.sqrt(var_v)), 4),
            }
        else:
            channel_stats[col] = {"min": None, "max": None, "mean": None, "std": None}

    crew_id = subject_to_crew_id(subject_id) if subject_id is not None else None
    seat = subject_to_seat(subject_id) if subject_id is not None else None
    duration_sec = (last_time - first_time) if (first_time is not None and last_time is not None) else None

    return {
        "source_name": source_name,
        "subject_id": subject_id,
        "crew_id": crew_id,
        "seat": seat,
        "session_type": session_type,
        "schema_exact_match": (len(missing_cols) == 0 and len(extra_cols) == 0),
        "missing_columns": missing_cols,
        "extra_columns": extra_cols,
        "total_rows": total_rows,
        "first_time_sec": round(first_time, 4) if first_time is not None else None,
        "last_time_sec": round(last_time, 4) if last_time is not None else None,
        "duration_sec": round(duration_sec, 2) if duration_sec is not None else None,
        "estimated_fs_hz": round(est_fs, 3) if est_fs is not None else None,
        "non_monotonic_time_steps": non_monotonic_steps,
        "time_gap_steps": gap_steps,
        "total_nan_cells": int(sum(nan_counts.values())),
        "total_inf_cells": int(sum(inf_counts.values())),
        "nan_by_column": dict(nan_counts),
        "gsr_zero_or_neg_rows": gsr_zero_or_neg,
        "gsr_zero_or_neg_pct": round(100.0 * gsr_zero_or_neg / max(1, total_rows), 3),
        "ecg_saturated_rows": ecg_saturated,
        "resp_saturated_rows": resp_saturated,
        "gsr_saturated_rows": gsr_saturated,
        "flatline_rows_by_channel": dict(flatline_counts),
        "raw_event_counts": dict(event_counts),
        "class_rows": class_rows,
        "class_episodes": class_episodes,
        "stray_3_4_rows": stray_3_4_rows,
        "unexpected_event_rows": unexpected_event_rows,
        "channel_stats": channel_stats,
    }


# ---------------------------------------------------------------------------
# Archive Discovery, Gate Evaluation & Report Rendering
# ---------------------------------------------------------------------------
def evaluate_stop_conditions(
    archive_records: Sequence[Dict[str, Any]],
    file_audits: Sequence[Dict[str, Any]],
) -> Dict[str, Any]:
    """Evaluate formal DEC-001 Stop Conditions from audited raw CSV statistics."""
    gates: Dict[str, Dict[str, Any]] = {}

    found_subjects = sorted({
        r["subject_id"] for r in file_audits if r.get("subject_id") is not None
    })
    found_crews = sorted({
        r["crew_id"] for r in file_audits if r.get("crew_id") is not None
    })

    # Gate 1: Archive access & file count
    if len(file_audits) == 0:
        gates["archive_access"] = {
            "status": "STOP",
            "detail": "Zero NASA CSM CSV files were audited.",
        }
    elif len(found_subjects) < len(PUBLISHED_SUBJECT_IDS):
        gates["archive_access"] = {
            "status": "REVIEW",
            "detail": (
                f"Audited {len(found_subjects)} subjects across {len(found_crews)} crews "
                f"(expected {len(PUBLISHED_SUBJECT_IDS)} published ZIPs; Subject 20 absent from NASA catalog)."
            ),
        }
    else:
        gates["archive_access"] = {
            "status": "PASS",
            "detail": f"Audited all {len(found_subjects)} published subjects ({len(found_crews)} crews).",
        }

    # Gate 2: Exact schema match
    bad_schema = [r["source_name"] for r in file_audits if not r["schema_exact_match"]]
    gates["schema_integrity"] = {
        "status": "PASS" if not bad_schema else "STOP",
        "detail": "All CSVs match the 25-column NASA description.txt schema."
        if not bad_schema
        else f"{len(bad_schema)} CSVs failed schema match: {bad_schema[:5]}",
    }

    # Gate 3: Stray Event codes 3/4 and unexpected event codes
    total_stray = sum(r["stray_3_4_rows"] for r in file_audits)
    total_unexpected = sum(r["unexpected_event_rows"] for r in file_audits)
    if total_unexpected > 0:
        gates["label_mapping"] = {
            "status": "STOP",
            "detail": f"Found {total_unexpected} rows with undocumented Event codes outside {{0,1,2,3,4,5}}.",
        }
    elif total_stray > 0:
        gates["label_mapping"] = {
            "status": "REVIEW",
            "detail": (
                f"Found {total_stray} rows with stray Event codes 3/4. "
                "Owner must decide whether to drop these windows (recommended) or collapse to Baseline."
            ),
        }
    else:
        gates["label_mapping"] = {
            "status": "PASS",
            "detail": "Zero stray (3/4) or unexpected Event codes across all audited CSVs.",
        }

    # Gate 4: LOFT 4-class coverage per crew
    loft_audits = [r for r in file_audits if r["session_type"] == "LOFT"]
    crews_with_4class_loft: List[int] = []
    for cid in found_crews:
        c_lofts = [r for r in loft_audits if r["crew_id"] == cid]
        totals = {cls: sum(r["class_rows"][cls] for r in c_lofts) for cls in TARGET_CLASSES}
        if all(totals[cls] > 0 for cls in TARGET_CLASSES):
            crews_with_4class_loft.append(cid)

    if len(crews_with_4class_loft) >= 5:
        gates["loft_4class_coverage"] = {
            "status": "PASS",
            "detail": (
                f"{len(crews_with_4class_loft)}/{len(found_crews)} crews have all 4 target classes "
                "labeled in LOFT (supports Outer Test Vault + Dev LOCO CV)."
            ),
        }
    elif len(crews_with_4class_loft) >= 2:
        gates["loft_4class_coverage"] = {
            "status": "REVIEW",
            "detail": (
                f"Only {len(crews_with_4class_loft)}/{len(found_crews)} crews have all 4 classes in LOFT. "
                "Outer test vault statistical power will be severely limited."
            ),
        }
    else:
        gates["loft_4class_coverage"] = {
            "status": "STOP",
            "detail": (
                f"Only {len(crews_with_4class_loft)}/{len(found_crews)} crews have 4-class LOFT labels. "
                "LOFT is unsuitable as a 4-class test set; activate Contingency Protocol C or revise scope."
            ),
        }

    # Overall verdict
    statuses = [g["status"] for g in gates.values()]
    if "STOP" in statuses:
        overall = "STOP_CONDITION_TRIGGERED"
    elif "REVIEW" in statuses:
        overall = "REVISE_OR_OWNER_REVIEW"
    else:
        overall = "READY_FOR_BENCHMARK_PHASE"

    return {
        "overall_gate_verdict": overall,
        "n_subjects_audited": len(found_subjects),
        "n_crews_audited": len(found_crews),
        "crews_with_4class_loft": crews_with_4class_loft,
        "gates": gates,
    }


def run_raw_audit(
    data_dir: Path,
    out_dir: Path,
    *,
    download: bool = False,
    check_missing_20: bool = False,
    subject_ids: Sequence[int] = PUBLISHED_SUBJECT_IDS,
    chunksize: int = 65_536,
    data_provenance: str = "real_nasa_csm_local",
) -> Dict[str, Any]:
    """Execute end-to-end raw ZIP / CSV audit and write manifest, JSON, CSV, and Markdown outputs."""
    data_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    download_log: List[Dict[str, Any]] = []
    missing_probes: List[Dict[str, Any]] = []

    if download:
        download_log.append(download_url(NASA_DESCRIPTION_URL, data_dir / "description.txt"))
        for sid in subject_ids:
            download_log.append(download_url(subject_zip_url(sid), data_dir / f"{sid}.zip"))

    if check_missing_20:
        for sid in MISSING_EXPECTED_SUBJECT_IDS:
            missing_probes.append(probe_url_status(subject_zip_url(sid)))

    archive_records: List[Dict[str, Any]] = []
    file_audits: List[Dict[str, Any]] = []
    input_format = "empty"

    # 1. Inspect all ZIP archives in data_dir
    for zip_path in sorted(data_dir.glob("*.zip")):
        input_format = "zip"
        m_sub = re.match(r"^(\d+)$", zip_path.stem)
        zip_subject_id = int(m_sub.group(1)) if m_sub else None
        rec: Dict[str, Any] = {
            "filename": zip_path.name,
            "subject_id": zip_subject_id,
            "bytes": zip_path.stat().st_size,
            "sha256": sha256_file(zip_path),
            "members": [],
            "error": None,
        }
        try:
            with zipfile.ZipFile(zip_path, "r") as zf:
                csv_members = [m for m in zf.namelist() if m.lower().endswith(".csv") and not m.startswith("__MACOSX")]
                rec["members"] = sorted(csv_members)
                for member in sorted(csv_members):
                    sid, sess = parse_csv_identity(member, fallback_subject_id=zip_subject_id)
                    with zf.open(member, "r") as raw_bin:
                        text_stream = io.TextIOWrapper(raw_bin, encoding="utf-8", errors="replace")
                        audit = audit_csv_stream(
                            text_stream,
                            source_name=f"{zip_path.name}:{member}",
                            subject_id=sid,
                            session_type=sess,
                            chunksize=chunksize,
                        )
                        file_audits.append(audit)
        except Exception as exc:  # noqa: BLE001
            rec["error"] = f"{type(exc).__name__}: {exc}"
        archive_records.append(rec)

    # 2. Also inspect standalone CSVs if user already unzipped archives directly in data_dir
    if not archive_records:
        for csv_path in sorted(data_dir.rglob("*.csv")):
            input_format = "csv"
            rel_name = str(csv_path.relative_to(data_dir)).replace("\\", "/")
            sid, sess = parse_csv_identity(csv_path.name)
            rec = {
                "filename": rel_name,
                "subject_id": sid,
                "bytes": csv_path.stat().st_size,
                "sha256": sha256_file(csv_path),
                "members": [rel_name],
                "error": None,
            }
            try:
                with csv_path.open("r", encoding="utf-8", errors="replace") as f:
                    audit = audit_csv_stream(
                        f,
                        source_name=rel_name,
                        subject_id=sid,
                        session_type=sess,
                        chunksize=chunksize,
                    )
                    file_audits.append(audit)
            except Exception as exc:  # noqa: BLE001
                rec["error"] = f"{type(exc).__name__}: {exc}"
            archive_records.append(rec)

    gate_summary = evaluate_stop_conditions(archive_records, file_audits)
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Machine-readable enforceable audit manifest required by run_benchmark.py
    audit_manifest: Dict[str, Any] = {
        "schema_version": AUDIT_MANIFEST_SCHEMA_VERSION,
        "generated_at_utc": generated_at,
        "data_provenance": data_provenance,
        "input_format": input_format,
        "input_archives": [
            {
                "filename": r["filename"],
                "subject_id": r["subject_id"],
                "bytes": r["bytes"],
                "sha256": r["sha256"],
                "csv_members": list(r["members"]),
                "error": r["error"],
            }
            for r in sorted(archive_records, key=lambda item: str(item["filename"]))
        ],
        "n_subjects_audited": gate_summary["n_subjects_audited"],
        "n_crews_audited": gate_summary["n_crews_audited"],
        "crews_with_4class_loft": list(gate_summary["crews_with_4class_loft"]),
        "gate_verdict": gate_summary["overall_gate_verdict"],
        "gates": gate_summary["gates"],
    }

    manifest_path = out_dir / AUDIT_MANIFEST_FILENAME
    manifest_path.write_text(json.dumps(audit_manifest, indent=2), encoding="utf-8")

    report = {
        "generated_at_utc": generated_at,
        "data_dir": str(data_dir),
        "data_provenance": data_provenance,
        "download_log": download_log,
        "missing_subject_probes": missing_probes,
        "archives": archive_records,
        "gate_summary": gate_summary,
        "audit_manifest": audit_manifest,
        "file_audits": file_audits,
    }

    # Write JSON report
    (out_dir / "audit_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")

    # Write flat CSV summary tables
    if file_audits:
        summary_rows = []
        class_rows = []
        for fa in file_audits:
            summary_rows.append({
                "source_name": fa["source_name"],
                "subject_id": fa["subject_id"],
                "crew_id": fa["crew_id"],
                "seat": fa["seat"],
                "session_type": fa["session_type"],
                "schema_exact_match": fa["schema_exact_match"],
                "total_rows": fa["total_rows"],
                "duration_sec": fa["duration_sec"],
                "estimated_fs_hz": fa["estimated_fs_hz"],
                "non_monotonic_time_steps": fa["non_monotonic_time_steps"],
                "time_gap_steps": fa["time_gap_steps"],
                "total_nan_cells": fa["total_nan_cells"],
                "total_inf_cells": fa["total_inf_cells"],
                "gsr_zero_or_neg_pct": fa["gsr_zero_or_neg_pct"],
                "ecg_saturated_rows": fa["ecg_saturated_rows"],
                "stray_3_4_rows": fa["stray_3_4_rows"],
                "unexpected_event_rows": fa["unexpected_event_rows"],
            })
            crow = {
                "source_name": fa["source_name"],
                "subject_id": fa["subject_id"],
                "crew_id": fa["crew_id"],
                "session_type": fa["session_type"],
                "stray_3_4_rows": fa["stray_3_4_rows"],
            }
            for cls in TARGET_CLASSES:
                crow[f"{cls}_rows"] = fa["class_rows"][cls]
                crow[f"{cls}_episodes"] = fa["class_episodes"][cls]
            class_rows.append(crow)

        pd.DataFrame(summary_rows).to_csv(out_dir / "audit_summary_files.csv", index=False)
        pd.DataFrame(class_rows).to_csv(out_dir / "audit_class_distribution.csv", index=False)

    # Write concise Markdown report
    md_lines = [
        "# DEC-001 Local Raw NASA CSM Data Audit Report",
        "",
        f"- **Generated (UTC):** {report['generated_at_utc']}",
        f"- **Data Directory:** `{data_dir}`",
        f"- **Overall Gate Verdict:** **`{gate_summary['overall_gate_verdict']}`**",
        f"- **Subjects Audited:** {gate_summary['n_subjects_audited']} | **Crews Audited:** {gate_summary['n_crews_audited']}",
        f"- **Crews with Complete 4-Class LOFT Labels:** {gate_summary['crews_with_4class_loft']}",
        "",
        "## Stop-Condition Gates",
        "",
        "| Gate | Status | Detail |",
        "|---|---|---|",
    ]
    for gname, gval in gate_summary["gates"].items():
        md_lines.append(f"| `{gname}` | **{gval['status']}** | {gval['detail']} |")

    if missing_probes:
        md_lines.extend(["", "## Missing Subject Probe (`20.zip`)", ""])
        for p in missing_probes:
            md_lines.append(f"- `{p.get('url')}` -> HTTP `{p.get('http_status')}` ({p.get('error', 'OK')})")

    md_lines.extend([
        "",
        "## Next Step",
        "",
        f"- Machine-readable manifest written to `{AUDIT_MANIFEST_FILENAME}`.",
        "- Review `audit_summary_files.csv` and `audit_class_distribution.csv`.",
        "- Only if all gates pass (`READY_FOR_BENCHMARK_PHASE`), run crew-grouped benchmarking via "
        f"`python -m csm.run_benchmark --data-dir {data_dir} --audit-manifest {out_dir / AUDIT_MANIFEST_FILENAME}`.",
    ])
    (out_dir / "audit_report.md").write_text("\n".join(md_lines) + "\n", encoding="utf-8")
    return report


def verify_audit_manifest(
    manifest_path: Path,
    data_dir: Path,
) -> Dict[str, Any]:
    """
    Enforce raw-data audit manifest integrity before any scientifically-valid
    benchmark execution on local real data.

    Raises AuditManifestError if:
        - manifest_path is missing or not valid JSON
        - schema_version, provenance, or required fields are invalid
        - gate_verdict is not 'READY_FOR_BENCHMARK_PHASE' (refuses REVIEW / STOP)
        - any required gate is missing or does not have status == 'PASS'
        - data_dir archive set or SHA-256 checksums do not match the manifest
    """
    if not manifest_path or not manifest_path.is_file():
        raise AuditManifestError(
            f"Audit manifest not found: {manifest_path}. Run `python -m csm.audit_raw_data` first."
        )

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        raise AuditManifestError(
            f"Audit manifest is malformed JSON ({manifest_path}): {type(exc).__name__}: {exc}"
        ) from exc

    if not isinstance(manifest, dict):
        raise AuditManifestError("Audit manifest root must be a JSON object.")

    if manifest.get("schema_version") != AUDIT_MANIFEST_SCHEMA_VERSION:
        raise AuditManifestError(
            f"Unsupported audit manifest schema_version: {manifest.get('schema_version')!r} "
            f"(expected {AUDIT_MANIFEST_SCHEMA_VERSION!r})."
        )

    if not isinstance(manifest.get("generated_at_utc"), str) or not manifest["generated_at_utc"].strip():
        raise AuditManifestError("Audit manifest missing valid 'generated_at_utc'.")

    provenance = manifest.get("data_provenance")
    if provenance != "real_nasa_csm_local":
        raise AuditManifestError(
            f"Audit manifest data_provenance must be 'real_nasa_csm_local' for scientifically valid "
            f"benchmarking, got {provenance!r}."
        )

    verdict = manifest.get("gate_verdict")
    if verdict != "READY_FOR_BENCHMARK_PHASE":
        raise AuditManifestError(
            f"Refusing scientifically-valid benchmark: audit manifest gate_verdict is {verdict!r} "
            "(must be 'READY_FOR_BENCHMARK_PHASE'; REVIEW and STOP verdicts are blocked)."
        )

    gates = manifest.get("gates")
    if not isinstance(gates, dict):
        raise AuditManifestError("Audit manifest missing 'gates' object.")

    for gate_name in REQUIRED_AUDIT_GATES:
        gate = gates.get(gate_name)
        if not isinstance(gate, dict) or gate.get("status") != "PASS":
            status = gate.get("status") if isinstance(gate, dict) else "MISSING"
            detail = gate.get("detail") if isinstance(gate, dict) else "Gate entry missing"
            raise AuditManifestError(
                f"Audit gate '{gate_name}' did not PASS (status={status!r}): {detail}"
            )

    input_archives = manifest.get("input_archives")
    if not isinstance(input_archives, list) or len(input_archives) == 0:
        raise AuditManifestError("Audit manifest must list at least one verified input archive.")

    if not data_dir.is_dir():
        raise AuditManifestError(f"Data directory does not exist: {data_dir}")

    input_format = manifest.get("input_format", "zip")
    if input_format not in ("zip", "csv"):
        raise AuditManifestError(f"Invalid audit manifest input_format: {input_format!r}")

    expected_checksums: Dict[str, str] = {}
    for entry in input_archives:
        if not isinstance(entry, dict):
            raise AuditManifestError("Audit manifest 'input_archives' contains a non-object entry.")
        fname = entry.get("filename")
        digest = entry.get("sha256")
        if not isinstance(fname, str) or not fname.strip():
            raise AuditManifestError("Audit manifest archive entry missing valid 'filename'.")
        if not isinstance(digest, str) or not _SHA256_RE.match(digest):
            raise AuditManifestError(f"Audit manifest archive '{fname}' has invalid SHA-256 digest.")
        if entry.get("error") is not None:
            raise AuditManifestError(f"Audit manifest archive '{fname}' recorded an audit error: {entry['error']}")
        expected_checksums[fname] = digest

    # Inspect actual files in data_dir and verify exact set + exact SHA-256 match
    if input_format == "zip":
        actual_files = {p.name: p for p in sorted(data_dir.glob("*.zip"))}
    else:
        actual_files = {
            str(p.relative_to(data_dir)).replace("\\", "/"): p
            for p in sorted(data_dir.rglob("*.csv"))
        }

    expected_names = set(expected_checksums.keys())
    actual_names = set(actual_files.keys())

    missing_files = sorted(expected_names - actual_names)
    if missing_files:
        raise AuditManifestError(
            f"Data directory is missing audited archive(s): {missing_files[:5]}"
        )

    extra_files = sorted(actual_names - expected_names)
    if extra_files:
        raise AuditManifestError(
            f"Data directory contains un-audited archive(s) not listed in manifest: {extra_files[:5]}"
        )

    for fname in sorted(expected_names):
        actual_digest = sha256_file(actual_files[fname])
        if actual_digest != expected_checksums[fname]:
            raise AuditManifestError(
                f"SHA-256 checksum mismatch for '{fname}': manifest={expected_checksums[fname]}, "
                f"actual={actual_digest}. Re-run `python -m csm.audit_raw_data`."
            )

    return {
        "manifest": manifest,
        "manifest_sha256": sha256_file(manifest_path),
        "verified_archive_count": len(expected_checksums),
        "verified_archive_checksums": expected_checksums,
    }


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="DEC-001 Stop-Condition #1 Raw NASA CSM Data Auditor")
    parser.add_argument("--data-dir", type=Path, required=True, help="Directory holding (or to download) NASA ZIP/CSV files")
    parser.add_argument("--out-dir", type=Path, default=Path("audit_outputs/nasa_csm"), help="Directory for audit outputs")
    parser.add_argument("--download", action="store_true", help="Download the 17 official NASA ZIP archives + description.txt")
    parser.add_argument("--check-missing-20", action="store_true", help="Probe HTTP status of missing 20.zip on data.nasa.gov")
    parser.add_argument("--chunksize", type=int, default=65_536, help="CSV streaming chunk size")
    args = parser.parse_args(argv)

    report = run_raw_audit(
        data_dir=args.data_dir,
        out_dir=args.out_dir,
        download=args.download,
        check_missing_20=args.check_missing_20,
        chunksize=args.chunksize,
    )
    verdict = report["gate_summary"]["overall_gate_verdict"]
    print(f"DEC-001 Raw Audit complete -> Verdict: {verdict}")
    print(f"Reports written to: {args.out_dir}")
    return 0 if verdict != "STOP_CONDITION_TRIGGERED" else 2


if __name__ == "__main__":
    raise SystemExit(main())
