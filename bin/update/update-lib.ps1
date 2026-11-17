# update-lib.ps1 - shared helpers for the myappx-portable update scripts.
#
# Dot-source this file from update.ps1 / make-manifest.ps1. Windows PowerShell 5.1.
# Nothing in here changes system state by itself; every mutating helper is explicit.

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

$script:UpdateLibRoot = $PSScriptRoot
$script:TarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------------------
# Logging and reporting
# ---------------------------------------------------------------------------

function Write-UpdateLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [string]$LogPath
    )
    $line = '[{0}] {1} {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    switch ($Level) {
        'WARN' { Write-Host $Message -ForegroundColor Yellow }
        'ERROR' { Write-Host $Message -ForegroundColor Red }
        default { Write-Host $Message }
    }
    if ($LogPath) {
        try { Add-Content -Path $LogPath -Value $line -Encoding UTF8 } catch { }
    }
}

function New-UpdateReport {
    param([string]$Title, [string]$Root, [string]$Stamp)
    return [pscustomobject]@{
        Title = $Title
        Root = $Root
        Stamp = $Stamp
        Started = (Get-Date)
        Rows = New-Object System.Collections.ArrayList
        Notes = New-Object System.Collections.ArrayList
        Overall = 0
    }
}

function Add-ReportRow {
    param(
        $Report,
        [string]$Step,
        [string]$Result,
        [int]$ExitCode,
        [int]$Seconds,
        [string]$Note = ''
    )
    $clean = ($Note -replace '"', "'") -replace '[\r\n]+', ' '
    [void]$Report.Rows.Add([pscustomobject]@{
            Step = $Step; Result = $Result; Exit = $ExitCode; Seconds = $Seconds; Note = $clean
        })
    if ($Result -ne 'OK' -and $Result -ne 'SKIP') { $Report.Overall = 1 }
}

function Add-ReportNote {
    param($Report, [string]$Text)
    [void]$Report.Notes.Add($Text)
}

function Save-UpdateReport {
    param($Report, [string]$Path, [string]$FallbackPath)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine($Report.Title)
    [void]$sb.AppendLine(('Started: {0}' -f $Report.Started.ToString('yyyy-MM-dd HH:mm:ss')))
    [void]$sb.AppendLine(('Root: {0}' -f $Report.Root))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("Step`tResult`tExit`tSeconds`tNote")
    foreach ($row in $Report.Rows) {
        $fields = @(('{0}' -f $row.Step), ('{0}' -f $row.Result), ('{0}' -f $row.Exit), ('{0}' -f $row.Seconds), ('"{0}"' -f $row.Note))
        [void]$sb.AppendLine($fields -join "`t")
    }
    if ($Report.Notes.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('Notes:')
        foreach ($n in $Report.Notes) { [void]$sb.AppendLine(('  {0}' -f $n)) }
    }
    [void]$sb.AppendLine('')
    $word = 'FAIL'
    if ($Report.Overall -eq 0) { $word = 'OK' }
    [void]$sb.AppendLine(('OVERALL: {0}' -f $word))
    [void]$sb.AppendLine(('Finished: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))

    $text = $sb.ToString()
    try {
        [System.IO.File]::WriteAllText($Path, $text, $script:Utf8NoBom)
        return $Path
    } catch {
        [System.IO.File]::WriteAllText($FallbackPath, $text, $script:Utf8NoBom)
        return $FallbackPath
    }
}

# ---------------------------------------------------------------------------
# Small IO helpers
# ---------------------------------------------------------------------------

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    return $Path
}

function Read-IniFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $map = @{}
    if (-not (Test-Path $Path)) { return $map }
    foreach ($raw in [System.IO.File]::ReadAllLines($Path)) {
        $line = $raw.Trim()
        if (-not $line) { continue }
        if ($line.StartsWith('#') -or $line.StartsWith(';')) { continue }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $line.Substring(0, $idx).Trim()
        $value = $line.Substring($idx + 1).Trim()
        $map[$key] = $value
    }
    return $map
}

function Read-BatSetVars {
    param([Parameter(Mandatory = $true)][string]$Path)
    $map = @{}
    if (-not (Test-Path $Path)) { return $map }
    $pattern = '^\s*@?\s*SET\s+"?(?<k>[A-Za-z0-9_]+)"?\s*=\s*(?<v>.*)$'
    foreach ($raw in [System.IO.File]::ReadAllLines($Path)) {
        $m = [regex]::Match($raw, $pattern, 'IgnoreCase')
        if ($m.Success) { $map[$m.Groups['k'].Value.ToUpper()] = $m.Groups['v'].Value.Trim() }
    }
    return $map
}

function Write-TextNoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom)
}

function Write-JsonNoBom {
    param([string]$Path, $Object, [int]$Depth = 8)
    $json = $Object | ConvertTo-Json -Depth $Depth
    Write-TextNoBom -Path $Path -Text ($json + "`r`n")
}

# ---------------------------------------------------------------------------
# Version helpers
# ---------------------------------------------------------------------------

function Compare-VersionString {
    param([string]$Left, [string]$Right)

    $l = @([regex]::Matches([string]$Left, '\d+') | ForEach-Object { [uint64]$_.Value })
    $r = @([regex]::Matches([string]$Right, '\d+') | ForEach-Object { [uint64]$_.Value })
    $n = [Math]::Max($l.Count, $r.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $a = [uint64]0
        $b = [uint64]0
        if ($i -lt $l.Count) { $a = $l[$i] }
        if ($i -lt $r.Count) { $b = $r[$i] }
        if ($a -lt $b) { return -1 }
        if ($a -gt $b) { return 1 }
    }
    return 0
}

function Compare-Candidate {
    param($Left, $Right)
    # Product packages are identified by the p2 build stamp; other components by version.
    if ($Left.Build -and $Right.Build) {
        $lb = [decimal]$Left.Build
        $rb = [decimal]$Right.Build
        if ($lb -lt $rb) { return -1 }
        if ($lb -gt $rb) { return 1 }
    }
    return (Compare-VersionString -Left $Left.Version -Right $Right.Version)
}

# ---------------------------------------------------------------------------
# Zip helpers
# ---------------------------------------------------------------------------

function Get-ZipEntryText {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$EntryName
    )
    $wanted = $EntryName -replace '\\', '/'
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = $zip.Entries | Where-Object { ($_.FullName -replace '\\', '/') -eq $wanted } | Select-Object -First 1
        if (-not $entry) { return $null }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { return $reader.ReadToEnd() } finally { $reader.Close() }
    } finally { $zip.Dispose() }
}

function Get-ZipEntryNames {
    param([Parameter(Mandatory = $true)][string]$ZipPath)

    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        return @($zip.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
    } finally { $zip.Dispose() }
}

function Test-ZipHasEntry {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$EntryName
    )
    $wanted = $EntryName -replace '\\', '/'
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        return [bool]($zip.Entries | Where-Object { ($_.FullName -replace '\\', '/') -eq $wanted } | Select-Object -First 1)
    } finally { $zip.Dispose() }
}

