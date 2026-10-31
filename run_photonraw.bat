@echo off
title PhotonRaw Studio
cd /d "%~dp0"

echo [PhotonRaw] Launching application...
echo --------------------------------------------------------
echo NOTE: If you see 'symlink' error, please turn ON 'Developer Mode':
echo Press Win + I -> Privacy and Security -> For developers
echo Or run: start ms-settings:developers
echo --------------------------------------------------------

call D:\flutter\bin\flutter.bat run -d windows
if %errorlevel% neq 0 (
    echo.
    echo [Failed] If developer mode is not enabled, opening Settings now...
    start ms-settings:developers
)
pause
