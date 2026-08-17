param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference="Stop"
$ProgressPreference="SilentlyContinue"
$utf8=New-Object System.Text.UTF8Encoding($false)

Write-Host ""
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host "          WEMOTE v0.5.5 UPDATE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host ""

$Backups=Join-Path $Root "backups"
New-Item -ItemType Directory -Force -Path $Backups | Out-Null
$current=if(Test-Path(Join-Path $Root "VERSION")){(Get-Content(Join-Path $Root "VERSION") -Raw).Trim()}else{"unknown"}
$backup=Join-Path $Backups ("wemote-"+$current+"-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".zip")
$items=@()
foreach($n in @("app","VERSION","UPDATE_WEMOTE.cmd","update_wemote.ps1","update_source.txt")){
  $p=Join-Path $Root $n
  if(Test-Path $p){$items+=$p}
}
if($items.Count -gt 0){Compress-Archive -Path $items -DestinationPath $backup -Force}
Write-Host "Backup created: $backup" -ForegroundColor Green

$stage=Join-Path $env:TEMP ("wemote-055-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# The release script itself is SHA-256 verified by UPDATE_WEMOTE.cmd.
# These two fixed raw URLs are the known-good v0.5.3 controller assets.
$appUrl="https://raw.githubusercontent.com/sczahra/wemote/main/bridge/releases/0.5.3/app.js"
$wemoUrl="https://raw.githubusercontent.com/sczahra/wemote/main/bridge/releases/0.5.3/wemo_controller.py"
$appTmp=Join-Path $stage "app.js"
$wemoTmp=Join-Path $stage "wemo_controller.py"

Write-Host "Getting fixed scheduler/UI controller..."
Invoke-WebRequest -UseBasicParsing -Uri $appUrl -OutFile $appTmp -TimeoutSec 60
Write-Host "Getting fixed Wemo state controller..."
Invoke-WebRequest -UseBasicParsing -Uri $wemoUrl -OutFile $wemoTmp -TimeoutSec 60

if((Get-Item $appTmp).Length -lt 1000){throw "Downloaded app.js is unexpectedly small. Nothing was installed."}
if((Get-Item $wemoTmp).Length -lt 1000){throw "Downloaded wemo_controller.py is unexpectedly small. Nothing was installed."}

$conns=Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
foreach($c in $conns){
  $p=Get-CimInstance Win32_Process -Filter "ProcessId=$($c.OwningProcess)" -ErrorAction SilentlyContinue
  if($p -and $p.CommandLine -match "uvicorn" -and $p.CommandLine -match "app\.main"){
    Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
  }
}
Start-Sleep -Milliseconds 500

Copy-Item -LiteralPath $appTmp -Destination (Join-Path $Root "app\static\app.js") -Force
Copy-Item -LiteralPath $wemoTmp -Destination (Join-Path $Root "app\wemo_controller.py") -Force

# Bump visible/local version strings.
$main=Join-Path $Root "app\main.py"
if(Test-Path $main){
  $s=Get-Content $main -Raw
  $s=[regex]::Replace($s,'version="[^"]+"','version="0.5.5"',1)
  [IO.File]::WriteAllText($main,$s,$utf8)
}
$index=Join-Path $Root "app\static\index.html"
if(Test-Path $index){
  $s=Get-Content $index -Raw
  $s=[regex]::Replace($s,'<title>WEMOTE v[^<]+</title>','<title>WEMOTE v0.5.5</title>')
  $s=[regex]::Replace($s,'<h1>WEMOTE v[^<]+</h1>','<h1>WEMOTE v0.5.5</h1>',1)
  $s=[regex]::Replace($s,'(<span id="appVersion">)[^<]*(</span>)','$10.5.5$2')
  [IO.File]::WriteAllText($index,$s,$utf8)
}
$app=Join-Path $Root "app\static\app.js"
if(Test-Path $app){
  $s=Get-Content $app -Raw
  $s=$s.Replace('s.version || "0.5.3"','s.version || "0.5.5"')
  [IO.File]::WriteAllText($app,$s,$utf8)
}
[IO.File]::WriteAllText((Join-Path $Root "VERSION"),"0.5.5`n",$utf8)

# Reversible cleanup helper. It moves known legacy files into an archive, never deletes them.
$cleanupPs1=@'
$ErrorActionPreference="Stop"
$Project=Split-Path -Parent $MyInvocation.MyCommand.Path
$Parent=Split-Path -Parent $Project
$stamp=Get-Date -Format "yyyyMMdd-HHmmss"
$archive=Join-Path $Parent ("archive\legacy-"+$stamp)
New-Item -ItemType Directory -Force -Path $archive | Out-Null

$projectLegacy=@(
  "REMOTE_TEST_CLOUDFLARE.cmd",
  "cloudflare_quick_tunnel.ps1",
  "ENABLE_HOST_MODE.cmd",
  "DISABLE_HOST_MODE.cmd",
  "HOST_STATUS.cmd",
  "host_mode.ps1",
  "PREPARE_MIGRATION.cmd",
  "prepare_migration.ps1"
)
foreach($name in $projectLegacy){
  $p=Join-Path $Project $name
  if(Test-Path $p){Move-Item -LiteralPath $p -Destination $archive -Force}
}

Get-ChildItem -LiteralPath $Project -File -ErrorAction SilentlyContinue | Where-Object {
  ($_.Name -match '^WEMOTE_v0\.[0-4]\..*\.cmd$') -or
  ($_.Name -match '^WEMOTE_v0\.5\.[0-4].*(BOOTSTRAP|HOTFIX|UPDATE).*\.cmd$')
} | ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination $archive -Force }

# Clean only known legacy siblings in the parent Downloads folder.
Get-ChildItem -LiteralPath $Parent -File -ErrorAction SilentlyContinue | Where-Object {
  ($_.Extension -eq '.zip' -and $_.Name -match '^(WEMOTE|wemo-mode-controller)') -or
  ($_.Name -match '^WEMOTE_v0\.[0-4]\..*\.cmd$') -or
  ($_.Name -match '^WEMOTE_v0\.5\.[0-4].*(BOOTSTRAP|HOTFIX|UPDATE).*\.cmd$')
} | ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination $archive -Force }

Write-Host ""
Write-Host "WEMOTE cleanup complete." -ForegroundColor Green
Write-Host "Nothing was permanently deleted."
Write-Host "Moved legacy files to:"
Write-Host $archive
'@
[IO.File]::WriteAllText((Join-Path $Root "CLEAN_WEMOTE_FOLDER.ps1"),$cleanupPs1,$utf8)
$cleanupCmd='@echo off
title WEMOTE Folder Cleanup
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CLEAN_WEMOTE_FOLDER.ps1"
echo.
pause
'
[IO.File]::WriteAllText((Join-Path $Root "CLEAN_WEMOTE_FOLDER.cmd"),$cleanupCmd,$utf8)

Start-Process -FilePath (Join-Path $Root "RUN_CONTROLLER.cmd") -WorkingDirectory $Root
Start-Sleep -Seconds 2
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "WEMOTE v0.5.5 READY" -ForegroundColor Green
Write-Host "Scheduler form overwrite and ON-state fixes installed." -ForegroundColor Green
Write-Host "Cleanup helper added: CLEAN_WEMOTE_FOLDER.cmd" -ForegroundColor Green
exit 0
