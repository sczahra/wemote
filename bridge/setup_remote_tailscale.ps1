$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$TokenFile = Join-Path $Root "data\remote_token.txt"
$ProxyScript = Join-Path $Root "remote_proxy.py"
$Python = Join-Path $Root ".venv\Scripts\python.exe"
$PagesUrl = "https://wemotecontwol.pages.dev"

Write-Host ""
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host "      WEMOTE v0.5.2 REMOTE SETUP" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host ""

try {
    $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://127.0.0.1:8765/api/status
    if ($r.StatusCode -ne 200) { throw "HTTP $($r.StatusCode)" }
    Write-Host "WEMOTE bridge: running" -ForegroundColor Green
} catch {
    Write-Host "Start WEMOTE first, then run this again." -ForegroundColor Yellow
    exit 2
}

$candidates = @(
    (Get-Command tailscale.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    "$env:ProgramFiles\Tailscale\tailscale.exe",
    "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

if (-not $candidates) {
    Write-Host "Tailscale CLI was not found. Nothing was installed or changed." -ForegroundColor Red
    exit 3
}
$Tailscale = $candidates[0]
Write-Host "Tailscale: $(& $Tailscale version | Select-Object -First 1)" -ForegroundColor Green
Write-Host "Location:  $Tailscale"

$status = & $Tailscale status --json | ConvertFrom-Json
if (-not $status.Self -or -not $status.Self.DNSName) {
    Write-Host "Tailscale is not connected or does not have a MagicDNS name yet." -ForegroundColor Yellow
    exit 4
}
$DnsName = ([string]$status.Self.DNSName).TrimEnd('.')
$PublicUrl = "https://$DnsName"

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TokenFile) | Out-Null
$Token = ""
if (Test-Path $TokenFile) { $Token = (Get-Content $TokenFile -Raw).Trim() }
if (-not $Token) {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $Token = -join ($bytes | ForEach-Object { $_.ToString('x2') })
    [IO.File]::WriteAllText($TokenFile, $Token, (New-Object System.Text.UTF8Encoding($false)))
}

if (-not (Test-Path $Python)) { throw "Missing .venv Python. Run FIRST_RUN.cmd first." }
if (-not (Test-Path $ProxyScript)) { throw "Missing remote_proxy.py. Run the WEMOTE bootstrap/update again." }

$proxy = Get-NetTCPConnection -LocalPort 8766 -State Listen -ErrorAction SilentlyContinue
if (-not $proxy) {
    Start-Process -FilePath $Python -ArgumentList ('"' + $ProxyScript + '"') -WorkingDirectory $Root -WindowStyle Hidden | Out-Null
    Start-Sleep -Milliseconds 700
}

Write-Host ""
Write-Host "Enabling Tailscale Funnel..." -ForegroundColor Cyan
Write-Host "A one-time Tailscale approval page may open if Funnel/HTTPS needs permission." -ForegroundColor Yellow
& $Tailscale funnel --bg --yes http://127.0.0.1:8766
if ($LASTEXITCODE -ne 0) {
    Write-Host "Funnel did not finish enabling." -ForegroundColor Yellow
    Write-Host "If Tailscale opened an approval page, approve it and run SETUP_REMOTE_TAILSCALE.cmd again."
    exit 5
}

Write-Host "Public bridge: $PublicUrl" -ForegroundColor Green
$SetupUrl = "$PagesUrl/#bridge=$([Uri]::EscapeDataString($PublicUrl))&token=$([Uri]::EscapeDataString($Token))"
Write-Host "Opening WEMOTE and linking this browser automatically..." -ForegroundColor Cyan
Start-Process $SetupUrl
Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host "Funnel was configured with --bg, so Tailscale will resume it after restarts."
