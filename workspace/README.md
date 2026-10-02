# workspace

**中文** · [English](README.en.md)

便携版数据目录。`bin\env.bat` 设 `ENV_WORKSPACE_HOME` 指向这里。产品默认是 `{IDEMPIERE_HOME}/data/workspace`；portable 用环境变量，SysConfig 的 `AI_SOURCE_ROOTS` / `AI_KB_ROOT` / `AI_WORKSPACE_ROOT` / `MYAPPX_SOURCE_ROOTS` **留空**。

| 目录 | 谁写入 | 能否手改 | 环境变量 |
|---|---|---|---|
| `sources/` | `bin\assemble\assemble-sources.bat` | 否 — 每次装配覆盖 | `IDEMPIERE_MYAPPX_SOURCE_ROOTS`、`IDEMPIERE_AI_SOURCE_ROOTS`（同一份包） |
| `kb/assembled/` | `bin\assemble\assemble-kb.bat` | 否 — 每次装配覆盖。plugin `README*.md` 与 `id-docs`：`docs/{rest,site,skills}` | `IDEMPIERE_AI_KB_ROOT`（语料根是 `kb/`） |
| `kb/drop/` | 你 | 是 — 额外 markdown，不从网上爬 | 同上 |
| `scratch/` | 运行时临时文件 | 当临时目录 | `IDEMPIERE_AI_WORKSPACE_ROOT` |

知识库向量在独立 Postgres 库 `appx_kb`，不在这些目录里。改完 `kb/` 后跑 **Rebuild AI Knowledge Index**（`POST /ai/v1/kb/ingest` 或进程 `KBIngestProcess`）。ingest 只扫 `kb/assembled/` 与 `kb/drop/`。

`bin\clean.bat` 只删上述生成物，不删本 README。
