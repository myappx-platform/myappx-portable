# Windows Service 部署指南

将 `appxserver-portable` 以 **Windows 服务**方式常驻运行（手动启动、无需登录桌面）。

交互式开发仍使用根目录 `start-db.bat` + `run-appxserver.bat`；**服务模式与交互模式二选一**，不可同机并用（端口冲突）。

---

## 1. 方案概述

注册两个 Windows 服务，AppxServer 依赖 PostgreSQL：

| 组件 | Windows 服务名 | 显示名 | 实现 | 端口 |
|------|----------------|--------|------|------|
| PostgreSQL | `MyAppx Database` | （同左） | `pg_ctl register` | 15432 |
| AppxServer | `MyAppx Application` | MyAppx Application | WinSW → `service-appxserver.bat` | 18080 / 18443 |

启动链路：

1. Windows 启动 `MyAppx Database` → `postgres -D runtime\pgdata -F -p 15432`
2. Windows 启动 `MyAppx Application`（WinSW）→ `cmd /c service-appxserver.bat`
3. `service-appxserver.bat` 设置环境 → `pg_isready` 等待数据库（最长 120 秒）→ `call appxserver.bat`

要点：

- Service **复用** `appxserver/appxserver.bat`（含 `IDEMPIERE_EXTENSION_REPOSITORY` 等 VM 参数），与交互式启动一致
- 统一使用 **`java.exe`**（交互式与服务模式相同），便于 WinSW 捕获 Service 进程生命周期
- 服务运行在 Session 0，**不**执行 `bin\env.bat`，改用 `service-env.bat` 设置绝对路径
- 安装时按实际部署路径生成 `winsw/AppxServer.xml`

---

## 2. 目录与脚本

```
appxserver-portable/
├── bin\env.bat                  # 交互式环境（服务不使用）
├── start-db.bat / stop-db.bat   # 交互式数据库启停
├── run-appxserver.bat           # 交互式启动
├── runtime\jdk / runtime\pgsql  # 捆绑 JDK / PostgreSQL
├── runtime\pgdata               # 数据库文件
├── runtime\logs                 # PostgreSQL / WinSW 日志
├── packages\                    # 离线 zip + packages.ini
├── workspace\                   # sources / kb / scratch
└── service/
    ├── service-env.bat          # 服务名、端口、路径（唯一配置入口）
    ├── service-appxserver.bat   # WinSW 入口（前台 java）
    ├── install-services.bat     # 安装（管理员；不启动）
    ├── uninstall-services.bat   # 卸载（管理员）
    ├── services.bat             # 日常：start | stop | status
    ├── clean-for-copy.bat       # 复制到其他机器前清理生成文件
    ├── README-service.md        # 本文档
    └── winsw/
        ├── AppxServer.xml.template   # WinSW 配置模板（提交 Git）
        ├── WinSW-x64.exe             # 安装前手工放入（Git 忽略）
        ├── AppxServer.exe            # 安装时复制生成（Git 忽略）
        └── AppxServer.xml            # 安装时按路径生成（Git 忽略）
```

### 脚本说明

| 脚本 | 权限 | 作用 |
|------|------|------|
| `service-env.bat` | — | 定义 `SERVICE_NAME_PG`、`SERVICE_ID_APP`、`SERVICE_DISPLAY_APP`、`PG_PORT` 及 `JAVA_HOME` / `PGSQL_HOME` / `PGDATA` / `ENV_APPXSERVER_HOME` |
| `service-appxserver.bat` | — | WinSW 入口：等待 PostgreSQL 就绪后 `call appxserver.bat` |
| `install-services.bat` | 管理员 | 校验环境 → 准备 WinSW → 生成 XML → 注册双服务（不启动） |
| `uninstall-services.bat` | 管理员 | 停止并移除双服务（不删 `runtime/pgdata/`、`appxserver/`） |
| `services.bat` | — | `start` / `stop` / `status` |
| `clean-for-copy.bat` | — | 删除机器相关的生成文件，便于打包迁移 |

---

## 3. 前提条件

