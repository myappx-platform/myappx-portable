# myappx-portable 安装说明

**中文** · [English](INSTALL.en.md)

捆绑 **JDK 21** 与 **PostgreSQL 18** 的便携版 AppxServer，无需在本机单独安装 Java / Postgres。本文面向**全新部署**。

更细的专题：Windows 服务见 [service/README-service.md](service/README-service.md)。

---

## 1. 环境

| 项 | 要求 |
|---|---|
| 系统 | Windows 10 / 11 x64 |
| 路径 | 固定绝对路径，安装后**不要移动**；避免空格与非 ASCII |
| 工具 | 系统自带 `tar.exe`（`%SystemRoot%\System32\tar.exe`） |
| 端口 | `15432`（PostgreSQL）、`18080` / `18443`（HTTP / HTTPS）、`12612`（OSGi console） |

交互式开发用根目录脚本；生产用 Windows 服务。**两种模式不可同机并用**（端口冲突）。

---

## 2. 准备离线包

zip **不进 Git**。把下列文件放到 `packages\`，文件名与 `packages\packages.ini` 一致（升级时只改 ini 里的 zip 名）：

| 变量 | 当前文件名 | 解压到 |
|---|---|---|
| `JDK_ZIP` | `microsoft-jdk-21.0.12.1-windows-x64.zip` | `runtime\jdk\` |
| `PGSQL_ZIP` | `postgresql-18.6-3-windows-x64-binaries.zip` | `runtime\pgsql\` |
| `APPX_ZIP` | `myappxserver-14.0.0.latest-win32.win32.x86_64.zip` | `appxserver\` |
| `VECTOR_ZIP` | `vector.v0.8.6-pg18.zip` | overlay 进 `runtime\pgsql\` |
| `PYTHON_ZIP` | `python-3.12.10-embed-amd64.zip` | `runtime\python\` |

`appxserver\` 产品包须含 seed（`data\seed\Adempiere_pg.jar`）。`conf\` 由 `bin\setup.bat` **覆盖**复制到 `appxserver\`，不要改解压出来的产品配置，改 `conf\` 后再跑 setup。

---

## 3. 全新安装（交互式）

在 portable **根目录**执行。

### 步骤 1 — 初始化

```bat
bin\setup.bat
```

一次性完成：

1. 按 `packages.ini` 解压 JDK / PostgreSQL / AppxServer / Python，并 overlay pgvector
2. 将 `conf\` **强制覆盖**复制到 `appxserver\`
3. `initdb` 初始化 `runtime\pgdata\`（SCRAM-SHA-256、UTF-8）

`initdb` 会把 superuser `postgres` 密码设为 **`postgres123`**（`--pwfile`），与 `conf\utils\myEnvironment.bat` 中 `ADEMPIERE_DB_SYSTEM` 一致。

`runtime\pgdata\` 已存在时会跳过 `initdb`，但仍会重新复制 `conf\`。

### 步骤 2 — 启动数据库

```bat
start-db.bat
```

监听 `localhost:15432`。日志：`runtime\logs\postgres.log`。

### 步骤 3 — 导入种子库

```bat
bin\db-import.bat
```

会暂停确认。随后：解压 seed → 重建库 `appx` / 用户 `appx` → 导入 dump → `AppxFinalizeDb`（schema `adempiere` 改名为 `appx`，并建只读角色 `appx_ro`）→ `RUN_SyncDB` → 签名 → 从 `appxserver\data\lang\zh_CN_System` 导入 zh_CN 并同步术语（该目录由 setup 从 `conf\data\lang` 覆盖而来）。语言导入日志：`runtime\logs\lang-import.log`。

已有业务 dump 时改用 `bin\db-restore.bat`（读 `appxserver\data\ExpDat.dmp`），不要再跑 seed 导入。恢复不会导入语言包。

已有库只想重灌 zh_CN、不删库时，用 `bin\db-lang.bat`（Postgres 须已启动）。改过 `conf\data\lang` 后先重新跑 `bin\setup.bat`。

### 步骤 4 — 启动应用

```bat
run-appxserver.bat
```

### 步骤 5 — 登录

| 服务 | URL |
|---|---|
| 应用 | https://localhost:18443/webui/ |
| Felix OSGi | https://localhost:18443/osgi/system/console/bundles |

种子库默认租户：**GardenWorld** / **GardenAdmin** 。系统级：**System** / **SuperUser**。

首次 HTTPS 为自签证书，浏览器需信任例外。

### 步骤 6 — 安装扩展

以 **System / SuperUser** 登录，打开 **System Admin → Extension Management**。

---

## 4. 默认账号与配置

来源：`conf\utils\myEnvironment.bat`（经 `bin\setup.bat` 落到 `appxserver\utils\`）。

| 用途 | 用户 | 密码 | 说明 |
|---|---|---|---|
| PostgreSQL superuser | `postgres` | `postgres123` | 由 `bin\setup.bat` `--pwfile` 设置 |
| 应用库 | `appx` / 库名 `appx` | `appx123` | JDBC `localhost:15432/appx` |
| 只读角色 | `appx_ro` | `appx_ro` | `AppxFinalizeDb` 创建 |
| 知识库角色 | `appx_kb` | `appx_kb` | 仅 `bin\setup-kb.bat` 使用 |

生产环境请改密码后重新 `bin\setup.bat`，并同步 `initdb` / 已有角色密码。

---

## 5. 日常命令

| 命令 | 作用 |
|---|---|
| `start-db.bat` / `stop-db.bat` | 交互式启停 PostgreSQL |
| `run-appxserver.bat` | 前台启动应用 |
| `bin\setup.bat` | 补齐 runtime、覆盖 conf、同步 PG 便携配置 |
| `bin\clean.bat` | 删安装产物，回到待安装（服务或交互式 Postgres 正在运行则先停） |
| `bin\reset.bat` | 重置：先输入 YES，然后 clean、setup、导入库、setup-kb；结束时停库并写报告 |
| `bin\db-import.bat` | 导入 iDempiere seed（会重建库），然后导入 zh_CN |
| `bin\db-lang.bat` | 在已有库上重灌 zh_CN 并同步术语（不删库；`db-import` 已包含） |
| `bin\db-restore.bat` | 从 `ExpDat.dmp` 恢复 |
| `bin\db-export.bat` | 导出 dump |
| `bin\db-sync.bat` | 只跑 migration（升级时用；全新 import 已包含） |
| `bin\check-update.bat` | 检查是否有更新的包（退出码 0=最新，2=有更新，1=出错） |
| `bin\update.bat` | 按 `packages\`（或联网清单）升级，自动备份、迁移库、签名、重灌 zh_CN |
| `bin\rollback-update.bat` | 回退到上一次升级前的 `appxserver.bak-<stamp>` |
| `bin\setup-kb.bat` | 标准 KB：建 `appx_kb` + pgvector，并组装 `workspace\kb` / `workspace\sources`（Postgres 须已启动；旁路仓库或 Python 缺失则跳过组装） |
| `bin\assemble\assemble-kb.bat` | 只重装 `workspace\kb\`（需旁边 `myappx-plugins`；`id-docs` 可选） |
| `bin\assemble\assemble-sources.bat` | 只重装 `workspace\sources\`（需旁边 `myappx-server` / `myappx-plugins`） |

### 无人值守重置

`bin\reset.bat` 开始前要输入 `YES`。确认之后不再暂停：删除安装产物、重新 setup、导入种子库并执行 `setup-kb`。结束时 PostgreSQL 是停止的，不会启动应用。

报告写在 `runtime\logs\reset-report.txt`。若在 `setup` 之前失败，报告留在 `%TEMP%\myappx-reset-report.txt`，控制台会打印实际路径。

Windows 服务正在运行，或端口 `18080` / `18443` 仍在监听时，脚本直接失败，不删除文件。先执行 `service\services.bat stop`，或停掉 `run-appxserver.bat`。

---

## 6. Windows 服务（生产）

交互式初始化并导入数据库之后：

1. 将 [WinSW v2.12.0 x64](https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe) 放到 `service\winsw\WinSW-x64.exe`
2. **管理员**运行 `service\install-services.bat`

注册 `MyAppx Database` 与 `MyAppx Application`（手动、安装后不启动）。日常：`service\services.bat start|stop|status`。

同一台机器不要再跑 `start-db.bat` + `run-appxserver.bat`。细节见 [service/README-service.md](service/README-service.md)。

---

## 7. 目录要点

```
myappx-portable/
├── README.md / README.en.md
├── INSTALL.zh-CN.md / INSTALL.en.md
├── start-db.bat / stop-db.bat / run-appxserver.bat
├── bin\                 # init、clean、db-*、setup-*、assemble\、install-packages、env、update
├── packages\            # 离线 zip + packages.ini（+ 可选 packages.json）
├── runtime\jdk          # JAVA_HOME
├── runtime\pgsql        # PostgreSQL 程序
├── runtime\python       # embeddable Python（assemble）
├── runtime\pgdata       # 数据库文件
├── runtime\logs         # PostgreSQL / WinSW 日志
├── runtime\backup       # bin\update.bat 的 dump 与扩展 jar
├── workspace\           # sources / kb / scratch（说明见 workspace/README.md）
├── appxserver\          # 产品（gitignore；由 zip + conf 覆盖生成）
├── conf\                # 配置源（init 覆盖到 appxserver；`data\lang` 为 zh_CN 翻译包）
└── service\             # Windows 服务
```

不要手改 `runtime\pgdata\postgresql.portable.conf`；改 `conf\pg\postgresql.portable.conf` 后重新 `bin\setup.bat`，再重启数据库。

---

## 8. 升级（update）

update 会把整棵树一起推进：runtime 包、产品、数据库与语言包。所需文件都放在 `packages\` 即可，**不依赖网络**。
### 8.1 检查更新

```bat
bin\check-update.bat
```

打印每个组件的当前版本与可用版本。退出码 `0` = 已最新，`2` = 有更新，`1` = 检查失败。

版本从哪来：

| 组件 | 版本来源 |
|---|---|
| AppxServer | zip 内 `artifacts.xml` 的 `p2.timestamp` 与 `org.adempiere.server` 版本 |
| JDK / PostgreSQL / Python / pgvector | zip 文件名中的版本 |

产品包名恒为 `myappxserver-14.0.0.latest-*.zip`，文件名分不出两次构建，**只有包内构建戳能区分**。

### 8.2 执行升级

> **update 只支持便携模式。** 应用用 `run-appxserver.bat` 启动，PostgreSQL 用 `start-db.bat` 启动。
> 如果 `MyAppx Database` / `MyAppx Application` 服务正在运行，update 会直接拒绝，请先 `service\services.bat stop`。

```bat
bin\update.bat
```

先打印计划，输入 `YES` 后：

1. preflight：端口空闲、磁盘至少 6 GB、无运行中的 MyAppx 服务
2. backup：`pg_dump` 到 `runtime\backup\<stamp>\appx.dump`，另存 `globals.sql`、`conf\`、`packages.ini`、已装客户化 bundle 与 `installed.json`
3. 停 PostgreSQL
4. 并排解压 JDK / PostgreSQL / Python（并 overlay pgvector）后切换，旧目录改名 `<name>.bak-<stamp>`
5. 解压产品到 `appxserver.new-<stamp>`，覆盖 `conf\`，**只生成待重装清单、不写任何加载清单**，然后改名为 `appxserver`（旧的变 `appxserver.bak-<stamp>`）
6. 启动 PostgreSQL，依次跑 `RUN_SyncDB`、`sign-database-build-alt`、`bin\db-lang.bat`
7. 校验 `AD_System`、迁移条数、`bundles.info`、扩展状态
8. 改写 `packages\packages.ini` 的 zip 名，清理超期备份
9. **结束时停掉 PostgreSQL**（无论成功还是失败）

### 客户化 bundle 的处理方式

升级**不会**把客户化 bundle 写进新树，只做两件事：

- 备份 jar 到 `runtime\backup\<stamp>\extensions\`（回滚与举证）
- 生成待重装清单 `runtime\logs\update\<stamp>\extensions-to-reinstall.json`

判定“哪些是客户化”的基线取自**产品 zip 内的 `bundles.info`**，不是当前安装树。

**升级后必须通过 Extension Management 重装这些扩展**（应用启动后，System Admin → Extension Management，逐个 Install）。原因：

Extension Management 用 `installBundle(downloadUrl)` 安装扩展，其 OSGi **location 是 HTTP URL**；而写进 `plugins\` + `bundles.info` 的 jar，location 是本地路径。同一个 symbolic name 出现两个 location 时，OSGi 的 singleton 规则只能选中一个，另一个直接解析失败：

```
Could not resolve module: org.idempiere.myappx.plugin.aic
  Another singleton bundle selected: version="1.0.1.202611181609"
