# myappx-portable install guide

[中文](INSTALL.zh-CN.md) · **English**

Portable AppxServer with bundled **JDK 21** and **PostgreSQL 18**. No separate Java / Postgres install on the machine. This document is for a **fresh deploy**.

Windows services: [service/README-service.md](service/README-service.md).

---

## 1. Environment

| Item | Requirement |
|---|---|
| OS | Windows 10 / 11 x64 |
| Path | Fixed absolute path; **do not move** after install; avoid spaces and non-ASCII |
| Tools | Built-in `tar.exe` (`%SystemRoot%\System32\tar.exe`) |
| Ports | `15432` (PostgreSQL), `18080` / `18443` (HTTP / HTTPS), `12612` (OSGi console) |

Use root scripts for interactive development; Windows services for production. **Do not run both modes on the same machine** (port conflict).

---

## 2. Offline packages

Zips are **not in Git**. Place the files in `packages\`; names must match `packages\packages.ini` (when upgrading, change only the zip name in the ini):

| Variable | Current filename | Unpacks to |
|---|---|---|
| `JDK_ZIP` | `microsoft-jdk-21.0.12.1-windows-x64.zip` | `runtime\jdk\` |
| `PGSQL_ZIP` | `postgresql-18.6-3-windows-x64-binaries.zip` | `runtime\pgsql\` |
| `APPX_ZIP` | `myappxserver-14.0.0.latest-win32.win32.x86_64.zip` | `appxserver\` |
| `VECTOR_ZIP` | `vector.v0.8.6-pg18.zip` | overlay into `runtime\pgsql\` |
| `PYTHON_ZIP` | `python-3.12.10-embed-amd64.zip` | `runtime\python\` |

The AppxServer zip must include the seed (`data\seed\Adempiere_pg.jar`). `bin\setup.bat` **overwrites** `appxserver\` from `conf\`. Do not edit unpacked product config; edit `conf\` and re-run setup.

---

## 3. Fresh install (interactive)

Run from the portable **root**.

### Step 1 — Initialize

```bat
bin\setup.bat
```

This does, in one go:

1. Unpack JDK / PostgreSQL / AppxServer / Python from `packages.ini`, and overlay pgvector
2. **Force-copy** `conf\` onto `appxserver\`
3. `initdb` for `runtime\pgdata\` (SCRAM-SHA-256, UTF-8)

`initdb` sets the `postgres` superuser password to **`postgres123`** (via `--pwfile`), matching `ADEMPIERE_DB_SYSTEM` in `conf\utils\myEnvironment.bat`.

If `runtime\pgdata\` already exists, `initdb` is skipped; `conf\` is still copied.

### Step 2 — Start the database

```bat
start-db.bat
```

Listens on `localhost:15432`. Log: `runtime\logs\postgres.log`.

### Step 3 — Import the seed database

```bat
bin\db-import.bat
```

Pauses for confirmation. Then: unpack seed → recreate database `appx` / user `appx` → import dump → `AppxFinalizeDb` (rename schema `adempiere` to `appx`, create read-only role `appx_ro`) → `RUN_SyncDB` → sign.

If you already have a business dump, use `bin\db-restore.bat` (reads `appxserver\data\ExpDat.dmp`) instead of seed import.

### Step 4 — Start the application

```bat
run-appxserver.bat
```

### Step 5 — Sign in

| Service | URL |
|---|---|
| Application | https://localhost:18443/webui/ |
| Felix OSGi | https://localhost:18443/osgi/system/console/bundles |

Seed tenant defaults: **GardenWorld** / **GardenAdmin**. System: **System** / **SuperUser**.

First HTTPS uses a self-signed certificate; the browser needs an exception.

### Step 6 — Install extensions

Sign in as **System / SuperUser**, then open **System Admin → Extension Management**.

---

## 4. Default accounts and config

Source: `conf\utils\myEnvironment.bat` (copied to `appxserver\utils\` by `bin\setup.bat`).

| Use | User | Password | Notes |
|---|---|---|---|
| PostgreSQL superuser | `postgres` | `postgres123` | Set by `bin\setup.bat` `--pwfile` |
| Application DB | `appx` / database `appx` | `appx123` | JDBC `localhost:15432/appx` |
| Read-only role | `appx_ro` | `appx_ro` | Created by `AppxFinalizeDb` |
| Knowledge-base role | `appx_kb` | `appx_kb` | `bin\setup-kb.bat` only |

For production, change passwords, re-run `bin\setup.bat`, and sync `initdb` / existing role passwords.

---

## 5. Daily commands

| Command | Role |
|---|---|
| `start-db.bat` / `stop-db.bat` | Interactive PostgreSQL start/stop |
| `run-appxserver.bat` | Foreground application start |
| `bin\setup.bat` | Unpack runtime, overlay conf, sync portable PG settings |
| `bin\clean.bat` | Delete install output, back to pre-init (stop the services or interactive Postgres if they are running) |
| `bin\db-import.bat` | Import iDempiere seed (recreates the database) |
| `bin\db-restore.bat` | Restore from `ExpDat.dmp` |
| `bin\db-export.bat` | Export dump |
| `bin\db-sync.bat` | Migrations only (upgrades; already included in a fresh import) |
| `bin\setup-kb.bat` | Standard KB: create `appx_kb` + pgvector, then assemble `workspace\kb` / `workspace\sources` (Postgres must be up; skips assemble if sibling repos or Python are missing) |
| `bin\assemble\assemble-kb.bat` | Re-assemble `workspace\kb\` only (needs sibling `myappx-plugins`; `id-docs` optional) |
| `bin\assemble\assemble-sources.bat` | Re-assemble `workspace\sources\` only (needs sibling `myappx-server` / `myappx-plugins`) |

---

## 6. Windows services (production)

After interactive init and database import:

1. Place [WinSW v2.12.0 x64](https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe) at `service\winsw\WinSW-x64.exe`
2. Run `service\install-services.bat` as **Administrator**

Registers `MyAppx Database` and `MyAppx Application` as **Manual** (does not start them). Daily: `service\services.bat start|stop|status`.

Do not also run `start-db.bat` + `run-appxserver.bat` on the same machine. Details: [service/README-service.md](service/README-service.md).

---

## 7. Layout

```
myappx-portable/
├── README.md / README.en.md
├── INSTALL.zh-CN.md / INSTALL.en.md
├── start-db.bat / stop-db.bat / run-appxserver.bat
├── bin\                 # init, clean, db-*, setup-*, assemble\, install-packages, env
├── packages\            # offline zips + packages.ini
├── runtime\jdk          # JAVA_HOME
├── runtime\pgsql        # PostgreSQL binaries
├── runtime\python       # embeddable Python (assemble)
├── runtime\pgdata       # database files
├── runtime\logs         # PostgreSQL / WinSW logs
├── workspace\           # sources / kb / scratch (see workspace/README.md)
├── appxserver\          # product (gitignore; zip + conf overlay)
├── conf\                # config source (init copies onto appxserver)
└── service\             # Windows services
```

Do not edit `runtime\pgdata\postgresql.portable.conf` by hand; change `conf\pg\postgresql.portable.conf`, re-run `bin\setup.bat`, then restart PostgreSQL.

---

## 8. Troubleshooting

| Symptom | What to do |
|---|---|
| Missing `packages.ini` / zip | Put the zip in `packages\`; filename must match the ini |
| `initdb` password vs import | Superuser must be `postgres123`, or change `conf\utils\myEnvironment.bat` and re-run `bin\setup.bat` |
| Port in use | `stop-db.bat`, kill leftover `java.exe`; do not run service mode at the same time |
| Import fails / not enough locks | `bin\setup.bat` writes `max_locks_per_transaction=256` into PG; restart the database after that |
| Services fail after moving the folder | Administrator: `service\uninstall-services.bat`, then `install-services.bat` at the new path |
| Wipe and re-import the DB | Stop PostgreSQL, delete `runtime\pgdata\`, then `bin\setup.bat` → `start-db.bat` → `bin\db-import.bat` |
| Reset to pre-install | `bin\clean.bat` (type YES). If Windows services are running, `service\services.bat stop` first |
