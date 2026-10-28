# Windows-GPU-UNLOCK 세팅 및 실행 가이드 (`v0.3.0` 기준)

이 폴더(`C:\Users\<username>\misc\261027_Windows-GPU-UNLOCK`)는 아카라이브 게시글([https://arca.live/b/aiart/186860914](https://arca.live/b/aiart/186860914)) 및 공식 GitHub 저장소([`impacifist/Windows-GPU-UNLOCK`](https://github.com/impacifist/Windows-GPU-UNLOCK))의 지침에 따라 **USB나 내장 그래픽 없이 파티션 체인로딩 방식으로 GPU 언락**을 구성할 수 있도록 준비된 작업 공간입니다.

> [!NOTE]
> **실제 검증 완료 사양:** 본 툴킷 워크플로는 **AMD Ryzen 7 5700X3D + B450 메인보드 + NVIDIA GeForce RTX 3090 Ti** 환경에서 USB EFI 체인로딩 및 텐서 코어 언락 성공이 직접 검증되었습니다.

---

## 📁 구성된 파일 목록

| 파일명 | 설명 |
| :--- | :--- |
| [`1_fetch_repo_and_check.ps1`](./1_fetch_repo_and_check.ps1) | **1단계:** 현재 PC의 GPU, Secure Boot, BitLocker, 파티션(Windows ESP GUID), 필수 툴체인을 점검하고 `impacifist/Windows-GPU-UNLOCK` 원본 저장소를 `Windows-GPU-UNLOCK-src`에 클론합니다. |
| [`2_build_assets_wsl.sh`](./2_build_assets_wsl.sh) | **2단계 (WSL 실행):** 저작권 문제로 저장소에 포함되지 않은 5개의 필수 NVIDIA 펌웨어 바이너리(`.bin`)를 `Zagitta/gpu-unlock`에서 추출하여 `Windows-GPU-UNLOCK-src/assets/`에 복사합니다. |
| [`3_configure_and_build.ps1`](./3_configure_and_build.ps1) | **3단계 (관리자 PowerShell):** `Configure.ps1` → `build-unlock.ps1` → `Headless.ps1 -Register`를 순차 실행하여 EFI 바이너리를 빌드하고 부트 메뉴(F8 등)에 수동 테스트 항목을 등록합니다. |
| [`4_enable_auto_or_recover.ps1`](./4_enable_auto_or_recover.ps1) | **4단계 (관리자 PowerShell):** 수동 부팅 테스트가 성공한 뒤, 부팅 순서를 `1. 언락 -> 2. Windows Boot Manager`로 자동화(`-EnableAutomatic -ConfirmedSuccess`)합니다. |

---

## ⚠️ 0단계: 필수 사전 준비 사항 (반드시 확인!)

1. **메인보드 BIOS에서 `Secure Boot(보안 부팅)` 비활성화**
   * 서명되지 않은 커스텀 EFI 애플리케이션이 실행되어야 하므로 반드시 꺼야 합니다.
2. **`C:` 드라이브 BitLocker 완전 해제 (`FullyDecrypted`)**
   * 부팅 경로가 변경될 때 BitLocker 복구 키 요구 창에 갇히지 않도록 `제어판 -> BitLocker 드라이브 암호화`에서 암호화를 완전히 해제하세요.
3. **FAT32 포맷의 USB 메모리 또는 별도 GPT FAT32 파티션 준비**
   * **권장 (가장 안전): FAT32 USB 메모리 (1GB ~ 4GB 이상)**
     * 하드웨어 프로필 진단 및 언락 페이로드를 담아 부팅할 전용 USB 메모리를 준비하고 FAT32로 포맷합니다. 문제가 생겨도 USB만 뽑으면 즉시 순정 부팅되므로 가장 안전합니다.
   * **대체 방식 (내부 디스크 체인로딩 시): 별도 `1 GiB (1024 MB) 이상` GPT FAT32 파티션 생성 (예: `U:` 드라이브)**
     * **절대 기존 Windows의 기본 100MB EFI 시스템 파티션(ESP)이나 복구 파티션을 건드리지 마세요!**
     * `디스크 관리(diskmgmt.msc)`에서 여유 공간 있는 디스크를 `1024 MB ~ 2048 MB` 정도 축소(Shrink)한 뒤, **새 단순 볼륨 → 드라이브 문자 `U` 할당 → `FAT32` 포맷**으로 별도 파티션을 만들어 둡니다.
4. **필수 도구 설치 (Windows 및 WSL)**
   * **Windows:** `Git`, `Python 3.9+`, `LLVM (Clang / lld-link)`
     * LLVM은 PowerShell에서 `winget install LLVM.LLVM`으로 간편하게 설치할 수 있습니다.
   * **WSL (Ubuntu 등):** `git`, `make`, `tar`, `zstd`, `python3` (또는 `python3.14`)

---

## 🚀 단계별 실행 순서

### Step 1. 환경 점검 및 소스 코드 다운로드
**관리자 권한 PowerShell**을 열고 아래 명령을 실행합니다:
```powershell
cd C:\Users\<username>\misc\261027_Windows-GPU-UNLOCK
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\1_fetch_repo_and_check.ps1
```
* 스크립트가 완료되면 `Windows-GPU-UNLOCK-src` 폴더가 생성되고, 현재 Windows 기본 ESP의 GUID가 `windows_esp_guid.txt`에 기록됩니다.

---

### Step 2. WSL에서 펌웨어 에셋(`.bin` 5종) 생성
공식 저장소는 라이선스상 NVIDIA 펌웨어 바이너리를 직접 배포하지 않으므로, WSL을 통해 생성합니다:
```powershell
wsl bash ./2_build_assets_wsl.sh
```
성공하면 `Windows-GPU-UNLOCK-src\assets\` 폴더 안에 아래 5개 파일이 들어갑니다:
* `booter_load_ga102.bin`
* `v67-ga102-610.43.03.bin`
* `gsp_ga10x.bin`
* `gsp_boot_ga102.bin`
* `gsp_boot_desc_ga102.bin`

---

### Step 3. 파티션 매핑, EFI 빌드 및 수동 부트 항목 등록
언락용 FAT32 파티션이 `U:` 드라이브로 준비되었다면, **관리자 권한 PowerShell**에서 실행합니다:
```powershell
.\3_configure_and_build.ps1 -UnlockDriveLetter U
```
> **참고 (하드웨어 프로필 불일치 오류가 발생할 경우):**
> * `impacifist/Windows-GPU-UNLOCK`은 안전을 위해 메인보드/BIOS/GPU의 하드웨어 지문(`machine-profile.h` / `proven.json`)을 엄격히 대조합니다.
> * 본인 PC가 기본 프로필과 다를 경우 `Windows-GPU-UNLOCK-src\docs\NEW-MACHINE.ko.md` (또는 `NEW-MACHINE.en.md`) 절차에 따라 읽기 전용 하드웨어 캡처(`build-probe.ps1`)를 수행해 `-HardwareProfile local` 프로필을 생성하거나, 출력된 에러 메시지를 이 대화창에 붙여넣어 주시면 본인 PC 사양에 맞게 프로필 코드를 수정해 드릴 수 있습니다.

---

### Step 4. 재부팅 후 수동 테스트 (F8 / F11 / F12)
1. PC를 재부팅하면서 메인보드 부트 메뉴 단축키(ASUS `F8`, MSI `F11`, Gigabyte `F12`, ASRock `F11`)를 연타합니다.
2. 부트 메뉴에서 **`GPU Headless UNLOCK - EXPERIMENTAL`** 항목을 선택합니다.
3. 언락이 진행되는 동안 화면이 잠시 깜빡이거나 신호 없음 상태가 되었다가 Windows 로그인 화면으로 넘어오면 정상입니다.
4. ComfyUI나 벤치마크를 돌려 BF16/FP16 속도 향상을 확인합니다.

---

### Step 5. 자동 부팅(1순위 언락 -> 2순위 Windows) 활성화
Step 4에서 수동 테스트가 완벽히 성공했다면, 매번 부트 메뉴를 누를 필요 없도록 자동 부팅을 켭니다:
```powershell
.\4_enable_auto_or_recover.ps1
```
(메뉴에서 `1` 선택 시 `.\internal-boot\Headless.ps1 -EnableAutomatic -ConfirmedSuccess`가 실행됩니다.)

---

## 🛟 되돌리기(원상 복구) 및 비상 안전 장치

이 방식은 그래픽카드 롬(VBIOS)이나 기존 Windows 시스템 파티션(ESP)을 전혀 개조하지 않으므로 **언제든 100% 순정 상태로 되돌릴 수 있습니다.**

1. **1회성 건너뛰기 (부팅 중 `Esc` 키):**
   * 부팅 초기 **5초 이내에 `Esc` 키**를 누르면 이번 부팅에서만 언락을 건너뛰고 순정 상태로 Windows에 진입합니다.
2. **명령어로 순정 부팅 복원 (공식 복구 옵션):**
   * [`4_enable_auto_or_recover.ps1`](./4_enable_auto_or_recover.ps1)을 실행해 **`2`번**을 선택하거나, 관리자 PowerShell에서 아래 명령어를 실행합니다:
     ```powershell
     .\Windows-GPU-UNLOCK-src\internal-boot\Headless.ps1 -RestoreWindowsFirst
     ```
   * 이 명령은 `Windows Boot Manager`를 다시 부팅 1순위로 돌려놓고 Windows 빠른 시작(Fast Startup) 설정도 원래대로 복원합니다. 이후 PC 전원을 한 번 완전히 껐다 켜면(Cold Boot) GPU 레지스터도 초기 순정 상태로 돌아옵니다.
3. **윈도우 진입이 안 될 때 (BIOS / 부트 메뉴 복구):**
   * 본체 전원 버튼을 길게 눌러 끈 뒤, 다시 켜면서 부트 메뉴 키(ASUS `F8`, MSI `F11`, Gigabyte `F12`) 또는 BIOS(`Del`/`F2`)로 들어가 **`Windows Boot Manager`를 직접 선택(또는 1순위 지정)**하면 즉시 정상 부팅됩니다.
4. **완전 삭제 (파티션 회수):**
   * 위 2번(`-RestoreWindowsFirst`) 수행 후, 디스크 관리(`diskmgmt.msc`)에서 언락용으로 만들었던 `U:`(1GiB FAT32) 파티션을 삭제하고 원래 볼륨에 다시 합치면 흔적 없이 제거됩니다.
