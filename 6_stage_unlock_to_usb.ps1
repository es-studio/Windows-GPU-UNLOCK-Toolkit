#Requires -RunAsAdministrator
#Requires -Version 5.1
param(
    [string]$TargetDrive = 'I'
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = 'Stop'
$WorkDir = $PSScriptRoot
$RepoDir = Join-Path $WorkDir 'Windows-GPU-UNLOCK-src'

if (-not (Test-Path $RepoDir)) {
    throw 'Windows-GPU-UNLOCK-src folder not found.'
}

$ClangPath = 'C:\Program Files\LLVM\bin\clang.exe'
$LldLinkPath = 'C:\Program Files\LLVM\bin\lld-link.exe'
$VcVarsPath = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat'
$WindowsEspGuid = '1f5e6b36-5cb7-4aa1-80b7-bc1b79f15c8b'
$AssetsDir = Join-Path $RepoDir 'assets'

$TargetDrive = $TargetDrive.TrimEnd(':')

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [STAGE-UNLOCK] Staging unlock files to USB drive ${TargetDrive}:" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

Push-Location $RepoDir
try {
    $newMachineScript = Join-Path $RepoDir 'research\profile\new-machine.ps1'
    if (-not (Test-Path $newMachineScript)) {
        throw "research\profile\new-machine.ps1 not found."
    }

    & $newMachineScript `
        -Drive $TargetDrive `
        -WindowsEspGuid $WindowsEspGuid `
        -Assets $AssetsDir `
        -Clang $ClangPath `
        -LldLink $LldLinkPath `
        -VcVars $VcVarsPath `
        -StageUnlock
} finally {
    Pop-Location
}
