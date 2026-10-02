@Echo	Portable DB finalize: schema %ADEMPIERE_DB_USER%, read-only role %ADEMPIERE_DB_RO_USER%

@if "%ADEMPIERE_DB_NAME%" == "" goto environment
@if "%ADEMPIERE_DB_SERVER%" == "" goto environment
@if "%ADEMPIERE_DB_PORT%" == "" goto environment
@if "%ADEMPIERE_DB_USER%" == "" goto environment
@if "%ADEMPIERE_DB_PASSWORD%" == "" goto environment
@if "%ADEMPIERE_DB_RO_USER%" == "" goto environment
@if "%ADEMPIERE_DB_RO_PASSWORD%" == "" goto environment

@set PGPASSWORD=%ADEMPIERE_DB_PASSWORD%
@psql -b -v ON_ERROR_STOP=1 -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -d %ADEMPIERE_DB_NAME% -U %ADEMPIERE_DB_USER% -v db_ro_user="%ADEMPIERE_DB_RO_USER%" -v db_ro_password="%ADEMPIERE_DB_RO_PASSWORD%" -f "%~dp0AppxFinalizeDb.sql"
@set PGPASSWORD=
@if errorlevel 1 exit /b 1
@goto end

:environment
@Echo AppxFinalizeDb: load myEnvironment.bat first
@Echo   ADEMPIERE_DB_SERVER ADEMPIERE_DB_PORT ADEMPIERE_DB_NAME
@Echo   ADEMPIERE_DB_USER ADEMPIERE_DB_PASSWORD
@Echo   ADEMPIERE_DB_RO_USER ADEMPIERE_DB_RO_PASSWORD
@exit /b 1

:end