function Get-ProductIdentityFromZip {
    param([Parameter(Mandatory = $true)][string]$ZipPath)

    $result = [pscustomobject]@{ Build = $null; Version = $null }
    # The product archive keeps artifacts.xml at the root or one level down (appxserver/).
    $candidates = @('artifacts.xml', 'appxserver/artifacts.xml')
    $text = $null
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($name in $candidates) {
            $entry = $zip.Entries | Where-Object { ($_.FullName -replace '\\', '/') -eq $name } | Select-Object -First 1
            if (-not $entry) { continue }
            $reader = New-Object System.IO.StreamReader($entry.Open())
            try { $text = $reader.ReadToEnd() } finally { $reader.Close() }
            break
        }
    } finally { $zip.Dispose() }
    if (-not $text) { return $result }

    $m = [regex]::Match($text, "name='p2\.timestamp'\s+value='(\d+)'")
    if ($m.Success) { $result.Build = $m.Groups[1].Value }
    $v = [regex]::Match($text, "id='org\.adempiere\.server'\s+version='([^']+)'")
    if ($v.Success) { $result.Version = $v.Groups[1].Value }
    return $result
}

function Get-ProductIdentityFromDir {
    param([Parameter(Mandatory = $true)][string]$AppxHome)

    $result = [pscustomobject]@{ Build = $null; Version = $null }
    $artifacts = Join-Path $AppxHome 'artifacts.xml'
    if (-not (Test-Path $artifacts)) { return $result }
    $text = [System.IO.File]::ReadAllText($artifacts)
    $m = [regex]::Match($text, "name='p2\.timestamp'\s+value='(\d+)'")
    if ($m.Success) { $result.Build = $m.Groups[1].Value }
    $v = [regex]::Match($text, "id='org\.adempiere\.server'\s+version='([^']+)'")
    if ($v.Success) { $result.Version = $v.Groups[1].Value }
    return $result
}

# ---------------------------------------------------------------------------
# Component definitions
# ---------------------------------------------------------------------------

function Get-ComponentSpecs {
    # Order matters: runtime packages first, product last.
    return @(
        [pscustomobject]@{
            Name = 'jdk'; Label = 'JDK'; Dir = 'runtime\jdk'; Marker = 'bin\java.exe'
            Pattern = '^microsoft-jdk-(?<ver>[0-9][0-9.]*)-windows'; IniKey = 'JDK_ZIP'
        },
        [pscustomobject]@{
            Name = 'pgsql'; Label = 'PostgreSQL'; Dir = 'runtime\pgsql'; Marker = 'bin\postgres.exe'
            Pattern = '^postgresql-(?<ver>[0-9][0-9.]*)(?:-(?<build>[0-9]+))?-windows'; IniKey = 'PGSQL_ZIP'
        },
        [pscustomobject]@{
            Name = 'vector'; Label = 'pgvector'; Dir = 'runtime\pgsql'; Marker = 'share\extension\vector.control'
            Pattern = '^vector\.v?(?<ver>[0-9][0-9.]*)-pg(?<pgmajor>[0-9]+)'; IniKey = 'VECTOR_ZIP'
        },
        [pscustomobject]@{
            Name = 'python'; Label = 'Python'; Dir = 'runtime\python'; Marker = 'python.exe'
            Pattern = '^python-(?<ver>[0-9][0-9.]*)-embed'; IniKey = 'PYTHON_ZIP'
        },
        [pscustomobject]@{
            Name = 'product'; Label = 'AppxServer'; Dir = 'appxserver'; Marker = 'idempiere.ini'
            Pattern = '^myappxserver-(?<ver>[0-9][^-]*(?:[0-9])[^-]*)-(?:win32|linux|macosx)'; IniKey = 'APPX_ZIP'
        }
    )
}