1. **固定绝对路径**：例如 `D:\MyAppx\appxserver-portable`。安装后**勿移动**；迁移需先卸载再在新路径重装。
2. **环境已初始化**：已执行 `bin\setup.bat`，且已完成 `bin\db-import.bat` 或 `bin\db-restore.bat`（或复制了含数据的 `runtime\pgdata\`）。
3. **运行时完整**：`appxserver/plugins/`、`jettyhome/` 等存在。
4. **管理员权限**：安装/卸载必须以管理员运行 CMD 或 PowerShell。
5. **WinSW（离线）**：将 `WinSW-x64.exe` 放入 `service\winsw\`。**安装过程不联网**。

### 首次部署顺序（安装服务之前）

在 `appxserver-portable` 根目录完成交互式初始化：

| 步骤 | 命令 | 说明 |
|------|------|------|
| 0 | （离线准备） | 将 `WinSW-x64.exe` 放入 `service\winsw\` |
| 1 | `bin\setup.bat` | 复制 `conf/` → `appxserver/`；初始化 `runtime\pgdata\` |
| 2 | `start-db.bat` | 启动数据库（导入时需要） |
| 3 | `bin\db-import.bat` 或 `bin\db-restore.bat` | 导入种子库或业务库 |
| 4 | `stop-db.bat` | 停止数据库（可选，安装脚本会注册为服务） |
| 5 | `service\install-services.bat` | 注册 Windows 服务（不启动） |

若 `runtime\pgdata\` 已含业务数据（例如从其他机器复制），可跳过步骤 1–4，直接执行步骤 5。

---

## 4. 安装

### 4.1 离线准备 WinSW

在有网络的机器下载 [WinSW v2.12.0 x64](https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe)，复制到：

```
appxserver-portable\service\winsw\WinSW-x64.exe
```

也可直接放置已改名的 `AppxServer.exe`（跳过复制步骤）。可随离线安装包一并分发。

### 4.2 执行安装

以**管理员**打开命令提示符：

```bat
cd C:\path\to\appxserver-portable\service
install-services.bat
```

脚本依次（**全程离线**）：

1. 校验 JDK、`runtime\pgsql`、`runtime\pgdata`、`appxserver/plugins`
2. 检查 `winsw\WinSW-x64.exe`，复制为 `winsw\AppxServer.exe`（若已存在则跳过）
3. 按当前路径生成 `winsw/AppxServer.xml`
4. `pg_ctl register` 注册 `MyAppx Database`（手动启动，端口 15432）
5. `AppxServer.exe install` 注册 MyAppx Application 服务

安装后服务保持停止。启动：`service\services.bat start`。启动后可访问：

| 服务 | URL |
|------|-----|
| 应用主页 | https://localhost:18443/ |
| Felix OSGi 控制台 | https://localhost:18443/osgi/system/console/bundles |

---

## 5. 日常管理

```bat
service\services.bat start
service\services.bat stop
service\services.bat status
```

也可使用 `services.msc` 或：

```bat
net start "MyAppx Database"
net start "MyAppx Application"
net stop "MyAppx Application"
net stop "MyAppx Database"
```

**停止顺序**：先 MyAppx Application，再 MyAppx Database（`services.bat stop` 已按此顺序）。

---

## 6. 卸载

以**管理员**运行：

```bat
service\uninstall-services.bat
```

停止并移除 WinSW 与 `pg_ctl` 注册的服务。**不会删除** `runtime\pgdata\` 与 `appxserver/` 数据。

---

## 7. 复制到其他机器

### 7.1 源机器（复制前）

1. 停止服务：`service\services.bat stop`（或 `uninstall-services.bat` 若源机不再使用）
2. 确认 PostgreSQL 已正常关闭（`runtime\pgdata\` 中无活跃 `postmaster.pid`）
3. 清理生成文件（可选，推荐）：

```bat
service\clean-for-copy.bat
```

### 7.2 迁移包应包含

```
appxserver-portable/
├── runtime/jdk/
├── runtime/pgsql/
├── runtime/pgdata/
├── appxserver/
├── service/
│   ├── *.bat
│   └── winsw/
│       ├── AppxServer.xml.template
│       └── WinSW-x64.exe
└── ...
```

### 7.3 可删除的生成文件（目标机会重建）

| 文件 | 原因 |
|------|------|
| `service/winsw/AppxServer.xml` | 含源机器绝对路径，`install-services.bat` 会重新生成 |
| `service/winsw/AppxServer.exe` | `WinSW-x64.exe` 的副本，安装时自动复制 |
| `runtime/logs/AppxServer*.log` | 运行日志 |
| `runtime/logs/postgres.log` | 交互式数据库日志 |

**必须保留**：`AppxServer.xml.template`、`WinSW-x64.exe`。

### 7.4 目标机器（安装）

1. 复制到**最终路径**（安装后勿移动）
2. 确认端口 15432 / 18080 / 18443 未被占用
3. 不要同时运行交互式 `start-db.bat` + `run-appxserver.bat`
4. 以**管理员**运行：

```bat
cd D:\path\to\appxserver-portable\service
install-services.bat
```

路径可以不同于源机器；`install-services.bat` 会按目标机实际路径生成配置。**不要**直接使用源机器复制的 `AppxServer.xml`。

---

## 8. 升级 portable 包

1. `service\services.bat stop`
2. 替换/更新文件（保留 `runtime\pgdata\`）
3. 若版本跨度大，停止状态下运行 `bin\db-sync.bat`（需临时启动 PostgreSQL）
4. `service\services.bat start`

若安装路径变更：先 `uninstall-services.bat`，移动目录后在新路径执行 `install-services.bat`。

---

## 9. 配置

在 `service-env.bat` 中修改：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SERVICE_NAME_PG` | `MyAppx Database` | PostgreSQL Windows 服务名 |
| `SERVICE_DESC_PG` | `MyAppx Database Server` | PostgreSQL 服务描述（`services.msc` 中显示） |
| `SERVICE_ID_APP` | `MyAppx Application` | AppxServer Windows 服务名（WinSW `<id>`，`net start` 用此名） |
| `SERVICE_DISPLAY_APP` | `MyAppx Application` | 服务管理器中显示的名称 |
| `SERVICE_DESC_APP` | `MyAppx Application Server` | WinSW 服务描述 |
| `PG_PORT` | `15432` | PostgreSQL 端口 |

