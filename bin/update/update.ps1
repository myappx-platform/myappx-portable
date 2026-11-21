# update.ps1 - myappx-portable update driver.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File bin\update\update.ps1 -Action check
#   powershell -NoProfile -ExecutionPolicy Bypass -File bin\update\update.ps1 -Action apply
#
# Prefer the wrappers: bin\check-update.bat, bin\update.bat, bin\rollback-update.bat.
# Strategy: extract each component side by side, swap directories, keep the old copy as
# <name>.bak-<stamp>. PostgreSQL major changes go through pg_upgrade.
#
# Customer bundles installed through Extension Management survive the product swap by being
# carried over: their directory is copied into the new tree and one bundles.info line is added,
# which is the same shape the product uses for its own bundles. They are found in all three
# shapes an install can leave behind (OSGi pool bundleFile, plugins\<sn>_<ver>\ directory, and the
# older plugins\<sn>_<ver>.jar), exported uniformly as directories, and re-registered together
# with their Require-Bundle relations checked afterwards.
#
# Why not p2: converting these bundles into p2 installable units was evaluated and rejected.
# (1) The migration problem does not go away - the p2 profile stores absolute install paths, so a
# product swap invalidates it exactly like plugins\ does, and it would have to be rewritten too.
# (2) Applying a p2 change uses ConfigApplier, which calls refreshBundles; the AI Copilot web
# bundle has a refresh closure of 119 bundles including org.adempiere.ui.zk and
# org.adempiere.server, which tears down the deployed web contexts. (3) It adds IU metadata, a
# category.xml and an artifact repository to maintain, for no gain over one directory copy plus
# one registry line.
#
# This file only orchestrates; helpers live in update-lib.ps1.

[CmdletBinding()]
param(
    [ValidateSet('check', 'apply', 'rollback', 'download', 'manifest')]
    [string]$Action = 'apply',

    [string]$Root,
    [string]$PackagesDir,
    [string]$BaseUrl,
    [string]$ManifestName,
    [string]$Channel,
    [string]$Stamp,

    [switch]$CheckOnly,
    [switch]$Offline,
    [switch]$AllowPgMajor,
    [switch]$ClusterBackup,
    [switch]$RestoreDb,
    [switch]$SkipBackup,
    [switch]$SkipDbSync,
    [switch]$SkipLang,
    [switch]$SkipPreflight,
    [Alias('SkipServiceControl')]
    [switch]$SkipPortCheck,
    [switch]$OnlyChanged,
    [switch]$Resume,
    [switch]$Force,
    [switch]$Yes,

    [int]$Keep = 0,
    [int]$PgUpgradeOldPort = 54332,
    [int]$PgUpgradeNewPort = 54333
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1.0

. (Join-Path $PSScriptRoot 'update-lib.ps1')

if ($CheckOnly -and $Action -eq 'apply') { $Action = 'check' }

# ---------------------------------------------------------------------------
# Settings: conf\update.ini supplies defaults; parameters win.
# ---------------------------------------------------------------------------

function Get-UpdateSettings {
    param([string]$PortableRoot)

    $iniPath = Join-Path $PortableRoot 'conf\update.ini'
    $ini = Read-IniFile -Path $iniPath

    $settings = [pscustomobject]@{
        BaseUrl = ''
        Channel = 'latest'
        Manifest = 'packages.json'
        Offline = $false
        Keep = 3
    }
    if ($ini['UPDATE_BASE_URL']) { $settings.BaseUrl = $ini['UPDATE_BASE_URL'].TrimEnd('/') }
    if ($ini['UPDATE_CHANNEL']) { $settings.Channel = $ini['UPDATE_CHANNEL'] }
    if ($ini['UPDATE_MANIFEST']) { $settings.Manifest = $ini['UPDATE_MANIFEST'] }
    if ($ini['UPDATE_OFFLINE']) { $settings.Offline = ($ini['UPDATE_OFFLINE'] -match '^(1|yes|true|y)$') }
    if ($ini['UPDATE_KEEP_BACKUPS']) {
        $parsed = 0
        if ([int]::TryParse($ini['UPDATE_KEEP_BACKUPS'], [ref]$parsed)) { $settings.Keep = $parsed }
    }
    return $settings
}

$portableRootForSettings = $Root
if (-not $portableRootForSettings) {
    $portableRootForSettings = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
} else {
    $portableRootForSettings = (Resolve-Path $portableRootForSettings).Path
}

$settings = Get-UpdateSettings -PortableRoot $portableRootForSettings
if (-not $BaseUrl) { $BaseUrl = $settings.BaseUrl }
if (-not $Channel) { $Channel = $settings.Channel }
if (-not $ManifestName) { $ManifestName = $settings.Manifest }
if (-not $Offline -and $settings.Offline) { $Offline = $true }
if ($Keep -le 0) { $Keep = $settings.Keep }

$envBat = Join-Path $portableRootForSettings 'bin\env.bat'

# ---------------------------------------------------------------------------
# Step runner
# ---------------------------------------------------------------------------

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )

    Write-Host ''
    Write-Host '########################################################'
    Write-Host ('### {0}' -f $Name)
    Write-Host '########################################################'

    $started = Get-Date
    $result = 'OK'
    $exit = 0
    $note = ''
    try {
        & $Body
    } catch {
        $result = 'FAIL'
        $exit = 1
        $message = $_.Exception.Message
        if ($_.Exception.InnerException) { $message = $_.Exception.InnerException.Message }
        $note = $message
    }
    $elapsed = [int]((Get-Date) - $started).TotalSeconds
    Add-ReportRow -Report $State.Report -Step $Name -Result $result -ExitCode $exit -Seconds $elapsed -Note $note
    Save-UpdateReport -Report $State.Report -Path (Join-Path $State.Context.LogsDir 'update-report.txt') -FallbackPath (Join-Path $env:TEMP 'myappx-update-report.txt') | Out-Null

    if ($result -ne 'OK') {
        Write-UpdateLog -Level ERROR -Message ('{0} failed: {1}' -f $Name, $note) -LogPath $State.LogPath
        throw (New-Object System.Exception(('Step {0} failed: {1}' -f $Name, $note)))
    }
}

# ---------------------------------------------------------------------------
# Plan post-processing
# ---------------------------------------------------------------------------

function Set-PlanForce {
    # -Force re-applies components that already report "skip", e.g. to repair a partially
    # applied update or to re-run the swap with a rebuilt package of the same version.
    param($Plan)
    foreach ($row in $Plan.Rows) {
        if ($row.Action -ne 'skip') { continue }
        if (-not $row.Target) { continue }
        $row.Action = 'upgrade'
    }
    $Plan.Changed = $true
}