```

所以自动搬运 jar 会破坏 Extension Management 的升级与卸载能力，update 因此改为“只备份、不代装”。

报告：`runtime\logs\update-report.txt`；分步日志：`runtime\logs\update\<stamp>\`。

升级完成后按顺序启动即可：

```bat
start-db.bat
run-appxserver.bat
```

然后用 Extension Management 重装清单里的扩展。

常用参数：

| 参数 | 作用 |
|---|---|
| `-CheckOnly` | 只打印计划 |
| `-Offline` | 忽略 `conf\update.ini` 里的 base URL |
| `-SkipBackup` | 跳过 `pg_dump`（不建议） |
| `-SkipDbSync` | 不跑 `RUN_SyncDB`，之后手动 `bin\db-sync.bat` |
| `-SkipLang` | 不重灌 zh_CN |
| `-AllowPgMajor` | 允许 PostgreSQL 大版本升级 |
| `-Resume` | 上次升级在换包后中断时，只补跑数据库阶段 |
| `-Force` | 对已是最新的组件强制再走一遍 |

### 8.3 联网清单（可选）

`conf\update.ini` 可让 update 走清单，而不是只用已下载的包：

```ini
UPDATE_BASE_URL=https://example.com/myappx-portable
UPDATE_CHANNEL=latest
UPDATE_MANIFEST=packages.json
UPDATE_OFFLINE=0
UPDATE_KEEP_BACKUPS=3
```

在 zip 旁边生成清单：

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File bin\update\make-manifest.ps1 -BaseUrl https://example.com/myappx-portable
```

