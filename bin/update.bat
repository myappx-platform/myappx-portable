@echo off
setlocal EnableExtensions
rem Update the portable installation to the newest packages found locally or in the
rem configured online manifest (conf\update.ini).
rem
rem Portable mode only: the application runs via run-appxserver.bat and PostgreSQL via
rem start-db.bat. Do not install or run the Windows services on a tree you update.
rem
rem   bin\update.bat                    plan, ask for YES, then update (offline when no base URL)
rem   bin\update.bat -CheckOnly         print the plan only
rem   bin\update.bat -Offline           ignore conf\update.ini base URL
rem   bin\update.bat -AllowPgMajor      allow a PostgreSQL major upgrade (pg_upgrade)
rem   bin\update.bat -Force             re-apply components that already report "skip"
rem   bin\update.bat -Resume            finish the database phase after a run that stopped mid-way
rem
rem Steps: preflight, plan, download, backup, check ports, stop DB, swap runtime + product,
rem pg_upgrade, start DB, RUN_SyncDB, sign, zh_CN, verify, update packages.ini,
rem stop DB again.
rem PostgreSQL is always stopped when the update ends. Report: runtime\logs\update-report.txt
rem Logs: runtime\logs\update\<stamp>\   Rollback: bin\rollback-update.bat <stamp>

cd /d "%~dp0.."

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update\update.ps1" -Action apply %*
exit /b %ERRORLEVEL%
