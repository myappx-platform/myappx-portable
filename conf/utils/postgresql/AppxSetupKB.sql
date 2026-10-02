-- Database: appx_kb  (never run against ERP database appx)
-- Schema:   appx     (tables kb_*; owner is ADEMPIERE_DB_KB_USER, typically appx_kb)
-- Tables:   kb_*
-- vector / pg_trgm extensions must already exist in public.
--
-- Requires psql:  -v db_user=appx_kb
-- Source: myappx-portable/conf/utils/postgresql/AppxSetupKB.sql
-- Runtime after setup.bat: {IDEMPIERE_HOME}/utils/postgresql/AppxSetupKB.sql

\if :{?db_user}
\else
\echo AppxSetupKB.sql: missing -v db_user
\quit 1
\endif

\encoding UTF8

CREATE SCHEMA IF NOT EXISTS appx AUTHORIZATION :"db_user";
SET search_path TO appx, public;

CREATE TABLE IF NOT EXISTS kb_source (
    source_id       serial PRIMARY KEY,
    root_path       text NOT NULL,
    file_glob       text,
    last_sync       timestamptz
);

CREATE TABLE IF NOT EXISTS kb_document (
    document_id     serial PRIMARY KEY,
    path            text NOT NULL UNIQUE,
    layer           text NOT NULL DEFAULT 'project',
    title           text,
    content_hash    text,
    mtime           timestamptz,
    updated         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS kb_chunk (
    chunk_id        serial PRIMARY KEY,
    document_id     integer NOT NULL REFERENCES kb_document(document_id) ON DELETE CASCADE,
    chunk_index     integer NOT NULL DEFAULT 0,
    heading_path    text,
    text            text NOT NULL,
    content_hash    text,
    tsv             tsvector,
    embedding       vector(1024),
    embed_status    text NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS kb_alias (
    alias_id        serial PRIMARY KEY,
    alias           text NOT NULL,
    alias_norm      text NOT NULL,
    entity_type     text NOT NULL,
    canonical       text NOT NULL,
    UNIQUE (alias_norm, entity_type)
);

CREATE TABLE IF NOT EXISTS kb_embed_cache (
    content_hash    text PRIMARY KEY,
    embedding       vector(1024) NOT NULL,
    created         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS kb_chunk_tsv_idx ON kb_chunk USING gin (tsv);
CREATE INDEX IF NOT EXISTS kb_chunk_embed_idx ON kb_chunk USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS kb_chunk_text_trgm_idx ON kb_chunk USING gin (text gin_trgm_ops);
CREATE INDEX IF NOT EXISTS kb_document_path_trgm_idx ON kb_document USING gin (path gin_trgm_ops);
CREATE INDEX IF NOT EXISTS kb_document_title_trgm_idx ON kb_document USING gin (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS kb_alias_norm_idx ON kb_alias (alias_norm);
CREATE INDEX IF NOT EXISTS kb_document_layer_idx ON kb_document (layer);

INSERT INTO kb_alias (alias, alias_norm, entity_type, canonical)
VALUES
    ('SysConfig', 'sysconfig', 'table', 'AD_SysConfig'),
    ('系统配置', '系统配置', 'table', 'AD_SysConfig'),
    ('系统配置器', '系统配置器', 'table', 'AD_SysConfig'),
    ('Shipment', 'shipment', 'table', 'M_InOut'),
    ('发货', '发货', 'table', 'M_InOut'),
    ('客户发货', '客户发货', 'table', 'M_InOut'),
    ('物料入库', '物料入库', 'table', 'M_InOut'),
    ('M_InOut', 'm_inout', 'table', 'M_InOut'),
    ('销售订单', '销售订单', 'table', 'C_Order'),
    ('业务伙伴', '业务伙伴', 'table', 'C_BPartner'),
    ('销售发票', '销售发票', 'table', 'C_Invoice'),
    ('付款', '付款', 'table', 'C_Payment'),
    ('仓库', '仓库', 'table', 'M_Warehouse'),
    ('产品主数据', '产品主数据', 'table', 'M_Product'),
    ('ODT', 'odt', 'plugin', 'org.idempiere.myappx.plugin.odt')
ON CONFLICT (alias_norm, entity_type) DO NOTHING;
