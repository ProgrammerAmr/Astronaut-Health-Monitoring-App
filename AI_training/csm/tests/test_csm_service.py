"""
FastAPI integration tests for DEC-001 CSM service mounted on `AI_training/ai_service.py`.

Verifies:
    1. Existing `/health` and `/analyze` routes remain backward-compatible.
    2. `GET /csm/status` returns availability & fixed limitations without model-health claims.
    3. `POST /csm/analyze` returns INSUFFICIENT_DATA when no model artifact exists,
       when SQI is low/missing, or when synthetic input is passed to research_replay.
    4. `mode="synthetic_demo"` never invents probabilities and tags `data_provenance="synthetic"`,
       `demo_mode=True`, clear warnings, and `model_status.validated=False`.
    5. `live_sensor`, raw physiological signal fields, unknown fields, and oversized payloads
       are strictly rejected without persistence.
"""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient

AI_TRAINING_DIR = Path(__file__).resolve().parents[2]
if str(AI_TRAINING_DIR) not in sys.path:
    sys.path.insert(0, str(AI_TRAINING_DIR))

import ai_service  # noqa: E402


@pytest.fixture()
def client(monkeypatch: pytest.MonkeyPatch) -> TestClient:
    # Stub MissionHealthSystem so /health and /analyze tests don't require ChromaDB/Ollama
    fake_system = MagicMock()
    fake_system.health.return_value = {"thresholds_validated": False, "indexed_chunks": 0}
    fake_system.analyze.return_value = {
        "schema_version": "1.0",
        "status": "GREEN",
        "astronaut_id": "astro-1",
        "disclaimer": "non-diagnostic",
    }
    monkeypatch.setattr(ai_service, "get_system", lambda: fake_system)
    monkeypatch.delenv("CSM_MODEL_ARTIFACT_PATH", raising=False)
    monkeypatch.delenv("CSM_VALIDATION_ARTIFACT_PATH", raising=False)
    return TestClient(ai_service.app)


def test_existing_health_and_analyze_remain_backward_compatible(client: TestClient):
    r_health = client.get("/health")
    assert r_health.status_code == 200
    body_h = r_health.json()
    assert body_h["ok"] is True
    assert body_h["thresholds_validated"] is False

    r_analyze = client.post(
        "/analyze",
        json={"astronaut_id": "astro-1", "measurements": {"heart_rate": 72}},
    )
    assert r_analyze.status_code == 200
    assert r_analyze.json()["status"] == "GREEN"


def test_csm_status_reports_availability_and_limitations(client: TestClient):
    resp = client.get("/csm/status")
    assert resp.status_code == 200
    data = resp.json()
    assert data["api_version"] == "v1"
    assert data["service_available"] is True
    assert data["registered_model_available"] is False
    assert data["model_status"]["validated"] is False
    assert data["live_sensor_enabled"] is False
    assert data["raw_signal_persistence"] is False
    assert "synthetic_demo" in data["supported_modes"]
    assert "research_replay" in data["supported_modes"]
    assert "not a medical diagnosis" in data["disclaimer"].lower()


