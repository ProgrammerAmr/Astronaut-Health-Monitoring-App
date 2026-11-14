"""
Astronaut Health Monitoring - AI module (integration-ready)
===========================================================
Decision-support prototype. NOT a diagnostic tool.

Pipeline for one request:
    raw payload -> normalize_measurements() -> VitalSignsAnalyzer (rules decide the status)
                -> AstronautAdvisor (RAG + Ollama explains / suggests steps)
                -> fixed JSON contract (see build_response)

Key rules
  * The RULES decide GREEN/YELLOW/RED/INSUFFICIENT_DATA. The LLM never changes the status.
  * analyze() never raises: every failure becomes a valid JSON response.
  * No absolute paths: everything comes from env vars or is relative to this file.
  * Heavy dependencies (chromadb, langchain) are imported lazily, so the rule engine
    can be used and tested without them.

Usage
  python nasa_claude.py --stdin < request.json     # JSON in, JSON out (for child_process)
  python nasa_claude.py --demo                     # runs sample scenarios
  uvicorn ai_service:app --port 8001               # HTTP service (recommended for the backend)
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import math
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

BASE_DIR = Path(__file__).resolve().parent
SCHEMA_VERSION = "1.0"
COLLECTION_NAME = "nasa_health_collection"
DISCLAIMER = (
    "Decision-support prototype. Not a medical diagnosis and not a replacement for "
    "professional medical judgment."
)

log = logging.getLogger("mission_health")


def setup_logging(level: int = logging.INFO) -> None:
    """Logs go to stderr so stdout stays clean JSON for the backend."""
    logging.basicConfig(level=level, format="%(levelname)s | %(message)s", stream=sys.stderr)


# ---------------------------------------------------------------------------
# Settings (env vars, no hard-coded machine paths)
# ---------------------------------------------------------------------------
def _env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, default))
    except ValueError:
        return default


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, default))
    except ValueError:
        return default


def _env_path(name: str, default: Path) -> Path:
    value = os.getenv(name)
    return Path(value).expanduser() if value else default


@dataclass
class Settings:
    docs_dir: Path = BASE_DIR / "nasa_docs"
    db_path: Path = BASE_DIR / "chroma_db"
    thresholds_path: Path = BASE_DIR / "thresholds.json"
    llm_model: str = "llama3"
    embed_model: str = "nomic-embed-text"
    ollama_base_url: Optional[str] = None
    n_results: int = 4
    max_distance: float = 1.2        # cosine distance; weaker matches are dropped
    llm_timeout: float = 90.0        # seconds
    require_grounding: bool = False  # True -> no NASA source found = no AI text

    @classmethod
    def from_env(cls) -> "Settings":
        try:  # optional: load a local .env file if python-dotenv is installed
            from dotenv import load_dotenv
            load_dotenv(BASE_DIR / ".env")
        except ImportError:
            pass
        return cls(
            docs_dir=_env_path("NASA_DOCS_DIR", BASE_DIR / "nasa_docs"),
            db_path=_env_path("CHROMA_DB_PATH", BASE_DIR / "chroma_db"),
            thresholds_path=_env_path("THRESHOLDS_PATH", BASE_DIR / "thresholds.json"),
            llm_model=os.getenv("OLLAMA_LLM_MODEL", "llama3"),
            embed_model=os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text"),
            ollama_base_url=os.getenv("OLLAMA_BASE_URL") or None,
            n_results=_env_int("RAG_N_RESULTS", 4),
            max_distance=_env_float("RAG_MAX_DISTANCE", 1.2),
            llm_timeout=_env_float("LLM_TIMEOUT_SECONDS", 90.0),
            require_grounding=os.getenv("REQUIRE_GROUNDING", "").lower() in ("1", "true", "yes"),
        )


# ---------------------------------------------------------------------------
# Thresholds (loaded from JSON, validated at startup)
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Metric:
    name: str
    unit: str
    low: float
    high: float
    crit_low: Optional[float]
    crit_high: Optional[float]
    plausible_min: float
    plausible_max: float
    required: bool = True
    source: str = ""


@dataclass(frozen=True)
class ThresholdSet:
    version: str
    validated: bool
    metrics: dict


def load_thresholds(path: Path) -> ThresholdSet:
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(f"thresholds file not found: {path} (set THRESHOLDS_PATH)")
    data = json.loads(path.read_text(encoding="utf-8"))
    metrics: dict[str, Metric] = {}
    for name, cfg in data["metrics"].items():
        m = Metric(
            name=name,
            unit=cfg.get("unit", ""),
            low=float(cfg["low"]),
            high=float(cfg["high"]),
            crit_low=None if cfg.get("crit_low") is None else float(cfg["crit_low"]),
            crit_high=None if cfg.get("crit_high") is None else float(cfg["crit_high"]),
            plausible_min=float(cfg["plausible_min"]),
            plausible_max=float(cfg["plausible_max"]),
            required=bool(cfg.get("required", True)),
            source=str(cfg.get("source", "")),
        )
        if not (m.plausible_min <= m.low <= m.high <= m.plausible_max):
            raise ValueError(f"bad thresholds for '{name}': need plausible_min <= low <= high <= plausible_max")
        if m.crit_low is not None and m.crit_low > m.low:
            raise ValueError(f"bad thresholds for '{name}': crit_low must be <= low")
        if m.crit_high is not None and m.crit_high < m.high:
            raise ValueError(f"bad thresholds for '{name}': crit_high must be >= high")
        metrics[name] = m
    return ThresholdSet(str(data.get("version", "unknown")), bool(data.get("validated", False)), metrics)


# ---------------------------------------------------------------------------
# Unified measurement schema (aliases -> canonical names)
# Canonical names: heart_rate, systolic_bp, diastolic_bp, spo2, sleep_hours, radiation_msv
# ---------------------------------------------------------------------------
_ALIASES = {
    "heart_rate": ("heart_rate", "hr", "heartrate", "pulse", "pulse_rate"),
    "systolic_bp": ("systolic_bp", "systolic", "sbp", "bp_systolic", "systolic_blood_pressure"),
    "diastolic_bp": ("diastolic_bp", "diastolic", "dbp", "bp_diastolic", "diastolic_blood_pressure"),
    "spo2": ("spo2", "sp_o2", "oxygen_saturation", "o2_saturation", "blood_oxygen", "oxygen"),
    "sleep_hours": ("sleep_hours", "sleep", "sleep_duration", "sleep_duration_hours", "hours_of_sleep"),
    "radiation_msv": ("radiation_msv", "radiation", "radiation_dose", "radiation_dose_msv", "dose_msv"),
}
_ALIAS_LOOKUP = {alias: canon for canon, names in _ALIASES.items() for alias in names}
_BP_KEYS = ("blood_pressure", "bp")


def _canon(key: Any) -> str:
    return re.sub(r"[\s\-]+", "_", str(key).strip().lower())


def _first(mapping: dict, keys: tuple) -> Any:
    for k in keys:
        if k in mapping:
            return mapping[k]
    return None


def _parse_bp(value: Any) -> Optional[tuple]:
    """Accepts '120/80', {'systolic':120,'diastolic':80}, [120, 80]. Returns (sys, dia) or None."""
    try:
        if isinstance(value, str):
            m = re.fullmatch(r"\s*(\d{2,3}(?:\.\d+)?)\s*[/\\]\s*(\d{2,3}(?:\.\d+)?)\s*(?:mm\s*hg)?\s*", value, re.I)
            return (float(m.group(1)), float(m.group(2))) if m else None
        # في normalize_measurements
        put("systolic_bp", parsed[0], key)
        if parsed[1] is not None:  # ضيف الشرط ده
            put("diastolic_bp", parsed[1], key)
        if isinstance(value, dict):
            c = {_canon(k): v for k, v in value.items()}
            sys_v = _first(c, ("systolic", "sys", "sbp", "systolic_bp"))
            dia_v = _first(c, ("diastolic", "dia", "dbp", "diastolic_bp"))
            return None if sys_v is None and dia_v is None else (sys_v, dia_v)
        if isinstance(value, (list, tuple)) and len(value) == 2:
            return value[0], value[1]
    except Exception:  # noqa: BLE001 - any parsing problem simply means "unparseable"
        pass
    return None


def normalize_measurements(raw: dict) -> tuple:
    """Map backend field names to the canonical schema.
    Returns (known_measurements, unknown_keys, warnings)."""
    known: dict[str, Any] = {}
    unknown: list[str] = []
    warnings: list[str] = []

    def put(name: str, value: Any, original_key: Any) -> None:
        if name in known:
            if known[name] != value:
                warnings.append(f"conflicting values for '{name}': kept the first, ignored '{original_key}'")
            return
        known[name] = value

    for key, value in raw.items():
        canon = _canon(key)
        if canon in _BP_KEYS:
            parsed = _parse_bp(value)
            if parsed is None:
                warnings.append(f"could not parse '{key}' (expected '120/80' or {{systolic, diastolic}})")
                put("systolic_bp", None, key)
            else:
                put("systolic_bp", parsed[0], key)
                if parsed[1] is not None:
                    put("diastolic_bp", parsed[1], key)
            continue
        name = _ALIAS_LOOKUP.get(canon)
        if name is None:
            unknown.append(str(key))
            continue
        put(name, value, key)

    if unknown:
        warnings.append("unknown measurements ignored: " + ", ".join(unknown))
    return known, unknown, warnings


# ---------------------------------------------------------------------------
# Rule engine
# ---------------------------------------------------------------------------
def _to_number(raw: Any, m: Metric) -> tuple:
    """Returns (value, None) or (None, reason)."""
    if raw is None:
        return None, "no value (null)"
    if isinstance(raw, bool):
        return None, "boolean is not a valid measurement"
    if isinstance(raw, str):
        try:
            value = float(raw.strip().replace(",", "."))
        except ValueError:
            return None, f"not a number: {raw!r}"
    elif isinstance(raw, (int, float)):
        value = float(raw)
    else:
        return None, f"unsupported type: {type(raw).__name__}"
    if not math.isfinite(value):
        return None, "not a finite number"
    if not (m.plausible_min <= value <= m.plausible_max):
        return None, (f"{value:g} is outside the plausible range "
                      f"{m.plausible_min:g}-{m.plausible_max:g} {m.unit}; likely a sensor or entry error")
    return value, None


class VitalSignsAnalyzer:
    """Status rules:
        any critical value, or 2+ abnormal values -> RED
        exactly 1 abnormal value                  -> YELLOW
        no abnormal values but missing/invalid    -> INSUFFICIENT_DATA   (never GREEN)
        all required present, valid and normal    -> GREEN
    Abnormal values are never hidden by missing/invalid data elsewhere."""

    def __init__(self, thresholds: ThresholdSet):
        self.thresholds = thresholds

    @staticmethod
    def _check(m: Metric, value: float) -> Optional[dict]:
        if value < m.low:
            direction = "low"
            critical = m.crit_low is not None and value < m.crit_low
        elif value > m.high:
            direction = "high"
            critical = m.crit_high is not None and value > m.crit_high
        else:
            return None
        expected = f"{m.low:g}-{m.high:g} {m.unit}".strip()
        prefix = "CRITICAL: " if critical else ""
        return {
            "metric": m.name,
            "value": value,
            "unit": m.unit,
            "direction": direction,
            "expected": expected,
            "critical": critical,
            "message": f"{prefix}{m.name} is {direction} ({value:g} {m.unit}, expected {expected})".replace(" )", ")"),
        }

    def evaluate(self, measurements: dict) -> dict:
        alerts, invalid, missing, valid = [], {}, [], {}
        for name, m in self.thresholds.metrics.items():
            if name not in measurements:
                if m.required:
                    missing.append(name)
                continue
            value, reason = _to_number(measurements[name], m)
            if reason:
                invalid[name] = reason
                continue
            valid[name] = value
            alert = self._check(m, value)
            if alert:
                alerts.append(alert)

        if any(a["critical"] for a in alerts) or len(alerts) >= 2:
            status = "RED"
        elif len(alerts) == 1:
            status = "YELLOW"
        elif invalid or missing or not valid:
            status = "INSUFFICIENT_DATA"
        else:
            status = "GREEN"

        if not valid:
            quality = "none"
        elif invalid or missing:
            quality = "partial"
        else:
            quality = "complete"
        return {"status": status, "data_quality": quality, "alerts": alerts,
                "invalid": invalid, "missing": missing, "valid": valid}


# ---------------------------------------------------------------------------
# Knowledge base (ChromaDB + Ollama embeddings)
# ---------------------------------------------------------------------------
class KnowledgeBase:
    SUPPORTED = (".md", ".txt")

    def __init__(self, settings: Settings, embeddings: Any = None):
        self.s = settings
        self._embeddings = embeddings
        self._client = None
        self._collection = None

    # -- lazy connections (nothing heavy happens in __init__) ---------------
    def _get_embeddings(self):
        if self._embeddings is None:
            from langchain_ollama import OllamaEmbeddings
            kwargs: dict[str, Any] = {"model": self.s.embed_model}
            if self.s.ollama_base_url:
                kwargs["base_url"] = self.s.ollama_base_url
            self._embeddings = OllamaEmbeddings(**kwargs)
        return self._embeddings

    def _get_collection(self):
        if self._collection is None:
            import chromadb
            self.s.db_path.mkdir(parents=True, exist_ok=True)
            self._client = chromadb.PersistentClient(path=str(self.s.db_path))
            col = self._client.get_or_create_collection(
                name=COLLECTION_NAME,
                metadata={"hnsw:space": "cosine", "embed_model": self.s.embed_model},
            )
            stored = (col.metadata or {}).get("embed_model")
            if stored and stored != self.s.embed_model:
                raise RuntimeError(
                    f"index was built with embedding model '{stored}' but '{self.s.embed_model}' is configured; "
                    "run: python ingest.py --rebuild"
                )
            self._collection = col
        return self._collection

    def count(self) -> int:
        return self._get_collection().count()

    # -- ingestion ----------------------------------------------------------
    def _embed(self, chunks: list, label: str) -> list:
        embeddings: list = []
        batch = 32  # small batches avoid Ollama overload / long silent waits
        for i in range(0, len(chunks), batch):
            log.info("Embedding %s: %d/%d chunks", label, min(i + batch, len(chunks)), len(chunks))
            embeddings.extend(self._get_embeddings().embed_documents(chunks[i:i + batch]))
        return embeddings

    def ingest(self, rebuild: bool = False, prune: bool = True) -> dict:
        """Index .md/.txt files. Safe to run repeatedly:
        unchanged files are skipped, changed files re-indexed, deleted files pruned.
        Old chunks are only removed AFTER the new embeddings succeeded."""
        docs_dir = self.s.docs_dir
        if not docs_dir.is_dir():
            raise FileNotFoundError(f"docs folder not found: {docs_dir} (set NASA_DOCS_DIR)")

        if rebuild:
            self._get_collection()
            self._client.delete_collection(COLLECTION_NAME)
            self._collection = None
        col = self._get_collection()

        from langchain_text_splitters import RecursiveCharacterTextSplitter
        splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)

        stats = {"files": 0, "indexed": 0, "skipped": 0, "failed": 0, "chunks": 0, "pruned": 0}
        seen: set = set()

        for path in sorted(docs_dir.rglob("*")):
            if not path.is_file() or path.suffix.lower() not in self.SUPPORTED:
                continue
            rel = path.relative_to(docs_dir).as_posix()  # unique id even across sub-folders
            seen.add(rel)
            stats["files"] += 1
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError) as e:
                log.error("Skipping %s: %s", rel, e)
                stats["failed"] += 1
                continue

            digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
            existing = col.get(where={"source": rel}, limit=1, include=["metadatas"])
            if existing["ids"] and (existing["metadatas"][0] or {}).get("hash") == digest:
                stats["skipped"] += 1
                continue

            chunks = [c for c in splitter.split_text(text) if c.strip()]
            if not chunks:
                continue
            try:
                embeddings = self._embed(chunks, rel)
            except Exception as e:  # noqa: BLE001
                log.error("Embedding failed for %s (is Ollama running?): %s", rel, e)
                stats["failed"] += 1
                continue

            if existing["ids"]:
                col.delete(where={"source": rel})
            for i in range(0, len(chunks), 100):
                part = range(i, min(i + 100, len(chunks)))
                col.upsert(
                    documents=[chunks[j] for j in part],
                    embeddings=[embeddings[j] for j in part],
                    ids=[f"{rel}::{j}" for j in part],
                    metadatas=[{"source": rel, "chunk": j, "hash": digest} for j in part],
                )
            stats["indexed"] += 1
            stats["chunks"] += len(chunks)
            log.info("Indexed %s (%d chunks)", rel, len(chunks))

        if prune and seen:
            stored = col.get(include=["metadatas"])
            stale = {m["source"] for m in stored["metadatas"] if m and m.get("source") not in seen}
            for source in stale:
                col.delete(where={"source": source})
            stats["pruned"] = len(stale)
        return stats

    # -- retrieval ----------------------------------------------------------
    def retrieve(self, query: str) -> tuple:
        """Returns (context_text, sources). Empty when nothing relevant is found."""
        col = self._get_collection()
        total = col.count()
        if total == 0:
            return "", []
        q_emb = self._get_embeddings().embed_query(query)
        res = col.query(
            query_embeddings=[q_emb],
            n_results=min(self.s.n_results, total),
            include=["documents", "metadatas", "distances"],
        )
        docs, sources = [], []
        for doc, meta, dist in zip(res["documents"][0], res["metadatas"][0], res["distances"][0]):
            if dist <= self.s.max_distance:
                docs.append(doc)
                sources.append({"source": meta["source"], "chunk": meta["chunk"], "distance": round(dist, 3)})
        return "\n---\n".join(docs), sources


# ---------------------------------------------------------------------------
# AI advisor (LLM explains; it never decides the status)
# ---------------------------------------------------------------------------
class OllamaTextModel:
    def __init__(self, settings: Settings):
        self.s = settings
        self._llm = None

    def invoke(self, prompt: str) -> str:
        if self._llm is None:
            from langchain_ollama import OllamaLLM
            kwargs: dict[str, Any] = {"model": self.s.llm_model, "temperature": 0.1}
            if self.s.ollama_base_url:
                kwargs["base_url"] = self.s.ollama_base_url
            self._llm = OllamaLLM(**kwargs)
        return str(self._llm.invoke(prompt))


FALLBACK_TEXT = {
    "GREEN": "All monitored vital signs are within the configured ranges. Maintain the current mission routine.",
    "YELLOW": ("One measurement is outside its normal range. Re-measure in 15-30 minutes, rest, and keep "
               "monitoring. Report to the crew medical officer if it persists or worsens."),
    "RED": "Multiple or critical abnormal measurements. Contact Mission Control / the crew medical officer immediately.",
    "INSUFFICIENT_DATA": ("Not enough valid data to confirm the astronaut's status. Re-take the missing or "
                          "invalid measurements before relying on this result."),
    "ERROR": "The request could not be analysed.",
}


def _ai_block(*, available: bool, used_llm: bool, grounded: bool, text: str,
              sources: Optional[list] = None, error: Optional[str] = None) -> dict:
    return {"available": available, "used_llm": used_llm, "grounded": grounded,
            "text": text, "sources": sources or [], "error": error}


class AstronautAdvisor:
    def __init__(self, kb: Any, llm: Any, settings: Settings):
        self.kb = kb
        self.llm = llm
        self.s = settings
        self._pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix="llm")

    @staticmethod
    def _build_prompt(status: str, measurements: dict, alerts: list, context: str, history_free_query: str) -> str:
        values = ", ".join(f"{k}={v:g}" for k, v in measurements.items())
        abnormal = "; ".join(a["message"] for a in alerts) or "none"
        return f"""You are an AI Flight Surgeon assistant on a deep-space mission (decision support, not a diagnosis).
