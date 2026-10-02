@Echo	ADempiere Database Import (portable)

@Rem Portable override: restore ExpDat.dmp then finalize schema/role (%ADEMPIERE_DB_USER% / %ADEMPIERE_DB_RO_USER%).

@Echo	Importing ADempiere DB from %IDEMPIERE_HOME%\data\ExpDat.dmp (%ADEMPIERE_DB_NAME%)

@if (%IDEMPIERE_HOME%) == () goto environment
@if (%ADEMPIERE_DB_NAME%) == () goto environment
@if (%ADEMPIERE_DB_SERVER%) == () goto environment
@if (%ADEMPIERE_DB_PORT%) == () goto environment
@Rem Must have parameters systemAccount AdempiereID AdempierePwd PostgresPwd
@if (%1) == () goto usage
@if (%2) == () goto usage
@if (%3) == () goto usage
@if (%4) == () goto usage

@if "%ADEMPIERE_DB_SYSTEM_USER%" == "" @set ADEMPIERE_DB_SYSTEM_USER=postgres
@set PGPASSWORD=%4
@echo -------------------------------------
@echo Re-Create user and database
@echo -------------------------------------
@psql -q -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -d postgres -U %ADEMPIERE_DB_SYSTEM_USER% -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '%ADEMPIERE_DB_NAME%' AND pid <> pg_backend_pid();"
@dropdb -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %ADEMPIERE_DB_SYSTEM_USER% %ADEMPIERE_DB_NAME%
@dropuser -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %ADEMPIERE_DB_SYSTEM_USER% %2
@set ADEMPIERE_CREATE_ROLE_SQL=CREATE ROLE %2 SUPERUSER LOGIN PASSWORD '%3'
@psql -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -U %ADEMPIERE_DB_SYSTEM_USER% -c "%ADEMPIERE_CREATE_ROLE_SQL%"
@set ADEMPIERE_CREATE_ROLE_SQL=

@set PGPASSWORD=%3
@createdb -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -E UNICODE -O %2 -U %2 %ADEMPIERE_DB_NAME%

@echo -------------------------------------
@echo Import ExpDat.dmp
@echo -------------------------------------
@psql -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -d %ADEMPIERE_DB_NAME% -U %2 -c "drop schema sqlj cascade"
@set ADEMPIERE_ALTER_ROLE_SQL="ALTER ROLE %2 SET search_path TO adempiere, pg_catalog"
@psql -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -d %ADEMPIERE_DB_NAME% -U %2 -c "%ADEMPIERE_ALTER_ROLE_SQL%"
@psql -h %ADEMPIERE_DB_SERVER% -p %ADEMPIERE_DB_PORT% -d %ADEMPIERE_DB_NAME% -U %2 -f %IDEMPIERE_HOME%/data/ExpDat.dmp
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
@Echo Please make sure that the environment variables are set correctly:
@Echo		IDEMPIERE_HOME	e.g. D:\ADEMPIERE2
@Echo		ADEMPIERE_DB_NAME 	e.g. %ADEMPIERE_DB_NAME%
@Echo		ADEMPIERE_DB_SERVER 	e.g. dbserver.adempiere.org
@Echo		ADEMPIERE_DB_PORT 	e.g. 5432 or 1521

:usage
@echo Usage:		%0 <systemAccount> <AdempiereID> <AdempierePwd> <postgresPwd>
@echo Example:	%0 postgres %ADEMPIERE_DB_USER% %ADEMPIERE_DB_PASSWORD% %ADEMPIERE_DB_SYSTEM%

:end
