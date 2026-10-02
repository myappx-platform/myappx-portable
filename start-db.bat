@ECHO OFF

cd /d "%~dp0"
call "%~dp0bin\env.bat"

if not exist "%ENV_RUNTIME_LOGS%" mkdir "%ENV_RUNTIME_LOGS%"

rem -W: do not wait for server to accept connections (avoids blocking; init 6s delay allows DB to be ready)
pg_ctl -D %PGDATA% -l "%ENV_RUNTIME_LOGS%\postgres.log" -o "-F -p %PG_PORT%" -W start
