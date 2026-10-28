# Windows-GPU-UNLOCK Automator & Helper Toolkit

A streamlined, battle-tested helper toolkit and automation workflow for [`impacifist/Windows-GPU-UNLOCK`](https://github.com/impacifist/Windows-GPU-UNLOCK) (port of Zagitta's `gpu-unlock` to Windows/UEFI).

This toolkit automates prerequisites checking, upstream asset extraction via WSL, local hardware profiling (resolving PCIe bus mapping and MSVC/vcvars traps), EFI compilation, and staging the unlock payload onto USB or internal EFI partitions for **NVIDIA RTX 30-series GPUs (e.g. RTX 3090, RTX 3090 Ti)**.

> [!NOTE]
> **Verified Hardware:** Fully tested and operational on an **AMD Ryzen 7 5700X3D + B450 Motherboard + NVIDIA GeForce RTX 3090 Ti** system via USB EFI chainloading.

---

## 🚀 What Does This Toolkit Do?

NVIDIA artificially throttles instruction-issue rates for FP16 and BF16 matrix-multiply operations with FP32 accumulation on GeForce GPUs to segment them from workstation cards (A100, RTX A6000).

`Windows-GPU-UNLOCK` executes before Windows and the NVIDIA display driver load, configuring internal hardware Speed Selectors (`SS0 = 0x88888888`, `SS1 = 0x8`) and performing a PCIe Function Level Reset (FLR). This unleashes full tensor compute throughput (~2x compute in BF16/FP16 w/ FP32 accumulation) for AI workloads like ComfyUI (Flux, SDXL, Wan 2.1) and LLM prefill without permanent VBIOS flashing.

This toolkit resolves common pitfalls encountered during setup on Windows:
- **Encoding & Line Ending Safety**: Enforces UTF-8 and auto-converts CRLF to LF for WSL bash scripts.
- **Accurate ESP Detection**: Identifies the primary boot drive's ESP partition GUID, preventing issues on multi-drive setups.
- **Automated Asset Extraction**: Automatically clones the pinned upstream source and extracts the 5 required firmware `.bin` files via WSL.
- **Custom Hardware Profiling Automation**: Overcomes hardware mismatches (such as non-standard PCIe bus assignments like `TargetBus 0x26`) and resolves Windows command-line character length limits during MSVC `vcvars64.bat` environment imports.

---

## 📁 Repository Structure

| File | Description |
| :--- | :--- |
| [`1_fetch_repo_and_check.ps1`](./1_fetch_repo_and_check.ps1) | **Step 1:** Verifies hardware (GPU model, Secure Boot, BitLocker), auto-detects the active Windows ESP GUID, verifies toolchains (`git`, `python`, `clang`, `lld-link`, `wsl`), clones the upstream repository into `Windows-GPU-UNLOCK-src`, and sanitizes WSL script line endings. |
| [`2_build_assets_wsl.sh`](./2_build_assets_wsl.sh) | **Step 2 (WSL):** Clones pinned `Zagitta/gpu-unlock`, verifies/installs package dependencies (`make`, `zstd`, `python3-zstandard`), builds and copies the 5 required `.bin` assets into `Windows-GPU-UNLOCK-src/assets/`. |
| [`3_configure_and_build.ps1`](./3_configure_and_build.ps1) | **Step 3:** Binds the target partition and Windows ESP GUID, dynamically searches compiler paths, and builds/registers the EFI payload for pre-reviewed machine profiles. |
| [`4_enable_auto_or_recover.ps1`](./4_enable_auto_or_recover.ps1) | **Step 4:** Post-verification utility to enable automatic priority boot (`-EnableAutomatic -ConfirmedSuccess`) or perform instant 1-click restoration to factory default Windows boot order (`-RestoreWindowsFirst`). |
| [`5_make_local_profile.ps1`](./5_make_local_profile.ps1) | **Step 5 (Custom Profiling):** Generates and stages a read-only generic EFI diagnostic probe onto a FAT32 USB drive to capture cold-boot hardware fingerprints. |
| [`6_stage_unlock_to_usb.ps1`](./6_stage_unlock_to_usb.ps1) | **Step 6 (Stage Payload):** Runs local host tests against the captured fingerprints, generates `profile-local.h`, builds the full unlock EFI binaries, and stages them directly to the USB drive with `-StageUnlock`. |
| [`push_to_github.ps1`](./push_to_github.ps1) | *(Optional)* Helper script to initialize git and push to GitHub (excluded from tracking). |
| [`README_KR.md`](./README_KR.md) | Comprehensive step-by-step documentation in Korean. |

---

## 🛠️ Prerequisites

1. **Disable Secure Boot**: In your motherboard BIOS/UEFI settings, turn **Secure Boot OFF (Disabled)**. Custom EFI binaries cannot be verified by standard Microsoft Secure Boot keys.
2. **Turn off BitLocker**: Ensure your `C:` drive is fully decrypted (`VolumeStatus: FullyDecrypted`) to prevent BitLocker recovery prompts.
3. **Dedicated USB Flash Drive**:
   - A standard USB 2.0/3.0 stick (1GB to 4GB FAT32 partition).
   - Format with FAT32:
     ```powershell
     # Example for Disk 6 / 4GB partition
     $disk = Get-Disk (Get-Partition -DriveLetter I).DiskNumber
     $disk | Clear-Disk -RemoveData -Confirm:$false
     $part = New-Partition -DiskNumber $disk.Number -Size 4GB -AssignDriveLetter
     Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel "GPU_UNLOCK" -Force
     ```
4. **Required Tools on Windows**:
   - Install LLVM:
     ```powershell
     winget install LLVM.LLVM
     ```
   - Git for Windows, Python 3.10+, and Visual Studio (Community or Build Tools with C++ workload).

---

## 📖 Step-by-Step Workflow

### Step 1: Check Environment & Clone Upstream
Open PowerShell as **Administrator** and run:
```powershell
cd C:\Users\<username>\misc\261027_Windows-GPU-UNLOCK
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\1_fetch_repo_and_check.ps1
```

### Step 2: Extract Firmware Assets via WSL
In the same PowerShell prompt:
```powershell
wsl bash ./2_build_assets_wsl.sh
```
This extracts:
- `booter_load_ga102.bin`
- `v67-ga102-610.43.03.bin`
- `gsp_ga10x.bin`
- `gsp_boot_ga102.bin`
- `gsp_boot_desc_ga102.bin`

### Step 3: Local Hardware Profile Generation (For Custom Motherboards)
If your motherboard/GPU combination is not in `machine-profile.h`:

1. **Stage Diagnostic Probe**:
   ```powershell
   .\5_make_local_profile.ps1 -TargetDrive I
   ```
2. **Collect 2 Cold-Boot Captures**:
   - **Shut down** the PC completely (Do not use "Restart").
   - Power on, press your motherboard boot menu key (ASUS `F8`, MSI `F11`, Gigabyte `F12`), and select the USB drive.
   - It captures data in 1-2 seconds and boots into Windows.
   - **Shut down** again and boot from USB a **second time**.
3. **Compile & Stage Unlock Payload**:
   After booting into Windows the second time:
   ```powershell
   .\6_stage_unlock_to_usb.ps1
   ```
   This compiles `profile-local.h`, runs all 20 host validation checks, builds the release payload, and copies `BOOTX64.EFI`, `UNLOCK-HEADLESS.EFI`, and `ASSETS` to your USB drive.

---

## ⚡ Booting with Unlock

1. **Shut down** your PC.
2. Power on and press your boot menu key (e.g. `F8`/`F11`/`F12`).
3. Select your **USB drive (UEFI)**.
4. During boot:
   - The screen will momentarily go dark/blank for 2-3 seconds as the PCIe FLR resets the GPU with full speed selectors active.
   - Control is handed directly to Windows Boot Manager.
5. In Windows, verify that your AI workloads (ComfyUI Flux/Wan 2.1 BF16, PyTorch GEMM) run with full tensor compute throughput!

---

## 🛟 How to Revert (100% Non-Permanent)

This method does **not** flash your GPU's VBIOS or modify Windows driver binaries:
- **One-time bypass**: Press `Esc` within the first 5 seconds of boot to skip unlock and proceed with normal boot.
- **Return to stock**: Boot into Windows normally by selecting **Windows Boot Manager** in the BIOS boot menu, or simply unplug the USB drive. On a cold restart, GPU registers revert completely to factory default settings.

---

## ⚖️ License & Acknowledgments

- Based on research and source code from [`impacifist/Windows-GPU-UNLOCK`](https://github.com/impacifist/Windows-GPU-UNLOCK) and [`Zagitta/gpu-unlock`](https://github.com/Zagitta/gpu-unlock).
- Licensed under GPL-2.0.
