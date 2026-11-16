@echo off
setlocal EnableExtensions
rem Update the portable installation to the newest packages found locally or in the
rem configured online manifest (conf\update.ini).
rem
rem   bin\update.bat                    plan, ask for YES, then update (offline when no base URL)
rem   bin\update.bat -CheckOnly         print the plan only
rem   bin\update.bat -Offline           ignore conf\update.ini base URL
rem   bin\update.bat -StopServices      stop the MyAppx services first
rem   bin\update.bat -AllowPgMajor      allow a PostgreSQL major upgrade (pg_upgrade)
rem   bin\update.bat -Start             start the application service when done
rem   bin\update.bat -Force             re-apply components that already report "skip"
rem
rem Steps: preflight, plan, download, backup, stop, swap runtime + product, pg_upgrade,
rem start DB, RUN_SyncDB, sign, zh_CN, verify, update packages.ini.
rem Report: runtime\logs\update-report.txt   Logs: runtime\logs\update\<stamp>\
rem Rollback: bin\rollback-update.bat <stamp>

cd /d "%~dp0.."

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update\update.ps1" -Action apply %*
exit /b %ERRORLEVEL%
