# workspace

[中文](README.md) · **English**

Portable data directory. `bin\env.bat` sets `ENV_WORKSPACE_HOME` here. Product default is `{IDEMPIERE_HOME}/data/workspace`; portable uses env vars. Leave SysConfig `AI_SOURCE_ROOTS` / `AI_KB_ROOT` / `AI_WORKSPACE_ROOT` / `MYAPPX_SOURCE_ROOTS` **empty**.

| Folder | Who writes it | Safe to edit? | Env |
|---|---|---|---|
| `sources/` | `bin\assemble\assemble-sources.bat` | No — replaced every assemble | `IDEMPIERE_MYAPPX_SOURCE_ROOTS` and `IDEMPIERE_AI_SOURCE_ROOTS` (same pack) |
| `kb/assembled/` | `bin\assemble\assemble-kb.bat` | No — replaced every assemble. Plugin `README*.md` plus `id-docs` markdown: `docs/{rest,site,skills}` | `IDEMPIERE_AI_KB_ROOT` (corpus root is `kb/`) |
| `kb/drop/` | You | Yes — extra markdown. Never crawled from the web | same |
| `scratch/` | Runtime temp files | Treat as ephemeral | `IDEMPIERE_AI_WORKSPACE_ROOT` |

KB vectors live in Postgres database `appx_kb`, not in these folders. After changing `kb/`, run **Rebuild AI Knowledge Index** (`POST /ai/v1/kb/ingest` or process `KBIngestProcess`). Ingest reads only `kb/assembled/` and `kb/drop/`.

`bin\clean.bat` deletes generated trees under this folder; this README stays.
