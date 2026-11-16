# myappx-portable

**中文** · [English](README.en.md)

捆绑 JDK 21 与 PostgreSQL 的便携版 AppxServer。配置源在 `conf\`，运行时在 `runtime\` / `appxserver\`，脚本统一走 `bin\env.bat`。

| 文档 | 内容 |
|------|------|
| [INSTALL.zh-CN.md](INSTALL.zh-CN.md) | 全新安装、离线包、导入库、扩展、账号与日常命令 |
| [service/README-service.md](service/README-service.md) | Windows 服务（手动启动；与交互模式互斥） |
| [workspace/README.md](workspace/README.md) | `sources` / `kb` / `scratch` |

```
myappx-portable/
├── README.md / README.en.md
├── INSTALL.zh-CN.md / INSTALL.en.md
├── start-db.bat / stop-db.bat / run-appxserver.bat
├── bin/                 # setup、clean、reset、db-*、setup-kb、assemble\、install-packages、env、update
├── packages/            # 离线 zip + packages.ini（+ 可选 packages.json；zip 不进 Git）
├── runtime/jdk          # JAVA_HOME
├── runtime/pgsql        # PostgreSQL 程序
├── runtime/python       # embeddable Python（assemble）
├── runtime/pgdata       # 数据目录
├── runtime/logs
├── runtime/backup       # bin\update.bat 的 dump 与扩展 jar
├── workspace/           # sources / kb / scratch
├── appxserver/          # 产品（gitignore；zip 解压 + conf 覆盖）
├── conf/                # 配置源（改这里，再跑 bin\setup.bat；`data/lang` 为 zh_CN 翻译包）
└── service/             # Windows 服务
```

## 运行

交互（开发）：`start-db.bat` → `run-appxserver.bat`  
服务（生产）：管理员 `service\install-services.bat`，日常 `service\services.bat start|stop|status`

两种模式**不要同机并用**（端口 `15432` / `18080` / `18443`）。

| 入口 | URL |
|------|-----|
| 应用 | https://localhost:18443/webui/ |
| OSGi | https://localhost:18443/osgi/system/console/bundles |

首次安装、导入库、Extension Management 见安装文档。可选：`bin\setup-kb.bat`（含语料/源码组装）。

升级：`bin\check-update.bat` 先看计划，再 `bin\update.bat`；回退用 `bin\rollback-update.bat`。详见安装文档「升级（update）」一节。
