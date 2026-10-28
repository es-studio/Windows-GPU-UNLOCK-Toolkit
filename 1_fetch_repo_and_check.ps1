[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
#Requires -Version 5.1
<#
.SYNOPSIS
    1단계: 시스템 환경(GPU, Secure Boot, BitLocker, 파티션 GUID, LLVM/Python) 점검 및
    impacifist/Windows-GPU-UNLOCK 공식 저장소 클론 스크립트
#>

$ErrorActionPreference = "Stop"
$WorkDir = $PSScriptRoot
Set-Location $WorkDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [1/5] 시스템 하드웨어 및 GPU 확인" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
try {
    $gpus = Get-CimInstance Win32_VideoController | Select-Object Name, PNPDeviceID, DriverVersion
    $gpus | Format-Table -AutoSize
} catch {
    Write-Warning "GPU 정보를 가져오지 못했습니다: $_"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [2/5] Secure Boot 및 BitLocker 상태 점검" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
try {
    $sb = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    if ($sb -eq $true) {
        Write-Warning "[주의] 현재 Secure Boot가 켜져 있습니다 (True). BIOS에서 비활성화해야 합니다!"
    } elseif ($sb -eq $false) {
        Write-Host "[통과] Secure Boot가 비활성화되어 있습니다 (False)." -ForegroundColor Green
    } else {
        Write-Host "[참고] Secure Boot 상태를 읽으려면 관리자 권한 PowerShell이 필요합니다." -ForegroundColor Yellow
    }
} catch {
    Write-Host "[참고] Secure Boot 상태 확인 생략: $_" -ForegroundColor Yellow
}

try {
    $bl = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
    if ($null -ne $bl) {
        Write-Host "C: 드라이브 BitLocker 상태: VolumeStatus=$($bl.VolumeStatus), ProtectionStatus=$($bl.ProtectionStatus)"
        if ($bl.VolumeStatus -ne "FullyDecrypted") {
            Write-Warning "[주의] C: 드라이브가 완전히 복호화(FullyDecrypted)되어 있지 않습니다. BitLocker를 완전히 해제해야 합니다."
        } else {
            Write-Host "[통과] C: 드라이브 BitLocker 해제 확인됨 (FullyDecrypted)." -ForegroundColor Green
        }
    } else {
        Write-Host "[참고] BitLocker 상태를 확인하려면 관리자 권한으로 실행하세요." -ForegroundColor Yellow
    }
} catch {
    Write-Host "[참고] BitLocker 확인 생략 (관리자 권한 필요)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [3/5] 파티션 목록 및 Windows ESP GUID 확인" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
try {
    $partitions = Get-Partition | Select-Object DiskNumber, PartitionNumber, DriveLetter, @{Name="Size(MB)";Expression={[math]::Round($_.Size/1MB, 1)}}, Guid, IsSystem, GptType
    $partitions | Format-Table -AutoSize

    $cDisk = (Get-Partition -DriveLetter C -ErrorAction SilentlyContinue).DiskNumber
    $sysEsp = $partitions | Where-Object { $_.IsSystem -eq $true -and ($null -eq $cDisk -or $_.DiskNumber -eq $cDisk) } | Select-Object -First 1
    if (-not $sysEsp) {
        $sysEsp = $partitions | Where-Object { $_.IsSystem -eq $true } | Select-Object -First 1
    }
    if ($sysEsp) {
        Write-Host "[확인된 Windows 기본 ESP GUID]: $($sysEsp.Guid)" -ForegroundColor Green
        $sysEsp.Guid | Set-Content -Path (Join-Path $WorkDir "windows_esp_guid.txt") -Encoding UTF8
        Write-Host " -> windows_esp_guid.txt 파일에 저장되었습니다." -ForegroundColor Gray
    }
} catch {
    Write-Warning "파티션 정보를 읽으려면 관리자 권한 PowerShell로 실행해 주세요."
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [4/5] 필수 빌드 도구(Git, Python, LLVM/Clang, WSL) 확인" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

foreach ($cmd in @("git", "python", "clang", "lld-link", "wsl")) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "[설치됨] $cmd -> $($found.Source)" -ForegroundColor Green
    } else {
        Write-Host "[미확인] $cmd (PATH에 없거나 별도 경로 지정 필요)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [5/5] impacifist/Windows-GPU-UNLOCK 저장소 다운로드" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$RepoDir = Join-Path $WorkDir "Windows-GPU-UNLOCK-src"
if (-not (Test-Path $RepoDir)) {
    Write-Host "GitHub에서 impacifist/Windows-GPU-UNLOCK 클론 중..." -ForegroundColor Cyan
    git clone https://github.com/impacifist/Windows-GPU-UNLOCK.git $RepoDir
} else {
    Write-Host "이미 $RepoDir 디렉토리가 존재합니다. 최신 커밋을 가져옵니다 (git pull)..." -ForegroundColor Cyan
    Push-Location $RepoDir
    git pull
    Pop-Location
}

$AssetsDir = Join-Path $RepoDir "assets"
if (-not (Test-Path $AssetsDir)) {
    New-Item -ItemType Directory -Path $AssetsDir | Out-Null
    Write-Host "assets 디렉토리 생성 완료: $AssetsDir" -ForegroundColor Green
}

# WSL 스크립트의 CRLF -> LF 자동 정제 (Windows/WSL 개행 호환성 보장)
$shFile = Join-Path $WorkDir "2_build_assets_wsl.sh"
if (Test-Path $shFile) {
    try {
        $rawText = [System.IO.File]::ReadAllText($shFile)
        if ($rawText.Contains("`r`n")) {
            [System.IO.File]::WriteAllText($shFile, $rawText.Replace("`r`n", "`n"))
            Write-Host " -> 2_build_assets_wsl.sh 개행을 Linux(LF) 형식으로 자동 변환했습니다." -ForegroundColor Gray
        }
    } catch {
        # 무시
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " 1단계 완료! 다음 순서:" -ForegroundColor Green
Write-Host "  1) WSL에서 펌웨어 에셋 추출: wsl bash ./2_build_assets_wsl.sh" -ForegroundColor White
Write-Host "  2) 1GiB 이상 별도 FAT32 파티션(예: U:) 준비 후 3_configure_and_build.ps1 실행" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Green