function Add-SkippedStep {
    param($State, [string]$Name, [string]$Note)
    Write-Host ('--- {0} skipped: {1}' -f $Name, $Note)
    Add-ReportRow -Report $State.Report -Step $Name -Result 'SKIP' -ExitCode 0 -Seconds 0 -Note $Note
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

function New-UpdateState {
    param([string]$Title)

    $context = New-UpdateContext -Root $Root -PackagesDir $PackagesDir -Stamp $Stamp `
        -BaseUrl $BaseUrl -Channel $Channel -ManifestName $ManifestName -Offline:$Offline -Keep $Keep

    New-DirectoryIfMissing -Path $context.LogsDir | Out-Null
    New-DirectoryIfMissing -Path $context.UpdateLogDir | Out-Null
    New-DirectoryIfMissing -Path $context.TempDir | Out-Null

    $logPath = Join-Path $context.UpdateLogDir 'update.log'
    $report = New-UpdateReport -Title $Title -Root $context.Root -Stamp $context.Stamp

    return [pscustomobject]@{
        Context = $context
        Report = $report
        LogPath = $logPath
        Plan = $null
        Pg = $null
        ExtensionStatesBefore = $null
    }
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

function Assert-DiskSpace {
    param([string]$Path, [int]$RequiredGb = 6)

    $drive = (Get-Item $Path).PSDrive
    if (-not $drive -and $Path) {
        $root = [System.IO.Path]::GetPathRoot((Resolve-Path $Path).Path)
        $drive = Get-PSDrive -Name $root.Substring(0, 1) -ErrorAction SilentlyContinue
    }
    if (-not $drive -or -not $drive.Free) { return }
    $freeGb = [math]::Round($drive.Free / 1GB, 1)
    if ($freeGb -lt $RequiredGb) {
        throw ('not enough free space on {0}: {1} GB free, {2} GB required' -f $drive.Name, $freeGb, $RequiredGb)
    }
}

function Test-Preflight {
    param($State, [switch]$AllowRunning)

    $ctx = $State.Context

    if (-not (Test-Path (Join-Path $ctx.Root 'bin\env.bat'))) {
        throw ('not a myappx-portable root: {0}' -f $ctx.Root)
    }
    Assert-DiskSpace -Path $ctx.Root -RequiredGb 6

    # update only supports portable mode: the application is started with run-appxserver.bat and
    # PostgreSQL with start-db.bat. A registered Windows service would fight for the same ports.
    Assert-PortableMode -State $State

    if (-not $AllowRunning) {
        # Only the application has to be down: the backup dump needs the database up, and it is
        # stopped right before the swap.
        $ports = Test-PortListening -Ports @(18080, 18443, 12612)
        if ($ports.Count -gt 0) {
            throw ('port(s) {0} still listening; stop run-appxserver.bat first' -f ($ports -join ', '))
        }
    }

    Add-ReportNote -Report $State.Report -Text 'Mode: portable (no Windows service)'
}

function Assert-PortableMode {
    param($State)

    # Registered services are not an error on their own (installing them is optional and they may
    # be stopped), but a *running* one means this tree is being served in service mode, and the
    # update would stop a service it never started.
    $running = @()
    foreach ($name in @('MyAppx Database', 'MyAppx Application')) {
        if ((Get-ServiceState -Name $name) -eq 'RUNNING') { $running += $name }
    }
    if ($running.Count -gt 0) {
        throw ('update only supports portable mode, but {0} is running. Stop it first: service\services.bat stop' -f ($running -join ', '))
    }
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

function Invoke-Downloads {
    param($State, [switch]$IncludeUnchanged)

    $plan = $State.Plan
    $ctx = $State.Context
    foreach ($row in $plan.Rows) {
        if (-not $row.Target) { continue }
        if (-not $row.NeedsDownload) { continue }
        if (-not $IncludeUnchanged -and $row.Action -ne 'upgrade' -and $row.Action -ne 'install') {
            # Up to date already: no reason to pull the archive down just to skip it.
            continue
        }
        if (-not $row.Target.Url) {
            throw ('{0}: {1} is not in packages\ and the manifest has no url for it' -f $row.Label, $row.Target.File)
        }
        Invoke-PackageDownload -Url $row.Target.Url -Destination $row.Target.Path -Sha256 $row.Target.Sha256
        $row.Target.Source = 'download'
        $row.NeedsDownload = $false
    }
}

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

function Copy-DirectorySafely {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path $Source)) { return }
    if (Test-Path $Destination) { Remove-Item $Destination -Recurse -Force -ErrorAction SilentlyContinue }
    Copy-Item -Path $Source -Destination $Destination -Recurse -Force
}

function Export-LiveExtensions {
    param($State, [string]$AppxHome, [string]$ProductZip)

    # Export the customer bundles from the current installation so they can be re-registered
    # after the product swap. Runs from Invoke-Backup and again from Invoke-ProductSwap, so a
    # skipped or failed backup cannot silently drop them.
    #
    # The baseline is the bundles.info inside the package being installed, never the live tree:
    # a live tree may already list customer bundles from an earlier Extension Management install,
    # and those must still be recognised as customer bundles.
    $ctx = $State.Context
    $manifestPath = Join-Path $ctx.BackupDir 'extensions.json'
    if (Test-Path $manifestPath) {
        $reused = @()
        $raw = Get-Content $manifestPath -Raw -Encoding UTF8
        if ($raw -and $raw.Trim()) {
            $decoded = $raw | ConvertFrom-Json
            if ($null -ne $decoded) {
                foreach ($item in @($decoded)) {
                    if ($null -ne $item) { $reused += $item }
                }
            }
        }
        Write-UpdateLog -Message ('Reusing {0} previously exported extension bundle(s)' -f $reused.Count) -LogPath $State.LogPath
        return $reused
    }

    if (-not $ProductZip) {
        $productRow = $State.Plan.Rows | Where-Object { $_.Name -eq 'product' } | Select-Object -First 1
        if ($productRow -and $productRow.Target) { $ProductZip = $productRow.Target.Path }
    }
    if (-not $ProductZip -or -not (Test-Path $ProductZip)) {
        throw ('cannot export customer bundles: the product package is not available ({0})' -f $ProductZip)
    }

    $productSymbols = Get-ProductBundleSymbols -ZipPath $ProductZip
    $extensions = @(Get-InstalledExtensionBundles -AppxHome $AppxHome -ExcludeSymbolic @($productSymbols.Keys))
    if ($extensions.Count -eq 0) {
        Write-UpdateLog -Message ('No customer bundles outside the product (baseline {0} bundles).' -f $productSymbols.Count) -LogPath $State.LogPath
        New-DirectoryIfMissing -Path $ctx.BackupDir | Out-Null
        Write-JsonNoBom -Path $manifestPath -Object @()
        return @()
    }

    New-DirectoryIfMissing -Path $ctx.BackupDir | Out-Null
    $exported = Export-ExtensionBundles -Bundles $extensions -BackupDir $ctx.BackupDir
    $fromPool = @($exported | Where-Object { $_.sourceKind -eq 'pool' }).Count
    $fromPlugins = @($exported | Where-Object { $_.sourceKind -eq 'plugins' }).Count
    Write-UpdateLog -Message ('Exported {0} customer bundle(s) to {1} (pool={2}, plugins={3})' -f $exported.Count, (Join-Path $ctx.BackupDir 'extensions'), $fromPool, $fromPlugins) -LogPath $State.LogPath
    return $exported
}

function Invoke-Backup {
    param($State, [switch]$IncludeCluster)

    $ctx = $State.Context
    $pg = $State.Pg
    New-DirectoryIfMissing -Path $ctx.BackupDir | Out-Null

    # Database dump (requires the database to be running).
    if (-not (Test-Path (Join-Path $pg.PgData 'PG_VERSION'))) {
        Write-UpdateLog -Level WARN -Message 'database not initialized; skipping the pg_dump backup' -LogPath $State.LogPath
    } else {
        $ready = Wait-PgReady -PgHome $pg.PgHome -Port $pg.Port -TimeoutSec 5
        if (-not $ready) {
            $startDb = Join-Path $ctx.Root 'start-db.bat'
            if (-not (Test-Path $startDb)) {
                throw ('PostgreSQL is not reachable on port {0} and {1} is missing; start the database first' -f $pg.Port, $startDb)
            }
            Write-UpdateLog -Message 'Starting PostgreSQL to take the backup ...' -LogPath $State.LogPath
            Start-DetachedCommand -CommandLine ('call "' + $startDb + '"') -WorkingDirectory $ctx.Root `
                -LogPath (Join-Path $ctx.UpdateLogDir 'start-db.log') | Out-Null
            $ready = Wait-PgReady -PgHome $pg.PgHome -Port $pg.Port -TimeoutSec 90
        }
        if (-not $ready) { throw ('PostgreSQL is not reachable on port {0}; cannot take a backup' -f $pg.Port) }

        $dump = Join-Path $ctx.BackupDir 'appx.dump'
        $pgDump = Join-Path $pg.PgHome 'bin\pg_dump.exe'
        Write-Host ('Dumping database {0} to {1} ...' -f $pg.Database, $dump)
        Write-UpdateLog -Message ('pg_dump {0} -> {1}' -f $pg.Database, $dump) -LogPath $State.LogPath

        $previous = $env:PGPASSWORD
        $env:PGPASSWORD = $pg.Password
        try {
            $dumpLog = Join-Path $ctx.UpdateLogDir 'pg_dump.log'
            $dumpErr = $dumpLog + '.err'
            $proc = Start-Process -FilePath $pgDump `
                -ArgumentList @('-h', $pg.Host, '-p', [string]$pg.Port, '-U', $pg.User, '-Fc', '-f', $dump, $pg.Database) `
                -WindowStyle Hidden -Wait -PassThru `
                -RedirectStandardOutput $dumpLog -RedirectStandardError $dumpErr
            if ($proc.ExitCode -ne 0) {
                $detail = ''
                if (Test-Path $dumpErr) { $detail = ([System.IO.File]::ReadAllText($dumpErr)).Trim() }
                throw ('pg_dump failed with exit code {0}{1}; see {2}' -f $proc.ExitCode, $(if ($detail) { ': ' + $detail } else { '' }), $dumpErr)
            }
            $sizeMb = [math]::Round((Get-Item $dump).Length / 1MB, 1)
            Write-Host ('  dump ready: {0} MB' -f $sizeMb)
            Write-UpdateLog -Message ('pg_dump finished: {0} MB' -f $sizeMb) -LogPath $State.LogPath

            $env:PGPASSWORD = $pg.SystemPassword
            $globals = Join-Path $ctx.BackupDir 'globals.sql'
            $gErr = (Join-Path $ctx.UpdateLogDir 'pg_dumpall.log')
            $gProc = Start-Process -FilePath (Join-Path $pg.PgHome 'bin\pg_dumpall.exe') `
                -ArgumentList @('-h', $pg.Host, '-p', [string]$pg.Port, '-U', $pg.SystemUser, '--globals-only', '-f', $globals) `
                -WindowStyle Hidden -Wait -PassThru `
                -RedirectStandardOutput $gErr -RedirectStandardError ($gErr + '.err')
            if ($gProc.ExitCode -ne 0) {
                Write-UpdateLog -Level WARN -Message ('pg_dumpall --globals-only failed (exit {0}); continuing without a globals backup' -f $gProc.ExitCode) -LogPath $State.LogPath
            }
        } finally {
            $env:PGPASSWORD = $previous
        }
    }

    Copy-DirectorySafely -Source (Join-Path $ctx.Root 'conf') -Destination (Join-Path $ctx.BackupDir 'conf')
    Copy-Item -Path (Join-Path $ctx.PackagesDir 'packages.ini') -Destination (Join-Path $ctx.BackupDir 'packages.ini') -Force -ErrorAction SilentlyContinue

    # Record what we are about to replace.
    $installed = [ordered]@{}
    foreach ($row in $State.Plan.Rows) {
        $installed[$row.Name] = [ordered]@{
            present = $row.Installed.Present
            version = $row.Installed.Version
            build = $row.Installed.Build
        }
    }
    Write-JsonNoBom -Path (Join-Path $ctx.BackupDir 'installed.json') -Object ([ordered]@{
            stamp = $ctx.Stamp
            pgDataMajor = $ctx.PgDataMajor
            components = $installed
        })

    # Baseline for the post-update extension state comparison.
    $State.ExtensionStatesBefore = Get-ExtensionStates -Pg $pg
    if ($State.ExtensionStatesBefore) {
        Write-JsonNoBom -Path (Join-Path $ctx.BackupDir 'extension-states.json') -Object $State.ExtensionStatesBefore
    }

    # Customer bundles live in the OSGi pool or plugins\ and would be lost with appxserver\.
    Export-LiveExtensions -State $State -AppxHome (Join-Path $ctx.Root 'appxserver') | Out-Null

    if ($IncludeCluster) {
        Write-UpdateLog -Message 'Copying the PostgreSQL data directory (this can take a while) ...' -LogPath $State.LogPath
        Copy-DirectorySafely -Source (Join-Path $ctx.Root 'runtime\pgdata') -Destination (Join-Path $ctx.BackupDir 'pgdata')
    }
}

