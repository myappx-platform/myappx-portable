@echo off

rem Interactive start. PostgreSQL must already be up (start-db.bat).
rem Do not run together with Windows service (ports 18080 / 18443).

cd /d "%~dp0"
call "%~dp0bin\env.bat"

if not exist "%ENV_APPXSERVER_HOME%\appxserver.bat" (
    echo AppxServer not found: %ENV_APPXSERVER_HOME%\appxserver.bat
    echo Run bin\setup.bat first.
    exit /b 1
)

cd /d "%ENV_APPXSERVER_HOME%"
call appxserver.bat
