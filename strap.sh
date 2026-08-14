#!/usr/bin/env bash

# ==============================================================================
# Shorin Arch 安装入口
# 1. 检查操作系统和处理器架构。
# 2. 使用 root 或 sudo 执行特权命令。
# 3. 引导统一 GitHub 下载 wrapper，并下载仓库。
# 4. 启动 install.sh。
# ==============================================================================

# 如果命令、变量或管道出错，立即退出。
set -euo pipefail

# 终端颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # 重置颜色

# 检查运行环境

# 检查 Linux 内核。
if [ "$(uname -s)" != "Linux" ]; then
    printf "%bError: This installer supports Linux only.%b\n" "$RED" "$NC"
    exit 1
fi

# 检查处理器架构。
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    printf "%bError: The %s architecture is not supported.%b\n" "$RED" "$ARCH" "$NC"
    printf "This installer supports x86_64 only.\n"
    exit 1
fi
ARCH_NAME="amd64"

# 如果当前用户不是 root，则使用 sudo。
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        if ! command -v sudo >/dev/null 2>&1; then
            printf "%bError: sudo is not available. Run this script as root.%b\n" "$RED" "$NC"
            exit 1
        fi
        sudo "$@"
    fi
}

# 下载配置
TARGET_BRANCH="${BRANCH:-main}"
TARBALL_URL="https://github.com/U1805/arch-niri-dms/archive/refs/heads/${TARGET_BRANCH}.tar.gz"
TARGET_DIR="/tmp/arch-niri-dms"
BOOTSTRAP_WRAPPER="/tmp/arch-niri-dms-curl-github-wrapper.sh"
ARCHIVE_PATH="/tmp/arch-niri-dms-${TARGET_BRANCH}.tar.gz"

cleanup_download() {
    if [ -d "$TARGET_DIR" ]; then
        run_as_root rm -rf -- "$TARGET_DIR"
    fi
    rm -f -- "$BOOTSTRAP_WRAPPER" "$ARCHIVE_PATH"
}
trap cleanup_download EXIT
trap 'exit 130' INT TERM

printf "%bInstall branch: %s. Architecture: %s.%b\n" "$BLUE" "$TARGET_BRANCH" "$ARCH_NAME" "$NC"

# 下载仓库前，仅检查入口脚本所需的命令。install.sh 负责所有软件包操作。
MISSING_BOOTSTRAP_CMDS=()
for cmd in curl tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_BOOTSTRAP_CMDS+=("$cmd")
    fi
done

if [ ${#MISSING_BOOTSTRAP_CMDS[@]} -gt 0 ]; then
    printf "%bError: Required commands are not available: %s.%b\n" "$RED" "${MISSING_BOOTSTRAP_CMDS[*]}" "$NC"
    printf "Install them first: sudo pacman -S --needed %s\n" "${MISSING_BOOTSTRAP_CMDS[*]}"
    exit 1
fi

# `strap.sh` 可能通过网络独立执行，此时仓库内 wrapper 尚不可用。
# 这里只负责按统一顺序引导取得 wrapper；后续 GitHub 文件均由 wrapper 路由。
WRAPPER_URL="https://raw.githubusercontent.com/U1805/arch-niri-dms/refs/heads/${TARGET_BRANCH}/github-wrapper/curl-github-wrapper.sh"
WRAPPER_READY=false
for prefix in "" "https://gh-proxy.com/" "https://gh-proxy.org/"; do
    rm -f -- "$BOOTSTRAP_WRAPPER"
    printf "Get the GitHub download wrapper through %s.\n" "${prefix:-a direct connection}"
    if curl -q -fL --retry 0 --connect-timeout 15 \
        --speed-limit 40960 --speed-time 20 \
        -o "$BOOTSTRAP_WRAPPER" "${prefix}${WRAPPER_URL}" && \
       bash -n "$BOOTSTRAP_WRAPPER"; then
        chmod 0755 "$BOOTSTRAP_WRAPPER"
        WRAPPER_READY=true
        break
    fi
done

if [ "$WRAPPER_READY" != true ]; then
    printf "%bError: The GitHub download wrapper could not be downloaded.%b\n" "$RED" "$NC"
    exit 1
fi

# 重新创建下载目录。
if [ -d "$TARGET_DIR" ]; then
    run_as_root rm -rf "$TARGET_DIR"
fi
mkdir -p "$TARGET_DIR"

# 下载并解压仓库。curl 显示传输进度。
printf "Download and extract the repository to %s.\n" "$TARGET_DIR"

if ! "$BOOTSTRAP_WRAPPER" "$ARCHIVE_PATH" "$TARBALL_URL"; then
    printf "%bError: The %s branch download failed through all routes.%b\n" "$RED" "$TARGET_BRANCH" "$NC"
    exit 1
fi
if ! tar -xzf "$ARCHIVE_PATH" -C "$TARGET_DIR" --strip-components=1; then
    printf "%bError: The downloaded repository archive is invalid.%b\n" "$RED" "$NC"
    exit 1
fi
run_as_root chmod 755 "$TARGET_DIR"
printf "%b\nThe repository download is complete.%b\n" "$GREEN" "$NC"

# 启动安装程序。
cd "$TARGET_DIR"
printf "Start the installer.\n"
run_as_root bash install.sh < /dev/tty
