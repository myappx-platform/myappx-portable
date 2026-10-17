@echo off
setlocal EnableExtensions
rem Reset: one YES prompt, then clean /Y, setup, start-db, db-import /Y, setup-kb, stop-db.
rem Later steps do not prompt. Report: runtime\logs\reset-report.txt
rem If runtime\logs does not exist yet, the report stays in %%TEMP%%\myappx-reset-report.txt.

cd /d "%~dp0.."
set "ROOT=%CD%"

echo.
echo Reset %ROOT%
echo   clean, setup, import database appx, setup-kb, then stop PostgreSQL.
echo   Install output is deleted. The application is not started.
echo.
set /p "ANS=Type YES to continue: "
if /I not "%ANS%"=="YES" (
    echo Cancelled.
    exit /b 1
)

call "%ROOT%\service\service-env.bat"
set "REPORT_TEMP=%TEMP%\myappx-reset-report.txt"
set "REPORT_FINAL=%ROOT%\runtime\logs\reset-report.txt"
set "OVERALL=0"
set "DB_STARTED="

call :InitReport
call :Preflight
if errorlevel 1 goto Finish

call :Exec clean "%ROOT%\bin\clean.bat" /Y
if errorlevel 1 goto Finish

call :Exec setup "%ROOT%\bin\setup.bat"
if errorlevel 1 goto Finish

call :StartDb
if errorlevel 1 goto StopIfNeeded

call :Exec db-import "%ROOT%\bin\db-import.bat" /Y
if errorlevel 1 goto StopIfNeeded

call :Exec setup-kb "%ROOT%\bin\setup-kb.bat"

:StopIfNeeded
if defined DB_STARTED call :Exec stop-db "%ROOT%\stop-db.bat"

:Finish
call :WriteFooter
call :Publish
echo.
type "%REPORT_PATH%"
echo.
exit /b %OVERALL%

:InitReport
call :NowStamp
set "STARTED=%NOW_STAMP%"
>"%REPORT_TEMP%" echo myappx-portable reset
>>"%REPORT_TEMP%" echo Started: %STARTED%
>>"%REPORT_TEMP%" echo Root: %ROOT%
>>"%REPORT_TEMP%" echo.
>>"%REPORT_TEMP%" echo Step	Result	Exit	Seconds	Note
exit /b 0

:Preflight
set "STEP_NAME=preflight"
set "STEP_RESULT=OK"
set "STEP_RC=0"
set "STEP_ELAPSED=0"
set "STEP_NOTE="

sc query "%SERVICE_NAME_PG%" 2>nul | findstr /I /C:"RUNNING" >nul
if not errorlevel 1 goto PreflightServicePg

sc query "%SERVICE_ID_APP%" 2>nul | findstr /I /C:"RUNNING" >nul
if not errorlevel 1 goto PreflightServiceApp

netstat -ano | findstr /I /C:"LISTENING" | findstr /C:":18080 " /C:":18443 " >nul
if not errorlevel 1 goto PreflightPort

call :AppendStep
call :Publish
exit /b 0

:PreflightServicePg
set "STEP_NOTE=Windows service is running: %SERVICE_NAME_PG%. Stop it first: service\services.bat stop"
goto PreflightFail

:PreflightServiceApp
set "STEP_NOTE=Windows service is running: %SERVICE_ID_APP%. Stop it first: service\services.bat stop"
goto PreflightFail

:PreflightPort
set "STEP_NOTE=Port 18080 or 18443 is listening. Stop run-appxserver.bat first."
goto PreflightFail

:PreflightFail
set "STEP_RESULT=FAIL"
set "STEP_RC=1"
set "OVERALL=1"
call :AppendStep
call :Publish
exit /b 1

:Exec
set "STEP_NAME=%~1"
set "STEP_SCRIPT=%~2"
set "STEP_ARG=%~3"
set "STEP_NOTE="
set "STEP_LOG=%TEMP%\myappx-reset-%STEP_NAME%.log"
echo.
echo ########################################################
echo ### %STEP_NAME%
echo ########################################################
call :NowEpoch
set "STEP_EPOCH=%NOW_EPOCH%"
pushd "%ROOT%"
call "%STEP_SCRIPT%" %STEP_ARG% > "%STEP_LOG%" 2>&1
set "STEP_RC=%ERRORLEVEL%"
popd
type "%STEP_LOG%"
if not "%STEP_RC%"=="0" goto ExecFail
if /I "%STEP_NAME%"=="setup-kb" if not exist "%ROOT%\workspace\kb\manifest.json" set "STEP_NOTE=assemble skipped"
set "STEP_RESULT=OK"
call :FinishStep
exit /b 0

