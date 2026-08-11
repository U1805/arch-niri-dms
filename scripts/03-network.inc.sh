#!/bin/bash

# ==============================================================================
# 03-driver.sh 的内部组件：配置网络后端
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

section "Optional" "Configure the network backend (iwd)"

# 配置前检查 NetworkManager。
if pacman -Qi networkmanager &> /dev/null; then
    log "NetworkManager is installed."
    
    log "Set the NetworkManager backend to iwd."
    exe pacman -S --noconfirm --needed iwd impala
    exe systemctl enable iwd
    # 创建配置目录。
    if [ ! -d /etc/NetworkManager/conf.d ]; then
        mkdir -p /etc/NetworkManager/conf.d
    fi
    if [ -f /etc/NetworkManager/conf.d/wifi_backend.conf ];then
        rm /etc/NetworkManager/conf.d/wifi_backend.conf
    fi
    if [ ! -f /etc/NetworkManager/conf.d/iwd.conf  ];then
        echo -e "[device]\nwifi.backend=iwd" >> /etc/NetworkManager/conf.d/iwd.conf
        rm -rfv /etc/NetworkManager/system-connections/*
    fi
    log "Do not restart NetworkManager now. The configuration applies after restart."
    success "The network backend is iwd."
else
    log "NetworkManager is not installed. Skip iwd configuration."
fi
