#!/usr/bin/env bash
# =====================================================================
#  OrbitCare - start the Node backend (macOS / Linux)
#  Usage:  ./scripts/start_backend.sh
# =====================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo
echo "=== OrbitCare backend setup ==="
echo

if [ ! -d "backend/node_modules/express" ]; then
  echo "[1/4] Installing backend dependencies ..."
  (cd backend && npm install)
else
  echo "[1/4] Dependencies already installed."
fi

if [ ! -f "backend/.env" ]; then
  echo "[2/4] Creating backend/.env ..."
  (cd backend && npm run doctor:fix)
else
  echo "[2/4] backend/.env already exists."
fi

echo "[3/4] Checking MongoDB, port and configuration ..."
(cd backend && npm run doctor)
DOCTOR_EXIT=$?

if [ "$DOCTOR_EXIT" -ne 0 ]; then
  echo
  echo "*** The doctor found blocking problems. Fix them above before continuing. ***"
  echo "    Most common cause: MongoDB is not running."
  echo "      - Docker : docker run -d -p 27017:27017 --name orbitcare-mongo mongo:7"
  echo "      - Local  : brew services start mongodb-community   (macOS)"
  echo "                 sudo systemctl start mongod             (Linux)"
  echo
  exit 1
fi

echo "[4/4] Starting the API (Ctrl+C to stop) ..."
echo
cd backend && npm run dev
