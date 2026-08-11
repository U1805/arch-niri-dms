#!/bin/bash

# ==============================================================================
# 05a-dms-niri.sh - 配置 Shorin DMS 和 Niri 核心组件
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
  source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh is not available in $SCRIPT_DIR."
  exit 1
fi

check_root
VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

# ------------------------------------------------------------------------------
# 确定目标用户。
# ------------------------------------------------------------------------------
log "Identify the target user."
detect_target_user

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
  error "The target user is not valid, or the home directory does not exist."
  exit 1
fi

info_kv "Target user" "$TARGET_USER"

if ! enable_temporary_sudo; then
  exit 1
fi

critical_failure_handler() {
  local failed_reason="$1"
  trap - ERR
  echo -e "\n\033[0;31m[FATAL ERROR] $failed_reason\033[0m\n"
  exit 1
}
trap 'critical_failure_handler "Script Error at Line $LINENO"' ERR

# ==============================================================================
# 安装官方仓库中的核心依赖项。
# ==============================================================================
section "Shorin DMS" "Install official core dependencies"

# dms-shell-niri 从官方仓库引入 dms-shell、quickshell 和 dgop。
# 显式列出其余运行依赖项，以便审查。
OFFICIAL_DEPS=(
  dms-shell-niri xdg-desktop-portal-gnome xwayland-satellite
  libnotify wl-clipboard cliphist cava
  cups-pk-helper matugen qt6-multimedia qt6ct wtype swayosd
)

log "Add official dependencies to the verification list."
printf "%s\n" "${OFFICIAL_DEPS[@]}" >>"$VERIFY_LIST"

log "Install core dependencies with pacman."
if ! pacman -S --noconfirm --needed "${OFFICIAL_DEPS[@]}"; then
  critical_failure_handler "The official Shorin DMS dependencies failed to install."
fi

log "Enable the SwayOSD libinput backend."
if ! systemctl enable --now swayosd-libinput-backend.service; then
  critical_failure_handler "The SwayOSD libinput backend failed to start."
fi

# ==============================================================================
# 安装其他仓库依赖项。
# ==============================================================================
section "Shorin DMS" "Install additional dependencies"

ADDITIONAL_DEPS=(dsearch-bin)

log "Add additional dependencies to the verification list."
printf "%s\n" "${ADDITIONAL_DEPS[@]}" >>"$VERIFY_LIST"

log "Install additional dependencies with paru."
PARU_MAKEPKG_ARGS=()
if [[ -x "${SHORIN_MAKEPKG_WRAPPER:-}" ]]; then
  PARU_MAKEPKG_ARGS+=(--makepkg "$SHORIN_MAKEPKG_WRAPPER")
fi
if ! as_user paru "${PARU_MAKEPKG_ARGS[@]}" -S --noconfirm --needed "${ADDITIONAL_DEPS[@]}"; then
  critical_failure_handler "The additional Shorin DMS dependencies failed to install."
fi

# ==============================================================================
# 安装 DMS Greeter。
# ==============================================================================
section "Shorin DMS" "Install and configure DMS Greeter"

log "Install greetd from the official repository."
if ! pacman -S --noconfirm --needed greetd; then
  critical_failure_handler "greetd failed to install."
fi

log "Install and synchronize DMS Greeter."
if ! as_user dms greeter install --yes || \
   ! as_user dms greeter sync --yes || \
   ! as_user dms greeter status; then
  critical_failure_handler "DMS Greeter installation or verification failed"
fi

success "The Shorin DMS Niri core is installed."
