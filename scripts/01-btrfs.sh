#!/bin/bash

# ==============================================================================
# 01-btrfs.sh - 配置根目录和主目录快照
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

section "Phase 0" "Configure system snapshots"

# ------------------------------------------------------------------------------
# 检查根文件系统。
# ------------------------------------------------------------------------------
log "Check the root file system."
ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

if [ "$ROOT_FSTYPE" != "btrfs" ]; then
    warn "The root file system is $ROOT_FSTYPE, not Btrfs."
    log "Skip Btrfs snapshot configuration."
    exit 0
fi

log "The root file system is Btrfs. Configure pacman transaction snapshots."

# ------------------------------------------------------------------------------
# 配置根目录和主目录。
# ------------------------------------------------------------------------------
log "Install Snapper and the pacman snapshot hooks."
exe pacman -Syu --noconfirm --needed snapper snap-pac

log "Configure Snapper for the root file system."
if ! snapper list-configs | grep -q "^root "; then
    if [ -d "/.snapshots" ]; then
        exe_silent umount /.snapshots
        exe_silent rm -rf /.snapshots
    fi
    if exe snapper -c root create-config /; then
        success "The Snapper root configuration is created."
    fi
fi

# 保留软件包事务快照。时间线快照独立记录系统状态。
if snapper -c root get-config &>/dev/null; then
    exe snapper -c root set-config ALLOW_GROUPS="wheel" NUMBER_LIMIT="10" NUMBER_MIN_AGE="0" NUMBER_LIMIT_IMPORTANT="5" TIMELINE_CREATE="yes" TIMELINE_CLEANUP="yes" TIMELINE_MIN_AGE="3600" TIMELINE_LIMIT_HOURLY="10" TIMELINE_LIMIT_DAILY="10" TIMELINE_LIMIT_WEEKLY="0" TIMELINE_LIMIT_MONTHLY="10" TIMELINE_LIMIT_QUARTERLY="0" TIMELINE_LIMIT_YEARLY="10"
fi

HOME_FSTYPE=$(findmnt -n -o FSTYPE /home 2>/dev/null || true)
if [ "$HOME_FSTYPE" = "btrfs" ]; then
    log "Configure Snapper for /home."
    if ! snapper list-configs | grep -q "^home "; then
        if [ -e "/home/.snapshots" ]; then
            error "/home/.snapshots exists, but the Snapper home configuration does not. Check the current snapshots."
            exit 1
        fi
        if exe snapper -c home create-config /home; then
            success "The Snapper home configuration is created."
        fi
    fi

    if snapper -c home get-config &>/dev/null; then
        exe snapper -c home set-config ALLOW_GROUPS="wheel" NUMBER_LIMIT="10" NUMBER_MIN_AGE="0" NUMBER_LIMIT_IMPORTANT="5" TIMELINE_CREATE="yes" TIMELINE_CLEANUP="yes" TIMELINE_MIN_AGE="3600" TIMELINE_LIMIT_HOURLY="10" TIMELINE_LIMIT_DAILY="10" TIMELINE_LIMIT_WEEKLY="0" TIMELINE_LIMIT_MONTHLY="10" TIMELINE_LIMIT_QUARTERLY="0" TIMELINE_LIMIT_YEARLY="10"
    fi
else
    warn "/home is not on Btrfs. Keep only the Snapper root configuration."
fi

# 清理和时间线定时器适用于所有 Snapper 配置。
# snap-pac 独立为软件包事务创建根目录的前置和后置快照。
exe systemctl enable snapper-cleanup.timer
exe systemctl enable snapper-timeline.timer

# ------------------------------------------------------------------------------
# 配置 GRUB 快照入口。
# ------------------------------------------------------------------------------
section "Recovery" "Connect GRUB to Btrfs snapshots"

if [ -f "/etc/default/grub" ] && command -v grub-mkconfig >/dev/null 2>&1; then
    if [ ! -d /efi/grub ]; then
        error "The GRUB directory on the ESP is not available: /efi/grub."
        exit 1
    fi
    if [ ! -L /boot/grub ] || [ "$(readlink -f /boot/grub)" != "$(readlink -f /efi/grub)" ]; then
        error "/boot/grub does not point to /efi/grub. Repair the link before you continue."
        exit 1
    fi

    log "Install the GRUB snapshot components."
    exe pacman -S --noconfirm --needed grub-btrfs inotify-tools

    exe systemctl enable --now grub-btrfsd
fi

log "Module 01 is complete. Snapper transaction snapshots and GRUB entries are configured."
