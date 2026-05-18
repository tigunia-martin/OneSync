#requires -Version 5.1
<#
.SYNOPSIS
    Builds OneSync.msi end-to-end (publish + stage + WiX).

.DESCRIPTION
    1. dotnet publish OneSync.csproj in Release (self-contained single-file win-x64)
    2. Copy the published artefacts into stage/ alongside the pre-built
       OneSyncShellOverlay.dll, OneDriveFolder.ico, and License.rtf
    3. Run `wix build` with -arch x64 so the MSI installs to the 64-bit
       Program Files (not Program Files (x86) — WiX v6 defaults to x86)

    Run from any working directory; paths are resolved relative to the
    script. Requires the WiX v6 CLI (`wix`) and the .NET SDK on PATH.

.EXAMPLE
    .\build.ps1
    Produces OneSync.msi in this folder.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$installerDir = $PSScriptRoot
$repoRoot     = Resolve-Path (Join-Path $installerDir '..\..')
$srcProject   = Join-Path $repoRoot 'src\OneSync\OneSync.csproj'
$publishDir   = Join-Path $repoRoot 'src\OneSync\bin\Release\net8.0-windows10.0.19041.0\win-x64\publish'
$stageDir     = Join-Path $installerDir 'stage'
$wxs          = Join-Path $installerDir 'OneSync.wxs'
$msi          = Join-Path $installerDir 'OneSync.msi'
$bundleWxs    = Join-Path $installerDir 'OneSync.Bundle.wxs'
$distDir      = Join-Path $repoRoot 'dist'
$bundleExe    = Join-Path $distDir 'OneSyncSetup.exe'

Write-Host "[1/4] Publishing OneSync (Release, win-x64, self-contained)..." -ForegroundColor Cyan
dotnet publish $srcProject -c Release -r win-x64 --nologo | Out-Host
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)" }

Write-Host "[2/4] Staging artefacts..." -ForegroundColor Cyan
# Publisher outputs go to stage/. Pre-built native artefacts (OneSyncShellOverlay.dll,
# OneDriveFolder.ico, License.rtf) are already in stage/ and not touched here.
$payload = @('OneSync.exe', 'config.json', 'config.template.json', 'README.md', 'icon.ico')
foreach ($f in $payload) {
    $src = Join-Path $publishDir $f
    if (-not (Test-Path $src)) { throw "Expected publish output missing: $src" }
    Copy-Item $src $stageDir -Force
}
foreach ($required in @('OneSyncShellOverlay.dll', 'OneDriveFolder.ico', 'License.rtf')) {
    if (-not (Test-Path (Join-Path $stageDir $required))) {
        throw "Pre-built artefact missing from stage/: $required (rebuild ShellOverlay separately if needed)"
    }
}

Write-Host "[3/4] Building MSI with WiX (-arch x64)..." -ForegroundColor Cyan
wix build $wxs -arch x64 -d "SourceDir=$stageDir" -ext WixToolset.UI.wixext -out $msi | Out-Host
if ($LASTEXITCODE -ne 0) { throw "wix build failed (exit $LASTEXITCODE)" }

$msiInfo = Get-Item $msi
Write-Host "  Built: $($msiInfo.FullName) ($([math]::Round($msiInfo.Length/1MB, 2)) MB)" -ForegroundColor DarkGray

# Bundle: chains Dokan_x64.msi + OneSync.msi into one bootstrapper. SourceDir
# points at the LightweightCDM root so the bundle's MsiPackage references can
# resolve both dist/Dokan_x64.msi and src/OneSync.Installer/OneSync.msi.
Write-Host "[4/4] Building Burn bundle (OneSyncSetup.exe)..." -ForegroundColor Cyan
$dokanMsi = Join-Path $distDir 'Dokan_x64.msi'
if (-not (Test-Path $dokanMsi)) { throw "Bundle dependency missing: $dokanMsi (expected at dist/Dokan_x64.msi)" }
if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }

wix build $bundleWxs -arch x64 -d "SourceDir=$repoRoot" -ext WixToolset.BootstrapperApplications.wixext -out $bundleExe | Out-Host
if ($LASTEXITCODE -ne 0) { throw "wix bundle build failed (exit $LASTEXITCODE)" }

$bundleInfo = Get-Item $bundleExe
Write-Host ""
Write-Host "Built MSI:    $($msiInfo.FullName) ($([math]::Round($msiInfo.Length/1MB, 2)) MB)" -ForegroundColor Green
Write-Host "Built bundle: $($bundleInfo.FullName) ($([math]::Round($bundleInfo.Length/1MB, 2)) MB)" -ForegroundColor Green
