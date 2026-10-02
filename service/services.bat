@echo off
setlocal
call "%~dp0service-env.bat"

if /i "%~1"=="start" goto start
if /i "%~1"=="stop" goto stop
if /i "%~1"=="status" goto status

echo Usage: %~nx0 start^|stop^|status
exit /b 1

:start
echo Starting %SERVICE_NAME_PG% ...
net start "%SERVICE_NAME_PG%"
if errorlevel 1 exit /b 1
echo Starting %SERVICE_DISPLAY_APP% ...
net start "%SERVICE_ID_APP%"
if errorlevel 1 exit /b 1
echo Services started.
exit /b 0

:stop
echo Stopping %SERVICE_DISPLAY_APP% ...
net stop "%SERVICE_ID_APP%" >nul 2>&1
echo Stopping %SERVICE_NAME_PG% ...
net stop "%SERVICE_NAME_PG%" >nul 2>&1
echo Services stopped.
exit /b 0

:status
echo === %SERVICE_NAME_PG% ===
sc query "%SERVICE_NAME_PG%"
echo.
echo === %SERVICE_DISPLAY_APP% (%SERVICE_ID_APP%) ===
sc query "%SERVICE_ID_APP%"
exit /b 0
