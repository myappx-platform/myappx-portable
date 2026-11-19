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

Pauses for confirmation. Then: unpack seed → recreate database `appx` / user `appx` → import dump → `AppxFinalizeDb` (rename schema `adempiere` to `appx`, create read-only role `appx_ro`) → `RUN_SyncDB` → sign → import zh_CN from `appxserver\data\lang\zh_CN_System` and synchronize terminology (setup copies that folder from `conf\data\lang`). Language import log: `runtime\logs\lang-import.log`.

If you already have a business dump, use `bin\db-restore.bat` (reads `appxserver\data\ExpDat.dmp`) instead of seed import. Restore does not import the language pack.

To re-import zh_CN on an existing database without dropping it, run `bin\db-lang.bat` (PostgreSQL must already be up). After editing `conf\data\lang`, re-run `bin\setup.bat` first.

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
| `bin\reset.bat` | Reset: type YES, then clean, setup, import, setup-kb; stops PostgreSQL and writes a report |
| `bin\db-import.bat` | Import iDempiere seed (recreates the database), then import zh_CN |
| `bin\db-lang.bat` | Re-import zh_CN and synchronize terminology on an existing database (does not drop it; already included in `db-import`) |
| `bin\db-restore.bat` | Restore from `ExpDat.dmp` |
| `bin\db-export.bat` | Export dump |
| `bin\db-sync.bat` | Migrations only (upgrades; already included in a fresh import) |
| `bin\check-update.bat` | Report whether newer packages exist (exit 0 = current, 2 = update available, 1 = error) |
| `bin\update.bat` | Upgrade from `packages\` (or the online manifest): backup, swap, migrate, sign, re-import zh_CN |
| `bin\rollback-update.bat` | Restore the `appxserver.bak-<stamp>` saved by the previous update |
| `bin\setup-kb.bat` | Standard KB: create `appx_kb` + pgvector, then assemble `workspace\kb` / `workspace\sources` (Postgres must be up; skips assemble if sibling repos or Python are missing) |
| `bin\assemble\assemble-kb.bat` | Re-assemble `workspace\kb\` only (needs sibling `myappx-plugins`; `id-docs` optional) |
| `bin\assemble\assemble-sources.bat` | Re-assemble `workspace\sources\` only (needs sibling `myappx-server` / `myappx-plugins`) |

### Unattended reset

`bin\reset.bat` asks for `YES` before it starts. After that it does not pause: it deletes install output, runs setup, imports the seed database, and runs `setup-kb`. PostgreSQL is stopped when it finishes. The application is not started.

The report is `runtime\logs\reset-report.txt`. If the run fails before setup, the report stays at `%TEMP%\myappx-reset-report.txt` and the console prints the path actually used.

If a Windows service is running, or port `18080` / `18443` is still listening, the script fails immediately and deletes nothing. Stop the services with `service\services.bat stop`, or stop `run-appxserver.bat`, then run it again.

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
├── bin\                 # init, clean, db-*, setup-*, assemble\, install-packages, env, update
├── packages\            # offline zips + packages.ini (+ optional packages.json)
├── runtime\jdk          # JAVA_HOME
├── runtime\pgsql        # PostgreSQL binaries
├── runtime\python       # embeddable Python (assemble)
├── runtime\pgdata       # database files
├── runtime\logs         # PostgreSQL / WinSW logs
├── runtime\backup       # dumps + extension jars taken by bin\update.bat
├── workspace\           # sources / kb / scratch (see workspace/README.md)
├── appxserver\          # product (gitignore; zip + conf overlay)
├── conf\                # config source (init copies onto appxserver; `data\lang` is the zh_CN pack)
└── service\             # Windows services
```

Do not edit `runtime\pgdata\postgresql.portable.conf` by hand; change `conf\pg\postgresql.portable.conf`, re-run `bin\setup.bat`, then restart PostgreSQL.

---

## 8. Upgrading (update)

The update feature keeps the whole portable tree in step: runtime zips, the product, the
database and the language pack. Everything it needs can sit in `packages\`, so it works
without a network.

### 8.1 Check for updates

```bat
bin\check-update.bat
```

Prints the current and available version of every component. Exit code `0` means
everything is current, `2` means an update is available, `1` means the check failed.

Components and how their version is read:

| Component | Version source |
|---|---|
| AppxServer | `p2.timestamp` + `org.adempiere.server` version inside the zip's `artifacts.xml` |
| JDK / PostgreSQL / Python / pgvector | version in the zip file name |

The product zip is always called `myappxserver-14.0.0.latest-*.zip`, so the file name
alone cannot tell two builds apart; the build stamp inside the zip is what counts.

### 8.2 Run the update

> **The update only supports portable mode.** The application runs from `run-appxserver.bat`
> and PostgreSQL from `start-db.bat`. If `MyAppx Database` / `MyAppx Application` is running as a
> Windows service, the update refuses to start - stop it with `service\services.bat stop` first.

```bat
bin\update.bat
```

It prints the plan, asks for `YES`, then:

1. preflight - ports free, at least 6 GB free, no MyAppx service running
2. backup - `pg_dump` to `runtime\backup\<stamp>\appx.dump`, plus `globals.sql`, `conf\`,
   `packages.ini`, the installed customer bundles and `installed.json`
3. stops PostgreSQL
4. swaps JDK / PostgreSQL / Python (and overlays pgvector) into place; the old directory
   becomes `<name>.bak-<stamp>`
5. unpacks the product into `appxserver.new-<stamp>`, overlays `conf\`, records what has to be
   reinstalled without writing any load-time manifest, then renames it to `appxserver`
   (the old one becomes `appxserver.bak-<stamp>`)
6. starts PostgreSQL, runs `RUN_SyncDB`, `sign-database-build-alt` and `bin\db-lang.bat`
7. verifies `AD_System`, the migration count, `bundles.info` and the extension states
8. rewrites the zip names in `packages\packages.ini`, then prunes old backups
9. stops PostgreSQL again, whether the update succeeded or failed

### How customer bundles are handled

The update does **not** write customer bundles into the new tree. It only:

- backs the jars up to `runtime\backup\<stamp>\extensions\` (rollback and evidence)
- writes the reinstall list `runtime\logs\update\<stamp>\extensions-to-reinstall.json`

The baseline for "which bundles are customer bundles" comes from the **package's own
`bundles.info`**, not from the live tree.

**After the update you must reinstall those extensions through Extension Management**
(System Admin -> Extension Management, Install each one). Reason: Extension Management calls
`installBundle(downloadUrl)`, so the bundle's OSGi **location is an HTTP URL**, while a jar
copied to `plugins\` and listed in `bundles.info` has a local path location. When the same
symbolic name exists under two locations, the OSGi singleton rule can only resolve one of them:

```
Could not resolve module: org.idempiere.myappx.plugin.aic
  Another singleton bundle selected: version="1.0.1.202611181609"