修改 `PG_PORT` 后还需同步：

- `appxserver/utils/myEnvironment.bat`（`ADEMPIERE_DB_PORT`、`ADEMPIERE_DB_URL`）
- `start-db.bat`（交互模式）
- `appxserver/idempiere.properties`（若存在 JDBC 连接串）

然后重新以管理员运行 `install-services.bat`。

应用端口（18080 / 18443）在 `appxserver/utils/myEnvironment.bat` 与 Jetty 配置中，与 service 脚本无直接绑定。

---

## 10. 日志

| 组件 | 位置 |
|------|------|
| WinSW 标准输出 | `runtime/logs/AppxServer.out.log` |
| WinSW 错误输出 | `runtime/logs/AppxServer.err.log` |
| WinSW 包装器 | `runtime/logs/AppxServer.wrapper.log` |
| PostgreSQL（服务模式） | `runtime/pgdata/log/` |
| PostgreSQL（交互模式） | `runtime/logs/postgres.log` |
| Java / OSGi / Jetty | `appxserver/logs/` |

服务启动失败时，优先查看 `AppxServer.err.log` 与 `appxserver/logs/`。

---

## 11. 注意事项

### 部署模式互斥

| 模式 | 启动方式 |
|------|----------|
| 服务模式 | `install-services.bat` 后由 Windows 管理 |
| 交互模式 | `start-db.bat` + `run-appxserver.bat` 或 myappx-desktop 自启动 |

同一台机器**不能同时**使用两种模式。冲突端口：15432、18080、18443。

### 路径与环境

- 服务**不会**执行 `bin\env.bat`。
- 所有路径由 `service-env.bat` 基于 `service/` 的父目录推导。
- 安装后移动目录会导致服务失败，需卸载后在新路径重装。

### 运行账户

- PostgreSQL 默认以安装时当前 Windows 用户注册；WinSW 默认 Local System。
- 生产环境如需专用服务账户，需手动调整 `pg_ctl register -U` 及 WinSW XML 中的 `<serviceaccount>`。

### 优雅停止

- WinSW 停止超时 **120 秒**（`stoptimeout`），以便 OSGi/Jetty 卸载。
- 避免在任务管理器中强杀 `java.exe`。

---

## 12. 故障排查

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| 提示未初始化数据库 | 未运行 `bin\setup.bat` | 先初始化再安装 |
| AppxServer 启动失败 | 数据库未就绪 | 查 PostgreSQL 是否 Running；看 `wait-for-db` 超时与 `AppxServer.err.log` |
| 端口被占用 | 交互式实例仍在运行 | `stop-db.bat`、结束残留 `java.exe`，或 `services.bat stop` |
| WinSW 未找到 | 未放置 `WinSW-x64.exe` | 放入 `service\winsw\` 后重试 |
| 移动目录后失败 | XML 中写死旧路径 | `uninstall-services.bat` → 新路径 `install-services.bat` |
| `MyAppx Database` 仍指向 `workspace\pgdata` | 布局迁移后未重注册 | 管理员重跑 `service\install-services.bat`（`pg_ctl register -D runtime\pgdata`） |
| 复制后路径错误 | 使用了源机器 `AppxServer.xml` | 删除后重新 `install-services.bat` |
| 权限错误 | 非管理员安装 | 以管理员重新运行 |
| `runtime\pgdata` 无法启动 | 复制前未正常停库 | 确认无 `postmaster.pid`；检查目录权限 |

```bat
service\services.bat status
sc query "MyAppx Database"
sc query "MyAppx Application"
```

---

## 13. 与 myappx-desktop 的关系

- Desktop 打包时将 `appxserver-portable` 打入 zip，解压后以 `run-appxserver.bat` 交互启动。
- **服务器 + Desktop 客户端**：服务器安装 Windows 服务；Desktop 仅作浏览器壳连接远程 URL。**不要**在服务器上同时启用 Desktop 自带的 portable 自启动。

源码位置：`myappx-server/appxserver-portable`。
