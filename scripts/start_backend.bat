@echo off
REM =====================================================================
REM  OrbitCare - start the Node backend on Windows
REM  Usage:  scripts\start_backend.bat
REM
REM  What it does:
REM    1. installs backend dependencies if needed
REM    2. creates backend\.env from .env.example (with a generated JWT secret)
REM    3. runs the environment doctor (MongoDB, port, firewall hints)
REM    4. starts the API and prints the exact URLs for the Flutter app
REM =====================================================================
setlocal
cd /d "%~dp0\.."

echo.
echo === OrbitCare backend setup ===
echo.

if not exist "backend\node_modules\express" (
  echo [1/4] Installing backend dependencies ...
  pushd backend
  call npm install
  popd
) else (
  echo [1/4] Dependencies already installed.
)

if not exist "backend\.env" (
  echo [2/4] Creating backend\.env ...
  pushd backend
  call npm run doctor:fix
  popd
) else (
  echo [2/4] backend\.env already exists.
)

echo [3/4] Checking MongoDB, port and configuration ...
pushd backend
call npm run doctor
set DOCTOR_EXIT=%ERRORLEVEL%
popd

if not "%DOCTOR_EXIT%"=="0" (
  echo.
  echo *** The doctor found blocking problems. Fix them above before continuing. ***
  echo     Most common cause: MongoDB is not running.
  echo       - Docker : docker run -d -p 27017:27017 --name orbitcare-mongo mongo:7
  echo       - Local  : start the "MongoDB Server" Windows service, or run mongod
  echo.
  pause
  exit /b 1
)

echo [4/4] Starting the API (Ctrl+C to stop) ...
echo.
pushd backend
call npm run dev
popd

endlocal