```

Copying the jars automatically therefore breaks Extension Management's upgrade and uninstall,
so the update only backs them up and leaves the install to Extension Management.

Report: `runtime\logs\update-report.txt`. Per-step logs: `runtime\logs\update\<stamp>\`.

After the update, start the tree in this order:

```bat
start-db.bat
run-appxserver.bat
```

Then reinstall the extensions listed in the reinstall file through Extension Management.

Useful switches:

| Switch | Effect |
|---|---|
| `-CheckOnly` | print the plan and stop |
| `-Offline` | ignore the configured base URL |
| `-SkipBackup` | skip `pg_dump` (not recommended) |
| `-SkipDbSync` | do not run `RUN_SyncDB`; run `bin\db-sync.bat` later |
| `-SkipLang` | do not re-import zh_CN |
| `-AllowPgMajor` | allow a PostgreSQL major upgrade |
| `-Resume` | finish the database phase after a run that stopped mid-way |
| `-Force` | re-apply components that already report "skip" |

### 8.3 Online manifest (optional)

`conf\update.ini` points at a manifest instead of relying on what is already downloaded:

```ini
UPDATE_BASE_URL=https://example.com/myappx-portable
UPDATE_CHANNEL=latest
UPDATE_MANIFEST=packages.json
UPDATE_OFFLINE=0
UPDATE_KEEP_BACKUPS=3
```

Generate the manifest next to the zips:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File bin\update\make-manifest.ps1 -BaseUrl https://example.com/myappx-portable
```

Upload `packages.json` and the zips to that URL. With a base URL set, `bin\update.bat`
downloads only components that are newer than what is installed, verifies `sha256`, and
falls back to the local `packages\` folder when the manifest cannot be fetched.

### 8.4 PostgreSQL major upgrades

A PostgreSQL major change (for example 18 to 19) needs `pg_upgrade` and is refused unless
`-AllowPgMajor` is given. The script then:

1. copies `runtime\pgdata` to `runtime\backup\<stamp>\pgdata`
2. runs `initdb` into `runtime\pgdata.new` with the same SCRAM/UTF-8 settings
3. runs `pg_upgrade --check` (a failure here leaves the old cluster untouched), then the
   real `pg_upgrade`
4. renames `pgdata` to `pgdata.bak-<stamp>` and `pgdata.new` to `pgdata`

The old PostgreSQL binaries are kept as `runtime\pgsql.bak-<stamp>` because `pg_upgrade`
needs them.

### 8.5 Rollback

```bat
bin\rollback-update.bat                       :: newest backup, database stays migrated
bin\rollback-update.bat 20261115-2312         :: specific stamp
bin\rollback-update.bat 20261115-2312 -RestoreDb
```

Rollback swaps `appxserver.bak-<stamp>` (and `runtime\*.bak-<stamp>` when they exist) back
into place. Migration scripts cannot be undone by code, so only `-RestoreDb` returns the
schema to the pre-update state: it drops and recreates database `appx` from
`runtime\backup\<stamp>\appx.dump`.

---

## 9. Troubleshooting

| Symptom | What to do |
|---|---|
| Missing `packages.ini` / zip | Put the zip in `packages\`; filename must match the ini |
| `initdb` password vs import | Superuser must be `postgres123`, or change `conf\utils\myEnvironment.bat` and re-run `bin\setup.bat` |
| Port in use | `stop-db.bat`, kill leftover `java.exe`; do not run service mode at the same time |
| Import fails / not enough locks | `bin\setup.bat` writes `max_locks_per_transaction=256` into PG; restart the database after that |
| Services fail after moving the folder | Administrator: `service\uninstall-services.bat`, then `install-services.bat` at the new path |
| Wipe and re-import the DB | Stop PostgreSQL, delete `runtime\pgdata\`, then `bin\setup.bat` → `start-db.bat` → `bin\db-import.bat` |
| Reset to pre-install | `bin\clean.bat` (type YES). If Windows services are running, `service\services.bat stop` first |
