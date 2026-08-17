$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $Root ".venv\Scripts\python.exe"
$ProxyScript = Join-Path $Root "remote_proxy.py"
$TokenFile = Join-Path $Root "data\remote_token.txt"

if (-not (Test-Path $Python)) {
    Write-Host "WEMOTE Python environment is missing." -ForegroundColor Yellow
    Write-Host "Run FIRST_RUN.cmd first."
    exit 1
}

$proxyProcess = $null
if ((Test-Path $TokenFile) -and (Test-Path $ProxyScript)) {
    $existingProxy = Get-NetTCPConnection -LocalPort 8766 -State Listen -ErrorAction SilentlyContinue
    if (-not $existingProxy) {
        $proxyProcess = Start-Process -FilePath $Python -ArgumentList ('"' + $ProxyScript + '"') -WorkingDirectory $Root -WindowStyle Hidden -PassThru
        Start-Sleep -Milliseconds 500
    }
}

Write-Host "WEMOTE local: http://127.0.0.1:8765" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop this controller session."

try {
    & $Python -m uvicorn app.main:app --host 0.0.0.0 --port 8765
} finally {
    if ($proxyProcess -and -not $proxyProcess.HasExited) {
        Stop-Process -Id $proxyProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
