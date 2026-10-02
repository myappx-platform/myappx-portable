@echo off
setlocal EnableExtensions
rem Standard KB setup: database appx_kb (schema appx), then workspace\kb and workspace\sources.
rem PostgreSQL must already be up (start-db.bat). After bin\setup.bat.
rem Assemble needs runtime\python and sibling myappx-plugins (sources also myappx-server); skip if missing.
rem SQL: only %ENV_APPXSERVER_HOME%\utils\postgresql\AppxSetupKB.sql
rem Login: ADEMPIERE_DB_KB_USER / ADEMPIERE_DB_KB_PASSWORD from myEnvironment.bat
rem        (CREATE ROLE if missing; never reset password).

cd /d "%~dp0.."
call "%~dp0env.bat"

"%PGSQL_HOME%\bin\pg_isready.exe" -h localhost -p %PG_PORT% -q
if errorlevel 1 (
    echo PostgreSQL is not ready on port %PG_PORT%. Run start-db.bat first.
    exit /b 1
)

set "ENVFILE=%ENV_APPXSERVER_HOME%\utils\myEnvironment.bat"
if not exist "%ENVFILE%" (
    echo myEnvironment.bat not found:
    echo   %ENVFILE%
    echo Run bin\setup.bat first so conf\utils\ is copied to appxserver\.
    exit /b 1
)
call "%ENVFILE%"

if "%ADEMPIERE_DB_KB_USER%"=="" (
    echo ADEMPIERE_DB_KB_USER is empty. Set it in conf\utils\myEnvironment.bat then re-run bin\setup.bat.
    exit /b 1
)
if "%ADEMPIERE_DB_KB_PASSWORD%"=="" (
    echo ADEMPIERE_DB_KB_PASSWORD is empty. Set it in conf\utils\myEnvironment.bat then re-run bin\setup.bat.
    exit /b 1
)
if "%ADEMPIERE_DB_SERVER%"=="" set "ADEMPIERE_DB_SERVER=localhost"
if "%ADEMPIERE_DB_PORT%"=="" set "ADEMPIERE_DB_PORT=%PG_PORT%"
if "%ADEMPIERE_DB_SYSTEM_USER%"=="" set "ADEMPIERE_DB_SYSTEM_USER=postgres"
if "%ADEMPIERE_DB_SYSTEM%"=="" (
    echo ADEMPIERE_DB_SYSTEM is empty ^(postgres superuser password^).
    exit /b 1
)

set "SQL=%ENV_APPXSERVER_HOME%\utils\postgresql\AppxSetupKB.sql"
if not exist "%SQL%" (
    echo AppxSetupKB.sql not found:
    echo   %SQL%
    echo Run bin\setup.bat first so conf\utils\postgresql\ is copied to appxserver\.
    exit /b 1
)

if not exist "%PGSQL_HOME%\share\extension\vector.control" (
    echo pgvector files missing - bin\install-packages.bat pgvector
    call "%~dp0install-packages.bat" pgvector
    if errorlevel 1 exit /b 1
)

set "PGPASSWORD=%ADEMPIERE_DB_SYSTEM%"
set "PSQL=%PGSQL_HOME%\bin\psql.exe"
set "KBUSER=%ADEMPIERE_DB_KB_USER%"
set "KBPASS=%ADEMPIERE_DB_KB_PASSWORD%"

echo Ensuring role %KBUSER% ...
"%PSQL%" -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %ADEMPIERE_DB_SYSTEM_USER% -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='%KBUSER%'" | findstr /C:"1" >nul
if errorlevel 1 (
    "%PSQL%" -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %ADEMPIERE_DB_SYSTEM_USER% -d postgres -v ON_ERROR_STOP=1 -c "CREATE ROLE %KBUSER% LOGIN PASSWORD '%KBPASS%';"
    if errorlevel 1 (
        echo CREATE ROLE %KBUSER% failed.
        exit /b 1
    )
    echo Created role %KBUSER%
) else (
    echo Role %KBUSER% already exists - password not changed
)

