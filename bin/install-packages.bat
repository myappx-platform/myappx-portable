@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM Unpack zips from packages\ using packages.ini.
REM   bin\install-packages.bat              JDK + pgsql + appxserver + python + pgvector
REM   bin\install-packages.bat pgvector     overlay pgvector only
REM   bin\install-packages.bat pgvector --force

for %%I in ("%~dp0..") do set "ROOT=%%~fI"
cd /d "%ROOT%"
set "PKG=%ROOT%\packages"
set "INI=%PKG%\packages.ini"
set "TAR=%SystemRoot%\System32\tar.exe"

set "DO_RUNTIME=1"
set "DO_VECTOR="
set "FORCE="
:ParseArgs
if "%~1"=="" goto ArgsDone
if /I "%~1"=="pgvector" (
    set "DO_RUNTIME="
    set "DO_VECTOR=1"
) else if /I "%~1"=="--force" (
    set "FORCE=1"
) else (
    echo Unknown argument: %~1
    echo Usage: bin\install-packages.bat [pgvector] [--force]
    exit /b 1
)
shift
goto ParseArgs
:ArgsDone

if not exist "%INI%" (
    echo Missing package list:
    echo   %INI%
    exit /b 1
)
if not exist "%TAR%" (
    echo tar.exe not found: %TAR%
    exit /b 1
)

call :LoadIni
if errorlevel 1 exit /b 1

if defined DO_RUNTIME (
    if not exist "%ROOT%\runtime" mkdir "%ROOT%\runtime"
    call :EnsureExtract "!JDK_ZIP!" "%ROOT%\!JDK_DIR!" "!JDK_MARKER!" "JDK"
    if errorlevel 1 exit /b 1
    call :EnsureExtract "!PGSQL_ZIP!" "%ROOT%\!PGSQL_DIR!" "!PGSQL_MARKER!" "PostgreSQL"
    if errorlevel 1 exit /b 1
    if not "!APPX_ZIP!"=="" (
        call :EnsureExtract "!APPX_ZIP!" "%ROOT%\!APPX_DIR!" "!APPX_MARKER!" "AppxServer" overlay
        if errorlevel 1 exit /b 1
    )
    call :EnsureExtract "!PYTHON_ZIP!" "%ROOT%\!PYTHON_DIR!" "!PYTHON_MARKER!" "Python"
    if errorlevel 1 exit /b 1
    call :EnsureVector
    if errorlevel 1 exit /b 1
)

if defined DO_VECTOR (
    call :EnsureVector
    if errorlevel 1 exit /b 1
)

exit /b 0

:LoadIni
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%INI%") do (
    set "_k=%%A"
    if not "!_k!"=="" if not "!_k:~0,1%"==";" (
        set "%%A=%%B"
    )
)
if "!JDK_ZIP!"=="" (
    echo packages.ini: JDK_ZIP is empty
    exit /b 1
)
if "!JDK_DIR!"=="" set "JDK_DIR=runtime\jdk"
if "!JDK_MARKER!"=="" set "JDK_MARKER=bin\java.exe"
if "!PGSQL_ZIP!"=="" (
    echo packages.ini: PGSQL_ZIP is empty
    exit /b 1
)
if "!PGSQL_DIR!"=="" set "PGSQL_DIR=runtime\pgsql"
if "!PGSQL_MARKER!"=="" set "PGSQL_MARKER=bin\postgres.exe"
if "!APPX_DIR!"=="" set "APPX_DIR=appxserver"
if "!APPX_MARKER!"=="" set "APPX_MARKER=idempiere.ini"
if "!VECTOR_ZIP!"=="" (
    echo packages.ini: VECTOR_ZIP is empty
    exit /b 1
)
if "!VECTOR_DEST!"=="" set "VECTOR_DEST=!PGSQL_DIR!"
if "!VECTOR_MARKER!"=="" set "VECTOR_MARKER=share\extension\vector.control"
if "!PYTHON_ZIP!"=="" (
    echo packages.ini: PYTHON_ZIP is empty
    exit /b 1
)
if "!PYTHON_DIR!"=="" set "PYTHON_DIR=runtime\python"
if "!PYTHON_MARKER!"=="" set "PYTHON_MARKER=python.exe"
exit /b 0

:EnsureExtract
set "ZIPNAME=%~1"
set "DEST=%~2"
set "MARKER=%~3"
set "LABEL=%~4"
set "OVERLAY=%~5"
if exist "%DEST%\%MARKER%" (
    echo %LABEL% already present: %DEST%
    exit /b 0
)
if exist "%DEST%" if /I not "%OVERLAY%"=="overlay" (
    echo %DEST% exists but is missing %MARKER%
    echo Remove that folder and re-run, or unpack the zip from packages\ yourself.
    exit /b 1
)
set "ZIP=%PKG%\%ZIPNAME%"
if not exist "%ZIP%" (
    echo Missing %LABEL% zip:
    echo   %ZIP%
    echo Place it in packages\ and set the zip name in packages.ini.
    exit /b 1
)

