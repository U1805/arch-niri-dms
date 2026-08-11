#!/bin/bash

# ==============================================================================
# 04-dualboot-fix.sh - 配置 Windows 双系统和用户
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

check_root

run_user_configuration() {
    bash "$SCRIPT_DIR/04-user.inc.sh"
}

# 检查 GRUB。
if ! command -v grub-mkconfig &>/dev/null || [ ! -f "/etc/default/grub" ]; then
    warn "GRUB was not detected. Skip dual-boot configuration."
    run_user_configuration
    exit $?
fi

# 辅助函数

# 设置 GRUB 键值对。
set_grub_value() {
    local key="$1"
    local value="$2"
    local conf_file="/etc/default/grub"
    
    local escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed 's,[\/&],\\&,g')

    if grep -q -E "^#\s*$key=" "$conf_file"; then
        exe sed -i -E "s,^#\s*$key=.*,$key=\"$escaped_value\"," "$conf_file"
    elif grep -q -E "^$key=" "$conf_file"; then
        exe sed -i -E "s,^$key=.*,$key=\"$escaped_value\"," "$conf_file"
    else
        log "Add the GRUB key: $key."
        echo "$key=\"$escaped_value\"" >> "$conf_file"
    fi
}

# 主流程

section "Phase 2A" "Configure Windows dual boot"

# ------------------------------------------------------------------------------
# 检测 Windows。
# ------------------------------------------------------------------------------
section "Step 1/2" "Detect Windows"

log "Install os-prober."
exe pacman -S --noconfirm --needed os-prober

log "Scan for Windows."
WINDOWS_DETECTED=$(os-prober | grep -qi "windows" && echo "true" || echo "false")

if [ "$WINDOWS_DETECTED" != "true" ]; then
    log "os-prober did not detect Windows."
    log "Skip dual-boot configuration."
    run_user_configuration
    exit $?
fi

success "Windows was detected."

log "Install exfat-utils for Windows partitions."
exe pacman -S --noconfirm --needed exfat-utils

# 检查现有配置。
OS_PROBER_CONFIGURED=$(grep -q -E '^\s*GRUB_DISABLE_OS_PROBER\s*=\s*(false|"false")' /etc/default/grub && echo "true" || echo "false")

if [ "$OS_PROBER_CONFIGURED" == "true" ]; then
    log "The dual-boot settings are configured."
    echo ""
    echo -e "   ${H_YELLOW}Dual boot is configured.${NC}"
    echo ""
fi

# ------------------------------------------------------------------------------
# 配置 GRUB 双系统菜单。
# ------------------------------------------------------------------------------
section "Step 2/2" "Enable OS Prober"

log "Enable OS Prober."
set_grub_value "GRUB_DISABLE_OS_PROBER" "false"

success "The dual-boot settings are updated."

log "Dual-boot configuration is complete. Continue with user configuration."

if ! run_user_configuration; then
    error "User configuration failed."
    exit 1
fi

log "Module 04 is complete."
