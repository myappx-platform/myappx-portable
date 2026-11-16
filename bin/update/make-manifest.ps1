# make-manifest.ps1 - generate packages.json for the myappx-portable update feed.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File bin\update\make-manifest.ps1 `
#       -BaseUrl https://example.com/myappx-portable
#
# Scans packages\*.zip, keeps the newest build of each component, and writes
# packages\packages.json with version, build, size and sha256 per component.
# Upload packages.json plus the zips to the base URL.

[CmdletBinding()]
param(
    [string]$PackagesDir,
    [string]$BaseUrl,
    [string]$Channel = 'latest',
    [string]$OutputPath,
    [switch]$NoSha256
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'update-lib.ps1')

if (-not $PackagesDir) {
    $PackagesDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $PackagesDir = Join-Path $PackagesDir 'packages'
}
if (-not (Test-Path $PackagesDir)) {
    Write-Error ('packages directory not found: {0}' -f $PackagesDir)
    exit 1
}
if (-not $OutputPath) { $OutputPath = Join-Path $PackagesDir 'packages.json' }

if (-not $BaseUrl) {
    Write-Host 'No -BaseUrl given: the manifest will not contain download URLs.'
    Write-Host 'Clients fall back to the local packages\ directory in that case.'
}

New-PackageManifest -PackagesDir $PackagesDir -Channel $Channel -BaseUrl $BaseUrl `
    -OutputPath $OutputPath -IncludeSha256:(-not $NoSha256) | Out-Null

exit 0
