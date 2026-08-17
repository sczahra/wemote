$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$VersionFile = Join-Path $Root "VERSION"
$SourceFile = Join-Path $Root "update_source.txt"
$Temp = Join-Path $env:TEMP ("wemote-update-" + [guid]::NewGuid().ToString("N"))

function Current-Version {
    if (Test-Path $VersionFile) { return (Get-Content $VersionFile -Raw).Trim() }
    return "0.0.0"
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host "          WEMOTE ONE-CLICK UPDATE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host ""

$current = Current-Version
Write-Host "Installed: $current"
$feed = (Get-Content $SourceFile -Raw).Trim()
try { $manifest = Invoke-RestMethod -Uri $feed -TimeoutSec 20 }
catch { Write-Host "Could not reach GitHub. Nothing was changed." -ForegroundColor Yellow; exit 2 }

$latest = [string]$manifest.version
Write-Host "Latest:    $latest"
try { $cmp = ([version]$current).CompareTo([version]$latest) }
catch { $cmp = [string]::Compare($current,$latest,$true) }
if ($cmp -ge 0) { Write-Host "Already up to date." -ForegroundColor Green; exit 0 }

if (-not $manifest.script_url -or -not $manifest.sha256) { throw "Release feed is missing its update script." }
New-Item -ItemType Directory -Force -Path $Temp | Out-Null
$release = Join-Path $Temp "release.ps1"
Invoke-WebRequest -Uri ([string]$manifest.script_url) -OutFile $release -TimeoutSec 60
$actual = (Get-FileHash $release -Algorithm SHA256).Hash.ToLowerInvariant()
$expected = ([string]$manifest.sha256).ToLowerInvariant()
if ($actual -ne $expected) { throw "Update verification failed. Nothing was installed." }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $release -Root $Root
$code = $LASTEXITCODE
Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue
exit $code
