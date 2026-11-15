#!/usr/bin/env bash
# =====================================================================
#  OrbitCare - run the Flutter app with the CORRECT backend URL
#  (macOS / Linux)
#  Usage:  ./scripts/run_flutter.sh
#
#  The #1 reason "the app cannot connect to the backend" is running plain
#  `flutter run`: the app then has to guess the backend address, and a
#  physical phone cannot reach localhost / 10.0.2.2 at all.
# =====================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PORT="${ORBITCARE_PORT:-5000}"

detect_lan_ip() {
  if command -v ipconfig >/dev/null 2>&1 && [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
  elif command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | awk '/inet /{print $2}' | grep -v '^127\.' | head -n 1
  fi
}

LAN_IP="$(detect_lan_ip)"

echo
echo "=== OrbitCare Flutter launcher ==="
echo
echo "Backend port : $PORT"
if [ -n "$LAN_IP" ]; then
  echo "LAN IP       : $LAN_IP"
else
  echo "LAN IP       : not detected - a physical phone will not be able to connect"
fi
echo
echo "Where do you want to run the app?"
echo "  [1] Android emulator      -> http://10.0.2.2:$PORT"
echo "  [2] Physical Android/iOS  -> http://$LAN_IP:$PORT   (same Wi-Fi as this PC)"
echo "  [3] Chrome (web)          -> http://localhost:$PORT"
echo "  [4] Linux/macOS desktop   -> http://localhost:$PORT"
echo "  [5] iOS simulator         -> http://localhost:$PORT"
echo
read -r -p "Choose 1-5 and press Enter: " CHOICE

DEVICE=""
case "$CHOICE" in
  1) URL="http://10.0.2.2:$PORT" ;;
  2)
    if [ -z "$LAN_IP" ]; then
      echo "*** No LAN IP detected. Connect to Wi-Fi and run this script again. ***"
      exit 1
    fi
    URL="http://$LAN_IP:$PORT"
    ;;
  3) URL="http://localhost:$PORT"; DEVICE="-d chrome" ;;
  4)
    URL="http://localhost:$PORT"
    if [[ "$OSTYPE" == "darwin"* ]]; then DEVICE="-d macos"; else DEVICE="-d linux"; fi
    ;;
  5) URL="http://localhost:$PORT"; DEVICE="-d ios" ;;
  *) echo "Invalid choice."; exit 1 ;;
esac

echo
echo "Checking the backend at $URL ..."
if command -v curl >/dev/null 2>&1; then
  if ! curl -s -m 5 "$URL/api/health" >/dev/null 2>&1; then
    echo
    echo "*** WARNING: $URL/api/health did not answer. ***"
    echo "    Start the backend first in another terminal: ./scripts/start_backend.sh"
    echo
    read -r -p "Run anyway? (y/n): " CONTINUE
    [ "$CONTINUE" = "y" ] || exit 1
  else
    echo "Backend is answering."
  fi
fi

echo
echo "Running: flutter run $DEVICE --dart-define=ORBITCARE_API_BASE_URL=$URL"
echo
cd Flutter
flutter pub get
# shellcheck disable=SC2086
flutter run $DEVICE --dart-define=ORBITCARE_API_BASE_URL="$URL"
