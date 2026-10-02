@echo off

rem Unique path contract for myappx-portable. Caller may be root or bin\.
for %%I in ("%~dp0..") do set "PORTABLE_ROOT=%%~fI"

echo ########################################################
echo ### Setup JAVA HOME                                  ###
echo ########################################################
set "JAVA_HOME=%PORTABLE_ROOT%\runtime\jdk"
set "PATH=%JAVA_HOME%\bin;%PATH%"

java -version

echo ########################################################
echo ### Setup PGSQL HOME                                 ###
echo ########################################################
set "PGSQL_HOME=%PORTABLE_ROOT%\runtime\pgsql"
set "PATH=%PGSQL_HOME%\bin;%PATH%"
set "PGDATA=%PORTABLE_ROOT%\runtime\pgdata"
set "ENV_RUNTIME_LOGS=%PORTABLE_ROOT%\runtime\logs"
set "PG_PORT=15432"
rem Windows psql follows the console code page (CP936=GBK). Portable SQL is UTF-8.
set "PGCLIENTENCODING=UTF8"

postgres -V

echo ########################################################
echo ### Setup APPXSERVER HOME                            ###
echo ########################################################
set "ENV_APPXSERVER_HOME=%PORTABLE_ROOT%\appxserver"

echo ########################################################
echo ### Setup WORKSPACE                                  ###
echo ########################################################
set "ENV_WORKSPACE_HOME=%PORTABLE_ROOT%\workspace"
rem Source Browser pack (independent). Leave SysConfig MYAPPX_SOURCE_ROOTS empty.
set "IDEMPIERE_MYAPPX_SOURCE_ROOTS=%ENV_WORKSPACE_HOME%\sources"
rem Copilot source tools reuse the same pack; not a second tree.
rem Leave SysConfig AI_SOURCE_ROOTS empty.
set "IDEMPIERE_AI_SOURCE_ROOTS=%IDEMPIERE_MYAPPX_SOURCE_ROOTS%"
set "IDEMPIERE_AI_KB_ROOT=%ENV_WORKSPACE_HOME%\kb"
set "IDEMPIERE_AI_WORKSPACE_ROOT=%ENV_WORKSPACE_HOME%\scratch"
set "PYTHON_HOME=%PORTABLE_ROOT%\runtime\python"
