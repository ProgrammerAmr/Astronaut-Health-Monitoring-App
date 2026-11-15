#!/usr/bin/env bash
set -euo pipefail
# AI listens only inside the container; browser access is through the authenticated Node proxy.
cd /app/AI_training
/opt/orbitcare-python/bin/python -m uvicorn ai_service:app --host 127.0.0.1 --port 8000 &
ai_pid=$!
cd /app/backend
node server.js &
api_pid=$!
cleanup() { kill "$ai_pid" "$api_pid" 2>/dev/null || true; wait "$ai_pid" "$api_pid" 2>/dev/null || true; }
trap 'cleanup; exit 0' TERM INT
set +e
wait -n "$ai_pid" "$api_pid"
status=$?
set -e
cleanup
# A service stopping unexpectedly, even with exit status 0, requires a restart.
if [ "$status" -eq 0 ]; then exit 1; else exit "$status"; fi
