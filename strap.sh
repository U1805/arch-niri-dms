#!/usr/bin/env bash

# ==============================================================================
# Shorin Arch 安装入口
# 1. 检查操作系统和处理器架构。
# 2. 使用 root 或 sudo 执行特权命令。
# 3. 检查下载命令，并通过 GitHub 代理下载仓库。
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
TARBALL_URL="https://gh-proxy.org/https://github.com/U1805/arch-niri-dms/archive/refs/heads/${TARGET_BRANCH}.tar.gz"
TARGET_DIR="/tmp/arch-niri-dms"

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

# 重新创建下载目录。
if [ -d "$TARGET_DIR" ]; then
    run_as_root rm -rf "$TARGET_DIR"
fi
mkdir -p "$TARGET_DIR"

# 下载并解压仓库。curl 显示传输进度。
printf "Download and extract the repository to %s.\n" "$TARGET_DIR"

for attempt in 1 2 3; do
    if curl --fail --location "$TARBALL_URL" | tar -xz -C "$TARGET_DIR" --strip-components=1; then
        run_as_root chmod 755 "$TARGET_DIR"
        printf "%b\nThe repository download is complete.%b\n" "$GREEN" "$NC"
        break
    fi
    
    if [ "$attempt" -eq 3 ]; then
        printf "%bError: The %s branch download failed after three attempts. Check the network connection.%b\n" "$RED" "$TARGET_BRANCH" "$NC"
        exit 1
    fi
    
    printf "%bWarning: Download attempt %d of 3 failed. Retry in three seconds.%b\n" "$RED" "$attempt" "$NC"
    sleep 3
    run_as_root rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
done

# 启动安装程序。
cd "$TARGET_DIR"
printf "Start the installer.\n"
run_as_root bash install.sh < /dev/tty
