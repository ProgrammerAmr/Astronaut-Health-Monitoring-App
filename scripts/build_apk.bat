@echo off
REM =====================================================================
REM  OrbitCare - build an installable Android APK (Windows)
REM  Usage:  scripts\build_apk.bat
REM
REM  IMPORTANT: an installed APK cannot receive --dart-define at runtime, so
REM  the backend URL is baked in at BUILD time. This script asks which device
REM  you are installing on and bakes the right address for you.
REM  (You can still change it later inside the app: Backend Connection.)
REM =====================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0\.."

set PORT=5000
set LAN_IP=

for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command ^
  "(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' -or ($_.IPAddress -like '172.*' -and $_.IPAddress -notlike '172.17.*') } | Select-Object -First 1).IPAddress"`) do set LAN_IP=%%i

echo.
echo === OrbitCare APK builder ===
echo.
if defined LAN_IP (echo LAN IP of this PC : %LAN_IP%) else (echo LAN IP of this PC : not detected)
echo.
echo Which device will run the APK?
echo   [1] Android emulator on this PC   -^> http://10.0.2.2:%PORT%
echo   [2] Physical phone (same Wi-Fi)   -^> http://%LAN_IP%:%PORT%
echo   [3] Custom URL (deployed backend / another IP)
echo.
set /p TARGET=Choose 1-3: 

if "%TARGET%"=="1" (
  set URL=http://10.0.2.2:%PORT%
) else if "%TARGET%"=="2" (
  if not defined LAN_IP (
    echo *** No LAN IP detected. Connect to Wi-Fi, or choose 3 and type it manually. ***
    pause & exit /b 1
  )
  set URL=http://%LAN_IP%:%PORT%
) else if "%TARGET%"=="3" (
  echo Example: http://192.168.1.42:5000  or  https://orbitcare-api.onrender.com
  set /p URL=Backend URL: 
) else (
  echo Invalid choice. & pause & exit /b 1
)

echo.
echo Which build do you want?
echo   [1] Split per ABI  - smaller APK, recommended for a phone (arm64-v8a)
echo   [2] Universal APK  - one big APK that runs on every Android device
echo   [3] App Bundle     - .aab for Google Play upload
echo.
set /p KIND=Choose 1-3 [default 1]: 
if "%KIND%"=="" set KIND=1

cd Flutter
echo.
echo [1/3] Fetching dependencies ...
call flutter pub get
if errorlevel 1 (echo *** flutter pub get failed *** & pause & exit /b 1)

echo.
if "%KIND%"=="2" (
  echo [2/3] Building universal release APK for %URL% ...
  call flutter build apk --release --dart-define=ORBITCARE_API_BASE_URL=%URL%
) else if "%KIND%"=="3" (
  echo [2/3] Building release app bundle for %URL% ...
  call flutter build appbundle --release --dart-define=ORBITCARE_API_BASE_URL=%URL%
) else (
  echo [2/3] Building split-per-ABI release APKs for %URL% ...
  call flutter build apk --release --split-per-abi --dart-define=ORBITCARE_API_BASE_URL=%URL%
)
if errorlevel 1 (
  echo.
  echo *** Build failed. Try once with a clean build: ***
  echo     cd Flutter ^&^& flutter clean ^&^& flutter pub get ^&^& scripts\..\scripts\build_apk.bat
  pause & exit /b 1
)

echo.
echo [3/3] Done. Output files:
if "%KIND%"=="3" (
  dir /b build\app\outputs\bundle\release\*.aab 2>nul
  set OUTPUT=build\app\outputs\bundle\release\app-release.aab
) else (
  dir /b build\app\outputs\flutter-apk\*.apk 2>nul
  set OUTPUT=build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
)
echo.
echo Full path: %CD%\%OUTPUT%
echo.

REM ---- optional: install straight onto a connected phone -----------------
set ADB=adb
if not exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" goto no_adb_path
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
:no_adb_path

if "%KIND%"=="3" goto skip_install
echo Connected devices:
"%ADB%" devices
echo.
set /p INSTALL=Install now on the connected device? (y/n): 
if /i "!INSTALL!"=="y" (
  if exist "%OUTPUT%" (
    "%ADB%" install -r "%OUTPUT%"
  ) else (
    echo Expected %OUTPUT% - install one of the APKs listed above with:
    echo   adb install -r "Flutter\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
  )
)
:skip_install

echo.
echo ---------------------------------------------------------------------
echo  Before the app can log in on a physical phone:
echo    1. Backend must be running on this PC:  scripts\start_backend.bat
echo    2. Phone and PC on the SAME Wi-Fi network
echo    3. Allow the port through Windows Firewall (run cmd as Administrator):
echo       netsh advfirewall firewall add rule name="OrbitCare API" dir=in action=allow protocol=TCP localport=%PORT%
echo    4. Test from the phone browser:  %URL%/api/health
echo    5. Demo login: demo.astronaut@orbitcare.local / OrbitDemo!2026
echo       (create it first with: cd backend ^&^& npm run seed:demo)
echo  Baked backend URL: %URL%
echo  Change it later inside the app: login screen -^> Backend Connection
echo ---------------------------------------------------------------------
echo.
cd ..
endlocal
pause
