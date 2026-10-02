@echo off
rem Remove machine-specific service artifacts before copying appxserver-portable elsewhere.
rem Run after stopping services. Does not uninstall Windows services — use uninstall-services.bat first.

setlocal
call "%~dp0service-env.bat"

echo Removing generated service files under %PORTABLE_HOME% ...
del /q "%~dp0winsw\AppxServer.xml" 2>nul
del /q "%~dp0winsw\AppxServer.exe" 2>nul
del /q "%PORTABLE_HOME%\runtime\logs\AppxServer*.log" 2>nul
del /q "%PORTABLE_HOME%\runtime\logs\postgres.log" 2>nul

echo.
echo Kept for target machine install:
echo   service\winsw\AppxServer.xml.template
echo   service\winsw\WinSW-x64.exe
echo.
echo On the target machine: place at final path, then run install-services.bat as Administrator.
exit /b 0
