#!/bin/bash

set -euo pipefail

# ==============================================================================
# 03-driver.sh 的内部组件：使用 chwd 安装 GPU 驱动
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
GITHUB_GIT_WRAPPER="${SHORIN_GITHUB_GIT_WRAPPER:-$PARENT_DIR/github-wrapper/git-github-wrapper.sh}"
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
trap cleanup_chwd EXIT
trap 'exit 130' INT TERM

log "Install the official build and runtime dependencies for chwd."
exe pacman -S --noconfirm --needed clang pciutils lua libusb

log "Clone the chwd source through the unified GitHub route."
exe "$GITHUB_GIT_WRAPPER" clone --depth 1 "$CHWD_REPO_URL" "$CHWD_SOURCE_DIR/source"

# 加入镜像优化 cargo 下载
CHWD_CARGO_HOME="$CHWD_SOURCE_DIR/cargo-home"
CHWD_MANIFEST="$CHWD_SOURCE_DIR/source/Cargo.toml"
install -d -m 0755 "$CHWD_CARGO_HOME"

log "Fetch the locked Rust dependencies through the RSProxy sparse mirror."
cat >"$CHWD_CARGO_HOME/config.toml" <<'EOF'
[source.crates-io]
replace-with = "rsproxy-sparse"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[net]
git-fetch-with-cli = true
retry = 3
EOF

if ! exe env CARGO_HOME="$CHWD_CARGO_HOME" \
    cargo fetch --locked --manifest-path "$CHWD_MANIFEST"; then
    warn "RSProxy failed. Retry the locked dependency download from the official crates.io sparse index."
    cat >"$CHWD_CARGO_HOME/config.toml" <<'EOF'
[registries.crates-io]
protocol = "sparse"

[net]
git-fetch-with-cli = true
retry = 3
EOF
    if ! exe env CARGO_HOME="$CHWD_CARGO_HOME" \
        cargo fetch --locked --manifest-path "$CHWD_MANIFEST"; then
        error "The locked Rust dependencies for chwd could not be downloaded."
        exit 1
    fi
fi

log "Build chwd offline from the downloaded dependencies."
exe env CARGO_HOME="$CHWD_CARGO_HOME" \
    cargo build --locked --offline --release --manifest-path "$CHWD_MANIFEST"

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
