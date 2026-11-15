@echo off
REM =====================================================================
REM  OrbitCare - build the app as something you can install (Windows)
REM  Usage:  scripts\build_app.bat
REM
REM    [1] Android APK  (phone / emulator)      -> delegates to build_apk.bat
REM    [2] Windows desktop app (.exe)
REM    [3] Web build (installable from Chrome)
REM
REM  The backend URL is baked in at BUILD time (an installed app cannot receive
REM  --dart-define later). It can still be changed from inside the app:
REM  login screen -> Backend Connection.
REM =====================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0\.."

set PORT=5000
set LAN_IP=

for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command ^
  "(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' -or ($_.IPAddress -like '172.*' -and $_.IPAddress -notlike '172.17.*') } | Select-Object -First 1).IPAddress"`) do set LAN_IP=%%i

echo.
echo === OrbitCare app builder ===
echo.
if defined LAN_IP (echo LAN IP of this PC : %LAN_IP%) else (echo LAN IP of this PC : not detected)
echo.
echo What do you want to build?
echo   [1] Android APK        - phone or emulator
echo   [2] Windows desktop    - .exe you can double click ^(needs Visual Studio C++^)
echo   [3] Web build          - folder you can host, and Chrome can install it as an app
echo.
set /p CHOICE=Choose 1-3: 

if "%CHOICE%"=="1" (
  call "%~dp0build_apk.bat"
  exit /b %ERRORLEVEL%
)

REM ---------------- backend URL for desktop / web ----------------------
set URL=http://localhost:%PORT%
echo.
echo Backend URL to bake in [Enter = %URL%]:
set /p CUSTOM=URL: 
if not "%CUSTOM%"=="" set URL=%CUSTOM%

cd Flutter
call flutter pub get
if errorlevel 1 (echo *** flutter pub get failed *** & pause & exit /b 1)

if "%CHOICE%"=="2" goto windows_build
if "%CHOICE%"=="3" goto web_build
echo Invalid choice. & pause & exit /b 1

:windows_build
echo.
echo Building Windows desktop app for %URL% ...
echo ^(requires Visual Studio 2022 with "Desktop development with C++"^)
call flutter build windows --release --dart-define=ORBITCARE_API_BASE_URL=%URL%
if errorlevel 1 (
  echo.
  echo *** Windows build failed. ***
  echo   - Install Visual Studio 2022 Community + workload "Desktop development with C++"
  echo   - Check what is missing:  flutter doctor -v
  echo   - Or build the Android APK instead:  scripts\build_apk.bat
  pause & exit /b 1
)
echo.
echo ---------------------------------------------------------------------
echo  Your app folder ^(copy the WHOLE folder, then run nasa.exe^):
echo    %CD%\build\windows\x64\runner\Release
echo  Baked backend URL: %URL%
echo  The backend must be running:  scripts\start_backend.bat
echo ---------------------------------------------------------------------
explorer "%CD%\build\windows\x64\runner\Release" 2>nul
cd .. & pause & exit /b 0

:web_build
echo.
echo Building web app for %URL% ...
call flutter build web --release --dart-define=ORBITCARE_API_BASE_URL=%URL%
if errorlevel 1 (echo *** Web build failed *** & pause & exit /b 1)
echo.
echo ---------------------------------------------------------------------
echo  Output folder: %CD%\build\web
echo  Baked backend URL: %URL%
echo.
echo  Try it locally ^(from the Flutter folder^):
echo    python -m http.server 8080 --directory build\web
echo    then open http://localhost:8080
echo.
echo  Install it like an app: open it in Chrome -^> address bar "Install app"
echo  icon ^(or Chrome menu -^> Cast, save and share -^> Install page as app^).
echo.
echo  Note: the browser must be able to reach the backend URL above, and the
echo  backend must allow CORS ^(backend/server.js already allows all origins^).
echo ---------------------------------------------------------------------
cd .. & pause & exit /b 0
