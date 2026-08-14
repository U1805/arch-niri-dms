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
  for package in "${ADDITIONAL_DEPS[@]}"; do
    rm -rf -- "$HOME_DIR/.cache/paru/clone/$package" "$HOME_DIR/.cache/paru/aur/$package"
  done
  critical_failure_handler "The additional Shorin DMS dependencies failed to install."
fi

# ==============================================================================
# 安装 DMS Greeter。
# ==============================================================================
section "Shorin DMS" "Install and configure DMS Greeter"

GREETER_PACKAGE="greetd-dms-greeter-bin"
log "Install the fixed-release DMS Greeter binary package from AUR with paru."
if ! as_user paru "${PARU_MAKEPKG_ARGS[@]}" -S --noconfirm --needed "$GREETER_PACKAGE"; then
  rm -rf -- "$HOME_DIR/.cache/paru/clone/$GREETER_PACKAGE" "$HOME_DIR/.cache/paru/aur/$GREETER_PACKAGE"
  critical_failure_handler "The DMS Greeter AUR package failed to install."
fi
printf "%s\n" "$GREETER_PACKAGE" >>"$VERIFY_LIST"

# AUR 二进制包提供 dms-greeter 启动器和 QML 文件；官方 dms-shell 提供管理命令。
# 软件包已经由 paru 安装，因此不要再运行 `dms greeter install` 触发发行版安装检测。
if ! command -v dms-greeter >/dev/null 2>&1; then
  critical_failure_handler "The dms-greeter command is missing after package installation."
fi
if [[ ! -d /usr/share/quickshell/dms-greeter ]]; then
  critical_failure_handler "The packaged DMS Greeter QML directory is missing."
fi
if ! command -v dms >/dev/null 2>&1; then
  critical_failure_handler "The dms management command is missing."
fi

log "Enable, synchronize, and verify DMS Greeter."
if ! as_user env HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
     dms greeter enable --yes || \
   ! as_user env HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
     dms greeter sync --yes || \
   ! as_user env HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
     dms greeter status; then
  critical_failure_handler "DMS Greeter enable, synchronization, or verification failed."
fi

success "The Shorin DMS Niri core is installed."
