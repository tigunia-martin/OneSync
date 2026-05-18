#requires -Version 5.1
<#
.SYNOPSIS
  Compile + build MSI + reinstall + restart cycle.
  Adapted for a machine where Dokan2 is in StopPending and drives won't mount
  — that's a separate environment issue and doesn't affect fix verification.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)] [string]$Version
)
$ErrorActionPreference = 'Stop'

Write-Host "[1/7] Stop OneSync gracefully (or forcibly)" -ForegroundColor Cyan
Get-Process OneSync -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 3

Write-Host "[2/7] Reset shell folders + bounce Explorer for .lnk lock" -ForegroundColor Cyan
$usf = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
$sf  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
@{ 'Desktop'='%USERPROFILE%\Desktop';'My Music'='%USERPROFILE%\Music';'My Pictures'='%USERPROFILE%\Pictures';'My Video'='%USERPROFILE%\Videos';'Personal'='%USERPROFILE%\Documents';'{374DE290-123F-4565-9164-39C4925E467B}'='%USERPROFILE%\Downloads' }.GetEnumerator() | ForEach-Object {
  Remove-ItemProperty $usf $_.Key -ErrorAction SilentlyContinue
  New-ItemProperty $usf $_.Key -PropertyType ExpandString -Value $_.Value -Force | Out-Null
  Set-ItemProperty $sf $_.Key -Value ([Environment]::ExpandEnvironmentVariables($_.Value)) -Type String -Force
}
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2; Start-Process explorer.exe; Start-Sleep 3

Write-Host "[3/7] Build MSI" -ForegroundColor Cyan
& "$PSScriptRoot\build.ps1" 2>&1 | Select-Object -Last 2

Write-Host "[4/7] Uninstall current, install new" -ForegroundColor Cyan
$pkg = Get-WmiObject Win32_Product -Filter "Name='OneSync'" -ErrorAction SilentlyContinue
if ($pkg) { Start-Process msiexec.exe -ArgumentList '/x',$pkg.IdentifyingNumber,'/quiet','/norestart' -Wait | Out-Null }
Start-Sleep 2
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2; Start-Process explorer.exe; Start-Sleep 3
$logName = "install-$Version.log"
$p = Start-Process msiexec.exe -ArgumentList '/i',"$PSScriptRoot\OneSync.msi",'/quiet','/norestart','/l*v',"$PSScriptRoot\$logName" -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) { Write-Error "Install failed exit $($p.ExitCode); see $logName" ; return }
Write-Host "  Installed: $((Get-ItemProperty 'HKLM:\SOFTWARE\OneSync').Version)"

Write-Host "[5/7] Stop MSI-launched OneSync + restore real config" -ForegroundColor Cyan
Get-Process OneSync -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 3
$cfg = Get-Content "C:\Program Files\OneSync\config.json.bak-20260515" -Raw | ConvertFrom-Json
$coop = @{ enabled=$true; controlFolder='.onesync-test'; leaseTtlSeconds=600; renewIntervalSeconds=300; readerPollIntervalSeconds=300; selfCheckIntervalMinutes=60; lazyFallbackEnabled=$true; lazyFallbackCacheSeconds=300; cacheForceWriteEveryNCycles=12; cacheItemMaxAgeDays=30; forceReaderRoleAlongsideLeader=$false }
$cfg | Add-Member -NotePropertyName 'cooperativePolling' -NotePropertyValue $coop -Force
$cfg | ConvertTo-Json -Depth 10 | Set-Content "C:\Program Files\OneSync\config.json" -Encoding UTF8

Write-Host "[6/7] Clear logs and start" -ForegroundColor Cyan
Remove-Item "$env:LOCALAPPDATA\OneSync\Logs\*.log" -Force -ErrorAction SilentlyContinue
& explorer.exe "C:\Program Files\OneSync\OneSync.exe"
Start-Sleep 22

Write-Host "[7/7] Verify" -ForegroundColor Cyan
$proc = Get-Process OneSync -ErrorAction SilentlyContinue
if ($proc) { Write-Host "  Running PID $($proc.Id) version $($proc.MainModule.FileVersionInfo.FileVersion)" }
$log = "$env:LOCALAPPDATA\OneSync\Logs\onesync-20260515.log"
# Filter pre-existing "Drive letter X: already in use" + "No drives mounted" caused by stuck Dokan2 — environment issue, not regression.
$realWarn = Select-String -Path $log -Pattern " WRN " | Where-Object { $_.Line -notmatch "already in use|No drives mounted" }
$realErr  = Select-String -Path $log -Pattern " ERR "
Write-Host "  WRN (excluding Dokan-state): $($realWarn.Count)   ERR: $($realErr.Count)"
if ($realWarn) { Write-Host "  --- WRN ---"; $realWarn | ForEach-Object { "  " + $_.Line } }
if ($realErr)  { Write-Host "  --- ERR ---"; $realErr  | ForEach-Object { "  " + $_.Line } }
