@echo off
setlocal EnableDelayedExpansion

rem Install MyAppx Database (pg_ctl) and MyAppx Application (WinSW). Requires Administrator.

net session >nul 2>&1
if errorlevel 1 (
    echo This script must be run as Administrator.
    exit /b 1
)

set "SERVICE_DIR=%~dp0"
if "%SERVICE_DIR:~-1%"=="\" set "SERVICE_DIR=%SERVICE_DIR:~0,-1%"
for %%I in ("%SERVICE_DIR%\..") do set "PORTABLE_ROOT=%%~fI"

call "%SERVICE_DIR%\service-env.bat"

echo Portable root: %PORTABLE_ROOT%

if not exist "%JAVA_HOME%\bin\java.exe" (
    echo Missing JDK: %JAVA_HOME%
    exit /b 1
)
if not exist "%PGSQL_HOME%\bin\pg_ctl.exe" (
    echo Missing PostgreSQL: %PGSQL_HOME%
    exit /b 1
)
if not exist "%PGDATA%\PG_VERSION" (
    echo Portable environment is not initialized. Run bin\setup.bat first.
    exit /b 1
)
if not exist "%ENV_APPXSERVER_HOME%\plugins" (
    echo Missing appxserver runtime: %ENV_APPXSERVER_HOME%
    exit /b 1
)

if not exist "%ENV_RUNTIME_LOGS%" mkdir "%ENV_RUNTIME_LOGS%"

set "WINSW_DIR=%SERVICE_DIR%\winsw"
set "WINSW_SOURCE=%WINSW_DIR%\WinSW-x64.exe"
set "WINSW_SERVICE=%WINSW_DIR%\AppxServer.exe"

if not exist "%WINSW_DIR%" mkdir "%WINSW_DIR%"

if not exist "%WINSW_SERVICE%" (
    if not exist "%WINSW_SOURCE%" (
        echo WinSW-x64.exe not found in %WINSW_DIR%
        echo Download WinSW v2.12.0 x64 and copy to service\winsw\WinSW-x64.exe
        echo   https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe
        exit /b 1
    )
    copy /Y "%WINSW_SOURCE%" "%WINSW_SERVICE%" >nul
    if errorlevel 1 (
        echo Failed to copy WinSW-x64.exe to %WINSW_SERVICE%
        exit /b 1
    )
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$r=(Resolve-Path '%PORTABLE_ROOT%').Path; $t='%SERVICE_DIR%\winsw\AppxServer.xml.template'; $o='%SERVICE_DIR%\winsw\AppxServer.xml'; $c=Get-Content -Raw $t; $c=$c.Replace('__SERVICE_SCRIPT__',(Join-Path $r 'service\service-appxserver.bat')).Replace('__APPXSERVER_HOME__',(Join-Path $r 'appxserver')).Replace('__LOG_DIR__',(Join-Path $r 'runtime\logs')).Replace('__SERVICE_NAME_PG__','%SERVICE_NAME_PG%').Replace('__SERVICE_ID_APP__','%SERVICE_ID_APP%').Replace('__SERVICE_DISPLAY_APP__','%SERVICE_DISPLAY_APP%').Replace('__SERVICE_DESC_APP__','%SERVICE_DESC_APP%'); Set-Content $o $c -Encoding UTF8; Write-Host Generated $o"
if errorlevel 1 exit /b 1

echo.
echo === Registering PostgreSQL service: %SERVICE_NAME_PG% ===
sc query "%SERVICE_NAME_PG%" >nul 2>&1
if not errorlevel 1 (
    echo Stopping existing %SERVICE_NAME_PG% ...
    net stop "%SERVICE_NAME_PG%" >nul 2>&1
    "%PGSQL_HOME%\bin\pg_ctl.exe" unregister -N "%SERVICE_NAME_PG%"
)

"%PGSQL_HOME%\bin\pg_ctl.exe" register -N "%SERVICE_NAME_PG%" -D "%PGDATA%" -S demand -o "-F -p %PG_PORT%"
if errorlevel 1 (
    echo Failed to register PostgreSQL service.
    exit /b 1
)

sc description "%SERVICE_NAME_PG%" "%SERVICE_DESC_PG%" >nul 2>&1

echo.
echo === Installing AppxServer service via WinSW ===
sc query "%SERVICE_ID_APP%" >nul 2>&1
if not errorlevel 1 (
    echo Stopping existing %SERVICE_DISPLAY_APP% ...
    net stop "%SERVICE_ID_APP%" >nul 2>&1
    "%WINSW_SERVICE%" uninstall >nul 2>&1
)

"%WINSW_SERVICE%" install
if errorlevel 1 (
    echo Failed to install AppxServer service.
    exit /b 1
)

echo.
echo Services installed (Manual, not started).
echo   PostgreSQL: %SERVICE_NAME_PG%
echo   AppxServer: %SERVICE_DISPLAY_APP% (%SERVICE_ID_APP%)
echo Start later: service\services.bat start
echo Logs: %PORTABLE_ROOT%\runtime\logs
exit /b 0
