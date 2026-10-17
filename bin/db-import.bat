@echo off
rem Import iDempiere seed into appx, then import zh_CN. DROPS and recreates the database.
rem PostgreSQL must already be up (start-db.bat).
rem   bin\db-import.bat       product script pauses for confirmation
rem   bin\db-import.bat /Y    no pause (bin\reset.bat)

cd /d "%~dp0.."
call "%~dp0env.bat"

if /I "%~1"=="/Y" (
    set "MYAPPX_UNATTENDED=1"
) else (
    set "MYAPPX_UNATTENDED="
)

"%PGSQL_HOME%\bin\pg_isready.exe" -h localhost -p %PG_PORT% -q
if errorlevel 1 (
    echo PostgreSQL is not ready on port %PG_PORT%. Run start-db.bat first.
    exit /b 1
)

cd /d "%ENV_APPXSERVER_HOME%\utils"
if defined MYAPPX_UNATTENDED (
    echo Import will DROP and recreate database appx. Unattended: no pause.
) else (
    echo Import will DROP and recreate database appx. Product script will pause to confirm.
)
call RUN_ImportIdempiere.bat
if errorlevel 1 exit /b 1
call "%~dp0db-lang.bat"
if errorlevel 1 exit /b 1
echo db-import finished.
