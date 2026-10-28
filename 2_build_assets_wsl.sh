#!/usr/bin/env bash
# ==============================================================================
# 2단계: WSL(Linux) 환경에서 Zagitta/gpu-unlock 펌웨어 에셋(.bin 5종) 추출 스크립트
# [Grok 4.7 패치]: 필수 패키지(make, zstd, python3-pip) 자동 점검 및 설치 안내 포함
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SRC_DIR="${SCRIPT_DIR}/Windows-GPU-UNLOCK-src"
TARGET_ASSETS_DIR="${REPO_SRC_DIR}/assets"
FW_WORK_DIR="${SCRIPT_DIR}/gpu-unlock-firmware-source"
PINNED_COMMIT="0ebdb1c6308b6a2072be5bf04513472942541956"

echo "=========================================================="
echo " [WSL] GPU-UNLOCK 펌웨어 에셋 추출 파이프라인"
echo "=========================================================="

# 1. 필수 리눅스 도구 점검 (make, git, tar, zstd)
MISSING_TOOLS=()
for tool in make git tar zstd; do
    if ! command -v "${tool}" &>/dev/null; then
        MISSING_TOOLS+=("${tool}")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "[경고] WSL 내에 다음 필수 도구가 없습니다: ${MISSING_TOOLS[*]}"
    echo "       자동 설치를 위해 apt-get을 실행합니다 (sudo 패스워드가 필요할 수 있습니다)..."
    sudo apt-get update -qq && sudo apt-get install -y -qq make git tar zstd python3 python3-pip python3-zstandard
fi

mkdir -p "${TARGET_ASSETS_DIR}"

# 2. Python 환경 및 zstandard 라이브러리 확인
if command -v python3.14 &>/dev/null; then
    PY_BIN="python3.14"
elif command -v python3 &>/dev/null; then
    PY_BIN="python3"
    # zstandard 모듈 확인 (Ubuntu 24.04 PEP 668 대비)
    if ! "${PY_BIN}" -c "import zstandard" &>/dev/null; then
        echo "[참고] Python zstandard 모듈 설치 시도 (pip/apt)..."
        sudo apt-get install -y -qq python3-zstandard 2>/dev/null || \
        "${PY_BIN}" -m pip install --upgrade zstandard --break-system-packages 2>/dev/null || \
        "${PY_BIN}" -m pip install --upgrade zstandard 2>/dev/null || true
    fi
else
    echo "[오류] python3 인터프리터를 찾을 수 없습니다. 'sudo apt install python3'을 실행하세요."
    exit 1
fi

echo "[확인] Python: $("${PY_BIN}" --version)"

# 3. Upstream 소스 클론 및 체크아웃
if [ ! -d "${FW_WORK_DIR}" ]; then
    echo "[1/3] Zagitta/gpu-unlock 클론 중..."
    git clone https://github.com/Zagitta/gpu-unlock.git "${FW_WORK_DIR}"
fi

cd "${FW_WORK_DIR}"
echo "[2/3] 검증된 커밋(${PINNED_COMMIT}) 고정 체크아웃..."
git fetch --all
git checkout --detach "${PINNED_COMMIT}"

echo "[3/3] 펌웨어 바이너리 추출 및 빌드 중 (make inputs firmware)..."
make inputs firmware PYTHON="${PY_BIN}" INPUTS="${PWD}/inputs" ASSETS="${PWD}/assets"

REQUIRED_BINS=(
    "booter_load_ga102.bin"
    "v67-ga102-610.43.03.bin"
    "gsp_ga10x.bin"
    "gsp_boot_ga102.bin"
    "gsp_boot_desc_ga102.bin"
)

echo "=========================================================="
echo " 추출된 5종 에셋 검증 및 복사"
echo "=========================================================="
for bin_file in "${REQUIRED_BINS[@]}"; do
    if [ -f "${PWD}/assets/${bin_file}" ]; then
        cp -f "${PWD}/assets/${bin_file}" "${TARGET_ASSETS_DIR}/${bin_file}"
        echo " [OK] ${bin_file}"
    else
        echo " [FAIL] ${bin_file} 파일이 생성되지 않았습니다."
        exit 1
    fi
done

echo "=========================================================="
echo " 에셋 추출 성공: ${TARGET_ASSETS_DIR}"
echo " 관리자 PowerShell에서 3_configure_and_build.ps1 을 진행하세요."
echo "=========================================================="
