@echo off
REM =====================================================================
REM  OrbitCare - run the Flutter app with the CORRECT backend URL (Windows)
REM  Usage:  scripts\run_flutter.bat
REM
REM  The #1 reason "the app cannot connect to the backend" is running plain
REM  `flutter run`: the app then has to guess the backend address, and a
REM  physical phone cannot reach localhost / 10.0.2.2 at all.
REM
REM  This script detects your LAN IP and passes it with --dart-define.
REM =====================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0\.."

set PORT=5000
set LAN_IP=

REM --- detect the first private IPv4 address of this PC -----------------
for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command ^
  "(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' -or ($_.IPAddress -like '172.*' -and $_.IPAddress -notlike '172.17.*') } | Select-Object -First 1).IPAddress"`) do set LAN_IP=%%i

echo.
echo === OrbitCare Flutter launcher ===
echo.
echo Backend port : %PORT%
if defined LAN_IP (
  echo LAN IP       : %LAN_IP%
) else (
  echo LAN IP       : not detected - a physical phone will not be able to connect
)
echo.
echo Where do you want to run the app?
echo   [1] Android emulator      -^> http://10.0.2.2:%PORT%
echo   [2] Physical Android/iOS  -^> http://%LAN_IP%:%PORT%   ^(same Wi-Fi as this PC^)
echo   [3] Chrome / Edge (web)   -^> http://localhost:%PORT%
echo   [4] Windows desktop       -^> http://localhost:%PORT%
echo.
set /p CHOICE=Choose 1-4 and press Enter: 

if "%CHOICE%"=="1" (
  set URL=http://10.0.2.2:%PORT%
  set DEVICE=
) else if "%CHOICE%"=="2" (
  if not defined LAN_IP (
    echo.
    echo *** No LAN IP detected. Connect to Wi-Fi and run this script again. ***
    pause
    exit /b 1
  )
  set URL=http://%LAN_IP%:%PORT%
  set DEVICE=
) else if "%CHOICE%"=="3" (
  set URL=http://localhost:%PORT%
  set DEVICE=-d chrome
) else if "%CHOICE%"=="4" (
  set URL=http://localhost:%PORT%
  set DEVICE=-d windows
) else (
  echo Invalid choice.
  pause
  exit /b 1
)

echo.
echo Checking the backend at %URL% ...
curl -s -m 5 "%URL%/api/health" >nul 2>&1
if errorlevel 1 (
  echo.
  echo *** WARNING: %URL%/api/health did not answer. ***
  echo     Start the backend first in another terminal:  scripts\start_backend.bat
  echo     For a physical phone also allow the port through the firewall:
  echo       netsh advfirewall firewall add rule name="OrbitCare API" dir=in action=allow protocol=TCP localport=%PORT%
  echo.
  set /p CONTINUE=Run anyway? (y/n): 
  if /i not "!CONTINUE!"=="y" exit /b 1
) else (
  echo Backend is answering. 
)

echo.
echo Running: flutter run %DEVICE% --dart-define=ORBITCARE_API_BASE_URL=%URL%
echo.
pushd Flutter
call flutter pub get
call flutter run %DEVICE% --dart-define=ORBITCARE_API_BASE_URL=%URL%
popd

endlocal