# ---------------------------------------------------------------------------
# Stop / start services and PostgreSQL
# ---------------------------------------------------------------------------

function Stop-Application {
    param($State)

    # Portable mode: the application runs in a console via run-appxserver.bat. Nothing to stop
    # programmatically - just verify the ports are free.
    if ($SkipPortCheck) {
        Write-UpdateLog -Level WARN -Message 'port check skipped (-SkipPortCheck)' -LogPath $State.LogPath
        return
    }

    $ports = Test-PortListening -Ports @(18080, 18443, 12612)
    if ($ports.Count -gt 0) {
        throw ('port(s) {0} still listening; close run-appxserver.bat before updating' -f ($ports -join ', '))
    }
    Write-UpdateLog -Message 'Application ports are free.' -LogPath $State.LogPath
}

function Stop-Database {
    param($State)

    if ($SkipPortCheck) {
        Write-UpdateLog -Level WARN -Message 'database stop skipped (-SkipPortCheck)' -LogPath $State.LogPath
        return
    }

    $pg = $State.Pg
    $pgCtl = Join-Path $pg.PgHome 'bin\pg_ctl.exe'
    if (-not (Test-Path $pgCtl)) {
        throw ('pg_ctl.exe not found: {0}' -f $pgCtl)
    }

    $ready = Join-Path $pg.PgHome 'bin\pg_isready.exe'
    $running = $false
    if (Test-Path $ready) {
        & $ready -h 127.0.0.1 -p $pg.Port -q 2>$null
        $running = ($LASTEXITCODE -eq 0)
    }
    if (-not $running -and -not (Test-Path (Join-Path $pg.PgData 'postmaster.pid'))) {
        Write-UpdateLog -Message 'PostgreSQL is already stopped.' -LogPath $State.LogPath
        return
    }

    Write-UpdateLog -Message 'Stopping PostgreSQL ...' -LogPath $State.LogPath
    Start-DetachedCommand -CommandLine ('"' + $pgCtl + '" -D "' + $pg.PgData + '" -m fast stop') `
        -LogPath (Join-Path $State.Context.UpdateLogDir 'stop-db.log') | Out-Null

    $pidFile = Join-Path $pg.PgData 'postmaster.pid'
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-Path $pidFile)) { break }
        Start-Sleep -Seconds 2
    }
    if (Test-Path $pidFile) {
        throw ('PostgreSQL did not stop; postmaster.pid is still present in {0}. Close any client and retry, or stop-db.bat' -f $pg.PgData)
    }
}

function Test-DatabaseInitialized {
    param($State)
    $pgData = Join-Path $State.Context.Root 'runtime\pgdata'
    return (Test-Path (Join-Path $pgData 'PG_VERSION'))
}

function Start-Database {
    param($State)

    if (-not (Test-DatabaseInitialized -State $State)) {
        Write-UpdateLog -Level WARN -Message 'PostgreSQL is not initialized (runtime\pgdata is empty); skipping the database phase. Run bin\setup.bat then bin\db-import.bat.' -LogPath $State.LogPath
        return
    }

    $pg = $State.Pg
    if (Wait-PgReady -PgHome $pg.PgHome -Port $pg.Port -TimeoutSec 1) { return }

    # Portable mode only: PostgreSQL is started with start-db.bat (pg_ctl), which works without
    # Administrator rights. There is no `net start` path any more.
    $startDb = Join-Path $State.Context.Root 'start-db.bat'
    if (-not (Test-Path $startDb)) {
        throw ('cannot start PostgreSQL: {0} is missing' -f $startDb)
    }
    Write-UpdateLog -Message 'Starting PostgreSQL with start-db.bat ...' -LogPath $State.LogPath
    Start-DetachedCommand -CommandLine ('call "' + $startDb + '"') -WorkingDirectory $State.Context.Root `
        -LogPath (Join-Path $State.Context.UpdateLogDir 'start-db.log') | Out-Null

    if (-not (Wait-PgReady -PgHome $pg.PgHome -Port $pg.Port -TimeoutSec 120)) {
        $hint = 'Check runtime\logs\postgres.log'
        $pgLog = Join-Path $State.Context.Root 'runtime\logs\postgres.log'
        if (Test-Path $pgLog) {
            $tail = Get-Content $pgLog -Tail 5 -ErrorAction SilentlyContinue
            if ($tail) { $hint = ($tail -join ' | ') }
        }
        throw ('PostgreSQL did not become ready on port {0}: {1}' -f $pg.Port, $hint)
    }
}

function Stop-DatabaseAtEnd {
    param($State)

    # An unattended update must not leave the database running: the operator decides when the
    # application starts again, and a stray postmaster would block the next update or a restart.
    # Report rows are added by the caller (Invoke-Step), so this function stays side-effect free.
    if (-not (Test-DatabaseInitialized -State $State)) { return }
    Stop-Database -State $State
}

# ---------------------------------------------------------------------------
# Runtime component swap
# ---------------------------------------------------------------------------

function Swap-Directory {
    param(
        [Parameter(Mandatory = $true)][string]$LiveDir,
        [Parameter(Mandatory = $true)][string]$NewDir,
        [Parameter(Mandatory = $true)][string]$Stamp
    )

    $parent = Split-Path -Parent $LiveDir
    $name = Split-Path -Leaf $LiveDir
    $backup = Join-Path $parent ('{0}.bak-{1}' -f $name, $Stamp)

    if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
    if (Test-Path $LiveDir) {
        Rename-Item -Path $LiveDir -NewName (Split-Path -Leaf $backup)
    } else {
        $backup = $null
    }
    Rename-Item -Path $NewDir -NewName $name
    return $backup
}

function Invoke-RuntimeSwap {
    param($State, $Row)

    $ctx = $State.Context
    $spec = $Row.Spec
    $runtimeDir = Join-Path $ctx.Root 'runtime'
    New-DirectoryIfMissing -Path $runtimeDir | Out-Null

    $name = $spec.Name
    $liveDir = Join-Path $ctx.Root $spec.Dir
    $newDir = Join-Path $runtimeDir ($name + '.new')

    if (Test-Path $newDir) { Remove-Item $newDir -Recurse -Force }
    Expand-ZipToDirectory -ZipPath $Row.Target.Path -Destination $newDir -Marker $spec.Marker -Label $Row.Label

    $backup = Swap-Directory -LiveDir $liveDir -NewDir $newDir -Stamp $ctx.Stamp
    $from = '-'
    if ($Row.Installed.Present) { $from = [string]$Row.Installed.Version }
    $kept = 'nothing'
    if ($backup) { $kept = Split-Path -Leaf $backup }
    Write-UpdateLog -Message ('{0}: {1} -> {2} (previous kept at {3})' -f $Row.Label, $from, $Row.Target.Version, $kept) -LogPath $State.LogPath
}