function Get-MajorFromVersion {
    param([string]$Version)
    if (-not $Version) { return $null }
    $m = [regex]::Match($Version, '^([0-9]+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return $null
}

function Get-InstalledComponentInfo {
    param($Spec, [string]$Root)

    $dir = Join-Path $Root $Spec.Dir
    $markerPath = Join-Path $dir $Spec.Marker
    $info = [pscustomobject]@{
        Name = $Spec.Name; Label = $Spec.Label; Present = (Test-Path $markerPath)
        Version = $null; Build = $null; PgMajor = $null; Dir = $dir
    }
    if (-not $info.Present) { return $info }

    switch ($Spec.Name) {
        'jdk' {
            $release = Join-Path $dir 'release'
            if (Test-Path $release) {
                $m = [regex]::Match([System.IO.File]::ReadAllText($release), 'JAVA_VERSION="([^"]+)"')
                if ($m.Success) { $info.Version = $m.Groups[1].Value }
            }
            if (-not $info.Version) {
                try {
                    $out = (& (Join-Path $dir 'bin\java.exe') -version 2>&1 | Out-String)
                    $m = [regex]::Match($out, 'version "([^"]+)"')
                    if ($m.Success) { $info.Version = $m.Groups[1].Value }
                } catch { }
            }
        }
        'pgsql' {
            try {
                $out = (& (Join-Path $dir 'bin\postgres.exe') -V 2>&1 | Out-String)
                $m = [regex]::Match($out, '(\d+(?:\.\d+)*)')
                if ($m.Success) { $info.Version = $m.Groups[1].Value }
            } catch { }
            $info.PgMajor = Get-MajorFromVersion -Version $info.Version
        }
        'python' {
            try {
                $out = (& (Join-Path $dir 'python.exe') -V 2>&1 | Out-String)
                $m = [regex]::Match($out, '(\d+\.\d+\.\d+)')
                if ($m.Success) { $info.Version = $m.Groups[1].Value }
            } catch { }
        }
        'vector' {
            $control = Join-Path $dir $Spec.Marker
            if (Test-Path $control) {
                $m = [regex]::Match([System.IO.File]::ReadAllText($control), "default_version\s*=\s*'([^']+)'")
                if ($m.Success) { $info.Version = $m.Groups[1].Value }
            }
            $pgInfo = Get-InstalledComponentInfo -Spec (Get-ComponentSpecs | Where-Object { $_.Name -eq 'pgsql' }) -Root $Root
            $info.PgMajor = $pgInfo.PgMajor
        }
        'product' {
            $identity = Get-ProductIdentityFromDir -AppxHome $dir
            $info.Version = $identity.Version
            $info.Build = $identity.Build
        }
    }
    return $info
}

function Get-PgDataMajor {
    param([string]$Root)
    $versionFile = Join-Path $Root 'runtime\pgdata\PG_VERSION'
    if (-not (Test-Path $versionFile)) { return $null }
    $raw = ([System.IO.File]::ReadAllText($versionFile)).Trim()
    $m = [regex]::Match($raw, '^([0-9]+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return $null
}

# ---------------------------------------------------------------------------
# Package candidates
# ---------------------------------------------------------------------------

function Get-LocalPackageCandidates {
    param(
        [Parameter(Mandatory = $true)]$Spec,
        [Parameter(Mandatory = $true)][string]$PackagesDir,
        [string]$IniFileName
    )

    $candidates = New-Object System.Collections.ArrayList
    $seen = @{}
    $pattern = [regex]$Spec.Pattern

    $names = New-Object System.Collections.ArrayList
    # packages.ini names one file; local *.zip scan finds everything else (newer builds included).
    if ($IniFileName) { [void]$names.Add($IniFileName) }
    if (Test-Path $PackagesDir) {
        foreach ($file in Get-ChildItem -Path $PackagesDir -Filter '*.zip' -File) {
            if ($pattern.IsMatch($file.Name)) { [void]$names.Add($file.Name) }
        }
    }

    foreach ($fileName in $names) {
        if (-not $fileName) { continue }
        $key = $fileName.ToLower()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        $path = Join-Path $PackagesDir $fileName
        if (-not (Test-Path $path)) { continue }

        $match = $pattern.Match($fileName)
        $candidate = [pscustomobject]@{
            Spec = $Spec; File = $fileName; Path = $path; Source = 'local'
            Version = $null; Build = $null; PgMajor = $null; Url = $null; Sha256 = $null
        }
        if ($match.Success) {
            if ($match.Groups['ver'].Success) { $candidate.Version = $match.Groups['ver'].Value }
            if ($match.Groups['pgmajor'].Success) { $candidate.PgMajor = [int]$match.Groups['pgmajor'].Value }
        }
        if ($Spec.Name -eq 'product') {
            try {
                $identity = Get-ProductIdentityFromZip -ZipPath $path
                $candidate.Build = $identity.Build
                if ($identity.Version) { $candidate.Version = $identity.Version }
            } catch {
                Write-UpdateLog -Level WARN -Message ('cannot read product identity from {0}: {1}' -f $fileName, $_.Exception.Message)
            }
        }
        if (-not $candidate.Version) { continue }
        [void]$candidates.Add($candidate)
    }

    return $candidates.ToArray()
}

# ---------------------------------------------------------------------------
# Remote manifest
# ---------------------------------------------------------------------------

function Get-RemoteManifest {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$ManifestName,
        [int]$TimeoutSec = 20
    )

    $url = $BaseUrl.TrimEnd('/') + '/' + $ManifestName
    $tmp = Join-Path $env:TEMP ('appx-manifest-' + [guid]::NewGuid().ToString('N') + '.json')
    & curl.exe -fsSL --max-time $TimeoutSec -o $tmp $url 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) {
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        return $null
    }
    try {
        return (Get-Content -Path $tmp -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Get-RemoteComponentEntry {
    param($Manifest, [string]$Channel, [string]$ComponentName)

    if (-not $Manifest) { return $null }
    if (-not $Manifest.channels) { return $null }
    $channelNode = $Manifest.channels.PSObject.Properties[$Channel]
    if (-not $channelNode) { return $null }
    $componentNode = $channelNode.Value.PSObject.Properties[$ComponentName]
    if (-not $componentNode) { return $null }
    return $componentNode.Value
}

# ---------------------------------------------------------------------------
# Plan resolution
# ---------------------------------------------------------------------------

function New-UpdateContext {
    param(
        [string]$Root,
        [string]$PackagesDir,
        [string]$Stamp,
        [string]$BaseUrl,
        [string]$Channel,
        [string]$ManifestName,
        [bool]$Offline = $false,
        [int]$Keep = 3
    )

    if (-not $Root) {
        $Root = (Resolve-Path (Join-Path $script:UpdateLibRoot '..\..')).Path
    } else {
        $Root = (Resolve-Path $Root).Path
    }
    if (-not $PackagesDir) { $PackagesDir = Join-Path $Root 'packages' }
    if (-not (Test-Path $PackagesDir)) { New-Item -ItemType Directory -Path $PackagesDir -Force | Out-Null }
    if (-not $Stamp) { $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss' }
    if (-not $Channel) { $Channel = 'latest' }
    if (-not $ManifestName) { $ManifestName = 'packages.json' }

    $logsDir = Join-Path $Root 'runtime\logs'
    $updateLogDir = Join-Path $logsDir ('update\' + $Stamp)
    $backupDir = Join-Path $Root ('runtime\backup\' + $Stamp)
    $tmpDir = Join-Path $env:TEMP ('appx-update-' + $Stamp)

    return [pscustomobject]@{
        Root = $Root
        PackagesDir = $PackagesDir
        Stamp = $Stamp
        BaseUrl = $BaseUrl
        Channel = $Channel
        ManifestName = $ManifestName
        Offline = $Offline
        Keep = $Keep
        LogsDir = $logsDir
        UpdateLogDir = $updateLogDir
        BackupDir = $backupDir
        TempDir = $tmpDir
        PgDataMajor = (Get-PgDataMajor -Root $Root)
    }
}

function Resolve-UpdatePlan {
    param([Parameter(Mandatory = $true)]$Context)

    $specs = Get-ComponentSpecs
    $ini = Read-IniFile -Path (Join-Path $Context.PackagesDir 'packages.ini')

    $installed = @{}
    foreach ($spec in $specs) {
        $installed[$spec.Name] = Get-InstalledComponentInfo -Spec $spec -Root $Context.Root
    }

    $remote = $null
    $remoteStatus = 'disabled'
    if (-not $Context.Offline -and $Context.BaseUrl) {
        $remote = Get-RemoteManifest -BaseUrl $Context.BaseUrl -ManifestName $Context.ManifestName
        if ($remote) { $remoteStatus = 'ok' } else { $remoteStatus = 'unreachable' }
    } elseif ($Context.Offline) {
        $remoteStatus = 'offline'
    }

    $rows = New-Object System.Collections.ArrayList
    $errors = New-Object System.Collections.ArrayList
    $warnings = New-Object System.Collections.ArrayList

    foreach ($spec in $specs) {
        $local = Get-LocalPackageCandidates -Spec $spec -PackagesDir $Context.PackagesDir -IniFileName $ini[$spec.IniKey]

        $bestLocal = $null
        foreach ($candidate in $local) {
            if (-not $bestLocal -or (Compare-Candidate -Left $candidate -Right $bestLocal) -gt 0) {
                $bestLocal = $candidate
            }
        }

        $remoteCandidate = $null
        $entry = Get-RemoteComponentEntry -Manifest $remote -Channel $Context.Channel -ComponentName $spec.Name
        if ($entry -and $entry.file) {
            $remoteCandidate = [pscustomobject]@{
                Spec = $spec; File = $entry.file; Path = (Join-Path $Context.PackagesDir $entry.file)
                Source = 'manifest'; Url = $entry.url
                Version = $entry.version; Build = $entry.build
                PgMajor = $entry.pgMajor; Sha256 = $entry.sha256; Size = $entry.size
            }
            if ($remoteCandidate.Build) { $remoteCandidate.Build = [string]$remoteCandidate.Build }
        }

        $target = $bestLocal
        if ($remoteCandidate) {
            if (-not $target) {
                $target = $remoteCandidate
            } else {
                $cmp = Compare-Candidate -Left $remoteCandidate -Right $target
                if ($cmp -gt 0) { $target = $remoteCandidate }
                elseif ($cmp -eq 0 -and (Test-Path $target.Path)) { $target.Source = 'local' }
            }
        }

        $inst = $installed[$spec.Name]
        $action = 'skip'
        $needsDownload = $false
        if ($target) {
            $needsDownload = -not (Test-Path $target.Path)
            if (-not $needsDownload -and $target.Sha256) {
                # Same file name can mean a different build (product zips are always "-latest").
                $actual = (Get-FileHash -Path $target.Path -Algorithm SHA256).Hash
                if ($actual -ne $target.Sha256.ToLower() -and $actual -ne $target.Sha256.ToUpper()) {
                    $needsDownload = $true
                }
            }
            if (-not $inst.Present) {
                $action = 'install'
            } elseif ((Compare-Candidate -Left $target -Right $inst) -gt 0) {
                $action = 'upgrade'
            } else {
                $action = 'skip'
            }
        } elseif (-not $inst.Present) {
            $action = 'unavailable'
            [void]$warnings.Add(('{0}: no package in packages\ and not installed' -f $spec.Label))
        } else {
            $action = 'skip'
            [void]$warnings.Add(('{0}: no package in packages\; keeping the installed {1}' -f $spec.Label, $inst.Version))
        }

        [void]$rows.Add([pscustomobject]@{
                Name = $spec.Name; Label = $spec.Label; Spec = $spec
                Installed = $inst; Target = $target
                Action = $action; NeedsDownload = $needsDownload
            })
    }

    # pgvector must match the PostgreSQL major version the new binaries provide.
    $pgRow = $rows | Where-Object { $_.Name -eq 'pgsql' }
    $vecRow = $rows | Where-Object { $_.Name -eq 'vector' }
    $targetPgMajor = $null
    if ($pgRow -and $pgRow.Target) { $targetPgMajor = Get-MajorFromVersion -Version $pgRow.Target.Version }
    $pgMajorChange = ($targetPgMajor -and $Context.PgDataMajor -and $targetPgMajor -ne $Context.PgDataMajor)
    if ($pgMajorChange -and $vecRow.Target -and $vecRow.Target.PgMajor) {
        if ([int]$vecRow.Target.PgMajor -ne [int]$targetPgMajor) {
            [void]$errors.Add(('pgvector package targets PostgreSQL {0} but the new PostgreSQL is {1}; add vector.v<ver>-pg{1}.zip to packages\' -f $vecRow.Target.PgMajor, $targetPgMajor))
        }
    }

    $changed = @($rows | Where-Object { $_.Action -eq 'upgrade' -or $_.Action -eq 'install' }).Count -gt 0

    return [pscustomobject]@{
        Rows = $rows
        Errors = $errors
        Warnings = $warnings
        Changed = $changed
        RemoteStatus = $remoteStatus
        TargetPgMajor = $targetPgMajor
        PgMajorChange = $pgMajorChange
        Installed = $installed
    }
}

function Format-PlanTable {
    param($Plan, $Context)

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('')
    [void]$lines.Add(('Component     Installed            -> Target               Action'))
    [void]$lines.Add(('------------- -------------------- --------------------- -------'))
    foreach ($row in $Plan.Rows) {
        $left = '-'
        if ($row.Installed.Present) {
            $left = [string]$row.Installed.Version
            if ($row.Installed.Build) { $left = '{0} ({1})' -f $row.Installed.Version, $row.Installed.Build }
        }
        $right = '-'
        if ($row.Target) {
            $right = [string]$row.Target.Version
            if ($row.Target.Build) { $right = '{0} ({1})' -f $row.Target.Version, $row.Target.Build }
            if ($row.NeedsDownload -and ($row.Action -eq 'upgrade' -or $row.Action -eq 'install')) { $right = $right + ' *' }
        }
        [void]$lines.Add(('{0,-13} {1,-20} -> {2,-21} {3}' -f $row.Label, $left, $right, $row.Action))
    }
    [void]$lines.Add('')
    [void]$lines.Add(('Packages: {0}' -f $Context.PackagesDir))
    [void]$lines.Add(('Manifest: {0}' -f $Plan.RemoteStatus))
    if ($Plan.PgMajorChange) {
        [void]$lines.Add(('PostgreSQL data directory major: {0} -> binaries {1} (pg_upgrade required)' -f $Context.PgDataMajor, $Plan.TargetPgMajor))
    }
    foreach ($note in @($Plan.Rows | Where-Object { $_.NeedsDownload -and ($_.Action -eq 'upgrade' -or $_.Action -eq 'install') })) {
        [void]$lines.Add(('* {0} will be downloaded from {1}' -f $note.Target.File, $note.Target.Url))
    }
    return ($lines -join [Environment]::NewLine)
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

function Invoke-PackageDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$Sha256
    )

    $part = $Destination + '.part'
    if (Test-Path $part) { Remove-Item $part -Force }
    Write-UpdateLog -Message ('Downloading {0}' -f $Url)
    # -s -S: only errors reach the console; the byte progress bar is noise in a batch run.
    & curl.exe -fsSL --retry 3 --retry-delay 2 -C - -o $part $Url 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path $part) { Remove-Item $part -Force -ErrorAction SilentlyContinue }
        throw ('curl failed ({0}) for {1}' -f $LASTEXITCODE, $Url)
    }
    if ($Sha256) {
        $actual = (Get-FileHash -Path $part -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $Sha256.ToLower()) {
            Remove-Item $part -Force -ErrorAction SilentlyContinue
            throw ('sha256 mismatch for {0}: expected {1}, got {2}' -f $Url, $Sha256, $actual)
        }
    }
    Move-Item -Path $part -Destination $Destination -Force
    Write-UpdateLog -Message ('Saved {0}' -f $Destination)
}

# ---------------------------------------------------------------------------
# Extract / overlay
# ---------------------------------------------------------------------------

function Expand-ZipToDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Marker,
        [string]$Label = ''
    )

    if (-not (Test-Path $script:TarExe)) { throw ('tar.exe not found: {0}' -f $script:TarExe) }
    $work = Join-Path $env:TEMP ('appx-unpack-' + [guid]::NewGuid().ToString('N'))
    New-DirectoryIfMissing -Path $work | Out-Null
    & $script:TarExe -xf $ZipPath -C $work
    if ($LASTEXITCODE -ne 0) {
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
        throw ('tar extract failed: {0}' -f $ZipPath)
    }

    $source = $null
    if (Test-Path (Join-Path $work $Marker)) {
        $source = $work
    } else {
        $hits = @()
        foreach ($dir in Get-ChildItem -Path $work -Directory) {
            if (Test-Path (Join-Path $dir.FullName $Marker)) { $hits += $dir.FullName }
        }
        if ($hits.Count -eq 1) { $source = $hits[0] }
    }
    if (-not $source) {
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
        throw ('zip layout unexpected: {0} not found in {1}' -f $Marker, $ZipPath)
    }

    if (Test-Path $Destination) { Remove-Item $Destination -Recurse -Force }
    $parent = Split-Path -Parent $Destination
    if ($parent) { New-DirectoryIfMissing -Path $parent | Out-Null }
    Move-Item -Path $source -Destination $Destination
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path (Join-Path $Destination $Marker))) {
        throw ('unpack incomplete: {0} missing in {1}' -f $Marker, $Destination)
    }
    if ($Label) { Write-UpdateLog -Message ('Unpacked {0} to {1}' -f $Label, $Destination) }
}

function Copy-TreeOverlay {
    param([Parameter(Mandatory = $true)][string]$Source, [Parameter(Mandatory = $true)][string]$Destination)

    if (-not (Test-Path $Source)) { return }
    New-DirectoryIfMissing -Path $Destination | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

function Expand-VectorOverlay {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$PgHome
    )

    $work = Join-Path $env:TEMP ('appx-vector-' + [guid]::NewGuid().ToString('N'))
    New-DirectoryIfMissing -Path $work | Out-Null
    & $script:TarExe -xf $ZipPath -C $work
    if ($LASTEXITCODE -ne 0) {
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
        throw ('tar extract failed: {0}' -f $ZipPath)
    }

    $source = $null
    if (Test-Path (Join-Path $work 'lib\vector.dll')) { $source = $work }
    else {
        foreach ($dir in Get-ChildItem -Path $work -Directory) {
            if (Test-Path (Join-Path $dir.FullName 'lib\vector.dll')) { $source = $dir.FullName; break }
        }
    }
    if (-not $source) {
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
        throw ('lib\vector.dll not found in {0}' -f $ZipPath)
    }

    New-DirectoryIfMissing -Path (Join-Path $PgHome 'lib') | Out-Null
    Copy-Item -Path (Join-Path $source 'lib\vector.dll') -Destination (Join-Path $PgHome 'lib\vector.dll') -Force
    Copy-TreeOverlay -Source (Join-Path $source 'share\extension') -Destination (Join-Path $PgHome 'share\extension')
    Copy-TreeOverlay -Source (Join-Path $source 'include\server\extension\vector') -Destination (Join-Path $PgHome 'include\server\extension\vector')
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path (Join-Path $PgHome 'share\extension\vector.control'))) {
        throw 'vector.control was not installed'
    }
}