The rule-based monitor has ALREADY determined the status: {status}. Do not change or contradict it.

Answer using exactly these sections:
1. CLINICAL ASSESSMENT: what the abnormal values may indicate, in 1-3 sentences.
2. ACTION STEPS: 3 to 5 short numbered steps.
3. MISSION CONTROL: say clearly whether to contact Mission Control / the crew medical officer now.

Rules:
- Base the answer ONLY on the NASA context below when it is relevant.
- If the context is missing or insufficient, say so and give only general, safe first steps.
- Never invent drug doses, protocol names or numbers that are not in the context.
- Maximum ~150 words.

NASA Context:
{context or "No relevant NASA document found."}

Measurements: {values}
Abnormal: {abnormal}
Request: {history_free_query}

Response:"""

    def advise(self, status: str, alerts: list, measurements: dict) -> dict:
        query = (f"Astronaut health alert ({status}). Abnormal: "
                 f"{'; '.join(a['message'] for a in alerts)}. "
                 "What immediate actions and follow-up checks are required?")
        try:
            context, sources = self.kb.retrieve(query)
            grounded = bool(context)
            if not grounded and self.s.require_grounding:
                return _ai_block(available=False, used_llm=False, grounded=False,
                                 text=FALLBACK_TEXT[status], error="NO_NASA_SOURCE_FOUND")
            prompt = self._build_prompt(status, measurements, alerts, context, query)
            future = self._pool.submit(self.llm.invoke, prompt)
            text = str(future.result(timeout=self.s.llm_timeout)).strip()
            if not text:
                raise ValueError("empty LLM response")
            return _ai_block(available=True, used_llm=True, grounded=grounded, text=text, sources=sources)
        except Exception as e:  # noqa: BLE001 - Ollama down, timeout, DB error, ...
            log.error("AI guidance failed: %s: %s", type(e).__name__, e)
            return _ai_block(available=False, used_llm=False, grounded=False,
                             text=FALLBACK_TEXT[status], error=f"LLM_UNAVAILABLE ({type(e).__name__})")


# ---------------------------------------------------------------------------
# Response contract + system
# ---------------------------------------------------------------------------
def build_response(*, status: str, data_quality: str = "none", measurements: Optional[dict] = None,
                   alerts: Optional[list] = None, invalid: Optional[dict] = None,
                   missing: Optional[list] = None, warnings: Optional[list] = None,
                   errors: Optional[list] = None, ai: Optional[dict] = None,
                   thresholds: Optional[dict] = None, astronaut_id: Any = None,
                   timestamp: Any = None) -> dict:
    """The ONE response shape. Every key is always present."""
    return {
        "schema_version": SCHEMA_VERSION,
        "status": status,                      # GREEN | YELLOW | RED | INSUFFICIENT_DATA | ERROR
        "data_quality": data_quality,          # complete | partial | none
        "astronaut_id": astronaut_id,
        "timestamp": timestamp,
        "processed_at": datetime.now(timezone.utc).isoformat(),
        "measurements": measurements or {},    # normalized + validated values actually used
        "alerts": alerts or [],
        "invalid": invalid or {},              # {metric: reason}
        "missing": missing or [],              # required metrics not sent
        "warnings": warnings or [],
        "errors": errors or [],                # [{code, message}] fatal problems only
        "ai": ai or _ai_block(available=False, used_llm=False, grounded=False, text=""),
        "thresholds": thresholds or {"version": None, "validated": False},
        "disclaimer": DISCLAIMER,
    }


def error_response(code: str, message: str) -> dict:
    return build_response(status="ERROR", errors=[{"code": code, "message": message}],
                          ai=_ai_block(available=False, used_llm=False, grounded=False,
                                       text=FALLBACK_TEXT["ERROR"]))


class MissionHealthSystem:
    def __init__(self, settings: Optional[Settings] = None, thresholds: Optional[ThresholdSet] = None,
                 advisor: Any = None):
        self.settings = settings or Settings.from_env()
        self.thresholds = thresholds or load_thresholds(self.settings.thresholds_path)  # fail fast
        self.analyzer = VitalSignsAnalyzer(self.thresholds)
        self.kb = KnowledgeBase(self.settings)
        self.advisor = advisor or AstronautAdvisor(self.kb, OllamaTextModel(self.settings), self.settings)

    def _threshold_info(self) -> dict:
        return {"version": self.thresholds.version, "validated": self.thresholds.validated}

    def analyze(self, payload: Any) -> dict:
        """Never raises. Accepts {"astronaut_id":..., "timestamp":..., "measurements": {...}}
        (also "vitals", or a flat dict of measurements)."""
        try:
            return self._analyze(payload)
        except Exception as e:  # noqa: BLE001
            log.exception("unexpected failure while analysing")
            return error_response("INTERNAL_ERROR", f"{type(e).__name__}: {e}")

    def _analyze(self, payload: Any) -> dict:
        if not isinstance(payload, dict):
            return error_response("INVALID_INPUT", "payload must be a JSON object")

        astronaut_id = payload.get("astronaut_id")
        timestamp = payload.get("timestamp")
        raw = payload.get("measurements", payload.get("vitals"))
        if raw is None:
            raw = {k: v for k, v in payload.items() if k not in ("astronaut_id", "timestamp")}
        if not isinstance(raw, dict):
            return error_response("INVALID_INPUT", "'measurements' must be an object")

        known, _unknown, warnings = normalize_measurements(raw)
        result = self.analyzer.evaluate(known)
        status = result["status"]

        if result["missing"]:
            warnings.append("missing required measurements: " + ", ".join(result["missing"]))
        for name, reason in result["invalid"].items():
            warnings.append(f"invalid '{name}': {reason}")
        if status in ("YELLOW", "RED") and result["data_quality"] != "complete":
            warnings.append("status is based on partial data; re-take the missing/invalid measurements")
        if not self.thresholds.validated:
            warnings.append("thresholds are not medically validated (prototype values)")

        if status in ("GREEN", "INSUFFICIENT_DATA"):
            ai = _ai_block(available=True, used_llm=False, grounded=False, text=FALLBACK_TEXT[status])
        else:
            ai = self.advisor.advise(status, result["alerts"], result["valid"])
            if ai["error"]:
                warnings.append("AI guidance unavailable; showing rule-based fallback text")
            elif not ai["grounded"]:
                warnings.append("no relevant NASA source found; AI text is general guidance (grounded=false)")

        return build_response(
            status=status, data_quality=result["data_quality"], measurements=result["valid"],
            alerts=result["alerts"], invalid=result["invalid"], missing=result["missing"],
            warnings=warnings, ai=ai, thresholds=self._threshold_info(),
            astronaut_id=astronaut_id, timestamp=timestamp,
        )

    def health(self) -> dict:
        info: dict[str, Any] = {"thresholds": self._threshold_info(), "docs_indexed_chunks": None, "error": None}
        try:
            info["docs_indexed_chunks"] = self.kb.count()
        except Exception as e:  # noqa: BLE001
            info["error"] = f"{type(e).__name__}: {e}"
        return info


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
DEMO_SCENARIOS = [
    ("Normal vitals (expect GREEN)",
     {"heart_rate": 72, "systolic_bp": 118, "spo2": 99, "sleep_hours": 8.0, "radiation_msv": 0.1}),
    ("Low sleep only (expect YELLOW)",
     {"heart_rate": 75, "systolic_bp": 120, "spo2": 97, "sleep_hours": 4.5, "radiation_msv": 0.3}),
    ("Elevated HR/BP + radiation (expect RED)",
     {"heart_rate": 125, "systolic_bp": 155, "spo2": 96, "sleep_hours": 5.0, "radiation_msv": 2.5}),
    ("Backend field names (oxygen_saturation + blood_pressure)",
     {"heart_rate": 70, "blood_pressure": "118/76", "oxygen_saturation": 98, "sleep_hours": 7.5, "radiation_msv": 0.2}),
    ("Missing / invalid data (expect INSUFFICIENT_DATA)",
     {"heart_rate": "abc", "spo2": None}),
]


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(description="Astronaut health AI module")
    parser.add_argument("--stdin", action="store_true", help="read one JSON request from stdin, print JSON")
    parser.add_argument("--demo", action="store_true", help="run sample scenarios")
    parser.add_argument("--health", action="store_true", help="print service health as JSON")
    args = parser.parse_args(argv)
    setup_logging()

    try:
        system = MissionHealthSystem()
    except Exception as e:  # noqa: BLE001 - e.g. thresholds file missing
        print(json.dumps(error_response("CONFIG_ERROR", f"{type(e).__name__}: {e}")))
        return 2

    if args.stdin:
        try:
            payload = json.loads(sys.stdin.read())
        except json.JSONDecodeError as e:
            print(json.dumps(error_response("INVALID_JSON", str(e))))
            return 0
        print(json.dumps(system.analyze(payload), ensure_ascii=True))
        return 0
    if args.health:
        print(json.dumps(system.health(), ensure_ascii=True))
        return 0
    if args.demo:
        for title, vitals in DEMO_SCENARIOS:
            res = system.analyze({"measurements": vitals})
            print("=" * 70)
            print(title)
            print("status:", res["status"], "| data_quality:", res["data_quality"])
            print("alerts:", [a["message"] for a in res["alerts"]] or "none")
            print("warnings:", res["warnings"] or "none")
            print("grounded:", res["ai"]["grounded"], "| ai_error:", res["ai"]["error"])
            print("AI text:", res["ai"]["text"])
        return 0

    parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
