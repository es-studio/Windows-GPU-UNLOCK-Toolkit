[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
.SYNOPSIS
    4단계: 자동 부팅 활성화 및 원상 복구(-RestoreWindowsFirst) 관리 도구
#>

$ErrorActionPreference = "Stop"
$WorkDir = $PSScriptRoot
$RepoDir = Join-Path $WorkDir "Windows-GPU-UNLOCK-src"

if (-not (Test-Path $RepoDir)) {
    throw "Windows-GPU-UNLOCK-src 폴더가 없습니다."
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " GPU Headless UNLOCK 자동 부팅 설정 및 원상 복구 도구" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " 1) 자동 부팅 활성화 (-EnableAutomatic -ConfirmedSuccess)" -ForegroundColor Green
Write-Host "    -> 부트 메뉴(F8 등) 수동 테스트가 성공한 뒤 실행하세요."
Write-Host ""
Write-Host " 2) 순정 부팅 순서로 원상 복구 (-RestoreWindowsFirst)" -ForegroundColor Yellow
Write-Host "    -> Windows Boot Manager를 다시 1순위로 복원하고 빠른 시작(Fast Startup) 설정을 되돌립니다."
Write-Host ""
Write-Host " 3) 현재 Windows UEFI(NVRAM) 부팅 항목 목록 확인 (bcdedit /enum firmware)" -ForegroundColor White
Write-Host " Q) 종료"
Write-Host ""

$choice = Read-Host "원하는 작업 번호를 입력하세요"

$headlessScript = Join-Path $RepoDir "internal-boot\Headless.ps1"
if (-not (Test-Path $headlessScript)) {
    throw "internal-boot\Headless.ps1 을 찾을 수 없습니다. 1단계와 3단계를 먼저 완료해 주세요."
}

Push-Location $RepoDir
try {
    switch ($choice) {
        "1" {
            Write-Host "`nHeadless.ps1 -EnableAutomatic -ConfirmedSuccess 실행 중..." -ForegroundColor Cyan
            & $headlessScript -EnableAutomatic -ConfirmedSuccess
            Write-Host "`n[완료] 이제 전원을 켜면 자동으로 언락 후 Windows로 부팅됩니다." -ForegroundColor Green
            Write-Host "부팅 초기 5초 내에 Esc를 누르면 언락을 건너뛰고 일반 부팅됩니다." -ForegroundColor Gray
        }
        "2" {
            Write-Host "`nHeadless.ps1 -RestoreWindowsFirst 실행 중 (순정 부팅 복원)..." -ForegroundColor Cyan
            & $headlessScript -RestoreWindowsFirst
            Write-Host "`n[복구 완료] Windows Boot Manager가 1순위로 복원되었습니다." -ForegroundColor Green
            Write-Host "PC를 완전히 종료(Shutdown) 후 다시 켜면 그래픽카드도 100% 순정 상태로 돌아옵니다." -ForegroundColor Gray
        }
        "3" {
            bcdedit /enum firmware
        }
        default {
            Write-Host "종료합니다."
        }
    }
} finally {
    Pop-Location
}