# ---------------------------------------------------------------------------
# Process helpers
# ---------------------------------------------------------------------------

function Invoke-ProcessFile {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory,
        [string]$LogPath
    )

    # Launches a console program without touching its standard streams.
    #
    # Why this exists instead of `& $exe ... | Out-Null` or Start-Process -RedirectStandardOutput:
    # any PowerShell redirection or pipeline creates a pipe. A command that starts a long-lived
    # process (start-db.bat -> pg_ctl -> postgres.exe, net start, a daemon) leaves that process
    # holding the write end, so PowerShell waits for the daemon and the update appears to hang
    # forever. Here nothing is redirected: the caller redirects inside a .bat if it wants a log,
    # and WaitForExit only ever waits for this one process.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    if ($ArgumentList -and $ArgumentList.Count -gt 0) {
        # .NET Framework (Windows PowerShell 5.1) has no ArgumentList; quote arguments ourselves.
        $quoted = @()
        foreach ($arg in $ArgumentList) {
            if ($arg -match '[\s"]' -and -not ($arg.StartsWith('"') -and $arg.EndsWith('"'))) {
                $quoted += '"' + ($arg -replace '"', '\"') + '"'
            } else {
                $quoted += $arg
            }
        }
        $psi.Arguments = ($quoted -join ' ')
    }
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $process.WaitForExit()
    $code = $process.ExitCode
    $process.Dispose()

    if ($LogPath -and (Test-Path $LogPath)) {
        # Surface the tail so the operator sees progress, bounded so huge logs stay out of the way.
        $tail = Get-Content -Path $LogPath -Tail 20 -ErrorAction SilentlyContinue
        if ($tail) { Write-Host (($tail -join [Environment]::NewLine)) }
    }
    return $code
}

