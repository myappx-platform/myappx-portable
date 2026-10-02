@echo off
rem Restore appx from appxserver\data\ExpDat.dmp. DROPS and recreates the database.
rem PostgreSQL must already be up (start-db.bat).

cd /d "%~dp0.."
call "%~dp0env.bat"

"%PGSQL_HOME%\bin\pg_isready.exe" -h localhost -p %PG_PORT% -q
if errorlevel 1 (
    echo PostgreSQL is not ready on port %PG_PORT%. Run start-db.bat first.
    exit /b 1
)

cd /d "%ENV_APPXSERVER_HOME%\utils"
echo Restore will DROP and recreate database appx from data\ExpDat.dmp. Product script will pause to confirm.
call RUN_DBRestore.bat
