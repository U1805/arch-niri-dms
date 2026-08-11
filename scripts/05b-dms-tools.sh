#!/usr/bin/env bash

# ==============================================================================
# 05b-dms-tools.sh - 安装桌面辅助程序和系统集成
# ==============================================================================

OFFICIAL_FILE_MANAGER_SOFTWARE=(
  imv mpv
  thunar tumbler thunar-archive-plugin thunar-volman
  ffmpegthumbnailer icoextract python-pillow poppler-glib
  webp-pixbuf-loader libgsf kimageformats
  gvfs-smb
  file-roller
  gnome-keyring xdg-desktop-portal-gtk
  gst-plugins-base gst-plugins-good gst-libav
)

OFFICIAL_COMPANION_SOFTWARE=(
  xorg-xhost
  kitty bat fuzzel fzf
  eza zoxide starship fish imagemagick
  adw-gtk-theme nwg-look breeze-cursors
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"
check_root

section "Shorin DMS" "Install desktop companion tools"

log "Install companion packages from the official repositories."
if ! pacman -S --needed --noconfirm \
  "${OFFICIAL_FILE_MANAGER_SOFTWARE[@]}" \
  "${OFFICIAL_COMPANION_SOFTWARE[@]}"; then
  error "Desktop companion installation failed."
  exit 1
fi

success "The DMS desktop companion tools are installed."