function Invoke-CommandToLog {
    param(
        [Parameter(Mandatory = $true)][string]$LogPath,
        [string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$CommandLine,
        [string]$EnvBat,
        [switch]$CaptureStdio
    )

    $parent = Split-Path -Parent $LogPath
    if ($parent) { New-DirectoryIfMissing -Path $parent | Out-Null }

    $tmp = Join-Path $env:TEMP ('appx-update-' + [guid]::NewGuid().ToString('N') + '.cmd')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('@echo off')
    [void]$sb.AppendLine('setlocal')
    if ($EnvBat) { [void]$sb.AppendLine('call "' + $EnvBat + '" >nul 2>&1') }
    if ($WorkingDirectory) { [void]$sb.AppendLine('cd /d "' + $WorkingDirectory + '"') }
    [void]$sb.AppendLine('(' + $CommandLine + ') > "' + $LogPath + '" 2>&1 < nul')
    [void]$sb.AppendLine('set "RC=%ERRORLEVEL%"')
    [void]$sb.AppendLine('endlocal & exit /b %RC%')
    [System.IO.File]::WriteAllText($tmp, $sb.ToString(), [System.Text.Encoding]::Default)

    try {
        $rc = Invoke-ProcessFile -FilePath $env:ComSpec -ArgumentList @('/c', $tmp) -WorkingDirectory $WorkingDirectory `
            -LogPath $(if ($CaptureStdio) { $LogPath } else { $null })
        return $rc
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Start-DetachedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$CommandLine,
        [string]$WorkingDirectory,
        [string]$LogPath
    )

    # For scripts that start a daemon and should return as soon as the script itself exits
    # (start-db.bat, pg_ctl start, net start). See Invoke-ProcessFile for why no redirection.
    $tmp = Join-Path $env:TEMP ('appx-detach-' + [guid]::NewGuid().ToString('N') + '.cmd')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('@echo off')
    if ($WorkingDirectory) { [void]$sb.AppendLine('cd /d "' + $WorkingDirectory + '"') }
    if ($LogPath) {
        [void]$sb.AppendLine('(' + $CommandLine + ') > "' + $LogPath + '" 2>&1 < nul')
    } else {
        [void]$sb.AppendLine('(' + $CommandLine + ') > nul 2>&1 < nul')
    }
    [System.IO.File]::WriteAllText($tmp, $sb.ToString(), [System.Text.Encoding]::Default)

    try {
        return (Invoke-ProcessFile -FilePath $env:ComSpec -ArgumentList @('/c', $tmp) -WorkingDirectory $WorkingDirectory)
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Get-ServiceState {
    param([Parameter(Mandatory = $true)][string]$Name)
    $out = & sc.exe query $Name 2>$null | Out-String
    if ($out -match 'RUNNING') { return 'RUNNING' }
    if ($out -match 'STOPPED') { return 'STOPPED' }
    return 'ABSENT'
}

function Test-PortListening {
    param([Parameter(Mandatory = $true)][int[]]$Ports)

    $found = @()
    $out = & netstat.exe -ano -p tcp 2>$null
    foreach ($line in $out) {
        if ($line -notmatch 'LISTENING') { continue }
        foreach ($port in $Ports) {
            if ($line -match (':' + $port + '\s')) {
                if ($found -notcontains $port) { $found += $port }
            }
        }
    }
    return $found
}

# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------

function Get-PgConnectionInfo {
    param([Parameter(Mandatory = $true)][string]$Root)

    $envFile = Join-Path $Root 'appxserver\utils\myEnvironment.bat'
    $fallback = Join-Path $Root 'conf\utils\myEnvironment.bat'
    $vars = Read-BatSetVars -Path $envFile
    if ($vars.Count -eq 0) { $vars = Read-BatSetVars -Path $fallback }

    $info = [pscustomobject]@{
        Host = '127.0.0.1'
        Port = 15432
        Database = 'appx'
        User = 'appx'
        Password = 'appx123'
        SystemUser = 'postgres'
        SystemPassword = 'postgres123'
        PgHome = (Join-Path $Root 'runtime\pgsql')
        PgData = (Join-Path $Root 'runtime\pgdata')
    }
    if ($vars['ADEMPIERE_DB_SERVER']) { $info.Host = $vars['ADEMPIERE_DB_SERVER'] }
    if ($vars['ADEMPIERE_DB_PORT']) { $info.Port = [int]$vars['ADEMPIERE_DB_PORT'] }
    if ($vars['ADEMPIERE_DB_NAME']) { $info.Database = $vars['ADEMPIERE_DB_NAME'] }
    if ($vars['ADEMPIERE_DB_USER']) { $info.User = $vars['ADEMPIERE_DB_USER'] }
    if ($vars['ADEMPIERE_DB_PASSWORD']) { $info.Password = $vars['ADEMPIERE_DB_PASSWORD'] }
    if ($vars['ADEMPIERE_DB_SYSTEM_USER']) { $info.SystemUser = $vars['ADEMPIERE_DB_SYSTEM_USER'] }
    if ($vars['ADEMPIERE_DB_SYSTEM']) { $info.SystemPassword = $vars['ADEMPIERE_DB_SYSTEM'] }
    return $info
}

function Invoke-PsqlScalar {
    param(
        [Parameter(Mandatory = $true)]$Pg,
        [Parameter(Mandatory = $true)][string]$Sql,
        [string]$User,
        [string]$Password,
        [string]$Database
    )

    $psql = Join-Path $Pg.PgHome 'bin\psql.exe'
    if (-not (Test-Path $psql)) { return $null }
    if (-not $User) { $User = $Pg.User }
    if (-not $Password) { $Password = $Pg.Password }
    if (-not $Database) { $Database = $Pg.Database }

    $previous = $env:PGPASSWORD
    $env:PGPASSWORD = $Password
    try {
        $out = & $psql -h $Pg.Host -p $Pg.Port -U $User -d $Database -tA -c $Sql 2>&1
        if ($LASTEXITCODE -ne 0) { return $null }
        return (($out | Out-String).Trim())
    } finally {
        $env:PGPASSWORD = $previous
    }
}

function Wait-PgReady {
    param(
        [Parameter(Mandatory = $true)][string]$PgHome,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutSec = 60
    )

    $ready = Join-Path $PgHome 'bin\pg_isready.exe'
    if (-not (Test-Path $ready)) { return $false }
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        & $ready -h 127.0.0.1 -p $Port -q 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

# ---------------------------------------------------------------------------
# OSGi extension bundles
# ---------------------------------------------------------------------------

function Get-BundlesInfoMap {
    param([Parameter(Mandatory = $true)][string]$BundlesInfoPath)

    $map = @{}
    if (-not (Test-Path $BundlesInfoPath)) { return $map }
    foreach ($line in [System.IO.File]::ReadAllLines($BundlesInfoPath)) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        if ($trimmed.StartsWith('#')) { continue }
        $parts = $trimmed.Split(',')
        if ($parts.Count -lt 3) { continue }
        $map[$parts[0]] = [pscustomobject]@{ Symbolic = $parts[0]; Version = $parts[1]; Path = $parts[2] }
    }
    return $map
}

function Read-ManifestIdentity {
    param([Parameter(Mandatory = $true)][string]$Text)

    $unfolded = $Text -replace "`r`n ", '' -replace "`n ", ''
    $symbolic = $null
    $version = $null
    foreach ($line in ($unfolded -split "`r?`n")) {
        if ($line -match '^Bundle-SymbolicName:\s*(.+)$') {
            $symbolic = ($matches[1] -split ';')[0].Trim()
        } elseif ($line -match '^Bundle-Version:\s*(.+)$') {
            $version = $matches[1].Trim()
        }
    }
    return [pscustomobject]@{ Symbolic = $symbolic; Version = $version }
}

function Get-ProductBundleSymbols {
    param([Parameter(Mandatory = $true)][string]$ZipPath)

    # The baseline for "what the product ships" must come from the package being installed, not
    # from the live tree: Install-ExtensionBundles appends customer bundles to the live
    # bundles.info, so using it as the baseline makes them look product-owned on the next run.
    # The product archive always carries its own 388-entry bundles.info.
    $entryName = 'appxserver/configuration/org.eclipse.equinox.simpleconfigurator/bundles.info'
    $text = $null
    try { $text = Get-ZipEntryText -ZipPath $ZipPath -EntryName $entryName } catch { }
    if (-not $text) {
        throw ('{0} has no {1}; cannot tell product bundles from customer bundles' -f (Split-Path -Leaf $ZipPath), $entryName)
    }

    $symbols = @{}
    foreach ($line in ($text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        if ($trimmed.StartsWith('#')) { continue }
        $parts = $trimmed.Split(',')
        if ($parts.Count -lt 3) { continue }
        $symbols[$parts[0]] = $true
    }
    if ($symbols.Count -eq 0) {
        throw ('{0}: bundles.info lists no bundles' -f (Split-Path -Leaf $ZipPath))
    }
    return $symbols
}

function Get-InstalledExtensionBundles {
    param(
        [Parameter(Mandatory = $true)][string]$AppxHome,
        [string[]]$ExcludeSymbolic = @()
    )

    # Customer bundles live in two places depending on how they were installed:
    #   pool     - configuration\org.eclipse.osgi\<id>\0\bundleFile, written by Extension
    #              Management / the Felix web console (BundleContext.installBundle)
    #   plugins  - plugins\<symbolic>_<version>.jar, written by this update when it re-registers
    #              bundles after a product swap
    # Scanning only the pool silently returns 0 on a tree that a previous update populated, which
    # is how the 2026-11-17 run dropped every customer bundle. Scan both, and let the pool win
    # when the same symbolic name shows up twice (it is the authority the running framework uses).
    $bySymbolic = [ordered]@{}
    $notes = New-Object System.Collections.ArrayList

    $pool = Join-Path $AppxHome 'configuration\org.eclipse.osgi'
    if (Test-Path $pool) {
        foreach ($dir in Get-ChildItem -Path $pool -Directory) {
            $bundleFile = Join-Path $dir.FullName '0\bundleFile'
            if (-not (Test-Path $bundleFile)) { continue }
            $identity = Get-BundleFileIdentity -Path $bundleFile
            if (-not $identity) { continue }
            if ($ExcludeSymbolic -contains $identity.Symbolic) { continue }
            $bySymbolic[$identity.Symbolic] = New-ExtensionBundleEntry -Identity $identity -Source $bundleFile -SourceKind 'pool'
        }
    }

    $pluginsDir = Join-Path $AppxHome 'plugins'
    if (Test-Path $pluginsDir) {
        foreach ($file in Get-ChildItem -Path $pluginsDir -File) {
            if ($file.Extension -ne '.jar') { continue }
            $identity = Get-BundleFileIdentity -Path $file.FullName
            if (-not $identity) { continue }
            if ($ExcludeSymbolic -contains $identity.Symbolic) { continue }
            if ($bySymbolic.Contains($identity.Symbolic)) {
                # Both copies exist. Keep the pool entry so the exported jar matches what the
                # framework actually resolves, and report the duplicate instead of hiding it.
                [void]$notes.Add(('{0} exists in both the OSGi pool and plugins\; using the pool copy' -f $identity.Symbolic))
                continue
            }
            $bySymbolic[$identity.Symbolic] = New-ExtensionBundleEntry -Identity $identity -Source $file.FullName -SourceKind 'plugins'
        }
    }

    $result = @($bySymbolic.Values)
    foreach ($note in $notes) { Write-UpdateLog -Level WARN -Message ('extension: ' + $note) }
    return $result
}

function Get-BundleFileIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)

    # A bundle is either a jar or an OSGi pool "bundleFile"; both are zip archives whose
    # META-INF/MANIFEST.MF carries Bundle-SymbolicName / Bundle-Version.
    $manifest = $null
    try { $manifest = Get-ZipEntryText -ZipPath $Path -EntryName 'META-INF/MANIFEST.MF' } catch { return $null }
    if (-not $manifest) { return $null }
    $identity = Read-ManifestIdentity -Text $manifest
    if (-not $identity.Symbolic) { return $null }
    return $identity
}

function New-ExtensionBundleEntry {
    param($Identity, [string]$Source, [string]$SourceKind)

    $version = $Identity.Version
    if (-not $version) { $version = '0.0.0' }
    return [pscustomobject]@{
        Symbolic = $Identity.Symbolic
        Version = $version
        Source = $Source
        SourceKind = $SourceKind
        File = ('{0}_{1}.jar' -f $Identity.Symbolic, $version)
        StartLevel = 4
        Started = $true
    }
}

function Export-ExtensionBundles {
    param(
        [Parameter(Mandatory = $true)]$Bundles,
        [Parameter(Mandatory = $true)][string]$BackupDir
    )

    $target = Join-Path $BackupDir 'extensions'
    New-DirectoryIfMissing -Path $target | Out-Null
    $rows = @()
    foreach ($bundle in $Bundles) {
        $dest = Join-Path $target $bundle.File
        Copy-Item -Path $bundle.Source -Destination $dest -Force
        $rows += [pscustomobject]@{
            symbolic = $bundle.Symbolic
            version = $bundle.Version
            file = $bundle.File
            startLevel = $bundle.StartLevel
            started = $bundle.Started
            sourceKind = $bundle.SourceKind
        }
    }
    Write-JsonNoBom -Path (Join-Path $BackupDir 'extensions.json') -Object @($rows)
    return $rows
}

function Install-ExtensionBundles {
    param(
        [Parameter(Mandatory = $true)][string]$AppxHome,
        [Parameter(Mandatory = $true)][string]$BackupDir,
        [string]$LogPath
    )

    $manifestPath = Join-Path $BackupDir 'extensions.json'
    $report = [pscustomobject]@{ Installed = @(); Replaced = @(); Skipped = @(); Warnings = @() }
    if (-not (Test-Path $manifestPath)) { return $report }

    $raw = Get-Content -Path $manifestPath -Raw -Encoding UTF8
    if (-not $raw -or -not $raw.Trim()) { return $report }

    $decoded = $raw | ConvertFrom-Json
    $entries = @()
    if ($null -ne $decoded) {
        foreach ($item in @($decoded)) {
            if ($null -ne $item) { $entries += $item }
        }
    }
    if ($entries.Count -eq 0) {
        if ($LogPath) {
            Write-TextNoBom -Path $LogPath -Text ("Extension bundles after product swap`r`ninstalled: 0`r`n")
        }
        return $report
    }

    $bundlesInfo = Join-Path $AppxHome 'configuration\org.eclipse.equinox.simpleconfigurator\bundles.info'
    $existing = Get-BundlesInfoMap -BundlesInfoPath $bundlesInfo
    $pluginsDir = Join-Path $AppxHome 'plugins'
    New-DirectoryIfMissing -Path $pluginsDir | Out-Null

    $lines = New-Object System.Collections.ArrayList
    if (Test-Path $bundlesInfo) {
        foreach ($line in [System.IO.File]::ReadAllLines($bundlesInfo)) { [void]$lines.Add($line) }
    } else {
        # Should not happen: the product archive ships bundles.info. Start a valid file so the
        # extension bundles are at least registered instead of silently disappearing.
        $simpleDir = Split-Path -Parent $bundlesInfo
        New-DirectoryIfMissing -Path $simpleDir | Out-Null
        [void]$lines.Add('#encoding=UTF-8')
        [void]$lines.Add('#version=1')
        $report.Warnings += 'bundles.info was missing in the new product; created a new one'
    }

    foreach ($entry in @($entries)) {
        if (-not $entry.symbolic) { continue }
        $source = Join-Path (Join-Path $BackupDir 'extensions') $entry.file
        if (-not (Test-Path $source)) {
            $report.Warnings += ('jar missing in backup: {0}' -f $entry.file)
            continue
        }

        $packaged = $existing[$entry.symbolic]
        $replace = $false
        if ($packaged) {
            $cmp = Compare-VersionString -Left $entry.version -Right $packaged.Version
            if ($cmp -le 0) {
                # The new product already ships this bundle at an equal or newer version.
                $report.Skipped += ('{0} ({1}); product ships {2}' -f $entry.symbolic, $entry.version, $packaged.Version)
                continue
            }
            $replace = $true
        }

        Copy-Item -Path $source -Destination (Join-Path $pluginsDir $entry.file) -Force

        if ($replace) {
            # Point the packaged entry at the newer extension jar instead of registering twice.
            $newPath = 'plugins/' + $entry.file
            $newLine = ('{0},{1},{2},{3},{4}' -f $entry.symbolic, $entry.version, $newPath, $entry.startLevel, ([string]$entry.started).ToLower())
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i].StartsWith($entry.symbolic + ',')) { $lines[$i] = $newLine; break }
            }
            $packagedFile = Join-Path $pluginsDir (Split-Path -Leaf $packaged.Path)
            if ((Split-Path -Leaf $packaged.Path) -ne $entry.file) {
                Remove-Item -Path $packagedFile -Recurse -Force -ErrorAction SilentlyContinue
            }
            $report.Replaced += ('{0} {1} (product had {2})' -f $entry.symbolic, $entry.version, $packaged.Version)
        } else {
            [void]$lines.Add(('{0},{1},plugins/{2},{3},{4}' -f $entry.symbolic, $entry.version, $entry.file, $entry.startLevel, ([string]$entry.started).ToLower()))
            $report.Installed += ('{0} {1}' -f $entry.symbolic, $entry.version)
        }
        $existing[$entry.symbolic] = [pscustomobject]@{ Symbolic = $entry.symbolic; Version = $entry.version; Path = ('plugins/' + $entry.file) }
    }

    [System.IO.File]::WriteAllLines($bundlesInfo, $lines, $script:Utf8NoBom)

    if ($LogPath) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('Extension bundles after product swap')
        [void]$sb.AppendLine(('installed: {0}' -f $report.Installed.Count))
        foreach ($item in $report.Installed) { [void]$sb.AppendLine(('  + {0}' -f $item)) }
        foreach ($item in $report.Replaced) { [void]$sb.AppendLine(('  ^ {0}' -f $item)) }
        foreach ($item in $report.Skipped) { [void]$sb.AppendLine(('  = {0}' -f $item)) }
        foreach ($item in $report.Warnings) { [void]$sb.AppendLine(('  ! {0}' -f $item)) }
        Write-TextNoBom -Path $LogPath -Text $sb.ToString()
    }
    return $report
}

