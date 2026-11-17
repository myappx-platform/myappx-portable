# myappx-portable

[中文](README.md) · **English**

Portable AppxServer with bundled JDK 21 and PostgreSQL. Config lives in `conf\`; runtime in `runtime\` / `appxserver\`; scripts use `bin\env.bat`.

| Doc | Contents |
|------|------|
| [INSTALL.en.md](INSTALL.en.md) | Fresh install, offline zips, database import, extensions, accounts, daily commands |
| [service/README-service.md](service/README-service.md) | Windows services (manual start; mutually exclusive with interactive mode) |
| [workspace/README.md](workspace/README.md) | `sources` / `kb` / `scratch` |

```
myappx-portable/
├── README.md / README.en.md
├── INSTALL.zh-CN.md / INSTALL.en.md
├── start-db.bat / stop-db.bat / run-appxserver.bat
├── bin/                 # setup, clean, reset, db-*, setup-kb, assemble\, install-packages, env, update
├── packages/            # offline zips + packages.ini (+ optional packages.json)
├── runtime/jdk          # JAVA_HOME
├── runtime/pgsql        # PostgreSQL binaries
├── runtime/python       # embeddable Python (assemble)
├── runtime/pgdata       # data directory
├── runtime/logs
├── runtime/backup       # dumps + extension jars taken by bin\update.bat
├── workspace/           # sources / kb / scratch
├── appxserver/          # product (gitignore; zip + conf overlay)
├── conf/                # config source (edit here, then bin\setup.bat; `data/lang` is the zh_CN pack)
└── service/             # Windows services
```

## Run

Interactive (dev): `start-db.bat` → `run-appxserver.bat`  
Services (production): Administrator `service\install-services.bat`; daily `service\services.bat start|stop|status`

Do **not** use both modes on the same machine (ports `15432` / `18080` / `18443`).

| Entry | URL |
|------|-----|
| Application | https://localhost:18443/webui/ |
| OSGi | https://localhost:18443/osgi/system/console/bundles |

First-time install, database import, and Extension Management are in the install guide. Optional: `bin\setup-kb.bat` (includes corpus/source assemble).

Upgrade: `bin\check-update.bat` for the plan, then `bin\update.bat` (**portable mode only**; it stops PostgreSQL when it finishes, so start it again with `start-db.bat` + `run-appxserver.bat`); `bin\rollback-update.bat` restores the previous copy. See the "Upgrading (update)" section of the install guide.
