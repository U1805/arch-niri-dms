#!/bin/bash

# ==============================================================================
# 04h-shorindms-quickshell.sh - Shorin DMS / Niri Core Setup
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
  source "$SCRIPT_DIR/00-utils.sh"
else
  echo "Error: 00-utils.sh not found in $SCRIPT_DIR."
  exit 1
fi

check_root
VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

# ------------------------------------------------------------------------------
# Identify User & DM Check
# ------------------------------------------------------------------------------
log "Identifying target user..."
detect_target_user

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
  error "Target user invalid or home directory does not exist."
  exit 1
fi

info_kv "Target User" "$TARGET_USER"
check_dm_conflict
log "DM Check result $SKIP_DM"

# ------------------------------------------------------------------------------
# Temporary Sudo Privileges
# ------------------------------------------------------------------------------
log "Granting temporary sudo privileges..."
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

cleanup_sudo() {
  if [[ -f "$SUDO_TEMP_FILE" ]]; then
    rm -f "$SUDO_TEMP_FILE"
    log "Security: Temporary sudo privileges revoked."
  fi
}
trap cleanup_sudo EXIT INT TERM

critical_failure_handler() {
  local failed_reason="$1"
  trap - ERR
  echo -e "\n\033[0;31m[CRITICAL FAILURE] $failed_reason\033[0m\n"
  exit 1
}
trap 'critical_failure_handler "Script Error at Line $LINENO"' ERR

AUR_HELPER="paru"

# ==============================================================================
# STEP 1: Pre-requisites Installation
# ==============================================================================
section "Shorin DMS" "Installing Pre-requisites"

PRE_PKGS="quickshell-git vulkan-headers xdg-desktop-portal-gnome"

log "Generating verify list for pre-requisites..."
echo "$PRE_PKGS" | tr ' ' '\n' >>"$VERIFY_LIST"

log "Installing pre-requisites explicitly..."
if ! as_user "$AUR_HELPER" -S --noconfirm --needed $PRE_PKGS; then
  critical_failure_handler "Failed to install pre-requisites: $PRE_PKGS"
fi

# ==============================================================================
# STEP 2: Core Meta Environment
# ==============================================================================
section "Shorin DMS" "Installing Core Environment"

# DMS source (dotfiles, shorindms, README) is bundled in the same repository
# as the installer; $PARENT_DIR is the repo root.
DMS_ROOT="$PARENT_DIR"
CORE_DEPS=(
  git bash dms-shell-niri xwayland-satellite unzip
  libnotify power-profiles-daemon wl-clipboard cliphist cava
  dgop dsearch-bin qt5-multimedia cups-pk-helper kimageformats
)

log "Adding core dependencies to verification list..."
printf "%s\n" "${CORE_DEPS[@]}" >>"$VERIFY_LIST"

log "Installing core package dependencies..."
if ! as_user "$AUR_HELPER" -S --noconfirm --needed "${CORE_DEPS[@]}"; then
  critical_failure_handler "Failed to install Shorin DMS Niri core dependencies"
fi

if [[ ! -d "$DMS_ROOT/dotfiles" || ! -f "$DMS_ROOT/shorindms" ]]; then
  critical_failure_handler "DMS source not found at $DMS_ROOT (dotfiles/shorindms missing)"
fi

log "Installing Shorin DMS Niri from bundled source..."
# Replace the managed template; user config remains protected because
# shorindms copies from /usr/share later.
rm -rf /usr/share/arch-niri-dms
install -dm755 /usr/share/arch-niri-dms /usr/share/doc/arch-niri-dms
cp -a "$DMS_ROOT/dotfiles/." /usr/share/arch-niri-dms/
install -Dm755 "$DMS_ROOT/shorindms" /usr/bin/shorindms
if [[ -f "$DMS_ROOT/README-DMS.txt" ]]; then
  install -Dm644 "$DMS_ROOT/README-DMS.txt" /usr/share/doc/arch-niri-dms/README-DMS.txt
fi

# ==============================================================================
# STEP 3: Initialize Dotfiles & Environment
# ==============================================================================
section "Shorin DMS" "Initializing User Environment"

log "Initializing User Dotfiles and Environment..."
exe as_user shorindms init

# ==============================================================================
# STEP 4: Static Resources
# ==============================================================================
section "Shorin DMS" "Wallpapers & Tutorials"

log "Downloading wallpapers..."
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"
WALLPAPERS_FILE="$PARENT_DIR/wallpapers.txt"
WALLPAPER_URLS=()

if [[ -f "$WALLPAPERS_FILE" ]]; then
  while IFS= read -r url; do
    # 跳过空行和 # 开头的注释行
    [[ -z "$url" || "$url" == \#* ]] && continue
    WALLPAPER_URLS+=("$url")
  done <"$WALLPAPERS_FILE"
else
  warn "$WALLPAPERS_FILE not found, skipping wallpaper download"
fi

as_user mkdir -p "$WALLPAPER_DIR"
for url in "${WALLPAPER_URLS[@]}"; do
  filename="${url##*/}"
  log "  -> $filename"
  curl -fsSL --retry 3 -o "$WALLPAPER_DIR/$filename" "$url" || {
    warn "Failed to download $url"
  }
done
chown -R "$TARGET_USER:" "$WALLPAPER_DIR"

# ==============================================================================
# Finalization & Auto-Login
# ==============================================================================
section "Final" "Auto-Login & Cleanup"

log "Cleaning up legacy TTY autologin configs..."

if [[ "$SKIP_DM" == false ]]; then
  setup_ly
fi

success "Shorin DMS Niri Installation Complete!"
