"""
Mission Health System
=====================
Decision-support prototype (NOT a diagnostic tool):
  1. VitalSignsAnalyzer      -> rule-based threshold check (GREEN / YELLOW / RED)
  2. AstronautRAGAssistant   -> RAG over NASA medical docs (ChromaDB + Ollama)
  3. MissionHealthSystem     -> glues both together, returns a JSON-friendly dict

Requirements:
    pip install chromadb langchain-text-splitters langchain-ollama
    ollama pull llama3 && ollama pull nomic-embed-text
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
from dataclasses import dataclass, asdict
from typing import Optional

import chromadb
from langchain_ollama import OllamaEmbeddings, OllamaLLM
from langchain_text_splitters import RecursiveCharacterTextSplitter

logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
log = logging.getLogger("mission_health")


# ---------------------------------------------------------------------------
# 1. Vital signs analysis
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Range:
    low: float            # lower bound of the normal range
    high: float           # upper bound of the normal range
    crit_low: float       # below this -> RED immediately
    crit_high: float      # above this -> RED immediately
    unit: str = ""


@dataclass
class Alert:
    metric: str
    value: float
    direction: str        # "low" | "high"
    expected: str         # e.g. "50-100 bpm"
    critical: bool

    def __str__(self) -> str:
        level = "CRITICAL " if self.critical else ""
        return f"{level}{self.metric} is {self.direction} ({self.value}, expected {self.expected})"


class VitalSignsAnalyzer:
    """Threshold-based analysis. Thresholds are defaults: ideally they should be
    personalised per astronaut (baseline) and reviewed by a medical expert."""

    DEFAULT_THRESHOLDS = {
        "heart_rate":    Range(50, 100, 40, 130, "bpm"),
        "systolic_bp":   Range(90, 130, 80, 180, "mmHg"),
        "spo2":          Range(94, 100, 90, 100, "%"),
        "sleep_hours":   Range(6.0, 9.0, 3.0, 12.0, "h"),
        "radiation_msv": Range(0.0, 1.5, 0.0, 5.0, "mSv/day"),
    }

    def __init__(self, thresholds: Optional[dict[str, Range]] = None):
        self.thresholds = thresholds or self.DEFAULT_THRESHOLDS

    def evaluate_vitals(self, vitals: dict) -> dict:
        alerts: list[Alert] = []
        invalid: list[str] = []
        unknown: list[str] = []

        for metric, raw in vitals.items():
            rng = self.thresholds.get(metric)
            if rng is None:
                unknown.append(metric)
                continue

            # Validate the value (None / strings / NaN must not crash or pass silently)
            try:
                value = float(raw)
                if value != value:  # NaN check
                    raise ValueError
            except (TypeError, ValueError):
                invalid.append(metric)
                continue

            if value < rng.low:
                alerts.append(Alert(metric, value, "low",
                                    f"{rng.low}-{rng.high} {rng.unit}".strip(),
                                    critical=value < rng.crit_low))
            elif value > rng.high:
                alerts.append(Alert(metric, value, "high",
                                    f"{rng.low}-{rng.high} {rng.unit}".strip(),
                                    critical=value > rng.crit_high))

        missing = [m for m in self.thresholds if m not in vitals]

        # Status: any critical value OR 2+ abnormal values -> RED
        if any(a.critical for a in alerts) or len(alerts) >= 2:
            status = "RED"
        elif len(alerts) == 1:
            status = "YELLOW"
        else:
            status = "GREEN"

        return {
            "status": status,
            "alerts": [str(a) for a in alerts],
            "alerts_detail": [asdict(a) for a in alerts],
            "missing_metrics": missing,
            "invalid_metrics": invalid,
            "unknown_metrics": unknown,
            "raw_vitals": vitals,
        }


# ---------------------------------------------------------------------------
# 2. RAG medical assistant
# ---------------------------------------------------------------------------
class AstronautRAGAssistant:
    def __init__(
        self,
        docs_folder: str = r"C:\Users\LENOVO\Desktop\for final project\nasa data",
        db_path: str = "./nasa_chroma_db",
        llm_model: str = "llama3",
        embed_model: str = "nomic-embed-text",
        n_results: int = 4,
        max_distance: float = 1.2,      # drop weakly related chunks (tune on your data)
        history_turns: int = 3,
    ):
        self.docs_folder = docs_folder
        self.n_results = n_results
        self.max_distance = max_distance
        self.history_turns = history_turns
        self.chat_history: list[tuple[str, str]] = []

        self.embedding_fn = OllamaEmbeddings(model=embed_model)
        self.llm = OllamaLLM(model=llm_model, temperature=0.2)  # low temp = safer medical answers
        self.chroma_client = chromadb.PersistentClient(path=db_path)
        self.collection = self.chroma_client.get_or_create_collection(
            name="nasa_health_collection",
            metadata={"hnsw:space": "cosine"},
        )

        # Index new/changed files (not only when the DB is empty)
        self.ingest_documents()

    # ---- ingestion -------------------------------------------------------
    def ingest_documents(self) -> int:
        """Index .md/.txt files. Safe to call repeatedly: unchanged files are skipped,
        changed files are re-indexed."""
        if not os.path.isdir(self.docs_folder):
            os.makedirs(self.docs_folder, exist_ok=True)
            log.warning("Created %s. Add NASA medical .md/.txt files then re-run.", self.docs_folder)
            return 0

        splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
        total = 0

        for root, _, files in os.walk(self.docs_folder):
            for filename in sorted(files):
                if not filename.lower().endswith((".md", ".txt", ".csv")):
                    continue

                path = os.path.join(root, filename)
                rel = os.path.relpath(path, self.docs_folder)   # unique id even for same filename in subfolders

                try:
                    with open(path, "r", encoding="utf-8") as f:
                        text = f.read()
                except (OSError, UnicodeDecodeError) as e:
                    log.error("Skipping %s: %s", rel, e)
                    continue

                file_hash = hashlib.md5(text.encode("utf-8")).hexdigest()

                # Skip if this exact file version is already indexed
                existing = self.collection.get(where={"source": rel}, limit=1, include=["metadatas"])
                if existing["ids"] and existing["metadatas"][0].get("hash") == file_hash:
                    continue
                if existing["ids"]:
                    self.collection.delete(where={"source": rel})   # file changed -> drop old chunks

                chunks = [c for c in splitter.split_text(text) if c.strip()]
                if not chunks:
                    continue

                try:
                    embeddings = self.embedding_fn.embed_documents(chunks)
                except Exception as e:
                    log.error("Embedding failed for %s (is Ollama running?): %s", rel, e)
                    continue

                self.collection.upsert(
                    documents=chunks,
                    embeddings=embeddings,
                    ids=[f"{rel}::{i}" for i in range(len(chunks))],
                    metadatas=[{"source": rel, "chunk": i, "hash": file_hash} for i in range(len(chunks))],
                )
                total += len(chunks)
                log.info("Indexed %s (%d chunks)", rel, len(chunks))

        return total

    # ---- retrieval + generation -----------------------------------------
    def _retrieve(self, query: str) -> tuple[str, list[dict]]:
        count = self.collection.count()
        if count == 0:
            return "", []

        q_emb = self.embedding_fn.embed_query(query)
        res = self.collection.query(
            query_embeddings=[q_emb],
            n_results=min(self.n_results, count),
            include=["documents", "metadatas", "distances"],
        )

        docs, sources = [], []
        for doc, meta, dist in zip(res["documents"][0], res["metadatas"][0], res["distances"][0]):
            if dist <= self.max_distance:
                docs.append(doc)
                sources.append({"source": meta["source"], "chunk": meta["chunk"], "distance": round(dist, 3)})
        return "\n---\n".join(docs), sources

    def ask(self, query: str, use_history: bool = True) -> tuple[str, list[dict], bool]:
        """Returns (answer, sources, grounded). grounded=False means no relevant
        NASA document was found and the answer is from general model knowledge."""
        context, sources = self._retrieve(query)
        grounded = bool(context)
        if not grounded:
            context = "No relevant NASA protocol found in the local knowledge base."

        history_str = ""
        if use_history and self.chat_history:
            history_str = "\n".join(
                f"Astronaut: {q}\nFlight Surgeon AI: {a}"
                for q, a in self.chat_history[-self.history_turns:]
            )

        prompt = f"""You are an AI Flight Surgeon assisting an astronaut on a deep-space mission.
