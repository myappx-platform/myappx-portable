@echo off
rem Windows service entry point for AppxServer (foreground java process)

setlocal EnableDelayedExpansion

call "%~dp0service-env.bat"

if not exist "%JAVA_HOME%\bin\java.exe" (
    echo JAVA_HOME not found: %JAVA_HOME%
    exit /b 1
)
if not exist "%ENV_APPXSERVER_HOME%\plugins" (
    echo AppxServer home not found: %ENV_APPXSERVER_HOME%
    exit /b 1
)

set "MAX_WAIT=120"
set "WAITED=0"
:wait_db
"%PGSQL_HOME%\bin\pg_isready.exe" -h localhost -p %PG_PORT% -q
if %errorlevel%==0 goto db_ready
timeout /t 2 /nobreak >nul
set /a WAITED+=2
if %WAITED% geq %MAX_WAIT% (
    echo PostgreSQL not ready after %MAX_WAIT% seconds on port %PG_PORT%
    exit /b 1
)
goto wait_db
:db_ready

cd /d "%ENV_APPXSERVER_HOME%"
echo Starting AppxServer service from %ENV_APPXSERVER_HOME%
call appxserver.bat
set "EXIT_CODE=%errorlevel%"
echo AppxServer service exited with code %EXIT_CODE%
exit /b %EXIT_CODE%
