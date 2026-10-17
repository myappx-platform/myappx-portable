@echo off
setlocal EnableExtensions
rem Reset portable to pre-install: delete runtime/appxserver/generated workspace.
rem Keeps Git sources, packages\ zips, conf\, workspace README, WinSW exe/template.
rem   bin\clean.bat       prompt for YES
rem   bin\clean.bat /Y    skip the prompt (bin\reset.bat)

cd /d "%~dp0.."
call "%cd%\service\service-env.bat"
set "ROOT=%PORTABLE_HOME%"
set "PG_CTL=%ROOT%\runtime\pgsql\bin\pg_ctl.exe"
set "PGDATA=%ROOT%\runtime\pgdata"

sc query "%SERVICE_NAME_PG%" 2>nul | findstr /I /C:"RUNNING" >nul
if not errorlevel 1 (
    echo Windows service is running: %SERVICE_NAME_PG%
    echo Stop it first: service\services.bat stop
    exit /b 1
)
sc query "%SERVICE_ID_APP%" 2>nul | findstr /I /C:"RUNNING" >nul
if not errorlevel 1 (
    echo Windows service is running: %SERVICE_ID_APP%
    echo Stop it first: service\services.bat stop
    exit /b 1
)

if exist "%PG_CTL%" if exist "%PGDATA%\PG_VERSION" (
    "%PG_CTL%" -D "%PGDATA%" status >nul 2>&1
    if not errorlevel 1 (
        echo Stopping PostgreSQL ...
        "%PG_CTL%" -D "%PGDATA%" -m fast stop
        if errorlevel 1 (
            echo Could not stop PostgreSQL. Close clients and retry.
            exit /b 1
        )
    )
)
if exist "%PGDATA%\postmaster.pid" (
    echo PostgreSQL pid file still present: %PGDATA%\postmaster.pid
    echo Stop the database first.
    exit /b 1
)

echo.
echo This deletes install output and returns the tree to pre-init:
echo   runtime\   appxserver\   plugins\
echo   workspace\sources  kb\assembled  kb\drop  scratch  kb\manifest.json
echo   service\winsw\AppxServer.xml  AppxServer.exe
echo Kept: packages\ zips, conf\, workspace README, WinSW-x64.exe
echo Stop run-appxserver.bat if it is still running.
echo.
if /I "%~1"=="/Y" goto DoClean
set /p "ANS=Type YES to continue: "
if /I not "%ANS%"=="YES" (
    echo Cancelled.
    exit /b 1
)

:DoClean
echo Removing generated files ...
if exist "%ROOT%\runtime" rmdir /s /q "%ROOT%\runtime"
if exist "%ROOT%\appxserver" rmdir /s /q "%ROOT%\appxserver"
if exist "%ROOT%\plugins" rmdir /s /q "%ROOT%\plugins"
if exist "%ROOT%\conf\data\ExpDat.dmp" del /q "%ROOT%\conf\data\ExpDat.dmp"
if exist "%ROOT%\service\winsw\AppxServer.xml" del /q "%ROOT%\service\winsw\AppxServer.xml"
if exist "%ROOT%\service\winsw\AppxServer.exe" del /q "%ROOT%\service\winsw\AppxServer.exe"
if exist "%ROOT%\bin\assemble\__pycache__" rmdir /s /q "%ROOT%\bin\assemble\__pycache__"
if exist "%ROOT%\workspace\kb\manifest.json" del /q "%ROOT%\workspace\kb\manifest.json"

call :WipeKeepGitkeep "%ROOT%\workspace\sources"
call :WipeKeepGitkeep "%ROOT%\workspace\scratch"
call :WipeKeepGitkeep "%ROOT%\workspace\kb\assembled"
call :WipeKeepGitkeep "%ROOT%\workspace\kb\drop"

if exist "%ROOT%\runtime" (
    echo Failed to remove runtime\ - a process may still have files open.
    exit /b 1
)
if exist "%ROOT%\appxserver" (
    echo Failed to remove appxserver\ - stop the application and retry.
    exit /b 1
)

echo.
echo Clean finished. Next: bin\setup.bat
exit /b 0

:WipeKeepGitkeep
set "DIR=%~1"
if exist "%DIR%" rmdir /s /q "%DIR%"
mkdir "%DIR%"
type nul > "%DIR%\.gitkeep"
exit /b 0