# ---------------------------------------------------------------------------
# packages.ini rewrite and backup retention
# ---------------------------------------------------------------------------

function Set-PackagesIniNames {
    param(
        [Parameter(Mandatory = $true)][string]$IniPath,
        [Parameter(Mandatory = $true)][hashtable]$FileByKey
    )

    if (-not (Test-Path $IniPath)) { return }
    $original = [System.IO.File]::ReadAllText($IniPath)
    # Preserve the file's existing line endings: WriteAllLines would silently rewrite every line
    # to CRLF and turn a one-line change into a whole-file diff.
    $newLine = "`r`n"
    if ($original -notmatch "`r`n" -and $original -match "`n") { $newLine = "`n" }

    $lines = $original -split "`r?`n"
    $output = New-Object System.Collections.ArrayList
    foreach ($line in $lines) {
        $replaced = $false
        foreach ($key in $FileByKey.Keys) {
            if ($line -match ('^\s*' + [regex]::Escape($key) + '\s*=')) {
                [void]$output.Add(('{0}={1}' -f $key, $FileByKey[$key]))
                $replaced = $true
                break
            }
        }
        if (-not $replaced) { [void]$output.Add($line) }
    }
    Write-TextNoBom -Path $IniPath -Text ($output -join $newLine)
}

function Remove-OldBackups {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [int]$Keep = 3
    )

    if ($Keep -le 0) { return }
    $patterns = @(
        @{ Path = $Root; Filter = 'appxserver.bak-*' },
        @{ Path = $Root; Filter = 'appxserver.new-*' },
        @{ Path = (Join-Path $Root 'runtime'); Filter = 'jdk.bak-*' },
        @{ Path = (Join-Path $Root 'runtime'); Filter = 'pgsql.bak-*' },
        @{ Path = (Join-Path $Root 'runtime'); Filter = 'python.bak-*' },
        @{ Path = (Join-Path $Root 'runtime'); Filter = 'pgdata.bak-*' },
        @{ Path = (Join-Path $Root 'runtime'); Filter = 'pgdata.new' },
        @{ Path = (Join-Path $Root 'runtime'); Filter = 'jdk.new' },
        @{ Path = (Join-Path $Root 'runtime'); Filter = 'pgsql.new' },
        @{ Path = (Join-Path $Root 'runtime'); Filter = 'python.new' }
    )
    foreach ($entry in $patterns) {
        if (-not (Test-Path $entry.Path)) { continue }
        $items = @(Get-ChildItem -Path $entry.Path -Filter $entry.Filter -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
        if ($items.Count -le $Keep) { continue }
        for ($i = $Keep; $i -lt $items.Count; $i++) {
            Remove-Item -Path $items[$i].FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $updateLogs = Join-Path $Root 'runtime\logs\update'
    if (Test-Path $updateLogs) {
        $dirs = @(Get-ChildItem -Path $updateLogs -Directory | Sort-Object Name -Descending)
        for ($i = $Keep; $i -lt $dirs.Count; $i++) {
            Remove-Item -Path $dirs[$i].FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $backups = Join-Path $Root 'runtime\backup'
    if (Test-Path $backups) {
        $dirs = @(Get-ChildItem -Path $backups -Directory | Sort-Object Name -Descending)
        for ($i = $Keep; $i -lt $dirs.Count; $i++) {
            Remove-Item -Path $dirs[$i].FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Manifest generation
# ---------------------------------------------------------------------------

function New-PackageManifest {
    param(
        [Parameter(Mandatory = $true)][string]$PackagesDir,
        [string]$Channel = 'latest',
        [string]$BaseUrl,
        [string]$OutputPath,
        [switch]$IncludeSha256
    )

    if (-not (Test-Path $PackagesDir)) { throw ('packages directory not found: {0}' -f $PackagesDir) }
    if (-not $OutputPath) { $OutputPath = Join-Path $PackagesDir 'packages.json' }

    $specs = Get-ComponentSpecs
    $channelNode = [ordered]@{}
    foreach ($spec in $specs) {
        $candidates = Get-LocalPackageCandidates -Spec $spec -PackagesDir $PackagesDir
        $best = $null
        foreach ($candidate in $candidates) {
            if (-not $best -or (Compare-Candidate -Left $candidate -Right $best) -gt 0) { $best = $candidate }
        }
        if (-not $best) {
            Write-UpdateLog -Level WARN -Message ('manifest: no package for {0}' -f $spec.Label)
            continue
        }
        # Ordered so a regenerated manifest diffs cleanly and reads top-down.
        $entry = [ordered]@{ version = $best.Version }
        if ($best.Build) { $entry['build'] = $best.Build }
        if ($spec.Name -eq 'pgsql' -or $spec.Name -eq 'jdk') { $entry['major'] = Get-MajorFromVersion -Version $best.Version }
        if ($best.PgMajor) { $entry['pgMajor'] = $best.PgMajor }
        $entry['file'] = $best.File
        $entry['size'] = (Get-Item $best.Path).Length
        if ($BaseUrl) { $entry['url'] = $BaseUrl.TrimEnd('/') + '/' + $best.File }
        if ($IncludeSha256) { $entry['sha256'] = (Get-FileHash -Path $best.Path -Algorithm SHA256).Hash.ToLower() }
        $channelNode[$spec.Name] = [pscustomobject]$entry
    }

    $manifest = [ordered]@{
        schemaVersion = 1
        generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        channels = [ordered]@{ $Channel = [pscustomobject]$channelNode }
    }
    Write-JsonNoBom -Path $OutputPath -Object ([pscustomobject]$manifest) -Depth 8
    Write-UpdateLog -Message ('Wrote {0}' -f $OutputPath)
    return $OutputPath
}
