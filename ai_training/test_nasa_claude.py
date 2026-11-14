"""
Run:  pytest -q
No Ollama / ChromaDB needed: the advisor is replaced by fakes.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from nasa_claude import (  # noqa: E402
    AstronautAdvisor,
    MissionHealthSystem,
    Settings,
    normalize_measurements,
)

CONTRACT_KEYS = {
    "schema_version", "status", "data_quality", "astronaut_id", "timestamp", "processed_at",
    "measurements", "alerts", "invalid", "missing", "warnings", "errors", "ai", "thresholds", "disclaimer",
}
AI_KEYS = {"available", "used_llm", "grounded", "text", "sources", "error"}

NORMAL = {"heart_rate": 72, "systolic_bp": 118, "spo2": 99, "sleep_hours": 8.0, "radiation_msv": 0.1}


class FakeAdvisor:
    """Stands in for the RAG + LLM part."""
    def __init__(self, grounded=True):
        self.grounded = grounded
        self.calls = 0

    def advise(self, status, alerts, measurements):
        self.calls += 1
        return {"available": True, "used_llm": True, "grounded": self.grounded,
                "text": "fake guidance", "sources": [{"source": "x.md", "chunk": 0, "distance": 0.1}],
                "error": None}


class FakeKB:
    def __init__(self, context="NASA context", sources=None):
        self.context, self.sources = context, sources or []

    def retrieve(self, query):
        return self.context, self.sources


class BrokenLLM:
    def invoke(self, prompt):
        raise ConnectionError("ollama is down")


class OkLLM:
    def invoke(self, prompt):
        return "1. do this"


@pytest.fixture
def system():
    return MissionHealthSystem(settings=Settings.from_env(), advisor=FakeAdvisor())


def check_contract(res):
    assert CONTRACT_KEYS <= set(res)
    assert AI_KEYS <= set(res["ai"])


# ---- status rules ----------------------------------------------------------
def test_normal_is_green_and_skips_llm(system):
    res = system.analyze({"measurements": NORMAL})
    check_contract(res)
    assert res["status"] == "GREEN" and res["data_quality"] == "complete"
    assert system.advisor.calls == 0


def test_single_abnormal_is_yellow(system):
    res = system.analyze({"measurements": {**NORMAL, "sleep_hours": 4.5}})
    assert res["status"] == "YELLOW"
    assert res["alerts"][0]["metric"] == "sleep_hours"
    assert system.advisor.calls == 1


def test_two_abnormal_is_red(system):
    res = system.analyze({"measurements": {**NORMAL, "heart_rate": 120, "systolic_bp": 150}})
    assert res["status"] == "RED"


def test_single_critical_is_red(system):
    res = system.analyze({"measurements": {**NORMAL, "spo2": 85}})
    assert res["status"] == "RED" and res["alerts"][0]["critical"] is True


# ---- missing / invalid data ------------------------------------------------
def test_empty_payload_is_insufficient_not_green(system):
    for payload in ({}, {"measurements": {}}):
        res = system.analyze(payload)
        check_contract(res)
        assert res["status"] == "INSUFFICIENT_DATA"


def test_all_null_values_are_insufficient(system):
    res = system.analyze({"measurements": {k: None for k in NORMAL}})
    assert res["status"] == "INSUFFICIENT_DATA" and res["data_quality"] == "none"


def test_missing_one_required_metric_is_not_green(system):
    data = dict(NORMAL)
    del data["sleep_hours"]
    res = system.analyze({"measurements": data})
    assert res["status"] == "INSUFFICIENT_DATA"
    assert res["missing"] == ["sleep_hours"]


@pytest.mark.parametrize("bad", ["abc", True, float("nan"), float("inf"), -5, 999, [1], {"a": 1}])
def test_invalid_values_never_pass_as_normal(system, bad):
    res = system.analyze({"measurements": {**NORMAL, "heart_rate": bad}})
    assert "heart_rate" in res["invalid"]
    assert res["status"] != "GREEN"


def test_abnormal_value_not_hidden_by_missing_data(system):
    res = system.analyze({"measurements": {"spo2": 85}})
    assert res["status"] == "RED"
    assert res["data_quality"] == "partial"
    assert any("partial data" in w for w in res["warnings"])


# ---- unified schema / aliases ----------------------------------------------
def test_backend_aliases_are_normalized(system):
    res = system.analyze({"measurements": {
        "HR": 70, "blood_pressure": "118/76", "oxygen_saturation": 98,
        "sleep": 7.5, "radiation": 0.2,
    }})
    assert res["status"] == "GREEN"
    assert res["measurements"]["spo2"] == 98
    assert res["measurements"]["systolic_bp"] == 118
    assert res["measurements"]["diastolic_bp"] == 76


@pytest.mark.parametrize("bp", ["120/80", {"systolic": 120, "diastolic": 80}, [120, 80]])
def test_blood_pressure_formats(bp):
    known, _, _ = normalize_measurements({"blood_pressure": bp})
    assert known["systolic_bp"] == 120 and known["diastolic_bp"] == 80


def test_unparseable_blood_pressure_warns():
    known, _, warnings = normalize_measurements({"blood_pressure": "high"})
    assert known["systolic_bp"] is None
    assert any("could not parse" in w for w in warnings)


def test_unknown_metric_is_reported_not_silently_green(system):
    res = system.analyze({"measurements": {"mood": 5}})
    assert res["status"] == "INSUFFICIENT_DATA"
    assert any("unknown measurements" in w for w in res["warnings"])


def test_flat_payload_and_vitals_key_are_accepted(system):
    assert system.analyze(NORMAL)["status"] == "GREEN"
    assert system.analyze({"vitals": NORMAL})["status"] == "GREEN"


def test_ids_are_echoed(system):
    res = system.analyze({"astronaut_id": "A1", "timestamp": "2026-11-14T10:00:00Z", "measurements": NORMAL})
    assert res["astronaut_id"] == "A1" and res["timestamp"] == "2026-11-14T10:00:00Z"


# ---- bad requests never crash ----------------------------------------------
@pytest.mark.parametrize("payload", [None, "text", 5, [1, 2], {"measurements": "oops"}])
def test_bad_payload_returns_error_contract(system, payload):
    res = system.analyze(payload)
    check_contract(res)
    assert res["status"] == "ERROR" and res["errors"]


# ---- Ollama failure / no NASA sources (real advisor, fake parts) ------------
def test_ollama_down_falls_back_and_keeps_status():
    advisor = AstronautAdvisor(FakeKB(), BrokenLLM(), Settings.from_env())
    system = MissionHealthSystem(settings=Settings.from_env(), advisor=advisor)
    res = system.analyze({"measurements": {**NORMAL, "heart_rate": 120, "systolic_bp": 150}})
    check_contract(res)
    assert res["status"] == "RED"                       # rules still decide
    assert res["ai"]["available"] is False
    assert res["ai"]["error"].startswith("LLM_UNAVAILABLE")
    assert "Mission Control" in res["ai"]["text"]       # safe fallback text


def test_knowledge_base_failure_falls_back():
    class BrokenKB:
        def retrieve(self, q):
            raise RuntimeError("chroma exploded")

    advisor = AstronautAdvisor(BrokenKB(), OkLLM(), Settings.from_env())
    system = MissionHealthSystem(settings=Settings.from_env(), advisor=advisor)
    res = system.analyze({"measurements": {**NORMAL, "sleep_hours": 4}})
    assert res["status"] == "YELLOW" and res["ai"]["available"] is False


def test_no_nasa_sources_is_flagged_ungrounded():
    advisor = AstronautAdvisor(FakeKB(context="", sources=[]), OkLLM(), Settings.from_env())
    system = MissionHealthSystem(settings=Settings.from_env(), advisor=advisor)
    res = system.analyze({"measurements": {**NORMAL, "sleep_hours": 4}})
    assert res["ai"]["available"] is True and res["ai"]["grounded"] is False
    assert any("no relevant NASA source" in w for w in res["warnings"])


def test_require_grounding_blocks_ai_text_without_sources():
    settings = Settings.from_env()
    settings.require_grounding = True
    advisor = AstronautAdvisor(FakeKB(context=""), OkLLM(), settings)
    system = MissionHealthSystem(settings=settings, advisor=advisor)
    res = system.analyze({"measurements": {**NORMAL, "sleep_hours": 4}})
    assert res["ai"]["used_llm"] is False and res["ai"]["error"] == "NO_NASA_SOURCE_FOUND"


def test_grounded_answer_returns_sources():
    advisor = AstronautAdvisor(FakeKB(context="ctx", sources=[{"source": "a.md", "chunk": 0, "distance": 0.2}]),
                               OkLLM(), Settings.from_env())
    system = MissionHealthSystem(settings=Settings.from_env(), advisor=advisor)
    res = system.analyze({"measurements": {**NORMAL, "sleep_hours": 4}})
    assert res["ai"]["grounded"] is True and res["ai"]["sources"][0]["source"] == "a.md"


# ---- thresholds config ------------------------------------------------------
def test_thresholds_are_flagged_unvalidated(system):
    res = system.analyze({"measurements": NORMAL})
    assert res["thresholds"]["validated"] is False
    assert any("not medically validated" in w for w in res["warnings"])
