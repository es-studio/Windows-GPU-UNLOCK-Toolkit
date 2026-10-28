#Requires -RunAsAdministrator
#Requires -Version 5.1
param(
    [string]$UnlockDriveLetter = 'U',
    [string]$WindowsEspGuid = '',
    [string]$ClangPath = '',
    [string]$LldLinkPath = '',
    [string]$HardwareProfile = ''
)

$ErrorActionPreference = 'Stop'
$WorkDir = $PSScriptRoot
$RepoDir = Join-Path $WorkDir 'Windows-GPU-UNLOCK-src'

if (-not (Test-Path $RepoDir)) {
    throw 'Windows-GPU-UNLOCK-src folder not found. Run 1_fetch_repo_and_check.ps1 first.'
}

# 1. Assets Check
$RequiredBins = @(
    'booter_load_ga102.bin',
    'v67-ga102-610.43.03.bin',
    'gsp_ga10x.bin',
    'gsp_boot_ga102.bin',
    'gsp_boot_desc_ga102.bin'
)
$AssetsDir = Join-Path $RepoDir 'assets'
foreach ($bin in $RequiredBins) {
    $binPath = Join-Path $AssetsDir $bin
    if (-not (Test-Path $binPath)) {
        throw "Missing asset: $binPath. Run 'wsl bash ./2_build_assets_wsl.sh' first."
    }
}
Write-Host '[OK] All 5 firmware assets verified.' -ForegroundColor Green

# 2. Clang / lld-link Path Lookup
if ([string]::IsNullOrWhiteSpace($ClangPath) -or -not (Test-Path $ClangPath)) {
    $candidates = @(
        'clang.exe',
        'C:\Program Files\LLVM\bin\clang.exe',
        'C:\TOOLS\LLVM20\bin\clang.exe'
    )
    foreach ($c in $candidates) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { $ClangPath = $cmd.Source; break }
        if (Test-Path $c) { $ClangPath = $c; break }
    }
}
if ([string]::IsNullOrWhiteSpace($LldLinkPath) -or -not (Test-Path $LldLinkPath)) {
    $candidates = @(
        'lld-link.exe',
        'C:\Program Files\LLVM\bin\lld-link.exe',
        'C:\TOOLS\LLVM20\bin\lld-link.exe'
    )
    foreach ($c in $candidates) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { $LldLinkPath = $cmd.Source; break }
        if (Test-Path $c) { $LldLinkPath = $c; break }
    }
}

if (-not (Test-Path $ClangPath) -or -not (Test-Path $LldLinkPath)) {
    throw "LLVM tools (clang/lld-link) not found. Run 'winget install LLVM.LLVM' and reopen PowerShell."
}
Write-Host "[OK] Clang: $ClangPath" -ForegroundColor Green
Write-Host "[OK] lld-link: $LldLinkPath" -ForegroundColor Green

# 3. Windows ESP GUID Lookup
if ([string]::IsNullOrWhiteSpace($WindowsEspGuid)) {
    $guidFile = Join-Path $WorkDir 'windows_esp_guid.txt'
    if (Test-Path $guidFile) {
        $WindowsEspGuid = (Get-Content $guidFile -Raw).Trim()
    } else {
        $sysPart = Get-Partition | Where-Object { $_.IsSystem -eq $true } | Select-Object -First 1
        if ($sysPart -and $sysPart.Guid) {
            $WindowsEspGuid = $sysPart.Guid
        } else {
            throw 'Could not auto-detect Windows ESP GUID. Pass -WindowsEspGuid explicitly.'
        }
    }
}
Write-Host "[OK] Windows ESP GUID: $WindowsEspGuid" -ForegroundColor Green

