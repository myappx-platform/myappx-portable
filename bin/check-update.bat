@echo off
setlocal
rem Check whether newer packages are available. Does not change anything.
rem   bin\check-update.bat
rem   bin\check-update.bat -Offline
rem Exit code: 0 = up to date, 2 = update available, 1 = error.

cd /d "%~dp0.."

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update\update.ps1" -Action check %*
exit /b %ERRORLEVEL%
