#!/usr/bin/env bash
# =====================================================================
#  OrbitCare - build an installable Android APK (macOS / Linux)
#  Usage:  ./scripts/build_apk.sh
#
#  An installed APK cannot receive --dart-define at runtime, so the backend
#  URL is baked in at BUILD time. You can still change it later inside the
#  app: login screen -> Backend Connection.
# =====================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PORT="${ORBITCARE_PORT:-5000}"

detect_lan_ip() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
  elif command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | awk '/inet /{print $2}' | grep -v '^127\.' | head -n 1
  fi
}

LAN_IP="$(detect_lan_ip)"

echo
echo "=== OrbitCare APK builder ==="
echo
echo "LAN IP of this PC : ${LAN_IP:-not detected}"
echo
echo "Which device will run the APK?"
echo "  [1] Android emulator on this PC   -> http://10.0.2.2:$PORT"
echo "  [2] Physical phone (same Wi-Fi)   -> http://$LAN_IP:$PORT"
echo "  [3] Custom URL (deployed backend / another IP)"
echo
read -r -p "Choose 1-3: " TARGET

case "$TARGET" in
  1) URL="http://10.0.2.2:$PORT" ;;
  2)
    if [ -z "$LAN_IP" ]; then
      echo "*** No LAN IP detected. Connect to Wi-Fi, or choose 3 and type it manually. ***"
      exit 1
    fi
    URL="http://$LAN_IP:$PORT"
    ;;
  3)
    echo "Example: http://192.168.1.42:5000  or  https://orbitcare-api.onrender.com"
    read -r -p "Backend URL: " URL
    ;;
  *) echo "Invalid choice."; exit 1 ;;
esac

echo
echo "Which build do you want?"
echo "  [1] Split per ABI  - smaller APK, recommended for a phone (arm64-v8a)"
echo "  [2] Universal APK  - one big APK that runs on every Android device"
echo "  [3] App Bundle     - .aab for Google Play upload"
echo
read -r -p "Choose 1-3 [default 1]: " KIND
KIND="${KIND:-1}"

cd Flutter || exit 1
echo
echo "[1/3] Fetching dependencies ..."
flutter pub get || { echo "*** flutter pub get failed ***"; exit 1; }

echo
case "$KIND" in
  2)
    echo "[2/3] Building universal release APK for $URL ..."
    flutter build apk --release --dart-define=ORBITCARE_API_BASE_URL="$URL"
    ;;
  3)
    echo "[2/3] Building release app bundle for $URL ..."
    flutter build appbundle --release --dart-define=ORBITCARE_API_BASE_URL="$URL"
    ;;
  *)
    echo "[2/3] Building split-per-ABI release APKs for $URL ..."
    flutter build apk --release --split-per-abi --dart-define=ORBITCARE_API_BASE_URL="$URL"
    ;;
esac

if [ $? -ne 0 ]; then
  echo
  echo "*** Build failed. Try once with a clean build: ***"
  echo "    cd Flutter && flutter clean && flutter pub get && cd .. && ./scripts/build_apk.sh"
  exit 1
fi

echo
echo "[3/3] Done. Output files:"
if [ "$KIND" = "3" ]; then
  ls -1 build/app/outputs/bundle/release/*.aab 2>/dev/null
  OUTPUT="build/app/outputs/bundle/release/app-release.aab"
else
  ls -1 build/app/outputs/flutter-apk/*.apk 2>/dev/null
  OUTPUT="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
fi

echo
echo "Full path: $(pwd)/$OUTPUT"
echo

if [ "$KIND" != "3" ] && command -v adb >/dev/null 2>&1; then
  echo "Connected devices:"
  adb devices
  echo
  read -r -p "Install now on the connected device? (y/n): " INSTALL
  if [ "$INSTALL" = "y" ] && [ -f "$OUTPUT" ]; then
    adb install -r "$OUTPUT"
  fi
fi

cat <<EOF

---------------------------------------------------------------------
 Before the app can log in on a physical phone:
   1. Backend must be running on this PC:  ./scripts/start_backend.sh
   2. Phone and PC on the SAME Wi-Fi network
   3. Allow TCP port $PORT through the firewall
        macOS : System Settings -> Network -> Firewall -> allow node
        Linux : sudo ufw allow $PORT/tcp
   4. Test from the phone browser:  $URL/api/health
   5. Demo login: demo.astronaut@orbitcare.local / OrbitDemo!2026
      (create it first with: cd backend && npm run seed:demo)
 Baked backend URL: $URL
 Change it later inside the app: login screen -> Backend Connection
---------------------------------------------------------------------
EOF
