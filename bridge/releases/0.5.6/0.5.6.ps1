param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference="Stop"
$ProgressPreference="SilentlyContinue"
$utf8=New-Object System.Text.UTF8Encoding($false)
$base="https://raw.githubusercontent.com/sczahra/wemote/main"

Write-Host ""
Write-Host "WEMOTE v0.5.6 UI UPDATE" -ForegroundColor Cyan
Write-Host "Creating backup..." -ForegroundColor Yellow

$Backups=Join-Path $Root "backups"
New-Item -ItemType Directory -Force -Path $Backups | Out-Null
$current=if(Test-Path(Join-Path $Root "VERSION")){(Get-Content(Join-Path $Root "VERSION") -Raw).Trim()}else{"unknown"}
$backup=Join-Path $Backups ("wemote-"+$current+"-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".zip")
$items=@()
foreach($n in @("app","VERSION")){$p=Join-Path $Root $n;if(Test-Path $p){$items+=$p}}
if($items.Count -gt 0){Compress-Archive -Path $items -DestinationPath $backup -Force}

$stage=Join-Path $env:TEMP ("wemote-056-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach($name in @("index.html","styles.css","app.js")){
  Invoke-WebRequest -Uri ($base+"/"+$name) -OutFile (Join-Path $stage $name) -TimeoutSec 60
}

$conns=Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
foreach($c in $conns){
  $p=Get-CimInstance Win32_Process -Filter "ProcessId=$($c.OwningProcess)" -ErrorAction SilentlyContinue
  if($p -and $p.CommandLine -match "uvicorn" -and $p.CommandLine -match "app\.main"){
    Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
  }
}
Start-Sleep -Milliseconds 500

$static=Join-Path $Root "app\static"
New-Item -ItemType Directory -Force -Path $static | Out-Null
Copy-Item (Join-Path $stage "index.html") (Join-Path $static "index.html") -Force
Copy-Item (Join-Path $stage "styles.css") (Join-Path $static "styles.css") -Force
Copy-Item (Join-Path $stage "app.js") (Join-Path $static "app.js") -Force

$main=Join-Path $Root "app\main.py"
if(Test-Path $main){
  $s=Get-Content $main -Raw
  $s=[regex]::Replace($s,'version="[^"]+"','version="0.5.6"',1)
  [IO.File]::WriteAllText($main,$s,$utf8)
}
[IO.File]::WriteAllText((Join-Path $Root "VERSION"),"0.5.6`n",$utf8)
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

Start-Process -FilePath (Join-Path $Root "RUN_CONTROLLER.cmd") -WorkingDirectory $Root
Start-Sleep -Seconds 2
Write-Host ""
Write-Host "WEMOTE v0.5.6 READY" -ForegroundColor Green
Write-Host "Simplified status-first UI installed." -ForegroundColor Green
Write-Host "Backup: $backup"
exit 0
