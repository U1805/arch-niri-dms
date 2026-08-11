#!/bin/bash

set -euo pipefail

# ==============================================================================
# 03-driver.sh 的内部组件：使用 chwd 安装 GPU 驱动
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh is not available."
    exit 1
fi

check_root

section "Required" "Install GPU drivers"

CHWD_REPO_URL="https://github.com/SHORiN-KiWATA/chwd.git"
CHWD_DATA_DIR="/var/lib/chwd"

if [[ -e "$CHWD_DATA_DIR" ]]; then
    error "$CHWD_DATA_DIR exists. Remove the current chwd package and data before you run this module."
    exit 1
fi

CHWD_SOURCE_DIR="$(mktemp -d /tmp/shorin-chwd.XXXXXX)"

cleanup_chwd() {
    # chwd 仅在安装期间使用。pacman 继续管理和更新 chwd 安装的驱动。
    rm -rf -- "$CHWD_SOURCE_DIR"
    rm -rf -- "$CHWD_DATA_DIR"
}
trap cleanup_chwd EXIT INT TERM

log "Install the official build and runtime dependencies for chwd."
exe pacman -S --noconfirm --needed clang pciutils lua libusb

log "Clone the chwd source through the GitHub proxy."
exe git clone --depth 1 "$CHWD_REPO_URL" "$CHWD_SOURCE_DIR/source"

log "Build chwd."
exe env CARGO_HOME="$CHWD_SOURCE_DIR/cargo-home" \
    cargo build --locked --release --manifest-path "$CHWD_SOURCE_DIR/source/Cargo.toml"

log "Prepare temporary chwd hardware profiles."
install -d "$CHWD_DATA_DIR/db" "$CHWD_DATA_DIR/ids" "$CHWD_DATA_DIR/local/pci" \
    "$CHWD_DATA_DIR/local/usb" "$CHWD_DATA_DIR/scripts"
cp -a "$CHWD_SOURCE_DIR/source/profiles/pci" "$CHWD_DATA_DIR/db/"
cp -a "$CHWD_SOURCE_DIR/source/profiles/usb" "$CHWD_DATA_DIR/db/"
install -m 0644 "$CHWD_SOURCE_DIR/source/ids/"*.ids "$CHWD_DATA_DIR/ids/"
install -m 0755 "$CHWD_SOURCE_DIR/source/scripts/chwd" "$CHWD_DATA_DIR/scripts/chwd"

log "Detect hardware and install drivers for it."
if "$CHWD_SOURCE_DIR/source/target/release/chwd" -a; then
    success "The hardware drivers are installed. Remove the temporary chwd files."
else
    error "chwd failed. Check the pacman log before you install the desktop."
    exit 1
fi

log "The GPU component of module 03 is complete."