Give concise, actionable medical guidance (max ~150 words, numbered steps).
Rules:
- Base your answer ONLY on the NASA context below when it is relevant.
- If the context is missing or insufficient, say so clearly and give only general safe first steps.
- Never invent drug doses, protocol names or numbers that are not in the context.
- If the situation looks life-threatening, tell the astronaut to contact Mission Control / the crew medical officer immediately.
- This is decision support, not a diagnosis.

Conversation history:
{history_str or "(none)"}

NASA Context:
{context}

Astronaut Query / Alert:
{query}

Actionable Medical Guidance:"""

        response = self.llm.invoke(prompt).strip()
        if use_history:
            self.chat_history.append((query, response))
        return response, sources, grounded


# ---------------------------------------------------------------------------
# 3. Integrated system
# ---------------------------------------------------------------------------
class MissionHealthSystem:
    FALLBACK = {
        "YELLOW": "Minor deviation detected. Re-measure in 15-30 minutes and monitor closely.",
        "RED": "Multiple/critical abnormal vitals. Contact Mission Control / crew medical officer immediately.",
    }

    def __init__(self, analyzer: Optional[VitalSignsAnalyzer] = None,
                 assistant: Optional[AstronautRAGAssistant] = None):
        self.analyzer = analyzer or VitalSignsAnalyzer()
        self.assistant = assistant or AstronautRAGAssistant()

    def process_checkup(self, vitals: dict) -> dict:
        report = self.analyzer.evaluate_vitals(vitals)
        report["grounded"] = None

        if report["status"] == "GREEN":
            report["ai_recommendation"] = "All vital signs are within range. Maintain current mission routine."
            report["sources"] = []
            return report

        values = ", ".join(f"{k}={v}" for k, v in vitals.items())
        auto_query = (
            f"Astronaut alert ({report['status']}). Readings: {values}. "
            f"Abnormal: {'; '.join(report['alerts'])}. "
            "What immediate actions and follow-up checks are required?"
        )

        try:
            # use_history=False: automatic checkups must not pollute the chat memory
            guidance, sources, grounded = self.assistant.ask(auto_query, use_history=False)
            report.update(ai_recommendation=guidance, sources=sources, grounded=grounded)
        except Exception as e:  # Ollama down, model missing, etc. -> the system must still respond
            log.error("AI assistant failed: %s", e)
            report.update(
                ai_recommendation=self.FALLBACK[report["status"]],
                sources=[],
                grounded=False,
                ai_error=str(e),
            )
        return report


# ---------------------------------------------------------------------------
if __name__ == "__main__":
    system = MissionHealthSystem()

    # Define test scenarios to evaluate risk detection capabilities
    test_scenarios = [
        {
            "description": "🧪 Test Case 1: Optimal Normal Vitals (Expected Status: GREEN)",
            "vitals": {
                "heart_rate": 72,
                "systolic_bp": 118,
                "spo2": 99,
                "sleep_hours": 8.0,
                "radiation_msv": 0.1
            }
        },
        {
            "description": "⚠️ Test Case 2: Minor Warning - Low Sleep (Expected Status: YELLOW)",
            "vitals": {
                "heart_rate": 75,
                "systolic_bp": 120,
                "spo2": 97,
                "sleep_hours": 4.5,  # Below normal range
                "radiation_msv": 0.3
            }
        },
        {
            "description": "🚨 Test Case 3: High Risk - Elevated HR, BP & Radiation (Expected Status: RED)",
            "vitals": {
                "heart_rate": 130,  # Critical / High
                "systolic_bp": 155,  # High
                "spo2": 94,
                "sleep_hours": 5.0,
                "radiation_msv": 2.5   # High radiation
            }
        }
    ]

    for scenario in test_scenarios:
        print("\n" + "="*70)
        print(scenario["description"])
        print("="*70)
        
        result = system.process_checkup(scenario["vitals"])
        
        print(f"🔹 Detected Status: {result['status']}")
        print(f"🔹 Detected Alerts: {result['alerts'] if result['alerts'] else 'No alerts (All Good)'}")
        print(f"🔹 Grounded in NASA Docs: {result['grounded']}")
        print(f"\n💡 AI Flight Surgeon Guidance:\n{result['ai_recommendation']}")
        print("-" * 70)