def test_csm_research_replay_abstains_safely_when_no_model_or_bad_sqi(client: TestClient):
    # 1. Valid SQI, real replay provenance -> abstains because no trained model artifact exists
    r1 = client.post(
        "/csm/analyze",
        json={
            "mode": "research_replay",
            "astronaut_id": "user-123",
            "session_id": "5_Loft",
            "window_end_sec": 120.0,
            "data_provenance": "real_nasa_csm_replay",
            "signal_quality": {"valid": True, "sqi_score": 0.95, "reasons": []},
        },
    )
    assert r1.status_code == 200
    d1 = r1.json()
    assert d1["status"] == "INSUFFICIENT_DATA"
    assert d1["prediction"]["abstained"] is True
    assert d1["prediction"]["state"] is None
    assert d1["prediction"]["probabilities"] is None
    assert d1["model_status"]["validated"] is False
    assert d1["demo_mode"] is False
    assert "NO_REGISTERED_MODEL_ARTIFACT" in d1["signal_quality"]["reasons"]

    # 2. Missing signal_quality evidence -> INSUFFICIENT_DATA
    r2 = client.post(
        "/csm/analyze",
        json={"mode": "research_replay", "astronaut_id": "user-123"},
    )
    assert r2.status_code == 200
    d2 = r2.json()
    assert d2["status"] == "INSUFFICIENT_DATA"
    assert "MISSING_SIGNAL_QUALITY_EVIDENCE" in d2["signal_quality"]["reasons"]

    # 3. Low signal quality -> INSUFFICIENT_DATA
    r3 = client.post(
        "/csm/analyze",
        json={
            "mode": "research_replay",
            "astronaut_id": "user-123",
            "signal_quality": {"valid": False, "sqi_score": 0.2, "reasons": ["GSR_DROPOUT"]},
        },
    )
    assert r3.status_code == 200
    d3 = r3.json()
    assert d3["status"] == "INSUFFICIENT_DATA"
    assert d3["prediction"]["probabilities"] is None

    # 4. Synthetic provenance passed into research_replay -> INSUFFICIENT_DATA
    r4 = client.post(
        "/csm/analyze",
        json={
            "mode": "research_replay",
            "astronaut_id": "user-123",
            "data_provenance": "synthetic",
            "signal_quality": {"valid": True, "sqi_score": 0.99, "reasons": []},
        },
    )
    assert r4.status_code == 200
    d4 = r4.json()
    assert d4["status"] == "INSUFFICIENT_DATA"
    assert d4["prediction"]["probabilities"] is None


def test_csm_explicit_synthetic_demo_never_invents_probabilities(client: TestClient):
    resp = client.post(
        "/csm/analyze",
        json={
            "mode": "synthetic_demo",
            "astronaut_id": "user-123",
            "session_id": "demo-01",
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "INSUFFICIENT_DATA"
    assert data["mode"] == "synthetic_demo"
    assert data["demo_mode"] is True
    assert data["data_provenance"] == "synthetic"
    assert data["prediction"]["abstained"] is True
    assert data["prediction"]["state"] is None
    assert data["prediction"]["probabilities"] is None
    assert data["model_status"]["validated"] is False
    assert any("synthetic demo data" in w.lower() for w in data["warnings"])


def test_csm_rejects_live_sensor_raw_signals_and_oversized_payloads(client: TestClient):
    # Live sensor mode rejected
    r_live = client.post("/csm/analyze", json={"mode": "live_sensor"})
    assert r_live.status_code == 400
    assert r_live.json()["errors"][0]["code"] == "LIVE_SENSOR_UNSUPPORTED"
    assert r_live.json()["model_status"]["validated"] is False

    # Live sensor provenance rejected even under research_replay
    r_live_prov = client.post(
        "/csm/analyze",
        json={"mode": "research_replay", "data_provenance": "live_sensor"},
    )
    assert r_live_prov.status_code == 400
    assert r_live_prov.json()["errors"][0]["code"] == "LIVE_SENSOR_UNSUPPORTED"

    # Raw physiological waveform fields rejected (no persistence)
    r_raw = client.post(
        "/csm/analyze",
        json={"mode": "research_replay", "eeg": [1.0, 2.0, 3.0]},
    )
    assert r_raw.status_code == 400
    assert r_raw.json()["errors"][0]["code"] == "RAW_SIGNAL_NOT_ACCEPTED"

    # Unknown mode rejected
    r_bad_mode = client.post("/csm/analyze", json={"mode": "clinical_diagnosis"})
    assert r_bad_mode.status_code == 400
    assert r_bad_mode.json()["errors"][0]["code"] == "INVALID_MODE"

    # Oversized payload rejected (> 32 KiB)
    r_big = client.post(
        "/csm/analyze",
        json={
            "mode": "synthetic_demo",
            "signal_quality": {"valid": True, "sqi_score": 0.9, "reasons": ["x" * 35000]},
        },
    )
    assert r_big.status_code == 413
    assert r_big.json()["errors"][0]["code"] == "PAYLOAD_TOO_LARGE"
