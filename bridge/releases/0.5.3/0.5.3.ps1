param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference="Stop"
$ProgressPreference="SilentlyContinue"
$utf8=New-Object System.Text.UTF8Encoding($false)
$base="https://raw.githubusercontent.com/sczahra/wemote/main/bridge/releases/0.5.3"
$assets=@(
  @{name="app.js"; path="app\static\app.js"; sha="23dd80d638bae2ebe37786a9ef5710fc86c4af2fac9e72c0e30c6f6f50c65cbc"},
  @{name="wemo_controller.py"; path="app\wemo_controller.py"; sha="7f3e6874dd4c4995d84d28bb74c85cd6ee23e7f58ee8c6785e7ebd09c3008213"}
)
$stage=Join-Path $env:TEMP ("wemote-053-"+[guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach($a in $assets){
  $tmp=Join-Path $stage $a.name
  Invoke-WebRequest -Uri ($base+"/"+$a.name) -OutFile $tmp -TimeoutSec 60
  $actual=(Get-FileHash $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
  if($actual -ne $a.sha){throw "Verification failed for $($a.name). Nothing was installed."}
}
$Backups=Join-Path $Root "backups"
New-Item -ItemType Directory -Force -Path $Backups | Out-Null
$current=if(Test-Path(Join-Path $Root "VERSION")){(Get-Content(Join-Path $Root "VERSION") -Raw).Trim()}else{"unknown"}
$backup=Join-Path $Backups ("wemote-"+$current+"-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".zip")
$items=@()
foreach($n in @("app","VERSION")){$p=Join-Path $Root $n;if(Test-Path $p){$items+=$p}}
if($items.Count -gt 0){Compress-Archive -Path $items -DestinationPath $backup -Force}
$conns=Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
foreach($c in $conns){$p=Get-CimInstance Win32_Process -Filter "ProcessId=$($c.OwningProcess)" -ErrorAction SilentlyContinue;if($p -and $p.CommandLine -match "uvicorn" -and $p.CommandLine -match "app\.main"){Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue}}
Start-Sleep -Milliseconds 500
foreach($a in $assets){
  $dest=Join-Path $Root $a.path
  Copy-Item -LiteralPath (Join-Path $stage $a.name) -Destination $dest -Force
}
$main=Join-Path $Root "app\main.py"
if(Test-Path $main){$s=Get-Content $main -Raw;$s=[regex]::Replace($s,'version="[^"]+"','version="0.5.3"',1);[IO.File]::WriteAllText($main,$s,$utf8)}
$index=Join-Path $Root "app\static\index.html"
if(Test-Path $index){$s=Get-Content $index -Raw;$s=[regex]::Replace($s,'<title>WEMOTE v[^<]+</title>','<title>WEMOTE v0.5.3</title>');$s=[regex]::Replace($s,'<h1>WEMOTE v[^<]+</h1>','<h1>WEMOTE v0.5.3</h1>',1);$s=[regex]::Replace($s,'(<span id="appVersion">)[^<]*(</span>)','$10.5.3$2');[IO.File]::WriteAllText($index,$s,$utf8)}
[IO.File]::WriteAllText((Join-Path $Root "VERSION"),"0.5.3`n",$utf8)
Start-Process -FilePath (Join-Path $Root "RUN_CONTROLLER.cmd") -WorkingDirectory $Root
Start-Sleep -Seconds 2
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "WEMOTE v0.5.3 READY" -ForegroundColor Green
Write-Host "Fixed schedule form polling and ON-state reporting." -ForegroundColor Green
Write-Host "Backup: $backup"
exit 0
