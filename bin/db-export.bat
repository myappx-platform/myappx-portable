@echo off
rem Export appx to appxserver\data\ExpDat.dmp.
rem PostgreSQL must already be up (start-db.bat).

cd /d "%~dp0.."
call "%~dp0env.bat"

"%PGSQL_HOME%\bin\pg_isready.exe" -h localhost -p %PG_PORT% -q
if errorlevel 1 (
    echo PostgreSQL is not ready on port %PG_PORT%. Run start-db.bat first.
    exit /b 1
)

cd /d "%ENV_APPXSERVER_HOME%\utils"
call RUN_DBExport.bat
