#!/bin/bash

# ==============================================================================
# 02-fonts.sh - 配置 ArchLinuxCN、字体和 AUR 构建环境
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

log "Start phase 1: Configure the base system."

# ------------------------------------------------------------------------------
# 配置 ArchLinuxCN 仓库。
# ------------------------------------------------------------------------------
section "Step 1/3" "Configure the ArchLinuxCN repository"

if grep -q "\[archlinuxcn\]" /etc/pacman.conf; then
    success "The ArchLinuxCN repository is configured."
else
    log "Add ArchLinuxCN mirrors to pacman.conf."

    # 使用时区选择镜像。此方法适用于 arch-chroot 和已安装的系统。
    LOCAL_TZ=""
    if [ -L /etc/localtime ]; then
        LOCAL_TZ=$(readlink -f /etc/localtime)
    fi

    echo "" >> /etc/pacman.conf
    echo "[archlinuxcn]" >> /etc/pacman.conf

    if [[ "$LOCAL_TZ" == *"Asia/Shanghai"* ]]; then
        log "The time zone is Asia/Shanghai. Add China mirrors."
        cat <<EOT >> /etc/pacman.conf
Server = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.hit.edu.cn/archlinuxcn/\$arch
Server = https://repo.huaweicloud.com/archlinuxcn/\$arch
EOT
    else
        log "The time zone is not Asia/Shanghai. Add the global mirror first."
        cat <<EOT >> /etc/pacman.conf
Server = https://repo.archlinuxcn.org/\$arch
Server = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch
Server = https://mirrors.hit.edu.cn/archlinuxcn/\$arch
Server = https://repo.huaweicloud.com/archlinuxcn/\$arch
EOT
    fi
    success "ArchLinuxCN mirrors are configured for the time zone."
fi

log "Install archlinuxcn-keyring."
exe pacman -Syu --noconfirm archlinuxcn-keyring
success "ArchLinuxCN is configured."

# ------------------------------------------------------------------------------
# 安装基础字体。
# ------------------------------------------------------------------------------
section "Step 2/3" "Install base fonts"

log "Install base fonts from the official repositories."
exe pacman -S --noconfirm --needed ttf-liberation noto-fonts noto-fonts-cjk noto-fonts-emoji otf-font-awesome ttf-jetbrains-mono-nerd

log "Install Maple Mono NF from ArchLinuxCN."
exe pacman -S --noconfirm --needed ttf-maplemono-nf
log "The base fonts are installed."

log "Install terminus-font."
exe pacman -S --noconfirm --needed terminus-font

log "Set the font for the current console."
exe setfont ter-v28n

log "Set the vconsole font."
if [ -f /etc/vconsole.conf ] && grep -q "^FONT=" /etc/vconsole.conf; then
    exe sed -i 's/^FONT=.*/FONT=ter-v28n/' /etc/vconsole.conf
else
    echo "FONT=ter-v28n" >> /etc/vconsole.conf
fi

log "Restart systemd-vconsole-setup."
exe systemctl restart systemd-vconsole-setup

success "The TTY font is ter-v28n."
# ------------------------------------------------------------------------------
# 安装 AUR 助手。
# ------------------------------------------------------------------------------
section "Step 3/3" "Install the AUR helper"

log "Install paru."
exe pacman -S --noconfirm --needed base-devel paru
success "paru is installed."


# ------------------------------------------------------------------------------

log "Module 02 is complete."