:ExecFail
set "STEP_RESULT=FAIL"
set "OVERALL=1"
call :LastLogLine
call :FinishStep
exit /b 1

:StartDb
set "STEP_NAME=start-db"
set "STEP_NOTE="
set "STEP_LOG=%TEMP%\myappx-reset-start-db.log"
echo.
echo ########################################################
echo ### start-db
echo ########################################################
call :NowEpoch
set "STEP_EPOCH=%NOW_EPOCH%"
pushd "%ROOT%"
call "%ROOT%\start-db.bat" > "%STEP_LOG%" 2>&1
set "STEP_RC=%ERRORLEVEL%"
popd
type "%STEP_LOG%"
if not "%STEP_RC%"=="0" goto StartDbFail
set "DB_STARTED=1"
set "N=0"

:WaitPg
"%PGSQL_HOME%\bin\pg_isready.exe" -h localhost -p %PG_PORT% -q
if not errorlevel 1 goto StartDbOk
set /a N+=1
if %N% GEQ 30 goto StartDbTimeout
ping -n 2 127.0.0.1 >nul
goto WaitPg

:StartDbTimeout
set "STEP_RC=1"
set "STEP_NOTE=PostgreSQL not ready on port %PG_PORT% within 30s"
goto StartDbFail

:StartDbFail
set "STEP_RESULT=FAIL"
set "OVERALL=1"
if not defined STEP_NOTE call :LastLogLine
call :FinishStep
exit /b 1

:StartDbOk
set "STEP_RESULT=OK"
set "STEP_RC=0"
set "STEP_NOTE=ready on %PG_PORT%"
call :FinishStep
exit /b 0

:FinishStep
call :NowEpoch
set "STEP_ELAPSED=0"
set /a "STEP_ELAPSED=NOW_EPOCH-STEP_EPOCH" 2>nul
call :AppendStep
call :Publish
exit /b 0

:LastLogLine
set "STEP_NOTE="
if exist "%STEP_LOG%" for /f "usebackq delims=" %%L in ("%STEP_LOG%") do set "STEP_NOTE=%%L"
if not defined STEP_NOTE set "STEP_NOTE=failed"
set "STEP_NOTE=%STEP_NOTE:"='%"
exit /b 0

:AppendStep
>>"%REPORT_TEMP%" echo %STEP_NAME%	%STEP_RESULT%	%STEP_RC%	%STEP_ELAPSED%	"%STEP_NOTE%"
exit /b 0

:WriteFooter
call :NowStamp
set "OVERALL_WORD=FAIL"
if "%OVERALL%"=="0" set "OVERALL_WORD=OK"
>>"%REPORT_TEMP%" echo.
>>"%REPORT_TEMP%" echo OVERALL: %OVERALL_WORD%
>>"%REPORT_TEMP%" echo Finished: %NOW_STAMP%
>>"%REPORT_TEMP%" echo Logs:
>>"%REPORT_TEMP%" echo   runtime\logs\initdb.log
>>"%REPORT_TEMP%" echo   runtime\logs\seed-import.log
>>"%REPORT_TEMP%" echo   runtime\logs\lang-import.log
>>"%REPORT_TEMP%" echo   runtime\logs\postgres.log
call :Publish
>>"%REPORT_TEMP%" echo Report: %REPORT_PATH%
exit /b 0

:Publish
set "REPORT_PATH=%REPORT_TEMP%"
if not exist "%ROOT%\runtime\logs\" exit /b 0
copy /Y "%REPORT_TEMP%" "%REPORT_FINAL%" >nul
set "REPORT_PATH=%REPORT_FINAL%"
exit /b 0

:NowStamp
set "NOW_STAMP="
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"`) do set "NOW_STAMP=%%T"
if not defined NOW_STAMP set "NOW_STAMP=unknown"
exit /b 0

:NowEpoch
set "NOW_EPOCH=0"
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:TEMP + '\myappx-reset-epoch.txt', [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString())" >nul
set /p NOW_EPOCH=<"%TEMP%\myappx-reset-epoch.txt"
exit /b 0
