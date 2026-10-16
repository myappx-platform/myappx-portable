@echo off
setlocal EnableExtensions
rem Import zh_CN from appxserver\data\lang\zh_CN_System (copied from conf\data\lang by setup).
rem Does not drop the database. PostgreSQL must already be up (start-db.bat).
rem Safe to re-run. db-import.bat calls this after a fresh seed import.

cd /d "%~dp0.."
call "%~dp0env.bat"

"%PGSQL_HOME%\bin\pg_isready.exe" -h localhost -p %PG_PORT% -q
if errorlevel 1 (
    echo PostgreSQL is not ready on port %PG_PORT%. Run start-db.bat first.
    exit /b 1
)

if not exist "%ENV_APPXSERVER_HOME%\idempiere.ini" (
    echo AppxServer is not installed. Run bin\setup.bat first.
    exit /b 1
)

set "LANG_DIR=%ENV_APPXSERVER_HOME%\data\lang\zh_CN_System"
if not exist "%LANG_DIR%\" (
    echo zh_CN translation folder not found: %LANG_DIR%
    echo Run bin\setup.bat so conf\data\lang is copied onto appxserver\.
    exit /b 1
)

cd /d "%ENV_APPXSERVER_HOME%\utils"
call myEnvironment.bat
cd /d "%ENV_APPXSERVER_HOME%"

set "JARFILE="
for %%c in (plugins\org.eclipse.equinox.launcher_1.*.jar) do set "JARFILE=%%c"
if not exist "%JARFILE%" (
    echo Equinox launcher jar not found under %CD%\plugins
    exit /b 1
)

if not exist "%ENV_RUNTIME_LOGS%" mkdir "%ENV_RUNTIME_LOGS%"
set "LANG_LOG=%ENV_RUNTIME_LOGS%\lang-import.log"

echo Importing zh_CN from %LANG_DIR%
echo Log: %LANG_LOG%

"%JAVA_HOME%\bin\java" -Dosgi.compatibility.bootdelegation=true -Dosgi.noShutdown=false -jar "%JARFILE%" -application org.adempiere.install.translation import "%LANG_DIR%" zh_CN > "%LANG_LOG%" 2>&1
if errorlevel 1 (
    echo Translation import failed. See %LANG_LOG%
    exit /b 1
)

findstr /i /c:"Language does not exist" /c:"Language not active" "%LANG_LOG%" >nul
if not errorlevel 1 (
    echo Translation import rejected zh_CN. See %LANG_LOG%
    exit /b 1
)

echo Synchronizing terminology
"%JAVA_HOME%\bin\java" -Dosgi.compatibility.bootdelegation=true -Dosgi.noShutdown=false -jar "%JARFILE%" -install setup -application org.adempiere.install.translation sync >> "%LANG_LOG%" 2>&1
if errorlevel 1 (
    echo Synchronize terminology failed. See %LANG_LOG%
    exit /b 1
)

echo zh_CN translation imported.
exit /b 0