echo Creating database appx_kb on %ADEMPIERE_DB_SERVER%:%ADEMPIERE_DB_PORT%
"%PSQL%" -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %ADEMPIERE_DB_SYSTEM_USER% -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='appx_kb'" | findstr /C:"1" >nul
if errorlevel 1 (
    "%PSQL%" -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %ADEMPIERE_DB_SYSTEM_USER% -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE appx_kb OWNER %KBUSER%;"
    if errorlevel 1 (
        echo CREATE DATABASE appx_kb failed.
        exit /b 1
    )
) else (
    echo Database appx_kb already exists.
)

"%PSQL%" -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %ADEMPIERE_DB_SYSTEM_USER% -d postgres -v ON_ERROR_STOP=1 -c "GRANT CONNECT ON DATABASE appx_kb TO %KBUSER%;"

echo CREATE EXTENSION vector / pg_trgm in public ...
"%PSQL%" -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %ADEMPIERE_DB_SYSTEM_USER% -d appx_kb -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS vector;"
if errorlevel 1 (
    echo.
    echo vector extension is missing. Run bin\install-packages.bat pgvector --force for this postgres -V:
    "%PGSQL_HOME%\bin\postgres.exe" -V
    exit /b 1
)
"%PSQL%" -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %ADEMPIERE_DB_SYSTEM_USER% -d appx_kb -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"

echo Applying %SQL%
"%PSQL%" -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %ADEMPIERE_DB_SYSTEM_USER% -d appx_kb -v ON_ERROR_STOP=1 -v db_user="%KBUSER%" -f "%SQL%"
if errorlevel 1 exit /b 1

echo GRANT on schema appx to %KBUSER% ...
"%PSQL%" -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %ADEMPIERE_DB_SYSTEM_USER% -d appx_kb -v ON_ERROR_STOP=1 -c "GRANT USAGE, CREATE ON SCHEMA appx TO %KBUSER%; GRANT ALL ON ALL TABLES IN SCHEMA appx TO %KBUSER%; GRANT ALL ON ALL SEQUENCES IN SCHEMA appx TO %KBUSER%; ALTER DEFAULT PRIVILEGES IN SCHEMA appx GRANT ALL ON TABLES TO %KBUSER%;"

set "DEV_ROOT=%PORTABLE_ROOT%\.."
if "%PYTHON_HOME%"=="" set "PYTHON_HOME=%PORTABLE_ROOT%\runtime\python"
echo.
if not exist "%PYTHON_HOME%\python.exe" (
    echo Skip assemble: portable Python not found. Run bin\setup.bat first.
    goto KbNext
)
if exist "%DEV_ROOT%\myappx-plugins\" (
    call "%~dp0assemble\assemble-kb.bat"
    if errorlevel 1 exit /b 1
) else (
    echo Skip assemble-kb: sibling myappx-plugins not found
)
if not exist "%DEV_ROOT%\myappx-server\" goto SkipSources
if not exist "%DEV_ROOT%\myappx-plugins\" goto SkipSources
call "%~dp0assemble\assemble-sources.bat"
if errorlevel 1 exit /b 1
goto KbNext

:SkipSources
echo Skip assemble-sources: need sibling myappx-server and myappx-plugins

:KbNext
echo.
echo Next:
echo   1. System Configurator: AI_KB_JDBC_URL=jdbc:postgresql://127.0.0.1:%ADEMPIERE_DB_PORT%/appx_kb
echo      AI_KB_USER=%KBUSER%   IDEMPIERE_AI_KB_PASSWORD=^(ADEMPIERE_DB_KB_PASSWORD^)   AI_KB_ENABLED=Y
echo   2. After AI extension is installed: POST /ai/v1/kb/ingest
echo Re-assemble later: bin\assemble\assemble-kb.bat  /  assemble-sources.bat
exit /b 0
