@echo off
setlocal
rem First-run / refresh: unpack packages, overwrite conf\ -> appxserver\, initdb if needed.
rem Re-run is safe: skips initdb when runtime\pgdata\ already exists; always recopies conf\.

cd /d "%~dp0.."
call "%~dp0install-packages.bat"
if errorlevel 1 exit /b 1

call "%~dp0env.bat"

set "PG_PORTABLE_INCLUDE=postgresql.portable.conf"
set "PG_ALREADY_INIT="
if exist "%PGDATA%\PG_VERSION" set "PG_ALREADY_INIT=1"

if not exist "%PORTABLE_ROOT%\runtime" mkdir "%PORTABLE_ROOT%\runtime"
if not exist "%ENV_WORKSPACE_HOME%" mkdir "%ENV_WORKSPACE_HOME%"
if not exist "%ENV_RUNTIME_LOGS%" mkdir "%ENV_RUNTIME_LOGS%"

echo ########################################################
echo ### Copy conf to appxserver (overwrite)              ###
echo ########################################################
if not exist "%ENV_APPXSERVER_HOME%" mkdir "%ENV_APPXSERVER_HOME%"
xcopy /E /Y /I "%PORTABLE_ROOT%\conf\*" "%ENV_APPXSERVER_HOME%\" >nul
if errorlevel 1 (
    echo Failed to copy conf to %ENV_APPXSERVER_HOME%
    exit /b 1
)
echo Config copied from conf\ to appxserver\

echo ########################################################
echo ### Initialize PostgreSQL (pgdata)                   ###
echo ########################################################
if defined PG_ALREADY_INIT goto SkipInitDb

rem Do not put initdb in a parenthesized IF/ELSE block: cmd.exe + PowerShell
rem make -W password prompts and ERRORLEVEL checks unreliable there.
rem --pwfile avoids stdin; long options avoid "-E UTF8" being split (e.g. F8).
rem Success is PG_VERSION, not ERRORLEVEL (spurious cmd noise can be 9009).
set "PG_PWFILE=%TEMP%\myappx-pg-pw-%RANDOM%%RANDOM%.txt"
set "PG_INITDB_LOG=%ENV_RUNTIME_LOGS%\initdb.log"
rem Must match ADEMPIERE_DB_SYSTEM in conf\utils\myEnvironment.bat
(echo postgres123) > "%PG_PWFILE%"
set "LC_MESSAGES=C"
set "LANG=C"
echo Initializing %PGDATA% (user postgres / postgres123)
echo Log: %PG_INITDB_LOG%
initdb.exe --pgdata="%PGDATA%" --auth=scram-sha-256 --username=postgres --pwfile="%PG_PWFILE%" --encoding=UTF8 --no-locale --lc-messages=C > "%PG_INITDB_LOG%" 2>&1
set "INITDB_RC=%ERRORLEVEL%"
del /q "%PG_PWFILE%" >nul 2>&1
if not exist "%PGDATA%\PG_VERSION" (
    echo initdb failed, exit code %INITDB_RC%
    type "%PG_INITDB_LOG%"
    exit /b 1
)
echo PostgreSQL data directory initialized: %PGDATA%
goto AfterInitDb

:SkipInitDb
echo PostgreSQL data directory already initialized: %PGDATA%
echo Skipping initdb. Remove runtime\pgdata\ to re-initialize.

:AfterInitDb
echo ########################################################
echo ### Apply PostgreSQL portable settings               ###
echo ########################################################
call :ApplyPgPortableConfig
exit /b %ERRORLEVEL%

:ApplyPgPortableConfig
set "PG_TEMPLATE=%PORTABLE_ROOT%\conf\pg\%PG_PORTABLE_INCLUDE%"
set "PG_OVERRIDE=%PGDATA%\%PG_PORTABLE_INCLUDE%"
set "PG_MAIN=%PGDATA%\postgresql.conf"

if not exist "%PGDATA%\PG_VERSION" (
    echo PostgreSQL not initialized, skipped portable PG settings.
    exit /b 0
)

if not exist "%PG_TEMPLATE%" (
    echo Missing template: %PG_TEMPLATE%
    exit /b 1
)

copy /Y "%PG_TEMPLATE%" "%PG_OVERRIDE%" >nul
if errorlevel 1 (
    echo Failed to copy portable PostgreSQL settings to %PG_OVERRIDE%
    exit /b 1
)
echo Synced conf\pg\%PG_PORTABLE_INCLUDE% -^> runtime\pgdata\%PG_PORTABLE_INCLUDE%

findstr /i /r /c:"include[ ]*'%PG_PORTABLE_INCLUDE%'" "%PG_MAIN%" >nul 2>&1
if not errorlevel 1 goto ApplyPgPortableConfigDone

echo.>>"%PG_MAIN%"
echo # myappx-portable overrides>>"%PG_MAIN%"
echo include '%PG_PORTABLE_INCLUDE%'>>"%PG_MAIN%"
echo Registered include '%PG_PORTABLE_INCLUDE%' in postgresql.conf

:ApplyPgPortableConfigDone
if defined PG_ALREADY_INIT echo Restart PostgreSQL if it is running: stop-db.bat then start-db.bat
exit /b 0
