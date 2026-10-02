-- Portable: rename seed schema adempiere -> application user schema,
-- drop leftover adempiere role, ensure read-only login.
--
-- Idempotent. Requires psql variables from AppxFinalizeDb.bat:
--   -v db_ro_user=... -v db_ro_password=...
-- Application user / database / schema come from the connected session
-- (ADEMPIERE_DB_USER / ADEMPIERE_DB_NAME), not hardcoded names.

\if :{?db_ro_user}
\else
\echo AppxFinalizeDb.sql: missing -v db_ro_user
\quit 1
\endif

\if :{?db_ro_password}
\else
\echo AppxFinalizeDb.sql: missing -v db_ro_password
\quit 1
\endif

CREATE OR REPLACE FUNCTION pg_temp.appx_finalize_db(p_ro_user text, p_ro_password text)
RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
  db_user text := current_user;
  db_name text := current_database();
  db_schema text := current_user;
BEGIN
  IF p_ro_user IS NULL OR length(trim(p_ro_user)) = 0 THEN
    RAISE EXCEPTION 'read-only user is empty';
  END IF;
  IF p_ro_password IS NULL OR length(p_ro_password) = 0 THEN
    RAISE EXCEPTION 'read-only password is empty';
  END IF;
  IF lower(p_ro_user) = lower(db_user) THEN
    RAISE EXCEPTION 'read-only user (%) must differ from application user (%)', p_ro_user, db_user;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'adempiere') THEN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'adempiere') THEN
      EXECUTE format('REASSIGN OWNED BY adempiere TO %I', db_user);
    END IF;
    EXECUTE format('ALTER SCHEMA adempiere RENAME TO %I', db_schema);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = db_schema) THEN
    RAISE EXCEPTION 'schema % not found after finalize', db_schema;
  END IF;

  EXECUTE format('ALTER ROLE %I SET search_path TO %I, pg_catalog', db_user, db_schema);

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'adempiere')
     AND lower(db_user) <> 'adempiere' THEN
    EXECUTE 'DROP OWNED BY adempiere';
    EXECUTE 'DROP ROLE adempiere';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = p_ro_user) THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', p_ro_user, p_ro_password);
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', p_ro_user, p_ro_password);
  END IF;

  EXECUTE format('ALTER ROLE %I NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION', p_ro_user);
  EXECUTE format('ALTER ROLE %I SET search_path TO %I, pg_catalog', p_ro_user, db_schema);
  EXECUTE format('ALTER ROLE %I SET default_transaction_read_only = on', p_ro_user);
  EXECUTE format('ALTER ROLE %I SET statement_timeout = %L', p_ro_user, '30s');
  EXECUTE format('ALTER ROLE %I SET idle_in_transaction_session_timeout = %L', p_ro_user, '60s');

  EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', db_name, p_ro_user);
  EXECUTE format('GRANT USAGE ON SCHEMA %I TO %I', db_schema, p_ro_user);
  EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO %I', db_schema, p_ro_user);
  EXECUTE format('GRANT SELECT ON ALL SEQUENCES IN SCHEMA %I TO %I', db_schema, p_ro_user);
  EXECUTE format(
    'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT SELECT ON TABLES TO %I',
    db_user, db_schema, p_ro_user);
  EXECUTE format(
    'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT SELECT ON SEQUENCES TO %I',
    db_user, db_schema, p_ro_user);
END
$fn$;

SELECT pg_temp.appx_finalize_db(:'db_ro_user', :'db_ro_password');
DROP FUNCTION pg_temp.appx_finalize_db(text, text);
