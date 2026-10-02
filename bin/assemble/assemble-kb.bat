@echo off
setlocal EnableExtensions
rem Assemble KB corpus from sibling git checkouts. Not first-run install.
rem   bin\assemble\assemble-kb.bat  -> workspace\kb

cd /d "%~dp0..\.."
call "%~dp0..\env.bat"

set "DEV_ROOT=%PORTABLE_ROOT%\.."
set "PY=%~dp0assemble.py"
set "PLUGINS_ROOT=%DEV_ROOT%\myappx-plugins"
set "DOCS_ROOT=%DEV_ROOT%\id-docs"
set "KB_OUT=%ENV_WORKSPACE_HOME%\kb"

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
if not exist "%PLUGINS_ROOT%\" (
    echo myappx-plugins not found: %PLUGINS_ROOT%
    echo Clone it next to myappx-portable.
    exit /b 1
)

echo Assembling KB corpus
echo   plugins: %PLUGINS_ROOT%
echo   kb     : %KB_OUT%
if exist "%DOCS_ROOT%\" (
    echo   docs   : %DOCS_ROOT%
    "%PYTHON_EXE%" "%PY%" kb --plugins-root "%PLUGINS_ROOT%" --docs-root "%DOCS_ROOT%" --kb-output "%KB_OUT%"
) else (
    echo   docs   : skipped ^(no %DOCS_ROOT%^)
    "%PYTHON_EXE%" "%PY%" kb --plugins-root "%PLUGINS_ROOT%" --kb-output "%KB_OUT%"
)
if errorlevel 1 exit /b 1
echo.
echo KB corpus is %KB_OUT% via IDEMPIERE_AI_KB_ROOT - leave SysConfig AI_KB_ROOT empty
echo Then POST /ai/v1/kb/ingest or process KBIngestProcess
exit /b 0
