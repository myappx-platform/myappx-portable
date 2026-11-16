@echo off
setlocal EnableExtensions
rem Roll the application back to the copy saved as appxserver.bak-<stamp>.
rem
rem   bin\rollback-update.bat                  use the newest backup, keep the migrated database
rem   bin\rollback-update.bat 20261115-2312    pick a specific stamp
rem   bin\rollback-update.bat 20261115-2312 -RestoreDb
rem
rem -RestoreDb also drops and restores database appx from the dump taken before the
rem update. Migration scripts cannot be undone any other way.

cd /d "%~dp0.."

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update\update.ps1" -Action rollback %*
exit /b %ERRORLEVEL%
