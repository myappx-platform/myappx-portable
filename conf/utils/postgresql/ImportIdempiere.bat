@Echo	idempiere Database Import (portable)		$Revision: 1.3 $

@Rem Portable override: import seed dump then finalize schema/role (%ADEMPIERE_DB_USER% / %ADEMPIERE_DB_RO_USER%).

@Echo	Importing idempiere DB from %IDEMPIERE_HOME%\data\seed\Adempiere%5.dmp (%ADEMPIERE_DB_NAME%)

@if (%IDEMPIERE_HOME%) == () goto environment
@if (%ADEMPIERE_DB_NAME%) == () goto environment
@if (%ADEMPIERE_DB_SERVER%) == () goto environment
@if (%ADEMPIERE_DB_PORT%) == () goto environment
@Rem Must have parameters AdempiereID AdempierePwd systemUser systemPwd
@if (%1) == () goto usage
@if (%2) == () goto usage
@if (%3) == () goto usage
@if (%4) == () goto usage

@set PGPASSWORD=%4
@echo -------------------------------------
@echo Re-Create user and database
@echo -------------------------------------
@psql -q -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -d postgres -U %3 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '%ADEMPIERE_DB_NAME%' AND pid <> pg_backend_pid();"
@dropdb --if-exists -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %3 %ADEMPIERE_DB_NAME%
@dropuser --if-exists -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %3 %1
@set ADEMPIERE_CREATE_ROLE_SQL=CREATE ROLE %1 SUPERUSER LOGIN PASSWORD '%2'
@psql -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %3 -c "%ADEMPIERE_CREATE_ROLE_SQL%" -d template1
@set ADEMPIERE_CREATE_ROLE_SQL=
rem Seed dump does ALTER ... OWNER TO adempiere. Keep a nologin stub so those lines are not ERROR.
@psql -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -d postgres -U %3 -c "DO $$ BEGIN CREATE ROLE adempiere NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;"

@set PGPASSWORD=%2
@createdb --template=template0 -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -E UNICODE -O %1 -U %1 %ADEMPIERE_DB_NAME%

@echo -------------------------------------
@echo Import Adempiere%5.dmp
@echo -------------------------------------
@set ADEMPIERE_ALTER_ROLE_SQL=ALTER ROLE %1 SET search_path TO adempiere, pg_catalog

@psql -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -d %ADEMPIERE_DB_NAME% -U %1 -c "%ADEMPIERE_ALTER_ROLE_SQL%"

@if "%ENV_RUNTIME_LOGS%"=="" set "ENV_RUNTIME_LOGS=%TEMP%"
@if not exist "%ENV_RUNTIME_LOGS%" mkdir "%ENV_RUNTIME_LOGS%"
@set "SEED_LOG=%ENV_RUNTIME_LOGS%\seed-import.log"
@echo Seed dump log: %SEED_LOG%
@psql -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -d %ADEMPIERE_DB_NAME% -U %1 -f %IDEMPIERE_HOME%/data/seed/Adempiere%5.dmp > "%SEED_LOG%" 2>&1
@set ADEMPIERE_ALTER_ROLE_SQL=

@echo -------------------------------------
@echo Finalize portable schema (%ADEMPIERE_DB_USER%) / read-only role (%ADEMPIERE_DB_RO_USER%)
@echo -------------------------------------
@call "%~dp0AppxFinalizeDb.bat"
@if errorlevel 1 (
    @set PGPASSWORD=
    @exit /b 1
)

@set PGPASSWORD=
@goto end

:environment
@Echo Please make sure that the enviroment variables are set correctly:
@Echo		IDEMPIERE_HOME	e.g. D:\idempiere
@Echo		ADEMPIERE_DB_NAME 	e.g. %ADEMPIERE_DB_NAME%
@Echo		ADEMPIERE_DB_SERVER 	e.g. dbserver.idempiere.org
@Echo		ADEMPIERE_DB_PORT 	e.g. 5432

:usage
@echo Usage:		%0 <AdempiereID> <AdempierePwd> <postgresUser> <PostgresPwd>
@echo Example:	%0 %ADEMPIERE_DB_USER% %ADEMPIERE_DB_PASSWORD% postgres %ADEMPIERE_DB_SYSTEM%

:end
