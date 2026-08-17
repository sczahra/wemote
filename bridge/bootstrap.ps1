param([string]$Root)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
if (-not $Root) { $Root = (Get-Location).Path }
if (-not (Test-Path (Join-Path $Root "FIRST_RUN.cmd"))) {
    throw "Run this bootstrap from inside the WEMOTE folder beside FIRST_RUN.cmd."
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$Base = "https://raw.githubusercontent.com/sczahra/wemote/main/bridge"

Write-Host ""
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host "      WEMOTE v0.5.2 REMOTE BOOTSTRAP" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host ""

$downloads = @{
    "UPDATE_WEMOTE.cmd" = "$Base/UPDATE_WEMOTE.cmd"
    "update_wemote.ps1" = "$Base/update_wemote.ps1"
    "update_source.txt" = "$Base/update_source.txt"
    "remote_proxy.py" = "$Base/remote_proxy.py"
    "run_windows.ps1" = "$Base/run_windows.ps1"
    "setup_remote_tailscale.ps1" = "$Base/setup_remote_tailscale.ps1"
    "SETUP_REMOTE_TAILSCALE.cmd" = "$Base/SETUP_REMOTE_TAILSCALE.cmd"
}

foreach ($name in $downloads.Keys) {
    Write-Host "Getting $name..."
    Invoke-WebRequest -Uri $downloads[$name] -OutFile (Join-Path $Root $name) -TimeoutSec 60
}

[IO.File]::WriteAllText((Join-Path $Root "VERSION"), "0.5.2`n", $utf8)

$main = Join-Path $Root "app\main.py"
if (Test-Path $main) {
    $s = Get-Content $main -Raw
    $s = [regex]::Replace($s, 'version="[^"]+"', 'version="0.5.2"', 1)
    [IO.File]::WriteAllText($main, $s, $utf8)
}

$index = Join-Path $Root "app\static\index.html"
if (Test-Path $index) {
    $s = Get-Content $index -Raw
    $s = [regex]::Replace($s, '<title>WEMOTE v[^<]+</title>', '<title>WEMOTE v0.5.2</title>')
    $s = [regex]::Replace($s, '<h1>WEMOTE v[^<]+</h1>', '<h1>WEMOTE v0.5.2</h1>', 1)
    $s = [regex]::Replace($s, '(<span id="appVersion">)[^<]*(</span>)', '$10.5.2$2')
    [IO.File]::WriteAllText($index, $s, $utf8)
}

Write-Host "Restarting WEMOTE with the secure remote proxy..." -ForegroundColor Yellow
$conns = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
foreach ($c in $conns) {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($c.OwningProcess)" -ErrorAction SilentlyContinue
    if ($p -and $p.CommandLine -match "uvicorn" -and $p.CommandLine -match "app\.main") {
        Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Milliseconds 700
Start-Process -FilePath (Join-Path $Root "RUN_CONTROLLER.cmd") -WorkingDirectory $Root
Start-Sleep -Seconds 2

Write-Host "WEMOTE v0.5.2 controller updated." -ForegroundColor Green
Write-Host "Starting one-time Tailscale remote setup..." -ForegroundColor Cyan
Start-Process -FilePath (Join-Path $Root "SETUP_REMOTE_TAILSCALE.cmd") -WorkingDirectory $Root
Write-Host ""
Write-Host "Bootstrap complete." -ForegroundColor Green
Write-Host "If Tailscale asks for Funnel/HTTPS approval, approve it once and rerun SETUP_REMOTE_TAILSCALE.cmd." -ForegroundColor Yellow
