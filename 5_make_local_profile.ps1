#Requires -RunAsAdministrator
#Requires -Version 5.1
param(
    [string]$TargetDrive = 'U',
    [string]$WindowsEspGuid = '',
    [string]$ClangPath = '',
    [string]$LldLinkPath = ''
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = 'Stop'
$WorkDir = $PSScriptRoot
$RepoDir = Join-Path $WorkDir 'Windows-GPU-UNLOCK-src'

if (-not (Test-Path $RepoDir)) {
    throw 'Windows-GPU-UNLOCK-src folder not found.'
}

# 1. Clang / lld-link lookup
if ([string]::IsNullOrWhiteSpace($ClangPath) -or -not (Test-Path $ClangPath)) {
    $candidates = @('clang.exe', 'C:\Program Files\LLVM\bin\clang.exe', 'C:\TOOLS\LLVM20\bin\clang.exe')
    foreach ($c in $candidates) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { $ClangPath = $cmd.Source; break }
        if (Test-Path $c) { $ClangPath = $c; break }
    }
}
if ([string]::IsNullOrWhiteSpace($LldLinkPath) -or -not (Test-Path $LldLinkPath)) {
    $candidates = @('lld-link.exe', 'C:\Program Files\LLVM\bin\lld-link.exe', 'C:\TOOLS\LLVM20\bin\lld-link.exe')
    foreach ($c in $candidates) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { $LldLinkPath = $cmd.Source; break }
        if (Test-Path $c) { $LldLinkPath = $c; break }
    }
}

# 2. Windows ESP GUID lookup
if ([string]::IsNullOrWhiteSpace($WindowsEspGuid)) {
    $guidFile = Join-Path $WorkDir 'windows_esp_guid.txt'
    if (Test-Path $guidFile) {
        $WindowsEspGuid = (Get-Content $guidFile -Raw).Trim()
    } else {
        $sysPart = Get-Partition | Where-Object { $_.IsSystem -eq $true } | Select-Object -First 1
        $WindowsEspGuid = $sysPart.Guid
    }
}

# 3. vcvars64.bat lookup
$VcVarsPath = ''
$vcCandidates = @(
    'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat',
    'C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
)
foreach ($v in $vcCandidates) {
    if (Test-Path $v) { $VcVarsPath = $v; break }
}

$TargetDrive = $TargetDrive.TrimEnd(':')
$AssetsDir = Join-Path $RepoDir 'assets'

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [NEW-MACHINE] Local Hardware Profile Pipeline" -ForegroundColor Cyan
Write-Host "  - Target Drive : ${TargetDrive}:"
Write-Host "  - Windows ESP  : $WindowsEspGuid"
if ($VcVarsPath) { Write-Host "  - MSVC vcvars  : $VcVarsPath" -ForegroundColor Green }
Write-Host "==========================================================" -ForegroundColor Cyan

Push-Location $RepoDir
try {
    $newMachineScript = Join-Path $RepoDir 'research\profile\new-machine.ps1'
    if (-not (Test-Path $newMachineScript)) {
        throw "research\profile\new-machine.ps1 not found."
    }

    $nmArgs = @{
        Drive          = $TargetDrive
        WindowsEspGuid = $WindowsEspGuid
        Assets         = $AssetsDir
        Clang          = $ClangPath
        LldLink        = $LldLinkPath
    }
    if ($VcVarsPath) { $nmArgs['VcVars'] = $VcVarsPath }

    & $newMachineScript @nmArgs
} finally {
    Pop-Location
}