把 `packages.json` 与 zip 上传到该 URL。配了 base URL 时，`bin\update.bat` 只下载比已装版本更新的组件、校验 `sha256`；清单拉不到就退回本地 `packages\`。

### 8.4 PostgreSQL 大版本

PostgreSQL 大版本变化（例如 18 → 19）需要 `pg_upgrade`，未加 `-AllowPgMajor` 会被拒绝。加了之后：

1. 把 `runtime\pgdata` 复制到 `runtime\backup\<stamp>\pgdata`
2. 用同样的 SCRAM/UTF-8 参数 `initdb` 到 `runtime\pgdata.new`
3. 先 `pg_upgrade --check`（失败则原集群完全不动），再跑真正的 `pg_upgrade`
4. `pgdata` 改名 `pgdata.bak-<stamp>`，`pgdata.new` 改名 `pgdata`

旧 PostgreSQL 程序保留为 `runtime\pgsql.bak-<stamp>`，因为 `pg_upgrade` 需要它。

### 8.5 回退

```bat
bin\rollback-update.bat                       :: 用最新备份，库保持已迁移
bin\rollback-update.bat 20261115-2312         :: 指定 stamp
bin\rollback-update.bat 20261115-2312 -RestoreDb
```

回退会把 `appxserver.bak-<stamp>`（以及存在的 `runtime\*.bak-<stamp>`）换回来。migration 脚本无法用代码回滚，只有 `-RestoreDb` 能把 schema 退回升级前：它会丢弃并按 `runtime\backup\<stamp>\appx.dump` 重建库 `appx`。

---

## 9. 常见问题

| 现象 | 处理 |
|---|---|
| `packages.ini` / zip 缺失 | 把对应 zip 放入 `packages\`，文件名与 ini 一致 |
| `initdb` 密码与导入不符 | superuser 须为 `postgres123`，或改 `conf\utils\myEnvironment.bat` 后重跑 `bin\setup.bat` |
| 端口被占用 | `stop-db.bat`，结束残留 `java.exe`；不要同时开服务模式 |
| 导入失败 / lock 不足 | `bin\setup.bat` 会把 `max_locks_per_transaction=256` 写入 PG；改完须重启数据库 |
| 移动目录后服务失败 | 管理员 `service\uninstall-services.bat`，在新路径再 `install-services.bat` |
| 想清空重装库 | 停库后删除 `runtime\pgdata\`，再 `bin\setup.bat` → `start-db.bat` → `bin\db-import.bat` |
| 退回待安装 | `bin\clean.bat`（输入 YES）。Windows 服务正在运行时先 `service\services.bat stop` |
