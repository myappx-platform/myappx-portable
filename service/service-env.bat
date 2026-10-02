@echo off
rem Shared config and environment for Windows services (Session 0; no interactive env.bat)

set "SERVICE_NAME_PG=MyAppx Database"
set "SERVICE_DESC_PG=MyAppx Database Server"
set "SERVICE_ID_APP=MyAppx Application"
set "SERVICE_DISPLAY_APP=MyAppx Application"
set "SERVICE_DESC_APP=MyAppx Application Server"
set "PG_PORT=15432"

set "PORTABLE_HOME=%~dp0.."
if "%PORTABLE_HOME:~-1%"=="\" set "PORTABLE_HOME=%PORTABLE_HOME:~0,-1%"
for %%I in ("%PORTABLE_HOME%") do set "PORTABLE_HOME=%%~fI"

set "JAVA_HOME=%PORTABLE_HOME%\runtime\jdk"
set "PGSQL_HOME=%PORTABLE_HOME%\runtime\pgsql"
set "PGDATA=%PORTABLE_HOME%\runtime\pgdata"
set "ENV_RUNTIME_LOGS=%PORTABLE_HOME%\runtime\logs"
set "ENV_APPXSERVER_HOME=%PORTABLE_HOME%\appxserver"
set "ENV_WORKSPACE_HOME=%PORTABLE_HOME%\workspace"
set "IDEMPIERE_AI_SOURCE_ROOTS=%ENV_WORKSPACE_HOME%\sources"
set "IDEMPIERE_AI_KB_ROOT=%ENV_WORKSPACE_HOME%\kb"
set "IDEMPIERE_AI_WORKSPACE_ROOT=%ENV_WORKSPACE_HOME%\scratch"
set "IDEMPIERE_MYAPPX_SOURCE_ROOTS=%ENV_WORKSPACE_HOME%\sources"
set "PATH=%JAVA_HOME%\bin;%PGSQL_HOME%\bin;%PATH%"
