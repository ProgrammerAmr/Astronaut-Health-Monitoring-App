# AI module - integration guide

Decision-support prototype. Not a diagnosis. **Rules decide the status; the LLM only explains.**

## Files
| File | Purpose |
|---|---|
| `nasa_claude.py` | The one main implementation (rules + RAG + JSON contract + CLI) |
| `ai_service.py` | FastAPI service for the Node.js backend |
| `ingest.py` | Offline indexing of `nasa_docs/` into ChromaDB |
| `thresholds.json` | Thresholds, with `source` / `reviewed_by` / `validated` fields |
| `nasa_docs/` | NASA knowledge files (`.md` / `.txt`) |
| `tests/test_nasa_claude.py` | Tests (no Ollama needed) |

`nasa_ai.py` is superseded: move it to `archive/` or delete it.

## Setup
```bash
pip install -r requirements.txt
ollama pull llama3 && ollama pull nomic-embed-text
cp .env.example .env          # optional, every value has a default
python ingest.py              # index docs once (re-run after adding/changing files)
uvicorn ai_service:app --host 127.0.0.1 --port 8001
pytest -q
```
Other ways to call it: `python nasa_claude.py --stdin < request.json` (JSON in, JSON out) or `--demo`.

## Request
```json
{
  "astronaut_id": "A1",
  "timestamp": "2026-11-14T10:00:00Z",
  "measurements": {
    "heart_rate": 72, "systolic_bp": 118, "diastolic_bp": 76,
    "spo2": 98, "sleep_hours": 7.5, "radiation_msv": 0.2
  }
}
```
Canonical names are `heart_rate, systolic_bp, diastolic_bp, spo2, sleep_hours, radiation_msv`.
Also accepted: `oxygen_saturation`, `o2_saturation` -> `spo2`; `blood_pressure` as `"120/80"`, `{systolic, diastolic}` or `[120, 80]`; `hr`, `pulse`, `sleep`, `radiation`, etc. A flat object or a `vitals` key also works.

## Response (always the same shape, never an exception)
```json
{
  "schema_version": "1.0",
  "status": "GREEN | YELLOW | RED | INSUFFICIENT_DATA | ERROR",
  "data_quality": "complete | partial | none",
  "astronaut_id": "A1", "timestamp": "...", "processed_at": "...",
  "measurements": {}, "alerts": [], "invalid": {}, "missing": [],
  "warnings": [], "errors": [],
  "ai": {"available": true, "used_llm": true, "grounded": true, "text": "...", "sources": [], "error": null},
  "thresholds": {"version": "0.1-draft", "validated": false},
  "disclaimer": "..."
}
```
Status rules: any critical value or 2+ abnormal -> `RED`; one abnormal -> `YELLOW`; nothing abnormal but data missing/invalid -> `INSUFFICIENT_DATA` (never GREEN); everything required present, valid and normal -> `GREEN`. Abnormal values are never hidden by missing data elsewhere.

## Node.js example
```js
const res = await fetch("http://127.0.0.1:8001/analyze", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ astronaut_id, measurements }),
});
const result = await res.json();   // always the contract above
```

## What changed vs. the review points
1. **Paths:** env vars + paths relative to the file; no machine paths; no silent `makedirs`.
2. **Schema:** `normalize_measurements()` with aliases and BP parsing; unknown names are reported in `warnings`.
3. **Missing/invalid data:** `INSUFFICIENT_DATA`, plausibility ranges, bool/NaN/inf/strings rejected.
4. **Interface:** FastAPI service + stdin/stdout CLI, fixed JSON contract, logs on stderr only.
5. **One implementation:** `nasa_claude.py`; the LLM no longer picks the status.
6. **ChromaDB updates:** hash-based re-indexing, new files picked up, deleted files pruned, old chunks removed only after new embeddings succeed, embedding model stored with the index (`python ingest.py --rebuild` after changing it).
7. **Thresholds:** moved to `thresholds.json`; the API reports `thresholds.validated: false` until a qualified reviewer fills `source`/`reviewed_by` and sets `validated: true`. **The numbers are still placeholders.**

## Failure behaviour
- Ollama down / timeout / Chroma error -> status unchanged, `ai.available=false`, safe fallback text, `ai.error` code.
- No NASA source found -> `ai.grounded=false` plus a warning (set `REQUIRE_GROUNDING=true` to return fallback text instead of ungrounded AI text).
- Bad JSON / bad payload / missing thresholds file -> `status: "ERROR"` with `errors[{code,message}]`.