function Invoke-VectorOverlay {
    param($State, $Row)

    $ctx = $State.Context
    $pgHome = Join-Path $ctx.Root 'runtime\pgsql'
    Expand-VectorOverlay -ZipPath $Row.Target.Path -PgHome $pgHome
    Write-UpdateLog -Message ('pgvector {0} overlaid into {1}' -f $Row.Target.Version, $pgHome) -LogPath $State.LogPath
}

# ---------------------------------------------------------------------------
# PostgreSQL major upgrade
# ---------------------------------------------------------------------------

function Sync-PgPortableConfig {
    param($State)

    $ctx = $State.Context
    $pg = $State.Pg
    $template = Join-Path $ctx.Root 'conf\pg\postgresql.portable.conf'
    if (-not (Test-Path $template)) {
        Write-UpdateLog -Level WARN -Message ('missing template: {0}' -f $template) -LogPath $State.LogPath
        return
    }
    Copy-Item -Path $template -Destination (Join-Path $pg.PgData 'postgresql.portable.conf') -Force

    $main = Join-Path $pg.PgData 'postgresql.conf'
    if (-not (Test-Path $main)) { return }
    $text = [System.IO.File]::ReadAllText($main)
    if ($text -notmatch "include\s+'postgresql\.portable\.conf'") {
        $text = $text + [Environment]::NewLine + '# myappx-portable overrides' + [Environment]::NewLine + "include 'postgresql.portable.conf'" + [Environment]::NewLine
        Write-TextNoBom -Path $main -Text $text
    }
}

function Invoke-PgMajorUpgrade {
    param($State)

    $ctx = $State.Context
    $pg = $State.Pg
    $binDir = Join-Path $ctx.Root 'runtime\pgsql\bin'
    $oldBinDir = $null
    $oldCandidates = @(Get-ChildItem -Path (Join-Path $ctx.Root 'runtime') -Filter 'pgsql.bak-*' -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    foreach ($candidate in $oldCandidates) {
        if (Test-Path (Join-Path $candidate.FullName 'bin\pg_upgrade.exe')) { $oldBinDir = Join-Path $candidate.FullName 'bin'; break }
    }
    if (-not $oldBinDir) {
        throw ('pg_upgrade needs the previous PostgreSQL binaries and none were kept under {0}\runtime\pgsql.bak-*. Add the old PostgreSQL package to packages\ and restore that directory, or restore runtime\pgdata from a backup' -f $ctx.Root)
    }

    $oldData = $pg.PgData
    $newData = Join-Path $ctx.Root 'runtime\pgdata.new'
    if (Test-Path $newData) { Remove-Item $newData -Recurse -Force }

    $pwFile = Join-Path $ctx.TempDir 'initdb-pw.txt'
    Write-TextNoBom -Path $pwFile -Text ($pg.SystemPassword + [Environment]::NewLine)
    $initdbLog = Join-Path $ctx.UpdateLogDir 'initdb.log'
    $initdb = Join-Path $binDir 'initdb.exe'
    try {
        $initdbArgs = @(
            '--pgdata=' + $newData
            '--auth=scram-sha-256'
            '--username=' + $pg.SystemUser
            '--pwfile=' + $pwFile
            '--encoding=UTF8'
            '--no-locale'
            '--lc-messages=C'
        )
        $env:LC_MESSAGES = 'C'
        & $initdb @initdbArgs 2>&1 | Out-File -FilePath $initdbLog -Encoding UTF8
        if (-not (Test-Path (Join-Path $newData 'PG_VERSION'))) {
            throw ('initdb failed for the new cluster; see {0}' -f $initdbLog)
        }
    } finally {
        if (Test-Path $pwFile) { Remove-Item $pwFile -Force }
    }

    Sync-PgPortableConfig -State $State

    $upgradeLog = Join-Path $ctx.UpdateLogDir 'pg_upgrade.log'
    $pgUpgrade = Join-Path $binDir 'pg_upgrade.exe'
    $args = @(
        '-b', $oldBinDir
        '-B', $binDir
        '-d', $oldData
        '-D', $newData
        '-U', $pg.SystemUser
        '-p', ([string]$PgUpgradeOldPort)
        '-P', ([string]$PgUpgradeNewPort)
    )

    Write-UpdateLog -Message 'Running pg_upgrade --check ...' -LogPath $State.LogPath
    & $pgUpgrade @args -c 2>&1 | Out-File -FilePath $upgradeLog -Encoding UTF8
    if ($LASTEXITCODE -ne 0) {
        Get-Content $upgradeLog -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
        throw ('pg_upgrade --check failed; see {0}. The old cluster was not modified.' -f $upgradeLog)
    }

    Write-UpdateLog -Message 'Running pg_upgrade ...' -LogPath $State.LogPath
    & $pgUpgrade @args 2>&1 | Out-File -FilePath $upgradeLog -Encoding UTF8 -Append
    if ($LASTEXITCODE -ne 0) {
        Get-Content $upgradeLog -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
        throw ('pg_upgrade failed; see {0}. The old cluster is still intact at {1}' -f $upgradeLog, $oldData)
    }

    $backupData = Join-Path $ctx.Root ('runtime\pgdata.bak-' + $ctx.Stamp)
    if (Test-Path $backupData) { Remove-Item $backupData -Recurse -Force }
    Rename-Item -Path $oldData -NewName (Split-Path -Leaf $backupData)
    Rename-Item -Path $newData -NewName 'pgdata'
    $ctx.PgDataMajor = Get-MajorFromVersion -Version $State.Plan.TargetPgMajor
    Write-UpdateLog -Message ('PostgreSQL cluster upgraded; previous data directory kept at {0}' -f (Split-Path -Leaf $backupData)) -LogPath $State.LogPath
}

# ---------------------------------------------------------------------------
# Product swap
# ---------------------------------------------------------------------------

function Invoke-ProductSwap {
    param($State, $Row)

    $ctx = $State.Context
    $spec = $Row.Spec
    $newDir = Join-Path $ctx.Root ('appxserver.new-' + $ctx.Stamp)

    if (Test-Path $newDir) { Remove-Item $newDir -Recurse -Force }
    Expand-ZipToDirectory -ZipPath $Row.Target.Path -Destination $newDir -Marker $spec.Marker -Label $Row.Label

    if ($Row.Target.Build) {
        $identity = Get-ProductIdentityFromDir -AppxHome $newDir
        if ($identity.Build -ne $Row.Target.Build) {
            throw ('unpacked product build {0} does not match the expected {1}' -f $identity.Build, $Row.Target.Build)
        }
    }

    # conf\ wins over the product defaults, exactly like bin\setup.bat.
    Copy-TreeOverlay -Source (Join-Path $ctx.Root 'conf') -Destination $newDir
    Write-UpdateLog -Message ('conf\ overlay applied to {0}' -f (Split-Path -Leaf $newDir)) -LogPath $State.LogPath

    # Start from a clean OSGi framework state. The product archive ships no
    # configuration\org.eclipse.osgi today, but if a future one does, stale framework.info and a
    # half-populated bundle pool must not shadow what bundles.info declares.
    Clear-OsgiFrameworkState -State $State -AppxHome $newDir

    # Customer bundles are carried over as directories plus a bundles.info line, which is exactly
    # the shape the product uses for its own bundles. Nothing is reinstalled through Extension
    # Management: that would leave the bundle with an ephemeral installBundle location and risk a
    # duplicate location for the same singleton symbolic name.
    $exported = @(Export-LiveExtensions -State $State -AppxHome (Join-Path $ctx.Root 'appxserver') -ProductZip $Row.Target.Path)
    $extensionLog = Join-Path $ctx.UpdateLogDir 'extensions.log'
    $plan = New-ExtensionReinstallPlan -AppxHome $newDir -BackupDir $ctx.BackupDir -ProductZip $Row.Target.Path -LogPath $extensionLog

    foreach ($warning in $plan.Warnings) {
        Write-UpdateLog -Level WARN -Message ('extension: {0}' -f $warning) -LogPath $State.LogPath
    }

    # Persist the carry-over list next to the run logs and in the backup directory, so the
    # operator can confirm what the new tree is expected to contain.
    $reinstallPath = Join-Path $ctx.UpdateLogDir 'extensions-to-reinstall.json'
    $reinstallRows = @($plan.CarryOver | ForEach-Object {
            [pscustomobject]@{
                symbolic = $_.symbolic
                version  = $_.version
                dir      = $_.dir
                requires = @($_.requires)
            }
        })
    Write-JsonNoBom -Path $reinstallPath -Object $reinstallRows
    Write-JsonNoBom -Path (Join-Path $ctx.BackupDir 'extensions-to-reinstall.json') -Object $reinstallRows

    Assert-ExtensionPlan -State $State -Expected $exported -Plan $plan -ReinstallPath $reinstallPath

    Restore-CustomerBundles -State $State -AppxHome $newDir -Plan $plan

    $backup = Swap-Directory -LiveDir (Join-Path $ctx.Root 'appxserver') -NewDir $newDir -Stamp $ctx.Stamp
    Write-UpdateLog -Message ('Product swapped; previous installation kept at {0}' -f (Split-Path -Leaf $backup)) -LogPath $State.LogPath
}

function Restore-CustomerBundles {
    param($State, [string]$AppxHome, $Plan)

    # Copy each carried-over bundle into the new tree and register it in bundles.info. Doing this
    # on $newDir before the swap means the product swap installs a tree that is complete on first
    # boot - there is no window where the application runs with missing bundles.
    #
    # bundles.info order does not matter: simpleconfigurator installs every entry first and only
    # then starts them by start level, so a bundle listed before its dependency still resolves.
    $carry = @($Plan.CarryOver)
    if ($carry.Count -eq 0) {
        Write-UpdateLog -Message 'No customer bundles to carry over.' -LogPath $State.LogPath
        return
    }

    $pluginsDir = Join-Path $AppxHome 'plugins'
    New-DirectoryIfMissing -Path $pluginsDir | Out-Null
    $bundlesInfo = Join-Path $AppxHome 'configuration\org.eclipse.equinox.simpleconfigurator\bundles.info'
    if (-not (Test-Path $bundlesInfo)) {
        throw ('cannot register customer bundles: bundles.info missing in the new tree ({0})' -f $bundlesInfo)
    }

    foreach ($item in $carry) {
        $dest = Join-Path $pluginsDir $item.dir
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue }
        Copy-Item -Path $item.source -Destination $dest -Recurse -Force
        Write-UpdateLog -Message ('Carried over {0} {1} -> plugins/{2}' -f $item.symbolic, $item.version, $item.dir) -LogPath $State.LogPath
    }

    # Rewrite bundles.info once: remove any existing line for a carried-over symbolic name so a
    # repeated update cannot accumulate duplicates, then append the registered entries.
    $lines = New-Object System.Collections.ArrayList
    foreach ($line in [System.IO.File]::ReadAllLines($bundlesInfo)) { [void]$lines.Add($line) }
    $carried = @{}
    foreach ($item in $carry) { $carried[$item.symbolic] = $true }

    $kept = New-Object System.Collections.ArrayList
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { [void]$kept.Add($line); continue }
        $name = ($trimmed.Split(','))[0]
        if ($carried.ContainsKey($name)) { continue }
        [void]$kept.Add($line)
    }
    foreach ($item in $carry) {
        [void]$kept.Add(('{0},{1},plugins/{2}/,{3},{4}' -f $item.symbolic, $item.version, $item.dir, 4, 'true'))
    }
    Write-TextNoBom -Path $bundlesInfo -Text (($kept -join "`r`n") + "`r`n")

    Write-UpdateLog -Message ('Registered {0} customer bundle(s) in the new tree bundles.info' -f $carry.Count) -LogPath $State.LogPath

    # Dependency view for the report: makes an incomplete set obvious before boot rather than at
    # the first use of a feature.
    $registered = @{}
    foreach ($line in $kept) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        $parts = $trimmed.Split(',')
        if ($parts.Count -ge 1) { $registered[$parts[0]] = $true }
    }
    foreach ($item in $carry) {
        foreach ($needed in @($item.requires)) {
            if (-not $registered.ContainsKey($needed)) {
                $State.Report.Notes.Add(('extension dependency missing: {0} requires {1}' -f $item.symbolic, $needed))
            }
        }
    }
    Add-ReportNote -Report $State.Report -Text ('customer bundles carried over: {0}' -f $carry.Count)
}

