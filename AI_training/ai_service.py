"""
HTTP service wrapping the AI module (recommended way for the Node.js backend to call it).

Run:
    uvicorn ai_service:app --host 127.0.0.1 --port 8001

Endpoints:
    GET  /health    -> thresholds info + number of indexed NASA chunks
    POST /analyze   -> body: {"astronaut_id": "...", "timestamp": "...", "measurements": {...}}
                       returns the fixed JSON contract (see nasa_claude.build_response)

Index the NASA documents once, separately:  python ingest.py
"""

from __future__ import annotations

import threading
from typing import Any

from fastapi import Body, FastAPI
from fastapi.responses import JSONResponse

from nasa_claude import MissionHealthSystem, SCHEMA_VERSION, error_response, setup_logging

setup_logging()
app = FastAPI(title="Astronaut Health AI", version=SCHEMA_VERSION)

_system: MissionHealthSystem | None = None
_lock = threading.Lock()


def get_system() -> MissionHealthSystem:
    global _system
    if _system is None:
        with _lock:
            if _system is None:
                _system = MissionHealthSystem()
    return _system


@app.get("/health")
def health():
    try:
        return {"ok": True, **get_system().health()}
    except Exception as e:  # noqa: BLE001
        return JSONResponse(status_code=503, content={"ok": False, "error": f"{type(e).__name__}: {e}"})


@app.post("/analyze")
def analyze(payload: Any = Body(...)):
    # Plain `def` -> FastAPI runs it in a worker thread, so a slow LLM does not block other requests.
    try:
        system = get_system()
    except Exception as e:  # noqa: BLE001 - e.g. thresholds file missing
        return JSONResponse(status_code=503,
                            content=error_response("CONFIG_ERROR", f"{type(e).__name__}: {e}"))
    return system.analyze(payload)