# 4. Target Unlock Partition Verification
$UnlockDriveLetter = $UnlockDriveLetter.TrimEnd(':')
$unlockVol = Get-Volume -DriveLetter $UnlockDriveLetter -ErrorAction SilentlyContinue
if (-not $unlockVol) {
    throw "Drive ${UnlockDriveLetter}: not found. Please create a 1GiB FAT32 partition in Disk Management."
}
if ($unlockVol.FileSystem -ne 'FAT32') {
    throw "Drive ${UnlockDriveLetter}: must be formatted as FAT32 (currently: $($unlockVol.FileSystem))."
}
Write-Host "[OK] Target Partition: ${UnlockDriveLetter}: (FAT32, $([math]::Round($unlockVol.Size/1GB, 2)) GB)" -ForegroundColor Green

# 5. build-unlock.ps1 Path Detection
$BuildUnlockScript = $null
$possibleBuildPaths = @(
    (Join-Path $RepoDir 'research\headless\build-unlock.ps1'),
    (Join-Path $RepoDir 'internal-boot\build-unlock.ps1'),
    (Join-Path $RepoDir 'build-unlock.ps1')
)
foreach ($p in $possibleBuildPaths) {
    if (Test-Path $p) { $BuildUnlockScript = $p; break }
}
if (-not $BuildUnlockScript) {
    throw 'Could not locate build-unlock.ps1 in the repository.'
}

# 6. HardwareProfile Inspection
$configScript = Join-Path $RepoDir 'internal-boot\Configure.ps1'
if (-not (Test-Path $configScript)) {
    throw 'internal-boot\Configure.ps1 not found.'
}

$profileRequired = $false
try {
    $configCmd = Get-Command $configScript -ErrorAction SilentlyContinue
    if ($configCmd -and $configCmd.Parameters.ContainsKey('HardwareProfile')) {
        $profileRequired = -not $configCmd.Parameters['HardwareProfile'].IsOptional
    }
} catch {
    $profileRequired = $false
}

if ([string]::IsNullOrWhiteSpace($HardwareProfile) -and $profileRequired) {
    Write-Warning 'Configure.ps1 requires -HardwareProfile argument.'
    Write-Host 'Available profiles examples: b650m-3090fe, b660m-3090fe, local' -ForegroundColor Yellow
    $HardwareProfile = Read-Host 'Enter HardwareProfile name (Press Enter for default/local)'
}

Write-Host ''
Write-Host '==========================================================' -ForegroundColor Yellow
Write-Host ' Build Configuration Summary' -ForegroundColor Yellow
Write-Host "  - Repo: $RepoDir"
Write-Host "  - Unlock Drive: ${UnlockDriveLetter}:"
Write-Host "  - Windows ESP: $WindowsEspGuid"
Write-Host "  - HardwareProfile: $(if ($HardwareProfile) { $HardwareProfile } else { '(Default)' })"
Write-Host '==========================================================' -ForegroundColor Yellow
$confirm = Read-Host 'Do you want to proceed? (y/N)'
if ($confirm -notin @('y', 'Y')) {
    Write-Host 'Aborted.'
    exit 0
}

Push-Location $RepoDir
try {
    Write-Host "`n[1/3] Running Configure.ps1..." -ForegroundColor Cyan
    $cfgArgs = @{
        UnlockDriveLetter = $UnlockDriveLetter
        WindowsEspGuid    = $WindowsEspGuid
    }
    if ($HardwareProfile) { $cfgArgs['HardwareProfile'] = $HardwareProfile }
    & $configScript @cfgArgs

    Write-Host "`n[2/3] Running build-unlock.ps1..." -ForegroundColor Cyan
    $buildArgs = @{
        Clang   = $ClangPath
        LldLink = $LldLinkPath
    }
    if ($HardwareProfile) { $buildArgs['HardwareProfile'] = $HardwareProfile }
    & $BuildUnlockScript @buildArgs

    Write-Host "`n[3/3] Running Headless.ps1 -Register..." -ForegroundColor Cyan
    & .\internal-boot\Headless.ps1 -Assets '.\assets' -Register

    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host ' Build & EFI Test Entry Registration Complete!' -ForegroundColor Green
    Write-Host " Reboot and select 'GPU Headless UNLOCK' from boot menu (F8/F11/F12)." -ForegroundColor White
    Write-Host '==========================================================' -ForegroundColor Green
} finally {
    Pop-Location
}