function Clear-OsgiFrameworkState {
    param($State, [string]$AppxHome)

    $pool = Join-Path $AppxHome 'configuration\org.eclipse.osgi'
    if (-not (Test-Path $pool)) { return }

    $frameworkInfo = @(Get-ChildItem -Path $pool -Filter 'framework.info.*' -File -ErrorAction SilentlyContinue)
    $poolDirs = @(Get-ChildItem -Path $pool -Directory -ErrorAction SilentlyContinue)
    if ($frameworkInfo.Count -eq 0 -and $poolDirs.Count -eq 0) { return }

    Write-UpdateLog -Message ('Clearing packaged OSGi framework state ({0} framework.info, {1} pool dir(s)); bundles.info is authoritative' -f $frameworkInfo.Count, $poolDirs.Count) -LogPath $State.LogPath
    Remove-Item -Path $pool -Recurse -Force -ErrorAction SilentlyContinue
}

function Assert-ExtensionPlan {
    param($State, $Expected, $Plan, [string]$ReinstallPath)

    # Every exported bundle must end up in exactly one bucket: carried over, or skipped because
    # the product already ships it. A bundle that falls through both would silently disappear,
    # which is the 2026-11-17 incident.
    $exportedSymbols = @($Expected | ForEach-Object { $_.symbolic })
    $plannedSymbols = @(@($Plan.CarryOver | ForEach-Object { $_.symbolic }) + @($Plan.Skipped | ForEach-Object { ($_ -split ' ')[0] }))
    $orphans = @($exportedSymbols | Where-Object { $plannedSymbols -notcontains $_ })

    $note = ('customer bundles: {0} exported, {1} to carry over, {2} shipped by the product' -f `
            $exportedSymbols.Count, @($Plan.CarryOver).Count, @($Plan.Skipped).Count)
    Add-ReportNote -Report $State.Report -Text $note
    Write-UpdateLog -Message $note -LogPath $State.LogPath
    Write-UpdateLog -Message ('Carry-over list: {0}' -f $ReinstallPath) -LogPath $State.LogPath

    if ($orphans.Count -gt 0) {
        throw ('customer bundle plan incomplete: {0} exported but neither carried over nor explained. Inspect {1}' -f ($orphans -join ', '), $ReinstallPath)
    }
}

# ---------------------------------------------------------------------------
# Database phase
# ---------------------------------------------------------------------------

function Invoke-DbSync {
    param($State)

    $ctx = $State.Context
    $log = Join-Path $ctx.UpdateLogDir 'syncdb.log'
    $rc = Invoke-CommandToLog -LogPath $log -WorkingDirectory $ctx.Root -CommandLine 'call bin\db-sync.bat' -CaptureStdio
    if ($rc -ne 0) {
        throw ('RUN_SyncDB failed (exit {0}); see {1}. Fix the error, then re-run bin\db-sync.bat until it finishes cleanly' -f $rc, $log)
    }
}

function Invoke-SignDatabase {
    param($State)

    $ctx = $State.Context
    $log = Join-Path $ctx.UpdateLogDir 'sign-database.log'
    $rc = Invoke-CommandToLog -LogPath $log -WorkingDirectory (Join-Path $ctx.Root 'appxserver') -CommandLine 'call sign-database-build-alt.bat' -EnvBat $envBat
    if ($rc -ne 0) { throw ('sign-database-build-alt failed (exit {0}); see {1}' -f $rc, $log) }
}

function Invoke-LangImport {
    param($State)

    $ctx = $State.Context
    $log = Join-Path $ctx.UpdateLogDir 'lang-import.log'
    $rc = Invoke-CommandToLog -LogPath $log -WorkingDirectory $ctx.Root -CommandLine 'call bin\db-lang.bat' -CaptureStdio
    if ($rc -ne 0) { throw ('zh_CN import failed (exit {0}); see {1}' -f $rc, $log) }
}

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------

function Get-ExtensionStates {
    param($Pg)
    # ExtensionId -> ExtensionState, for active records only. Returns $null when the
    # database cannot be read (not initialized, not reachable, missing table).
    if (-not (Test-Path (Join-Path $Pg.PgHome 'bin\psql.exe'))) { return $null }
    try {
        $raw = Invoke-PsqlScalar -Pg $Pg -Sql "SELECT ExtensionId || '=' || ExtensionState FROM AD_Extension WHERE IsActive='Y' ORDER BY ExtensionId"
    } catch {
        return $null
    }
    if (-not $raw) { return $null }
    $map = @{}
    foreach ($line in ($raw -split "`r?`n")) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        $idx = $trimmed.IndexOf('=')
        if ($idx -lt 1) { continue }
        $map[$trimmed.Substring(0, $idx)] = $trimmed.Substring($idx + 1)
    }
    if ($map.Count -eq 0) { return $null }
    return $map
}

function Get-ExtensionStateRegressions {
    param([hashtable]$Before, [hashtable]$After)

    # Only extensions that were IN before and are not IN any more are a problem; records
    # that were already UN (or absent) before the update are pre-existing conditions.
    $regressed = @()
    if (-not $Before -or -not $After) { return $regressed }
    foreach ($key in $Before.Keys) {
        if ($Before[$key] -ne 'IN') { continue }
        $now = $After[$key]
        if (-not $now) { $regressed += ('{0} (record disappeared)' -f $key); continue }
        if ($now -ne 'IN') { $regressed += ('{0} (IN -> {1})' -f $key, $now) }
    }
    return $regressed
}

function Invoke-Verify {
    param($State)

    $ctx = $State.Context
    $pg = $State.Pg
    $problems = New-Object System.Collections.ArrayList

    if (-not (Test-DatabaseInitialized -State $State)) {
        Write-UpdateLog -Level WARN -Message 'database not initialized; skipped the database checks' -LogPath $State.LogPath
        Add-ReportNote -Report $State.Report -Text 'database checks skipped (runtime\pgdata is empty)'
    } else {
        $systemInfo = Invoke-PsqlScalar -Pg $pg -Sql 'SELECT Name || '' | '' || Version || '' | '' || COALESCE(LastBuildInfo,''<none>'') || '' | '' || COALESCE(LastMigrationScriptApplied,''<none>'') FROM AD_System'
        if ($systemInfo) {
            Write-UpdateLog -Message ('AD_System: {0}' -f $systemInfo) -LogPath $State.LogPath
            Add-ReportNote -Report $State.Report -Text ('AD_System: ' + $systemInfo)
        } else {
            [void]$problems.Add('AD_System could not be read')
        }

        $migrationCount = Invoke-PsqlScalar -Pg $pg -Sql 'SELECT COUNT(*) FROM AD_MigrationScript'
        Write-UpdateLog -Message ('AD_MigrationScript rows: {0}' -f $migrationCount) -LogPath $State.LogPath
        Add-ReportNote -Report $State.Report -Text ('AD_MigrationScript rows: ' + $migrationCount)

        # Compare against what was installed before the update: pre-existing UN records are not
        # our problem, but an extension that flipped from IN to something else is.
        $before = $State.ExtensionStatesBefore
        $after = Get-ExtensionStates -Pg $pg
        if ($before -and $after) {
            $regressed = @(Get-ExtensionStateRegressions -Before $before -After $after)
            if ($regressed.Count -gt 0) {
                [void]$problems.Add(('extension state regressed: {0}' -f ($regressed -join ', ')))
            }
            $inCount = @($after.Values | Where-Object { $_ -eq 'IN' }).Count
            Add-ReportNote -Report $State.Report -Text ('extensions in state IN: {0}/{1}' -f $inCount, $after.Count)
        } else {
            Add-ReportNote -Report $State.Report -Text 'extension state comparison skipped (no baseline)'
        }
    }

    $bundlesInfo = Join-Path $ctx.Root 'appxserver\configuration\org.eclipse.equinox.simpleconfigurator\bundles.info'
    $bundleCount = 0
    if (Test-Path $bundlesInfo) {
        $bundleCount = (Get-BundlesInfoMap -BundlesInfoPath $bundlesInfo).Count
    } else {
        [void]$problems.Add('bundles.info is missing after the product swap')
    }
    Write-UpdateLog -Message ('bundles.info entries: {0}' -f $bundleCount) -LogPath $State.LogPath

    # Customer bundles must be registered in the new tree, and every customer-bundle dependency
    # between them must still be satisfied. A missing dependent does not fail the boot - OSGi
    # leaves it in INSTALLED and the feature breaks later with an unrelated error - so this is the
    # only place it can be caught while the cause is still obvious.
    $carryPath = Join-Path $ctx.UpdateLogDir 'extensions-to-reinstall.json'
    if (Test-Path $carryPath) {
        $carried = @()
        $carryRaw = Get-Content -Path $carryPath -Raw -Encoding UTF8
        if ($carryRaw -and $carryRaw.Trim()) {
            $decoded = $carryRaw | ConvertFrom-Json
            foreach ($item in @($decoded)) { if ($null -ne $item) { $carried += $item } }
        }
        if ($carried.Count -gt 0) {
            $registered = @{}
            if (Test-Path $bundlesInfo) {
                foreach ($name in (Get-BundlesInfoMap -BundlesInfoPath $bundlesInfo).Keys) { $registered[$name] = $true }
            }
            $missing = New-Object System.Collections.ArrayList
            foreach ($item in $carried) {
                if (-not $registered.ContainsKey($item.symbolic)) {
                    [void]$missing.Add(('{0} (exported but not registered in bundles.info)' -f $item.symbolic))
                    continue
                }
                foreach ($needed in @($item.requires)) {
                    if (-not $registered.ContainsKey($needed)) {
                        [void]$missing.Add(('{0} requires {1} (not registered)' -f $item.symbolic, $needed))
                    }
                }
            }
            if ($missing.Count -gt 0) {
                [void]$problems.Add(('customer bundle verification failed: {0}' -f ($missing -join '; ')))
            } else {
                Add-ReportNote -Report $State.Report -Text ('customer bundles verified: {0} registered, dependencies satisfied' -f $carried.Count)
            }
        }
    }

    $appxMarker = Join-Path $ctx.Root 'appxserver\idempiere.ini'
    if (-not (Test-Path $appxMarker)) { [void]$problems.Add('appxserver\idempiere.ini is missing') }

    if ($problems.Count -gt 0) {
        throw (($problems | ForEach-Object { '- ' + $_ }) -join '; ')
    }
    Write-UpdateLog -Message 'Verification passed.' -LogPath $State.LogPath
}

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

function Invoke-Apply {
    param($State)

    $ctx = $State.Context
    Write-UpdateLog -Message ('myappx-portable update {0}' -f $ctx.Stamp) -LogPath $State.LogPath

    Invoke-Step -State $State -Name 'preflight' -Body {
        if ($SkipPreflight) {
            Write-UpdateLog -Level WARN -Message 'preflight skipped (-SkipPreflight)' -LogPath $State.LogPath
            Assert-DiskSpace -Path $ctx.Root -RequiredGb 1
        } else {
            Test-Preflight -State $State
        }
    }

    Invoke-Step -State $State -Name 'plan' -Body {
        $State.Plan = Resolve-UpdatePlan -Context $ctx
        Write-Host (Format-PlanTable -Plan $State.Plan -Context $ctx)
        foreach ($warningText in $State.Plan.Warnings) { Write-UpdateLog -Level WARN -Message $warningText -LogPath $State.LogPath }
        foreach ($errorText in $State.Plan.Errors) { Write-UpdateLog -Level ERROR -Message $errorText -LogPath $State.LogPath }
        if ($State.Plan.Errors.Count -gt 0) {
            throw ($State.Plan.Errors -join '; ')
        }
        if ($State.Plan.PgMajorChange -and -not $AllowPgMajor) {
            throw ('PostgreSQL data directory is major {0} but the new binaries are {1}; re-run with -AllowPgMajor to run pg_upgrade' -f $ctx.PgDataMajor, $State.Plan.TargetPgMajor)
        }
        Add-ReportNote -Report $State.Report -Text ('manifest: ' + $State.Plan.RemoteStatus)
    }

    if (-not $State.Plan.Changed -and -not $Resume) {
        Write-Host ''
        Write-Host 'Everything is already at the newest available version. Nothing to do.'
        $path = Save-UpdateReport -Report $State.Report -Path (Join-Path $ctx.LogsDir 'update-report.txt') -FallbackPath (Join-Path $env:TEMP 'myappx-update-report.txt')
        Write-Host ('Report: {0}' -f $path)
        Write-Host 'If a previous run stopped after the swap and the database was never migrated, run:'
        Write-Host ('  {0} -Resume' -f (Join-Path $ctx.Root 'bin\update.bat'))
        return 0
    }

    if ($Resume -and -not $State.Plan.Changed) {
        Write-Host ''
        Write-Host '-Resume: re-running the database phase and verification for the installed build.'
    }

    if (-not $Yes) {
        Write-Host ''
        $answer = Read-Host 'Type YES to start the update'
        if ($answer -ne 'YES') {
            Write-Host 'Cancelled.'
            return 1
        }
    }

    if ($Resume) {
        # The product is already swapped; only the database work and verification are missing.
        foreach ($name in 'download', 'backup', 'stop-application', 'stop-database', 'pg-upgrade', 'overlay-pgvector', 'swap-product') {
            Add-SkippedStep -State $State -Name $name -Note 'resumed run: already applied'
        }
    } else {
        Invoke-Step -State $State -Name 'download' -Body {
            Invoke-Downloads -State $State
        }

        if ($SkipBackup) {
            Add-SkippedStep -State $State -Name 'backup' -Note 'disabled with -SkipBackup'
        } else {
            Invoke-Step -State $State -Name 'backup' -Body {
                Invoke-Backup -State $State -IncludeCluster:($State.Plan.PgMajorChange -or $ClusterBackup)
            }
        }

        Invoke-Step -State $State -Name 'stop-application' -Body { Stop-Application -State $State }
        Invoke-Step -State $State -Name 'stop-database' -Body { Stop-Database -State $State }

        foreach ($row in $State.Plan.Rows) {
            if ($row.Name -eq 'product' -or $row.Name -eq 'vector') { continue }
            if ($row.Action -ne 'upgrade' -and $row.Action -ne 'install') { continue }
            $captured = $row
            Invoke-Step -State $State -Name ('swap-' + $captured.Name) -Body {
                Invoke-RuntimeSwap -State $State -Row $captured
            }
        }

        if ($State.Plan.PgMajorChange) {
            Invoke-Step -State $State -Name 'pg-upgrade' -Body {
                Invoke-PgMajorUpgrade -State $State
            }
        } else {
            $note = 'no data directory yet'
            if ($ctx.PgDataMajor) { $note = ('data directory major stays {0}' -f $ctx.PgDataMajor) }
            Add-SkippedStep -State $State -Name 'pg-upgrade' -Note $note
        }

        # pgvector lives inside runtime\pgsql, so a PostgreSQL swap wipes it: re-overlay whenever
        # the binaries changed, even if the pgvector package itself reports "skip".
        $pgsqlSwapped = @($State.Plan.Rows | Where-Object { $_.Name -eq 'pgsql' -and ($_.Action -eq 'upgrade' -or $_.Action -eq 'install') }).Count -gt 0
        $vectorRow = $State.Plan.Rows | Where-Object { $_.Name -eq 'vector' -and ($_.Action -eq 'upgrade' -or $_.Action -eq 'install' -or ($pgsqlSwapped -and $_.Target)) }
        if ($vectorRow) {
            if (-not (Test-Path $vectorRow.Target.Path) -and $vectorRow.Target.Url) {
                Invoke-Step -State $State -Name 'download-pgvector' -Body {
                    Invoke-PackageDownload -Url $vectorRow.Target.Url -Destination $vectorRow.Target.Path -Sha256 $vectorRow.Target.Sha256
                }
            }
            Invoke-Step -State $State -Name 'overlay-pgvector' -Body {
                Invoke-VectorOverlay -State $State -Row $vectorRow
            }
        } elseif ($pgsqlSwapped) {
            throw 'PostgreSQL was replaced but no pgvector package is available; add vector.v<ver>-pg<major>.zip to packages\ and re-run'
        } else {
            Add-SkippedStep -State $State -Name 'overlay-pgvector' -Note 'pgvector already current'
        }

        $productRow = $State.Plan.Rows | Where-Object { $_.Name -eq 'product' -and ($_.Action -eq 'upgrade' -or $_.Action -eq 'install') }
        if ($productRow) {
            Invoke-Step -State $State -Name 'swap-product' -Body {
                Invoke-ProductSwap -State $State -Row $productRow
            }
        } else {
            Invoke-Step -State $State -Name 'refresh-conf' -Body {
                Copy-TreeOverlay -Source (Join-Path $ctx.Root 'conf') -Destination (Join-Path $ctx.Root 'appxserver')
            }
            Add-SkippedStep -State $State -Name 'swap-product' -Note 'product already current'
        }
    }

    Invoke-Step -State $State -Name 'start-database' -Body { Start-Database -State $State }

    if ($State.Plan.PgMajorChange) {
        Invoke-Step -State $State -Name 'pg-portable-config' -Body { Sync-PgPortableConfig -State $State }
    }

    if (-not (Test-DatabaseInitialized -State $State)) {
        Add-SkippedStep -State $State -Name 'db-sync' -Note 'database not initialized'
        Add-SkippedStep -State $State -Name 'sign-database' -Note 'database not initialized'
        Add-SkippedStep -State $State -Name 'db-lang' -Note 'database not initialized'
    } elseif ($SkipDbSync) {
        Add-SkippedStep -State $State -Name 'db-sync' -Note 'disabled with -SkipDbSync; run bin\db-sync.bat later'
        Add-SkippedStep -State $State -Name 'sign-database' -Note 'disabled with -SkipDbSync'
    } else {
        Invoke-Step -State $State -Name 'db-sync' -Body { Invoke-DbSync -State $State }
        Invoke-Step -State $State -Name 'sign-database' -Body { Invoke-SignDatabase -State $State }
        if ($SkipLang) {
            Add-SkippedStep -State $State -Name 'db-lang' -Note 'disabled with -SkipLang'
        } else {
            Invoke-Step -State $State -Name 'db-lang' -Body { Invoke-LangImport -State $State }
        }
    }

    Invoke-Step -State $State -Name 'verify' -Body { Invoke-Verify -State $State }

    Invoke-Step -State $State -Name 'finalize' -Body {
        $names = @{}
        foreach ($row in $State.Plan.Rows) {
            if (-not $row.Target) { continue }
            if ($row.Action -ne 'upgrade' -and $row.Action -ne 'install') { continue }
            if ($row.Target.Source -eq 'manifest' -and -not (Test-Path $row.Target.Path)) { continue }
            $names[$row.Spec.IniKey] = $row.Target.File
        }
        if ($names.Count -gt 0) {
            Set-PackagesIniNames -IniPath (Join-Path $ctx.PackagesDir 'packages.ini') -FileByKey $names
            Write-UpdateLog -Message ('packages.ini updated: {0}' -f (($names.GetEnumerator() | ForEach-Object { $_.Key + '=' + $_.Value }) -join ', ')) -LogPath $State.LogPath
        }
        Remove-OldBackups -Root $ctx.Root -Keep $ctx.Keep
    }

    # Always leave the database stopped: the operator decides when to start the application, and
    # a running postmaster would block the next update or a folder move. -Start is gone with
    # service mode, so there is no conflicting request to honour.
    Invoke-Step -State $State -Name 'stop-database-final' -Body { Stop-DatabaseAtEnd -State $State }

    $path = Save-UpdateReport -Report $State.Report -Path (Join-Path $ctx.LogsDir 'update-report.txt') -FallbackPath (Join-Path $env:TEMP 'myappx-update-report.txt')
    Write-Host ''
    Write-Host ('Update finished. Report: {0}' -f $path)
    Write-Host ('Per-step logs: {0}' -f $ctx.UpdateLogDir)
    Write-Host ('Backups: {0}' -f $ctx.BackupDir)
    Write-Host ''
    Write-Host 'PostgreSQL is stopped. Next:'
    Write-Host ('  {0}' -f (Join-Path $ctx.Root 'start-db.bat'))
    Write-Host ('  {0}' -f (Join-Path $ctx.Root 'run-appxserver.bat'))
    return 0
}

# ---------------------------------------------------------------------------
# Check / download
# ---------------------------------------------------------------------------

function Invoke-Check {
    param($State)

    $ctx = $State.Context
    Write-UpdateLog -Message ('myappx-portable update check ({0}, manifest {1})' -f $ctx.Channel, $State.Plan.RemoteStatus) -LogPath $State.LogPath
    Write-Host (Format-PlanTable -Plan $State.Plan -Context $ctx)
    foreach ($warningText in $State.Plan.Warnings) { Write-Host ('! ' + $warningText) -ForegroundColor DarkYellow }
    foreach ($errorText in $State.Plan.Errors) { Write-Host ('! ' + $errorText) -ForegroundColor Yellow }

    if ($State.Plan.PgMajorChange) {
        Write-Host ''
        Write-Host ('PostgreSQL major change: data directory {0} -> binaries {1}. The update needs -AllowPgMajor.' -f $ctx.PgDataMajor, $State.Plan.TargetPgMajor) -ForegroundColor Yellow
    }

    Add-ReportNote -Report $State.Report -Text ('manifest: ' + $State.Plan.RemoteStatus)
    Add-ReportNote -Report $State.Report -Text ('update available: ' + $State.Plan.Changed)
    $path = Save-UpdateReport -Report $State.Report -Path (Join-Path $ctx.LogsDir 'update-report.txt') -FallbackPath (Join-Path $env:TEMP 'myappx-update-report.txt')
    Write-Host ''
    if ($State.Plan.Changed) {
        Write-Host 'An update is available. Run bin\update.bat to install it.'
        Write-Host ('Report: {0}' -f $path)
        return 2
    }
    Write-Host ('Everything is up to date. Report: {0}' -f $path)
    return 0
}

function Invoke-DownloadOnly {
    param($State)

    if ($State.Plan.Errors.Count -gt 0) { throw ($State.Plan.Errors -join '; ') }
    Invoke-Step -State $State -Name 'download' -Body { Invoke-Downloads -State $State -IncludeUnchanged:(-not $OnlyChanged) }

    $path = Save-UpdateReport -Report $State.Report -Path (Join-Path $State.Context.LogsDir 'update-report.txt') -FallbackPath (Join-Path $env:TEMP 'myappx-update-report.txt')
    Write-Host ('Packages are in {0}. Report: {1}' -f $State.Context.PackagesDir, $path)
    return 0
}

# ---------------------------------------------------------------------------
# Rollback
# ---------------------------------------------------------------------------

function Invoke-Rollback {
    param($State)

    $ctx = $State.Context
    if (-not $Stamp) {
        $candidates = @()
        $candidates += @(Get-ChildItem -Path $ctx.Root -Filter 'appxserver.bak-*' -Directory -ErrorAction SilentlyContinue)
        $candidates += @(Get-ChildItem -Path (Join-Path $ctx.Root 'runtime') -Filter 'pgdata.bak-*' -Directory -ErrorAction SilentlyContinue)
        if ($candidates.Count -eq 0) { throw 'no backup found; nothing to roll back' }
        $latest = $candidates | Sort-Object Name -Descending | Select-Object -First 1
        $derived = ($latest.Name -replace '^.*\.bak-', '')
        $script:Stamp = $derived
        $ctx.Stamp = $derived
        Write-UpdateLog -Message ('No stamp given; using the newest backup: {0}' -f $derived) -LogPath $State.LogPath
    }

    Invoke-Step -State $State -Name 'preflight' -Body {
        if ($SkipPreflight) {
            Write-UpdateLog -Level WARN -Message 'preflight skipped (-SkipPreflight)' -LogPath $State.LogPath
        } else {
            Test-Preflight -State $State
        }
    }

    Invoke-Step -State $State -Name 'stop-application' -Body { Stop-Application -State $State }
    Invoke-Step -State $State -Name 'stop-database' -Body { Stop-Database -State $State }

    Invoke-Step -State $State -Name 'restore-product' -Body {
        $backup = Join-Path $ctx.Root ('appxserver.bak-' + $ctx.Stamp)
        if (-not (Test-Path $backup)) { throw ('no product backup at {0}' -f $backup) }
        $current = Join-Path $ctx.Root 'appxserver'
        if (Test-Path $current) {
            $discard = Join-Path $ctx.Root ('appxserver.rolledback-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Rename-Item -Path $current -NewName (Split-Path -Leaf $discard)
        }
        Rename-Item -Path $backup -NewName 'appxserver'
    }

    foreach ($name in @('jdk', 'pgsql', 'python', 'pgdata')) {
        $backup = Join-Path $ctx.Root ('runtime\' + $name + '.bak-' + $ctx.Stamp)
        if (-not (Test-Path $backup)) { continue }
        $captured = $backup
        $capturedName = $name
        Invoke-Step -State $State -Name ('restore-' + $capturedName) -Body {
            $live = Join-Path $ctx.Root ('runtime\' + $capturedName)
            if (Test-Path $live) {
                $discard = $live + '.rolledback-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
                Rename-Item -Path $live -NewName (Split-Path -Leaf $discard)
            }
            Rename-Item -Path $captured -NewName $capturedName
        }
    }

    Invoke-Step -State $State -Name 'start-database' -Body { Start-Database -State $State }

    if ($RestoreDb) {
        Invoke-Step -State $State -Name 'restore-database' -Body {
            $dump = Join-Path $ctx.BackupDir 'appx.dump'
            if (-not (Test-Path $dump)) { throw ('no dump at {0}; cannot restore the database' -f $dump) }
            $pgCtl = Join-Path $State.Pg.PgHome 'bin\pg_ctl.exe'
            Start-DetachedCommand -CommandLine ('"' + $pgCtl + '" -D "' + $State.Pg.PgData + '" -m fast stop') `
                -LogPath (Join-Path $ctx.UpdateLogDir 'restore-stop-db.log') | Out-Null
            Start-Sleep -Seconds 3

            $previous = $env:PGPASSWORD
            $env:PGPASSWORD = $State.Pg.SystemPassword
            try {
                & (Join-Path $State.Pg.PgHome 'bin\dropdb.exe') -h $State.Pg.Host -p $State.Pg.Port -U $State.Pg.SystemUser --if-exists $State.Pg.Database
                if ($LASTEXITCODE -ne 0) { throw 'dropdb failed' }
                & (Join-Path $State.Pg.PgHome 'bin\createdb.exe') -h $State.Pg.Host -p $State.Pg.Port -U $State.Pg.SystemUser -O $State.Pg.User $State.Pg.Database
                if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }
            } finally {
                $env:PGPASSWORD = $previous
            }

            $env:PGPASSWORD = $State.Pg.Password
            try {
                & (Join-Path $State.Pg.PgHome 'bin\pg_restore.exe') -h $State.Pg.Host -p $State.Pg.Port -U $State.Pg.User -d $State.Pg.Database --no-owner --no-privileges $dump
                if ($LASTEXITCODE -ne 0) { throw ('pg_restore failed with exit code {0}' -f $LASTEXITCODE) }
            } finally {
                $env:PGPASSWORD = $previous
            }
            Start-DetachedCommand -CommandLine ('"' + $pgCtl + '" -D "' + $State.Pg.PgData + '" -l "' +
                (Join-Path $ctx.Root 'runtime\logs\postgres.log') + '" -o "-F -p ' + $State.Pg.Port + '" -W start') `
                -LogPath (Join-Path $ctx.UpdateLogDir 'restore-start-db.log') | Out-Null
            if (-not (Wait-PgReady -PgHome $State.Pg.PgHome -Port $State.Pg.Port -TimeoutSec 120)) {
                throw 'PostgreSQL did not restart after the database restore'
            }
        }
    } else {
        Add-SkippedStep -State $State -Name 'restore-database' -Note 'passed -RestoreDb not set; the database keeps the migrated schema'
    }

    Invoke-Step -State $State -Name 'restore-packages-ini' -Body {
        $saved = Join-Path $ctx.BackupDir 'packages.ini'
        if (Test-Path $saved) {
            Copy-Item -Path $saved -Destination (Join-Path $ctx.PackagesDir 'packages.ini') -Force
        }
    }

    Invoke-Step -State $State -Name 'stop-database-final' -Body { Stop-DatabaseAtEnd -State $State }

    $path = Save-UpdateReport -Report $State.Report -Path (Join-Path $ctx.LogsDir 'update-report.txt') -FallbackPath (Join-Path $env:TEMP 'myappx-update-report.txt')
    Write-Host ''
    Write-Host 'Rollback finished. Migration scripts are not reversible: only -RestoreDb returns the schema to the pre-update state.'
    Write-Host ('Report: {0}' -f $path)
    Write-Host ''
    Write-Host 'PostgreSQL is stopped. Start it with start-db.bat when you are ready.'
    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$exitCode = 0
$state = $null

try {
    if ($Action -eq 'manifest') {
        $target = Join-Path $portableRootForSettings 'packages'
        if ($PackagesDir) { $target = $PackagesDir }
        New-PackageManifest -PackagesDir $target -Channel $Channel -BaseUrl $BaseUrl -IncludeSha256 | Out-Null
        exit 0
    }

    if ($Action -eq 'rollback') {
        $state = New-UpdateState -Title 'myappx-portable rollback'
        $state.Pg = Get-PgConnectionInfo -Root $state.Context.Root
        $exitCode = Invoke-Rollback -State $state
        exit $exitCode
    }

    $state = New-UpdateState -Title ('myappx-portable update ({0})' -f $Action)
    $state.Pg = Get-PgConnectionInfo -Root $state.Context.Root
    $state.Plan = Resolve-UpdatePlan -Context $state.Context
    if ($Force -and $Action -eq 'apply') { Set-PlanForce -Plan $state.Plan }

    if ($Action -eq 'check') {
        $exitCode = Invoke-Check -State $state
    } elseif ($Action -eq 'download') {
        $exitCode = Invoke-DownloadOnly -State $state
    } else {
        $exitCode = Invoke-Apply -State $state
    }
} catch {
    Write-UpdateLog -Level ERROR -Message $_.Exception.Message -LogPath $(if ($state) { $state.LogPath } else { $null })
    if ($state -and $state.Report) {
        $state.Report.Overall = 1
        $path = Save-UpdateReport -Report $state.Report -Path (Join-Path $state.Context.LogsDir 'update-report.txt') -FallbackPath (Join-Path $env:TEMP 'myappx-update-report.txt')
        Write-Host ('Report: {0}' -f $path)
    }
    # A failed run must not leave PostgreSQL running either: the operator needs a predictable
    # state before retrying, and postmaster.pid would block the next attempt.
    if ($state -and $state.Context) {
        try {
            $pgInfo = Get-PgConnectionInfo -Root $state.Context.Root
            $ready = Join-Path $pgInfo.PgHome 'bin\pg_isready.exe'
            $stillUp = $false
            if (Test-Path $ready) {
                & $ready -h 127.0.0.1 -p $pgInfo.Port -q 2>$null
                $stillUp = ($LASTEXITCODE -eq 0)
            }
            if ($stillUp) {
                Write-Host 'Stopping PostgreSQL after the failure ...'
                $pgCtl = Join-Path $pgInfo.PgHome 'bin\pg_ctl.exe'
                if (Test-Path $pgCtl) {
                    Start-DetachedCommand -CommandLine ('"' + $pgCtl + '" -D "' + $pgInfo.PgData + '" -m fast stop') `
                        -LogPath (Join-Path $state.Context.UpdateLogDir 'stop-db-after-failure.log') | Out-Null
                }
            }
        } catch {
            Write-Host ('Could not stop PostgreSQL: {0}' -f $_.Exception.Message)
        }
    }
    $exitCode = 1
} finally {
    if ($state -and $state.Context -and (Test-Path $state.Context.TempDir)) {
        Remove-Item -Path $state.Context.TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $exitCode
