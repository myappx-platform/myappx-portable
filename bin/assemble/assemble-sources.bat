@echo off
setlocal EnableExtensions
rem Assemble Java source pack from sibling git checkouts. Not first-run install.
rem   bin\assemble\assemble-sources.bat  -> workspace\sources

cd /d "%~dp0..\.."
call "%~dp0..\env.bat"

set "DEV_ROOT=%PORTABLE_ROOT%\.."
set "PY=%~dp0assemble.py"
set "SERVER_ROOT=%DEV_ROOT%\myappx-server"
set "PLUGINS_ROOT=%DEV_ROOT%\myappx-plugins"
set "SRC_OUT=%ENV_WORKSPACE_HOME%\sources"

if not exist "%PY%" (
    echo assemble.py not found: %PY%
    exit /b 1
)
if "%PYTHON_HOME%"=="" set "PYTHON_HOME=%PORTABLE_ROOT%\runtime\python"
set "PYTHON_EXE=%PYTHON_HOME%\python.exe"
if not exist "%PYTHON_EXE%" (
    echo Portable Python not found: %PYTHON_EXE%
    echo Run bin\setup.bat first so runtime\python\ exists.
    exit /b 1
)

echo Assembling source pack
echo   server : %SERVER_ROOT%
echo   plugins: %PLUGINS_ROOT%
echo   output : %SRC_OUT%
"%PYTHON_EXE%" "%PY%" sources --server-root "%SERVER_ROOT%" --plugins-root "%PLUGINS_ROOT%" --output "%SRC_OUT%" --clean
exit /b %ERRORLEVEL%
