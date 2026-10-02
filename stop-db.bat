@echo off

cd /d "%~dp0"
call "%~dp0bin\env.bat"

rem -m fast: do not wait for clients to disconnect, reduces hang risk on quit
pg_ctl -D %PGDATA% -m fast stop