echo Unpacking %LABEL% from %ZIPNAME% ...
set "WORK=%TEMP%\appx-unpack-%RANDOM%%RANDOM%"
if exist "%WORK%" rmdir /s /q "%WORK%"
mkdir "%WORK%" 2>nul
"%TAR%" -xf "%ZIP%" -C "%WORK%"
if errorlevel 1 (
    echo tar extract failed: %ZIP%
    if exist "%WORK%" rmdir /s /q "%WORK%"
    exit /b 1
)

set "SRC="
call :ResolveExtractRoot "%WORK%" "%MARKER%"
if not defined SRC (
    echo Zip layout unexpected: %MARKER% not found under extract dir
    rmdir /s /q "%WORK%"
    exit /b 1
)

if exist "%DEST%" (
    echo Overlay %LABEL% into %DEST%
    xcopy /E /Y /I "!SRC!\*" "%DEST%\" >nul
    rmdir /s /q "%WORK%" 2>nul
) else if /I "!SRC!"=="%WORK%" (
    move "%WORK%" "%DEST%" >nul
) else (
    move "!SRC!" "%DEST%" >nul
    rmdir /s /q "%WORK%" 2>nul
)
if errorlevel 1 (
    echo Failed to move unpacked %LABEL% to %DEST%
    if exist "%WORK%" rmdir /s /q "%WORK%"
    exit /b 1
)
if not exist "%DEST%\%MARKER%" (
    echo Unpack incomplete: missing %DEST%\%MARKER%
    exit /b 1
)
echo Installed %LABEL%: %DEST%
exit /b 0

:ResolveExtractRoot
set "_work=%~1"
set "_mark=%~2"
set "SRC="
if exist "%_work%\%_mark%" (
    set "SRC=%_work%"
    goto :eof
)
set "_n=0"
for /d %%D in ("%_work%\*") do (
    if exist "%%~D\%_mark%" (
        set /a _n+=1
        set "SRC=%%~D"
    )
)
if not "!_n!"=="1" set "SRC="
goto :eof

:EnsureVector
set "VDEST=%ROOT%\%VECTOR_DEST%"
if not exist "%VDEST%\bin\postgres.exe" (
    echo PostgreSQL not found: %VDEST%
    echo Run bin\setup.bat first so runtime\pgsql\ exists.
    exit /b 1
)
if exist "%VDEST%\%VECTOR_MARKER%" if not defined FORCE (
    echo pgvector already present:
    echo   %VDEST%\%VECTOR_MARKER%
    echo Re-run with --force to replace.
    exit /b 0
)

set "ZIP=%PKG%\%VECTOR_ZIP%"
if not exist "%ZIP%" (
    echo Missing pgvector zip:
    echo   %ZIP%
    echo Place it in packages\ and set VECTOR_ZIP in packages.ini.
    exit /b 1
)

echo Overlay pgvector from %VECTOR_ZIP% into %VDEST%
set "WORK=%TEMP%\appx-unpack-vector-%RANDOM%%RANDOM%"
if exist "%WORK%" rmdir /s /q "%WORK%"
mkdir "%WORK%" 2>nul
"%TAR%" -xf "%ZIP%" -C "%WORK%"
if errorlevel 1 (
    echo tar extract failed: %ZIP%
    if exist "%WORK%" rmdir /s /q "%WORK%"
    exit /b 1
)

set "SRC="
call :ResolveExtractRoot "%WORK%" "lib\vector.dll"
if not defined SRC (
    echo Zip layout unexpected: lib\vector.dll not found in %VECTOR_ZIP%
    rmdir /s /q "%WORK%"
    exit /b 1
)

if not exist "%VDEST%\lib" mkdir "%VDEST%\lib"
copy /Y "!SRC!\lib\vector.dll" "%VDEST%\lib\vector.dll" >nul
if errorlevel 1 (
    echo Copy vector.dll failed. If CREATE EXTENSION already loaded the DLL, stop Postgres and re-run --force.
    rmdir /s /q "%WORK%"
    exit /b 1
)
if exist "!SRC!\share\extension" (
    if not exist "%VDEST%\share\extension" mkdir "%VDEST%\share\extension"
    copy /Y "!SRC!\share\extension\*" "%VDEST%\share\extension\" >nul
)
if exist "!SRC!\include\server\extension\vector" (
    if not exist "%VDEST%\include\server\extension\vector" mkdir "%VDEST%\include\server\extension\vector"
    copy /Y "!SRC!\include\server\extension\vector\*" "%VDEST%\include\server\extension\vector\" >nul
)

rmdir /s /q "%WORK%" 2>nul

if not exist "%VDEST%\%VECTOR_MARKER%" (
    echo vector.control was not installed.
    exit /b 1
)
echo Installed:
echo   %VDEST%\lib\vector.dll
echo   %VDEST%\%VECTOR_MARKER%
exit /b 0
