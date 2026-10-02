@echo off
setlocal

rem Remove MyAppx Application (WinSW) and MyAppx Database (pg_ctl). Requires Administrator.

net session >nul 2>&1
if errorlevel 1 (
    echo This script must be run as Administrator.
    exit /b 1
)

set "SERVICE_DIR=%~dp0"
call "%SERVICE_DIR%\service-env.bat"

echo Stopping %SERVICE_DISPLAY_APP% ...
net stop "%SERVICE_ID_APP%" >nul 2>&1
if exist "%SERVICE_DIR%\winsw\AppxServer.exe" (
    "%SERVICE_DIR%\winsw\AppxServer.exe" uninstall >nul 2>&1
)

echo Stopping %SERVICE_NAME_PG% ...
net stop "%SERVICE_NAME_PG%" >nul 2>&1
if exist "%PGSQL_HOME%\bin\pg_ctl.exe" (
    "%PGSQL_HOME%\bin\pg_ctl.exe" unregister -N "%SERVICE_NAME_PG%" >nul 2>&1
)

echo Services removed.
exit /b 0
