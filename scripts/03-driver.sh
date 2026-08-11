#!/bin/bash

# ==============================================================================
# 03-driver.sh - 配置网络、硬件、GPU、音频和平台驱动
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

# 先配置 NetworkManager 的 iwd 后端，再配置其他硬件。
if ! bash "$SCRIPT_DIR/03-network.inc.sh"; then
    error "Network backend configuration failed."
    exit 1
fi

log "Start phase 2: Install required software and drivers."

# ------------------------------------------------------------------------------
# 1. Audio & Video
# ------------------------------------------------------------------------------
section "Step 1/7" "Configure audio and video"

log "Install firmware."
exe pacman -S --noconfirm --needed sof-firmware alsa-ucm-conf alsa-firmware

log "Install PipeWire components."
exe pacman -S --noconfirm --needed pipewire lib32-pipewire wireplumber pipewire-pulse pipewire-alsa pipewire-jack

exe systemctl --global enable pipewire pipewire-pulse wireplumber
success "Audio is configured."

# ------------------------------------------------------------------------------
# 2. Locale
# ------------------------------------------------------------------------------
section "Step 2/7" "Configure locales"

# 标记是否需要重新生成
NEED_GENERATE=false

# --- 1. 检测 en_US.UTF-8 ---
if locale -a | grep -iq "en_US.utf8"; then
    success "The en_US.UTF-8 locale is active."
else
    log "Enable en_US.UTF-8."
    # 使用 sed 取消注释
    sed -i 's/^#\s*en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    NEED_GENERATE=true
fi

# --- 2. 检测 zh_CN.UTF-8 ---
if locale -a | grep -iq "zh_CN.utf8"; then
    success "The zh_CN.UTF-8 locale is active."
else
    log "Enable zh_CN.UTF-8."
    # 使用 sed 取消注释
    sed -i 's/^#\s*zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
    NEED_GENERATE=true
fi

# --- 3. 如果有修改，统一执行生成 ---
if [ "$NEED_GENERATE" = true ]; then
    log "Generate locales."
    if exe locale-gen; then
        success "The locales are generated."
    else
        error "Locale generation failed."
    fi
else
    success "The locales are current."
fi

# ------------------------------------------------------------------------------
# 3. Input Method
# ------------------------------------------------------------------------------
section "Step 3/7" "Install the input method (Fcitx5)"

exe pacman -S --noconfirm --needed fcitx5-im fcitx5-rime

success "Fcitx5 is installed."

# ------------------------------------------------------------------------------
# 4. Bluetooth (Smart Detection)
# ------------------------------------------------------------------------------
section "Step 4/7" "Configure Bluetooth"

# 安装硬件检测工具。
log "Detect Bluetooth hardware."
exe pacman -S --noconfirm --needed usbutils pciutils

BT_FOUND=false

# 检查 USB 设备。
if lsusb | grep -qi "bluetooth"; then BT_FOUND=true; fi
# 检查 PCI 设备。
if lspci | grep -qi "bluetooth"; then BT_FOUND=true; fi
# 检查 RFKill 状态。
if rfkill list bluetooth >/dev/null 2>&1; then BT_FOUND=true; fi

if [ "$BT_FOUND" = true ]; then
    info_kv "Bluetooth" "Detected"
    
    log "Install BlueZ."
    exe pacman -S --noconfirm --needed bluez bluetui
    
    exe systemctl enable --now bluetooth
    success "The Bluetooth service is enabled."
else
    info_kv "Bluetooth" "Not detected"
    warn "No Bluetooth device was detected. Skip Bluetooth components."
fi

# ------------------------------------------------------------------------------
# 5. Power
# ------------------------------------------------------------------------------
section "Step 5/7" "Configure power management"

exe pacman -S --noconfirm --needed power-profiles-daemon
exe systemctl enable --now power-profiles-daemon
success "The power profile service is enabled."

# ------------------------------------------------------------------------------
# 6. GPU Drivers
# ------------------------------------------------------------------------------
section "Step 6/7" "Install GPU drivers"

if ! bash "$SCRIPT_DIR/03-gpu.inc.sh"; then
    error "GPU driver installation failed. Stop before the Flatpak and desktop installation."
    exit 1
fi

# ------------------------------------------------------------------------------
# 7. Flatpak
# ------------------------------------------------------------------------------
section "Step 7/7" "Configure Flatpak"

exe pacman -S --noconfirm --needed flatpak
exe flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

CURRENT_TZ=$(readlink -f /etc/localtime)
if [[ "$CURRENT_TZ" == *"Shanghai"* ]] || [ "$CN_MIRROR" == "1" ] || [ "$DEBUG" == "1" ]; then
    info_kv "Flathub source" "SJTU mirror"
    log "Set the Flathub source to the SJTU mirror."
    exe flatpak remote-modify flathub --url="https://mirror.sjtu.edu.cn/flathub"
else
    info_kv "Flathub source" "Official source"
    log "Use the official Flathub source."
    exe flatpak remote-modify flathub --url="https://dl.flathub.org/repo/"
fi

log "Module 03 is complete."
